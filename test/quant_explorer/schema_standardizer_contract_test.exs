defmodule Quant.Explorer.SchemaStandardizerContractTest do
  use ExUnit.Case, async: true

  alias Explorer.{DataFrame, Series}
  alias Quant.Explorer.SchemaStandardizer

  test "preserves false adjusted values and translates Yahoo intervals" do
    assert {:ok, params} =
             SchemaStandardizer.standardize_params(
               [interval: "1w", period: "1y", adjusted: false],
               :yahoo_finance
             )

    assert params[:interval] == "1wk"
    assert params[:adjusted] == false
    assert params[:period] == "1y"
  end

  test "rejects inverted date ranges" do
    assert {:error, :invalid_date_range} =
             SchemaStandardizer.standardize_params(
               [start_date: ~D[2026-01-02], end_date: ~D[2026-01-01]],
               :binance
             )
  end

  test "translates universal parameters to Binance and date ranges" do
    assert {:ok, params} =
             SchemaStandardizer.standardize_params(
               [interval: "1mo", period: "1d", currency: "eur", limit: 50],
               :binance
             )

    assert params[:interval] == "1M"
    assert params[:currency] == "eur"
    assert params[:limit] == 50
    assert params[:start_date] == Date.add(Date.utc_today(), -1)
    assert params[:end_date] == Date.utc_today()
  end

  test "rejects unsupported parameters before a provider call" do
    assert {:error, "Intraday intervals require explicit date range"} =
             SchemaStandardizer.standardize_params([interval: "1m"], :yahoo_finance)

    assert {:error, {:invalid_interval, "2m"}} =
             SchemaStandardizer.standardize_params([interval: "2m"], :binance)

    assert {:error, {:invalid_period, "forever"}} =
             SchemaStandardizer.standardize_params([period: "forever"], :binance)

    assert {:error, {:invalid_currency, "gbp"}} =
             SchemaStandardizer.standardize_params([currency: "gbp"], :binance)

    assert {:error, {:invalid_limit, 0}} =
             SchemaStandardizer.standardize_params([limit: 0], :binance)
  end

  test "normalizes schemas without accepting partial numeric values" do
    history =
      DataFrame.new(%{
        "symbol" => ["TEST"],
        "timestamp" => ["2026-01-02"],
        "open" => ["12.5invalid"],
        "high" => ["13.5"],
        "low" => ["11.0"],
        "close" => ["12.0"],
        "volume" => ["100.5"]
      })

    assert {:ok, standardized_history} =
             SchemaStandardizer.standardize_history_schema(history, provider: :demo)

    assert Series.to_list(standardized_history["open"]) == [nil]
    assert Series.to_list(standardized_history["high"]) == [13.5]
    assert Series.to_list(standardized_history["volume"]) == [100]
    assert Series.to_list(standardized_history["provider"]) == ["demo"]

    quote = DataFrame.new(%{"symbol" => ["TEST"], "change_percent" => ["1.23456%invalid"]})

    assert {:ok, standardized_quote} = SchemaStandardizer.standardize_quote_schema(quote)
    assert Series.to_list(standardized_quote["change_percent"]) == [nil]
  end

  test "normalizes search asset types and generates descending match scores" do
    search =
      DataFrame.new(%{
        "symbol" => ["AAA", "BBB", "CCC"],
        "name" => ["A", "B", "C"],
        "type" => ["EQUITY", "digital", nil]
      })

    assert {:ok, standardized_search} =
             SchemaStandardizer.standardize_search_schema(search, provider: :demo)

    assert Series.to_list(standardized_search["type"]) == ["stock", "crypto", "unknown"]
    assert Series.to_list(standardized_search["match_score"]) == [1.0, 0.9, 0.8]
    assert Series.to_list(standardized_search["provider"]) == ["demo", "demo", "demo"]
  end
end
