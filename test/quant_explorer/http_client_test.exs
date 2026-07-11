defmodule Quant.Explorer.HttpClientTest do
  use ExUnit.Case, async: false

  alias Quant.Explorer.HttpClient

  test "decodes JSON and exposes parse failures" do
    assert {:ok, %{"price" => 10.5}} = HttpClient.decode_json("{\"price\":10.5}")
    assert {:error, {:parse_error, _reason}} = HttpClient.decode_json("not json")
  end

  test "classifies success status codes" do
    assert HttpClient.success?(200)
    assert HttpClient.success?(299)
    refute HttpClient.success?(300)
    refute HttpClient.success?(429)
  end

  test "extracts common provider error messages" do
    assert "invalid symbol" =
             HttpClient.extract_error_message(%{
               status: 400,
               body: "{\"error\":\"invalid symbol\"}"
             })

    assert "slow down" =
             HttpClient.extract_error_message(%{status: 429, body: "{\"message\":\"slow down\"}"})

    assert "HTTP 500: unavailable" =
             HttpClient.extract_error_message(%{status: 500, body: "unavailable"})

    assert "nested message" =
             HttpClient.extract_error_message(%{
               status: 400,
               body: "{\"error\":{\"message\":\"nested message\"}}"
             })

    assert "first error" =
             HttpClient.extract_error_message(%{
               status: 400,
               body: "{\"errors\":[{\"message\":\"first error\"}]}"
             })
  end

  test "performs GET requests with encoded query parameters and headers" do
    {url, server} = start_server(json_response("{\"ok\":true}"))

    assert {:ok, %{status: 200, body: "{\"ok\":true}", headers: headers}} =
             HttpClient.get(url <> "/prices", %{symbol: "BTC USDT", ignored: nil},
               headers: [{"X-Client", "quant"}, {"X-Ignored", nil}],
               retries: 0
             )

    assert {"x-request-id", "local-1"} in headers

    request = await_request(server)
    assert request =~ "GET /prices?symbol=BTC+USDT HTTP/1.1"
    assert request =~ "x-client: quant"
    refute request =~ "x-ignored"
  end

  test "performs POST requests with the requested content type and body" do
    {url, server} = start_server(json_response("{\"accepted\":true}"))
    body = "{\"side\":\"buy\"}"

    assert {:ok, %{status: 200, body: "{\"accepted\":true}"}} =
             HttpClient.post(url <> "/orders", body, retries: 0, content_type: "application/json")

    request = await_request(server)
    assert request =~ "POST /orders HTTP/1.1"
    assert request =~ "content-type: application/json"
    assert String.ends_with?(request, body)
  end

  test "rejects unsupported methods without opening a network connection" do
    assert {:error, {:http_error, {:unsupported_method, :trace}}} =
             HttpClient.request(:trace, "https://example.test", "", [], retries: 0)
  end

  defp start_server(response) do
    {:ok, listen_socket} =
      :gen_tcp.listen(0, [:binary, active: false, reuseaddr: true, ip: {127, 0, 0, 1}])

    {:ok, {{127, 0, 0, 1}, port}} = :inet.sockname(listen_socket)

    server =
      Task.async(fn ->
        {:ok, socket} = :gen_tcp.accept(listen_socket)
        request = receive_request(socket)
        :ok = :gen_tcp.send(socket, response)
        :ok = :gen_tcp.close(socket)
        :ok = :gen_tcp.close(listen_socket)
        request
      end)

    {"http://127.0.0.1:#{port}", server}
  end

  defp await_request(server), do: Task.await(server, 1_000)

  defp receive_request(socket, request \\ "") do
    {:ok, chunk} = :gen_tcp.recv(socket, 0, 1_000)
    request = request <> chunk

    case :binary.match(request, "\r\n\r\n") do
      :nomatch -> receive_request(socket, request)
      {headers_end, _length} -> receive_body(socket, request, headers_end + 4)
    end
  end

  defp receive_body(socket, request, headers_end) do
    headers = binary_part(request, 0, headers_end)
    content_length = content_length(headers)
    received_body_size = byte_size(request) - headers_end

    if received_body_size >= content_length do
      request
    else
      {:ok, chunk} = :gen_tcp.recv(socket, content_length - received_body_size, 1_000)
      request <> chunk
    end
  end

  defp content_length(headers) do
    case Regex.run(~r/\r\ncontent-length:\s*(\d+)/i, headers) do
      [_, value] -> String.to_integer(value)
      nil -> 0
    end
  end

  defp json_response(body) do
    "HTTP/1.1 200 OK\r\ncontent-type: application/json\r\nx-request-id: local-1\r\n" <>
      "content-length: #{byte_size(body)}\r\nconnection: close\r\n\r\n#{body}"
  end
end
