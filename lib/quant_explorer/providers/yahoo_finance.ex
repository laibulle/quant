defmodule Quant.Explorer.Providers.YahooFinance do
  @moduledoc """
  Yahoo Finance provider implementation.

  This module provides access to Yahoo Finance data including:
  - Historical data (OHLCV) with multiple periods and intervals
  - Real-time quotes with streaming support
  - Company information and fundamentals
  - Symbol search functionality
  - Options data (advanced)

  All data is returned as Explorer DataFrames for immediate analysis.

  ## Yahoo Finance API Endpoints

  - Historical: `https://query1.finance.yahoo.com/v8/finance/chart/{symbol}`
  - Quote: `https://query1.finance.yahoo.com/v7/finance/quote?symbols={symbols}`
  - Search: `https://query1.finance.yahoo.com/v1/finance/search?q={query}`
  - Options: `https://query1.finance.yahoo.com/v7/finance/options/{symbol}`

  ## Rate Limiting

  Yahoo Finance has burst-tolerant rate limiting (around 100-200 requests/minute).
  Uses the advanced rate limiter with burst allowance configuration.

  ## Examples

      # Historical data
      {:ok, df} = YahooFinance.history("AAPL", period: "1y", interval: "1d")

      # Multiple symbols
      {:ok, df} = YahooFinance.history(["AAPL", "MSFT"], period: "1mo")

      # Real-time quotes
      {:ok, df} = YahooFinance.quote(["AAPL", "MSFT", "GOOGL"])

      # Company information
      {:ok, info} = YahooFinance.info("AAPL")

      # Symbol search
      {:ok, df} = YahooFinance.search("Apple")

      # Streaming historical data (large datasets)
      stream = YahooFinance.history_stream("AAPL", period: "max", interval: "1d")
      df = stream |> Enum.to_list() |> Explorer.DataFrame.concat_rows()
  """

  @behaviour Quant.Explorer.Providers.Behaviour

  alias Explorer.DataFrame
  alias Quant.Explorer.{HttpClientConfig, RateLimiter}
  require Logger

  # Yahoo Finance API configuration
  @base_url "https://query1.finance.yahoo.com"
  @user_agent "Quant.Explorer/#{Mix.Project.config()[:version]} (+https://github.com/the-nerd-company/quant)"

  # Default request options
  @default_timeout 10_000

  # Valid periods for historical data
  @valid_periods ~w(1d 5d 1mo 3mo 6mo 1y 2y 5y 10y ytd max)

  # Valid intervals for historical data
  @valid_intervals ~w(1m 2m 5m 15m 30m 60m 90m 1h 1d 5d 1wk 1mo 3mo)

  @type symbol :: String.t()
  @type symbols :: [symbol()] | symbol()
  @type period :: String.t()
  @type interval :: String.t()
  @type options :: keyword()

  # Behaviour Implementation

  @impl true
  def history(symbol_or_symbols, opts \\ [])

  def history(symbols, opts) when is_list(symbols) do
    # For multiple symbols, make concurrent requests and combine
    task_results =
      symbols
      |> Task.async_stream(
        &fetch_single_symbol_history(&1, opts),
        max_concurrency: 10,
        timeout: @default_timeout * 2
      )
      |> Enum.to_list()

    combine_multiple_symbol_results(task_results)
  end

  def history(symbol, opts) when is_binary(symbol) do
    # Rate limiting check
    case RateLimiter.check_and_consume(:yahoo_finance, :history) do
      :ok ->
        fetch_historical_data(symbol, opts)

      {:error, :rate_limited} ->
        {:error, :rate_limited}
    end
  end

  defp fetch_single_symbol_history(symbol, opts) do
    case history(symbol, opts) do
      {:ok, df} -> {symbol, df}
      {:error, reason} -> {symbol, {:error, reason}}
    end
  end

  defp combine_multiple_symbol_results(task_results) do
    task_results
    |> Enum.reduce_while({:ok, []}, fn
      {:ok, {_symbol, {:error, reason}}}, _acc ->
        {:halt, {:error, reason}}

      {:ok, {_symbol, df}}, {:ok, dfs} ->
        {:cont, {:ok, [df | dfs]}}

      {:error, reason}, _acc ->
        {:halt, {:error, reason}}
    end)
    |> case do
      {:ok, [_ | _] = dfs} ->
        combined_df = DataFrame.concat_rows(Enum.reverse(dfs))
        {:ok, combined_df}

      {:ok, []} ->
        {:error, :no_data}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl true
  def quote(symbol_or_symbols, _opts \\ [])
      when is_binary(symbol_or_symbols) or is_list(symbol_or_symbols) do
    symbols = List.wrap(symbol_or_symbols)

    case RateLimiter.check_and_consume(:yahoo_finance, :quote) do
      :ok ->
        fetch_quote_data(symbols)

      {:error, :rate_limited} ->
        {:error, :rate_limited}
    end
  end

  @impl true
  def info(symbol, _opts \\ []) when is_binary(symbol) do
    case RateLimiter.check_and_consume(:yahoo_finance, :info) do
      :ok ->
        fetch_company_info(symbol)

      {:error, :rate_limited} ->
        {:error, :rate_limited}
    end
  end

  @impl true
  def search(query, _opts \\ []) when is_binary(query) do
    case RateLimiter.check_and_consume(:yahoo_finance, :search) do
      :ok ->
        fetch_search_results(query)

      {:error, :rate_limited} ->
        {:error, :rate_limited}
    end
  end

  # Streaming Support

  @doc """
  Returns a stream of historical data for large datasets.

  Useful for fetching max period data or when working with multiple intervals.
  Each chunk is a DataFrame that can be processed independently or combined.
  """
  @spec history_stream(symbol(), options()) :: Enumerable.t()
  def history_stream(symbol, opts \\ []) do
    period = Keyword.get(opts, :period, "1y")
    interval = Keyword.get(opts, :interval, "1d")

    # For max period, we might need to chunk the requests
    case period do
      "max" ->
        stream_max_history(symbol, interval)

      _ ->
        create_single_request_stream(symbol, opts)
    end
  end

  defp create_single_request_stream(symbol, opts) do
    Stream.unfold(:start, fn
      :start ->
        case history(symbol, opts) do
          {:ok, df} -> {df, :done}
          {:error, _} -> nil
        end

      :done ->
        nil
    end)
  end

  # Options Data (Advanced)

  @doc """
  Fetches options chain data for a symbol.

  Returns both calls and puts with various expiration dates.
  """
  @spec options(symbol(), options()) :: {:ok, map()} | {:error, term()}
  def options(symbol, opts \\ []) do
    case RateLimiter.check_and_consume(:yahoo_finance, :options) do
      :ok ->
        fetch_options_data(symbol, opts)

      {:error, :rate_limited} ->
        {:error, :rate_limited}
    end
  end

  # Private Implementation Functions

  defp fetch_historical_data(symbol, opts) do
    period = Keyword.get(opts, :period, "1y")
    interval = Keyword.get(opts, :interval, "1d")

    # Validate parameters
    with :ok <- validate_period(period),
         :ok <- validate_interval(interval) do
      url = build_chart_url(symbol, period, interval, opts)

      headers = [
        {"User-Agent", @user_agent},
        {"Accept", "application/json"},
        {"Referer", "https://finance.yahoo.com/"},
        {"Origin", "https://finance.yahoo.com"}
      ]

      case HttpClientConfig.get(url, %{}, headers: headers, timeout: @default_timeout) do
        {:ok, %{status: 200, body: body}} ->
          parse_chart_response(body, symbol)

        {:ok, %{status: 404}} ->
          {:error, :symbol_not_found}

        {:ok, %{status: status, body: body}} ->
          Logger.warning("Yahoo Finance API error: #{status} - #{body}")
          {:error, {:http_error, status}}

        {:error, reason} ->
          {:error, {:http_error, reason}}
      end
    else
      {:error, reason} -> {:error, reason}
    end
  end

  defp fetch_quote_data(symbols) do
    symbols_str = Enum.join(symbols, ",")
    url = "#{@base_url}/v7/finance/quote"
    headers = [{"User-Agent", @user_agent}]
    params = %{symbols: symbols_str}

    case HttpClientConfig.get(url, params, headers: headers, timeout: @default_timeout) do
      {:ok, %{status: 200, body: body}} ->
        parse_quote_response(body)

      {:ok, %{status: status, body: body}} ->
        Logger.warning("Yahoo Finance quote error: #{status} - #{body}")
        {:error, {:http_error, status}}

      {:error, reason} ->
        {:error, {:http_error, reason}}
    end
  end

  defp fetch_company_info(symbol) do
    # Use the modules endpoint for company information
    url = "#{@base_url}/v10/finance/quoteSummary/#{symbol}"
    headers = [{"User-Agent", @user_agent}]

    params = %{
      modules: "summaryProfile,financialData,defaultKeyStatistics,assetProfile"
    }

    case HttpClientConfig.get(url, params, headers: headers, timeout: @default_timeout) do
      {:ok, %{status: 200, body: body}} ->
        parse_company_info_response(body, symbol)

      {:ok, %{status: 404}} ->
        {:error, :symbol_not_found}

      {:ok, %{status: status, body: body}} ->
        Logger.warning("Yahoo Finance info error: #{status} - #{body}")
        {:error, {:http_error, status}}

      {:error, reason} ->
        {:error, {:http_error, reason}}
    end
  end

  defp fetch_search_results(query) do
    url = "#{@base_url}/v1/finance/search"
    headers = [{"User-Agent", @user_agent}]
    params = %{q: query, newsCount: 0}

    case HttpClientConfig.get(url, params, headers: headers, timeout: @default_timeout) do
      {:ok, %{status: 200, body: body}} ->
        parse_search_response(body)

      {:ok, %{status: status, body: body}} ->
        Logger.warning("Yahoo Finance search error: #{status} - #{body}")
        {:error, {:http_error, status}}

      {:error, reason} ->
        {:error, {:http_error, reason}}
    end
  end

  defp fetch_options_data(symbol, _opts) do
    url = "#{@base_url}/v7/finance/options/#{symbol}"

    headers = [
      {"User-Agent", @user_agent},
      {"Accept", "application/json"},
      {"Referer", "https://finance.yahoo.com/"},
      {"Origin", "https://finance.yahoo.com"}
    ]

    case HttpClientConfig.get(url, %{}, headers: headers, timeout: @default_timeout) do
      {:ok, %{status: 200, body: body}} ->
        parse_options_response(body, symbol)

      {:ok, %{status: 404}} ->
        {:error, :symbol_not_found}

      {:ok, %{status: status, body: body}} ->
        Logger.warning("Yahoo Finance options error: #{status} - #{body}")
        {:error, {:http_error, status}}

      {:error, reason} ->
        {:error, {:http_error, reason}}
    end
  end

  # URL Building

  defp build_chart_url(symbol, period, interval, opts) do
    base_params = %{
      includePrePost: "false",
      interval: interval,
      range: period
    }

    # Add custom date range if provided
    params =
      case {Keyword.get(opts, :start_date), Keyword.get(opts, :end_date)} do
        {%Date{} = start_date, %Date{} = end_date} ->
          start_timestamp = start_date |> DateTime.new!(~T[00:00:00]) |> DateTime.to_unix()
          end_timestamp = end_date |> DateTime.new!(~T[23:59:59]) |> DateTime.to_unix()

          base_params
          |> Map.delete(:range)
          |> Map.merge(%{period1: start_timestamp, period2: end_timestamp})

        _ ->
          base_params
      end

    query_string = URI.encode_query(params)
    "#{@base_url}/v8/finance/chart/#{symbol}?#{query_string}"
  end

  # Response Parsing Functions

  defp parse_chart_response(body, symbol) do
    case HttpClientConfig.decode_json(body) do
      {:ok, %{"chart" => %{"result" => [result | _]}}} ->
        parse_chart_result(result, symbol)

      {:ok, %{"chart" => %{"error" => error}}} ->
        {:error, {:provider_error, error["description"] || "Unknown error"}}

      {:ok, %{"chart" => %{"result" => []}}} ->
        {:error, :no_data}

      {:error, reason} ->
        {:error, {:parse_error, reason}}
    end
  end

  defp parse_chart_result(result, symbol) do
    # Extract data from the result map with better error handling
    timestamps = Map.get(result, "timestamp", [])
    indicators = Map.get(result, "indicators", %{})
    quote_data = get_in(indicators, ["quote", Access.at(0)]) || %{}

    opens = Map.get(quote_data, "open", [])
    highs = Map.get(quote_data, "high", [])
    lows = Map.get(quote_data, "low", [])
    closes = Map.get(quote_data, "close", [])
    volumes = Map.get(quote_data, "volume", [])

    # Convert timestamps to DateTimes
    # Get adjusted closes if available
    adj_closes =
      case get_in(result, ["indicators", "adjclose", Access.at(0), "adjclose"]) do
        nil -> closes
        adj -> adj
      end

    # Build DataFrame data
    data =
      timestamps
      |> Enum.with_index()
      |> Enum.map(fn {timestamp, idx} ->
        open = Enum.at(opens, idx)
        high = Enum.at(highs, idx)
        low = Enum.at(lows, idx)
        close = Enum.at(closes, idx)
        volume = Enum.at(volumes, idx)
        adj_close = Enum.at(adj_closes, idx)

        %{
          "symbol" => symbol,
          "timestamp" => parse_unix_timestamp(timestamp),
          "open" => ensure_float(open),
          "high" => ensure_float(high),
          "low" => ensure_float(low),
          "close" => ensure_float(close),
          "volume" => ensure_integer(volume),
          "adj_close" => ensure_float(adj_close)
        }
      end)
      |> Enum.filter(fn row ->
        # Filter out rows with null essential data
        not is_nil(row["close"]) and not is_nil(row["timestamp"])
      end)

    case data do
      [] -> {:error, :no_data}
      data -> {:ok, DataFrame.new(data)}
    end
  rescue
    error -> {:error, {:parse_error, error}}
  end

  defp parse_quote_response(body) do
    case HttpClientConfig.decode_json(body) do
      {:ok, %{"quoteResponse" => %{"result" => quotes}}} when is_list(quotes) ->
        data =
          Enum.map(quotes, fn quote ->
            %{
              "symbol" => Map.get(quote, "symbol"),
              "price" => ensure_float(Map.get(quote, "regularMarketPrice")),
              "change" => ensure_float(Map.get(quote, "regularMarketChange")),
              "change_percent" => ensure_float(Map.get(quote, "regularMarketChangePercent")),
              "volume" => ensure_integer(Map.get(quote, "regularMarketVolume")),
              "timestamp" => parse_unix_timestamp(Map.get(quote, "regularMarketTime")),
              "market_state" => Map.get(quote, "marketState"),
              "currency" => Map.get(quote, "currency")
            }
          end)

        {:ok, DataFrame.new(data)}

      {:ok, %{"quoteResponse" => %{"error" => error}}} ->
        {:error, {:provider_error, error["description"] || "Quote error"}}

      {:error, reason} ->
        {:error, {:parse_error, reason}}
    end
  end

  defp parse_search_response(body) do
    case HttpClientConfig.decode_json(body) do
      {:ok, %{"quotes" => quotes}} when is_list(quotes) ->
        data =
          Enum.map(quotes, fn result ->
            %{
              "symbol" => Map.get(result, "symbol"),
              "name" => Map.get(result, "longname") || Map.get(result, "shortname"),
              "type" => Map.get(result, "quoteType"),
              "exchange" => Map.get(result, "exchDisp"),
              "sector" => Map.get(result, "sector"),
              "industry" => Map.get(result, "industry")
            }
          end)

        {:ok, DataFrame.new(data)}

      {:error, reason} ->
        {:error, {:parse_error, reason}}
    end
  end

  defp parse_company_info_response(body, symbol) do
    case HttpClientConfig.decode_json(body) do
      {:ok, %{"quoteSummary" => %{"result" => [result | _]}}} ->
        info = %{
          symbol: symbol,
          name: get_in(result, ["assetProfile", "longName"]),
          sector: get_in(result, ["assetProfile", "sector"]),
          industry: get_in(result, ["assetProfile", "industry"]),
          market_cap: get_in(result, ["defaultKeyStatistics", "marketCap", "raw"]),
          employees: get_in(result, ["assetProfile", "fullTimeEmployees"]),
          website: get_in(result, ["assetProfile", "website"]),
          summary: get_in(result, ["assetProfile", "longBusinessSummary"]),
          currency: get_in(result, ["financialData", "financialCurrency"]),
          exchange: get_in(result, ["assetProfile", "exchange"])
        }

        {:ok, info}

      {:ok, %{"quoteSummary" => %{"error" => error}}} ->
        {:error, {:provider_error, error["description"] || "Info error"}}

      {:error, reason} ->
        {:error, {:parse_error, reason}}
    end
  end

  defp parse_options_response(body, symbol) do
    case HttpClientConfig.decode_json(body) do
      {:ok, %{"optionChain" => %{"result" => [result | _]}}} ->
        options_data = %{
          symbol: symbol,
          expiration_dates: Map.get(result, "expirationDates", []),
          strikes: Map.get(result, "strikes", []),
          calls:
            parse_options_contracts(get_in(result, ["options", Access.at(0), "calls"]) || []),
          puts: parse_options_contracts(get_in(result, ["options", Access.at(0), "puts"]) || [])
        }

        {:ok, options_data}

      {:error, reason} ->
        {:error, {:parse_error, reason}}
    end
  end

  defp parse_options_contracts(contracts) do
    Enum.map(contracts, fn contract ->
      %{
        strike: ensure_float(Map.get(contract, "strike")),
        last_price: ensure_float(Map.get(contract, "lastPrice")),
        bid: ensure_float(Map.get(contract, "bid")),
        ask: ensure_float(Map.get(contract, "ask")),
        volume: ensure_integer(Map.get(contract, "volume")),
        open_interest: ensure_integer(Map.get(contract, "openInterest")),
        implied_volatility: ensure_float(Map.get(contract, "impliedVolatility"))
      }
    end)
  end

  # Streaming for Max History (chunked requests)

  defp stream_max_history(symbol, interval) do
    # Yahoo Finance limits historical data, so we might need to chunk
    # For now, return single request - can enhance later for true chunking
    Stream.unfold(:start, fn
      :start ->
        case history(symbol, period: "max", interval: interval) do
          {:ok, df} -> {df, :done}
          {:error, _} -> nil
        end

      :done ->
        nil
    end)
  end

  # Validation Functions

  defp validate_period(period) when period in @valid_periods, do: :ok
  defp validate_period(_), do: {:error, :invalid_period}

  defp validate_interval(interval) when interval in @valid_intervals, do: :ok
  defp validate_interval(_), do: {:error, :invalid_interval}

  # Utility Functions

  defp ensure_float(nil), do: nil
  defp ensure_float(value) when is_number(value), do: value * 1.0

  defp ensure_float(value) when is_binary(value) do
    case Float.parse(value) do
      {float, ""} -> float
      _ -> nil
    end
  end

  defp ensure_float(_), do: nil

  defp ensure_integer(nil), do: nil
  defp ensure_integer(value) when is_integer(value), do: value
  defp ensure_integer(value) when is_float(value), do: trunc(value)

  defp ensure_integer(value) when is_binary(value) do
    case Integer.parse(value) do
      {int, ""} -> int
      _ -> ensure_float_volume(value)
    end
  end

  defp ensure_integer(_), do: nil

  defp ensure_float_volume(value) do
    case Float.parse(value) do
      {float, ""} -> trunc(float)
      _ -> nil
    end
  end

  defp parse_unix_timestamp(timestamp) when is_integer(timestamp) do
    case DateTime.from_unix(timestamp) do
      {:ok, datetime} -> datetime
      {:error, _} -> nil
    end
  end

  defp parse_unix_timestamp(_), do: nil
end
