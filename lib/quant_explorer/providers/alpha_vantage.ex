defmodule Quant.Explorer.Providers.AlphaVantage do
  @moduledoc """
  Alpha Vantage data provider for Quant.Explorer.

  Provides access to Alpha Vantage's comprehensive financial data including:
  - Historical stock data (daily, weekly, monthly)
  - Real-time quotes
  - Symbol search
  - Company fundamentals
  - Forex and commodity data

  ## Configuration

  Requires an API key from Alpha Vantage. Set the ALPHA_VANTAGE_API_KEY environment variable
  or configure it in your application config:

      config :quant,
        api_keys: %{
          alpha_vantage: "your_api_key_here"
        }

  ## Rate Limits

  - Free tier: 25 requests per day, 5 API requests per minute
  - Premium: 75 requests per minute, higher daily limits

  ## Examples

      # Historical data
      {:ok, df} = AlphaVantage.history("IBM", outputsize: "compact")

      # Real-time quote
      {:ok, df} = AlphaVantage.quote("IBM")

      # Search symbols
      {:ok, df} = AlphaVantage.search("Microsoft")

  """

  @behaviour Quant.Explorer.Providers.Behaviour

  alias Explorer.DataFrame
  alias Quant.Explorer.{Config, HttpClientConfig, RateLimiter}

  require Logger

  # API configuration
  @base_url "https://www.alphavantage.co/query"
  @user_agent "Quant.Explorer/#{Mix.Project.config()[:version]} (+https://github.com/the-nerd-company/quant)"
  @default_timeout 30_000

  # Supported intervals and periods
  @intervals ~w[1min 5min 15min 30min 60min daily weekly monthly]
  @output_sizes ~w[compact full]

  # Type specifications
  @type symbol :: String.t()
  @type symbols :: [symbol()]
  @type options :: keyword()

  @doc """
  Fetches historical data for a symbol.

  ## Options

  - `:interval` - Time interval: "1min", "5min", "15min", "30min", "60min", "daily", "weekly", "monthly" (default: "daily")
  - `:outputsize` - Data size: "compact" (last 100 points) or "full" (all available) (default: "compact")
  - `:adjusted` - Whether to include adjusted close prices (default: true)

  ## Examples

      {:ok, df} = AlphaVantage.history("IBM")
      {:ok, df} = AlphaVantage.history("AAPL", interval: "5min", outputsize: "full")

  """
  @impl true
  @spec history(symbol() | symbols(), options()) :: {:ok, DataFrame.t()} | {:error, term()}
  def history(symbol_or_symbols, opts \\ [])

  def history(symbols, opts) when is_list(symbols) do
    # Alpha Vantage doesn't support batch requests, process sequentially
    Task.async_stream(
      symbols,
      fn symbol -> history(symbol, opts) end,
      # Respect rate limits
      max_concurrency: 2,
      timeout: @default_timeout * 2
    )
    |> Enum.reduce_while({:ok, []}, fn
      {:ok, {:ok, df}}, {:ok, dfs} -> {:cont, {:ok, [df | dfs]}}
      {:ok, {:error, reason}}, _acc -> {:halt, {:error, reason}}
      {:exit, reason}, _acc -> {:halt, {:error, {:task_exit, reason}}}
    end)
    |> case do
      {:ok, [_ | _] = dfs} ->
        combined_df =
          dfs
          |> Enum.reverse()
          |> Enum.reduce(&DataFrame.concat_rows/2)

        {:ok, combined_df}

      {:ok, []} ->
        {:error, :no_data}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def history(symbol, opts) when is_binary(symbol) do
    interval = Keyword.get(opts, :interval, "daily")

    outputsize =
      Keyword.get(
        opts,
        :outputsize,
        if(Keyword.has_key?(opts, :start_date), do: "full", else: "compact")
      )

    adjusted = Keyword.get(opts, :adjusted, true)
    api_key = Keyword.get(opts, :api_key)

    with :ok <- validate_interval(interval),
         :ok <- validate_outputsize(outputsize),
         :ok <- ensure_api_key(api_key),
         :ok <- RateLimiter.check_and_consume(:alpha_vantage, :time_series),
         data_result <- fetch_time_series(symbol, interval, outputsize, adjusted, api_key) do
      data_result
      |> parse_time_series_data(symbol)
      |> filter_history_range(opts)
    else
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Fetches real-time quotes for one or more symbols.

  ## Options

  - `:api_key` - Alpha Vantage API key (optional, will use config if not provided)

  ## Examples

      {:ok, df} = AlphaVantage.quote("IBM")
      {:ok, df} = AlphaVantage.quote("IBM", api_key: "YOUR_API_KEY")
      {:ok, df} = AlphaVantage.quote(["AAPL", "MSFT", "GOOGL"], api_key: "YOUR_API_KEY")

  """
  @impl true
  @spec quote(symbol() | symbols(), options()) :: {:ok, DataFrame.t()} | {:error, term()}
  def quote(symbol_or_symbols, opts \\ [])

  def quote(symbols, opts) when is_list(symbols) do
    # Process quotes sequentially due to rate limits
    Task.async_stream(
      symbols,
      fn symbol -> __MODULE__.quote(symbol, opts) end,
      # Conservative for rate limits
      max_concurrency: 3,
      timeout: @default_timeout
    )
    |> Enum.reduce_while({:ok, []}, fn
      {:ok, {:ok, df}}, {:ok, dfs} -> {:cont, {:ok, [df | dfs]}}
      {:ok, {:error, reason}}, _acc -> {:halt, {:error, reason}}
      {:exit, reason}, _acc -> {:halt, {:error, {:task_exit, reason}}}
    end)
    |> case do
      {:ok, [_ | _] = dfs} ->
        combined_df =
          dfs
          |> Enum.reverse()
          |> Enum.reduce(&DataFrame.concat_rows/2)

        {:ok, combined_df}

      {:ok, []} ->
        {:error, :no_data}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def quote(symbol, opts) when is_binary(symbol) do
    api_key = Keyword.get(opts, :api_key)

    with :ok <- ensure_api_key(api_key),
         :ok <- RateLimiter.check_and_consume(:alpha_vantage, :quote),
         data_result <- fetch_global_quote(symbol, api_key) do
      parse_quote_data(data_result, symbol)
    else
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Searches for symbols matching a query.

  ## Options

  - `:api_key` - Alpha Vantage API key (optional, will use config if not provided)

  ## Examples

      {:ok, df} = AlphaVantage.search("Microsoft")
      {:ok, df} = AlphaVantage.search("AAPL", api_key: "YOUR_API_KEY")

  """
  @impl true
  @spec search(String.t(), options()) :: {:ok, DataFrame.t()} | {:error, term()}
  def search(query, opts \\ []) when is_binary(query) do
    api_key = Keyword.get(opts, :api_key)

    with :ok <- ensure_api_key(api_key),
         :ok <- RateLimiter.check_and_consume(:alpha_vantage, :search),
         data_result <- fetch_symbol_search(query, api_key) do
      parse_search_data(data_result)
    else
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Alpha Vantage doesn't provide company info in the same way as other providers.
  This function returns an error indicating the feature is not supported.

  ## Options

  - `:api_key` - Alpha Vantage API key (optional, will use config if not provided)

  """
  @impl true
  @spec info(symbol(), options()) :: {:ok, map()} | {:error, term()}
  def info(_symbol, _opts \\ []), do: {:error, :not_supported}

  # Private functions

  defp ensure_api_key(api_key) do
    if is_binary(api_key || Config.api_key(:alpha_vantage)),
      do: :ok,
      else: {:error, :api_key_missing}
  end

  defp validate_interval(interval) do
    if interval in @intervals do
      :ok
    else
      {:error, {:invalid_interval, "Supported intervals: #{Enum.join(@intervals, ", ")}"}}
    end
  end

  defp validate_outputsize(outputsize) do
    if outputsize in @output_sizes do
      :ok
    else
      {:error, {:invalid_outputsize, "Supported output sizes: #{Enum.join(@output_sizes, ", ")}"}}
    end
  end

  defp fetch_time_series(symbol, interval, outputsize, adjusted, api_key) do
    function = determine_time_series_function(interval, adjusted)

    params =
      [
        {"function", function},
        {"symbol", symbol},
        {"outputsize", outputsize}
      ]
      |> add_interval_param(interval, function)
      |> add_api_key(api_key)

    headers = [{"User-Agent", @user_agent}]

    case HttpClientConfig.get(@base_url, params, headers: headers, timeout: @default_timeout) do
      {:ok, %{status: 200, body: body}} ->
        HttpClientConfig.decode_json(body)

      {:ok, %{status: status, body: body}} ->
        Logger.warning("Alpha Vantage time series error: #{status} - #{body}")
        {:error, {:http_error, status}}

      {:error, reason} ->
        Logger.error("Alpha Vantage time series request failed: #{inspect(reason)}")
        {:error, {:request_failed, reason}}
    end
  end

  defp fetch_global_quote(symbol, api_key) do
    params =
      [
        {"function", "GLOBAL_QUOTE"},
        {"symbol", symbol}
      ]
      |> add_api_key(api_key)

    headers = [{"User-Agent", @user_agent}]

    case HttpClientConfig.get(@base_url, params, headers: headers, timeout: @default_timeout) do
      {:ok, %{status: 200, body: body}} ->
        HttpClientConfig.decode_json(body)

      {:ok, %{status: status, body: body}} ->
        Logger.warning("Alpha Vantage quote error: #{status} - #{body}")
        {:error, {:http_error, status}}

      {:error, reason} ->
        Logger.error("Alpha Vantage quote request failed: #{inspect(reason)}")
        {:error, {:request_failed, reason}}
    end
  end

  defp fetch_symbol_search(query, api_key) do
    params =
      [
        {"function", "SYMBOL_SEARCH"},
        {"keywords", query}
      ]
      |> add_api_key(api_key)

    headers = [{"User-Agent", @user_agent}]

    case HttpClientConfig.get(@base_url, params, headers: headers, timeout: @default_timeout) do
      {:ok, %{status: 200, body: body}} ->
        HttpClientConfig.decode_json(body)

      {:ok, %{status: status, body: body}} ->
        Logger.warning("Alpha Vantage search error: #{status} - #{body}")
        {:error, {:http_error, status}}

      {:error, reason} ->
        Logger.error("Alpha Vantage search request failed: #{inspect(reason)}")
        {:error, {:request_failed, reason}}
    end
  end

  defp determine_time_series_function(interval, adjusted) do
    case interval do
      "daily" -> if adjusted, do: "TIME_SERIES_DAILY_ADJUSTED", else: "TIME_SERIES_DAILY"
      "weekly" -> if adjusted, do: "TIME_SERIES_WEEKLY_ADJUSTED", else: "TIME_SERIES_WEEKLY"
      "monthly" -> if adjusted, do: "TIME_SERIES_MONTHLY_ADJUSTED", else: "TIME_SERIES_MONTHLY"
      _ -> "TIME_SERIES_INTRADAY"
    end
  end

  defp add_interval_param(params, interval, "TIME_SERIES_INTRADAY") do
    [{"interval", interval} | params]
  end

  defp add_interval_param(params, _interval, _function), do: params

  defp add_api_key(params, api_key) do
    final_api_key = api_key || Config.api_key(:alpha_vantage)

    case final_api_key do
      nil ->
        params

      key ->
        [{"apikey", key} | params]
    end
  end

  defp filter_history_range({:ok, df}, opts) do
    start_date = Keyword.get(opts, :start_date)
    end_date = Keyword.get(opts, :end_date)

    if is_nil(start_date) and is_nil(end_date) do
      {:ok, df}
    else
      rows =
        df
        |> DataFrame.to_rows()
        |> Enum.filter(&timestamp_in_range?(&1, start_date, end_date))

      {:ok, DataFrame.new(rows)}
    end
  end

  defp filter_history_range({:error, _} = error, _opts), do: error

  defp timestamp_in_range?(row, start_date, end_date) do
    timestamp = Map.get(row, "timestamp") || Map.get(row, :timestamp)
    date = DateTime.to_date(timestamp)
    (is_nil(start_date) or date >= start_date) and (is_nil(end_date) or date <= end_date)
  end

  defp parse_time_series_data({:ok, data}, symbol) do
    # Check for demo API key message
    if Map.has_key?(data, "Information") and String.contains?(data["Information"], "demo") do
      {:error,
       {:api_key_error, "Demo API key detected. Please use a valid Alpha Vantage API key."}}
    else
      time_series = extract_time_series(data)
      process_time_series(time_series, data, symbol)
    end
  rescue
    error ->
      Logger.error("Failed to parse Alpha Vantage time series data: #{inspect(error)}")
      {:error, {:parse_error, "Invalid time series data format"}}
  end

  defp parse_time_series_data({:error, reason}, _symbol) do
    {:error, reason}
  end

  defp process_time_series(time_series, data, symbol) do
    if Enum.empty?(time_series) do
      handle_empty_time_series(data, symbol)
    else
      rows =
        Enum.map(time_series, fn {timestamp, values} ->
          parse_time_series_row(timestamp, values, symbol)
        end)

      df = DataFrame.new(rows)
      {:ok, df}
    end
  end

  defp handle_empty_time_series(data, symbol) do
    # Check if this might be a demo key response
    if Map.has_key?(data, "Information") or Map.has_key?(data, "Note") do
      message = Map.get(data, "Information", Map.get(data, "Note", "Unknown response"))
      {:error, {:api_key_error, "Alpha Vantage returned empty data: #{message}"}}
    else
      {:error, {:symbol_not_found, "No time series data found for symbol #{symbol}"}}
    end
  end

  defp extract_time_series(data) do
    # Alpha Vantage returns different keys for different time series
    time_series_key =
      data
      |> Map.keys()
      |> Enum.find(fn key -> String.contains?(key, "Time Series") end)

    case time_series_key do
      nil ->
        # Check for error messages
        case Map.get(data, "Error Message") do
          nil -> []
          error_msg -> raise "API Error: #{error_msg}"
        end

      key ->
        data[key] |> Enum.to_list()
    end
  end

  defp parse_time_series_row(timestamp_str, values, symbol) do
    timestamp = parse_timestamp(timestamp_str)

    %{
      symbol: symbol,
      timestamp: timestamp,
      open: parse_float(values["1. open"]),
      high: parse_float(values["2. high"]),
      low: parse_float(values["3. low"]),
      close: parse_float(values["4. close"]),
      adj_close: parse_float(values["5. adjusted close"] || values["4. close"]),
      volume: parse_integer(values["5. volume"] || values["6. volume"])
    }
  end

  defp parse_quote_data({:ok, data}, symbol) do
    with {:ok, validated_data} <- validate_quote_response(data),
         {:ok, quote_row} <- extract_quote_data(validated_data, symbol) do
      df = DataFrame.new([quote_row])
      {:ok, df}
    end
  rescue
    error ->
      Logger.error("Failed to parse Alpha Vantage quote data: #{inspect(error)}")
      {:error, {:parse_error, "Invalid quote data format"}}
  end

  defp parse_quote_data({:error, reason}, _symbol) do
    {:error, reason}
  end

  defp validate_quote_response(data) do
    cond do
      data["Error Message"] ->
        {:error, {:api_key_error, data["Error Message"]}}

      data["Note"] && String.contains?(data["Note"], "Thank you") ->
        {:error, {:api_key_error, "Alpha Vantage returned empty data: #{data["Note"]}"}}

      data["Information"] ->
        handle_information_field(data["Information"])

      true ->
        {:ok, data}
    end
  end

  defp handle_information_field(information) do
    cond do
      String.contains?(information, "rate limit") ->
        {:error, :rate_limited}

      String.contains?(information, "demo") ->
        {:error,
         {:api_key_error,
          "Demo API key detected. Please get a free API key at https://www.alphavantage.co/support/#api-key"}}

      String.contains?(information, "API key") ->
        {:error, {:api_key_error, information}}

      true ->
        {:ok, nil}
    end
  end

  defp extract_quote_data(data, symbol) do
    global_quote = data["Global Quote"]

    if is_nil(global_quote) or global_quote == %{} do
      handle_empty_quote_data(data, symbol)
    else
      build_quote_row(global_quote, symbol)
    end
  end

  defp handle_empty_quote_data(data, symbol) do
    if map_size(data) == 0 do
      {:error, {:api_key_error, "No data returned - check API key and symbol"}}
    else
      Logger.debug("Alpha Vantage response for #{symbol}: #{inspect(data)}")
      {:error, :symbol_not_found}
    end
  end

  defp build_quote_row(global_quote, symbol) do
    row = %{
      symbol: symbol,
      price: parse_float(global_quote["05. price"]),
      change: parse_float(global_quote["09. change"]),
      change_percent: parse_change_percent(global_quote["10. change percent"]),
      volume: parse_integer(global_quote["06. volume"]),
      timestamp: DateTime.utc_now()
    }

    {:ok, row}
  end

  defp parse_search_data({:ok, data}) do
    best_matches = data["bestMatches"] || []

    rows =
      Enum.map(best_matches, fn match ->
        %{
          symbol: match["1. symbol"],
          name: match["2. name"],
          type: match["3. type"],
          region: match["4. region"],
          market_open: match["5. marketOpen"],
          market_close: match["6. marketClose"],
          timezone: match["7. timezone"],
          currency: match["8. currency"],
          match_score: parse_float(match["9. matchScore"])
        }
      end)

    df = DataFrame.new(rows)
    {:ok, df}
  rescue
    error ->
      Logger.error("Failed to parse Alpha Vantage search data: #{inspect(error)}")
      {:error, {:parse_error, "Invalid search data format"}}
  end

  defp parse_search_data({:error, reason}) do
    {:error, reason}
  end

  defp parse_timestamp(timestamp_str) do
    case DateTime.from_iso8601(timestamp_str <> "T00:00:00Z") do
      {:ok, datetime, _} ->
        datetime

      {:error, _} ->
        # Try parsing as datetime
        case DateTime.from_iso8601(timestamp_str <> "Z") do
          {:ok, datetime, _} -> datetime
          {:error, _} -> DateTime.utc_now()
        end
    end
  end

  defp parse_float(nil), do: nil

  defp parse_float(value) when is_binary(value) do
    case Float.parse(value) do
      {float_val, _} -> float_val
      :error -> nil
    end
  end

  defp parse_float(value) when is_number(value), do: value / 1.0

  defp parse_integer(nil), do: nil

  defp parse_integer(value) when is_binary(value) do
    case Integer.parse(value) do
      {int_val, _} -> int_val
      :error -> nil
    end
  end

  defp parse_integer(value) when is_integer(value), do: value

  defp parse_change_percent(nil), do: nil

  defp parse_change_percent(value) when is_binary(value) do
    # Remove % sign and parse
    value
    |> String.replace("%", "")
    |> parse_float()
  end
end
