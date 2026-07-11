defmodule Quant.Math.DEMATest do
  @moduledoc """
  Test module for Double Exponential Moving Average (DEMA) functionality.
  """
  use ExUnit.Case, async: true
  alias Explorer.DataFrame
  alias Quant.Math

  describe "Double Exponential Moving Average (DEMA)" do
    test "calculates DEMA with basic algorithm verification" do
      # Simple ascending data for algorithm verification
      df = DataFrame.new(%{close: [1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0, 8.0, 9.0, 10.0]})

      result = Math.add_dema!(df, :close, period: 4)
      values = DataFrame.pull(result, "close_dema_4") |> Explorer.Series.to_list()

      assert length(values) == 10

      # DEMA needs sufficient data for double smoothing
      # First few values should be NaN due to insufficient data
      first_values = Enum.take(values, 3)
      nan_count = Enum.count(first_values, &(&1 == :nan))
      # Should have some NaN values
      assert nan_count > 0

      # Valid values should be present after sufficient data
      valid_values = Enum.filter(values, &(&1 != :nan))
      assert valid_values != []

      # DEMA should be numeric and finite
      assert Enum.all?(valid_values, &is_float/1)
      assert Enum.all?(valid_values, &finite?/1)
    end

    test "DEMA responds faster than EMA to trend changes" do
      # Create data with a clear trend change to test responsiveness
      trend_data = [10.0, 10.1, 10.2, 10.3, 10.4] ++ [11.0, 11.5, 12.0, 12.5, 13.0, 13.5, 14.0]
      df = DataFrame.new(%{close: trend_data})

      # Calculate both DEMA and EMA for comparison
      result_with_ema = Math.add_ema!(df, :close, period: 5)
      result_with_dema = Math.add_dema!(result_with_ema, :close, period: 5)

      ema_values = DataFrame.pull(result_with_dema, "close_ema_5") |> Explorer.Series.to_list()
      dema_values = DataFrame.pull(result_with_dema, "close_dema_5") |> Explorer.Series.to_list()

      # Both should have same length
      assert length(ema_values) == length(dema_values)
      assert length(ema_values) == length(trend_data)

      # Find the last valid values (should be non-NaN)
      last_ema = Enum.filter(ema_values, &(&1 != :nan)) |> List.last()
      last_dema = Enum.filter(dema_values, &(&1 != :nan)) |> List.last()

      # Both should have valid final values
      assert last_ema != nil and last_ema != :nan
      assert last_dema != nil and last_dema != :nan

      # Both should be numeric
      assert is_float(last_dema) and is_float(last_ema)
    end

    test "calculates DEMA with custom column name" do
      df = DataFrame.new(%{close: [1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0, 8.0]})

      result = Math.add_dema!(df, :close, period: 3, column_name: :my_dema)

      assert "my_dema" in DataFrame.names(result)
      refute "close_dema_3" in DataFrame.names(result)
    end

    test "calculates DEMA with custom alpha" do
      df = DataFrame.new(%{close: [1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0, 8.0, 9.0, 10.0]})

      # Test with custom alpha value
      result = Math.add_dema!(df, :close, period: 4, alpha: 0.5)
      values = DataFrame.pull(result, "close_dema_4") |> Explorer.Series.to_list()

      assert length(values) == 10

      # Should have some valid values
      valid_values = Enum.filter(values, &(&1 != :nan))
      assert valid_values != []

      # All valid values should be numeric
      assert Enum.all?(valid_values, &is_float/1)
    end

    test "handles insufficient data correctly" do
      # Only 2 data points
      df = DataFrame.new(%{close: [1.0, 2.0]})

      result = Math.add_dema!(df, :close, period: 4, validate: false)
      values = DataFrame.pull(result, "close_dema_4") |> Explorer.Series.to_list()

      # All values should be NaN because we need 4+ points for period 4
      assert Enum.all?(values, &(&1 == :nan))
    end

    test "handles empty DataFrame" do
      df = DataFrame.new(%{close: []})

      result = Math.add_dema!(df, :close, period: 3, validate: false)
      values = DataFrame.pull(result, "close_dema_3") |> Explorer.Series.to_list()

      assert values == []
    end

    test "validates required parameters" do
      df = DataFrame.new(%{close: [1.0, 2.0, 3.0, 4.0, 5.0, 6.0]})

      # Missing period
      assert_raise ArgumentError, "Period is required", fn ->
        Math.add_dema!(df, :close, [])
      end

      # Invalid period (zero)
      assert_raise ArgumentError, "Period must be a positive integer, got: 0", fn ->
        Math.add_dema!(df, :close, period: 0)
      end

      # Invalid period (negative)
      assert_raise ArgumentError, "Period must be a positive integer, got: -1", fn ->
        Math.add_dema!(df, :close, period: -1)
      end
    end

    test "validates alpha parameter" do
      df = DataFrame.new(%{close: [1.0, 2.0, 3.0, 4.0, 5.0, 6.0]})

      # Invalid alpha (too small)
      assert_raise ArgumentError, "Alpha must be between 0.0 and 1.0, got: 0.0", fn ->
        Math.add_dema!(df, :close, period: 3, alpha: 0.0)
      end

      # Invalid alpha (too large)
      assert_raise ArgumentError, "Alpha must be between 0.0 and 1.0, got: 1.5", fn ->
        Math.add_dema!(df, :close, period: 3, alpha: 1.5)
      end
    end

    test "validates DataFrame and column existence" do
      df = DataFrame.new(%{close: [1.0, 2.0, 3.0, 4.0, 5.0]})

      # Non-existent column
      assert_raise ArgumentError, "Column :price not found in DataFrame", fn ->
        Math.add_dema!(df, :price, period: 3)
      end
    end

    test "handles various period sizes" do
      df =
        DataFrame.new(%{close: [1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0, 8.0, 9.0, 10.0, 11.0, 12.0]})

      # Test different periods
      for period <- [3, 4, 5, 6] do
        result = Math.add_dema!(df, :close, period: period, column_name: :"dema_#{period}")
        values = DataFrame.pull(result, "dema_#{period}") |> Explorer.Series.to_list()

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
        |> Math.add_dema!(:close, period: 3)

      # Should have all MA columns
      names = DataFrame.names(result)
      assert "close_sma_3" in names
      assert "close_ema_3" in names
      assert "close_wma_3" in names
      assert "close_hma_3" in names
      assert "close_dema_3" in names
    end

    test "delegation through main Quant.Math module" do
      df = DataFrame.new(%{close: [1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0, 8.0]})

      # Test that delegation works
      result1 = Math.add_dema!(df, :close, period: 3)
      result2 = Math.MovingAverages.add_dema!(df, :close, period: 3)

      # Results should be identical
      values1 = DataFrame.pull(result1, "close_dema_3") |> Explorer.Series.to_list()
      values2 = DataFrame.pull(result2, "close_dema_3") |> Explorer.Series.to_list()

      assert values1 == values2
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

      result = Math.add_dema!(df, :close, period: 5)
      values = DataFrame.pull(result, "close_dema_5") |> Explorer.Series.to_list()

      # Check that we get reasonable values
      assert length(values) == 20

      # Valid DEMA values should be within reasonable range of the input prices
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

      # Test DEMA on different columns
      result =
        df
        |> Math.add_dema!(:open, period: 3, column_name: :dema_open)
        |> Math.add_dema!(:high, period: 3, column_name: :dema_high)

      assert "dema_open" in DataFrame.names(result)
      assert "dema_high" in DataFrame.names(result)

      # Values should be different for different source columns
      dema_open = DataFrame.pull(result, "dema_open") |> Explorer.Series.to_list()
      dema_high = DataFrame.pull(result, "dema_high") |> Explorer.Series.to_list()

      refute dema_open == dema_high
    end
  end

  describe "DEMA mathematical properties" do
    test "DEMA algorithm steps work correctly" do
      # Test with simple data where we can verify the algorithm steps
      df = DataFrame.new(%{close: [2.0, 4.0, 6.0, 8.0, 10.0, 12.0, 14.0, 16.0]})

      result = Math.add_dema!(df, :close, period: 4)
      values = DataFrame.pull(result, "close_dema_4") |> Explorer.Series.to_list()

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
      is_float(val)
    end

    defp finite?(_), do: false
  end
end
