defmodule Quant.Explorer.Providers.TwelveData do
  @moduledoc """
  Twelve Data financial API provider.

  Provides access to comprehensive financial data including:
  - Stock historical data and real-time prices
  - Forex exchange rates
  - Cryptocurrency data
  - Technical indicators
  - Company fundamentals

  ## Rate Limits

  Twelve Data API has the following rate limits:
  - Basic (Free): 8 requests per minute
  - Grow: 54 requests per minute
  - Pro: 164 requests per minute
  - Enterprise: Custom limits

  ## Configuration

  API key is required for most endpoints:

  ```elixir
  config :quant,
    api_keys: %{
      twelve_data: "your_api_key_here"
    }
  ```

  ## Examples

      # Get Apple stock historical data
      {:ok, df} = TwelveData.history("AAPL", interval: "1day", outputsize: 30)

      # Get real-time stock quote
      {:ok, df} = TwelveData.quote("AAPL")

      # Search for stocks
      {:ok, df} = TwelveData.search("Apple")

      # Get company profile
      {:ok, info} = TwelveData.info("AAPL")
  """

  @behaviour Quant.Explorer.Providers.Behaviour

  require Logger
  alias Explorer.DataFrame
  alias Quant.Explorer.{Config, HttpClientConfig, RateLimiter}

  @base_url "https://api.twelvedata.com"
  @user_agent "Quant.Explorer/1.0"
  @default_timeout 15_000

  # Supported intervals
  @supported_intervals [
    "1min",
    "5min",
    "15min",
    "30min",
    "45min",
    "1h",
    "2h",
    "4h",
    "1day",
    "1week",
    "1month"
  ]

  @doc """
  Fetches historical stock data.

  ## Options

  - `:api_key` - Twelve Data API key (optional, will use config if not provided)
  - `:interval` - Time interval ("1min", "5min", "15min", "30min", "45min", "1h", "2h", "4h", "1day", "1week", "1month")
  - `:outputsize` - Number of data points (default: 30, max: 5000)
  - `:format` - Response format (default: "json")
  - `:country` - Country filter
  - `:exchange` - Exchange filter

  ## Examples

      # Get Apple daily data for last 30 days
      {:ok, df} = TwelveData.history("AAPL", interval: "1day", outputsize: 30)

      # Get intraday data
      {:ok, df} = TwelveData.history("AAPL", interval: "5min", outputsize: 100)

      # With API key
      {:ok, df} = TwelveData.history("AAPL",
        interval: "1day",
        outputsize: 30,
        api_key: "YOUR_API_KEY"
      )
  """
  @impl true
  @spec history(String.t() | [String.t()], keyword()) :: {:ok, DataFrame.t()} | {:error, term()}
  def history(symbols, opts \\ []) when is_binary(symbols) or is_list(symbols) do
    with :ok <- ensure_api_key(Keyword.get(opts, :api_key)) do
      case RateLimiter.check_and_consume(:twelve_data, :time_series) do
        :ok -> fetch_time_series_data(symbols, opts)
        {:error, :rate_limited} -> {:error, :rate_limited}
      end
    end
  end

  @doc """
  Fetches current market data for stocks.

  ## Options

  - `:api_key` - Twelve Data API key (optional, will use config if not provided)

  ## Examples

      # Single stock
      {:ok, df} = TwelveData.quote("AAPL")

      # Multiple stocks
      {:ok, df} = TwelveData.quote(["AAPL", "MSFT", "GOOGL"])

      # With API key
      {:ok, df} = TwelveData.quote("AAPL", api_key: "YOUR_API_KEY")
  """
  @impl true
  @spec quote(String.t() | [String.t()], keyword()) :: {:ok, DataFrame.t()} | {:error, term()}
  def quote(symbols, opts \\ []) when is_binary(symbols) or is_list(symbols) do
    api_key = Keyword.get(opts, :api_key)

    with :ok <- ensure_api_key(api_key) do
      case RateLimiter.check_and_consume(:twelve_data, :quote) do
        :ok -> fetch_real_time_quotes(symbols, api_key)
        {:error, :rate_limited} -> {:error, :rate_limited}
      end
    end
  end

  @doc """
  Fetches company profile and fundamental data.

  ## Options

  - `:api_key` - Twelve Data API key (optional, will use config if not provided)

  ## Examples

      {:ok, info} = TwelveData.info("AAPL")
      {:ok, info} = TwelveData.info("AAPL", api_key: "YOUR_API_KEY")
  """
  @impl true
  @spec info(String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def info(symbol, opts \\ []) when is_binary(symbol) do
    api_key = Keyword.get(opts, :api_key)

    with :ok <- ensure_api_key(api_key) do
      case RateLimiter.check_and_consume(:twelve_data, :profile) do
        :ok -> fetch_company_profile(symbol, api_key)
        {:error, :rate_limited} -> {:error, :rate_limited}
      end
    end
  end

  @doc """
  Searches for stocks by symbol or company name.

  ## Options

  - `:api_key` - Twelve Data API key (optional, will use config if not provided)

  ## Examples

      {:ok, df} = TwelveData.search("Apple")
      {:ok, df} = TwelveData.search("AAPL", api_key: "YOUR_API_KEY")
  """
  @impl true
  @spec search(String.t(), keyword()) :: {:ok, DataFrame.t()} | {:error, term()}
  def search(query, opts \\ []) when is_binary(query) do
    api_key = Keyword.get(opts, :api_key)

    with :ok <- ensure_api_key(api_key) do
      case RateLimiter.check_and_consume(:twelve_data, :symbol_search) do
        :ok -> fetch_search_results(query, api_key)
        {:error, :rate_limited} -> {:error, :rate_limited}
      end
    end
  end

  @doc """
  Gets forex exchange rates.

  ## Options

  - `:from` - Base currency (default: "USD")
  - `:to` - Target currency (default: "EUR")

  ## Examples

      {:ok, df} = TwelveData.forex_rate("USD", "EUR")
      {:ok, df} = TwelveData.forex_rate(["USD", "GBP"], "EUR")
  """
  @spec forex_rate(String.t() | [String.t()], String.t()) ::
          {:ok, DataFrame.t()} | {:error, term()}
  def forex_rate(from_currencies, to_currency) do
    case RateLimiter.check_and_consume(:twelve_data, :exchange_rate) do
      :ok ->
        fetch_forex_rates(from_currencies, to_currency)

      {:error, :rate_limited} ->
        {:error, :rate_limited}
    end
  end

  # Private Implementation

  defp fetch_time_series_data(symbol, opts) when is_binary(symbol) do
    interval = Keyword.get(opts, :interval, "1day")
    outputsize = Keyword.get(opts, :outputsize, 30)

    with :ok <- validate_interval(interval) do
      params = build_time_series_params(symbol, interval, outputsize, opts)
      url = "#{@base_url}/time_series"

      case make_authenticated_request(url, params) do
        {:ok, %{status: 200, body: body}} ->
          parse_time_series_response(body, symbol)

        {:ok, %{status: 400, body: body}} ->
          parse_error_response(body)

        {:ok, %{status: 429}} ->
          {:error, :rate_limited}

        {:ok, %{status: status, body: body}} ->
          Logger.warning("Twelve Data API error: #{status} - #{body}")
          {:error, {:http_error, status}}

        {:error, reason} ->
          {:error, {:http_error, reason}}
      end
    end
  end

  defp fetch_time_series_data(symbols, opts) when is_list(symbols) do
    # For multiple symbols, fetch sequentially to respect rate limits
    results =
      Enum.map(symbols, fn symbol ->
        case fetch_time_series_data(symbol, opts) do
          {:ok, df} -> df
          {:error, _} = error -> error
        end
      end)

    case Enum.find(results, &match?({:error, _}, &1)) do
      nil ->
        # All successful, combine DataFrames
        combined_df =
          Enum.reduce(results, fn df, acc ->
            DataFrame.concat_rows([acc, df])
          end)

        {:ok, combined_df}

      error ->
        error
    end
  end

  defp fetch_real_time_quotes(symbols, api_key) do
    symbol_list = if is_binary(symbols), do: [symbols], else: symbols
    symbol_param = Enum.join(symbol_list, ",")

    params = %{
      "symbol" => symbol_param,
      "apikey" => api_key || get_api_key()
    }

    url = "#{@base_url}/quote"
    headers = [{"User-Agent", @user_agent}]

    case HttpClientConfig.get(url, params, headers: headers, timeout: @default_timeout) do
      {:ok, %{status: 200, body: body}} ->
        parse_quote_response(body, symbol_list)

      {:ok, %{status: 400, body: body}} ->
        parse_error_response(body)

      {:ok, %{status: 429}} ->
        {:error, :rate_limited}

      {:ok, %{status: status, body: body}} ->
        Logger.warning("Twelve Data quote API error: #{status} - #{body}")
        {:error, {:http_error, status}}

      {:error, reason} ->
        {:error, {:http_error, reason}}
    end
  end

  defp fetch_company_profile(symbol, api_key) do
    params = %{
      "symbol" => symbol,
      "apikey" => api_key || get_api_key()
    }

    url = "#{@base_url}/profile"
    headers = [{"User-Agent", @user_agent}]

    case HttpClientConfig.get(url, params, headers: headers, timeout: @default_timeout) do
      {:ok, %{status: 200, body: body}} ->
        parse_profile_response(body)

      {:ok, %{status: 400, body: body}} ->
        parse_error_response(body)

      {:ok, %{status: 429}} ->
        {:error, :rate_limited}

      {:ok, %{status: status, body: body}} ->
        Logger.warning("Twelve Data profile API error: #{status} - #{body}")
        {:error, {:http_error, status}}

      {:error, reason} ->
        {:error, {:http_error, reason}}
    end
  end

  defp fetch_search_results(query, api_key) do
    params = %{
      "symbol" => query,
      "apikey" => api_key || get_api_key()
    }

    url = "#{@base_url}/symbol_search"
    headers = [{"User-Agent", @user_agent}]

    case HttpClientConfig.get(url, params, headers: headers, timeout: @default_timeout) do
      {:ok, %{status: 200, body: body}} ->
        parse_search_response(body)

      {:ok, %{status: 400, body: body}} ->
        parse_error_response(body)

      {:ok, %{status: 429}} ->
        {:error, :rate_limited}

      {:ok, %{status: status, body: body}} ->
        Logger.warning("Twelve Data search API error: #{status} - #{body}")
        {:error, {:http_error, status}}

      {:error, reason} ->
        {:error, {:http_error, reason}}
    end
  end

  defp fetch_forex_rates(from_currencies, to_currency) do
    from_list = if is_binary(from_currencies), do: [from_currencies], else: from_currencies

    results =
      Enum.map(from_list, fn from_currency ->
        symbol = "#{from_currency}/#{to_currency}"

        params = %{
          "symbol" => symbol,
          "apikey" => get_api_key()
        }

        url = "#{@base_url}/exchange_rate"
        headers = [{"User-Agent", @user_agent}]

        case HttpClientConfig.get(url, params, headers: headers, timeout: @default_timeout) do
          {:ok, %{status: 200, body: body}} ->
            parse_exchange_rate_response(body, from_currency, to_currency)

          {:ok, %{status: 400, body: body}} ->
            {:error, {:parse_error, body}}

          {:ok, %{status: 429}} ->
            {:error, :rate_limited}

          {:ok, %{status: status, body: body}} ->
            Logger.warning("Twelve Data forex API error: #{status} - #{body}")
            {:error, {:http_error, status}}

          {:error, reason} ->
            {:error, {:http_error, reason}}
        end
      end)

    successful_results = Enum.filter(results, &match?({:ok, _}, &1))

    if successful_results != [] do
      data = Enum.map(successful_results, fn {:ok, row} -> row end)
      {:ok, DataFrame.new(data)}
    else
      # Return first error
      List.first(results)
    end
  end

  # Response Parsers

  defp parse_time_series_response(body, symbol) do
    case HttpClientConfig.decode_json(body) do
      {:ok, %{"values" => values}} when is_list(values) ->
        data =
          Enum.map(values, fn item ->
            {:ok, datetime, _} = DateTime.from_iso8601("#{item["datetime"]}T00:00:00Z")

            %{
              "symbol" => symbol,
              "timestamp" => datetime,
              "open" => ensure_float(item["open"]),
              "high" => ensure_float(item["high"]),
              "low" => ensure_float(item["low"]),
              "close" => ensure_float(item["close"]),
              "volume" => ensure_integer(item["volume"]),
              # Twelve Data doesn't provide adj_close
              "adj_close" => ensure_float(item["close"])
            }
          end)
          # Twelve Data returns newest first, we want oldest first
          |> Enum.reverse()

        {:ok, DataFrame.new(data)}

      {:ok, %{"code" => code, "message" => message}} ->
        handle_api_error(code, message)

      {:ok, %{"status" => "error", "message" => message}} ->
        {:error, {:provider_error, message}}

      {:error, reason} ->
        {:error, {:parse_error, reason}}

      {:ok, unexpected} ->
        {:error, {:parse_error, "Unexpected response format: #{inspect(unexpected)}"}}
    end
  end

  defp parse_quote_response(body, symbols) do
    with {:ok, decoded_data} <- HttpClientConfig.decode_json(body),
         {:ok, processed_data} <- process_quote_data(decoded_data, symbols) do
      {:ok, processed_data}
    else
      {:error, reason} -> {:error, {:parse_error, reason}}
    end
  end

  defp process_quote_data(quote_data, symbols) when is_map(quote_data) do
    process_single_quote_response(quote_data, symbols)
  end

  defp process_quote_data(quote_list, symbols) when is_list(quote_list) do
    process_multiple_quote_response(quote_list, symbols)
  end

  defp process_single_quote_response(quote_data, symbols) do
    case length(symbols) do
      1 ->
        symbol = List.first(symbols)
        data = [build_quote_row(quote_data, symbol)]
        {:ok, DataFrame.new(data)}

      _ ->
        case quote_data do
          %{"status" => "error"} -> {:error, {:provider_error, quote_data["message"]}}
          _ -> {:error, {:parse_error, "Unexpected multi-symbol response format"}}
        end
    end
  end

  defp process_multiple_quote_response(quote_list, symbols) do
    data =
      Enum.zip(quote_list, symbols)
      |> Enum.map(fn {quote_data, symbol} ->
        build_quote_row(quote_data, symbol)
      end)

    {:ok, DataFrame.new(data)}
  end

  defp parse_profile_response(body) do
    case HttpClientConfig.decode_json(body) do
      {:ok, %{"code" => code, "message" => message}} ->
        handle_api_error(code, message)

      {:ok, profile_data} when is_map(profile_data) ->
        profile = %{
          "symbol" => Map.get(profile_data, "symbol"),
          "name" => Map.get(profile_data, "name"),
          "exchange" => Map.get(profile_data, "exchange"),
          "currency" => Map.get(profile_data, "currency"),
          "country" => Map.get(profile_data, "country"),
          "type" => Map.get(profile_data, "type"),
          "sector" => Map.get(profile_data, "sector"),
          "industry" => Map.get(profile_data, "industry"),
          "description" => Map.get(profile_data, "description"),
          "ceo" => Map.get(profile_data, "ceo"),
          "employees" => Map.get(profile_data, "employees"),
          "website" => Map.get(profile_data, "website")
        }

        {:ok, profile}

      {:error, reason} ->
        {:error, {:parse_error, reason}}
    end
  end

  defp parse_search_response(body) do
    case HttpClientConfig.decode_json(body) do
      {:ok, %{"data" => search_results}} when is_list(search_results) ->
        data =
          Enum.map(search_results, fn item ->
            %{
              "symbol" => Map.get(item, "symbol"),
              "name" => Map.get(item, "instrument_name"),
              "exchange" => Map.get(item, "exchange"),
              "mic_code" => Map.get(item, "mic_code"),
              "currency" => Map.get(item, "currency"),
              "country" => Map.get(item, "country"),
              "type" => Map.get(item, "instrument_type")
            }
          end)

        {:ok, DataFrame.new(data)}

      {:ok, %{"code" => code, "message" => message}} ->
        handle_api_error(code, message)

      {:error, reason} ->
        {:error, {:parse_error, reason}}
    end
  end

  defp parse_exchange_rate_response(body, from_currency, to_currency) do
    case HttpClientConfig.decode_json(body) do
      {:ok, %{"rate" => rate, "timestamp" => timestamp}} ->
        {:ok, datetime, _} = DateTime.from_iso8601(timestamp)

        {:ok,
         %{
           "from_currency" => from_currency,
           "to_currency" => to_currency,
           "rate" => ensure_float(rate),
           "timestamp" => datetime
         }}

      {:ok, %{"code" => code, "message" => message}} ->
        handle_api_error(code, message)

      {:error, reason} ->
        {:error, {:parse_error, reason}}
    end
  end

  # Helper Functions

  defp build_quote_row(quote_data, symbol) do
    %{
      "symbol" => symbol,
      "price" => ensure_float(Map.get(quote_data, "close")),
      "change" => ensure_float(Map.get(quote_data, "change")),
      "change_percent" => ensure_float(Map.get(quote_data, "percent_change")),
      "volume" => ensure_integer(Map.get(quote_data, "volume")),
      "high" => ensure_float(Map.get(quote_data, "high")),
      "low" => ensure_float(Map.get(quote_data, "low")),
      "open" => ensure_float(Map.get(quote_data, "open")),
      "timestamp" => DateTime.utc_now()
    }
  end

  defp build_time_series_params(symbol, interval, outputsize, opts) do
    api_key = Keyword.get(opts, :api_key) || get_api_key()

    base_params = %{
      "symbol" => symbol,
      "interval" => interval,
      "outputsize" => min(outputsize, 5000),
      "apikey" => api_key
    }

    # Add optional parameters
    base_params
    |> maybe_add_param(:country, Keyword.get(opts, :country))
    |> maybe_add_param(:exchange, Keyword.get(opts, :exchange))
    |> maybe_add_param(:format, Keyword.get(opts, :format, "json"))
  end

  defp maybe_add_param(params, _key, nil), do: params
  defp maybe_add_param(params, key, value), do: Map.put(params, Atom.to_string(key), value)

  defp make_authenticated_request(url, params) do
    headers = [{"User-Agent", @user_agent}]
    HttpClientConfig.get(url, params, headers: headers, timeout: @default_timeout)
  end

  defp get_api_key, do: Config.api_key(:twelve_data)

  defp ensure_api_key(api_key) do
    if is_binary(api_key || get_api_key()), do: :ok, else: {:error, :api_key_missing}
  end

  defp validate_interval(interval) do
    if interval in @supported_intervals do
      :ok
    else
      {:error,
       {:invalid_interval, "Supported intervals: #{Enum.join(@supported_intervals, ", ")}"}}
    end
  end

  defp handle_api_error(400, message), do: {:error, {:invalid_request, message}}
  defp handle_api_error(401, message), do: {:error, {:api_key_error, message}}
  defp handle_api_error(403, message), do: {:error, {:api_key_error, message}}
  defp handle_api_error(404, _message), do: {:error, :symbol_not_found}
  defp handle_api_error(429, _message), do: {:error, :rate_limited}
  defp handle_api_error(code, message), do: {:error, {:provider_error, "#{code}: #{message}"}}

  defp parse_error_response(body) do
    case HttpClientConfig.decode_json(body) do
      {:ok, %{"code" => code, "message" => message}} ->
        handle_api_error(code, message)

      {:ok, %{"status" => "error", "message" => message}} ->
        {:error, {:provider_error, message}}

      _ ->
        {:error, {:parse_error, body}}
    end
  end

  defp ensure_float(nil), do: nil
  defp ensure_float(value) when is_number(value), do: value * 1.0

  defp ensure_float(value) when is_binary(value) do
    case Float.parse(value) do
      {float, _} -> float
      :error -> nil
    end
  end

  defp ensure_integer(nil), do: nil
  defp ensure_integer(value) when is_integer(value), do: value
  defp ensure_integer(value) when is_float(value), do: trunc(value)

  defp ensure_integer(value) when is_binary(value) do
    case Integer.parse(value) do
      {int, _} -> int
      :error -> nil
    end
  end
end
