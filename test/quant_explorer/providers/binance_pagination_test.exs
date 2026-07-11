defmodule Quant.Explorer.Providers.BinancePaginationTest do
  use ExUnit.Case, async: false

  alias Explorer.{DataFrame, Series}
  alias Quant.Explorer.{HttpMock, RateLimiter}
  alias Quant.Explorer.Providers.Binance

  setup do
    HttpMock.reset()
    RateLimiter.reset_limits(:binance)
    :ok
  end

  test "splits a range larger than 1,000 klines into ordered pages" do
    start_ms = 1_700_000_000_000
    interval_ms = :timer.minutes(1)
    end_ms = start_ms + interval_ms * 2_000

    HttpMock.mock_response("api.binance.com/api/v3/klines", fn url ->
      start_time =
        url
        |> URI.parse()
        |> Map.fetch!(:query)
        |> URI.decode_query()
        |> Map.fetch!("startTime")
        |> String.to_integer()

      JSON.encode!([kline(start_time)])
    end)

    assert {:ok, dataframe} =
             Binance.history("BTCUSDT",
               interval: "1m",
               start_time: start_ms,
               end_time: end_ms
             )

    assert DataFrame.n_rows(dataframe) == 3

    assert dataframe
           |> DataFrame.pull("timestamp")
           |> Series.to_list()
           |> Enum.map(&DateTime.to_unix(&1, :millisecond)) ==
             [start_ms, start_ms + interval_ms * 1_000, end_ms]

    assert HttpMock.get_requests() |> Enum.count(&String.contains?(&1, "/klines?")) == 3
  end

  test "does not return partial data when a later page fails" do
    start_ms = 1_700_000_000_000
    end_ms = start_ms + :timer.minutes(1_000)

    HttpMock.mock_response("api.binance.com/api/v3/klines", fn url ->
      start_time =
        url
        |> URI.parse()
        |> Map.fetch!(:query)
        |> URI.decode_query()
        |> Map.fetch!("startTime")
        |> String.to_integer()

      if start_time == start_ms do
        JSON.encode!([kline(start_time)])
      else
        %{status: 500, body: "upstream unavailable"}
      end
    end)

    assert {:error, {:page_failed, ^end_ms, {:http_error, 500}}} =
             Binance.history("BTCUSDT", interval: "1m", start_time: start_ms, end_time: end_ms)
  end

  defp kline(open_time) do
    [
      open_time,
      "10.0",
      "11.0",
      "9.0",
      "10.5",
      "100.0",
      open_time + :timer.minutes(1) - 1,
      "1_000.0",
      10,
      "50.0",
      "500.0",
      "0"
    ]
  end
end
