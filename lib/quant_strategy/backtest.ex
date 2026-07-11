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
  alias Quant.Strategy.Order
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
          intrabar_exit_policy: :stop_first | :take_profit_first,
          entry_order: :market | {:limit | :stop, number()},
          exit_order: :market | {:limit | :stop, number()},
          max_volume_participation: float() | nil,
          short_borrow_rate_per_bar: float(),
          short_maintenance_margin: float()
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
  - `:entry_order` - Market order (default), `{:limit, price}` or
    `{:stop, price}` for pending entries
  - `:exit_order` - Market order (default), `{:limit, price}` or
    `{:stop, price}` for pending signal exits
  - `:max_volume_participation` - Optional fraction of a bar's reported volume
    available to each conditional-order fill (strictly greater than 0 and at
    most 1)
  - `:short_borrow_rate_per_bar` - Borrow rate charged on each bar where a
    short remains open (default: `0.0`)
  - `:short_maintenance_margin` - Minimum portfolio equity divided by gross
    short exposure before forced close-out (default: `0.25`)

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
    entry_order = Keyword.get(opts, :entry_order, :market)
    exit_order = Keyword.get(opts, :exit_order, :market)
    max_volume_participation = Keyword.get(opts, :max_volume_participation)
    short_borrow_rate_per_bar = Keyword.get(opts, :short_borrow_rate_per_bar, 0.0)
    short_maintenance_margin = Keyword.get(opts, :short_maintenance_margin, 0.25)

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
      intrabar_exit_policy: intrabar_exit_policy,
      entry_order: entry_order,
      exit_order: exit_order,
      max_volume_participation: max_volume_participation,
      short_borrow_rate_per_bar: short_borrow_rate_per_bar,
      short_maintenance_margin: short_maintenance_margin
    }

    with :ok <- validate_execution_options(execution_options) do
      if portfolio_engine?(
           max_positions,
           allow_short,
           close_final_position,
           stop_loss,
           take_profit,
           entry_order,
           exit_order,
           max_volume_participation
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

  defp portfolio_engine?(
         max_positions,
         allow_short,
         close_final_position,
         stop_loss,
         take_profit,
         entry_order,
         exit_order,
         max_volume_participation
       ) do
    max_positions > 1 or allow_short or close_final_position or not is_nil(stop_loss) or
      not is_nil(take_profit) or entry_order != :market or exit_order != :market or
      not is_nil(max_volume_participation)
  end

  defp execute_portfolio_backtest_rows(signals_df, initial_capital, execution_options) do
    rows = portfolio_rows(signals_df)
    final_row_indexes = final_row_indexes(rows)

    initial_state = %{
      capital: initial_capital,
      positions: %{},
      last_prices: %{},
      pending_signals: %{},
      pending_orders: %{},
      last_order: nil,
      pending_fill_return: 0.0,
      last_borrow_cost: 0.0,
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

        state = %{
          put_in(state, [:last_prices, symbol], close_price)
          | last_order: nil,
            pending_fill_return: 0.0,
            last_borrow_cost: 0.0
        }

        state = apply_short_borrow_cost(state, symbol, close_price, execution_options)

        {state, margin_trade_return, margin_liquidated?} =
          maybe_liquidate_short_position(
            state,
            symbol,
            close_price,
            index,
            execution_options
          )

        state =
          state
          |> maybe_cancel_pending_entry(symbol, raw_signal)
          |> maybe_fill_pending_order(symbol, row, index, execution_options)

        {state, intrabar_trade_return} =
          maybe_exit_intrabar(state, symbol, row, index, execution_options)

        {state, trade_return} =
          if margin_liquidated? do
            {state, 0.0}
          else
            process_portfolio_signal(
              state,
              symbol,
              signal,
              execution_price,
              index,
              execution_options
            )
          end

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
          trade_return:
            state.pending_fill_return + margin_trade_return + intrabar_trade_return + trade_return +
              final_trade_return,
          order: state.last_order,
          borrow_cost: state.last_borrow_cost,
          short_margin_ratio: short_margin_ratio(state)
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
      |> DataFrame.put(
        "borrow_cost",
        Series.from_list(Enum.map(ordered_results, & &1.borrow_cost))
      )
      |> DataFrame.put(
        "short_margin_ratio",
        Series.from_list(Enum.map(ordered_results, & &1.short_margin_ratio))
      )
      |> add_order_audit_columns(ordered_results)
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
        {open_or_queue_position(state, symbol, :long, price, execution_options), 0.0}

      nil
      when signal == -1 and execution_options.allow_short and
             map_size(state.positions) < execution_options.max_positions ->
        {open_or_queue_position(state, symbol, :short, price, execution_options), 0.0}

      %{direction: :long} when signal == -1 ->
        close_or_queue_position(state, symbol, :sell, price, index, execution_options)

      %{direction: :short} when signal == 1 ->
        close_or_queue_position(state, symbol, :buy, price, index, execution_options)

      _ ->
        {state, 0.0}
    end
  end

  defp apply_short_borrow_cost(
         state,
         symbol,
         price,
         %{short_borrow_rate_per_bar: rate}
       )
       when is_number(price) and rate > 0 do
    case Map.get(state.positions, symbol) do
      %{direction: :short, quantity: quantity} ->
        borrow_cost = abs(quantity) * price * rate
        %{state | capital: state.capital - borrow_cost, last_borrow_cost: borrow_cost}

      _ ->
        state
    end
  end

  defp apply_short_borrow_cost(state, _symbol, _price, _execution_options), do: state

  defp maybe_liquidate_short_position(state, symbol, price, index, execution_options)
       when is_number(price) do
    case Map.get(state.positions, symbol) do
      %{direction: :short} ->
        liquidate_short_if_needed(state, symbol, price, index, execution_options)

      _ ->
        {state, 0.0, false}
    end
  end

  defp maybe_liquidate_short_position(state, _symbol, _price, _index, _execution_options),
    do: {state, 0.0, false}

  defp liquidate_short_if_needed(state, symbol, price, index, execution_options) do
    if short_margin_breached?(state, execution_options) do
      {state, trade_return} =
        close_portfolio_position(
          state,
          symbol,
          price,
          index,
          execution_options,
          :margin_liquidation
        )

      {state, trade_return, true}
    else
      {state, 0.0, false}
    end
  end

  defp short_margin_breached?(state, %{short_maintenance_margin: maintenance_margin}) do
    case short_margin_ratio(state) do
      ratio when is_number(ratio) -> ratio < maintenance_margin
      nil -> false
    end
  end

  defp short_margin_ratio(state) do
    gross_short_exposure =
      Enum.reduce(state.positions, 0.0, fn {symbol, %{quantity: quantity}}, exposure ->
        if quantity < 0 do
          exposure + abs(quantity) * Map.get(state.last_prices, symbol, 0.0)
        else
          exposure
        end
      end)

    if gross_short_exposure > 0 do
      calculate_portfolio_value(state) / gross_short_exposure
    else
      nil
    end
  end

  defp maybe_exit_intrabar(state, symbol, row, index, execution_options) do
    case Map.get(state.positions, symbol) do
      nil ->
        {state, 0.0}

      position ->
        case intrabar_exit_price(position, row, execution_options) do
          nil ->
            {state, 0.0}

          {price, reason} ->
            close_portfolio_position(state, symbol, price, index, execution_options, reason)
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
    do: {stop_price, :stop_loss}

  defp choose_intrabar_exit(false, true, _stop_price, take_price, _execution_options),
    do: {take_price, :take_profit}

  defp choose_intrabar_exit(true, true, stop_price, _take_price, %{
         intrabar_exit_policy: :stop_first
       }),
       do: {stop_price, :stop_loss}

  defp choose_intrabar_exit(true, true, _stop_price, take_price, %{
         intrabar_exit_policy: :take_profit_first
       }),
       do: {take_price, :take_profit}

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
      close_portfolio_position(state, symbol, price, index, execution_options, :final_close)
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

  defp open_or_queue_position(
         state,
         symbol,
         direction,
         price,
         %{entry_order: :market} = execution_options
       ) do
    case direction do
      :long -> open_long_position(state, symbol, price, execution_options)
      :short -> open_short_position(state, symbol, price, execution_options)
    end
  end

  defp open_or_queue_position(state, symbol, direction, _price, execution_options) do
    {order_type, trigger_price} = execution_options.entry_order
    side = if direction == :long, do: :buy, else: :sell

    position_value =
      calculate_position_size(state.capital, execution_options.position_size_method)

    quantity = position_value / trigger_price

    {:ok, order} =
      Order.new(symbol, side, order_type, quantity,
        trigger_price: trigger_price,
        reason: :signal_entry,
        intent: :entry
      )

    %{state | pending_orders: Map.put(state.pending_orders, symbol, order), last_order: order}
  end

  defp close_or_queue_position(
         state,
         symbol,
         _side,
         price,
         index,
         %{exit_order: :market} = execution_options
       ) do
    close_portfolio_position(state, symbol, price, index, execution_options, :signal_exit)
  end

  defp close_or_queue_position(state, symbol, side, _price, _index, execution_options) do
    if Map.has_key?(state.pending_orders, symbol) do
      {state, 0.0}
    else
      {order_type, trigger_price} = execution_options.exit_order
      position = Map.fetch!(state.positions, symbol)

      {:ok, order} =
        Order.new(symbol, side, order_type, abs(position.quantity),
          trigger_price: trigger_price,
          reason: :signal_exit,
          intent: :exit
        )

      {%{state | pending_orders: Map.put(state.pending_orders, symbol, order), last_order: order},
       0.0}
    end
  end

  defp maybe_fill_pending_order(state, symbol, row, index, execution_options) do
    fill_pending_order(
      Map.get(state.pending_orders, symbol),
      state,
      symbol,
      row,
      index,
      execution_options
    )
  end

  defp fill_pending_order(nil, state, _symbol, _row, _index, _execution_options), do: state

  defp fill_pending_order(order, state, symbol, row, index, execution_options) do
    fill_quantity = conditional_fill_quantity(order, row, execution_options)

    if Order.fillable?(order, order_bar(row)) and fill_quantity > 0 do
      {:ok, filled_order} =
        Order.fill(order, order.trigger_price,
          quantity: fill_quantity,
          commission: execution_options.commission,
          slippage: execution_options.slippage
        )

      apply_filled_pending_order(state, symbol, filled_order, index)
    else
      state
    end
  end

  defp conditional_fill_quantity(order, _row, %{max_volume_participation: nil}),
    do: order.remaining_quantity

  defp conditional_fill_quantity(order, row, %{max_volume_participation: participation}) do
    case row_value(row, "volume") do
      volume when is_number(volume) and volume > 0 ->
        min(order.remaining_quantity, volume * participation)

      _ ->
        0.0
    end
  end

  defp apply_filled_pending_order(state, symbol, %{intent: :entry} = order, _index),
    do: open_filled_pending_position(state, symbol, order)

  defp apply_filled_pending_order(state, symbol, %{intent: :exit} = order, index),
    do: close_filled_pending_position(state, symbol, order, index)

  defp maybe_cancel_pending_entry(state, symbol, signal) do
    case Map.get(state.pending_orders, symbol) do
      %{side: :buy} = order when signal == -1 ->
        {:ok, cancelled_order} = Order.cancel(order)

        %{
          state
          | pending_orders: Map.delete(state.pending_orders, symbol),
            last_order: cancelled_order
        }

      %{side: :sell} = order when signal == 1 ->
        {:ok, cancelled_order} = Order.cancel(order)

        %{
          state
          | pending_orders: Map.delete(state.pending_orders, symbol),
            last_order: cancelled_order
        }

      _ ->
        state
    end
  end

  defp order_bar(row) do
    %{
      high: row_value(row, "high"),
      low: row_value(row, "low"),
      close: row_value(row, "close"),
      volume: row_value(row, "volume")
    }
  end

  defp open_filled_pending_position(state, symbol, %{side: :buy} = order) do
    position = add_to_position(state.positions[symbol], :long, order)

    %{
      state
      | capital:
          state.capital - order.last_fill_quantity * order.fill_price - order.last_fill_fee,
        positions: Map.put(state.positions, symbol, position),
        pending_orders: update_pending_order(state.pending_orders, symbol, order),
        last_order: order
    }
  end

  defp open_filled_pending_position(state, symbol, %{side: :sell} = order) do
    position = add_to_position(state.positions[symbol], :short, order)

    %{
      state
      | capital:
          state.capital + order.last_fill_quantity * order.fill_price - order.last_fill_fee,
        positions: Map.put(state.positions, symbol, position),
        pending_orders: update_pending_order(state.pending_orders, symbol, order),
        last_order: order
    }
  end

  defp add_to_position(nil, :long, order) do
    %{direction: :long, quantity: order.last_fill_quantity, entry_price: order.fill_price}
  end

  defp add_to_position(nil, :short, order) do
    %{direction: :short, quantity: -order.last_fill_quantity, entry_price: order.fill_price}
  end

  defp add_to_position(%{quantity: quantity, entry_price: entry_price}, direction, order) do
    existing_quantity = abs(quantity)
    filled_quantity = order.last_fill_quantity
    total_quantity = existing_quantity + filled_quantity

    %{
      direction: direction,
      quantity: if(direction == :long, do: total_quantity, else: -total_quantity),
      entry_price:
        (existing_quantity * entry_price + filled_quantity * order.fill_price) / total_quantity
    }
  end

  defp close_filled_pending_position(state, symbol, order, index) do
    position = Map.fetch!(state.positions, symbol)
    {proceeds, trade_return, remaining_position} = filled_exit_values(position, order)

    trade = %{
      symbol: symbol,
      direction: position.direction,
      entry_price: position.entry_price,
      exit_price: order.fill_price,
      shares: signed_filled_quantity(position, order),
      return: trade_return,
      index: index
    }

    %{
      state
      | capital: state.capital + proceeds,
        positions: update_position_after_exit(state.positions, symbol, remaining_position),
        pending_orders: update_pending_order(state.pending_orders, symbol, order),
        last_order: order,
        pending_fill_return: trade_return,
        trades: [trade | state.trades],
        trade_count: state.trade_count + 1
    }
  end

  defp filled_exit_values(
         %{direction: :long, quantity: quantity, entry_price: entry_price},
         order
       ) do
    filled_quantity = order.last_fill_quantity
    value = filled_quantity * order.fill_price

    {value - order.last_fill_fee, (order.fill_price - entry_price) / entry_price,
     quantity - filled_quantity}
  end

  defp filled_exit_values(
         %{direction: :short, quantity: quantity, entry_price: entry_price},
         order
       ) do
    filled_quantity = order.last_fill_quantity
    value = filled_quantity * order.fill_price

    {-(value + order.last_fill_fee), (entry_price - order.fill_price) / entry_price,
     quantity + filled_quantity}
  end

  defp signed_filled_quantity(%{direction: :long}, order), do: order.last_fill_quantity
  defp signed_filled_quantity(%{direction: :short}, order), do: -order.last_fill_quantity

  defp update_position_after_exit(positions, symbol, quantity) when abs(quantity) < 1.0e-12,
    do: Map.delete(positions, symbol)

  defp update_position_after_exit(positions, symbol, quantity),
    do: put_in(positions, [symbol, :quantity], quantity)

  defp update_pending_order(pending_orders, symbol, %{status: :filled}),
    do: Map.delete(pending_orders, symbol)

  defp update_pending_order(pending_orders, symbol, order),
    do: Map.put(pending_orders, symbol, order)

  defp open_long_position(state, symbol, price, execution_options) do
    position_value =
      calculate_position_size(state.capital, execution_options.position_size_method)

    entry_price = price * (1 + execution_options.slippage)
    commission_cost = position_value * execution_options.commission
    quantity = (position_value - commission_cost) / entry_price

    position = %{direction: :long, quantity: quantity, entry_price: entry_price}
    order = audit_order(symbol, :buy, quantity, price, execution_options, :signal_entry)

    %{
      state
      | capital: state.capital - position_value,
        last_order: order,
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
    order = audit_order(symbol, :sell, quantity, price, execution_options, :signal_entry)

    %{
      state
      | capital: state.capital + position_value - commission_cost,
        last_order: order,
        positions: Map.put(state.positions, symbol, position)
    }
  end

  defp close_portfolio_position(state, symbol, price, index, execution_options, reason) do
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

    side = if position.direction == :long, do: :sell, else: :buy
    order = audit_order(symbol, side, abs(position.quantity), price, execution_options, reason)

    {
      %{
        state
        | capital: state.capital + proceeds,
          last_order: order,
          positions: Map.delete(state.positions, symbol),
          pending_orders: Map.delete(state.pending_orders, symbol),
          trades: [trade | state.trades],
          trade_count: state.trade_count + 1
      },
      trade_return
    }
  end

  defp audit_order(symbol, side, quantity, price, execution_options, reason) do
    {:ok, order} = Order.new(symbol, side, :market, quantity, reason: reason)

    {:ok, filled_order} =
      Order.fill(order, price,
        commission: execution_options.commission,
        slippage: execution_options.slippage
      )

    filled_order
  end

  defp add_order_audit_columns(dataframe, results) do
    orders = Enum.map(results, & &1.order)

    dataframe
    |> DataFrame.put("order_status", Series.from_list(Enum.map(orders, &order_status/1)))
    |> DataFrame.put("order_type", Series.from_list(Enum.map(orders, &order_type/1)))
    |> DataFrame.put("order_side", Series.from_list(Enum.map(orders, &order_side/1)))
    |> DataFrame.put(
      "order_quantity",
      Series.from_list(Enum.map(orders, &order_field(&1, :quantity)))
    )
    |> DataFrame.put(
      "order_filled_quantity",
      Series.from_list(Enum.map(orders, &order_field(&1, :filled_quantity)))
    )
    |> DataFrame.put(
      "order_remaining_quantity",
      Series.from_list(Enum.map(orders, &order_field(&1, :remaining_quantity)))
    )
    |> DataFrame.put(
      "order_trigger_price",
      Series.from_list(Enum.map(orders, &order_field(&1, :trigger_price)))
    )
    |> DataFrame.put("order_reason", Series.from_list(Enum.map(orders, &order_reason/1)))
    |> DataFrame.put(
      "fill_price",
      Series.from_list(Enum.map(orders, &order_field(&1, :fill_price)))
    )
    |> DataFrame.put("fee", Series.from_list(Enum.map(orders, &order_field(&1, :fee))))
    |> DataFrame.put(
      "slippage_cost",
      Series.from_list(Enum.map(orders, &order_field(&1, :slippage_cost)))
    )
  end

  defp order_status(nil), do: nil
  defp order_status(order), do: Atom.to_string(order.status)
  defp order_type(nil), do: nil
  defp order_type(order), do: Atom.to_string(order.type)
  defp order_side(nil), do: nil
  defp order_side(order), do: Atom.to_string(order.side)
  defp order_reason(nil), do: nil
  defp order_reason(%{reason: nil}), do: nil
  defp order_reason(order), do: Atom.to_string(order.reason)
  defp order_field(nil, _field), do: nil
  defp order_field(order, field), do: Map.get(order, field)

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

  defp validate_execution_options(%{
         execute_on: execute_on,
         max_positions: max_positions,
         stop_loss: stop_loss,
         take_profit: take_profit,
         allow_short: allow_short,
         close_final_position: close_final_position,
         intrabar_exit_policy: intrabar_exit_policy,
         entry_order: entry_order,
         exit_order: exit_order,
         max_volume_participation: max_volume_participation,
         short_borrow_rate_per_bar: short_borrow_rate_per_bar,
         short_maintenance_margin: short_maintenance_margin
       }) do
    with :ok <- validate_execution_timing(execute_on, stop_loss, take_profit),
         :ok <- validate_max_positions(max_positions),
         :ok <- validate_stop_loss(stop_loss),
         :ok <- validate_take_profit(take_profit),
         :ok <- validate_boolean_option(allow_short, :allow_short) do
      with :ok <- validate_boolean_option(close_final_position, :close_final_position),
           :ok <- validate_intrabar_exit_policy(intrabar_exit_policy),
           :ok <- validate_entry_order(entry_order),
           :ok <- validate_exit_order(exit_order),
           :ok <- validate_max_volume_participation(max_volume_participation),
           :ok <- validate_short_borrow_rate(short_borrow_rate_per_bar) do
        validate_short_maintenance_margin(short_maintenance_margin)
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
  defp validate_entry_order(:market), do: :ok

  defp validate_entry_order({type, price})
       when type in [:limit, :stop] and is_number(price) and price > 0,
       do: :ok

  defp validate_entry_order(_entry_order), do: {:error, :invalid_entry_order}

  defp validate_exit_order(:market), do: :ok

  defp validate_exit_order({type, price})
       when type in [:limit, :stop] and is_number(price) and price > 0,
       do: :ok

  defp validate_exit_order(_exit_order), do: {:error, :invalid_exit_order}

  defp validate_max_volume_participation(nil), do: :ok

  defp validate_max_volume_participation(value)
       when is_number(value) and value > 0 and value <= 1,
       do: :ok

  defp validate_max_volume_participation(_value), do: {:error, :invalid_max_volume_participation}

  defp validate_short_borrow_rate(value) when is_number(value) and value >= 0, do: :ok
  defp validate_short_borrow_rate(_value), do: {:error, :invalid_short_borrow_rate_per_bar}

  defp validate_short_maintenance_margin(value) when is_number(value) and value > 0, do: :ok
  defp validate_short_maintenance_margin(_value), do: {:error, :invalid_short_maintenance_margin}

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
