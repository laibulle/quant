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

    fetcher = fn ->
      Agent.update(counter, &(&1 + 1))
      Process.sleep(20)
      {:ok, :data}
    end

    first = Task.async(fn -> Cache.fetch(:coalesced, fetcher) end)
    Process.sleep(5)
    second = Task.async(fn -> Cache.fetch(:coalesced, fetcher) end)

    assert [{:coalesced, {:ok, :data}}, {:miss, {:ok, :data}}] =
             [Task.await(first), Task.await(second)] |> Enum.sort()

    assert Agent.get(counter, & &1) == 1
    assert %{coalesced: 1, writes: 1} = Cache.stats()
  end
end
