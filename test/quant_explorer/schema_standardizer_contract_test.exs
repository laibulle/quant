defmodule Quant.Explorer.SchemaStandardizerContractTest do
  use ExUnit.Case, async: true

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
end
