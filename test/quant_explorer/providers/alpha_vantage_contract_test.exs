defmodule Quant.Explorer.Providers.AlphaVantageContractTest do
  use ExUnit.Case, async: false

  import Quant.Explorer.TestHelper

  alias Explorer.DataFrame
  alias Quant.Explorer.{HttpMock, TestHelper}
  alias Quant.Explorer.Providers.AlphaVantage

  setup do
    :ok = TestHelper.setup_rate_limiter()
    HttpMock.reset()
    :ok
  end

  test "parses intraday history timestamps instead of replacing them with now" do
    response =
      """
      {"Time Series (5min)":{"2024-01-02 14:35:00":{"1. open":"10.0","2. high":"11.0","3. low":"9.0","4. close":"10.5","5. volume":"100"}}}
      """

    with_http_mock([{"www.alphavantage.co", response}]) do
      assert {:ok, dataframe} = AlphaVantage.history("IBM", interval: "5min", api_key: "test_key")

      [row] = DataFrame.to_rows(dataframe)
      assert DateTime.compare(row["timestamp"], ~U[2024-01-02 14:35:00Z]) == :eq
    end
  end

  test "uses the latest trading date and rejects partial quote numbers" do
    response =
      """
      {"Global Quote":{"05. price":"10.5invalid","06. volume":"100invalid","07. latest trading day":"2024-01-02","09. change":"1.25","10. change percent":"2.5%"}}
      """

    with_http_mock([{"www.alphavantage.co", response}]) do
      assert {:ok, dataframe} = AlphaVantage.quote("IBM", api_key: "test_key")

      [row] = DataFrame.to_rows(dataframe)
      assert DateTime.compare(row["timestamp"], ~U[2024-01-02 00:00:00Z]) == :eq
      assert row["price"] == nil
      assert row["volume"] == nil
      assert row["change"] == 1.25
      assert row["change_percent"] == 2.5
    end
  end
end
