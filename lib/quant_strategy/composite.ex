defmodule Quant.Strategy.Composite do
  @moduledoc """
  Composite strategy implementation for combining multiple strategies.

  This module allows combining multiple individual strategies using
  various logical operators to create more sophisticated trading systems.

  ## Combination Logic

  - `:all` (AND) - All strategies must agree for signal generation
  - `:any` (OR) - Any strategy can trigger a signal
  - `:majority` - Majority of strategies must agree
  - `:weighted` - Weighted combination based on strategy confidence

  ## Examples

      # Combine SMA crossover with RSI confirmation
      strategies = [
        Quant.Strategy.sma_crossover(fast_period: 12, slow_period: 26),
        Quant.Strategy.rsi_threshold(oversold: 30, overbought: 70)
      ]

      composite = Quant.Strategy.Composite.create(strategies, logic: :all)

  """

  alias Explorer.DataFrame
  alias Explorer.Series
  alias Quant.Strategy.{Momentum, MovingAverage, Signal, Volatility}

  @type combination_logic :: :all | :any | :majority | :weighted
  @type strategy_weight :: {map(), float()}

  @doc """
  Create a composite strategy from multiple individual strategies.

  ## Parameters

  - `strategies` - List of individual strategy configurations
  - `opts` - Composite strategy options

  ## Options

  - `:logic` - Combination logic (`:all`, `:any`, `:majority`, `:weighted`)
  - `:weights` - Strategy weights for weighted combination (list of floats)
  - `:threshold` - Minimum confidence threshold for signal generation
  - `:name` - Name for the composite strategy

  ## Examples

      iex> strategies = [
      ...>   Quant.Strategy.sma_crossover(fast_period: 12, slow_period: 26),
      ...>   Quant.Strategy.rsi_threshold(oversold: 30, overbought: 70)
      ...> ]
      iex> composite = Quant.Strategy.Composite.create(strategies, logic: :all)
      iex> composite.type
      :composite
      iex> length(composite.strategies)
      2

  """
  @spec create([map()], keyword()) :: map()
  def create(strategies, opts \\ []) when is_list(strategies) do
    logic = Keyword.get(opts, :logic, :all)
    weights = Keyword.get(opts, :weights, equal_weights(length(strategies)))
    threshold = Keyword.get(opts, :threshold, 0.5)
    name = Keyword.get(opts, :name, "composite_strategy")

    %{
      type: :composite,
      strategies: strategies,
      logic: logic,
      weights: weights,
      threshold: threshold,
      name: name,
      description: "Composite Strategy: #{logic} combination of #{length(strategies)} strategies"
    }
  end

  @doc """
  Apply indicators for all sub-strategies in the composite.

  ## Parameters

  - `dataframe` - Input DataFrame
  - `strategy` - Composite strategy configuration
  - `opts` - Additional options

  ## Returns

  DataFrame with all required indicators for sub-strategies applied.

  """
  @spec apply_indicators(DataFrame.t(), map(), keyword()) ::
          {:ok, DataFrame.t()} | {:error, term()}
  def apply_indicators(dataframe, strategy, opts \\ []) do
    strategy.strategies
    |> Enum.reduce({:ok, dataframe}, fn sub_strategy, {:ok, df_acc} ->
      case apply_sub_strategy_indicators(df_acc, sub_strategy, opts) do
        {:ok, updated_df} -> {:ok, updated_df}
        {:error, reason} -> {:error, {:sub_strategy_failed, sub_strategy.type, reason}}
      end
    end)
  rescue
    e -> {:error, {:composite_indicator_application_failed, Exception.message(e)}}
  end

  @doc """
  Generate signals for a composite strategy.

  This function generates signals for each sub-strategy and then
  combines them according to the specified combination logic.

  ## Parameters

  - `dataframe` - DataFrame with all required indicators
  - `strategy` - Composite strategy configuration
  - `opts` - Signal generation options

  ## Returns

  DataFrame with combined signals.

  """
  @spec generate_signals(DataFrame.t(), map(), keyword()) ::
          {:ok, DataFrame.t()} | {:error, term()}
  def generate_signals(dataframe, strategy, opts \\ []) do
    # Generate signals for each sub-strategy
    sub_signals_results =
      strategy.strategies
      |> Enum.map(&Signal.generate(dataframe, &1, opts))

    # Check if all sub-strategies succeeded
    case Enum.find(sub_signals_results, &match?({:error, _}, &1)) do
      {:error, reason} ->
        {:error, {:sub_strategy_signal_failed, reason}}

      nil ->
        # Extract DataFrames and combine signals
        sub_dataframes = Enum.map(sub_signals_results, fn {:ok, df} -> df end)
        combined_df = combine_sub_signals(dataframe, sub_dataframes, strategy)
        {:ok, combined_df}
    end
  rescue
    e -> {:error, {:composite_signal_generation_failed, Exception.message(e)}}
  end

  @doc """
  Combine multiple signal DataFrames using specified logic.

  ## Parameters

  - `signals_list` - List of DataFrames with signals
  - `opts` - Combination options

  ## Options

  - `:logic` - Combination logic
  - `:weights` - Strategy weights
  - `:columns` - Which signal columns to combine

  """
  @spec combine([DataFrame.t()], keyword()) :: DataFrame.t()
  def combine(signals_list, opts \\ []) when is_list(signals_list) do
    logic = Keyword.get(opts, :logic, :all)
    weights = Keyword.get(opts, :weights, equal_weights(length(signals_list)))

    # Extract signal values from each DataFrame
    signal_columns = Enum.map(signals_list, &DataFrame.pull(&1, "signal"))
    strength_columns = Enum.map(signals_list, &DataFrame.pull(&1, "signal_strength"))

    # Combine signals using specified logic
    {combined_signals, combined_strengths, combined_reasons} =
      combine_signal_logic(signal_columns, strength_columns, logic, weights)

    # Use first DataFrame as base and update signal columns
    base_df = List.first(signals_list)

    base_df
    |> DataFrame.put("signal", combined_signals)
    |> DataFrame.put("signal_strength", combined_strengths)
    |> DataFrame.put("signal_reason", combined_reasons)
  end

  # Private helper functions

  defp apply_sub_strategy_indicators(dataframe, sub_strategy, opts) do
    case sub_strategy.type do
      :sma_crossover ->
        MovingAverage.apply_indicators(dataframe, sub_strategy, opts)

      :ema_crossover ->
        MovingAverage.apply_indicators(dataframe, sub_strategy, opts)

      :macd_crossover ->
        Momentum.apply_indicators(dataframe, sub_strategy, opts)

      :rsi_threshold ->
        Momentum.apply_indicators(dataframe, sub_strategy, opts)

      :bollinger_bands ->
        Volatility.apply_indicators(dataframe, sub_strategy, opts)

      _ ->
        {:error, {:unsupported_sub_strategy, sub_strategy.type}}
    end
  end

  defp combine_sub_signals(base_dataframe, sub_dataframes, strategy) do
    signal_columns = Enum.map(sub_dataframes, &DataFrame.pull(&1, "signal"))
    strength_columns = Enum.map(sub_dataframes, &DataFrame.pull(&1, "signal_strength"))

    {combined_signals, combined_strengths, combined_reasons} =
      combine_signal_logic(signal_columns, strength_columns, strategy.logic, strategy.weights)

    base_dataframe
    |> DataFrame.put("signal", combined_signals)
    |> DataFrame.put("signal_strength", combined_strengths)
    |> DataFrame.put("signal_reason", combined_reasons)
  end

  defp combine_signal_logic(signal_columns, strength_columns, logic, weights) do
    # Convert to lists for easier processing
    signal_lists = Enum.map(signal_columns, &Series.to_list/1)
    strength_lists = Enum.map(strength_columns, &Series.to_list/1)

    # Get the number of rows
    row_count = signal_lists |> List.first() |> length()

    # Combine signals row by row
    combined_data =
      0..(row_count - 1)
      |> Enum.map(fn row_index ->
        signals_for_row = Enum.map(signal_lists, &Enum.at(&1, row_index))
        strengths_for_row = Enum.map(strength_lists, &Enum.at(&1, row_index))

        combine_row_signals(signals_for_row, strengths_for_row, logic, weights)
      end)

    # Separate the combined results
    signals = Enum.map(combined_data, &elem(&1, 0))
    strengths = Enum.map(combined_data, &elem(&1, 1))
    reasons = Enum.map(combined_data, &elem(&1, 2))

    {
      Series.from_list(signals),
      Series.from_list(strengths),
      Series.from_list(reasons)
    }
  end

  defp combine_row_signals(signals, strengths, logic, weights) do
    case logic do
      :all -> combine_all_logic(signals, strengths)
      :any -> combine_any_logic(signals, strengths)
      :majority -> combine_majority_logic(signals, strengths)
      :weighted -> combine_weighted_logic(signals, strengths, weights)
    end
  end

  defp combine_all_logic(signals, strengths) do
    # All strategies must agree (same non-zero signal)
    non_zero_signals = Enum.reject(signals, &(&1 == 0))

    cond do
      # All signals are zero (hold)
      Enum.all?(signals, &(&1 == 0)) ->
        {0, 0.0, "all_hold"}

      # All non-zero signals agree
      length(Enum.uniq(non_zero_signals)) == 1 and length(non_zero_signals) == length(signals) ->
        signal = List.first(non_zero_signals)
        avg_strength = Enum.sum(strengths) / length(strengths)
        {signal, avg_strength, "all_agree_#{signal}"}

      # Signals disagree or some are hold
      true ->
        {0, 0.0, "all_disagree"}
    end
  end

  defp combine_any_logic(signals, strengths) do
    # Any strategy can trigger a signal
    non_zero_signals =
      signals
      |> Enum.with_index()
      |> Enum.reject(fn {signal, _} -> signal == 0 end)

    if non_zero_signals != [] do
      # Take the strongest signal
      {signal, index} =
        non_zero_signals
        |> Enum.max_by(fn {_, idx} -> Enum.at(strengths, idx) end)

      strength = Enum.at(strengths, index)
      {signal, strength, "any_triggered_#{signal}"}
    else
      {0, 0.0, "any_hold"}
    end
  end

  defp combine_majority_logic(signals, strengths) do
    # Majority of strategies must agree
    signal_counts =
      signals
      |> Enum.frequencies()

    majority_threshold = div(length(signals), 2) + 1

    # Find signals that meet majority threshold
    majority_signals =
      signal_counts
      |> Enum.filter(fn {_signal, count} -> count >= majority_threshold end)
      |> Enum.map(fn {signal, _count} -> signal end)

    case majority_signals do
      [signal] when signal != 0 ->
        # Calculate average strength for this signal
        relevant_strengths =
          signals
          |> Enum.with_index()
          |> Enum.filter(fn {s, _} -> s == signal end)
          |> Enum.map(fn {_, idx} -> Enum.at(strengths, idx) end)

        avg_strength = Enum.sum(relevant_strengths) / length(relevant_strengths)
        {signal, avg_strength, "majority_#{signal}"}

      _ ->
        {0, 0.0, "majority_hold"}
    end
  end

  defp combine_weighted_logic(signals, strengths, weights) do
    # Weighted combination based on strategy weights and strengths
    weighted_scores =
      signals
      |> Enum.zip(strengths)
      |> Enum.zip(weights)
      |> Enum.map(fn {{signal, strength}, weight} ->
        signal * strength * weight
      end)

    total_score = Enum.sum(weighted_scores)
    total_weight = Enum.sum(weights)

    cond do
      total_score > 0.1 ->
        {1, min(total_score / total_weight, 1.0), "weighted_buy"}

      total_score < -0.1 ->
        {-1, min(abs(total_score) / total_weight, 1.0), "weighted_sell"}

      true ->
        {0, 0.0, "weighted_hold"}
    end
  end

  defp equal_weights(count) when count > 0 do
    weight = 1.0 / count
    List.duplicate(weight, count)
  end

  defp equal_weights(_), do: []
end
