defmodule Quant.Explorer.Providers.YahooFinanceTest do
  use ExUnit.Case, async: false
  import Quant.Explorer.TestHelper

  alias Quant.Explorer.Providers.YahooFinance

  # These tests make real HTTP requests - tagged as integration tests
  @moduletag :integration

  setup_all do
    # Use real HTTP client for integration tests
    Application.put_env(:quant, :http_client, Quant.Explorer.HttpClient)
    :ok
  end

  alias Explorer.DataFrame

  doctest YahooFinance

  # Mock responses for testing
  @mock_chart_response """
  {
    "chart": {
      "result": [
        {
          "meta": {
            "currency": "USD",
            "symbol": "AAPL"
          },
          "timestamp": [1640995200, 1641081600, 1641168000],
          "indicators": {
            "quote": [
              {
                "open": [177.830002, 178.085007, 179.610001],
                "high": [182.880005, 179.229996, 182.130005],
                "low": [177.710007, 177.260002, 179.119995],
                "close": [182.009995, 179.699997, 182.009995],
                "volume": [59773000, 76138300, 64062300]
              }
            ],
            "adjclose": [
              {
                "adjclose": [182.009995, 179.699997, 182.009995]
              }
            ]
          }
        }
      ]
    }
  }
  """

  @mock_quote_response """
  {
    "quoteResponse": {
      "result": [
        {
          "symbol": "AAPL",
          "regularMarketPrice": 182.52,
          "regularMarketChange": 1.48,
          "regularMarketChangePercent": 0.818,
          "regularMarketVolume": 55632000,
          "currency": "USD",
          "marketState": "REGULAR"
        }
      ]
    }
  }
  """

  @mock_search_response """
  {
    "quotes": [
      {
        "symbol": "AAPL",
        "longname": "Apple Inc.",
        "shortname": "Apple Inc.",
        "quoteType": "EQUITY",
        "exchDisp": "NASDAQ",
        "sector": "Technology",
        "industry": "Consumer Electronics"
      }
    ]
  }
  """

  setup do
    setup_rate_limiter()
    :ok
  end

  describe "history/2" do
    test "fetches historical data for a single symbol" do
      with_http_mock_paths path: "/v8/finance/chart/AAPL",
                           method: "GET",
                           response: @mock_chart_response do
        assert {:ok, df} = YahooFinance.history("AAPL", period: "1y")
        assert DataFrame.n_rows(df) == 3

        assert DataFrame.names(df) == [
                 "symbol",
                 "timestamp",
                 "open",
                 "high",
                 "low",
                 "close",
                 "volume",
                 "adj_close"
               ]

        # Check data types
        first_row = DataFrame.to_rows(df) |> List.first()
        assert first_row["symbol"] == "AAPL"
        assert is_float(first_row["open"])
        assert is_integer(first_row["volume"])
        assert match?(%DateTime{}, first_row["timestamp"])
      end
    end

    test "handles multiple symbols concurrently" do
      with_http_mock_paths [
        # Mock both AAPL and MSFT responses
        %{path: "/v8/finance/chart/AAPL", method: "GET", response: @mock_chart_response},
        %{path: "/v8/finance/chart/MSFT", method: "GET", response: @mock_chart_response}
      ] do
        assert {:ok, df} = YahooFinance.history(["AAPL", "MSFT"], period: "1mo")
        # 3 rows per symbol
        assert DataFrame.n_rows(df) == 6

        symbols = df |> DataFrame.pull("symbol") |> Enum.uniq() |> Enum.sort()
        assert symbols == ["AAPL", "MSFT"]
      end
    end

    test "validates period parameter" do
      assert {:error, :invalid_period} = YahooFinance.history("AAPL", period: "invalid")
    end

    test "validates interval parameter" do
      assert {:error, :invalid_interval} = YahooFinance.history("AAPL", interval: "invalid")
    end

    test "handles 404 symbol not found" do
      with_http_mock_paths path: "/v8/finance/chart/INVALID",
                           method: "GET",
                           response: %{status: 404} do
        assert {:error, :symbol_not_found} = YahooFinance.history("INVALID")
      end
    end

    test "handles custom date ranges" do
      with_http_mock_paths path: "/v8/finance/chart/AAPL",
                           method: "GET",
                           response: @mock_chart_response do
        start_date = ~D[2024-01-01]
        end_date = ~D[2024-12-31]

        assert {:ok, df} =
                 YahooFinance.history("AAPL",
                   start_date: start_date,
                   end_date: end_date,
                   interval: "1d"
                 )

        assert DataFrame.n_rows(df) > 0
      end
    end
  end

  describe "quote/1" do
    test "fetches real-time quotes for symbols" do
      with_http_mock_paths path: "/v7/finance/quote",
                           method: "GET",
                           response: @mock_quote_response do
        assert {:ok, df} = YahooFinance.quote(["AAPL"])
        assert DataFrame.n_rows(df) == 1

        assert DataFrame.names(df) == [
                 "symbol",
                 "price",
                 "change",
                 "change_percent",
                 "volume",
                 "timestamp",
                 "market_state",
                 "currency"
               ]

        first_row = DataFrame.to_rows(df) |> List.first()
        assert first_row["symbol"] == "AAPL"
        assert first_row["price"] == 182.52
        assert first_row["currency"] == "USD"
      end
    end

    test "handles single symbol as string" do
      with_http_mock_paths path: "/v7/finance/quote",
                           method: "GET",
                           response: @mock_quote_response do
        assert {:ok, df} = YahooFinance.quote("AAPL")
        assert DataFrame.n_rows(df) == 1
      end
    end
  end

  describe "search/1" do
    test "searches for symbols by query" do
      with_http_mock_paths path: "/v1/finance/search",
                           method: "GET",
                           response: @mock_search_response do
        assert {:ok, df} = YahooFinance.search("Apple")
        assert DataFrame.n_rows(df) == 1

        assert DataFrame.names(df) == [
                 "symbol",
                 "name",
                 "type",
                 "exchange",
                 "sector",
                 "industry"
               ]

        first_row = DataFrame.to_rows(df) |> List.first()
        assert first_row["symbol"] == "AAPL"
        assert first_row["name"] == "Apple Inc."
      end
    end
  end

  describe "info/1" do
    test "fetches company information" do
      mock_info_response = """
      {
        "quoteSummary": {
          "result": [
            {
              "assetProfile": {
                "longName": "Apple Inc.",
                "sector": "Technology",
                "industry": "Consumer Electronics",
                "website": "https://www.apple.com",
                "fullTimeEmployees": 164000,
                "longBusinessSummary": "Apple Inc. designs, manufactures, and markets smartphones..."
              },
              "financialData": {
                "financialCurrency": "USD"
              },
              "defaultKeyStatistics": {
                "marketCap": {"raw": 3000000000000}
              }
            }
          ]
        }
      }
      """

      with_http_mock_paths path: "/v10/finance/quoteSummary/AAPL",
                           method: "GET",
                           response: mock_info_response do
        assert {:ok, info} = YahooFinance.info("AAPL")
        assert info.symbol == "AAPL"
        assert info.name == "Apple Inc."
        assert info.sector == "Technology"
        assert info.market_cap == 3_000_000_000_000
      end
    end
  end

  describe "history_stream/2" do
    test "creates stream for historical data" do
      with_http_mock_paths path: "/v8/finance/chart/AAPL",
                           method: "GET",
                           response: @mock_chart_response do
        stream = YahooFinance.history_stream("AAPL", period: "1y")
        dfs = Enum.to_list(stream)

        assert length(dfs) == 1
        assert match?({:ok, %DataFrame{}}, List.first(dfs))
      end
    end

    test "streams max period data" do
      with_http_mock_paths path: "/v8/finance/chart/AAPL",
                           method: "GET",
                           response: @mock_chart_response do
        stream = YahooFinance.history_stream("AAPL", period: "max", interval: "1d")
        dfs = Enum.to_list(stream)

        assert dfs != []
      end
    end
  end

  describe "options/2" do
    test "fetches options chain data" do
      mock_options_response = """
      {
        "optionChain": {
          "result": [
            {
              "underlyingSymbol": "AAPL",
              "expirationDates": [1705017600],
              "strikes": [170, 175, 180, 185],
              "options": [
                {
                  "calls": [
                    {
                      "strike": 175,
                      "lastPrice": 8.50,
                      "bid": 8.25,
                      "ask": 8.75,
                      "volume": 1250,
                      "openInterest": 5420,
                      "impliedVolatility": 0.25
                    }
                  ],
                  "puts": [
                    {
                      "strike": 175,
                      "lastPrice": 1.20,
                      "bid": 1.15,
                      "ask": 1.25,
                      "volume": 850,
                      "openInterest": 3200,
                      "impliedVolatility": 0.22
                    }
                  ]
                }
              ]
            }
          ]
        }
      }
      """

      with_http_mock_paths path: "/v7/finance/options/AAPL",
                           method: "GET",
                           response: mock_options_response do
        assert {:ok, options} = YahooFinance.options("AAPL")
        assert options.symbol == "AAPL"
        assert length(options.calls) == 1
        assert length(options.puts) == 1

        call = List.first(options.calls)
        assert call.strike == 175.0
        assert call.last_price == 8.5
      end
    end
  end

  describe "rate limiting" do
    test "respects rate limits" do
      # This would require more complex setup to test actual rate limiting
      # For now, just verify the function calls don't crash
      assert :ok == setup_rate_limiter()
    end
  end

  describe "error handling" do
    test "handles JSON parse errors" do
      with_http_mock_paths path: "/v8/finance/chart/AAPL",
                           method: "GET",
                           response: "invalid json" do
        assert {:error, {:parse_error, _}} = YahooFinance.history("AAPL")
      end
    end

    test "handles API errors" do
      error_response = """
      {
        "chart": {
          "error": {
            "code": "Not Found",
            "description": "No data found, symbol may be delisted"
          }
        }
      }
      """

      with_http_mock_paths path: "/v8/finance/chart/INVALID",
                           method: "GET",
                           response: error_response do
        assert {:error, {:provider_error, "No data found, symbol may be delisted"}} =
                 YahooFinance.history("INVALID")
      end
    end
  end

  # Performance and integration tests (require real API access)
end
