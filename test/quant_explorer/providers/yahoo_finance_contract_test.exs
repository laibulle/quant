defmodule Quant.Explorer.Providers.YahooFinanceContractTest do
  use ExUnit.Case, async: false

  import Quant.Explorer.TestHelper

  alias Explorer.DataFrame
  alias Quant.Explorer.{HttpMock, TestHelper}
  alias Quant.Explorer.Providers.YahooFinance

  setup do
    :ok = TestHelper.setup_rate_limiter()
    HttpMock.reset()
    :ok
  end

  test "uses Yahoo's market timestamp and rejects partial quote numbers" do
    response =
      """
      {"quoteResponse":{"result":[{"symbol":"AAPL","regularMarketPrice":"10.5invalid","regularMarketChange":1.25,"regularMarketVolume":"100invalid","regularMarketTime":1704067200,"marketState":"REGULAR","currency":"USD"}]}}
      """

    with_http_mock([{"query1.finance.yahoo.com", response}]) do
      assert {:ok, dataframe} = YahooFinance.quote("AAPL")

      [row] = DataFrame.to_rows(dataframe)
      assert DateTime.compare(row["timestamp"], ~U[2024-01-01 00:00:00Z]) == :eq
      assert row["price"] == nil
      assert row["volume"] == nil
      assert row["change"] == 1.25
    end
  end

  test "returns no data cleanly for empty historical responses" do
    response = "{\"chart\":{\"result\":[{\"timestamp\":[],\"indicators\":{\"quote\":[{}]}}]}}"

    with_http_mock([{"query1.finance.yahoo.com", response}]) do
      assert {:error, :no_data} = YahooFinance.history("AAPL")
    end
  end

  test "maps company information and option chains" do
    info_response =
      """
      {"quoteSummary":{"result":[{"assetProfile":{"longName":"Apple Inc.","sector":"Technology","industry":"Consumer Electronics","fullTimeEmployees":164000,"website":"https://apple.example","longBusinessSummary":"Summary","exchange":"NASDAQ"},"financialData":{"financialCurrency":"USD"},"defaultKeyStatistics":{"marketCap":{"raw":3000000000000}}}]}}
      """

    with_http_mock([{"query1.finance.yahoo.com", info_response}]) do
      assert {:ok, info} = YahooFinance.info("AAPL")
      assert info.name == "Apple Inc."
      assert info.market_cap == 3_000_000_000_000
      assert info.currency == "USD"
    end

    options_response =
      """
      {"optionChain":{"result":[{"expirationDates":[1704067200],"strikes":[100.0],"options":[{"calls":[{"strike":100.0,"lastPrice":5.0,"bid":4.9,"ask":5.1,"volume":10,"openInterest":20,"impliedVolatility":0.25}],"puts":[{"strike":100.0,"lastPrice":4.0,"bid":3.9,"ask":4.1,"volume":8,"openInterest":15,"impliedVolatility":0.3}]}]}]}}
      """

    with_http_mock([{"query1.finance.yahoo.com", options_response}]) do
      assert {:ok, options} = YahooFinance.options("AAPL")
      assert options.symbol == "AAPL"
      assert [%{strike: 100.0, volume: 10}] = options.calls
      assert [%{strike: 100.0, open_interest: 15}] = options.puts
    end
  end
end
