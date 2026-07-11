defmodule Quant.Explorer.Cache do
  @moduledoc """
  Small ETS cache for immutable provider results.

  The cache is intentionally local to a node. It is suitable for historical
  data and opt-in quote caching; it never serializes values or credentials.
  """

  use GenServer

  alias Quant.Explorer.Config

  @table :quant_explorer_cache

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @spec get(term()) :: {:ok, term()} | :miss
  def get(key), do: GenServer.call(__MODULE__, {:get, key})

  @spec put(term(), term()) :: :ok
  def put(key, value), do: GenServer.call(__MODULE__, {:put, key, value})

  @doc """
  Retrieves a value or coalesces concurrent cache misses for the same key.

  The fetcher executes once outside the cache server. Callers receive either
  `{:hit, value}`, `{:miss, value}`, or `{:coalesced, value}`.
  """
  @spec fetch(term(), (-> term())) :: {:hit | :miss | :coalesced, term()}
  def fetch(key, fetcher) when is_function(fetcher, 0),
    do: GenServer.call(__MODULE__, {:fetch, key, fetcher}, :infinity)

  @spec clear() :: :ok
  def clear, do: GenServer.call(__MODULE__, :clear)

  @doc """
  Returns local cache counters and capacity information.
  """
  @spec stats() :: map()
  def stats, do: GenServer.call(__MODULE__, :stats)

  @doc """
  Resets cache counters without removing cached values.
  """
  @spec reset_stats() :: :ok
  def reset_stats, do: GenServer.call(__MODULE__, :reset_stats)

  @doc """
  Removes cached historical responses matching provider, symbol and/or interval.

  Returns the number of entries removed. An empty filter invalidates every
  cached history response.
  """
  @spec invalidate(keyword()) :: {:ok, non_neg_integer()} | {:error, term()}
  def invalidate(filters \\ []) when is_list(filters),
    do: GenServer.call(__MODULE__, {:invalidate, filters})

  @impl true
  def init(opts) do
    table =
      case :ets.whereis(@table) do
        :undefined -> :ets.new(@table, [:set, :protected, :named_table])
        table -> table
      end

    {:ok,
     %{
       table: table,
       ttl: Keyword.get(opts, :ttl, Config.cache_ttl()),
       limit: Keyword.get(opts, :limit, 10_000),
       stats: empty_stats(),
       inflight: %{}
     }}
  end

  @impl true
  def handle_call({:get, key}, _from, state) do
    now = System.monotonic_time(:millisecond)

    case :ets.lookup(state.table, key) do
      [{^key, expires_at, value}] when expires_at > now ->
        {:reply, {:ok, value}, increment(state, :hits)}

      [{^key, _expires_at, _value}] ->
        :ets.delete(state.table, key)
        {:reply, :miss, state |> increment(:misses) |> increment(:expirations)}

      [] ->
        {:reply, :miss, increment(state, :misses)}
    end
  end

  @impl true
  def handle_call({:put, key, value}, _from, state) do
    state = evict_if_needed(state, key)
    expires_at = System.monotonic_time(:millisecond) + state.ttl
    :ets.insert(state.table, {key, expires_at, value})
    {:reply, :ok, increment(state, :writes)}
  end

  @impl true
  def handle_call({:fetch, key, fetcher}, from, state) do
    now = System.monotonic_time(:millisecond)

    case lookup_value(state, key, now) do
      {:ok, value} ->
        {:reply, {:hit, value}, increment(state, :hits)}

      :expired ->
        state = state |> increment(:misses) |> increment(:expirations)
        start_or_join_fetch(state, key, fetcher, from)

      :miss ->
        state = increment(state, :misses)
        start_or_join_fetch(state, key, fetcher, from)
    end
  end

  @impl true
  def handle_call(:clear, _from, state) do
    :ets.delete_all_objects(state.table)
    {:reply, :ok, increment(state, :clears)}
  end

  @impl true
  def handle_call(:stats, _from, state) do
    size = :ets.info(state.table, :size)
    requests = state.stats.hits + state.stats.misses

    stats =
      state.stats
      |> Map.put(:entries, size)
      |> Map.put(:limit, state.limit)
      |> Map.put(:ttl_ms, state.ttl)
      |> Map.put(:hit_rate, if(requests == 0, do: 0.0, else: state.stats.hits / requests))

    {:reply, stats, state}
  end

  @impl true
  def handle_call(:reset_stats, _from, state) do
    {:reply, :ok, %{state | stats: empty_stats()}}
  end

  @impl true
  def handle_call({:invalidate, filters}, _from, state) do
    case validate_filters(filters) do
      :ok ->
        {removed, state} = invalidate_entries(state, filters)
        {:reply, {:ok, removed}, state}

      {:error, _reason} = error ->
        {:reply, error, state}
    end
  end

  @impl true
  def handle_cast({:complete_fetch, key, result}, state) do
    {waiters, inflight} = Map.pop(state.inflight, key, [])
    state = %{state | inflight: inflight}
    state = cache_result(state, key, result)

    Enum.each(waiters, fn {from, status} -> GenServer.reply(from, {status, result}) end)
    {:noreply, state}
  end

  defp start_or_join_fetch(state, key, fetcher, from) do
    case Map.fetch(state.inflight, key) do
      {:ok, waiters} ->
        state =
          state
          |> Map.update!(:inflight, &Map.put(&1, key, [{from, :coalesced} | waiters]))
          |> increment(:coalesced)

        {:noreply, state}

      :error ->
        :ok = start_fetch_task(key, fetcher)
        {:noreply, %{state | inflight: Map.put(state.inflight, key, [{from, :miss}])}}
    end
  end

  defp start_fetch_task(key, fetcher) do
    {:ok, _pid} =
      Task.start(fn ->
        result =
          try do
            fetcher.()
          rescue
            error -> {:error, {:cache_fetch_failed, Exception.message(error)}}
          catch
            kind, reason -> {:error, {:cache_fetch_failed, {kind, reason}}}
          end

        GenServer.cast(__MODULE__, {:complete_fetch, key, result})
      end)

    :ok
  end

  defp cache_result(state, key, {:ok, _} = result) do
    state = evict_if_needed(state, key)
    expires_at = System.monotonic_time(:millisecond) + state.ttl
    :ets.insert(state.table, {key, expires_at, result})
    increment(state, :writes)
  end

  defp cache_result(state, _key, _result), do: state

  defp lookup_value(state, key, now) do
    case :ets.lookup(state.table, key) do
      [{^key, expires_at, value}] when expires_at > now ->
        {:ok, value}

      [{^key, _expires_at, _value}] ->
        :ets.delete(state.table, key)
        :expired

      [] ->
        :miss
    end
  end

  defp validate_filters(filters) do
    valid_keys = [:provider, :symbol, :interval]

    if Keyword.keyword?(filters) and Enum.all?(Keyword.keys(filters), &(&1 in valid_keys)) do
      :ok
    else
      {:error, :invalid_cache_filter}
    end
  end

  defp invalidate_entries(state, filters) do
    keys =
      state.table
      |> :ets.tab2list()
      |> Enum.map(&elem(&1, 0))
      |> Enum.filter(&history_key_matches?(&1, filters))

    Enum.each(keys, &:ets.delete(state.table, &1))
    {length(keys), update_in(state, [:stats, :invalidations], &(&1 + length(keys)))}
  end

  defp history_key_matches?({:history, provider, symbols, params}, filters) do
    provider_matches?(provider, filters[:provider]) and
      symbol_matches?(symbols, filters[:symbol]) and
      interval_matches?(params, filters[:interval])
  end

  defp history_key_matches?(_key, _filters), do: false

  defp provider_matches?(_provider, nil), do: true
  defp provider_matches?(provider, requested), do: provider == requested
  defp symbol_matches?(_symbols, nil), do: true
  defp symbol_matches?(symbols, requested), do: requested in List.wrap(symbols)
  defp interval_matches?(_params, nil), do: true
  defp interval_matches?(params, requested), do: Keyword.get(params, :interval) == requested

  defp evict_if_needed(state, key) do
    key_exists? = :ets.member(state.table, key)

    if not key_exists? and :ets.info(state.table, :size) >= state.limit do
      evict_one(state)
      increment(state, :evictions)
    else
      state
    end
  end

  defp evict_one(state) do
    case :ets.first(state.table) do
      :"$end_of_table" -> :ok
      key -> :ets.delete(state.table, key)
    end
  end

  defp increment(state, counter), do: update_in(state, [:stats, counter], &(&1 + 1))

  defp empty_stats do
    %{
      hits: 0,
      misses: 0,
      writes: 0,
      evictions: 0,
      expirations: 0,
      clears: 0,
      invalidations: 0,
      coalesced: 0
    }
  end
end
