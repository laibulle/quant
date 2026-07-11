defmodule Quant.Explorer.Providers.Binance do
  @moduledoc """
  Binance provider implementation for cryptocurrency data.

  This module provides access to Binance public API data including:
  - Historical OHLCV data (klines/candlesticks)
  - Real-time ticker statistics (24hr ticker)
  - Symbol search and exchange information

  All data is returned as Explorer DataFrames for immediate analysis.

  ## Binance API Endpoints

  - Historical: `https://api.binance.com/api/v3/klines`
  - 24hr Ticker: `https://api.binance.com/api/v3/ticker/24hr`
  - Exchange Info: `https://api.binance.com/api/v3/exchangeInfo`

  ## Rate Limiting

  Binance uses weighted rate limiting (1200 weight per minute):
  - Klines: 2-20 weight (based on limit parameter)
  - 24hr Ticker: 2 weight (single symbol), 80 weight (all symbols)
  - Exchange Info: 20 weight

  ## Interval Mapping

  Binance intervals: 1m, 3m, 5m, 15m, 30m, 1h, 2h, 4h, 6h, 8h, 12h, 1d, 3d, 1w, 1M

  ## Examples

      # Historical data (klines)
      {:ok, df} = Binance.history("BTCUSDT", interval: "1h", limit: 100)

      # Multiple symbols quotes
      {:ok, df} = Binance.quote(["BTCUSDT", "ETHUSDT", "ADAUSDT"])

      # Search for trading pairs
      {:ok, df} = Binance.search("BTC")

      # All available symbols
      {:ok, df} = Binance.search("")
  """

  @behaviour Quant.Explorer.Providers.Behaviour

  alias Explorer.DataFrame
  alias Quant.Explorer.{HttpClientConfig, RateLimiter}

  require Logger

  @base_url "https://api.binance.com"
  @user_agent "Quant.Explorer/1.0.0"
  @default_timeout 10_000

  # Binance interval constants (in milliseconds) - matching your existing code
  @interval_ms %{
    "1m" => 1 * 60 * 1000,
    "3m" => 3 * 60 * 1000,
    "5m" => 5 * 60 * 1000,
    "15m" => 15 * 60 * 1000,
    "30m" => 30 * 60 * 1000,
    "1h" => 1 * 60 * 60 * 1000,
    "2h" => 2 * 60 * 60 * 1000,
    "4h" => 4 * 60 * 60 * 1000,
    "6h" => 6 * 60 * 60 * 1000,
    "8h" => 8 * 60 * 60 * 1000,
    "12h" => 12 * 60 * 60 * 1000,
    "1d" => 1 * 24 * 60 * 60 * 1000,
    "3d" => 3 * 24 * 60 * 60 * 1000,
    "1w" => 7 * 24 * 60 * 60 * 1000,
    "1M" => 30 * 24 * 60 * 60 * 1000
  }

  @valid_intervals Map.keys(@interval_ms)

  # Provider Behaviour Implementation

  @impl true
  def history(symbol_or_symbols, opts \\ [])

  def history(symbols, opts) when is_list(symbols) do
    # Process multiple symbols concurrently
    tasks =
      symbols
      |> Enum.map(fn symbol ->
        Task.async(fn -> history(symbol, opts) end)
      end)

    results = Task.await_many(tasks, 30_000)

    case Enum.find(results, &match?({:error, _}, &1)) do
      {:error, _} = error ->
        error

      nil ->
        dataframes = Enum.map(results, fn {:ok, df} -> df end)
        {:ok, DataFrame.concat_rows(dataframes)}
    end
  end

  def history(symbol, opts) when is_binary(symbol) do
    interval = Keyword.get(opts, :interval, "1d")
    limit = Keyword.get(opts, :limit, 500)
    start_time = Keyword.get(opts, :start_time) || Keyword.get(opts, :start_date)
    end_time = Keyword.get(opts, :end_time) || Keyword.get(opts, :end_date)

    with :ok <- validate_interval(interval),
         {:ok, limit} <- resolve_limit(interval, limit, start_time, end_time),
         :ok <- RateLimiter.check_and_consume(:binance, :klines, limit: limit),
         data_result <- fetch_klines(symbol, interval, limit, start_time, end_time) do
      parse_klines_data(data_result, symbol)
    else
      {:error, reason} -> {:error, reason}
    end
  end

  @impl true
  def quote(symbol_or_symbols, _opts \\ [])

  def quote(symbols, _opts) when is_list(symbols) do
    with :ok <- RateLimiter.check_and_consume(:binance, :ticker_24hr, symbols: symbols),
         data_result <- fetch_ticker_24hr(symbols) do
      parse_ticker_data(data_result)
    else
      {:error, reason} -> {:error, reason}
    end
  end

  @impl true
  def quote(symbol, opts) when is_binary(symbol) do
    __MODULE__.quote([symbol], opts)
  end

  @impl true
  def search(query, _opts \\ []) when is_binary(query) do
    with :ok <- RateLimiter.check_and_consume(:binance, :exchange_info),
         data_result <- fetch_exchange_info() do
      parse_exchange_info(data_result, query)
    else
      {:error, reason} -> {:error, reason}
    end
  end

  @impl true
  def info(_symbol, _opts \\ []) do
    {:error, :not_supported}
  end

  # Additional Binance-specific functions

  @doc """
  Get all available trading pairs on Binance.
  """
  def get_all_symbols do
    search("")
  end

  @doc """
  Get klines/candlestick data with time range.
  Automatically calculates limit based on time range and interval.
  """
  def history_range(symbol, interval, start_time, end_time) when is_binary(symbol) do
    with {:ok, limit} <- compute_klines_limit(interval, start_time, end_time) do
      history(symbol,
        interval: interval,
        limit: limit,
        start_time: start_time,
        end_time: end_time
      )
    end
  end

  # Private Functions

  defp fetch_klines(symbol, interval, limit, start_time, end_time) do
    url = "#{@base_url}/api/v3/klines"
    headers = [{"User-Agent", @user_agent}]

    params = build_klines_params(symbol, interval, limit, start_time, end_time)

    case HttpClientConfig.get(url, params, headers: headers, timeout: @default_timeout) do
      {:ok, %{status: 200, body: body}} ->
        HttpClientConfig.decode_json(body)

      {:ok, %{status: status, body: body}} ->
        Logger.warning("Binance klines error: #{status} - #{body}")
        {:error, {:http_error, status}}

      {:error, reason} ->
        Logger.error("Binance klines request failed: #{inspect(reason)}")
        {:error, {:request_failed, reason}}
    end
  end

  defp build_klines_params(symbol, interval, limit, start_time, end_time) do
    base_params = %{
      symbol: symbol,
      interval: interval,
      limit: limit
    }

    base_params
    |> maybe_add_time_param(:startTime, start_time)
    |> maybe_add_time_param(:endTime, end_time)
  end

  defp maybe_add_time_param(params, _key, nil), do: params

  defp maybe_add_time_param(params, key, %DateTime{} = datetime) do
    Map.put(params, key, DateTime.to_unix(datetime, :millisecond))
  end

  defp maybe_add_time_param(params, key, timestamp) when is_integer(timestamp) do
    Map.put(params, key, timestamp)
  end

  defp fetch_ticker_24hr(symbols) when is_list(symbols) do
    url = "#{@base_url}/api/v3/ticker/24hr"
    headers = [{"User-Agent", @user_agent}]

    params =
      case symbols do
        # Get all symbols
        [] -> %{}
        _ -> %{symbols: Enum.join(symbols, ",")}
      end

    case HttpClientConfig.get(url, params, headers: headers, timeout: @default_timeout) do
      {:ok, %{status: 200, body: body}} ->
        HttpClientConfig.decode_json(body)

      {:ok, %{status: status, body: body}} ->
        Logger.warning("Binance ticker error: #{status} - #{body}")
        {:error, {:http_error, status}}

      {:error, reason} ->
        Logger.error("Binance ticker request failed: #{inspect(reason)}")
        {:error, {:request_failed, reason}}
    end
  end

  defp fetch_exchange_info do
    url = "#{@base_url}/api/v3/exchangeInfo"
    headers = [{"User-Agent", @user_agent}]

    case HttpClientConfig.get(url, %{}, headers: headers, timeout: @default_timeout) do
      {:ok, %{status: 200, body: body}} ->
        HttpClientConfig.decode_json(body)

      {:ok, %{status: status, body: body}} ->
        Logger.warning("Binance exchange info error: #{status} - #{body}")
        {:error, {:http_error, status}}

      {:error, reason} ->
        Logger.error("Binance exchange info request failed: #{inspect(reason)}")
        {:error, {:request_failed, reason}}
    end
  end

  # Data Parsing Functions

  defp parse_klines_data({:ok, klines_data}, symbol) when is_list(klines_data) do
    rows = Enum.map(klines_data, &parse_kline_row(&1, symbol))

    df = DataFrame.new(rows)
    {:ok, df}
  rescue
    error ->
      Logger.error("Failed to parse Binance klines data: #{inspect(error)}")
      {:error, {:parse_error, "Invalid klines data format"}}
  end

  defp parse_klines_data({:error, reason}, _symbol) do
    {:error, reason}
  end

  defp parse_kline_row(
         [
           open_time,
           open,
           high,
           low,
           close,
           volume,
           close_time,
           quote_asset_volume,
           number_of_trades,
           taker_buy_base_asset_volume,
           taker_buy_quote_asset_volume,
           _ignore
         ],
         symbol
       ) do
    %{
      symbol: symbol,
      timestamp: DateTime.from_unix!(open_time, :millisecond),
      open: parse_float(open),
      high: parse_float(high),
      low: parse_float(low),
      close: parse_float(close),
      volume: parse_float(volume),
      # Crypto doesn't have adjusted close, use close
      adj_close: parse_float(close),
      quote_volume: parse_float(quote_asset_volume),
      number_of_trades: number_of_trades,
      taker_buy_volume: parse_float(taker_buy_base_asset_volume),
      taker_buy_quote_volume: parse_float(taker_buy_quote_asset_volume),
      close_time: DateTime.from_unix!(close_time, :millisecond)
    }
  end

  defp parse_ticker_data({:ok, ticker_data}) when is_list(ticker_data) do
    rows = Enum.map(ticker_data, &parse_ticker_row/1)
    df = DataFrame.new(rows)
    {:ok, df}
  rescue
    error ->
      Logger.error("Failed to parse Binance ticker data: #{inspect(error)}")
      {:error, {:parse_error, "Invalid ticker data format"}}
  end

  defp parse_ticker_data({:error, reason}) do
    {:error, reason}
  end

  defp parse_ticker_row(%{
         "symbol" => symbol,
         "lastPrice" => price,
         "priceChange" => change,
         "priceChangePercent" => change_percent,
         "volume" => volume,
         "count" => count,
         "openTime" => open_time,
         "closeTime" => close_time,
         "highPrice" => high,
         "lowPrice" => low,
         "openPrice" => open_price,
         "quoteVolume" => quote_volume
       }) do
    %{
      symbol: symbol,
      price: parse_float(price),
      change: parse_float(change),
      change_percent: parse_float(change_percent),
      volume: parse_float(volume),
      timestamp: DateTime.from_unix!(close_time, :millisecond),
      high_24h: parse_float(high),
      low_24h: parse_float(low),
      open_24h: parse_float(open_price),
      quote_volume: parse_float(quote_volume),
      trade_count: count,
      open_time: DateTime.from_unix!(open_time, :millisecond)
    }
  end

  defp parse_exchange_info({:ok, %{"symbols" => symbols}}, query) when is_list(symbols) do
    filtered_symbols = filter_symbols(symbols, query)
    rows = Enum.map(filtered_symbols, &parse_symbol_info/1)
    df = DataFrame.new(rows)
    {:ok, df}
  rescue
    error ->
      Logger.error("Failed to parse Binance exchange info: #{inspect(error)}")
      {:error, {:parse_error, "Invalid exchange info format"}}
  end

  defp parse_exchange_info({:error, reason}, _query) do
    {:error, reason}
  end

  # Return all if empty query
  defp filter_symbols(symbols, ""), do: symbols

  defp filter_symbols(symbols, query) do
    query_upper = String.upcase(query)

    Enum.filter(symbols, fn %{"symbol" => symbol} ->
      String.contains?(String.upcase(symbol), query_upper)
    end)
  end

  defp parse_symbol_info(%{
         "symbol" => symbol,
         "status" => status,
         "baseAsset" => base_asset,
         "quoteAsset" => quote_asset,
         "baseAssetPrecision" => base_precision,
         "quotePrecision" => quote_precision
       }) do
    %{
      symbol: symbol,
      status: status,
      base_asset: base_asset,
      quote_asset: quote_asset,
      base_precision: base_precision,
      quote_precision: quote_precision,
      type: "SPOT",
      exchange: "Binance"
    }
  end

  # Utility Functions

  defp validate_interval(interval) when interval in @valid_intervals, do: :ok

  defp validate_interval(interval) do
    {:error,
     {:invalid_interval,
      "Invalid interval: #{interval}. Valid: #{Enum.join(@valid_intervals, ", ")}"}}
  end

  defp validate_limit(limit) when is_integer(limit) and limit > 0 and limit <= 1000, do: :ok

  defp validate_limit(limit) do
    {:error, {:invalid_limit, "Limit must be between 1 and 1000, got: #{limit}"}}
  end

  defp compute_klines_limit(interval, start_time, end_time) do
    case Map.get(@interval_ms, interval) do
      nil ->
        {:error, {:invalid_interval, interval}}

      interval_ms ->
        start_ms = datetime_to_ms(start_time)
        end_ms = datetime_to_ms(end_time)
        diff_ms = end_ms - start_ms
        limit = div(diff_ms, interval_ms) + 1

        cond do
          limit <= 0 ->
            {:error, {:invalid_time_range, "End time must be after start time"}}

          limit > 1000 ->
            {:error,
             {:limit_exceeded, "Time range too large, would require #{limit} klines (max: 1000)"}}

          true ->
            {:ok, limit}
        end
    end
  end

  defp datetime_to_ms(%DateTime{} = dt), do: DateTime.to_unix(dt, :millisecond)

  defp datetime_to_ms(%Date{} = date),
    do: date |> DateTime.new!(~T[00:00:00], "Etc/UTC") |> DateTime.to_unix(:millisecond)

  defp datetime_to_ms(timestamp) when is_integer(timestamp), do: timestamp

  defp resolve_limit(_interval, limit, nil, _end_time), do: validate_limit_result(limit)
  defp resolve_limit(_interval, limit, _start_time, nil), do: validate_limit_result(limit)

  defp resolve_limit(interval, _limit, start_time, end_time) do
    compute_klines_limit(interval, start_time, end_time)
  end

  defp validate_limit_result(limit) do
    case validate_limit(limit) do
      :ok -> {:ok, limit}
      {:error, _} = error -> error
    end
  end

  defp parse_float(value) when is_binary(value) do
    case Float.parse(value) do
      {float, ""} -> float
      _ -> 0.0
    end
  end

  defp parse_float(value) when is_number(value), do: value / 1
  defp parse_float(_), do: 0.0
end
