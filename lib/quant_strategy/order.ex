defmodule Quant.Strategy.Order do
  @moduledoc """
  Deterministic order lifecycle primitives for the backtesting engine.

  Market orders fill at the supplied reference price. Limit and stop orders
  remain pending until the bar OHLC range reaches their trigger price.
  """

  @type side :: :buy | :sell
  @type order_type :: :market | :limit | :stop
  @type status :: :pending | :partially_filled | :filled | :cancelled
  @type intent :: :entry | :exit | nil
  @type t :: %{
          id: term(),
          symbol: String.t(),
          side: side(),
          type: order_type(),
          quantity: pos_number(),
          filled_quantity: number(),
          remaining_quantity: number(),
          trigger_price: number() | nil,
          reason: atom() | nil,
          intent: intent(),
          status: status(),
          fill_price: number() | nil,
          fee: number() | nil,
          slippage_cost: number() | nil,
          last_fill_quantity: number() | nil,
          last_fill_fee: number() | nil,
          last_slippage_cost: number() | nil
        }

  @type pos_number :: number()

  @spec new(String.t(), side(), order_type(), pos_number(), keyword()) ::
          {:ok, t()} | {:error, term()}
  def new(symbol, side, type, quantity, opts \\ []) do
    trigger_price = Keyword.get(opts, :trigger_price)
    reason = Keyword.get(opts, :reason)
    intent = Keyword.get(opts, :intent)
    id = Keyword.get(opts, :id, System.unique_integer([:positive, :monotonic]))

    with :ok <- validate_side(side),
         :ok <- validate_type(type),
         :ok <- validate_quantity(quantity),
         :ok <- validate_trigger(type, trigger_price) do
      {:ok,
       %{
         id: id,
         symbol: symbol,
         side: side,
         type: type,
         quantity: quantity,
         filled_quantity: 0.0,
         remaining_quantity: quantity,
         trigger_price: trigger_price,
         reason: reason,
         intent: intent,
         status: :pending,
         fill_price: nil,
         fee: nil,
         slippage_cost: nil,
         last_fill_quantity: nil,
         last_fill_fee: nil,
         last_slippage_cost: nil
       }}
    end
  end

  @spec fillable?(t(), map()) :: boolean()
  def fillable?(%{status: status, type: :market}, %{close: close})
      when status in [:pending, :partially_filled] and is_number(close),
      do: true

  def fillable?(%{status: status, type: :limit, side: :buy, trigger_price: price}, %{low: low})
      when status in [:pending, :partially_filled] and is_number(low),
      do: low <= price

  def fillable?(%{status: status, type: :limit, side: :sell, trigger_price: price}, %{high: high})
      when status in [:pending, :partially_filled] and is_number(high),
      do: high >= price

  def fillable?(%{status: status, type: :stop, side: :buy, trigger_price: price}, %{high: high})
      when status in [:pending, :partially_filled] and is_number(high),
      do: high >= price

  def fillable?(%{status: status, type: :stop, side: :sell, trigger_price: price}, %{low: low})
      when status in [:pending, :partially_filled] and is_number(low),
      do: low <= price

  def fillable?(_order, _bar), do: false

  @spec fill(t(), number(), keyword()) :: {:ok, t()} | {:error, term()}
  def fill(
        %{status: status, side: side, remaining_quantity: remaining_quantity} = order,
        reference_price,
        opts
      )
      when status in [:pending, :partially_filled] and is_number(reference_price) and
             reference_price > 0 do
    slippage = Keyword.get(opts, :slippage, 0.0)
    commission = Keyword.get(opts, :commission, 0.0)
    quantity = Keyword.get(opts, :quantity, remaining_quantity)

    with :ok <- validate_fill_quantity(quantity, remaining_quantity) do
      fill_price = apply_slippage(reference_price, side, slippage)
      notional = quantity * fill_price
      fill_fee = notional * commission
      fill_slippage_cost = abs(fill_price - reference_price) * quantity
      remaining_quantity = max(remaining_quantity - quantity, 0.0)
      status = if remaining_quantity == 0.0, do: :filled, else: :partially_filled

      {:ok,
       %{
         order
         | status: status,
           filled_quantity: order.filled_quantity + quantity,
           remaining_quantity: remaining_quantity,
           fill_price: fill_price,
           fee: (order.fee || 0.0) + fill_fee,
           slippage_cost: (order.slippage_cost || 0.0) + fill_slippage_cost,
           last_fill_quantity: quantity,
           last_fill_fee: fill_fee,
           last_slippage_cost: fill_slippage_cost
       }}
    end
  end

  def fill(%{status: status}, _reference_price, _opts), do: {:error, {:order_not_pending, status}}
  def fill(_order, _reference_price, _opts), do: {:error, :invalid_fill_price}

  @spec cancel(t()) :: {:ok, t()} | {:error, term()}
  def cancel(%{status: status} = order) when status in [:pending, :partially_filled],
    do: {:ok, %{order | status: :cancelled}}

  def cancel(%{status: status}), do: {:error, {:order_not_pending, status}}

  defp apply_slippage(price, :buy, slippage), do: price * (1 + slippage)
  defp apply_slippage(price, :sell, slippage), do: price * (1 - slippage)

  defp validate_fill_quantity(quantity, remaining_quantity)
       when is_number(quantity) and quantity > 0 and quantity <= remaining_quantity,
       do: :ok

  defp validate_fill_quantity(_quantity, _remaining_quantity),
    do: {:error, :invalid_fill_quantity}

  defp validate_side(side) when side in [:buy, :sell], do: :ok
  defp validate_side(_side), do: {:error, :invalid_order_side}
  defp validate_type(type) when type in [:market, :limit, :stop], do: :ok
  defp validate_type(_type), do: {:error, :invalid_order_type}
  defp validate_quantity(quantity) when is_number(quantity) and quantity > 0, do: :ok
  defp validate_quantity(_quantity), do: {:error, :invalid_order_quantity}
  defp validate_trigger(:market, _trigger_price), do: :ok
  defp validate_trigger(_type, price) when is_number(price) and price > 0, do: :ok
  defp validate_trigger(_type, _trigger_price), do: {:error, :invalid_trigger_price}
end
