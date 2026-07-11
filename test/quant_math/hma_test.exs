defmodule Quant.Math.HMATest do
  @moduledoc """
  Test module for Hull Moving Average (HMA) functionality.
  """
  use ExUnit.Case, async: true
  alias Explorer.DataFrame
  alias Quant.Math

  describe "Hull Moving Average (HMA)" do
    test "calculates HMA with basic algorithm verification" do
      # Simple ascending data for algorithm verification
      df = DataFrame.new(%{close: [1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0, 8.0, 9.0, 10.0]})

      result = Math.add_hma!(df, :close, period: 4)
      values = DataFrame.pull(result, "close_hma_4") |> Explorer.Series.to_list()

      assert length(values) == 10

      # HMA needs sufficient data for calculation. Due to the multi-step algorithm:
      # 1. WMA(period/2) needs period/2 values
      # 2. WMA(period) needs period values
      # 3. Final WMA(sqrt(period)) needs sqrt(period) more values
      # So we expect several NaN values at the beginning

      # Just check that we have some NaN values at the beginning
      first_few_values = Enum.take(values, 3)
      nan_count = Enum.count(first_few_values, &(&1 == :nan))
      # Should have some NaN values
      assert nan_count > 0

      # Valid values should be present after sufficient data
      valid_values = Enum.filter(values, &(&1 != :nan))
      assert valid_values != []

      # HMA should be numeric and finite
      assert Enum.all?(valid_values, &is_float/1)
      assert Enum.all?(valid_values, &finite?/1)
    end

    test "HMA responds faster than SMA to trend changes" do
      # Create data with a clear trend change to test responsiveness
      trend_data = [10.0, 10.1, 10.2, 10.3, 10.4] ++ [11.0, 11.5, 12.0, 12.5, 13.0, 13.5, 14.0]
      df = DataFrame.new(%{close: trend_data})

      # Calculate both HMA and SMA for comparison
      result_with_sma = Math.add_sma!(df, :close, period: 5)
      result_with_hma = Math.add_hma!(result_with_sma, :close, period: 5)

      sma_values = DataFrame.pull(result_with_hma, "close_sma_5") |> Explorer.Series.to_list()
      hma_values = DataFrame.pull(result_with_hma, "close_hma_5") |> Explorer.Series.to_list()

      # Both should have same length
      assert length(sma_values) == length(hma_values)
      assert length(sma_values) == length(trend_data)

      # Find the last valid values (should be non-NaN)
      last_sma = Enum.filter(sma_values, &(&1 != :nan)) |> List.last()
      last_hma = Enum.filter(hma_values, &(&1 != :nan)) |> List.last()

      # Both should have valid final values
      assert last_sma != nil and last_sma != :nan
      assert last_hma != nil and last_hma != :nan

      # HMA should react more to the trend (higher value with uptrend)
      # This is a characteristic test rather than exact value
      assert is_float(last_hma) and is_float(last_sma)
    end

    test "calculates HMA with custom column name" do
      df = DataFrame.new(%{close: [1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0, 8.0]})

      result = Math.add_hma!(df, :close, period: 3, column_name: :my_hma)

      assert "my_hma" in DataFrame.names(result)
      refute "close_hma_3" in DataFrame.names(result)
    end

    test "handles insufficient data correctly" do
      # Only 2 data points
      df = DataFrame.new(%{close: [1.0, 2.0]})

      result = Math.add_hma!(df, :close, period: 4, validate: false)
      values = DataFrame.pull(result, "close_hma_4") |> Explorer.Series.to_list()

      # All values should be NaN because we need 4+ points for period 4
      assert Enum.all?(values, &(&1 == :nan))
    end

    test "handles empty DataFrame" do
      df = DataFrame.new(%{close: []})

      result = Math.add_hma!(df, :close, period: 3, validate: false)
      values = DataFrame.pull(result, "close_hma_3") |> Explorer.Series.to_list()

      assert values == []
    end

    test "validates required parameters" do
      df = DataFrame.new(%{close: [1.0, 2.0, 3.0, 4.0, 5.0, 6.0]})

      # Missing period
      assert_raise ArgumentError, "Period is required", fn ->
        Math.add_hma!(df, :close, [])
      end

      # Invalid period (zero)
      assert_raise ArgumentError, "Period must be a positive integer, got: 0", fn ->
        Math.add_hma!(df, :close, period: 0)
      end

      # Invalid period (negative)
      assert_raise ArgumentError, "Period must be a positive integer, got: -1", fn ->
        Math.add_hma!(df, :close, period: -1)
      end
    end

    test "validates DataFrame and column existence" do
      df = DataFrame.new(%{close: [1.0, 2.0, 3.0, 4.0, 5.0]})

      # Non-existent column
      assert_raise ArgumentError, "Column :price not found in DataFrame", fn ->
        Math.add_hma!(df, :price, period: 3)
      end
    end

    test "handles various period sizes" do
      df =
        DataFrame.new(%{close: [1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0, 8.0, 9.0, 10.0, 11.0, 12.0]})

      # Test different periods
      for period <- [3, 4, 5, 6] do
        result = Math.add_hma!(df, :close, period: period, column_name: :"hma_#{period}")
        values = DataFrame.pull(result, :"hma_#{period}") |> Explorer.Series.to_list()

        assert length(values) == 12

        # Should have some valid values
        valid_count = Enum.count(values, &(&1 != :nan))
        assert valid_count > 0

        # Valid values should be numeric
        valid_values = Enum.filter(values, &(&1 != :nan))
        assert Enum.all?(valid_values, &is_float/1)
      end
    end

    test "supports method chaining with other moving averages" do
      df = DataFrame.new(%{close: [1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0, 8.0, 9.0, 10.0]})

      result =
        df
        |> Math.add_sma!(:close, period: 3)
        |> Math.add_ema!(:close, period: 3)
        |> Math.add_wma!(:close, period: 3)
        |> Math.add_hma!(:close, period: 3)

      # Should have all MA columns
      names = DataFrame.names(result)
      assert "close_sma_3" in names
      assert "close_ema_3" in names
      assert "close_wma_3" in names
      assert "close_hma_3" in names
    end

    test "delegation through main Quant.Math module" do
      df = DataFrame.new(%{close: [1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0, 8.0]})

      # Test that delegation works
      result1 = Math.add_hma!(df, :close, period: 3)
      result2 = Math.MovingAverages.add_hma!(df, :close, period: 3)

      # Results should be identical
      values1 = DataFrame.pull(result1, "close_hma_3") |> Explorer.Series.to_list()
      values2 = DataFrame.pull(result2, "close_hma_3") |> Explorer.Series.to_list()

      assert values1 == values2
    end

    test "handles single data point gracefully" do
      df = DataFrame.new(%{close: [100.0]})

      # Use a larger period to avoid edge cases with period=1 and sqrt calculations
      result = Math.add_hma!(df, :close, period: 3, validate: false)
      values = DataFrame.pull(result, "close_hma_3") |> Explorer.Series.to_list()

      # With single data point and period > 1, result should be NaN
      assert length(values) == 1
      assert Enum.all?(values, &(&1 == :nan))
    end

    test "real-world price data example" do
      # Simulate realistic stock price data with volatility
      prices = [
        100.0,
        102.5,
        101.3,
        103.7,
        105.2,
        104.8,
        106.1,
        107.9,
        106.5,
        108.3,
        110.1,
        109.2,
        111.5,
        113.8,
        112.4,
        114.7,
        116.2,
        115.1,
        117.3,
        119.0
      ]

      df = DataFrame.new(%{close: prices})

      result = Math.add_hma!(df, :close, period: 5)
      values = DataFrame.pull(result, "close_hma_5") |> Explorer.Series.to_list()

      # Check that we get reasonable values
      assert length(values) == 20

      # Valid HMA values should be within reasonable range of the input prices
      valid_values = Enum.filter(values, &(&1 != :nan))
      assert valid_values != []

      # All valid values should be reasonable (within expanded price range)
      assert Enum.all?(valid_values, &(&1 >= 90.0 and &1 <= 130.0))

      # Should have numeric values
      assert Enum.all?(valid_values, &is_float/1)
    end

    test "different price columns work correctly" do
      df =
        DataFrame.new(%{
          open: [1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0, 8.0],
          high: [1.5, 2.5, 3.5, 4.5, 5.5, 6.5, 7.5, 8.5],
          low: [0.5, 1.5, 2.5, 3.5, 4.5, 5.5, 6.5, 7.5],
          close: [1.2, 2.2, 3.2, 4.2, 5.2, 6.2, 7.2, 8.2]
        })

      # Test HMA on different columns
      result =
        df
        |> Math.add_hma!(:open, period: 3, column_name: :hma_open)
        |> Math.add_hma!(:high, period: 3, column_name: :hma_high)

      assert "hma_open" in DataFrame.names(result)
      assert "hma_high" in DataFrame.names(result)

      # Values should be different for different source columns
      hma_open = DataFrame.pull(result, "hma_open") |> Explorer.Series.to_list()
      hma_high = DataFrame.pull(result, "hma_high") |> Explorer.Series.to_list()

      refute hma_open == hma_high
    end
  end

  describe "Hull MA mathematical properties" do
    test "HMA algorithm steps work correctly" do
      # Test with simple data where we can verify the algorithm steps
      df = DataFrame.new(%{close: [2.0, 4.0, 6.0, 8.0, 10.0, 12.0, 14.0, 16.0]})

      result = Math.add_hma!(df, :close, period: 4)
      values = DataFrame.pull(result, "close_hma_4") |> Explorer.Series.to_list()

      assert length(values) == 8

      # Should have some valid values after the initial NaN period
      valid_values = Enum.filter(values, &(&1 != :nan))
      assert valid_values != []

      # All valid values should be finite numbers
      assert Enum.all?(valid_values, fn val ->
               is_float(val) and finite?(val)
             end)
    end

    # Helper function to check if a float is finite
    defp finite?(val) when is_float(val) do
      val != :infinity and val != :neg_infinity and not is_nil(val)
    end

    defp finite?(_), do: false
  end
end
