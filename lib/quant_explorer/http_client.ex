defmodule Quant.Explorer.HttpClient do
  @moduledoc """
  HTTP client wrapper with retry logic, timeout handling, and standardized error responses.

  This module provides a consistent interface for making HTTP requests across all providers,
  with built-in retry mechanisms and error handling.
  """

  require Logger

  @type url :: String.t()
  @type headers :: [{String.t(), String.t()}]
  @type params :: keyword() | map()
  @type options :: keyword()

  @type response ::
          {:ok, %{status: integer(), body: binary(), headers: headers()}} | {:error, term()}

  @default_timeout 10_000
  @default_retries 3
  @default_retry_delay 1_000

  @doc """
  Makes a GET request with optional query parameters.

  ## Options

  - `:timeout` - Request timeout in milliseconds (default: #{@default_timeout})
  - `:retries` - Number of retry attempts (default: #{@default_retries})
  - `:retry_delay` - Delay between retries in milliseconds (default: #{@default_retry_delay})
  - `:headers` - Additional HTTP headers
  - `:follow_redirect` - Whether to follow redirects (default: true)
  """
  @spec get(url(), params(), options()) :: response()
  def get(url, params \\ %{}, opts \\ []) do
    request(:get, url, "", headers_from_opts(opts), [params: params] ++ opts)
  end

  @doc """
  Makes a POST request with a request body.

  ## Options

  Same as `get/3`, plus:
  - `:content_type` - Content-Type header (default: "application/json")
  """
  @spec post(url(), binary(), options()) :: response()
  def post(url, body, opts \\ []) do
    headers = headers_from_opts(opts)
    content_type = Keyword.get(opts, :content_type, "application/json")
    headers_with_content_type = [{"Content-Type", content_type} | headers]

    request(:post, url, body, headers_with_content_type, opts)
  end

  @doc """
  Makes a generic HTTP request with retry logic.
  """
  @spec request(atom(), url(), binary(), headers(), options()) :: response()
  def request(method, url, body, headers, opts) do
    timeout = Keyword.get(opts, :timeout, @default_timeout)
    retries = Keyword.get(opts, :retries, @default_retries)
    retry_delay = Keyword.get(opts, :retry_delay, @default_retry_delay)

    do_request_with_retries(method, url, body, headers, opts, retries, retry_delay, timeout)
  end

  # Private functions

  defp do_request_with_retries(
         method,
         url,
         body,
         headers,
         opts,
         retries_left,
         retry_delay,
         timeout
       ) do
    case do_request(method, url, body, headers, opts, timeout) do
      {:ok, response} ->
        {:ok, response}

      {:error, reason} when retries_left > 0 ->
        Logger.warning("HTTP request failed (#{retries_left} retries left): #{inspect(reason)}")
        :timer.sleep(retry_delay)

        do_request_with_retries(
          method,
          url,
          body,
          headers,
          opts,
          retries_left - 1,
          retry_delay * 2,
          timeout
        )

      {:error, reason} ->
        Logger.error("HTTP request failed after all retries: #{inspect(reason)}")
        {:error, {:http_error, reason}}
    end
  end

  defp do_request(method, url, body, headers, opts, timeout) do
    with {:ok, final_url} <- build_request_url(url, opts),
         {:ok, httpc_headers} <- prepare_headers(headers),
         {:ok, http_options} <- build_http_options(timeout, opts),
         {:ok, httpc_method} <- normalize_method(method),
         {:ok, request_result} <-
           execute_request(httpc_method, final_url, httpc_headers, body, http_options),
         {:ok, response} <- process_response(request_result) do
      {:ok, response}
    else
      {:error, reason} -> {:error, reason}
    end
  rescue
    error -> {:error, error}
  end

  defp build_request_url(url, opts) do
    params = Keyword.get(opts, :params, %{})
    {:ok, build_url_with_params(url, params)}
  end

  defp prepare_headers(headers) do
    httpc_headers =
      headers
      |> Enum.filter(fn {k, v} -> k != nil and v != nil end)
      |> Enum.map(fn {k, v} -> {String.to_charlist(k), String.to_charlist(v)} end)

    {:ok, httpc_headers}
  end

  defp build_http_options(timeout, opts) do
    follow_redirect = Keyword.get(opts, :follow_redirect, true)

    http_options = [
      timeout: timeout,
      autoredirect: follow_redirect,
      ssl: ssl_options()
    ]

    {:ok, http_options}
  end

  defp normalize_method(method) do
    httpc_method = if is_atom(method), do: method, else: String.to_existing_atom(method)
    {:ok, httpc_method}
  end

  defp execute_request(method, url, headers, body, http_options) do
    request_result = perform_httpc_request(method, url, headers, body, http_options)
    {:ok, request_result}
  end

  defp perform_httpc_request(:get, url, headers, _body, http_options) do
    :httpc.request(:get, {String.to_charlist(url), headers}, http_options, [])
  end

  defp perform_httpc_request(method, url, headers, body, http_options)
       when method in [:post, :put, :patch, :delete] do
    content_type = get_content_type_from_headers(headers)
    body_binary = if is_binary(body), do: body, else: ""

    :httpc.request(
      method,
      {String.to_charlist(url), headers, content_type, body_binary},
      http_options,
      []
    )
  end

  defp perform_httpc_request(method, _url, _headers, _body, _http_options) do
    {:error, {:unsupported_method, method}}
  end

  defp get_content_type_from_headers(headers) do
    # headers are already in charlist format here
    content_type =
      headers
      |> Enum.find_value(fn {k, v} ->
        if List.to_string(k) == "content-type", do: v, else: nil
      end)

    if content_type, do: content_type, else: ~c"application/octet-stream"
  end

  defp process_response(
         {:ok, {{_version, status_code, _reason_phrase}, response_headers, response_body}}
       ) do
    string_headers = convert_headers_to_strings(response_headers)
    response_body_string = convert_body_to_string(response_body)

    {:ok, %{status: status_code, body: response_body_string, headers: string_headers}}
  end

  defp process_response({:error, reason}) do
    {:error, reason}
  end

  defp convert_headers_to_strings(headers) do
    headers
    |> Enum.map(fn
      {k, v} when is_list(k) and is_list(v) -> {List.to_string(k), List.to_string(v)}
      {k, v} when is_binary(k) and is_binary(v) -> {k, v}
      _ -> nil
    end)
    |> Enum.filter(&(&1 != nil))
  end

  defp convert_body_to_string(body) do
    if is_list(body), do: List.to_string(body), else: body
  end

  defp ssl_options do
    [
      verify: :verify_peer,
      cacertfile: :certifi.cacertfile(),
      depth: 3
    ]
  end

  defp headers_from_opts(opts) do
    Keyword.get(opts, :headers, [])
  end

  defp build_url_with_params(url, params) when params == %{} or params == [], do: url

  defp build_url_with_params(url, params) do
    query_string =
      params
      |> Enum.reject(fn {_key, value} -> is_nil(value) end)
      |> Enum.map_join("&", fn {k, v} ->
        "#{URI.encode_www_form(to_string(k))}=#{URI.encode_www_form(to_string(v))}"
      end)

    case String.contains?(url, "?") do
      true -> "#{url}&#{query_string}"
      false -> "#{url}?#{query_string}"
    end
  end

  @doc """
  Decodes JSON response body.

  Returns `{:ok, decoded_data}` or `{:error, {:parse_error, reason}}`.
  """
  @spec decode_json(binary()) :: {:ok, term()} | {:error, term()}
  def decode_json(body) do
    case JSON.decode(body) do
      {:ok, data} -> {:ok, data}
      {:error, reason} -> {:error, {:parse_error, reason}}
    end
  end

  @doc """
  Checks if HTTP response indicates success (2xx status code).
  """
  @spec success?(integer()) :: boolean()
  def success?(status) when status >= 200 and status < 300, do: true
  def success?(_status), do: false

  @doc """
  Extracts error message from HTTP response based on common API patterns.
  """
  @spec extract_error_message(map()) :: String.t()
  def extract_error_message(%{status: status, body: body}) do
    case decode_json(body) do
      {:ok, %{"error" => error}} when is_binary(error) -> error
      {:ok, %{"message" => message}} when is_binary(message) -> message
      {:ok, %{"error" => %{"message" => message}}} when is_binary(message) -> message
      {:ok, %{"errors" => [%{"message" => message} | _]}} when is_binary(message) -> message
      _ -> "HTTP #{status}: #{body}"
    end
  end
end
