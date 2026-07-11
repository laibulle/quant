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

  @spec clear() :: :ok
  def clear, do: GenServer.call(__MODULE__, :clear)

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
       limit: Keyword.get(opts, :limit, 10_000)
     }}
  end

  @impl true
  def handle_call({:get, key}, _from, state) do
    now = System.monotonic_time(:millisecond)

    case :ets.lookup(state.table, key) do
      [{^key, expires_at, value}] when expires_at > now ->
        {:reply, {:ok, value}, state}

      [{^key, _expires_at, _value}] ->
        :ets.delete(state.table, key)
        {:reply, :miss, state}

      [] ->
        {:reply, :miss, state}
    end
  end

  @impl true
  def handle_call({:put, key, value}, _from, state) do
    if :ets.info(state.table, :size) >= state.limit, do: evict_one(state)
    expires_at = System.monotonic_time(:millisecond) + state.ttl
    :ets.insert(state.table, {key, expires_at, value})
    {:reply, :ok, state}
  end

  @impl true
  def handle_call(:clear, _from, state) do
    :ets.delete_all_objects(state.table)
    {:reply, :ok, state}
  end

  defp evict_one(state) do
    case :ets.first(state.table) do
      :"$end_of_table" -> :ok
      key -> :ets.delete(state.table, key)
    end
  end
end
