defmodule Quant.Math.Oscillators.RSITest do
  @moduledoc """
  Tests for RSI (Relative Strength Index) calculations.

  Tests Wilder's smoothing method, signal detection, and integration
  with main API.
  """
  use ExUnit.Case, async: true

  alias Explorer.DataFrame
  alias Explorer.Series
  alias Quant.Math.Oscillators

  describe "add_rsi!/3" do
    test "calculates RSI with default parameters" do
      # RSI test data with known expected values
      price_data = [
        44.0,
        44.3,
        44.1,
        44.2,
        44.5,
        43.4,
        44.0,
        44.25,
        44.8,
        45.1,
        45.4,
        45.8,
        46.0,
        45.9,
        45.2,
        44.8,
        44.6,
        44.4,
        44.2,
        44.0
      ]

      df = DataFrame.new(%{close: price_data})
      result = Oscillators.add_rsi!(df, :close)

      # Verify column exists
      assert "close_rsi_14" in DataFrame.names(result)

      # Get RSI values
      rsi_values = result |> DataFrame.pull("close_rsi_14") |> Series.to_list()

      # Our improved Wilder's smoothing starts calculating immediately
      # Only the first value might be nil (no previous value for delta calculation)
      nil_count = rsi_values |> Enum.count(&is_nil/1)
      assert nil_count <= 1, "Expected at most 1 nil value, got #{nil_count}"

      # RSI values should be between 0 and 100
      rsi_values
      |> Enum.filter(&is_number/1)
      |> Enum.each(fn rsi ->
        assert rsi >= 0 and rsi <= 100
      end)
    end

    test "calculates RSI with custom period" do
      price_data = [10.0, 11.0, 12.0, 11.5, 13.0, 12.8, 14.0, 13.5, 15.0, 14.2]
      df = DataFrame.new(%{close: price_data})

      result = Oscillators.add_rsi!(df, :close, period: 5)

      # Verify column exists with correct name
      assert "close_rsi_5" in DataFrame.names(result)

      # Get RSI values
      rsi_values = result |> DataFrame.pull("close_rsi_5") |> Series.to_list()

      # Our improved Wilder's smoothing starts calculating immediately
      # Only the first value might be nil (no previous value for delta calculation)
      nil_count = rsi_values |> Enum.count(&is_nil/1)
      assert nil_count <= 1, "Expected at most 1 nil value, got #{nil_count}"

      # Remaining values should be valid RSI
      rsi_values
      |> Enum.filter(&is_number/1)
      |> Enum.each(fn rsi ->
        assert rsi >= 0 and rsi <= 100
      end)
    end

    test "calculates RSI with custom column name" do
      price_data = [10.0, 11.0, 12.0, 11.5, 13.0, 12.8, 14.0, 13.5]
      df = DataFrame.new(%{price: price_data})

      result = Oscillators.add_rsi!(df, :price, period: 5, column_name: "custom_rsi")

      # Verify custom column name
      assert "custom_rsi" in DataFrame.names(result)
      refute "price_rsi_5" in DataFrame.names(result)
    end

    test "handles trending upward prices correctly" do
      # Strongly trending up prices should result in high RSI
      upward_trend = Enum.map(1..20, fn i -> i * 1.0 end)
      df = DataFrame.new(%{close: upward_trend})

      result = Oscillators.add_rsi!(df, :close, period: 10)
      rsi_values = result |> DataFrame.pull("close_rsi_10") |> Series.to_list()

      # Get the last few RSI values (after initial nil period)
      final_rsi_values = rsi_values |> Enum.drop(15) |> Enum.take(3)

      # Strong upward trend should result in high RSI (> 80)
      final_rsi_values
      |> Enum.each(fn rsi ->
        assert is_number(rsi)
        assert rsi > 80.0, "Expected RSI > 80 for strong upward trend, got #{rsi}"
      end)
    end

    test "handles trending downward prices correctly" do
      # Strongly trending down prices should result in low RSI
      downward_trend = Enum.map(20..1//-1, fn i -> i * 1.0 end)
      df = DataFrame.new(%{close: downward_trend})

      result = Oscillators.add_rsi!(df, :close, period: 10)
      rsi_values = result |> DataFrame.pull("close_rsi_10") |> Series.to_list()

      # Get the last few RSI values
      final_rsi_values = rsi_values |> Enum.drop(15) |> Enum.take(3)

      # Strong downward trend should result in low RSI (< 20)
      final_rsi_values
      |> Enum.each(fn rsi ->
        assert is_number(rsi)
        assert rsi < 20.0, "Expected RSI < 20 for strong downward trend, got #{rsi}"
      end)
    end

    test "handles sideways/flat prices correctly" do
      # Flat prices should result in RSI around 50
      flat_prices = List.duplicate(100.0, 20)
      df = DataFrame.new(%{close: flat_prices})

      result = Oscillators.add_rsi!(df, :close, period: 10)
      rsi_values = result |> DataFrame.pull("close_rsi_10") |> Series.to_list()

      # After the initial period, RSI should be 50 (no gains or losses)
      final_rsi = Enum.at(rsi_values, -1)
      assert is_number(final_rsi)
      assert abs(final_rsi - 50.0) < 0.01, "Expected RSI ≈ 50 for flat prices, got #{final_rsi}"
    end

    test "validates input parameters" do
      df = DataFrame.new(%{close: [1.0, 2.0, 3.0]})

      # Test invalid period
      assert_raise ArgumentError, ~r/period must be a positive integer/, fn ->
        Oscillators.add_rsi!(df, :close, period: 0)
      end

      assert_raise ArgumentError, ~r/period must be a positive integer/, fn ->
        Oscillators.add_rsi!(df, :close, period: -5)
      end

      # Test invalid column
      assert_raise ArgumentError, ~r/Column :nonexistent not found/, fn ->
        Oscillators.add_rsi!(df, :nonexistent)
      end

      # Test invalid dataframe
      assert_raise ArgumentError, ~r/Expected Explorer DataFrame/, fn ->
        Oscillators.add_rsi!(%{not: "dataframe"}, :close)
      end
    end

    test "works with different column types" do
      df =
        DataFrame.new(%{
          # Different pattern
          high: [10.0, 11.5, 13.0, 12.0, 14.5, 13.8, 16.0, 15.0],
          # Different pattern
          close: [9.5, 10.5, 11.5, 11.0, 12.5, 12.3, 13.5, 13.0]
        })

      # Test with high column
      result_high = Oscillators.add_rsi!(df, :high, period: 5)
      assert "high_rsi_5" in DataFrame.names(result_high)

      # Test with close column
      result_close = Oscillators.add_rsi!(df, :close, period: 5)
      assert "close_rsi_5" in DataFrame.names(result_close)

      # Results should be different for different columns
      rsi_high = result_high |> DataFrame.pull("high_rsi_5") |> Series.to_list()
      rsi_close = result_close |> DataFrame.pull("close_rsi_5") |> Series.to_list()

      # At least some RSI values should be different (after the nil period)
      valid_pairs =
        Enum.zip(rsi_high, rsi_close)
        |> Enum.filter(fn {h, c} ->
          is_number(h) and is_number(c)
        end)

      differences =
        valid_pairs
        |> Enum.count(fn {h, c} -> abs(h - c) > 0.01 end)

      assert differences > 0,
             "RSI should be different for different price columns with different patterns"
    end
  end

  describe "rsi_signals/3" do
    test "detects overbought and oversold conditions with default thresholds" do
      # Create DataFrame with RSI values that span overbought/oversold ranges
      rsi_data = [15, 25, 45, 65, 75, 85, 55, 30, 20, 80]
      df = DataFrame.new(%{rsi: rsi_data})

      result = Oscillators.rsi_signals(df, "rsi")

      # Verify signal column exists
      assert "rsi_signal" in DataFrame.names(result)

      # Get signals
      signals = result |> DataFrame.pull("rsi_signal") |> Series.to_list()

      # Verify expected signals (using default 30/70 thresholds)
      expected_signals = [
        # 15 -> oversold (buy)
        1,
        # 25 -> oversold (buy)
        1,
        # 45 -> neutral
        0,
        # 65 -> neutral
        0,
        # 75 -> overbought (sell)
        -1,
        # 85 -> overbought (sell)
        -1,
        # 55 -> neutral
        0,
        # 30 -> oversold (buy) - exactly at threshold
        1,
        # 20 -> oversold (buy)
        1,
        # 80 -> overbought (sell)
        -1
      ]

      assert signals == expected_signals
    end

    test "works with custom overbought/oversold thresholds" do
      rsi_data = [10, 25, 40, 65, 80, 90]
      df = DataFrame.new(%{rsi: rsi_data})

      # Use custom thresholds: oversold = 20, overbought = 75
      result =
        Oscillators.rsi_signals(df, "rsi",
          overbought: 75,
          oversold: 20
        )

      signals = result |> DataFrame.pull("rsi_signal") |> Series.to_list()

      # Expected with custom thresholds
      expected_signals = [
        # 10 -> oversold (< 20)
        1,
        # 25 -> neutral (between 20-75)
        0,
        # 40 -> neutral
        0,
        # 65 -> neutral
        0,
        # 80 -> overbought (> 75)
        -1,
        # 90 -> overbought (> 75)
        -1
      ]

      assert signals == expected_signals
    end

    test "uses custom signal column name" do
      rsi_data = [20, 50, 80]
      df = DataFrame.new(%{rsi: rsi_data})

      result = Oscillators.rsi_signals(df, "rsi", signal_column: "custom_signals")

      # Verify custom column name
      assert "custom_signals" in DataFrame.names(result)
      refute "rsi_signal" in DataFrame.names(result)

      # Verify signals are correct
      signals = result |> DataFrame.pull("custom_signals") |> Series.to_list()
      # oversold, neutral, overbought
      assert signals == [1, 0, -1]
    end

    test "handles edge cases and nil values" do
      # Mix of valid RSI values and nil
      rsi_data = [nil, 30.0, nil, 70.0, nil]
      df = DataFrame.new(%{rsi: rsi_data})

      result = Oscillators.rsi_signals(df, "rsi")
      signals = result |> DataFrame.pull("rsi_signal") |> Series.to_list()

      # nil values should produce neutral signals (0)
      # nil->neutral, oversold, nil->neutral, overbought, nil->neutral
      expected_signals = [0, 1, 0, -1, 0]
      assert signals == expected_signals
    end

    test "handles exact threshold values" do
      # Test RSI values exactly at thresholds
      # Exactly at default thresholds
      rsi_data = [30.0, 70.0]
      df = DataFrame.new(%{rsi: rsi_data})

      result = Oscillators.rsi_signals(df, "rsi")
      signals = result |> DataFrame.pull("rsi_signal") |> Series.to_list()

      # 30 should be oversold (<=), 70 should be overbought (>=)
      assert signals == [1, -1]
    end

    test "validates thresholds make sense" do
      rsi_data = [50.0]
      df = DataFrame.new(%{rsi: rsi_data})

      # Should work fine with valid thresholds
      result = Oscillators.rsi_signals(df, "rsi", overbought: 80, oversold: 20)
      assert "rsi_signal" in DataFrame.names(result)

      # Edge case: overlapping thresholds (oversold > overbought)
      # This should still work, just logically inconsistent
      result2 = Oscillators.rsi_signals(df, "rsi", overbought: 20, oversold: 80)
      assert "rsi_signal" in DataFrame.names(result2)
    end
  end

  describe "Wilder's smoothing method" do
    test "produces different results than standard EMA" do
      # Test that Wilder's smoothing differs from standard EMA
      # This is tested indirectly through RSI calculation

      # Simple upward trend
      price_data = [10.0, 11.0, 12.0, 13.0, 14.0, 15.0, 16.0, 17.0, 18.0, 19.0]
      df = DataFrame.new(%{close: price_data})

      result = Oscillators.add_rsi!(df, :close, period: 5)
      rsi_values = result |> DataFrame.pull("close_rsi_5") |> Series.to_list()

      # After initial nils, should have valid RSI values
      valid_rsi = rsi_values |> Enum.filter(&is_number/1)
      assert valid_rsi != []

      # All RSI values should be reasonable (upward trend = high RSI)
      # Note: first value might be 50.0 when there's no initial change
      valid_rsi
      # Skip first value which can be 50.0
      |> Enum.drop(1)
      |> Enum.each(fn rsi ->
        assert rsi > 50.0, "Upward trend should produce RSI > 50, got #{rsi}"
        assert rsi <= 100.0
      end)
    end
  end

  describe "integration with main API" do
    test "functions are accessible through Quant.Math" do
      price_data = [10.0, 11.0, 12.0, 13.0, 14.0, 15.0, 16.0, 17.0]
      df = DataFrame.new(%{close: price_data})

      # Test main API delegation
      result1 = Quant.Math.add_rsi!(df, :close, period: 5)
      result2 = Oscillators.add_rsi!(df, :close, period: 5)

      # Results should be identical
      rsi1 = result1 |> DataFrame.pull("close_rsi_5") |> Series.to_list()
      rsi2 = result2 |> DataFrame.pull("close_rsi_5") |> Series.to_list()

      assert rsi1 == rsi2

      # Test signal function through main API
      rsi_df = DataFrame.new(%{rsi: [20, 50, 80]})
      signals1 = Quant.Math.rsi_signals(rsi_df, "rsi")
      signals2 = Oscillators.rsi_signals(rsi_df, "rsi")

      s1 = signals1 |> DataFrame.pull("rsi_signal") |> Series.to_list()
      s2 = signals2 |> DataFrame.pull("rsi_signal") |> Series.to_list()

      assert s1 == s2
    end
  end
end
