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
    assert Series.to_list(result["order_status"]) == ["filled", nil, "filled"]
    assert Series.to_list(result["order_type"]) == ["market", nil, "market"]
    assert Series.to_list(result["fill_price"]) == [10.0, nil, 7.0]
    assert Series.to_list(result["fee"]) == [0.0, nil, 0.0]
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

  test "keeps a limit entry pending until a later bar reaches its trigger" do
    signals =
      DataFrame.new(%{
        timestamp: [
          ~U[2026-01-01 00:00:00Z],
          ~U[2026-01-02 00:00:00Z],
          ~U[2026-01-03 00:00:00Z]
        ],
        symbol: ["AAA", "AAA", "AAA"],
        close: [100.0, 98.0, 96.0],
        high: [101.0, 99.0, 97.0],
        low: [99.0, 97.0, 95.0],
        signal: [1, 0, 0]
      })

    assert {:ok, result} =
             Backtest.execute_backtest(signals,
               initial_capital: 10_000.0,
               position_size: {:fixed, 960.0},
               commission: 0.0,
               slippage: 0.0,
               execute_on: :close,
               entry_order: {:limit, 96.0}
             )

    assert Series.to_list(result["order_status"]) == ["pending", nil, "filled"]
    assert Series.to_list(result["order_type"]) == ["limit", nil, "limit"]
    assert Series.to_list(result["position"]) == [0.0, 0.0, 10.0]
    assert Series.to_list(result["fill_price"]) == [nil, nil, 96.0]
  end

  test "cancels a pending entry when the opposite signal arrives first" do
    signals =
      DataFrame.new(%{
        timestamp: [~U[2026-01-01 00:00:00Z], ~U[2026-01-02 00:00:00Z]],
        symbol: ["AAA", "AAA"],
        close: [100.0, 100.0],
        high: [101.0, 101.0],
        low: [99.0, 99.0],
        signal: [1, -1]
      })

    assert {:ok, result} =
             Backtest.execute_backtest(signals,
               initial_capital: 10_000.0,
               position_size: {:fixed, 1_000.0},
               commission: 0.0,
               slippage: 0.0,
               execute_on: :close,
               entry_order: {:limit, 90.0}
             )

    assert Series.to_list(result["order_status"]) == ["pending", "cancelled"]
    assert Series.to_list(result["position"]) == [0.0, 0.0]
  end

  test "keeps a signal exit pending until a later bar reaches its limit" do
    signals =
      DataFrame.new(%{
        timestamp: [
          ~U[2026-01-01 00:00:00Z],
          ~U[2026-01-02 00:00:00Z],
          ~U[2026-01-03 00:00:00Z]
        ],
        symbol: ["AAA", "AAA", "AAA"],
        close: [100.0, 104.0, 109.0],
        high: [101.0, 105.0, 111.0],
        low: [99.0, 100.0, 103.0],
        signal: [1, -1, 0]
      })

    assert {:ok, result} =
             Backtest.execute_backtest(signals,
               initial_capital: 10_000.0,
               position_size: {:fixed, 1_000.0},
               commission: 0.0,
               slippage: 0.0,
               execute_on: :close,
               exit_order: {:limit, 110.0}
             )

    assert Series.to_list(result["order_status"]) == ["filled", "pending", "filled"]
    assert Series.to_list(result["order_type"]) == ["market", "limit", "limit"]
    assert Series.to_list(result["position"]) == [10.0, 10.0, 0.0]
    assert Series.to_list(result["fill_price"]) == [100.0, nil, 110.0]
    assert Series.to_list(result["order_side"]) == ["buy", "sell", "sell"]
    assert Series.to_list(result["order_trigger_price"]) == [nil, 110.0, 110.0]

    assert Series.to_list(result["order_reason"]) == [
             "signal_entry",
             "signal_exit",
             "signal_exit"
           ]

    assert_in_delta List.last(Series.to_list(result["trade_return"])), 0.1, 1.0e-12
  end

  test "partially fills a conditional entry according to bar volume" do
    signals =
      DataFrame.new(%{
        timestamp: [
          ~U[2026-01-01 00:00:00Z],
          ~U[2026-01-02 00:00:00Z],
          ~U[2026-01-03 00:00:00Z],
          ~U[2026-01-04 00:00:00Z]
        ],
        symbol: ["AAA", "AAA", "AAA", "AAA"],
        close: [100.0, 100.0, 100.0, 100.0],
        high: [101.0, 101.0, 101.0, 101.0],
        low: [99.0, 99.0, 99.0, 99.0],
        volume: [100.0, 4.0, 6.0, 10.0],
        signal: [1, 0, 0, 0]
      })

    assert {:ok, result} =
             Backtest.execute_backtest(signals,
               initial_capital: 10_000.0,
               position_size: {:fixed, 1_000.0},
               commission: 0.0,
               slippage: 0.0,
               execute_on: :close,
               entry_order: {:limit, 100.0},
               max_volume_participation: 0.5
             )

    assert Series.to_list(result["order_status"]) == [
             "pending",
             "partially_filled",
             "partially_filled",
             "filled"
           ]

    assert Series.to_list(result["position"]) == [0.0, 2.0, 5.0, 10.0]
    assert Series.to_list(result["order_filled_quantity"]) == [0.0, 2.0, 5.0, 10.0]
    assert Series.to_list(result["order_remaining_quantity"]) == [10.0, 8.0, 5.0, 0.0]
  end

  test "charges short borrow costs once for every bar held" do
    signals =
      DataFrame.new(%{
        timestamp: [
          ~U[2026-01-01 00:00:00Z],
          ~U[2026-01-02 00:00:00Z],
          ~U[2026-01-03 00:00:00Z]
        ],
        symbol: ["AAA", "AAA", "AAA"],
        close: [100.0, 100.0, 100.0],
        signal: [-1, 0, 1]
      })

    assert {:ok, result} =
             Backtest.execute_backtest(signals,
               initial_capital: 10_000.0,
               position_size: {:fixed, 1_000.0},
               commission: 0.0,
               slippage: 0.0,
               execute_on: :close,
               allow_short: true,
               short_borrow_rate_per_bar: 0.01
             )

    assert Series.to_list(result["borrow_cost"]) == [0.0, 10.0, 10.0]
    assert_in_delta List.last(Series.to_list(result["portfolio_value"])), 9_980.0, 1.0e-12
  end

  test "liquidates a short when the maintenance margin is breached" do
    signals =
      DataFrame.new(%{
        timestamp: [~U[2026-01-01 00:00:00Z], ~U[2026-01-02 00:00:00Z]],
        symbol: ["AAA", "AAA"],
        close: [100.0, 2_000.0],
        signal: [-1, 0]
      })

    assert {:ok, result} =
             Backtest.execute_backtest(signals,
               initial_capital: 10_000.0,
               position_size: {:fixed, 1_000.0},
               commission: 0.0,
               slippage: 0.0,
               execute_on: :close,
               allow_short: true,
               short_maintenance_margin: 0.25
             )

    assert Series.to_list(result["position"]) == [-10.0, 0.0]
    assert Series.to_list(result["order_reason"]) == ["signal_entry", "margin_liquidation"]
    assert_in_delta List.last(Series.to_list(result["trade_return"])), -19.0, 1.0e-12
  end
end
