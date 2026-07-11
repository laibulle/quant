defmodule Quant.Math.Utils do
  @moduledoc """
  Shared utility functions for mathematical operations in the Quant.Math module.

  This module provides common utilities used across different technical indicator
  implementations, including DataFrame/NX bridge functions, validation, and
  core mathematical operations.
  """

  alias Explorer.DataFrame
  alias Explorer.Series

  @doc """
  Convert an Explorer Series to an NX Tensor.

  ## Parameters
  - `series` - The Explorer Series to convert

  ## Returns
  - `Nx.Tensor.t()` - The converted tensor with :f64 type
  """
  @spec to_tensor(Series.t()) :: Nx.Tensor.t()
  def to_tensor(series) do
    series
    |> Series.to_list()
    |> Nx.tensor(type: :f64)
  end

  @doc """
  Convert an NX Tensor back to an Explorer Series.

  ## Parameters
  - `tensor` - The NX Tensor to convert
  - `name` - The name for the series (currently unused but kept for API consistency)

  ## Returns
  - `Series.t()` - The converted series with :f64 dtype
  """
  @spec to_series(Nx.Tensor.t(), String.t()) :: Series.t()
  def to_series(tensor, _name) do
    list = Nx.to_list(tensor)

    # Handle empty tensor
    if Enum.empty?(list) do
      Series.from_list([], dtype: :f64)
    else
      Series.from_list(list, dtype: :f64)
    end
  end

  @doc """
  Calculate rolling mean over a tensor using a sliding window.

  ## Parameters
  - `tensor` - The input NX Tensor
  - `window_size` - The size of the rolling window

  ## Returns
  - `Nx.Tensor.t()` - Tensor with rolling means, NaN for insufficient data
  """
  @spec rolling_mean(Nx.Tensor.t(), pos_integer()) :: Nx.Tensor.t()
  def rolling_mean(tensor, window_size) do
    # Get the shape of the input tensor
    {n} = Nx.shape(tensor)

    # Handle edge cases early
    cond do
      window_size > n ->
        # Return all NaN if window is larger than data
        Nx.broadcast(:nan, {n})

      n < window_size ->
        # Not enough data points
        Nx.broadcast(:nan, {n})

      true ->
        # Calculate rolling mean with sufficient data
        calculate_rolling_windows(tensor, window_size, n)
    end
  end

  @doc """
  Validate that a column exists in the DataFrame.

  ## Parameters
  - `df` - The DataFrame to check
  - `column` - The column name (atom) to validate

  ## Returns
  - `:ok` if column exists
  - `{:error, message}` if column is missing
  """
  @spec validate_column(DataFrame.t(), atom()) :: :ok | {:error, String.t()}
  def validate_column(df, column) do
    column_names = Map.keys(df.dtypes)
    column_string = Atom.to_string(column)

    if column_string in column_names do
      :ok
    else
      {:error, "Column #{inspect(column)} not found in DataFrame"}
    end
  end

  @doc """
  Validate that a DataFrame is valid and raise if not.

  ## Parameters
  - `df` - The DataFrame to validate

  ## Returns
  - `:ok` if valid DataFrame

  ## Raises
  - `ArgumentError` if not a valid DataFrame
  """
  @spec validate_dataframe!(any()) :: :ok
  def validate_dataframe!(df) do
    if is_struct(df, DataFrame) do
      :ok
    else
      type_description =
        if is_struct(df) do
          inspect(df.__struct__)
        else
          inspect(typeof(df))
        end

      raise ArgumentError, "Expected Explorer DataFrame, got #{type_description}"
    end
  end

  defp typeof(value) when is_boolean(value), do: :boolean
  defp typeof(value) when is_atom(value), do: :atom
  defp typeof(value) when is_binary(value), do: :binary
  defp typeof(value) when is_bitstring(value), do: :bitstring
  defp typeof(value) when is_float(value), do: :float
  defp typeof(value) when is_function(value), do: :function
  defp typeof(value) when is_integer(value), do: :integer
  defp typeof(value) when is_list(value), do: :list
  defp typeof(value) when is_map(value), do: :map
  defp typeof(value) when is_pid(value), do: :pid
  defp typeof(value) when is_port(value), do: :port
  defp typeof(value) when is_reference(value), do: :reference
  defp typeof(value) when is_tuple(value), do: :tuple

  @doc """
  Validate that a column exists in the DataFrame and raise if not.

  ## Parameters
  - `df` - The DataFrame to check
  - `column` - The column name (atom) to validate

  ## Returns
  - `:ok` if column exists

  ## Raises
  - `ArgumentError` if column does not exist
  """
  @spec validate_column!(DataFrame.t(), atom()) :: :ok
  def validate_column!(df, column) do
    case validate_column(df, column) do
      :ok -> :ok
      {:error, message} -> raise ArgumentError, "Column validation failed: #{message}"
    end
  end

  @doc """
  Validate that a period is a positive integer and raise if not.

  ## Parameters
  - `period` - The period to validate
  - `name` - Optional name for better error messages (default: "period")

  ## Returns
  - `:ok` if valid period

  ## Raises
  - `ArgumentError` if period is not a positive integer
  """
  @spec validate_period!(any(), String.t()) :: :ok
  def validate_period!(period, name \\ "period") do
    if is_integer(period) and period > 0 do
      :ok
    else
      raise ArgumentError, "#{name} must be a positive integer, got #{inspect(period)}"
    end
  end

  @doc """
  Calculate exponential moving average over a tensor.

  ## Parameters
  - `tensor` - The input NX Tensor
  - `period` - The period for the EMA calculation
  - `alpha` - Optional alpha (smoothing factor). If not provided, uses 2/(period+1)

  ## Returns
  - `Nx.Tensor.t()` - Tensor with EMA values, first value is SMA of first `period` values

  ## Algorithm
  - First EMA value = SMA of first `period` values
  - Subsequent EMA values = alpha * current_price + (1 - alpha) * previous_ema
  - Default alpha = 2 / (period + 1)
  """
  @spec exponential_mean(Nx.Tensor.t(), pos_integer(), float() | nil) :: Nx.Tensor.t()
  def exponential_mean(tensor, period, alpha \\ nil) do
    # Get the shape of the input tensor
    {n} = Nx.shape(tensor)

    # Handle edge cases early
    cond do
      period > n ->
        # Return all NaN if period is larger than data
        Nx.broadcast(:nan, {n})

      n < period ->
        # Not enough data points
        Nx.broadcast(:nan, {n})

      true ->
        # Calculate EMA with sufficient data
        alpha_value = alpha || 2.0 / (period + 1)
        calculate_ema_values(tensor, period, alpha_value, n)
    end
  end

  @doc """
  Calculate weighted moving average over a tensor using a sliding window.

  ## Parameters
  - `tensor` - The input NX Tensor
  - `period` - The period for the WMA calculation
  - `weights` - Optional weight vector. If not provided, uses linear weights [1, 2, 3, ..., period]

  ## Returns
  - `Nx.Tensor.t()` - Tensor with WMA values, NaN for insufficient data

  ## Algorithm
  - Default weights: Linear sequence [1, 2, 3, ..., period]
  - WMA = Σ(price_i × weight_i) / Σ(weight_i)
  - Gives more weight to recent prices in the linear case
  """
  @spec weighted_mean(Nx.Tensor.t(), pos_integer(), Nx.Tensor.t() | nil) :: Nx.Tensor.t()
  def weighted_mean(tensor, period, weights \\ nil) do
    # Get the shape of the input tensor
    {n} = Nx.shape(tensor)

    # Handle edge cases early
    cond do
      n == 0 ->
        # Empty tensor - return empty tensor
        tensor

      period > n or n < period ->
        # Return all NaN if period is larger than data or not enough data points
        Nx.broadcast(:nan, {n})

      true ->
        # Create or validate weights
        weight_vector = create_or_validate_weights(weights, period)

        # Calculate WMA with sufficient data
        calculate_weighted_windows(tensor, period, weight_vector, n)
    end
  end

  # Private helper functions

  @doc false
  @spec create_or_validate_weights(Nx.Tensor.t() | nil, pos_integer()) :: Nx.Tensor.t()
  defp create_or_validate_weights(nil, period) do
    # Create linear weights [1, 2, 3, ..., period]
    1..period
    |> Enum.to_list()
    |> Nx.tensor(type: :f64)
  end

  defp create_or_validate_weights(weights, period) do
    # Validate weight vector if provided
    {weight_size} = Nx.shape(weights)

    if weight_size != period do
      raise ArgumentError, "Weight vector size #{weight_size} does not match period #{period}"
    end

    weights
  end

  @doc false
  @spec calculate_weighted_windows(Nx.Tensor.t(), pos_integer(), Nx.Tensor.t(), pos_integer()) ::
          Nx.Tensor.t()
  defp calculate_weighted_windows(tensor, period, weights, n) do
    # Create output tensor initialized with NaN
    output = Nx.broadcast(:nan, {n})
    range = Range.new(period - 1, n - 1, 1)

    # Calculate sum of weights once (for efficiency)
    weight_sum = Nx.sum(weights)

    Enum.reduce(range, output, fn i, acc ->
      # Extract window slice
      start_idx = i - period + 1
      window = Nx.slice_along_axis(tensor, start_idx, period, axis: 0)

      # Calculate weighted sum: Σ(price_i × weight_i)
      weighted_sum = Nx.sum(Nx.multiply(window, weights))

      # Calculate WMA: weighted_sum / weight_sum
      wma_val = Nx.divide(weighted_sum, weight_sum)

      # Put new WMA value in output
      Nx.put_slice(acc, [i], Nx.reshape(wma_val, {1}))
    end)
  end

  @doc false
  @spec calculate_ema_values(Nx.Tensor.t(), pos_integer(), float(), pos_integer()) ::
          Nx.Tensor.t()
  defp calculate_ema_values(tensor, period, alpha, n) do
    # Create output tensor initialized with NaN
    output = Nx.broadcast(:nan, {n})

    # Calculate initial SMA for the first EMA value
    first_window = Nx.slice_along_axis(tensor, 0, period, axis: 0)
    first_ema = Nx.mean(first_window)

    # Set the first EMA value (at index period-1)
    output = Nx.put_slice(output, [period - 1], Nx.reshape(first_ema, {1}))

    # Calculate subsequent EMA values
    if period < n do
      Enum.reduce(period..(n - 1), output, fn i, acc ->
        # Get current price
        current_price = Nx.slice_along_axis(tensor, i, 1, axis: 0) |> Nx.squeeze()

        # Get previous EMA
        prev_ema = Nx.slice_along_axis(acc, i - 1, 1, axis: 0) |> Nx.squeeze()

        # Calculate new EMA: alpha * current + (1 - alpha) * prev_ema
        new_ema =
          Nx.add(
            Nx.multiply(alpha, current_price),
            Nx.multiply(1.0 - alpha, prev_ema)
          )

        # Put new EMA value in output
        Nx.put_slice(acc, [i], Nx.reshape(new_ema, {1}))
      end)
    else
      output
    end
  end

  @doc false
  @spec calculate_rolling_windows(Nx.Tensor.t(), pos_integer(), pos_integer()) :: Nx.Tensor.t()
  defp calculate_rolling_windows(tensor, window_size, n) do
    # Create output tensor initialized with NaN
    output = Nx.broadcast(:nan, {n})
    range = Range.new(window_size - 1, n - 1, 1)

    Enum.reduce(range, output, fn i, acc ->
      # Extract window slice
      start_idx = i - window_size + 1
      window = Nx.slice_along_axis(tensor, start_idx, window_size, axis: 0)

      # Calculate mean and put it in the output
      mean_val = Nx.mean(window)
      Nx.put_slice(acc, [i], Nx.reshape(mean_val, {1}))
    end)
  end
end
