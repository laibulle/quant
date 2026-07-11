defmodule Quant.Strategy.Performance do
  @moduledoc """
  Performance analysis for backtest results.

  Metrics are calculated from the `portfolio_value` series emitted by
  `Quant.Strategy.Backtest`. Returns are period returns; set `:periods_per_year`
  to match the bar frequency of the data (252 for daily bars by default).
  """

  alias Explorer.{DataFrame, Series}

  @type metrics :: %{
          total_return: float(),
          annualized_return: float(),
          volatility: float(),
          sharpe_ratio: float() | nil,
          sortino_ratio: float() | nil,
          maximum_drawdown: float(),
          win_rate: float(),
          profit_factor: float() | nil,
          trade_count: non_neg_integer()
        }

  @doc """
  Calculates return, risk and trade metrics from a backtest DataFrame.

  `:periods_per_year` defaults to 252 and `:risk_free_rate` defaults to 0.0.
  Returns `{:error, :portfolio_value_required}` when the input is not a
  backtest result.
  """
  @spec analyze(DataFrame.t(), keyword()) :: {:ok, metrics()} | {:error, term()}
  def analyze(backtest_results, opts \\ []) do
    if "portfolio_value" in DataFrame.names(backtest_results) do
      portfolio_values = backtest_results |> DataFrame.pull("portfolio_value") |> Series.to_list()
      periods_per_year = Keyword.get(opts, :periods_per_year, 252)
      risk_free_rate = Keyword.get(opts, :risk_free_rate, 0.0)
      trade_returns = trade_returns(backtest_results)

      with :ok <- validate_portfolio_values(portfolio_values),
           :ok <- validate_positive_number(periods_per_year, :periods_per_year),
           :ok <- validate_non_negative_number(risk_free_rate, :risk_free_rate) do
        returns = period_returns(portfolio_values)

        {:ok,
         %{
           total_return: total_return(portfolio_values),
           annualized_return: annualized_return(portfolio_values, periods_per_year),
           volatility: annualized_volatility(returns, periods_per_year),
           sharpe_ratio: sharpe_ratio(returns, risk_free_rate, periods_per_year),
           sortino_ratio: sortino_ratio(returns, risk_free_rate, periods_per_year),
           maximum_drawdown: maximum_drawdown(portfolio_values),
           win_rate: win_rate(trade_returns),
           profit_factor: profit_factor(trade_returns),
           trade_count: length(trade_returns)
         }}
      end
    else
      {:error, :portfolio_value_required}
    end
  end

  defp trade_returns(dataframe) do
    if "trade_return" in DataFrame.names(dataframe) do
      dataframe
      |> DataFrame.pull("trade_return")
      |> Series.to_list()
      |> Enum.filter(&is_number/1)
      |> Enum.reject(&(&1 == 0.0))
    else
      []
    end
  end

  defp validate_portfolio_values(values) when length(values) >= 2 and is_number(hd(values)),
    do: :ok

  defp validate_portfolio_values(_values), do: {:error, :insufficient_portfolio_values}

  defp validate_positive_number(value, _name) when is_number(value) and value > 0, do: :ok
  defp validate_positive_number(_value, name), do: {:error, {:invalid_option, name}}

  defp validate_non_negative_number(value, _name) when is_number(value) and value >= 0, do: :ok
  defp validate_non_negative_number(_value, name), do: {:error, {:invalid_option, name}}

  defp period_returns(values) do
    values
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.map(fn [previous, current] -> (current - previous) / previous end)
  end

  defp total_return(values), do: (List.last(values) - hd(values)) / hd(values)

  defp annualized_return(values, periods_per_year) do
    periods = length(values) - 1
    :math.pow(List.last(values) / hd(values), periods_per_year / periods) - 1
  end

  defp annualized_volatility([], _periods_per_year), do: 0.0

  defp annualized_volatility(returns, periods_per_year),
    do: standard_deviation(returns) * :math.sqrt(periods_per_year)

  defp sharpe_ratio([], _risk_free_rate, _periods_per_year), do: nil

  defp sharpe_ratio(returns, risk_free_rate, periods_per_year) do
    deviation = standard_deviation(returns)

    if deviation == 0.0 do
      nil
    else
      (mean(returns) - risk_free_rate / periods_per_year) / deviation *
        :math.sqrt(periods_per_year)
    end
  end

  defp sortino_ratio(returns, risk_free_rate, periods_per_year) do
    downside = Enum.filter(returns, &(&1 < 0))

    case downside do
      [] ->
        nil

      _ ->
        deviation = standard_deviation(downside)

        if deviation == 0.0 do
          nil
        else
          (mean(returns) - risk_free_rate / periods_per_year) / deviation *
            :math.sqrt(periods_per_year)
        end
    end
  end

  defp maximum_drawdown(values) do
    {_peak, drawdown} =
      Enum.reduce(values, {hd(values), 0.0}, fn value, {peak, max_drawdown} ->
        peak = max(peak, value)
        {peak, max(max_drawdown, (peak - value) / peak)}
      end)

    drawdown
  end

  defp win_rate([]), do: 0.0
  defp win_rate(returns), do: Enum.count(returns, &(&1 > 0)) / length(returns)

  defp profit_factor(returns) do
    gross_profit = returns |> Enum.filter(&(&1 > 0)) |> Enum.sum()
    gross_loss = returns |> Enum.filter(&(&1 < 0)) |> Enum.sum() |> abs()
    if gross_loss == 0.0, do: nil, else: gross_profit / gross_loss
  end

  defp mean(values), do: Enum.sum(values) / length(values)

  defp standard_deviation(values) do
    average = mean(values)
    :math.sqrt(Enum.sum(Enum.map(values, &:math.pow(&1 - average, 2))) / length(values))
  end
end
