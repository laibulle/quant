defmodule Quant.Explorer.TestHelper do
  @moduledoc """
  Helper functions and utilities for testing Quant.Explorer.

  Provides common test fixtures, mock HTTP responses, and utility functions
  to make testing consistent across all provider implementations.
  """

  alias Explorer.DataFrame
  alias Quant.Explorer, as: QE
  alias Quant.Explorer.HttpMock

  @doc """
  Mock HTTP responses for tests.

  Usage:
      mock_http([
        {"https://api.example.com/data", %{status: 200, body: "{\"result\": \"success\"}"}},
        {"api.binance.com", "{\"symbols\": []}"}
      ])

  Or with regex patterns:
      mock_http([
        {~r/query.*\.finance\.yahoo\.com/, "{\"chart\": {\"result\": []}}"}
      ])
  """
  def mock_http(mocks) do
    HttpMock.reset()

    for {pattern, response} <- mocks do
      HttpMock.mock_response(pattern, response)
    end
  end

  @doc """
  Helper macro for setting up HTTP mocks in tests.
  """
  defmacro with_http_mock(mocks, do: block) do
    quote do
      QE.TestHelper.mock_http(unquote(mocks))

      # Mock the HttpClient at the module level
      original_http_client =
        Application.get_env(:quant, :http_client, QE.HttpClient)

      Application.put_env(:quant, :http_client, QE.HttpClient.Mock)

      try do
        unquote(block)
      after
        Application.put_env(:quant, :http_client, original_http_client)
        QE.HttpMock.reset()
      end
    end
  end

  @doc """
  Creates a mock HTTP response structure.
  """
  @spec mock_response(integer(), binary(), list()) :: {:ok, map()}
  def mock_response(status \\ 200, body \\ "", headers \\ []) do
    {:ok,
     %{
       status: status,
       body: body,
       headers: headers
     }}
  end

  @doc """
  Creates a mock error response.
  """
  @spec mock_error(term()) :: {:error, term()}
  def mock_error(reason), do: {:error, reason}

  @doc """
  Loads a test fixture from the fixtures directory.
  """
  @spec load_fixture(String.t()) :: binary()
  def load_fixture(filename) do
    fixture_path = Path.join([__DIR__, "fixtures", filename])
    File.read!(fixture_path)
  end

  @doc """
  Creates a sample historical data DataFrame for testing.
  """
  @spec sample_history_dataframe(String.t()) :: DataFrame.t()
  def sample_history_dataframe(symbol \\ "AAPL") do
    data = [
      %{
        "symbol" => symbol,
        "timestamp" => ~U[2024-01-01 00:00:00Z],
        "open" => 150.0,
        "high" => 155.0,
        "low" => 149.0,
        "close" => 152.0,
        "volume" => 1_000_000,
        "adj_close" => 152.0
      },
      %{
        "symbol" => symbol,
        "timestamp" => ~U[2024-01-02 00:00:00Z],
        "open" => 152.0,
        "high" => 158.0,
        "low" => 151.0,
        "close" => 157.0,
        "volume" => 1_200_000,
        "adj_close" => 157.0
      }
    ]

    DataFrame.new(data)
  end

  @doc """
  Creates a sample quote data DataFrame for testing.
  """
  @spec sample_quote_dataframe(String.t()) :: DataFrame.t()
  def sample_quote_dataframe(symbol \\ "AAPL") do
    data = [
      %{
        "symbol" => symbol,
        "price" => 157.0,
        "change" => 5.0,
        "change_percent" => 3.29,
        "volume" => 1_200_000,
        "timestamp" => DateTime.utc_now()
      }
    ]

    DataFrame.new(data)
  end

  @doc """
  Creates sample search results DataFrame for testing.
  """
  @spec sample_search_dataframe() :: DataFrame.t()
  def sample_search_dataframe do
    data = [
      %{
        "symbol" => "AAPL",
        "name" => "Apple Inc.",
        "type" => "stock",
        "exchange" => "NASDAQ"
      },
      %{
        "symbol" => "MSFT",
        "name" => "Microsoft Corporation",
        "type" => "stock",
        "exchange" => "NASDAQ"
      }
    ]

    DataFrame.new(data)
  end

  @doc """
  Validates that a DataFrame has the expected history schema.
  """
  @spec validate_history_schema(DataFrame.t()) :: :ok | {:error, term()}
  def validate_history_schema(df) do
    required_columns = ["symbol", "timestamp", "open", "high", "low", "close", "volume"]
    existing_columns = DataFrame.names(df)
    missing_columns = required_columns -- existing_columns

    case missing_columns do
      [] -> :ok
      missing -> {:error, {:missing_columns, missing}}
    end
  end

  @doc """
  Validates that a DataFrame has the expected quote schema.
  """
  @spec validate_quote_schema(DataFrame.t()) :: :ok | {:error, term()}
  def validate_quote_schema(df) do
    required_columns = ["symbol", "price", "timestamp"]
    existing_columns = DataFrame.names(df)
    missing_columns = required_columns -- existing_columns

    case missing_columns do
      [] -> :ok
      missing -> {:error, {:missing_columns, missing}}
    end
  end

  @doc """
  Sets up a clean rate limiter state for testing.
  """
  @spec setup_rate_limiter() :: :ok
  def setup_rate_limiter do
    # Reset all rate limits for testing with synchronous calls
    [:yahoo_finance, :alpha_vantage, :binance, :coin_gecko, :twelve_data]
    |> Enum.each(fn provider ->
      # Use GenServer.call to make it synchronous in tests
      :ok = GenServer.call(Quant.Explorer.RateLimiter, {:reset_limits, provider, :all})
    end)

    :ok
  end

  @doc """
  Converts endpoint definitions into HTTP mock responses keyed by request path.
  """
  def mock_http_paths(path: path, method: _method, response: response) do
    [{path, response}]
  end

  def mock_http_paths(endpoints) when is_list(endpoints) do
    Enum.map(endpoints, fn
      {path, _method, response} when is_binary(path) -> {path, response}
      %{path: path, method: _method, response: response} -> {path, response}
    end)
  end

  @doc """
  Executes a test block with HTTP responses mocked by request path.
  """
  defmacro with_http_mock_paths(opts, do: block) do
    quote do
      mocks = QE.TestHelper.mock_http_paths(unquote(opts))

      QE.TestHelper.mock_http(mocks)
      original_http_client = Application.get_env(:quant, :http_client, QE.HttpClient)
      Application.put_env(:quant, :http_client, QE.HttpClient.Mock)

      try do
        unquote(block)
      after
        Application.put_env(:quant, :http_client, original_http_client)
        QE.HttpMock.reset()
      end
    end
  end
end
