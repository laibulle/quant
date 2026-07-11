defmodule Quant.Strategy.BacktestPortfolioTest do
  use ExUnit.Case, async: true

  alias Explorer.{DataFrame, Series}
  alias Quant.Strategy.Backtest

  test "manages independent positions for multiple symbols with shared capital" do
    signals =
      DataFrame.new(%{
        timestamp: [
          ~U[2026-01-01 00:00:00Z],
          ~U[2026-01-01 00:00:00Z],
          ~U[2026-01-02 00:00:00Z],
          ~U[2026-01-02 00:00:00Z]
        ],
        symbol: ["AAA", "BBB", "AAA", "BBB"],
        open: [10.0, 20.0, 12.0, 18.0],
        close: [10.0, 20.0, 12.0, 18.0],
        signal: [1, 1, -1, -1]
      })

    assert {:ok, result} =
             Backtest.execute_backtest(signals,
               initial_capital: 10_000.0,
               position_size: {:fixed, 1_000.0},
               commission: 0.0,
               slippage: 0.0,
               execute_on: :close,
               max_positions: 2
             )

    assert Series.to_list(result["position"]) == [100.0, 50.0, 0.0, 0.0]
    assert Series.to_list(result["trade_count"]) == [2, 2, 2, 2]
    assert_in_delta List.last(Series.to_list(result["portfolio_value"])), 10_100.0, 1.0e-12
  end

  test "supports short positions and realizes profit when the price falls" do
    signals =
      DataFrame.new(%{
        timestamp: [
          ~U[2026-01-01 00:00:00Z],
          ~U[2026-01-02 00:00:00Z],
          ~U[2026-01-03 00:00:00Z]
        ],
        symbol: ["AAA", "AAA", "AAA"],
        close: [10.0, 8.0, 7.0],
        signal: [-1, 0, 1]
      })

    assert {:ok, result} =
             Backtest.execute_backtest(signals,
               initial_capital: 10_000.0,
               position_size: {:fixed, 1_000.0},
               commission: 0.0,
               slippage: 0.0,
               execute_on: :close,
               allow_short: true
             )

    assert Series.to_list(result["position"]) == [-100.0, -100.0, 0.0]
    assert_in_delta List.last(Series.to_list(result["portfolio_value"])), 10_300.0, 1.0e-12
    assert_in_delta List.last(Series.to_list(result["trade_return"])), 0.3, 1.0e-12
  end

  test "optionally closes a remaining position on its final bar" do
    signals =
      DataFrame.new(%{
        timestamp: [~U[2026-01-01 00:00:00Z], ~U[2026-01-02 00:00:00Z]],
        symbol: ["AAA", "AAA"],
        close: [10.0, 11.0],
        signal: [1, 0]
      })

    assert {:ok, result} =
             Backtest.execute_backtest(signals,
               initial_capital: 10_000.0,
               position_size: {:fixed, 1_000.0},
               commission: 0.0,
               slippage: 0.0,
               execute_on: :close,
               close_final_position: true
             )

    assert Series.to_list(result["position"]) == [100.0, 0.0]
    assert_in_delta List.last(Series.to_list(result["portfolio_value"])), 10_100.0, 1.0e-12
    assert_in_delta List.last(Series.to_list(result["trade_return"])), 0.1, 1.0e-12
  end

  test "uses an explicit deterministic policy when stop and take-profit collide intrabar" do
    signals =
      DataFrame.new(%{
        timestamp: [~U[2026-01-01 00:00:00Z], ~U[2026-01-02 00:00:00Z]],
        symbol: ["AAA", "AAA"],
        close: [10.0, 10.0],
        high: [10.0, 12.0],
        low: [10.0, 8.0],
        signal: [1, 0]
      })

    base_options = [
      initial_capital: 10_000.0,
      position_size: {:fixed, 1_000.0},
      commission: 0.0,
      slippage: 0.0,
      execute_on: :close,
      stop_loss: 0.1,
      take_profit: 0.1
    ]

    assert {:ok, stop_first} = Backtest.execute_backtest(signals, base_options)

    assert {:ok, take_first} =
             Backtest.execute_backtest(
               signals,
               Keyword.put(base_options, :intrabar_exit_policy, :take_profit_first)
             )

    assert Series.to_list(stop_first["position"]) == [100.0, 0.0]
    assert_in_delta List.last(Series.to_list(stop_first["trade_return"])), -0.1, 1.0e-12
    assert_in_delta List.last(Series.to_list(take_first["trade_return"])), 0.1, 1.0e-12
  end
end
