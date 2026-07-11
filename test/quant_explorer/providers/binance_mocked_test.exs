defmodule Quant.Explorer.Providers.BinanceTestMocked do
  use ExUnit.Case
  import Quant.Explorer.TestHelper
  alias Explorer.DataFrame
  alias Quant.Explorer.Providers.Binance

  @moduletag :mocked

  describe "Binance Provider - Mocked Tests" do
    test "history/2 returns historical klines data for single symbol" do
      binance_klines_response = """
      [
        [
          1640908800000,
          "47000.00",
          "47500.00",
          "46500.00",
          "47200.00",
          "1234.56",
          1640995199999,
          "58000000.00",
          8500,
          "600.00",
          "28000000.00",
          "0"
        ],
        [
          1640995200000,
          "47200.00",
          "47800.00",
          "46800.00",
          "47650.00",
          "2345.67",
          1641081599999,
          "110000000.00",
          12000,
          "1100.00",
          "52000000.00",
          "0"
        ]
      ]
      """

      with_http_mock([
        {"api.binance.com", binance_klines_response}
      ]) do
        assert {:ok, df} = Binance.history("BTCUSDT")

        # Should get exactly 2 rows from mock
        assert DataFrame.n_rows(df) == 2
        # Column names may be in different order - just check required ones exist
        column_names = DataFrame.names(df)
        required_columns = ["symbol", "timestamp", "open", "high", "low", "close", "volume"]
        assert Enum.all?(required_columns, &(&1 in column_names))

        # Verify data integrity
        rows = DataFrame.to_rows(df, atom_keys: true)
        assert length(rows) == 2
        assert Enum.all?(rows, &(&1.symbol == "BTCUSDT"))
      end
    end

    test "quote/1 returns 24hr ticker statistics for single symbol" do
      # Binance returns an array even for single symbol
      binance_ticker_response = """
      [
        {
          "symbol": "BTCUSDT",
          "priceChange": "1200.00",
          "priceChangePercent": "2.60",
          "weightedAvgPrice": "47000.50",
          "prevClosePrice": "46000.00",
          "lastPrice": "47200.00",
          "lastQty": "0.1",
          "bidPrice": "47195.00",
          "askPrice": "47205.00",
          "openPrice": "46000.00",
          "highPrice": "47800.00",
          "lowPrice": "45500.00",
          "volume": "15432.50000000",
          "quoteVolume": "725000000.00",
          "openTime": 1640908800000,
          "closeTime": 1640995199999,
          "firstId": 1000000,
          "lastId": 2000000,
          "count": 1000000
        }
      ]
      """

      with_http_mock([
        {"api.binance.com", binance_ticker_response}
      ]) do
        assert {:ok, df} = Binance.quote("BTCUSDT")

        # Should get exactly 1 row from mock
        assert DataFrame.n_rows(df) == 1
        assert "price" in DataFrame.names(df)
        assert "symbol" in DataFrame.names(df)

        # Verify data
        row = DataFrame.to_rows(df, atom_keys: true) |> hd()
        assert row.symbol == "BTCUSDT"
        assert row.price == 47_200.00
      end
    end

    test "search/1 filters symbols by query string" do
      binance_exchange_info_response = """
      {
        "timezone": "UTC",
        "serverTime": 1640995200000,
        "symbols": [
          {
            "symbol": "BTCUSDT",
            "status": "TRADING",
            "baseAsset": "BTC",
            "quoteAsset": "USDT",
            "baseAssetPrecision": 8,
            "quotePrecision": 8
          }
        ]
      }
      """

      with_http_mock([
        {"api.binance.com", binance_exchange_info_response}
      ]) do
        assert {:ok, df} = Binance.search("BTC")

        # Should get exactly 1 row from mock
        assert DataFrame.n_rows(df) == 1
        assert "symbol" in DataFrame.names(df)

        # Verify filtering worked
        row = DataFrame.to_rows(df, atom_keys: true) |> hd()
        assert row.symbol == "BTCUSDT"
      end
    end

    test "error handling with HTTP errors" do
      with_http_mock([
        {"api.binance.com", %{status: 404, body: "Not Found"}}
      ]) do
        assert {:error, {:http_error, 404}} = Binance.history("BTCUSDT")
      end
    end

    test "error handling with malformed JSON" do
      with_http_mock([
        {"api.binance.com", "invalid json response"}
      ]) do
        assert {:error, {:json_decode_error, _}} = Binance.history("BTCUSDT")
      end
    end
  end
end
