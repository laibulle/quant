defmodule Quant.Explorer.Providers.TwelveDataContractTest do
  use ExUnit.Case, async: false

  import Quant.Explorer.TestHelper

  alias Explorer.DataFrame
  alias Quant.Explorer.{HttpMock, TestHelper}
  alias Quant.Explorer.Providers.TwelveData

  setup do
    :ok = TestHelper.setup_rate_limiter()
    HttpMock.reset()
    :ok
  end

  test "parses intraday timestamps returned by the time-series endpoint" do
    response =
      """
      {"values":[{"datetime":"2024-01-02 14:30:00","open":"10.0","high":"11.0","low":"9.0","close":"10.5","volume":"100"}]}
      """

    with_http_mock([{"api.twelvedata.com", response}]) do
      assert {:ok, dataframe} = TwelveData.history("AAPL", interval: "1h", api_key: "test_key")

      [row] = DataFrame.to_rows(dataframe)
      assert DateTime.compare(row["timestamp"], ~U[2024-01-02 14:30:00Z]) == :eq
    end
  end

  test "preserves the provider quote timestamp and rejects partial numbers" do
    response =
      """
      {"timestamp":1704153600,"close":"10.5invalid","change":"1.25","percent_change":"2.5","volume":"100invalid"}
      """

    with_http_mock([{"api.twelvedata.com", response}]) do
      assert {:ok, dataframe} = TwelveData.quote("AAPL", api_key: "test_key")

      [row] = DataFrame.to_rows(dataframe)
      assert DateTime.compare(row["timestamp"], ~U[2024-01-02 00:00:00Z]) == :eq
      assert row["price"] == nil
      assert row["volume"] == nil
      assert row["change"] == 1.25
    end
  end

  test "maps company profiles without leaking provider-specific response fields" do
    response =
      """
      {"symbol":"AAPL","name":"Apple Inc.","exchange":"NASDAQ","currency":"USD","country":"United States","type":"Common Stock","sector":"Technology","industry":"Consumer Electronics","description":"Profile","ceo":"Tim Cook","employees":164000,"website":"https://apple.example"}
      """

    with_http_mock([{"api.twelvedata.com", response}]) do
      assert {:ok, profile} = TwelveData.info("AAPL", api_key: "test_key")

      assert profile["symbol"] == "AAPL"
      assert profile["name"] == "Apple Inc."
      assert profile["sector"] == "Technology"
      assert profile["website"] == "https://apple.example"
    end
  end

  test "combines forex rates and preserves source timestamps" do
    response = "{\"rate\":\"0.92\",\"timestamp\":\"2024-01-02T10:15:00Z\"}"

    with_http_mock([{"api.twelvedata.com", response}]) do
      assert {:ok, dataframe} = TwelveData.forex_rate(["USD", "GBP"], "EUR")
      assert DataFrame.n_rows(dataframe) == 2

      [first_row | _] = DataFrame.to_rows(dataframe)
      assert first_row["from_currency"] == "USD"
      assert first_row["to_currency"] == "EUR"
      assert first_row["rate"] == 0.92
      assert DateTime.compare(first_row["timestamp"], ~U[2024-01-02 10:15:00Z]) == :eq
    end
  end
end
