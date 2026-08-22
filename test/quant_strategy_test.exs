defmodule Quant.StrategyTest do
  @moduledoc """
  Tests for the main Quant.Strategy module.

  These tests verify the basic strategy mechanism functionality
  including signal generation, strategy composition, and backtesting.
  """

  use ExUnit.Case, async: true
  alias Explorer.DataFrame
  alias Quant.Strategy

  # Test data - realistic stock price movements
  @test_data %{
    close: [
      100.0,
      102.0,
      101.0,
      103.0,
      105.0,
      104.0,
      106.0,
      108.0,
      107.0,
      109.0,
      111.0,
      110.0,
      112.0,
      114.0,
      113.0,
      115.0,
      117.0,
      116.0,
      118.0,
      120.0
    ]
  }

  describe "generate_signals/3" do
    test "generates signals for SMA crossover strategy" do
      df = DataFrame.new(@test_data)
      strategy = Strategy.sma_crossover(fast_period: 3, slow_period: 5)

      assert {:ok, result_df} = Strategy.generate_signals(df, strategy)

      # Check that signal columns were added
      assert "signal" in DataFrame.names(result_df)
      assert "signal_strength" in DataFrame.names(result_df)
      assert "signal_reason" in DataFrame.names(result_df)

      # Check that moving averages were added
      assert "close_sma_3" in DataFrame.names(result_df)
      # Verify data types
      assert "close_sma_5" in DataFrame.names(result_df)
      signals = DataFrame.pull(result_df, "signal")
      assert Enum.all?(Explorer.Series.to_list(signals), fn s -> s in [-1, 0, 1] end)
    end

    test "generates signals for EMA crossover strategy" do
      df = DataFrame.new(@test_data)
      strategy = Strategy.ema_crossover(fast_period: 3, slow_period: 5)

      assert {:ok, result_df} = Strategy.generate_signals(df, strategy)

      # Check that EMA columns were added
      assert "close_ema_3" in DataFrame.names(result_df)
      assert "close_ema_5" in DataFrame.names(result_df)

      # Check signal columns
      assert "signal" in DataFrame.names(result_df)
      assert "signal_strength" in DataFrame.names(result_df)
    end

    test "generates signals for RSI threshold strategy" do
      # Need more data for RSI calculation
      extended_data = %{
        close:
          List.duplicate(100.0, 5) ++
            Enum.to_list(95..105) ++
            List.duplicate(105.0, 5)
      }

      df = DataFrame.new(extended_data)
      strategy = Strategy.rsi_threshold(period: 14, oversold: 30, overbought: 70)

      assert {:ok, result_df} = Strategy.generate_signals(df, strategy)

      # Check that RSI column was added
      assert "close_rsi_14" in DataFrame.names(result_df)

      # Check signal columns
      assert "signal" in DataFrame.names(result_df)
      assert "signal_strength" in DataFrame.names(result_df)
    end

    test "handles invalid strategy type" do
      df = DataFrame.new(@test_data)
      invalid_strategy = %{type: :invalid_strategy, column: :close}

      assert {:error, {:unsupported_strategy, :invalid_strategy}} =
               Strategy.generate_signals(df, invalid_strategy)
    end

    test "handles empty dataframe" do
      empty_df = DataFrame.new(%{close: []})
      strategy = Strategy.sma_crossover(fast_period: 3, slow_period: 5)

      assert {:error, :empty_dataframe} = Strategy.generate_signals(empty_df, strategy)
    end

    test "handles insufficient data" do
      # Only 2 rows
      small_df = DataFrame.new(%{close: [100.0, 101.0]})
      # Needs 5 rows minimum
      strategy = Strategy.sma_crossover(fast_period: 3, slow_period: 5)

      assert {:error, {:insufficient_data, _}} = Strategy.generate_signals(small_df, strategy)
    end
  end

  describe "composite strategies" do
    test "creates composite strategy with ALL logic" do
      strategies = [
        Strategy.sma_crossover(fast_period: 3, slow_period: 5),
        Strategy.rsi_threshold(period: 14, oversold: 30, overbought: 70)
      ]

      composite = Strategy.composite(strategies, logic: :all)

      assert composite.type == :composite
      assert composite.logic == :all
      assert length(composite.strategies) == 2
    end

    test "generates signals for composite strategy" do
      # Need sufficient data for both SMA and RSI
      extended_data = %{
        # 26 data points
        close: Enum.to_list(95..120)
      }

      df = DataFrame.new(extended_data)

      strategies = [
        Strategy.sma_crossover(fast_period: 3, slow_period: 5),
        Strategy.rsi_threshold(period: 14, oversold: 30, overbought: 70)
      ]

      composite = Strategy.composite(strategies, logic: :all)

      assert {:ok, result_df} = Strategy.generate_signals(df, composite)

      # Check that all indicators were added
      assert "close_sma_3" in DataFrame.names(result_df)
      assert "close_sma_5" in DataFrame.names(result_df)
      assert "close_rsi_14" in DataFrame.names(result_df)

      # Check signal columns
      assert "signal" in DataFrame.names(result_df)
      assert "signal_strength" in DataFrame.names(result_df)
    end
  end

  describe "backtest/3" do
    test "runs basic backtest" do
      df = DataFrame.new(@test_data)
      strategy = Strategy.sma_crossover(fast_period: 3, slow_period: 5)

      assert {:ok, backtest_df} = Strategy.backtest(df, strategy, initial_capital: 10_000.0)

      # Check that backtest columns were added
      assert "portfolio_value" in DataFrame.names(backtest_df)
      assert "cash" in DataFrame.names(backtest_df)
      assert "gross_exposure" in DataFrame.names(backtest_df)
      assert "net_exposure" in DataFrame.names(backtest_df)
      assert "exposure_ledger" in DataFrame.names(backtest_df)
      assert "position" in DataFrame.names(backtest_df)
      assert "trade_return" in DataFrame.names(backtest_df)
      assert "total_return" in DataFrame.names(backtest_df)
      assert "max_drawdown" in DataFrame.names(backtest_df)
      assert "win_rate" in DataFrame.names(backtest_df)
      assert "trade_count" in DataFrame.names(backtest_df)

      # Verify portfolio value is reasonable
      portfolio_values =
        DataFrame.pull(backtest_df, "portfolio_value") |> Explorer.Series.to_list()

      assert Enum.all?(portfolio_values, &is_number/1)
      # Portfolio value should be positive
      assert Enum.all?(portfolio_values, &(&1 > 0))
    end

    test "backtest with custom parameters" do
      df = DataFrame.new(@test_data)
      strategy = Strategy.sma_crossover(fast_period: 3, slow_period: 5)

      opts = [
        initial_capital: 50_000.0,
        commission: 0.002,
        slippage: 0.001
      ]

      assert {:ok, backtest_df} = Strategy.backtest(df, strategy, opts)

      # First portfolio value should equal initial capital
      portfolio_values =
        DataFrame.pull(backtest_df, "portfolio_value") |> Explorer.Series.to_list()

      initial_value = List.first(portfolio_values)
      # Allow for small rounding differences
      assert abs(initial_value - 50_000.0) < 1.0
    end
  end

  describe "strategy creation helpers" do
    test "sma_crossover/1 creates valid strategy" do
      strategy = Strategy.sma_crossover(fast_period: 12, slow_period: 26)

      assert strategy.type == :sma_crossover
      assert strategy.indicator == :sma
      assert strategy.fast_period == 12
      assert strategy.slow_period == 26
      assert strategy.column == :close
    end

    test "ema_crossover/1 creates valid strategy" do
      strategy = Strategy.ema_crossover(fast_period: 8, slow_period: 21)

      assert strategy.type == :ema_crossover
      assert strategy.indicator == :ema
      assert strategy.fast_period == 8
      assert strategy.slow_period == 21
    end

    test "rsi_threshold/1 creates valid strategy" do
      strategy = Strategy.rsi_threshold(period: 14, oversold: 25, overbought: 75)

      assert strategy.type == :rsi_threshold
      assert strategy.period == 14
      assert strategy.oversold == 25
      assert strategy.overbought == 75
    end
  end
end
