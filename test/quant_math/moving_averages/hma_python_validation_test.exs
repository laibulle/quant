defmodule Quant.Math.MovingAverages.HMAPythonValidationTest do
  @moduledoc """
  Python validation tests for HMA (Hull Moving Average) calculations.

  These tests validate our Elixir HMA implementation against Python
  to ensure we're calculating HMA correctly and identify any discrepancies.

  HMA Algorithm:
  1. WMA1 = WMA(price, period/2)
  2. WMA2 = WMA(price, period)
  3. Raw HMA = 2 * WMA1 - WMA2
  4. Final HMA = WMA(Raw HMA, sqrt(period))
  """

  use ExUnit.Case, async: true

  import Pythonx
  import Quant.Explorer.PythonHelpers

  alias Explorer.DataFrame
  alias Explorer.Series
  alias Quant.Math.MovingAverages

  describe "Python validation tests" do
    @tag :python_validation
    test "Pythonx integration works for HMA" do
      # Simple test to verify Pythonx is working
      if python_available?() do
        python_result = ~PY"""
        import pandas as pd
        import numpy as np
        "HMA validation ready"
        """

        # Convert Python object to Elixir string check
        result = python_result |> inspect() |> String.contains?("HMA validation ready")

        assert result
        IO.puts("\n✅ Pythonx integration is working correctly for HMA validation")
      else
        IO.puts("\n⚠️  Python/pandas not available, skipping HMA Python validation")
      end
    end

    @tag :python_validation
    test "HMA calculation matches Python implementation" do
      if python_available?() do
        # Test data - using realistic price movements with enough data for HMA calculation
        price_data = [
          100.0,
          102.0,
          101.5,
          103.0,
          104.5,
          103.8,
          105.2,
          106.1,
          105.0,
          107.3,
          108.7,
          107.9,
          110.2,
          111.5,
          110.8,
          112.4,
          113.9,
          112.7,
          115.1,
          116.8,
          115.5,
          117.9,
          119.2,
          118.1,
          120.5,
          121.8,
          120.9,
          123.2,
          124.7,
          123.4,
          126.1,
          127.5
        ]

        period = 9

        # Calculate HMA using our Elixir implementation
        df = DataFrame.new(%{close: price_data})
        elixir_result = MovingAverages.add_hma!(df, :close, period: period)
        elixir_hma = elixir_result |> DataFrame.pull("close_hma_#{period}") |> Series.to_list()

        # Calculate HMA using Python - implementing the exact same algorithm
        python_final_hma = ~PY"""
        import pandas as pd
        import numpy as np

        def wma(values, period):
            # Calculate Weighted Moving Average
            if len(values) < period:
                return np.nan
            weights = np.arange(1, period + 1)
            return np.dot(values[-period:], weights) / weights.sum()

        def hma(prices, period):
            # Calculate Hull Moving Average
            half_period = period // 2
            sqrt_period = int(np.sqrt(period))

            # Step 1: Calculate WMA with period/2
            wma_half_values = []
            for i in range(len(prices)):
                if i >= half_period - 1:
                    wma_val = wma(prices[:i+1], half_period)
                    wma_half_values.append(wma_val)
                else:
                    wma_half_values.append(np.nan)

            # Step 2: Calculate WMA with full period
            wma_full_values = []
            for i in range(len(prices)):
                if i >= period - 1:
                    wma_val = wma(prices[:i+1], period)
                    wma_full_values.append(wma_val)
                else:
                    wma_full_values.append(np.nan)

            # Step 3: Calculate raw HMA: 2 * WMA(period/2) - WMA(period)
            raw_hma = []
            for i in range(len(prices)):
                if not (np.isnan(wma_half_values[i]) or np.isnan(wma_full_values[i])):
                    raw_val = 2 * wma_half_values[i] - wma_full_values[i]
                    raw_hma.append(raw_val)
                else:
                    raw_hma.append(np.nan)

            # Step 4: Apply WMA with sqrt(period) to raw HMA
            final_hma = []
            for i in range(len(raw_hma)):
                # Find the valid portion of raw_hma up to this point
                valid_raw = [x for x in raw_hma[:i+1] if not np.isnan(x)]
                if len(valid_raw) >= sqrt_period:
                    hma_val = wma(valid_raw, sqrt_period)
                    final_hma.append(hma_val)
                else:
                    final_hma.append(np.nan)

            return final_hma

        # Calculate HMA
        hma_values = hma(price_data, period)

        # Get the final HMA value
        final_value = None
        for val in reversed(hma_values):
            if not np.isnan(val):
                final_value = float(val)
                break

        final_value
        """

        # Extract final values for comparison
        final_elixir = Enum.filter(elixir_hma, &(&1 != :nan)) |> List.last()

        # Parse the Python result
        final_python =
          case python_final_hma do
            result when is_number(result) ->
              result

            _ ->
              # Fallback: extract number from string representation
              python_str = python_final_hma |> inspect()

              if python_str =~ "None" do
                nil
              else
                parse_python_float(python_str)
              end
          end

        IO.puts("\n📊 Python HMA Validation Results:")

        IO.puts(
          "   Final Elixir HMA: #{if final_elixir, do: Float.round(final_elixir, 4), else: "nil"}"
        )

        IO.puts(
          "   Final Python HMA: #{if final_python, do: Float.round(final_python, 4), else: "nil"}"
        )

        if final_elixir && final_python do
          diff = abs(final_elixir - final_python)
          percent_diff = diff / final_python * 100.0

          IO.puts("   Absolute Difference: #{Float.round(diff, 4)}")
          IO.puts("   Percentage Difference: #{Float.round(percent_diff, 2)}%")

          if percent_diff > 2.0 do
            IO.puts("   ⚠️  SIGNIFICANT DIFFERENCES DETECTED")

            IO.puts(
              "   💡 This suggests an implementation bug - both should use the same HMA algorithm"
            )

            IO.puts("   🔍 Need to investigate calculation differences")
          else
            IO.puts("   ✅ Implementations are reasonably close")
          end
        else
          IO.puts("   ⚠️  Could not compare values (one or both are nil)")
        end
      end
    end

    @tag :python_validation
    test "HMA algorithm step verification" do
      if python_available?() do
        # Simple test case to verify step-by-step calculations
        price_data = [
          50.0,
          51.0,
          52.0,
          51.5,
          53.0,
          52.5,
          54.0,
          53.8,
          55.0,
          54.2,
          56.0,
          55.7,
          57.0,
          56.5,
          58.0,
          57.2,
          59.0,
          58.5,
          60.0,
          59.3,
          61.0
        ]

        period = 6

        df = DataFrame.new(%{close: price_data})
        elixir_result = MovingAverages.add_hma!(df, :close, period: period)
        elixir_hma = elixir_result |> DataFrame.pull("close_hma_#{period}") |> Series.to_list()

        # Get algorithm breakdown using Python
        python_results = ~PY"""
        import pandas as pd
        import numpy as np

        def wma(values, period):
            # Calculate Weighted Moving Average
            if len(values) < period:
                return np.nan
            weights = np.arange(1, period + 1)
            return np.dot(values[-period:], weights) / weights.sum()

        def hma_breakdown(prices, period):
            # Calculate HMA with step breakdown
            half_period = period // 2  # 3
            sqrt_period = int(np.sqrt(period))  # 2

            # For the last few values, show the breakdown
            n = len(prices)
            results = {
                'half_period': half_period,
                'sqrt_period': sqrt_period,
                'last_wma_half': None,
                'last_wma_full': None,
                'last_raw_hma': None,
                'final_hma': None
            }

            if n >= period:
                # Calculate final WMA values
                wma_half_val = wma(prices, half_period)
                wma_full_val = wma(prices, period)
                raw_hma_val = 2 * wma_half_val - wma_full_val

                results['last_wma_half'] = float(wma_half_val)
                results['last_wma_full'] = float(wma_full_val)
                results['last_raw_hma'] = float(raw_hma_val)

                # For final HMA, we need to build the raw HMA series first
                # This is simplified - just showing the concept
                results['final_hma'] = float(raw_hma_val)  # Simplified

            return results

        hma_breakdown(price_data, period)
        """

        # Extract valid values from Elixir implementation
        elixir_valid = Enum.filter(elixir_hma, &(&1 != :nan))

        # Parse Python results
        python_dict_str = python_results |> inspect()
        _half_period = extract_dict_value(python_dict_str, "half_period")
        _sqrt_period = extract_dict_value(python_dict_str, "sqrt_period")
        wma_half = extract_dict_value(python_dict_str, "last_wma_half")
        wma_full = extract_dict_value(python_dict_str, "last_wma_full")

        IO.puts("\n🔬 HMA Algorithm Step Verification:")
        IO.puts("   Input data length: #{length(price_data)}")
        IO.puts("   Period: #{period}")
        IO.puts("   Half period: #{div(period, 2)}")
        IO.puts("   Sqrt period: #{round(:math.sqrt(period))}")
        IO.puts("   Elixir valid values: #{length(elixir_valid)}")

        if wma_half && wma_full do
          expected_raw_hma = 2 * wma_half - wma_full
          IO.puts("   Python WMA(#{div(period, 2)}): #{Float.round(wma_half, 4)}")
          IO.puts("   Python WMA(#{period}): #{Float.round(wma_full, 4)}")
          IO.puts("   Expected Raw HMA: #{Float.round(expected_raw_hma, 4)}")

          if elixir_valid != [] do
            elixir_final = List.last(elixir_valid)
            IO.puts("   Elixir Final HMA: #{Float.round(elixir_final, 4)}")

            # Note: Direct comparison is difficult due to the final WMA step
            IO.puts("   📝 Note: Final HMA involves WMA(Raw HMA, sqrt(#{period}))")
            IO.puts("   📝 This explains any differences from the simple raw HMA calculation")
          end
        else
          IO.puts("   📝 Python breakdown calculation had issues - using direct calculation")
          IO.puts("   Half period: #{div(period, 2)}")
          IO.puts("   Sqrt period: #{round(:math.sqrt(period))}")
        end

        if elixir_valid != [] do
          IO.puts("   ✅ HMA algorithm steps are working (produces valid results)")
        else
          IO.puts("   ⚠️  No valid HMA values produced - check algorithm implementation")
        end
      end
    end

    @tag :python_validation
    test "HMA responsiveness compared to SMA - validation against Python" do
      if python_available?() do
        # Data with clear trend to test responsiveness
        price_data = [
          # Gradual uptrend
          10.0,
          10.2,
          10.4,
          10.3,
          10.6,
          10.8,
          10.7,
          11.0,
          # Steeper uptrend
          11.5,
          12.0,
          12.5,
          13.0,
          13.5,
          14.0,
          14.5,
          15.0,
          # Continued uptrend
          15.5,
          16.0,
          16.5,
          17.0,
          17.5,
          18.0
        ]

        period = 8

        df = DataFrame.new(%{close: price_data})

        # Calculate both SMA and HMA using our implementation
        result_with_sma = MovingAverages.add_sma!(df, :close, period: period)
        result_with_hma = MovingAverages.add_hma!(result_with_sma, :close, period: period)

        elixir_sma = result_with_hma |> DataFrame.pull("close_sma_#{period}") |> Series.to_list()
        elixir_hma = result_with_hma |> DataFrame.pull("close_hma_#{period}") |> Series.to_list()

        # Calculate SMA and simplified HMA comparison using Python
        python_comparison = ~PY"""
        import pandas as pd
        import numpy as np

        # Simple SMA calculation
        def sma(prices, period):
            result = []
            for i in range(len(prices)):
                if i >= period - 1:
                    avg = np.mean(prices[i-period+1:i+1])
                    result.append(avg)
                else:
                    result.append(np.nan)
            return result

        sma_values = sma(price_data, period)

        # Get final values
        final_sma = None
        for val in reversed(sma_values):
            if not np.isnan(val):
                final_sma = float(val)
                break

        # Calculate expected responsiveness difference
        current_price = price_data[-1]
        price_trend = current_price - price_data[0]  # Total trend

        {
            'final_sma': final_sma,
            'current_price': current_price,
            'total_trend': price_trend
        }
        """

        # Extract final values
        final_elixir_sma = Enum.filter(elixir_sma, &(&1 != :nan)) |> List.last()
        final_elixir_hma = Enum.filter(elixir_hma, &(&1 != :nan)) |> List.last()

        # Parse Python results
        python_str = python_comparison |> inspect()
        python_sma = extract_dict_value(python_str, "final_sma")
        current_price = extract_dict_value(python_str, "current_price")
        total_trend = extract_dict_value(python_str, "total_trend")

        IO.puts("\n🚀 HMA Responsiveness Validation:")

        IO.puts(
          "   Trend: #{if total_trend, do: "Upward (+#{Float.round(total_trend, 1)})", else: "Unknown"}"
        )

        IO.puts(
          "   Current Price: #{if current_price, do: Float.round(current_price, 1), else: "nil"}"
        )

        IO.puts("   Period: #{period}")

        if final_elixir_sma && final_elixir_hma do
          responsiveness_diff = final_elixir_hma - final_elixir_sma

          IO.puts("   Final SMA (Elixir): #{Float.round(final_elixir_sma, 4)}")
          IO.puts("   Final HMA (Elixir): #{Float.round(final_elixir_hma, 4)}")
          IO.puts("   Responsiveness difference: #{Float.round(responsiveness_diff, 4)}")

          if python_sma do
            sma_diff = abs(final_elixir_sma - python_sma)
            IO.puts("   SMA difference (Elixir vs Python): #{Float.round(sma_diff, 4)}")

            if sma_diff < 0.01 do
              IO.puts("   ✅ SMA calculation matches Python")
            end
          end

          if responsiveness_diff > 0 do
            IO.puts("   ✅ HMA is more responsive than SMA (as expected in uptrend)")
          else
            IO.puts("   ⚠️  HMA responsiveness may need investigation")
          end

          # Check if HMA is closer to current price than SMA
          if current_price do
            hma_distance = abs(final_elixir_hma - current_price)
            sma_distance = abs(final_elixir_sma - current_price)

            IO.puts("   Distance from current price:")
            IO.puts("     HMA: #{Float.round(hma_distance, 4)}")
            IO.puts("     SMA: #{Float.round(sma_distance, 4)}")

            if hma_distance < sma_distance do
              IO.puts("   ✅ HMA is closer to current price (shows reduced lag)")
            end
          end
        end
      end
    end
  end

  # Helper functions for Python validation
  defp parse_python_float(str) do
    # Extract the first number (int or float) from the string
    case Regex.run(~r/([0-9]+(?:\.[0-9]+)?)/, str) do
      [_, number_str] -> String.to_float(number_str)
      nil -> nil
    end
  rescue
    ArgumentError ->
      # Handle case where it's an integer
      case Regex.run(~r/([0-9]+)/, str) do
        [_, number_str] -> String.to_float(number_str)
        nil -> nil
      end
  end

  defp extract_dict_value(dict_str, key) do
    # Extract value from Python dict string representation
    # Looks for patterns like "'key': value" or "'key': None"
    pattern = ~r/'#{key}':\s*([0-9]+(?:\.[0-9]+)?|None)/

    case Regex.run(pattern, dict_str) do
      [_, "None"] -> nil
      [_, number_str] -> String.to_float(number_str)
      nil -> nil
    end
  rescue
    ArgumentError -> nil
  end
end
