defmodule Quant.Explorer.DataTransformerTest do
  use ExUnit.Case, async: true

  alias Explorer.{DataFrame, Series}
  alias Quant.Explorer.DataTransformer

  test "normalizes timestamps, numbers and volumes without inventing values" do
    assert ~U[2024-01-01 00:00:00Z] = DataTransformer.normalize_timestamp("2024-01-01")
    assert ~U[2024-01-01 00:00:00Z] = DataTransformer.normalize_timestamp(1_704_067_200)
    assert nil == DataTransformer.normalize_timestamp("not-a-date")

    assert 12.5 == DataTransformer.normalize_number("12.5")
    assert nil == DataTransformer.normalize_number("12.5USD")
    assert 101 == DataTransformer.normalize_volume("100.6")
    assert nil == DataTransformer.normalize_volume("unknown")
  end

  test "transforms history maps into normalized DataFrames" do
    raw = %{
      "2024-01-01" => %{open: "10.0", high: "11.0", low: "9.0", close: "10.5", volume: "100"}
    }

    assert {:ok, dataframe} = DataTransformer.transform_history(raw, "AAPL")
    [row] = DataFrame.to_rows(dataframe)

    assert row["symbol"] == "AAPL"
    assert row["close"] == 10.5
    assert row["volume"] == 100
  end

  test "does not fabricate a quote timestamp when upstream omits it" do
    assert {:ok, dataframe} = DataTransformer.transform_quote(%{price: "10.5"}, "AAPL")

    assert [nil] = dataframe |> DataFrame.pull("timestamp") |> Series.to_list()
  end

  test "transforms list payloads for history, quotes and search results" do
    history = [
      %{
        "timestamp" => 1_704_067_200_000,
        "open" => "10.0",
        "high" => "11.0",
        "low" => "9.0",
        "close" => "10.5",
        "volume" => 100.4
      }
    ]

    assert {:ok, history_dataframe} = DataTransformer.transform_history(history, "AAPL")
    [history_row] = DataFrame.to_rows(history_dataframe)
    assert history_row["symbol"] == "AAPL"
    assert DateTime.compare(history_row["timestamp"], ~U[2024-01-01 00:00:00Z]) == :eq
    assert history_row["volume"] == 100

    quotes = [%{"symbol" => "AAPL", "price" => "10.5", "timestamp" => "2024-01-01T00:00:00Z"}]

    assert {:ok, quote_dataframe} = DataTransformer.transform_quote(quotes, ["AAPL"])
    assert [%{"symbol" => "AAPL", "price" => 10.5}] = DataFrame.to_rows(quote_dataframe)

    search = [%{"symbol" => "AAPL", "name" => "Apple Inc."}]
    assert {:ok, search_dataframe} = DataTransformer.transform_search(search)

    assert [%{"symbol" => "AAPL", "name" => "Apple Inc.", "type" => "unknown"}] =
             DataFrame.to_rows(search_dataframe)
  end

  test "parses basic CSV data and cleans invalid history rows" do
    assert {:ok, dataframe} = DataTransformer.csv_to_dataframe("symbol,price\nAAPL,10.5\n")
    assert DataFrame.to_rows(dataframe) == [%{"symbol" => "AAPL", "price" => "10.5"}]

    history =
      DataFrame.new(%{
        timestamp: [~U[2024-01-01 00:00:00Z], nil],
        close: [10.0, 0.0]
      })

    assert 1 == history |> DataTransformer.clean_dataframe(:history) |> DataFrame.n_rows()

    quotes = DataFrame.new(%{symbol: ["AAPL", nil], price: [10.0, 0.0]})
    assert 1 == quotes |> DataTransformer.clean_dataframe(:quote) |> DataFrame.n_rows()

    search = DataFrame.new(%{symbol: ["AAPL", nil], name: ["Apple", "Missing"]})
    assert 1 == search |> DataTransformer.clean_dataframe(:search) |> DataFrame.n_rows()

    assert {:error, :empty_data} = DataTransformer.csv_to_dataframe("\n")
  end
end
