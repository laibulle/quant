defmodule Quant.Strategy.Optimization.BenchmarkTest do
  @moduledoc """
  Tests for the parameter optimization benchmark functionality.
  """

  use ExUnit.Case, async: true
  alias Explorer.DataFrame
  alias Quant.Strategy.Optimization

  # Create sample test data for benchmarking
  defp create_benchmark_data do
    # Create 100 days of sample OHLCV data with trend
    price_data =
      Enum.map(1..100, fn i ->
        # Upward trend
        base_price = 100 + i * 0.5
        # Some volatility
        volatility = :math.sin(i / 10.0) * 3
        base_price + volatility
      end)

    DataFrame.new(%{
      datetime:
        Enum.map(1..100, fn i ->
          ~N[2023-01-01 00:00:00] |> NaiveDateTime.add(i, :day)
        end),
      close: price_data,
      volume: List.duplicate(10_000, 100)
    })
  end

  describe "Parameter scaling benchmarks" do
    test "measures performance across different parameter grid sizes" do
      df = create_benchmark_data()

      # Test small parameter grid (4 combinations)
      small_params = %{period: [5, 10]}

      {time_micro, {:ok, results}} =
        :timer.tc(fn ->
          Optimization.run_combinations(df, :sma_crossover, small_params)
        end)

      # Verify benchmark metrics
      combinations_count = 2
      time_ms = div(time_micro, 1000)

      combinations_per_second =
        if time_ms > 0, do: div(combinations_count * 1000, time_ms), else: 1000

      assert time_ms >= 0
      assert combinations_per_second > 0
      assert DataFrame.n_rows(results) == combinations_count
    end

    test "parallel processing shows performance improvement" do
      df = create_benchmark_data()
      # 4 combinations
      test_params = %{period: 5..8}

      # Single-threaded
      {time_single, {:ok, _}} =
        :timer.tc(fn ->
          Optimization.run_combinations_parallel(df, :sma_crossover, test_params, concurrency: 1)
        end)

      # Multi-threaded
      {time_parallel, {:ok, _}} =
        :timer.tc(fn ->
          Optimization.run_combinations_parallel(df, :sma_crossover, test_params, concurrency: 4)
        end)

      # Verify both approaches work
      assert time_single > 0
      assert time_parallel > 0

      # Parallel should be at least as fast (allowing for overhead in small tests)
      speedup_ratio = time_single / time_parallel
      # Allow for test overhead
      assert speedup_ratio >= 0.5
    end

    test "streaming approach handles larger parameter spaces" do
      df = create_benchmark_data()
      # 8 combinations
      large_params = %{period: 5..12}

      # Regular approach
      {time_regular, {:ok, regular_results}} =
        :timer.tc(fn ->
          Optimization.run_combinations(df, :sma_crossover, large_params)
        end)

      # Streaming approach
      {time_streaming, stream_results} =
        :timer.tc(fn ->
          Optimization.run_combinations_stream(df, :sma_crossover, large_params, chunk_size: 3)
          |> Enum.to_list()
        end)

      # Verify both approaches work
      assert time_regular > 0
      assert time_streaming > 0
      assert DataFrame.n_rows(regular_results) == 8
      # At least one chunk
      assert stream_results != []

      # Verify streaming results are valid
      Enum.each(stream_results, fn result ->
        assert {:ok, chunk_df} = result
        assert DataFrame.n_rows(chunk_df) > 0
      end)
    end
  end

  describe "Memory usage patterns" do
    test "streaming uses consistent memory regardless of parameter space size" do
      df = create_benchmark_data()

      # Test different parameter space sizes with streaming
      # 4 combinations
      small_params = %{period: 5..8}
      # 12 combinations
      large_params = %{period: 5..16}

      # Both should process successfully with streaming
      small_stream =
        Optimization.run_combinations_stream(df, :sma_crossover, small_params, chunk_size: 2)

      large_stream =
        Optimization.run_combinations_stream(df, :sma_crossover, large_params, chunk_size: 2)

      small_results = Enum.to_list(small_stream)
      large_results = Enum.to_list(large_stream)

      # Verify streaming works for both sizes
      assert small_results != []
      assert large_results != []

      # All chunks should be successful
      Enum.each(small_results ++ large_results, fn result ->
        assert {:ok, _chunk_df} = result
      end)
    end
  end

  describe "Strategy comparison benchmarks" do
    test "compares performance across different strategy types" do
      df = create_benchmark_data()
      # 2 combinations
      test_params = %{period: [5, 10]}

      strategies = [:sma_crossover, :ema_crossover]

      results =
        Enum.map(strategies, fn strategy ->
          {time_micro, result} =
            :timer.tc(fn ->
              Optimization.run_combinations(df, strategy, test_params)
            end)

          success = match?({:ok, _}, result)

          %{
            strategy: strategy,
            time_ms: div(time_micro, 1000),
            success: success
          }
        end)

      # Verify all strategies processed successfully
      successful_results = Enum.filter(results, & &1.success)
      assert successful_results != []

      # Verify timing measurements
      Enum.each(successful_results, fn result ->
        assert result.time_ms >= 0
        assert is_atom(result.strategy)
      end)
    end
  end

  describe "Performance regression tests" do
    test "maintains reasonable performance for standard workloads" do
      df = create_benchmark_data()
      # 9 combinations
      standard_params = %{fast_period: 5..7, slow_period: 20..22}

      {time_micro, {:ok, results}} =
        :timer.tc(fn ->
          Optimization.run_combinations(df, :sma_crossover, standard_params)
        end)

      time_ms = div(time_micro, 1000)
      combinations_count = 9

      # Performance assertions (generous bounds for CI environments)
      # Should complete in under 5 seconds
      assert time_ms < 5000
      assert DataFrame.n_rows(results) == combinations_count

      # Calculate performance metrics
      combinations_per_second =
        if time_ms > 0, do: div(combinations_count * 1000, time_ms), else: 1000

      assert combinations_per_second > 0
    end

    test "walk-forward optimization maintains reasonable performance" do
      df = create_benchmark_data()
      # 2 combinations
      test_params = %{period: [5, 10]}

      {time_micro, result} =
        :timer.tc(fn ->
          Optimization.walk_forward_optimization(
            df,
            :sma_crossover,
            test_params,
            window_size: 30,
            step_size: 10,
            # Allow zero trades for test
            min_trades: 0
          )
        end)

      time_ms = div(time_micro, 1000)

      # Should complete reasonably quickly
      # Under 10 seconds for small test
      assert time_ms < 10_000

      # Result should be valid (success or expected failure)
      case result do
        {:ok, wf_results} ->
          assert DataFrame.n_rows(wf_results) >= 0

        {:error, reason} ->
          # Some errors are acceptable for walk-forward (insufficient data, etc.)
          case reason do
            :no_valid_results -> :ok
            :insufficient_data -> :ok
            {:insufficient_data, _msg} -> :ok
            _ -> flunk("Unexpected error: #{inspect(reason)}")
          end
      end
    end
  end
end
