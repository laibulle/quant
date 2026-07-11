defmodule Quant.Explorer.ApiContractTest do
  use ExUnit.Case, async: false

  import Quant.Explorer.TestHelper

  alias Explorer.DataFrame
  alias Quant.Explorer.{Cache, HttpMock, TestHelper}

  setup do
    :ok = TestHelper.setup_rate_limiter()
    :ok = Cache.clear()
    :ok = Cache.reset_stats()
    HttpMock.reset()

    on_exit(fn ->
      :ok = Cache.clear()
      :ok = Cache.reset_stats()
    end)

    :ok
  end

  test "fetch aliases standardized history and caches identical requests" do
    with_http_mock([{"query1.finance.yahoo.com", history_response()}]) do
      assert {:ok, first} = Quant.Explorer.history("AAPL", provider: :yahoo_finance, period: "1d")
      assert {:ok, second} = Quant.Explorer.fetch("AAPL", provider: :yahoo_finance, period: "1d")

      assert DataFrame.names(first) == DataFrame.names(second)
      assert length(HttpMock.get_requests()) == 1
      assert %{hits: 1, misses: 1, writes: 1} = Quant.Explorer.cache_stats()
    end
  end

  test "history can bypass the cache explicitly" do
    with_http_mock([{"query1.finance.yahoo.com", history_response()}]) do
      assert {:ok, _} =
               Quant.Explorer.history("AAPL",
                 provider: :yahoo_finance,
                 period: "1d",
                 cache: false
               )

      assert {:ok, _} =
               Quant.Explorer.history("AAPL",
                 provider: :yahoo_finance,
                 period: "1d",
                 cache: false
               )

      assert length(HttpMock.get_requests()) == 2
      assert %{hits: 0, misses: 0, writes: 0} = Quant.Explorer.cache_stats()
    end
  end

  test "exposes library metadata and rejects unknown providers consistently" do
    assert %{version: version, standardized_api: true, supported_intervals: intervals} =
             Quant.Explorer.config()

    assert is_binary(version)
    assert "1d" in intervals

    assert %{yahoo_finance: %{timezone: "America/New_York", standardized: true}} =
             Quant.Explorer.providers()

    for operation <- [&Quant.Explorer.history/2, &Quant.Explorer.quote/2, &Quant.Explorer.info/2] do
      assert {:error, {:unknown_provider, :unknown}} = operation.("AAPL", provider: :unknown)
    end

    assert {:error, {:unknown_provider, :unknown}} =
             Quant.Explorer.search("Apple", provider: :unknown)
  end

  defp history_response do
    """
    {"chart":{"result":[{"timestamp":[1704067200],"indicators":{"quote":[{"open":[10.0],"high":[11.0],"low":[9.0],"close":[10.5],"volume":[100]}],"adjclose":[{"adjclose":[10.5]}]}}]}}
    """
  end
end
