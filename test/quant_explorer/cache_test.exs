defmodule Quant.Explorer.CacheTest do
  use ExUnit.Case, async: false

  alias Quant.Explorer.Cache

  setup do
    Cache.clear()
    :ok
  end

  test "stores and retrieves a value" do
    assert :miss = Cache.get(:history)
    assert :ok = Cache.put(:history, {:ok, :data})
    assert {:ok, {:ok, :data}} = Cache.get(:history)
  end
end
