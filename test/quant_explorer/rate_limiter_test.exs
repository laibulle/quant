defmodule Quant.Explorer.RateLimiterTest do
  use ExUnit.Case, async: false

  alias Quant.Explorer.{RateLimiter, TestHelper}

  setup do
    :ok = TestHelper.setup_rate_limiter()

    on_exit(fn ->
      :ok = TestHelper.setup_rate_limiter()
    end)

    :ok
  end

  test "checks without consuming, consumes asynchronously and resets a limit" do
    assert :ok = RateLimiter.check_limit(:alpha_vantage, :quote)

    assert %{remaining: 5, retry_after_ms: 0} =
             RateLimiter.get_limit_status(:alpha_vantage, :quote)

    RateLimiter.consume_limit(:alpha_vantage, :quote)

    assert %{remaining: 4, retry_after_ms: 0} =
             RateLimiter.get_limit_status(:alpha_vantage, :quote)

    RateLimiter.reset_limits(:alpha_vantage, :quote)

    assert %{remaining: 5, retry_after_ms: 0} =
             RateLimiter.get_limit_status(:alpha_vantage, :quote)
  end

  test "enforces provider quotas and reports a retry delay" do
    Enum.each(1..5, fn _ ->
      assert :ok = RateLimiter.check_and_consume(:alpha_vantage, :quote)
    end)

    assert {:error, :rate_limited} = RateLimiter.check_and_consume(:alpha_vantage, :quote)

    assert %{remaining: 0, retry_after_ms: retry_after_ms, reset_time: %DateTime{}} =
             RateLimiter.get_limit_status(:alpha_vantage, :quote)

    assert retry_after_ms > 0

    assert %{allowed: allowed, denied: denied, last_request: %DateTime{}} =
             RateLimiter.get_stats(:alpha_vantage)

    assert allowed >= 5
    assert denied >= 1
  end

  test "uses Binance endpoint weights when consuming a limit" do
    assert :ok = RateLimiter.check_and_consume(:binance, :depth, params: [limit: 1_001])

    assert %{remaining: 1_150, retry_after_ms: 0} =
             RateLimiter.get_limit_status(:binance, :depth)
  end

  test "waits without delay when a request is immediately available" do
    assert :ok =
             RateLimiter.wait_for_rate_limit(:twelve_data, :default,
               initial_delay_ms: 1,
               max_wait_ms: 5
             )

    assert %{remaining: 7} = RateLimiter.get_limit_status(:twelve_data, :default)
  end
end
