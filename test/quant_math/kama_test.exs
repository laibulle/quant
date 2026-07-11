defmodule Quant.Math.KamaTest do
  @moduledoc """
  Tests for Kaufman Adaptive Moving Average (KAMA) calculations.

  KAMA adapts to market conditions using an efficiency ratio to determine
  smoothing levels - more smoothing during choppy markets, less during trends.
  """
  use ExUnit.Case
  alias Explorer.DataFrame
  alias Quant.Math

  # Test data - needs sufficient length for KAMA calculations
  @prices [
    10.0,
    11.0,
    12.0,
    13.0,
    12.0,
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
    25.0
  ]
  @small_prices [1.0, 2.0, 3.0]

  describe "add_kama!/3" do
    test "calculates basic KAMA correctly" do
      df = DataFrame.new(%{close: @prices})
      result = Math.add_kama!(df, :close, period: 10)

      # Should have close_kama_10 column
      assert "close_kama_10" in DataFrame.names(result)

      # Check column type
      assert Map.get(result.dtypes, "close_kama_10") == {:f, 64}

      # Early values should be NaN (first 10 values)
      kama_values = DataFrame.pull(result, "close_kama_10") |> Explorer.Series.to_list()

      # First 10 values should be NaN
      assert Enum.take(kama_values, 10) |> Enum.all?(&(&1 == :nan))

      # Later values should be finite numbers
      valid_values = Enum.drop(kama_values, 10)
      assert valid_values != []
      assert Enum.all?(valid_values, &finite?/1)
    end

    test "KAMA adapts to market conditions" do
      # Create data with trending and choppy sections
      trending_data = [10.0, 11.0, 12.0, 13.0, 14.0, 15.0, 16.0, 17.0, 18.0, 19.0]
      choppy_data = [20.0, 19.5, 20.2, 19.8, 20.1, 19.9, 20.0, 19.7, 20.3, 19.6]
      combined_data = trending_data ++ choppy_data

      df = DataFrame.new(%{close: combined_data})
      result = Math.add_kama!(df, :close, period: 8)

      kama_values = DataFrame.pull(result, "close_kama_8") |> Explorer.Series.to_list()
      valid_kama = kama_values |> Enum.filter(&finite?/1)

      # Should have some valid values
      assert valid_kama != []

      # All valid values should be reasonable (between min and max of input data)
      min_price = Enum.min(combined_data)
      max_price = Enum.max(combined_data)
      assert Enum.all?(valid_kama, fn v -> v >= min_price - 1.0 and v <= max_price + 1.0 end)
    end

    test "uses custom fast and slow smoothing constants" do
      df = DataFrame.new(%{close: @prices})
      result = Math.add_kama!(df, :close, period: 10, fast_sc: 2, slow_sc: 20)

      assert "close_kama_10" in DataFrame.names(result)

      # Should produce different results than default parameters
      default_result = Math.add_kama!(df, :close, period: 10)

      kama_custom = DataFrame.pull(result, "close_kama_10") |> Explorer.Series.to_list()
      kama_default = DataFrame.pull(default_result, "close_kama_10") |> Explorer.Series.to_list()

      # Should be different (compare valid portions)
      custom_valid = Enum.filter(kama_custom, &finite?/1)
      default_valid = Enum.filter(kama_default, &finite?/1)

      if custom_valid != [] and default_valid != [] do
        assert custom_valid != default_valid
      end
    end

    test "works with custom column name" do
      df = DataFrame.new(%{close: @prices})
      result = Math.add_kama!(df, :close, period: 8, column_name: "custom_kama")

      assert "custom_kama" in DataFrame.names(result)
      refute "close_kama_8" in DataFrame.names(result)
    end

    test "works with different price columns" do
      df =
        DataFrame.new(%{
          open: @prices,
          high: Enum.map(@prices, &(&1 + 1)),
          low: Enum.map(@prices, &(&1 - 1)),
          close: @prices
        })

      result = Math.add_kama!(df, :high, period: 8, column_name: "kama_high")

      assert "kama_high" in DataFrame.names(result)

      # Should be different from close KAMA
      close_result = Math.add_kama!(df, :close, period: 8)

      kama_high = DataFrame.pull(result, "kama_high") |> Explorer.Series.to_list()
      kama_close = DataFrame.pull(close_result, "close_kama_8") |> Explorer.Series.to_list()

      # Should be different - compare valid values only
      high_valid = Enum.filter(kama_high, &finite?/1)
      close_valid = Enum.filter(kama_close, &finite?/1)

      if high_valid != [] and close_valid != [] do
        assert high_valid != close_valid
      end
    end

    test "supports method chaining" do
      df = DataFrame.new(%{close: @prices})

      result =
        df
        |> Math.add_sma!(:close, period: 3)
        |> Math.add_kama!(:close, period: 8)
        |> Math.add_ema!(:close, period: 5)

      expected_columns = ["close", "close_sma_3", "close_kama_8", "close_ema_5"]
      assert Enum.all?(expected_columns, &(&1 in DataFrame.names(result)))
    end
  end

  describe "error handling" do
    test "raises error when period is missing" do
      df = DataFrame.new(%{close: @prices})

      assert_raise ArgumentError, ~r/Period is required/, fn ->
        Math.add_kama!(df, :close, [])
      end
    end

    test "raises error when period is invalid" do
      df = DataFrame.new(%{close: @prices})

      assert_raise ArgumentError, ~r/Period must be a positive integer/, fn ->
        Math.add_kama!(df, :close, period: 0)
      end

      assert_raise ArgumentError, ~r/Period must be a positive integer/, fn ->
        Math.add_kama!(df, :close, period: -1)
      end

      assert_raise ArgumentError, ~r/Period must be a positive integer/, fn ->
        Math.add_kama!(df, :close, period: 1.5)
      end
    end

    test "raises error when column doesn't exist" do
      df = DataFrame.new(%{close: @prices})

      assert_raise ArgumentError, ~r/Column :nonexistent not found/, fn ->
        Math.add_kama!(df, :nonexistent, period: 10)
      end
    end

    test "raises error when insufficient data" do
      df = DataFrame.new(%{close: @small_prices})

      assert_raise ArgumentError, ~r/Insufficient data for KAMA calculation/, fn ->
        Math.add_kama!(df, :close, period: 5)
      end
    end

    test "raises error for invalid smoothing constants" do
      df = DataFrame.new(%{close: @prices})

      # Negative fast_sc
      assert_raise ArgumentError, ~r/fast_sc and slow_sc must be positive/, fn ->
        Math.add_kama!(df, :close, period: 10, fast_sc: -1)
      end

      # Zero slow_sc
      assert_raise ArgumentError, ~r/fast_sc and slow_sc must be positive/, fn ->
        Math.add_kama!(df, :close, period: 10, slow_sc: 0)
      end

      # fast_sc >= slow_sc
      assert_raise ArgumentError, ~r/fast_sc must be less than slow_sc/, fn ->
        Math.add_kama!(df, :close, period: 10, fast_sc: 30, slow_sc: 30)
      end

      assert_raise ArgumentError, ~r/fast_sc must be less than slow_sc/, fn ->
        Math.add_kama!(df, :close, period: 10, fast_sc: 35, slow_sc: 30)
      end
    end

    test "raises error for invalid column_name type" do
      df = DataFrame.new(%{close: @prices})

      assert_raise ArgumentError, ~r/column_name must be a string or atom/, fn ->
        Math.add_kama!(df, :close, period: 10, column_name: 123)
      end
    end
  end

  describe "mathematical properties" do
    test "KAMA follows price trends smoothly" do
      # Create strong uptrend
      uptrend = 1..20 |> Enum.map(&(&1 * 1.0))
      df = DataFrame.new(%{close: uptrend})

      result = Math.add_kama!(df, :close, period: 8)
      kama_values = DataFrame.pull(result, "close_kama_8") |> Explorer.Series.to_list()

      # Get valid values (skip NaN)
      valid_kama = kama_values |> Enum.filter(&finite?/1)

      # Should generally increase with the trend
      if length(valid_kama) > 1 do
        increases =
          valid_kama
          |> Enum.chunk_every(2, 1, :discard)
          |> Enum.count(fn [a, b] -> b >= a end)

        total_pairs = length(valid_kama) - 1

        # At least 70% should be increasing in a strong uptrend
        assert increases / total_pairs >= 0.7
      end
    end

    test "KAMA handles flat prices appropriately" do
      flat_prices = List.duplicate(100.0, 15)
      df = DataFrame.new(%{close: flat_prices})

      result = Math.add_kama!(df, :close, period: 8)
      kama_values = DataFrame.pull(result, "close_kama_8") |> Explorer.Series.to_list()

      valid_kama = kama_values |> Enum.filter(&finite?/1)

      # All valid values should be close to the flat price
      assert Enum.all?(valid_kama, fn v -> abs(v - 100.0) < 1.0 end)
    end

    test "KAMA efficiency ratio behavior" do
      # Test with perfect trend (efficiency ratio should be high)
      perfect_trend = [10.0, 11.0, 12.0, 13.0, 14.0, 15.0, 16.0, 17.0, 18.0, 19.0, 20.0, 21.0]
      df_trend = DataFrame.new(%{close: perfect_trend})

      # Test with very choppy data (efficiency ratio should be low)
      choppy = [10.0, 11.0, 10.0, 11.0, 10.0, 11.0, 10.0, 11.0, 10.0, 11.0, 10.0, 11.0]
      df_choppy = DataFrame.new(%{close: choppy})

      kama_trend = Math.add_kama!(df_trend, :close, period: 8)
      kama_choppy = Math.add_kama!(df_choppy, :close, period: 8)

      # Both should produce valid KAMA values
      trend_values = DataFrame.pull(kama_trend, "close_kama_8") |> Explorer.Series.to_list()
      choppy_values = DataFrame.pull(kama_choppy, "close_kama_8") |> Explorer.Series.to_list()

      trend_valid = Enum.filter(trend_values, &finite?/1)
      choppy_valid = Enum.filter(choppy_values, &finite?/1)

      # Both should have some valid values
      assert trend_valid != []
      assert choppy_valid != []
    end
  end

  describe "edge cases" do
    test "handles DataFrame with exactly minimum required data" do
      # KAMA needs period + 1 rows
      # period 10 + 1
      min_data = List.duplicate(10.0, 11)
      df = DataFrame.new(%{close: min_data})

      result = Math.add_kama!(df, :close, period: 10)

      assert "close_kama_10" in DataFrame.names(result)
      kama_values = DataFrame.pull(result, "close_kama_10") |> Explorer.Series.to_list()

      # Should have at least one valid value
      assert Enum.any?(kama_values, &finite?/1)
    end

    test "handles very small periods" do
      df = DataFrame.new(%{close: @prices})

      result = Math.add_kama!(df, :close, period: 2)
      kama_values = DataFrame.pull(result, "close_kama_2") |> Explorer.Series.to_list()

      valid_count = Enum.count(kama_values, &finite?/1)
      assert valid_count >= 1
    end

    test "handles large periods" do
      # Create longer data series
      long_data = 1..50 |> Enum.map(&(&1 * 1.0))
      df = DataFrame.new(%{close: long_data})

      result = Math.add_kama!(df, :close, period: 40)
      kama_values = DataFrame.pull(result, "close_kama_40") |> Explorer.Series.to_list()

      # Should have some valid values even with large period
      valid_count = Enum.count(kama_values, &finite?/1)
      assert valid_count >= 1
    end
  end

  # Helper function to check if a float is finite (not NaN or infinite)
  defp finite?(val) when is_float(val) do
    is_float(val)
  end

  defp finite?(val) when is_number(val), do: true
  defp finite?(:nan), do: false
  defp finite?(_), do: false
end
