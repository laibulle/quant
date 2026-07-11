defmodule Quant.Strategy.Backtest do
  @moduledoc """
  Basic backtesting engine for strategy validation.

  This module provides a simple backtesting framework to evaluate
  trading strategies against historical data and calculate performance metrics.

  ## Features

  - Portfolio value tracking over time
  - Position management and trade execution
  - Performance metrics calculation
  - Risk management (stop losses, position sizing)
  - Commission and slippage modeling

  ## Example Usage

      strategy = Quant.Strategy.sma_crossover(fast_period: 12, slow_period: 26)
      {:ok, results} = Quant.Strategy.Backtest.run(historical_data, strategy,
        initial_capital: 10000.0,
        commission: 0.001
      )

  """

  alias Explorer.DataFrame
  alias Explorer.Series
  alias Quant.Strategy

  @type backtest_options :: [
          initial_capital: float(),
          position_size: atom() | float(),
          commission: float(),
          slippage: float(),
          max_positions: integer(),
          stop_loss: float(),
          take_profit: float()
        ]

  @doc """
  Run a backtest for the given strategy on historical data.

  ## Parameters

  - `dataframe` - Historical OHLCV data
  - `strategy` - Strategy configuration
  - `opts` - Backtesting options

  ## Options

  - `:initial_capital` - Starting capital (default: 10000.0)
  - `:position_size` - Position sizing method or fixed amount (default: :percent_capital)
  - `:commission` - Trading commission rate (default: 0.001)
  - `:slippage` - Market slippage rate (default: 0.0005)
  - `:max_positions` - Maximum concurrent positions (default: 1)
  - `:stop_loss` - Stop loss percentage (default: nil)
  - `:take_profit` - Take profit percentage (default: nil)

  ## Returns

  DataFrame with backtest results including:
  - Portfolio value over time
  - Positions and trades
  - Performance metrics

  """
  @spec run(DataFrame.t(), map(), backtest_options()) :: {:ok, DataFrame.t()} | {:error, term()}
  def run(dataframe, strategy, opts \\ []) do
    with {:ok, signals_df} <- Strategy.generate_signals(dataframe, strategy),
         {:ok, backtest_df} <- execute_backtest(signals_df, opts) do
      {:ok, backtest_df}
    else
      {:error, reason} -> {:error, {:backtest_failed, reason}}
    end
  end

  @doc """
  Execute the actual backtesting simulation.

  This function processes signals sequentially and simulates trade execution,
  portfolio value changes, and risk management.

  """
  @spec execute_backtest(DataFrame.t(), backtest_options()) ::
          {:ok, DataFrame.t()} | {:error, term()}
  def execute_backtest(signals_df, opts \\ []) do
    # Initialize backtest parameters
    initial_capital = Keyword.get(opts, :initial_capital, 10_000.0)
    commission = Keyword.get(opts, :commission, 0.001)
    slippage = Keyword.get(opts, :slippage, 0.0005)
    position_size_method = Keyword.get(opts, :position_size, :percent_capital)

    # Extract required data
    signals = DataFrame.pull(signals_df, "signal") |> Series.to_list()
    prices = DataFrame.pull(signals_df, "close") |> Series.to_list()

    # Initialize portfolio state
    initial_state = %{
      capital: initial_capital,
      position: 0.0,
      position_entry_price: nil,
      total_value: initial_capital,
      trades: [],
      trade_count: 0
    }

    # Process signals sequentially
    {final_state, portfolio_values, positions, trade_returns} =
      signals
      |> Enum.zip(prices)
      |> Enum.with_index()
      |> Enum.reduce({initial_state, [], [], []}, fn {{signal, price}, index},
                                                     {state, portfolio_acc, position_acc,
                                                      returns_acc} ->
        new_state =
          process_signal(
            state,
            signal,
            price,
            index,
            position_size_method,
            commission,
            slippage
          )

        portfolio_value = calculate_portfolio_value(new_state, price)

        # Calculate trade return if position was closed
        trade_return =
          if new_state.trade_count > state.trade_count do
            List.last(new_state.trades)[:return] || 0.0
          else
            0.0
          end

        {
          new_state,
          [portfolio_value | portfolio_acc],
          [new_state.position | position_acc],
          [trade_return | returns_acc]
        }
      end)

    # Add backtest results to DataFrame
    result_df =
      signals_df
      |> DataFrame.put("portfolio_value", Series.from_list(Enum.reverse(portfolio_values)))
      |> DataFrame.put("position", Series.from_list(Enum.reverse(positions)))
      |> DataFrame.put("trade_return", Series.from_list(Enum.reverse(trade_returns)))
      |> add_performance_metrics(final_state, initial_capital)

    {:ok, result_df}
  rescue
    e -> {:error, {:backtest_execution_failed, Exception.message(e)}}
  end

  # Private helper functions

  defp process_signal(state, signal, price, index, position_size_method, commission, slippage) do
    cond do
      # Buy signal and no current position
      signal == 1 and state.position == 0.0 ->
        execute_buy(state, price, index, position_size_method, commission, slippage)

      # Sell signal and have long position
      signal == -1 and state.position > 0.0 ->
        execute_sell(state, price, index, commission, slippage)

      # No signal or signal doesn't apply to current position
      true ->
        state
    end
  end

  defp execute_buy(state, price, _index, position_size_method, commission, slippage) do
    position_value = calculate_position_size(state.capital, position_size_method)
    # Account for slippage
    execution_price = price * (1 + slippage)
    commission_cost = position_value * commission

    shares = (position_value - commission_cost) / execution_price

    %{
      state
      | capital: state.capital - position_value,
        position: shares,
        position_entry_price: execution_price,
        trade_count: state.trade_count
    }
  end

  defp execute_sell(state, price, index, commission, slippage) do
    # Account for slippage
    execution_price = price * (1 - slippage)
    position_value = state.position * execution_price
    commission_cost = position_value * commission

    proceeds = position_value - commission_cost

    # Calculate trade return
    trade_return =
      if state.position_entry_price do
        (execution_price - state.position_entry_price) / state.position_entry_price
      else
        0.0
      end

    trade_record = %{
      entry_price: state.position_entry_price,
      exit_price: execution_price,
      shares: state.position,
      return: trade_return,
      index: index
    }

    %{
      state
      | capital: state.capital + proceeds,
        position: 0.0,
        position_entry_price: nil,
        trades: [trade_record | state.trades],
        trade_count: state.trade_count + 1
    }
  end

  defp calculate_position_size(capital, method) do
    case method do
      # Use 95% of available capital
      :percent_capital -> capital * 0.95
      {:fixed, amount} when is_number(amount) -> min(amount, capital)
      amount when is_number(amount) -> min(amount, capital)
      # Default to 10% of capital
      _ -> capital * 0.1
    end
  end

  defp calculate_portfolio_value(state, current_price) do
    cash_value = state.capital

    position_value =
      if state.position > 0 do
        state.position * current_price
      else
        0.0
      end

    cash_value + position_value
  end

  defp add_performance_metrics(dataframe, final_state, initial_capital) do
    # Calculate basic performance metrics
    portfolio_values = DataFrame.pull(dataframe, "portfolio_value") |> Series.to_list()

    final_value = List.last(portfolio_values)
    total_return = (final_value - initial_capital) / initial_capital

    # Calculate maximum drawdown
    max_drawdown = calculate_max_drawdown(portfolio_values)

    # Calculate win rate
    trade_returns = final_state.trades |> Enum.map(& &1.return)

    win_rate =
      if trade_returns != [] do
        winning_trades = Enum.count(trade_returns, &(&1 > 0))
        winning_trades / length(trade_returns)
      else
        0.0
      end

    # Add performance metrics as constant columns
    row_count = DataFrame.n_rows(dataframe)

    dataframe
    |> DataFrame.put("total_return", Series.from_list(List.duplicate(total_return, row_count)))
    |> DataFrame.put("max_drawdown", Series.from_list(List.duplicate(max_drawdown, row_count)))
    |> DataFrame.put("win_rate", Series.from_list(List.duplicate(win_rate, row_count)))
    |> DataFrame.put(
      "trade_count",
      Series.from_list(List.duplicate(final_state.trade_count, row_count))
    )
  end

  defp calculate_max_drawdown(portfolio_values) do
    {_, max_dd} =
      portfolio_values
      |> Enum.reduce({0.0, 0.0}, fn value, {running_max, max_drawdown} ->
        new_running_max = max(running_max, value)

        current_drawdown =
          if new_running_max > 0 do
            (new_running_max - value) / new_running_max
          else
            0.0
          end

        new_max_drawdown = max(max_drawdown, current_drawdown)

        {new_running_max, new_max_drawdown}
      end)

    max_dd
  end
end
