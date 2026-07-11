defmodule Quant.Explorer.RateLimiting.BehaviourTest do
  use ExUnit.Case, async: true

  alias Quant.Explorer.RateLimiting.Behaviour

  test "builds request information with safe defaults and caller metadata" do
    assert %{provider: :binance, endpoint: :klines, weight: 1, user_id: nil, ip_address: nil} =
             Behaviour.request_info(:binance, :klines)

    assert %{
             provider: :binance,
             endpoint: :depth,
             weight: 5,
             user_id: "trader-1",
             ip_address: "127.0.0.1"
           } =
             Behaviour.request_info(:binance, :depth,
               weight: 5,
               user_id: "trader-1",
               ip_address: "127.0.0.1"
             )
  end

  test "builds each supported rate-limit algorithm configuration" do
    assert %{type: :requests_per_minute, limit: 10, weight: 1, window_ms: 60_000} =
             Behaviour.limit_config(:requests_per_minute, 10)

    assert %{type: :requests_per_second, window_ms: 1_000} =
             Behaviour.limit_config(:requests_per_second, 10)

    assert %{type: :requests_per_hour, window_ms: 3_600_000} =
             Behaviour.limit_config(:requests_per_hour, 10)

    assert %{type: :requests_per_day, window_ms: 86_400_000} =
             Behaviour.limit_config(:requests_per_day, 10)

    assert %{type: :weighted_requests, limit: 20, weight: 4, window_ms: 500} =
             Behaviour.limit_config(:weighted_requests, 20, weight: 4, window_ms: 500)

    assert %{
             type: :burst_allowance,
             limit: 20,
             weight: 2,
             window_ms: 500,
             burst_size: 50,
             recovery_rate: 3
           } =
             Behaviour.limit_config(:burst_allowance, 20,
               weight: 2,
               window_ms: 500,
               burst_size: 50,
               recovery_rate: 3
             )
  end
end
