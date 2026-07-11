defmodule Quant.Explorer.DataTransformer do
  @moduledoc """
  Data normalization utilities for converting raw API responses into standardized Explorer DataFrames.

  This module handles the transformation of various data formats (JSON, CSV, maps, lists)
  from different providers into consistent DataFrame schemas that can be used across
  the entire library.
  """

  alias Explorer.DataFrame
  require Logger

  @type raw_data :: map() | list() | binary()
  @type schema :: :history | :quote | :search | :info

  @doc """
  Transforms raw historical data into a standardized DataFrame.

  Expected columns in output:
  - symbol (string): Stock/crypto symbol
  - timestamp (datetime): Data timestamp
  - open (f64): Opening price
  - high (f64): High price
  - low (f64): Low price
  - close (f64): Closing price
  - volume (s64): Trading volume
  - adj_close (f64): Adjusted closing price (optional)
  """
  @spec transform_history(raw_data(), String.t(), keyword()) ::
          {:ok, DataFrame.t()} | {:error, term()}
  def transform_history(data, symbol, opts \\ []) do
    df = do_transform_history(data, symbol, opts)
    validate_history_schema(df)
  rescue
    error ->
      Logger.error("Failed to transform history data: #{inspect(error)}")
      {:error, {:transform_error, error}}
  end

  @doc """
  Transforms raw quote data into a standardized DataFrame.

  Expected columns in output:
  - symbol (string): Stock/crypto symbol
  - price (f64): Current price
  - change (f64): Price change
  - change_percent (f64): Percentage change
  - volume (s64): Current volume
  - timestamp (datetime): Quote timestamp
  """
  @spec transform_quote(raw_data(), String.t() | [String.t()], keyword()) ::
          {:ok, DataFrame.t()} | {:error, term()}
  def transform_quote(data, symbols, opts \\ []) do
    df = do_transform_quote(data, symbols, opts)
    validate_quote_schema(df)
  rescue
    error ->
      Logger.error("Failed to transform quote data: #{inspect(error)}")
      {:error, {:transform_error, error}}
  end

  @doc """
  Transforms raw search results into a standardized DataFrame.

  Expected columns in output:
  - symbol (string): Trading symbol
  - name (string): Company/asset name
  - type (string): Asset type (stock, etf, crypto, etc.)
  - exchange (string): Trading exchange (optional)
  """
  @spec transform_search(raw_data(), keyword()) :: {:ok, DataFrame.t()} | {:error, term()}
  def transform_search(data, opts \\ []) do
    df = do_transform_search(data, opts)
    validate_search_schema(df)
  rescue
    error ->
      Logger.error("Failed to transform search data: #{inspect(error)}")
      {:error, {:transform_error, error}}
  end

  @doc """
  Normalizes timestamps from various formats to DateTime.

  Handles:
  - Unix timestamps (seconds/milliseconds)
  - ISO 8601 strings
  - Date strings in various formats
  - Already parsed DateTime structs
  """
  @spec normalize_timestamp(term()) :: DateTime.t() | nil
  def normalize_timestamp(nil), do: nil
  def normalize_timestamp(%DateTime{} = dt), do: dt

  def normalize_timestamp(timestamp) when is_integer(timestamp) do
    # Handle both seconds and milliseconds timestamps
    timestamp = if timestamp > 1_000_000_000_000, do: div(timestamp, 1000), else: timestamp

    case DateTime.from_unix(timestamp) do
      {:ok, dt} -> dt
      {:error, _} -> nil
    end
  end

  def normalize_timestamp(timestamp) when is_binary(timestamp) do
    # Try various datetime parsing strategies
    with {:error, _} <- DateTime.from_iso8601(timestamp),
         {:error, _} <- parse_date_string(timestamp) do
      nil
    else
      {:ok, dt, _offset} -> dt
      {:ok, dt} -> dt
    end
  end

  def normalize_timestamp(_), do: nil

  @doc """
  Normalizes numeric values, handling strings, floats, integers, and nil.
  """
  @spec normalize_number(term()) :: float() | nil
  def normalize_number(nil), do: nil
  def normalize_number(n) when is_number(n), do: n / 1

  def normalize_number(n) when is_binary(n) do
    case Float.parse(n) do
      {num, ""} -> num
      :error -> nil
      _ -> nil
    end
  end

  def normalize_number(_), do: nil

  @doc """
  Normalizes volume values, typically as integers.
  """
  @spec normalize_volume(term()) :: integer() | nil
  def normalize_volume(nil), do: nil
  def normalize_volume(n) when is_integer(n), do: n
  def normalize_volume(n) when is_float(n), do: round(n)

  def normalize_volume(n) when is_binary(n) do
    case Integer.parse(n) do
      {num, ""} ->
        num

      _ ->
        case Float.parse(n) do
          {num, ""} -> round(num)
          :error -> nil
          _ -> nil
        end
    end
  end

  def normalize_volume(_), do: nil

  # Private transformation functions

  defp do_transform_history(data, symbol, opts) when is_list(data) do
    # Transform list of maps to DataFrame
    rows = Enum.map(data, &normalize_history_row(&1, symbol, opts))
    DataFrame.new(rows)
  end

  defp do_transform_history(%{} = data, symbol, opts) do
    # Handle map format (e.g., keys are timestamps, values are OHLCV data)
    rows =
      data
      |> Enum.map(fn {timestamp, ohlcv_data} ->
        normalize_history_row(Map.put(ohlcv_data, :timestamp, timestamp), symbol, opts)
      end)

    DataFrame.new(rows)
  end

  defp normalize_history_row(row, symbol, _opts) do
    %{
      "symbol" => symbol,
      "timestamp" => normalize_timestamp(Map.get(row, :timestamp) || Map.get(row, "timestamp")),
      "open" => normalize_number(Map.get(row, :open) || Map.get(row, "open")),
      "high" => normalize_number(Map.get(row, :high) || Map.get(row, "high")),
      "low" => normalize_number(Map.get(row, :low) || Map.get(row, "low")),
      "close" => normalize_number(Map.get(row, :close) || Map.get(row, "close")),
      "volume" => normalize_volume(Map.get(row, :volume) || Map.get(row, "volume")),
      "adj_close" => normalize_number(Map.get(row, :adj_close) || Map.get(row, "adj_close"))
    }
  end

  defp do_transform_quote(data, _symbols, opts) when is_list(data) do
    rows = Enum.map(data, &normalize_quote_row(&1, opts))
    DataFrame.new(rows)
  end

  defp do_transform_quote(%{} = data, symbol, opts) when is_binary(symbol) do
    row = normalize_quote_row(Map.put(data, :symbol, symbol), opts)
    DataFrame.new([row])
  end

  defp normalize_quote_row(row, _opts) do
    %{
      "symbol" => Map.get(row, :symbol) || Map.get(row, "symbol"),
      "price" => normalize_number(Map.get(row, :price) || Map.get(row, "price")),
      "change" => normalize_number(Map.get(row, :change) || Map.get(row, "change")),
      "change_percent" =>
        normalize_number(Map.get(row, :change_percent) || Map.get(row, "change_percent")),
      "volume" => normalize_volume(Map.get(row, :volume) || Map.get(row, "volume")),
      "timestamp" => normalize_timestamp(Map.get(row, :timestamp) || Map.get(row, "timestamp"))
    }
  end

  defp do_transform_search(data, opts) when is_list(data) do
    rows = Enum.map(data, &normalize_search_row(&1, opts))
    DataFrame.new(rows)
  end

  defp normalize_search_row(row, _opts) do
    %{
      "symbol" => Map.get(row, :symbol) || Map.get(row, "symbol"),
      "name" => Map.get(row, :name) || Map.get(row, "name"),
      "type" => Map.get(row, :type) || Map.get(row, "type") || "unknown",
      "exchange" => Map.get(row, :exchange) || Map.get(row, "exchange")
    }
  end

  # Schema validation functions

  defp validate_history_schema(df) do
    required_columns = ["symbol", "timestamp", "open", "high", "low", "close", "volume"]

    case validate_required_columns(df, required_columns) do
      :ok -> {:ok, df}
      error -> error
    end
  end

  defp validate_quote_schema(df) do
    required_columns = ["symbol", "price", "timestamp"]

    case validate_required_columns(df, required_columns) do
      :ok -> {:ok, df}
      error -> error
    end
  end

  defp validate_search_schema(df) do
    required_columns = ["symbol", "name"]

    case validate_required_columns(df, required_columns) do
      :ok -> {:ok, df}
      error -> error
    end
  end

  defp validate_required_columns(df, required_columns) do
    existing_columns = DataFrame.names(df)
    missing_columns = required_columns -- existing_columns

    case missing_columns do
      [] -> :ok
      missing -> {:error, {:missing_columns, missing}}
    end
  end

  # Helper functions

  defp parse_date_string(date_str) do
    # Try common date formats using built-in DateTime
    case DateTime.from_iso8601(date_str) do
      {:ok, datetime, _offset} ->
        {:ok, datetime}

      {:error, _} ->
        case Date.from_iso8601(date_str) do
          {:ok, date} -> {:ok, DateTime.new!(date, ~T[00:00:00])}
          {:error, _} -> {:error, :invalid_date}
        end
    end
  end

  @doc """
  Converts CSV string to DataFrame with proper column types.
  """
  @spec csv_to_dataframe(binary(), keyword()) :: {:ok, DataFrame.t()} | {:error, term()}
  def csv_to_dataframe(csv_data, _opts \\ []) do
    # Use built-in string parsing (simple CSV parsing)
    rows = parse_csv_lines(csv_data)

    case rows do
      [] ->
        {:error, :empty_data}

      [headers | data_rows] ->
        # Convert to list of maps
        maps =
          Enum.map(data_rows, fn row ->
            headers
            |> Enum.zip(row)
            |> Enum.into(%{})
          end)

        df = DataFrame.new(maps)
        {:ok, df}
    end
  rescue
    error ->
      Logger.error("Failed to parse CSV data: #{inspect(error)}")
      {:error, {:csv_parse_error, error}}
  end

  @doc """
  Filters out rows with invalid or missing critical data.
  """
  @spec clean_dataframe(DataFrame.t(), schema()) :: DataFrame.t()
  def clean_dataframe(df, :history) do
    require Explorer.DataFrame

    df
    |> DataFrame.filter(not is_nil(timestamp) and not is_nil(close) and close > 0)
  end

  def clean_dataframe(df, :quote) do
    require Explorer.DataFrame

    df
    |> DataFrame.filter(not is_nil(price) and price > 0 and not is_nil(symbol))
  end

  def clean_dataframe(df, :search) do
    require Explorer.DataFrame

    df
    |> DataFrame.filter(not is_nil(symbol) and not is_nil(name))
  end

  def clean_dataframe(df, _schema), do: df

  # Simple CSV parsing function using built-in string operations
  defp parse_csv_lines(csv_data) do
    case String.trim(csv_data) do
      "" ->
        []

      content ->
        content
        |> String.split("\n")
        |> Enum.map(&parse_csv_line/1)
    end
  end

  defp parse_csv_line(line) do
    # Simple CSV parsing (handles basic cases)
    line
    |> String.split(",")
    |> Enum.map(&String.trim/1)
    |> Enum.map(fn cell ->
      # Remove quotes if present
      cell
      |> String.trim("\"")
      |> String.trim("'")
    end)
  end
end
