defmodule Quant.Strategy.PerformanceTest do
  use ExUnit.Case, async: true

  alias Explorer.DataFrame
  alias Quant.Strategy.{Backtest, Performance}

  test "executes a close-derived signal on the next bar open by default" do
    signals =
      DataFrame.new(%{
        timestamp: [~U[2026-01-01 00:00:00Z], ~U[2026-01-02 00:00:00Z], ~U[2026-01-03 00:00:00Z]],
        open: [10.0, 20.0, 30.0],
        close: [10.0, 20.0, 30.0],
        signal: [1, 0, -1]
      })

    assert {:ok, result} = Backtest.execute_backtest(signals, commission: 0.0, slippage: 0.0)
    assert Explorer.Series.to_list(result["position"]) == [0.0, 475.0, 475.0]
  end

  test "calculates performance metrics from portfolio values" do
    results =
      DataFrame.new(%{
        portfolio_value: [100.0, 110.0, 99.0, 121.0],
        trade_return: [0.0, 0.1, -0.1, 0.2]
      })

    assert {:ok, metrics} = Performance.analyze(results)
    assert_in_delta metrics.total_return, 0.21, 1.0e-12
    assert_in_delta metrics.maximum_drawdown, 0.1, 1.0e-12
    assert_in_delta metrics.win_rate, 2 / 3, 1.0e-12
    assert metrics.trade_count == 3
    assert_in_delta metrics.profit_factor, 3.0, 1.0e-12
  end
end
