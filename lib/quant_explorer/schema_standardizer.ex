defmodule Quant.Explorer.SchemaStandardizer do
  @moduledoc """
  Comprehensive schema standardization for financial data analysis.

  This module provides unified parameter handling and output schema standardization
  across all providers to ensure complete interoperability for financial analysis.

  ## Design Principles

  1. **Universal Parameters**: All providers accept the same parameter names
  2. **Automatic Translation**: Provider-specific parameters are translated internally
  3. **Consistent Output**: All DataFrames have identical schemas regardless of provider
  4. **Type Safety**: Strong typing and validation for all fields
  5. **Timezone Handling**: All timestamps normalized to UTC with timezone info
  """

  alias Explorer.DataFrame
  alias Explorer.Series
  require Logger

  # ========== STANDARDIZED PARAMETER DEFINITIONS ==========

  # Standard time intervals supported across all providers.
  # These are automatically translated to provider-specific formats.
  @standard_intervals %{
    # Intraday intervals
    "1m" => %{
      yahoo_finance: "1m",
      alpha_vantage: "1min",
      binance: "1m",
      twelve_data: "1min"
    },
    "5m" => %{
      yahoo_finance: "5m",
      alpha_vantage: "5min",
      binance: "5m",
      twelve_data: "5min"
    },
    "15m" => %{
      yahoo_finance: "15m",
      alpha_vantage: "15min",
      binance: "15m",
      twelve_data: "15min"
    },
    "30m" => %{
      yahoo_finance: "30m",
      alpha_vantage: "30min",
      binance: "30m",
      twelve_data: "30min"
    },
    "1h" => %{
      yahoo_finance: "1h",
      alpha_vantage: "60min",
      binance: "1h",
      twelve_data: "1h"
    },
    # Daily and longer intervals
    "1d" => %{
      yahoo_finance: "1d",
      alpha_vantage: "daily",
      binance: "1d",
      twelve_data: "1day",
      coin_gecko: "daily"
    },
    "1w" => %{
      yahoo_finance: "1wk",
      alpha_vantage: "weekly",
      binance: "1w",
      twelve_data: "1week"
    },
    "1mo" => %{
      yahoo_finance: "1mo",
      alpha_vantage: "monthly",
      binance: "1M",
      twelve_data: "1month"
    }
  }

  # Standard time periods supported across all providers.
  # These are automatically translated to provider-specific formats or date ranges.
  @standard_periods %{
    "1d" => %{days: 1, yahoo: "1d"},
    "5d" => %{days: 5, yahoo: "5d"},
    "1mo" => %{days: 30, yahoo: "1mo", coin_gecko: 30},
    "3mo" => %{days: 90, yahoo: "3mo", coin_gecko: 90},
    "6mo" => %{days: 180, yahoo: "6mo", coin_gecko: 180},
    "1y" => %{days: 365, yahoo: "1y", coin_gecko: 365},
    "2y" => %{days: 730, yahoo: "2y", coin_gecko: 730},
    "5y" => %{days: 1825, yahoo: "5y", coin_gecko: 1825},
    "10y" => %{days: 3650, yahoo: "10y"},
    "max" => %{days: :max, yahoo: "max", coin_gecko: "max"}
  }

  # ========== PARAMETER STANDARDIZATION ==========

  @doc """
  Standardizes query parameters across all providers.

  ## Standard Parameters

  - `:interval` - Time interval: "1m", "5m", "15m", "30m", "1h", "1d", "1w", "1mo"
  - `:period` - Time period: "1d", "5d", "1mo", "3mo", "6mo", "1y", "2y", "5y", "10y", "max"
  - `:limit` - Number of data points to return (integer)
  - `:start_date` - Start date (Date, DateTime, or ISO string)
  - `:end_date` - End date (Date, DateTime, or ISO string)
  - `:currency` - Base currency for crypto quotes: "usd", "eur", "btc", "eth"
  - `:adjusted` - Whether to use adjusted prices (boolean, default: true)
  - `:api_key` - API key for authentication

  ## Returns

  `{:ok, standardized_params}` or `{:error, reason}`
  """
  @spec standardize_params(keyword(), atom()) :: {:ok, keyword()} | {:error, term()}
  def standardize_params(params, provider) do
    with :ok <- validate_provider_support(params, provider),
         {:ok, interval} <- normalize_interval(params[:interval], provider),
         {:ok, period_params} <- normalize_period(params[:period], provider),
         {:ok, date_params} <- normalize_dates(params[:start_date], params[:end_date]),
         {:ok, currency} <- normalize_currency(params[:currency], provider),
         {:ok, limit} <- normalize_limit(params[:limit], provider) do
      standardized =
        [
          interval: interval,
          currency: currency,
          limit: limit,
          adjusted: Keyword.get(params, :adjusted, true),
          api_key: params[:api_key]
        ]
        |> Keyword.merge(period_params)
        |> Keyword.merge(date_params)
        |> Enum.reject(fn {_k, v} -> is_nil(v) end)

      {:ok, standardized}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  # ========== OUTPUT SCHEMA STANDARDIZATION ==========

  # Standard column orders for consistent output
  @standard_history_columns ~w[
    symbol timestamp open high low close volume adj_close
    market_cap provider currency timezone
  ]

  @standard_quote_columns ~w[
    symbol price change change_percent volume high_24h low_24h
    market_cap timestamp provider currency market_state
  ]

  @standard_search_columns ~w[
    symbol name type exchange currency country sector industry
    market_cap provider match_score
  ]

  @doc """
  Standardizes historical data DataFrame to consistent schema.

  ## Standard Historical Data Schema

  - `symbol` (string): Stock/crypto symbol
  - `timestamp` (datetime): UTC timestamp with timezone info
  - `open` (f64): Opening price
  - `high` (f64): Highest price
  - `low` (f64): Lowest price
  - `close` (f64): Closing price
  - `volume` (s64): Trading volume
  - `adj_close` (f64): Adjusted closing price (when available)
  - `market_cap` (f64): Market capitalization (crypto only)
  - `provider` (string): Data source provider
  - `currency` (string): Price currency
  - `timezone` (string): Original timezone
  """
  @spec standardize_history_schema(DataFrame.t(), keyword()) ::
          {:ok, DataFrame.t()} | {:error, term()}
  def standardize_history_schema(df, opts \\ []) do
    provider = opts[:provider] || "unknown"
    currency = opts[:currency] || "usd"
    timezone = opts[:timezone] || "UTC"

    try do
      standardized_df =
        df
        |> ensure_required_columns([
          :symbol,
          :timestamp,
          :open,
          :high,
          :low,
          :close,
          :volume,
          :adj_close,
          :market_cap
        ])
        |> normalize_timestamps()
        |> normalize_prices([:open, :high, :low, :close, :adj_close])
        |> normalize_volumes()
        |> add_metadata_columns(provider: provider, currency: currency, timezone: timezone)
        |> reorder_columns(@standard_history_columns)

      {:ok, standardized_df}
    rescue
      error ->
        Logger.error("Failed to standardize history schema: #{inspect(error)}")
        {:error, {:schema_error, error}}
    end
  end

  @doc """
  Standardizes quote data DataFrame to consistent schema.

  ## Standard Quote Data Schema

  - `symbol` (string): Stock/crypto symbol
  - `price` (f64): Current price
  - `change` (f64): Absolute price change
  - `change_percent` (f64): Percentage change
  - `volume` (s64): Current/24h volume
  - `high_24h` (f64): 24-hour high price
  - `low_24h` (f64): 24-hour low price
  - `market_cap` (f64): Market capitalization (when available)
  - `timestamp` (datetime): UTC timestamp
  - `provider` (string): Data source provider
  - `currency` (string): Quote currency
  - `market_state` (string): Market state (open/closed/pre/post)
  """
  @spec standardize_quote_schema(DataFrame.t(), keyword()) ::
          {:ok, DataFrame.t()} | {:error, term()}
  def standardize_quote_schema(df, opts \\ []) do
    provider = opts[:provider] || "unknown"
    currency = opts[:currency] || "usd"

    try do
      standardized_df =
        df
        |> ensure_required_columns([
          :symbol,
          :price,
          :timestamp,
          :change,
          :change_percent,
          :volume,
          :high_24h,
          :low_24h,
          :market_cap,
          :market_state
        ])
        |> normalize_timestamps()
        |> normalize_prices([:price, :change, :high_24h, :low_24h, :market_cap])
        |> normalize_volumes()
        |> normalize_change_percent()
        |> add_metadata_columns(provider: provider, currency: currency)
        |> reorder_columns(@standard_quote_columns)

      {:ok, standardized_df}
    rescue
      error ->
        Logger.error("Failed to standardize quote schema: #{inspect(error)}")
        {:error, {:schema_error, error}}
    end
  end

  @doc """
  Standardizes search results DataFrame to consistent schema.

  ## Standard Search Results Schema

  - `symbol` (string): Trading symbol
  - `name` (string): Full company/asset name
  - `type` (string): Asset type (stock, etf, crypto, forex, index)
  - `exchange` (string): Primary exchange
  - `currency` (string): Trading currency
  - `country` (string): Country/region
  - `sector` (string): Business sector (when available)
  - `industry` (string): Industry classification (when available)
  - `market_cap` (f64): Market capitalization (when available)
  - `provider` (string): Data source provider
  - `match_score` (f64): Search relevance score (0.0 - 1.0)
  """
  @spec standardize_search_schema(DataFrame.t(), keyword()) ::
          {:ok, DataFrame.t()} | {:error, term()}
  def standardize_search_schema(df, opts \\ []) do
    provider = opts[:provider] || "unknown"

    try do
      standardized_df =
        df
        |> ensure_required_columns([
          :symbol,
          :name,
          :type,
          :exchange,
          :currency,
          :country,
          :sector,
          :industry,
          :market_cap,
          :match_score
        ])
        |> normalize_asset_types()
        |> normalize_match_scores()
        |> add_metadata_columns(provider: provider)
        |> reorder_columns(@standard_search_columns)

      {:ok, standardized_df}
    rescue
      error ->
        Logger.error("Failed to standardize search schema: #{inspect(error)}")
        {:error, {:schema_error, error}}
    end
  end

  # ========== PRIVATE HELPER FUNCTIONS ==========

  defp normalize_interval(nil, _provider), do: {:ok, nil}

  defp normalize_interval(interval, provider) when is_binary(interval) do
    case Map.get(@standard_intervals, interval) do
      nil -> {:error, {:invalid_interval, interval}}
      translations -> {:ok, Map.get(translations, provider, interval)}
    end
  end

  defp normalize_interval(interval, _provider), do: {:error, {:invalid_interval, interval}}

  defp normalize_period(nil, _provider), do: {:ok, []}

  defp normalize_period(period, provider) when is_binary(period) do
    case Map.get(@standard_periods, period) do
      nil ->
        {:error, {:invalid_period, period}}

      period_info ->
        case provider do
          :yahoo_finance -> {:ok, [period: period_info[:yahoo]]}
          :coin_gecko -> {:ok, [days: period_info[:coin_gecko] || period_info[:days]]}
          :binance -> period_to_date_range(period_info[:days])
          _ -> period_to_date_range(period_info[:days])
        end
    end
  end

  defp normalize_period(period, _provider), do: {:error, {:invalid_period, period}}

  defp normalize_dates(nil, nil), do: {:ok, []}

  defp normalize_dates(start_date, end_date) do
    with {:ok, start_dt} <- parse_date(start_date),
         {:ok, end_dt} <- parse_date(end_date),
         :ok <- validate_date_range(start_dt, end_dt) do
      {:ok, [start_date: start_dt, end_date: end_dt]}
    else
      error -> error
    end
  end

  defp normalize_currency(nil, _provider), do: {:ok, "usd"}

  defp normalize_currency(currency, _provider) when currency in ~w[usd eur btc eth],
    do: {:ok, currency}

  defp normalize_currency(currency, _provider), do: {:error, {:invalid_currency, currency}}

  defp normalize_limit(nil, _provider), do: {:ok, nil}

  defp normalize_limit(limit, _provider) when is_integer(limit) and limit > 0 and limit <= 5000,
    do: {:ok, limit}

  defp normalize_limit(limit, _provider), do: {:error, {:invalid_limit, limit}}

  defp parse_date(nil), do: {:ok, nil}
  defp parse_date(%Date{} = date), do: {:ok, date}
  defp parse_date(%DateTime{} = dt), do: {:ok, DateTime.to_date(dt)}

  defp parse_date(date_string) when is_binary(date_string) do
    case Date.from_iso8601(date_string) do
      {:ok, date} -> {:ok, date}
      {:error, _} -> {:error, {:invalid_date, date_string}}
    end
  end

  defp parse_date(date), do: {:error, {:invalid_date, date}}

  defp validate_date_range(%Date{} = start_date, %Date{} = end_date) when start_date > end_date,
    do: {:error, :invalid_date_range}

  defp validate_date_range(_start_date, _end_date), do: :ok

  defp period_to_date_range(:max) do
    end_date = Date.utc_today()
    # 10 years default for max
    start_date = Date.add(end_date, -3650)
    {:ok, [start_date: start_date, end_date: end_date]}
  end

  defp period_to_date_range(days) when is_integer(days) do
    end_date = Date.utc_today()
    start_date = Date.add(end_date, -days)
    {:ok, [start_date: start_date, end_date: end_date]}
  end

  # DataFrame transformation helpers

  defp ensure_required_columns(df, required_columns) do
    existing_columns = DataFrame.names(df)

    Enum.reduce(required_columns, df, fn col_atom, acc_df ->
      col_name = Atom.to_string(col_atom)

      if col_name in existing_columns do
        acc_df
      else
        # Add missing column with null values
        null_series = Series.from_list(List.duplicate(nil, DataFrame.n_rows(acc_df)))
        DataFrame.put(acc_df, col_name, null_series)
      end
    end)
  end

  defp normalize_timestamps(df) do
    if "timestamp" in DataFrame.names(df) do
      timestamp_series =
        df["timestamp"]
        |> Series.transform(fn
          nil -> nil
          ts when is_binary(ts) -> parse_timestamp_string(ts)
          %DateTime{} = dt -> dt
          %NaiveDateTime{} = ndt -> DateTime.from_naive!(ndt, "UTC")
          unix_timestamp when is_integer(unix_timestamp) -> DateTime.from_unix!(unix_timestamp)
          # Fallback
          _ -> nil
        end)

      DataFrame.put(df, "timestamp", timestamp_series)
    else
      df
    end
  end

  defp normalize_prices(df, price_columns) do
    Enum.reduce(price_columns, df, fn col_atom, acc_df ->
      col_name = Atom.to_string(col_atom)

      if col_name in DataFrame.names(df) do
        price_series = acc_df[col_name] |> Series.transform(&normalize_price_value/1)
        DataFrame.put(acc_df, col_name, price_series)
      else
        acc_df
      end
    end)
  end

  defp normalize_price_value(nil), do: nil
  defp normalize_price_value(price) when is_number(price), do: price / 1.0

  defp normalize_price_value(price) when is_binary(price) do
    case Float.parse(price) do
      {float_val, _} -> float_val
      :error -> nil
    end
  end

  defp normalize_price_value(_), do: nil

  defp normalize_volumes(df) do
    if "volume" in DataFrame.names(df) do
      volume_series = df["volume"] |> Series.transform(&normalize_volume_value/1)
      DataFrame.put(df, "volume", volume_series)
    else
      df
    end
  end

  defp normalize_volume_value(nil), do: nil
  defp normalize_volume_value(vol) when is_integer(vol), do: vol
  defp normalize_volume_value(vol) when is_float(vol), do: trunc(vol)

  defp normalize_volume_value(vol) when is_binary(vol) do
    case Integer.parse(vol) do
      {int_val, _} -> int_val
      :error -> nil
    end
  end

  defp normalize_volume_value(_), do: nil

  defp normalize_change_percent(df) do
    if "change_percent" in DataFrame.names(df) do
      change_series = df["change_percent"] |> Series.transform(&normalize_percent_value/1)
      DataFrame.put(df, "change_percent", change_series)
    else
      df
    end
  end

  defp normalize_percent_value(nil), do: nil
  defp normalize_percent_value(pct) when is_number(pct), do: Float.round(pct, 4)

  defp normalize_percent_value(pct_string) when is_binary(pct_string) do
    clean_pct = String.replace(pct_string, ~r/[%\s]/, "")

    case Float.parse(clean_pct) do
      {float_val, _} -> Float.round(float_val, 4)
      :error -> nil
    end
  end

  defp normalize_percent_value(_), do: nil

  defp normalize_asset_types(df) do
    if "type" in DataFrame.names(df) do
      type_series = df["type"] |> Series.transform(&normalize_asset_type_value/1)
      DataFrame.put(df, "type", type_series)
    else
      df
    end
  end

  defp normalize_asset_type_value(nil), do: "unknown"

  defp normalize_asset_type_value(type) when is_binary(type) do
    case String.downcase(type) do
      t when t in ~w[stock equity common] -> "stock"
      t when t in ~w[etf fund] -> "etf"
      t when t in ~w[crypto cryptocurrency digital] -> "crypto"
      t when t in ~w[forex currency fx] -> "forex"
      t when t in ~w[index] -> "index"
      t when t in ~w[option derivative] -> "option"
      t when t in ~w[bond fixed income] -> "bond"
      _ -> type
    end
  end

  defp normalize_asset_type_value(_), do: "unknown"

  defp normalize_match_scores(df) do
    if "match_score" in DataFrame.names(df) do
      # Keep as-is if already present
      df
    else
      # Add default match score based on position (first result = highest score)
      rows = DataFrame.n_rows(df)

      scores = generated_match_scores(rows)

      score_series = Series.from_list(scores)
      DataFrame.put(df, "match_score", score_series)
    end
  end

  defp add_metadata_columns(df, metadata) do
    Enum.reduce(metadata, df, fn {key, value}, acc_df ->
      col_name = Atom.to_string(key)
      rows = DataFrame.n_rows(acc_df)
      # Convert atoms to strings for proper Series creation
      string_value = if is_atom(value), do: Atom.to_string(value), else: value
      value_series = Series.from_list(List.duplicate(string_value, rows))
      DataFrame.put(acc_df, col_name, value_series)
    end)
  end

  defp generated_match_scores(0), do: []

  defp generated_match_scores(rows) do
    Enum.map(1..rows, fn i -> max(0.0, Float.round(1.0 - (i - 1) * 0.1, 2)) end)
  end

  defp reorder_columns(df, standard_order) do
    existing_columns = DataFrame.names(df)
    # Only keep standard columns for consistent schema across providers
    ordered_columns = Enum.filter(standard_order, &(&1 in existing_columns))

    DataFrame.select(df, ordered_columns)
  end

  defp parse_timestamp_string(ts_string) do
    # Handle various timestamp formats
    cond do
      String.match?(ts_string, ~r/^\d{4}-\d{2}-\d{2}$/) ->
        {:ok, date} = Date.from_iso8601(ts_string)
        DateTime.new!(date, ~T[00:00:00], "UTC")

      String.contains?(ts_string, "T") ->
        case DateTime.from_iso8601(ts_string) do
          {:ok, dt, _} -> dt
          {:error, _} -> nil
        end

      true ->
        nil
    end
  end

  # ========== PUBLIC HELPER FUNCTIONS ==========

  @doc """
  Lists all supported standard intervals.
  """
  @spec supported_intervals() :: [String.t()]
  def supported_intervals, do: Map.keys(@standard_intervals)

  @doc """
  Lists all supported standard periods.
  """
  @spec supported_periods() :: [String.t()]
  def supported_periods, do: Map.keys(@standard_periods)

  @doc """
  Lists all supported currencies.
  """
  @spec supported_currencies() :: [String.t()]
  def supported_currencies, do: ~w[usd eur btc eth]

  @doc """
  Validates parameter compatibility with provider.
  """
  @spec validate_provider_support(keyword(), atom()) :: :ok | {:error, term()}
  def validate_provider_support(params, provider) do
    # Add provider-specific validation logic
    case provider do
      :yahoo_finance -> validate_yahoo_params(params)
      :alpha_vantage -> validate_alpha_vantage_params(params)
      :binance -> validate_binance_params(params)
      :coin_gecko -> validate_coin_gecko_params(params)
      :twelve_data -> validate_twelve_data_params(params)
      _ -> :ok
    end
  end

  # Provider-specific validation functions
  defp validate_yahoo_params(params) do
    # Yahoo Finance specific validation
    if params[:interval] in ["1m", "5m"] and is_nil(params[:period]) and
         is_nil(params[:start_date]) do
      {:error, "Intraday intervals require explicit date range"}
    else
      :ok
    end
  end

  defp validate_alpha_vantage_params(_params), do: :ok
  defp validate_binance_params(_params), do: :ok
  defp validate_coin_gecko_params(_params), do: :ok
  defp validate_twelve_data_params(_params), do: :ok
end
