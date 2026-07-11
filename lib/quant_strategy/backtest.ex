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
  require Explorer.DataFrame

  @type backtest_options :: [
          initial_capital: float(),
          position_size: atom() | float(),
          commission: float(),
          slippage: float(),
          max_positions: integer(),
          stop_loss: float(),
          take_profit: float(),
          execute_on: :next_open | :close,
          allow_short: boolean(),
          close_final_position: boolean(),
          intrabar_exit_policy: :stop_first | :take_profit_first
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
  - `:allow_short` - Allow `-1` signals to open short positions (default: false)
  - `:close_final_position` - Close remaining positions on each symbol's final
    bar (default: false)
  - `:intrabar_exit_policy` - Collision policy when a bar reaches both stop and
    take-profit levels: `:stop_first` (default) or `:take_profit_first`

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
    execute_on = Keyword.get(opts, :execute_on, :next_open)
    max_positions = Keyword.get(opts, :max_positions, 1)
    stop_loss = Keyword.get(opts, :stop_loss)
    take_profit = Keyword.get(opts, :take_profit)
    allow_short = Keyword.get(opts, :allow_short, false)
    close_final_position = Keyword.get(opts, :close_final_position, false)
    intrabar_exit_policy = Keyword.get(opts, :intrabar_exit_policy, :stop_first)

    execution_options = %{
      commission: commission,
      slippage: slippage,
      position_size_method: position_size_method,
      execute_on: execute_on,
      max_positions: max_positions,
      allow_short: allow_short,
      close_final_position: close_final_position,
      stop_loss: stop_loss,
      take_profit: take_profit,
      intrabar_exit_policy: intrabar_exit_policy
    }

    with :ok <-
           validate_execution_options(
             execute_on,
             max_positions,
             stop_loss,
             take_profit,
             allow_short,
             close_final_position,
             intrabar_exit_policy
           ) do
      if portfolio_engine?(
           max_positions,
           allow_short,
           close_final_position,
           stop_loss,
           take_profit
         ) do
        execute_portfolio_backtest_rows(signals_df, initial_capital, execution_options)
      else
        execute_backtest_rows(
          signals_df,
          initial_capital,
          commission,
          slippage,
          position_size_method,
          execute_on,
          stop_loss,
          take_profit
        )
      end
    end
  rescue
    e -> {:error, {:backtest_execution_failed, Exception.message(e)}}
  end

  defp execute_backtest_rows(
         signals_df,
         initial_capital,
         commission,
         slippage,
         position_size_method,
         execute_on,
         stop_loss,
         take_profit
       ) do
    signals_df = sort_by_timestamp(signals_df)

    # Extract required data
    signals = DataFrame.pull(signals_df, "signal") |> Series.to_list()
    prices = DataFrame.pull(signals_df, "close") |> Series.to_list()
    execution_prices = execution_prices(signals_df, prices, execute_on)
    execution_signals = execution_signals(signals, execute_on)

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
      execution_signals
      |> Enum.zip(Enum.zip(execution_prices, prices))
      |> Enum.with_index()
      |> Enum.reduce({initial_state, [], [], []}, fn {{signal, {execution_price, close_price}},
                                                      index},
                                                     {state, portfolio_acc, position_acc,
                                                      returns_acc} ->
        signal =
          apply_risk_controls(state, signal, close_price, stop_loss, take_profit, execute_on)

        new_state =
          process_signal(
            state,
            signal,
            execution_price,
            index,
            position_size_method,
            commission,
            slippage
          )

        portfolio_value = calculate_portfolio_value(new_state, close_price)

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
  end

  defp portfolio_engine?(max_positions, allow_short, close_final_position, stop_loss, take_profit) do
    max_positions > 1 or allow_short or close_final_position or not is_nil(stop_loss) or
      not is_nil(take_profit)
  end

  defp execute_portfolio_backtest_rows(signals_df, initial_capital, execution_options) do
    rows = portfolio_rows(signals_df)
    final_row_indexes = final_row_indexes(rows)

    initial_state = %{
      capital: initial_capital,
      positions: %{},
      last_prices: %{},
      pending_signals: %{},
      trades: [],
      trade_count: 0
    }

    {final_state, result_rows} =
      rows
      |> Enum.with_index()
      |> Enum.reduce({initial_state, []}, fn {row, index}, {state, results} ->
        symbol = row_value(row, "symbol", "__default__")
        close_price = row_value(row, "close")
        execution_price = execution_price(row, close_price, execution_options.execute_on)
        raw_signal = row_value(row, "signal", 0)
        signal = portfolio_signal(state, symbol, raw_signal, execution_options.execute_on)
        state = put_in(state, [:last_prices, symbol], close_price)

        {state, intrabar_trade_return} =
          maybe_exit_intrabar(state, symbol, row, index, execution_options)

        {state, trade_return} =
          process_portfolio_signal(
            state,
            symbol,
            signal,
            execution_price,
            index,
            execution_options
          )

        {state, final_trade_return} =
          maybe_close_final_position(
            state,
            symbol,
            close_price,
            index,
            final_row_indexes,
            execution_options
          )

        state = put_in(state, [:pending_signals, symbol], raw_signal)
        position = position_quantity(state, symbol)
        portfolio_value = calculate_portfolio_value(state)

        result = %{
          portfolio_value: portfolio_value,
          position: position,
          trade_return: intrabar_trade_return + trade_return + final_trade_return
        }

        {state, [result | results]}
      end)

    ordered_results = Enum.reverse(result_rows)

    result_df =
      signals_df
      |> sorted_portfolio_dataframe(rows)
      |> DataFrame.put(
        "portfolio_value",
        Series.from_list(Enum.map(ordered_results, & &1.portfolio_value))
      )
      |> DataFrame.put("position", Series.from_list(Enum.map(ordered_results, & &1.position)))
      |> DataFrame.put(
        "trade_return",
        Series.from_list(Enum.map(ordered_results, & &1.trade_return))
      )
      |> add_performance_metrics(final_state, initial_capital)

    {:ok, result_df}
  end

  defp portfolio_rows(dataframe) do
    dataframe
    |> DataFrame.to_rows()
    |> Enum.sort_by(fn row ->
      {timestamp_sort_key(row_value(row, "timestamp", 0)),
       row_value(row, "symbol", "__default__")}
    end)
  end

  defp sorted_portfolio_dataframe(_dataframe, rows), do: DataFrame.new(rows)

  defp timestamp_sort_key(%DateTime{} = timestamp), do: DateTime.to_unix(timestamp, :microsecond)
  defp timestamp_sort_key(timestamp), do: timestamp

  defp final_row_indexes(rows) do
    rows
    |> Enum.with_index()
    |> Enum.reduce(%{}, fn {row, index}, indexes ->
      Map.put(indexes, row_value(row, "symbol", "__default__"), index)
    end)
  end

  defp row_value(row, key, default \\ nil), do: Map.get(row, key, default)

  defp execution_price(row, close_price, :next_open), do: row_value(row, "open", close_price)
  defp execution_price(_row, close_price, :close), do: close_price

  defp portfolio_signal(state, symbol, _raw_signal, :next_open),
    do: Map.get(state.pending_signals, symbol, 0)

  defp portfolio_signal(_state, _symbol, raw_signal, :close), do: raw_signal

  defp process_portfolio_signal(state, symbol, signal, price, index, execution_options) do
    case Map.get(state.positions, symbol) do
      nil when signal == 1 and map_size(state.positions) < execution_options.max_positions ->
        {open_long_position(state, symbol, price, execution_options), 0.0}

      nil
      when signal == -1 and execution_options.allow_short and
             map_size(state.positions) < execution_options.max_positions ->
        {open_short_position(state, symbol, price, execution_options), 0.0}

      %{direction: :long} when signal == -1 ->
        close_portfolio_position(state, symbol, price, index, execution_options)

      %{direction: :short} when signal == 1 ->
        close_portfolio_position(state, symbol, price, index, execution_options)

      _ ->
        {state, 0.0}
    end
  end

  defp maybe_exit_intrabar(state, symbol, row, index, execution_options) do
    case Map.get(state.positions, symbol) do
      nil ->
        {state, 0.0}

      position ->
        case intrabar_exit_price(position, row, execution_options) do
          nil -> {state, 0.0}
          price -> close_portfolio_position(state, symbol, price, index, execution_options)
        end
    end
  end

  defp intrabar_exit_price(_position, _row, %{stop_loss: nil, take_profit: nil}), do: nil

  defp intrabar_exit_price(position, row, execution_options) do
    high = row_value(row, "high")
    low = row_value(row, "low")
    {stop_price, take_profit_price} = risk_prices(position, execution_options)

    stop_hit =
      is_number(stop_price) and intrabar_stop_hit?(position.direction, high, low, stop_price)

    take_profit_hit =
      is_number(take_profit_price) and
        intrabar_take_profit_hit?(position.direction, high, low, take_profit_price)

    choose_intrabar_exit(
      stop_hit,
      take_profit_hit,
      stop_price,
      take_profit_price,
      execution_options
    )
  end

  defp risk_prices(%{direction: :long, entry_price: entry_price}, execution_options) do
    {
      if(is_number(execution_options.stop_loss),
        do: entry_price * (1 - execution_options.stop_loss)
      ),
      if(is_number(execution_options.take_profit),
        do: entry_price * (1 + execution_options.take_profit)
      )
    }
  end

  defp risk_prices(%{direction: :short, entry_price: entry_price}, execution_options) do
    {
      if(is_number(execution_options.stop_loss),
        do: entry_price * (1 + execution_options.stop_loss)
      ),
      if(is_number(execution_options.take_profit),
        do: entry_price * (1 - execution_options.take_profit)
      )
    }
  end

  defp intrabar_stop_hit?(:long, _high, low, stop_price), do: is_number(low) and low <= stop_price

  defp intrabar_stop_hit?(:short, high, _low, stop_price),
    do: is_number(high) and high >= stop_price

  defp intrabar_take_profit_hit?(:long, high, _low, take_price),
    do: is_number(high) and high >= take_price

  defp intrabar_take_profit_hit?(:short, _high, low, take_price),
    do: is_number(low) and low <= take_price

  defp choose_intrabar_exit(false, false, _stop_price, _take_price, _execution_options), do: nil

  defp choose_intrabar_exit(true, false, stop_price, _take_price, _execution_options),
    do: stop_price

  defp choose_intrabar_exit(false, true, _stop_price, take_price, _execution_options),
    do: take_price

  defp choose_intrabar_exit(true, true, stop_price, _take_price, %{
         intrabar_exit_policy: :stop_first
       }),
       do: stop_price

  defp choose_intrabar_exit(true, true, _stop_price, take_price, %{
         intrabar_exit_policy: :take_profit_first
       }),
       do: take_price

  defp maybe_close_final_position(
         state,
         symbol,
         price,
         index,
         final_row_indexes,
         %{close_final_position: true} = execution_options
       )
       when is_number(price) do
    if Map.get(final_row_indexes, symbol) == index and Map.has_key?(state.positions, symbol) do
      close_portfolio_position(state, symbol, price, index, execution_options)
    else
      {state, 0.0}
    end
  end

  defp maybe_close_final_position(
         state,
         _symbol,
         _price,
         _index,
         _final_indexes,
         _execution_options
       ),
       do: {state, 0.0}

  defp open_long_position(state, symbol, price, execution_options) do
    position_value =
      calculate_position_size(state.capital, execution_options.position_size_method)

    entry_price = price * (1 + execution_options.slippage)
    commission_cost = position_value * execution_options.commission
    quantity = (position_value - commission_cost) / entry_price

    position = %{direction: :long, quantity: quantity, entry_price: entry_price}

    %{
      state
      | capital: state.capital - position_value,
        positions: Map.put(state.positions, symbol, position)
    }
  end

  defp open_short_position(state, symbol, price, execution_options) do
    position_value =
      calculate_position_size(state.capital, execution_options.position_size_method)

    entry_price = price * (1 - execution_options.slippage)
    commission_cost = position_value * execution_options.commission
    quantity = position_value / entry_price

    position = %{direction: :short, quantity: -quantity, entry_price: entry_price}

    %{
      state
      | capital: state.capital + position_value - commission_cost,
        positions: Map.put(state.positions, symbol, position)
    }
  end

  defp close_portfolio_position(state, symbol, price, index, execution_options) do
    position = Map.fetch!(state.positions, symbol)

    {exit_price, proceeds, trade_return} =
      close_position_values(
        position,
        price,
        execution_options.commission,
        execution_options.slippage
      )

    trade = %{
      symbol: symbol,
      direction: position.direction,
      entry_price: position.entry_price,
      exit_price: exit_price,
      shares: position.quantity,
      return: trade_return,
      index: index
    }

    {
      %{
        state
        | capital: state.capital + proceeds,
          positions: Map.delete(state.positions, symbol),
          trades: [trade | state.trades],
          trade_count: state.trade_count + 1
      },
      trade_return
    }
  end

  defp close_position_values(
         %{direction: :long, quantity: quantity, entry_price: entry_price},
         price,
         commission,
         slippage
       ) do
    exit_price = price * (1 - slippage)
    value = quantity * exit_price
    {exit_price, value - value * commission, (exit_price - entry_price) / entry_price}
  end

  defp close_position_values(
         %{direction: :short, quantity: quantity, entry_price: entry_price},
         price,
         commission,
         slippage
       ) do
    exit_price = price * (1 + slippage)
    value = abs(quantity) * exit_price
    {exit_price, -(value + value * commission), (entry_price - exit_price) / entry_price}
  end

  defp position_quantity(state, symbol) do
    state.positions
    |> Map.get(symbol, %{quantity: 0.0})
    |> Map.fetch!(:quantity)
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

  defp execution_signals(signals, :next_open), do: [0 | Enum.drop(signals, -1)]
  defp execution_signals(signals, :close), do: signals

  defp execution_prices(dataframe, fallback_prices, :next_open) do
    if "open" in DataFrame.names(dataframe) do
      DataFrame.pull(dataframe, "open") |> Series.to_list()
    else
      fallback_prices
    end
  end

  defp execution_prices(_dataframe, fallback_prices, :close), do: fallback_prices

  defp apply_risk_controls(
         %{position: position},
         signal,
         _price,
         _stop_loss,
         _take_profit,
         _execute_on
       )
       when position <= 0,
       do: signal

  defp apply_risk_controls(_state, signal, _price, _stop_loss, _take_profit, :next_open),
    do: signal

  defp apply_risk_controls(state, signal, price, stop_loss, take_profit, :close) do
    entry = state.position_entry_price

    cond do
      is_number(stop_loss) and price <= entry * (1 - stop_loss) -> -1
      is_number(take_profit) and price >= entry * (1 + take_profit) -> -1
      true -> signal
    end
  end

  defp sort_by_timestamp(dataframe) do
    if "timestamp" in DataFrame.names(dataframe),
      do: DataFrame.sort_by(dataframe, asc: timestamp),
      else: dataframe
  end

  defp validate_execution_options(
         execute_on,
         max_positions,
         stop_loss,
         take_profit,
         allow_short,
         close_final_position,
         intrabar_exit_policy
       ) do
    with :ok <- validate_execution_timing(execute_on, stop_loss, take_profit),
         :ok <- validate_max_positions(max_positions),
         :ok <- validate_stop_loss(stop_loss),
         :ok <- validate_take_profit(take_profit),
         :ok <- validate_boolean_option(allow_short, :allow_short) do
      with :ok <- validate_boolean_option(close_final_position, :close_final_position) do
        validate_intrabar_exit_policy(intrabar_exit_policy)
      end
    end
  end

  defp validate_execution_timing(execute_on, _stop_loss, _take_profit)
       when execute_on in [:next_open, :close], do: :ok

  defp validate_execution_timing(execute_on, _stop_loss, _take_profit),
    do: {:error, {:invalid_execute_on, execute_on}}

  defp validate_max_positions(value) when is_integer(value) and value > 0, do: :ok
  defp validate_max_positions(_max_positions), do: {:error, :invalid_max_positions}
  defp validate_stop_loss(nil), do: :ok
  defp validate_stop_loss(value) when is_number(value) and value > 0 and value < 1, do: :ok
  defp validate_stop_loss(_value), do: {:error, :invalid_stop_loss}
  defp validate_take_profit(nil), do: :ok
  defp validate_take_profit(value) when is_number(value) and value > 0, do: :ok
  defp validate_take_profit(_value), do: {:error, :invalid_take_profit}
  defp validate_boolean_option(value, _name) when is_boolean(value), do: :ok
  defp validate_boolean_option(_value, name), do: {:error, {:invalid_option, name}}

  defp validate_intrabar_exit_policy(policy) when policy in [:stop_first, :take_profit_first],
    do: :ok

  defp validate_intrabar_exit_policy(_policy), do: {:error, :invalid_intrabar_exit_policy}

  defp calculate_portfolio_value(%{
         capital: capital,
         positions: positions,
         last_prices: last_prices
       }) do
    positions_value =
      Enum.reduce(positions, 0.0, fn {symbol, %{quantity: quantity}}, total ->
        total + quantity * Map.get(last_prices, symbol, 0.0)
      end)

    capital + positions_value
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
