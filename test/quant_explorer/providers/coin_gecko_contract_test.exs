defmodule Quant.Explorer.Providers.CoinGeckoContractTest do
  use ExUnit.Case, async: false

  import Quant.Explorer.TestHelper

  alias Explorer.DataFrame
  alias Quant.Explorer.{HttpMock, TestHelper}
  alias Quant.Explorer.Providers.CoinGecko

  setup do
    :ok = TestHelper.setup_rate_limiter()
    HttpMock.reset()
    :ok
  end

  test "preserves the last price update supplied by the simple price endpoint" do
    response =
      """
      {"bitcoin":{"usd":42000.5,"usd_24h_change":1.25,"usd_24h_vol":1000.0,"usd_market_cap":800000.0,"last_updated_at":1704067200}}
      """

    with_http_mock([{"api.coingecko.com", response}]) do
      assert {:ok, dataframe} = CoinGecko.quote("bitcoin")

      [row] = DataFrame.to_rows(dataframe)
      assert row["price"] == 42_000.5
      assert DateTime.compare(row["timestamp"], ~U[2024-01-01 00:00:00Z]) == :eq
    end
  end

  test "uses the market timestamp rather than the local clock for top coins" do
    response =
      """
      [{"id":"bitcoin","name":"Bitcoin","current_price":42000.0,"price_change_24h":100.0,"price_change_percentage_24h":0.25,"total_volume":1234.0,"market_cap":800000.0,"market_cap_rank":1,"last_updated":"2024-01-01T12:30:00.000Z"}]
      """

    with_http_mock([{"api.coingecko.com", response}]) do
      assert {:ok, dataframe} = CoinGecko.top_coins()

      [row] = DataFrame.to_rows(dataframe)
      assert row["symbol"] == "bitcoin"
      assert DateTime.compare(row["timestamp"], ~U[2024-01-01 12:30:00Z]) == :eq
    end
  end

  test "accepts incomplete coin information and null market totals" do
    with_http_mock([
      {"api.coingecko.com", "{\"id\":\"unknown\",\"symbol\":\"unk\",\"name\":\"Unknown\"}"}
    ]) do
      assert {:ok, info} = CoinGecko.info("unknown")
      assert info["homepage"] == nil
      assert info["blockchain_site"] == nil
    end

    null_market_response =
      """
      [{"id":"unknown","name":"Unknown","total_volume":null,"market_cap":null,"last_updated":"not-a-date"}]
      """

    with_http_mock([{"api.coingecko.com", null_market_response}]) do
      assert {:ok, dataframe} = CoinGecko.top_coins()

      [row] = DataFrame.to_rows(dataframe)
      assert row["volume"] == nil
      assert row["market_cap"] == nil
      assert row["timestamp"] == nil
    end
  end
end
