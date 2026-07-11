defmodule Quant.Strategy.OrderTest do
  use ExUnit.Case, async: true

  alias Quant.Strategy.Order

  test "fills market orders with deterministic slippage and fees" do
    assert {:ok, order} =
             Order.new("AAA", :buy, :market, 10, id: "order-1", reason: :signal_entry)

    assert {:ok, filled} = Order.fill(order, 100.0, slippage: 0.01, commission: 0.001)

    assert filled.status == :filled
    assert filled.reason == :signal_entry
    assert filled.fill_price == 101.0
    assert_in_delta filled.fee, 1.01, 1.0e-12
    assert_in_delta filled.slippage_cost, 10.0, 1.0e-12
  end

  test "keeps limit and stop orders pending until their OHLC trigger is reached" do
    assert {:ok, buy_limit} = Order.new("AAA", :buy, :limit, 1, trigger_price: 95.0)
    refute Order.fillable?(buy_limit, %{low: 96.0, high: 101.0, close: 100.0})
    assert Order.fillable?(buy_limit, %{low: 95.0, high: 101.0, close: 100.0})

    assert {:ok, sell_stop} = Order.new("AAA", :sell, :stop, 1, trigger_price: 90.0)
    refute Order.fillable?(sell_stop, %{low: 91.0, high: 100.0, close: 95.0})
    assert Order.fillable?(sell_stop, %{low: 89.0, high: 100.0, close: 95.0})
  end

  test "accumulates partial fills until the requested quantity is complete" do
    assert {:ok, order} = Order.new("AAA", :buy, :limit, 10, trigger_price: 100.0)

    assert {:ok, partial} = Order.fill(order, 100.0, quantity: 4, commission: 0.001)
    assert partial.status == :partially_filled
    assert partial.filled_quantity == 4.0
    assert partial.remaining_quantity == 6
    assert_in_delta partial.fee, 0.4, 1.0e-12

    assert {:ok, filled} = Order.fill(partial, 100.0, quantity: 6, commission: 0.001)
    assert filled.status == :filled
    assert filled.filled_quantity == 10.0
    assert filled.remaining_quantity == 0.0
    assert_in_delta filled.fee, 1.0, 1.0e-12
  end

  test "validates and cancels pending orders" do
    assert {:error, :invalid_trigger_price} = Order.new("AAA", :buy, :limit, 1)
    assert {:ok, order} = Order.new("AAA", :sell, :stop, 1, trigger_price: 90.0)
    assert {:ok, %{status: :cancelled}} = Order.cancel(order)

    assert {:ok, partially_filled} = Order.fill(order, 90.0, quantity: 0.5)
    assert {:ok, %{status: :cancelled}} = Order.cancel(partially_filled)
  end
end
