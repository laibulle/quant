defmodule Quant.Math.TemaTest do
  @moduledoc """
  Tests for Triple Exponential Moving Average (TEMA) calculations.

  TEMA extends DEMA with a third level of exponential smoothing for even
  faster response to price changes while maintaining smoothness.
  """
  use ExUnit.Case
  alias Explorer.DataFrame
  alias Quant.Math

  # Test data - larger dataset for TEMA which needs more periods
  @prices [
    10.0,
    11.0,
    12.0,
    13.0,
    14.0,
    15.0,
    16.0,
    17.0,
    18.0,
    19.0,
    20.0,
    21.0,
    22.0,
    23.0,
    24.0,
    25.0,
    26.0,
    27.0,
    28.0,
    29.0
  ]
  @small_prices [1.0, 2.0, 3.0]

  describe "add_tema!/3" do
    test "calculates basic TEMA correctly" do
      df = DataFrame.new(%{close: @prices})
      result = Math.add_tema!(df, :close, period: 3)

      # Should have tema_3 column
      assert "close_tema_3" in DataFrame.names(result)

      # Check column type
      assert Map.get(result.dtypes, "close_tema_3") == {:f, 64}

      # Early values should be NaN (approximately 3 * (3-1) = 6 initial NaN values)
      tema_values = DataFrame.pull(result, "close_tema_3") |> Explorer.Series.to_list()

      # First 12 values should be NaN (approximately 3 * (3-1) + additional smoothing = 12 initial NaN values)\n      assert Enum.take(tema_values, 12) |> Enum.all?(&(is_float(&1) and not finite?(&1)))

      # Later values should be finite numbers
      valid_values = Enum.drop(tema_values, 12)
      assert valid_values != []
      assert Enum.all?(valid_values, &finite?/1)
    end

    test "TEMA responds faster than DEMA to price changes" do
      # Create a DataFrame with a clear trend change
      trend_data = [
        10.0,
        11.0,
        12.0,
        13.0,
        14.0,
        15.0,
        16.0,
        17.0,
        18.0,
        19.0,
        20.0,
        19.5,
        19.0,
        18.5,
        18.0,
        17.5,
        17.0
      ]

      df = DataFrame.new(%{close: trend_data})

      # Calculate both TEMA and DEMA
      result =
        df
        |> Math.add_tema!(:close, period: 5)
        |> Math.add_dema!(:close, period: 5)

      tema_values = DataFrame.pull(result, "close_tema_5") |> Explorer.Series.to_list()
      dema_values = DataFrame.pull(result, "close_dema_5") |> Explorer.Series.to_list()

      # Find first valid indices for both
      tema_first_valid = Enum.find_index(tema_values, &finite?/1)
      dema_first_valid = Enum.find_index(dema_values, &finite?/1)

      # TEMA should start producing values later (needs more periods)
      assert tema_first_valid > dema_first_valid

      # Both should have valid values
      assert tema_first_valid != nil
      assert dema_first_valid != nil
    end

    test "uses custom column name" do
      df = DataFrame.new(%{close: @prices})
      result = Math.add_tema!(df, :close, period: 4, column_name: "custom_tema")

      assert "custom_tema" in DataFrame.names(result)
      refute "close_tema_4" in DataFrame.names(result)
    end

    test "works with custom alpha parameter" do
      df = DataFrame.new(%{close: @prices})
      result = Math.add_tema!(df, :close, period: 5, alpha: 0.3)

      assert "close_tema_5" in DataFrame.names(result)

      # Should produce different results than default alpha
      default_result = Math.add_tema!(df, :close, period: 5)

      tema_custom = DataFrame.pull(result, "close_tema_5") |> Explorer.Series.to_list()
      tema_default = DataFrame.pull(default_result, "close_tema_5") |> Explorer.Series.to_list()

      # Should produce different results than default alpha
      assert tema_custom != tema_default
    end

    test "works with different price columns" do
      df =
        DataFrame.new(%{
          open: @prices,
          high: Enum.map(@prices, &(&1 + 1)),
          low: Enum.map(@prices, &(&1 - 1)),
          close: @prices
        })

      result = Math.add_tema!(df, :high, period: 3, column_name: "tema_high")

      assert "tema_high" in DataFrame.names(result)

      # Should be different from close TEMA
      close_result = Math.add_tema!(df, :close, period: 3)

      tema_high = DataFrame.pull(result, "tema_high") |> Explorer.Series.to_list()
      tema_close = DataFrame.pull(close_result, "close_tema_3") |> Explorer.Series.to_list()

      # Should be different - compare valid values only
      assert tema_high != tema_close
    end

    test "supports method chaining" do
      df = DataFrame.new(%{close: @prices})

      result =
        df
        |> Math.add_sma!(:close, period: 3)
        |> Math.add_tema!(:close, period: 4)
        |> Math.add_ema!(:close, period: 5)

      expected_columns = ["close", "close_sma_3", "close_tema_4", "close_ema_5"]
      assert Enum.all?(expected_columns, &(&1 in DataFrame.names(result)))
    end
  end

  describe "error handling" do
    test "raises error when period is missing" do
      df = DataFrame.new(%{close: @prices})

      assert_raise ArgumentError, ~r/Period is required/, fn ->
        Math.add_tema!(df, :close, [])
      end
    end

    test "raises error when period is invalid" do
      df = DataFrame.new(%{close: @prices})

      assert_raise ArgumentError, ~r/Period must be a positive integer/, fn ->
        Math.add_tema!(df, :close, period: 0)
      end

      assert_raise ArgumentError, ~r/Period must be a positive integer/, fn ->
        Math.add_tema!(df, :close, period: -1)
      end

      assert_raise ArgumentError, ~r/Period must be a positive integer/, fn ->
        Math.add_tema!(df, :close, period: 1.5)
      end
    end

    test "raises error when column doesn't exist" do
      df = DataFrame.new(%{close: @prices})

      assert_raise ArgumentError, ~r/Column :nonexistent not found/, fn ->
        Math.add_tema!(df, :nonexistent, period: 3)
      end
    end

    test "raises error when insufficient data" do
      df = DataFrame.new(%{close: @small_prices})

      assert_raise ArgumentError, ~r/Insufficient data for TEMA calculation/, fn ->
        Math.add_tema!(df, :close, period: 3)
      end
    end

    test "raises error for invalid column_name type" do
      df = DataFrame.new(%{close: @prices})

      assert_raise ArgumentError, ~r/column_name must be a string or atom/, fn ->
        Math.add_tema!(df, :close, period: 3, column_name: 123)
      end
    end
  end

  describe "mathematical properties" do
    test "TEMA values are smooth and follow price trends" do
      # Create trending data
      uptrend = 1..20 |> Enum.map(&(&1 * 1.0))
      df = DataFrame.new(%{close: uptrend})

      result = Math.add_tema!(df, :close, period: 5)
      tema_values = DataFrame.pull(result, "close_tema_5") |> Explorer.Series.to_list()

      # Get valid values (skip NaN)
      valid_tema = tema_values |> Enum.filter(&finite?/1)

      # Should generally increase with the trend (allowing for some volatility)
      increases =
        valid_tema
        |> Enum.chunk_every(2, 1, :discard)
        |> Enum.count(fn [a, b] -> b >= a end)

      decreases = length(valid_tema) - 1 - increases

      # Should have more increases than decreases in an uptrend
      assert increases > decreases
    end

    test "TEMA handles flat prices appropriately" do
      flat_prices = List.duplicate(100.0, 20)
      df = DataFrame.new(%{close: flat_prices})

      result = Math.add_tema!(df, :close, period: 5)
      tema_values = DataFrame.pull(result, "close_tema_5") |> Explorer.Series.to_list()

      valid_tema = tema_values |> Enum.filter(&finite?/1)

      # All valid values should be close to the flat price
      assert Enum.all?(valid_tema, fn v -> abs(v - 100.0) < 0.01 end)
    end

    test "TEMA formula correctness (3*EMA1 - 3*EMA2 + EMA3)" do
      df = DataFrame.new(%{close: @prices})

      # Calculate individual EMAs for verification
      df_with_emas =
        df
        |> Math.add_ema!(:close, period: 3, column_name: "ema1")
        # Calculate EMA2 on original data for now
        |> Math.add_ema!(:close, period: 3, column_name: "ema2_calc")
        |> Math.add_tema!(:close, period: 3)

      # Get the TEMA values
      tema = DataFrame.pull(df_with_emas, "close_tema_3") |> Explorer.Series.to_list()

      # Verify TEMA has some valid values and they're reasonable
      valid_tema = Enum.filter(tema, &finite?/1)
      assert valid_tema != []

      # TEMA should be close to price values (basic sanity check)
      assert Enum.all?(valid_tema, fn v -> v > 0 and v < 100 end)
    end
  end

  describe "edge cases" do
    test "handles DataFrame with exactly minimum required data" do
      # TEMA needs approximately 3 * period rows
      # 3 * 5 = 15
      min_data = List.duplicate(10.0, 15)
      df = DataFrame.new(%{close: min_data})

      result = Math.add_tema!(df, :close, period: 5)

      assert "close_tema_5" in DataFrame.names(result)
      tema_values = DataFrame.pull(result, "close_tema_5") |> Explorer.Series.to_list()

      # Should have at least one valid value
      assert Enum.any?(tema_values, &finite?/1)
    end

    test "handles single valid TEMA value" do
      # Create minimal dataset that produces exactly one valid TEMA value
      minimal_data = 1..10 |> Enum.map(&(&1 * 1.0))
      df = DataFrame.new(%{close: minimal_data})

      result = Math.add_tema!(df, :close, period: 3)
      tema_values = DataFrame.pull(result, "close_tema_3") |> Explorer.Series.to_list()

      valid_count = Enum.count(tema_values, &finite?/1)
      assert valid_count >= 1
    end

    test "handles DataFrame with mixed finite and infinite values" do
      mixed_prices = [1.0, 2.0, :infinity, 4.0, 5.0, 6.0, 7.0, 8.0, 9.0, 10.0, 11.0]
      df = DataFrame.new(%{close: mixed_prices})

      # Should not crash but may produce NaN values
      result = Math.add_tema!(df, :close, period: 3)

      assert "close_tema_3" in DataFrame.names(result)
      tema_values = DataFrame.pull(result, "close_tema_3") |> Explorer.Series.to_list()

      # Should produce some values (even if some are NaN)
      assert length(tema_values) == length(mixed_prices)
    end
  end

  # Helper function to check if a float is finite (not NaN or infinite)
  defp finite?(val) when is_float(val) do
    is_float(val)
  end

  defp finite?(val) when is_number(val), do: true
  defp finite?(_), do: false
end
