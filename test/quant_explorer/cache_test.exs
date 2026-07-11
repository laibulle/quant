defmodule Quant.Explorer.CacheTest do
  use ExUnit.Case, async: false

  alias Quant.Explorer.Cache

  setup do
    Cache.clear()
    Cache.reset_stats()
    :ok
  end

  test "stores and retrieves a value" do
    assert :miss = Cache.get(:history)
    assert :ok = Cache.put(:history, {:ok, :data})
    assert {:ok, {:ok, :data}} = Cache.get(:history)
  end

  test "reports hits, misses, writes and cache size" do
    assert :miss = Cache.get(:missing)
    assert :ok = Cache.put(:history, {:ok, :data})
    assert {:ok, {:ok, :data}} = Cache.get(:history)

    assert %{hits: 1, misses: 1, writes: 1, entries: 1, hit_rate: hit_rate} = Cache.stats()
    assert_in_delta hit_rate, 0.5, 1.0e-12
  end

  test "records clears without resetting counters" do
    assert :ok = Cache.put(:history, {:ok, :data})
    assert :ok = Cache.clear()

    assert %{clears: 1, entries: 0, writes: 1} = Cache.stats()
  end

  test "invalidates only matching historical entries" do
    yahoo_key = {:history, :yahoo_finance, "AAPL", [interval: "1d"]}
    binance_key = {:history, :binance, "BTCUSDT", [interval: "1h"]}

    assert :ok = Cache.put(yahoo_key, {:ok, :yahoo})
    assert :ok = Cache.put(binance_key, {:ok, :binance})
    assert {:ok, 1} = Cache.invalidate(provider: :yahoo_finance, symbol: "AAPL")

    assert :miss = Cache.get(yahoo_key)
    assert {:ok, {:ok, :binance}} = Cache.get(binance_key)
    assert %{invalidations: 1} = Cache.stats()
  end

  test "coalesces concurrent misses for the same key" do
    {:ok, counter} = Agent.start_link(fn -> 0 end)
    parent = self()

    fetcher = fn ->
      Agent.update(counter, &(&1 + 1))
      send(parent, {:fetch_started, self()})

      receive do
        :complete_fetch -> :ok
      end

      {:ok, :data}
    end

    first = Task.async(fn -> Cache.fetch(:coalesced, fetcher) end)
    assert_receive {:fetch_started, fetcher_pid}
    second = Task.async(fn -> Cache.fetch(:coalesced, fetcher) end)
    wait_for_coalesced_fetch()
    send(fetcher_pid, :complete_fetch)

    assert [{:coalesced, {:ok, :data}}, {:miss, {:ok, :data}}] =
             [Task.await(first), Task.await(second)] |> Enum.sort()

    assert Agent.get(counter, & &1) == 1
    assert %{coalesced: 1, writes: 1} = Cache.stats()
  end

  defp wait_for_coalesced_fetch(attempts \\ 20)

  defp wait_for_coalesced_fetch(0), do: flunk("second cache request was not coalesced")

  defp wait_for_coalesced_fetch(attempts) do
    if Cache.stats().coalesced == 1 do
      :ok
    else
      Process.sleep(5)
      wait_for_coalesced_fetch(attempts - 1)
    end
  end

  test "invalidates explicit history ranges that overlap the requested range" do
    january =
      {:history, :binance, "BTCUSDT",
       [interval: "1d", start_date: ~D[2026-01-01], end_date: ~D[2026-01-31]]}

    march =
      {:history, :binance, "BTCUSDT",
       [interval: "1d", start_date: ~D[2026-03-01], end_date: ~D[2026-03-31]]}

    assert :ok = Cache.put(january, {:ok, :january})
    assert :ok = Cache.put(march, {:ok, :march})

    assert {:ok, 1} =
             Cache.invalidate(start_date: ~D[2026-01-15], end_date: ~D[2026-02-15])

    assert :miss = Cache.get(january)
    assert {:ok, {:ok, :march}} = Cache.get(march)
  end

  test "rejects invalid cache date filters" do
    assert {:error, :invalid_cache_filter} = Cache.invalidate(start_date: "2026-01-01")

    assert {:error, :invalid_cache_filter} =
             Cache.invalidate(start_date: ~D[2026-02-01], end_date: ~D[2026-01-01])
  end
end
