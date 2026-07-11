defmodule Quant.Explorer.HttpClientConfigTest do
  use ExUnit.Case, async: false

  alias Quant.Explorer.{HttpClient, HttpClientConfig, HttpMock}

  setup do
    original_client = Application.get_env(:quant, :http_client)
    HttpMock.reset()

    on_exit(fn ->
      if is_nil(original_client) do
        Application.delete_env(:quant, :http_client)
      else
        Application.put_env(:quant, :http_client, original_client)
      end
    end)

    :ok
  end

  test "uses the real client by default and the configured client when present" do
    Application.delete_env(:quant, :http_client)
    assert HttpClient == HttpClientConfig.http_client()

    Application.put_env(:quant, :http_client, Quant.Explorer.HttpClient.Mock)
    assert Quant.Explorer.HttpClient.Mock == HttpClientConfig.http_client()
  end

  test "delegates GET, POST and JSON decoding to the configured client" do
    Application.put_env(:quant, :http_client, Quant.Explorer.HttpClient.Mock)
    HttpMock.mock_response("example.test/get", "{\"ok\":true}")
    HttpMock.mock_response("example.test/post", "{\"created\":true}")

    assert {:ok, %{status: 200, body: "{\"ok\":true}"}} =
             HttpClientConfig.get("https://example.test/get")

    assert {:ok, %{status: 200, body: "{\"created\":true}"}} =
             HttpClientConfig.post("https://example.test/post", "{}")

    assert {:ok, %{"ok" => true}} = HttpClientConfig.decode_json("{\"ok\":true}")
  end
end
