defmodule Quant.Explorer.HttpMock do
  @moduledoc """
  HTTP mocking system for tests. Provides a way to mock HTTP responses
  without making real requests to external APIs.
  """

  use GenServer

  # Client API
  def start_link(_opts \\ []) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  def mock_response(url_pattern, response) do
    GenServer.call(__MODULE__, {:mock, url_pattern, response})
  end

  def get_mocked_response(url) do
    GenServer.call(__MODULE__, {:get_mock, url})
  end

  def clear_mocks do
    GenServer.call(__MODULE__, :clear)
  end

  def get_requests do
    GenServer.call(__MODULE__, :get_requests)
  end

  def reset do
    GenServer.call(__MODULE__, :reset)
  end

  # Server callbacks
  def init(state) do
    {:ok, Map.merge(state, %{mocks: %{}, requests: []})}
  end

  def handle_call({:mock, url_pattern, response}, _from, state) do
    new_mocks = Map.put(state.mocks, url_pattern, response)
    {:reply, :ok, %{state | mocks: new_mocks}}
  end

  def handle_call({:get_mock, url}, _from, state) do
    # Record the request
    new_requests = [url | state.requests]
    new_state = %{state | requests: new_requests}

    # Find matching mock
    mock_response = find_matching_mock(url, state.mocks)
    {:reply, mock_response, new_state}
  end

  def handle_call(:clear, _from, state) do
    {:reply, :ok, %{state | mocks: %{}}}
  end

  def handle_call(:get_requests, _from, state) do
    {:reply, Enum.reverse(state.requests), state}
  end

  def handle_call(:reset, _from, state) do
    {:reply, :ok, %{state | mocks: %{}, requests: []}}
  end

  # Helper functions
  defp find_matching_mock(url, mocks) do
    Enum.find_value(mocks, fn {pattern, response} ->
      if url_matches?(url, pattern) do
        resolve_response(response, url)
      else
        nil
      end
    end)
  end

  defp resolve_response(response, url) when is_function(response, 1), do: response.(url)
  defp resolve_response(response, _url), do: response

  defp url_matches?(url, pattern) when is_binary(pattern) do
    String.contains?(url, pattern)
  end

  defp url_matches?(url, pattern) when is_struct(pattern, Regex) do
    Regex.match?(pattern, url)
  end

  defp url_matches?(_url, _pattern), do: false
end
