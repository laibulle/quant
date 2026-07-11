defmodule Quant.Explorer.ProviderHttpContractTest do
  use ExUnit.Case, async: false

  alias Explorer.DataFrame
  alias Quant.Explorer.{HttpMock, TestHelper}
  alias Quant.Explorer.Providers.{AlphaVantage, Binance, CoinGecko, TwelveData, YahooFinance}

  @providers [
    {:yahoo_finance, "query1.finance.yahoo.com"},
    {:alpha_vantage, "www.alphavantage.co"},
    {:binance, "api.binance.com"},
    {:coin_gecko, "api.coingecko.com"},
    {:twelve_data, "api.twelvedata.com"}
  ]

  setup do
    TestHelper.setup_rate_limiter()
    HttpMock.reset()
    :ok
  end

  test "every provider accepts its recorded successful history response" do
    for {provider, host} <- @providers do
      HttpMock.reset()
      HttpMock.mock_response(host, success_response(provider))

      assert {:ok, dataframe} = history(provider)
      assert DataFrame.n_rows(dataframe) > 0
      assert "symbol" in DataFrame.names(dataframe)
    end
  end

  for status <- [401, 404, 429, 500] do
    test "every provider maps HTTP #{status} without parsing the error body" do
      status = unquote(status)

      for {provider, host} <- @providers do
        HttpMock.reset()
        HttpMock.mock_response(host, %{status: status, body: "upstream error"})

        assert expected_http_error(provider, status) == history(provider)
      end
    end
  end

  test "every provider rejects invalid JSON responses" do
    for {provider, host} <- @providers do
      HttpMock.reset()
      HttpMock.mock_response(host, "not valid json")

      assert {:error, _reason} = history(provider)
    end
  end

  defp history(:yahoo_finance), do: YahooFinance.history("AAPL")
  defp history(:alpha_vantage), do: AlphaVantage.history("IBM", api_key: "test_key")
  defp history(:binance), do: Binance.history("BTCUSDT")
  defp history(:coin_gecko), do: CoinGecko.history("bitcoin")
  defp history(:twelve_data), do: TwelveData.history("AAPL", api_key: "test_key")

  defp expected_http_error(:yahoo_finance, 404), do: {:error, :symbol_not_found}
  defp expected_http_error(:coin_gecko, 404), do: {:error, :symbol_not_found}
  defp expected_http_error(:coin_gecko, 429), do: {:error, :rate_limited}
  defp expected_http_error(:twelve_data, 429), do: {:error, :rate_limited}
  defp expected_http_error(_provider, status), do: {:error, {:http_error, status}}

  defp success_response(:yahoo_finance),
    do: TestHelper.load_fixture("yahoo_history_response.json")

  defp success_response(:alpha_vantage), do: TestHelper.load_fixture("alpha_vantage_daily.json")

  defp success_response(:binance) do
    "[[1704067200000,\"10.0\",\"11.0\",\"9.0\",\"10.5\",\"100.0\",1704153599999,\"1000.0\",10,\"50.0\",\"500.0\",\"0\"]]"
  end

  defp success_response(:coin_gecko) do
    "{\"prices\":[[1704067200000,42000.0]],\"market_caps\":[[1704067200000,800000000000.0]],\"total_volumes\":[[1704067200000,1000000.0]]}"
  end

  defp success_response(:twelve_data) do
    "{\"values\":[{\"datetime\":\"2024-01-01\",\"open\":\"10.0\",\"high\":\"11.0\",\"low\":\"9.0\",\"close\":\"10.5\",\"volume\":\"100\"}]}"
  end
end
