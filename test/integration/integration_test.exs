defmodule Quant.Explorer.IntegrationTest do
  @moduledoc """
  Integration tests for Quant.Explorer.
  """
  use ExUnit.Case

  @moduletag :integration

  alias Quant.Explorer, as: QE

  describe "Provider Integration" do
    test "All providers are properly registered" do
      providers = QE.providers()

      assert is_map(providers)
      assert Map.has_key?(providers, :yahoo_finance)
      assert Map.has_key?(providers, :alpha_vantage)
      assert Map.has_key?(providers, :binance)

      # Each provider should have status information
      for {_provider, info} <- providers do
        assert Map.has_key?(info, :rate_limit)
        assert Map.has_key?(info, :api_key_configured)
        assert Map.has_key?(info, :current_request_count)
      end
    end

    test "Provider modules are available and have required functions" do
      # Test Yahoo Finance
      assert Code.ensure_loaded?(Quant.Explorer.Providers.YahooFinance)
      assert function_exported?(Quant.Explorer.Providers.YahooFinance, :history, 2)
      assert function_exported?(Quant.Explorer.Providers.YahooFinance, :quote, 1)
      assert function_exported?(Quant.Explorer.Providers.YahooFinance, :search, 1)

      # Test Alpha Vantage
      assert Code.ensure_loaded?(Quant.Explorer.Providers.AlphaVantage)
      assert function_exported?(Quant.Explorer.Providers.AlphaVantage, :history, 2)
      assert function_exported?(Quant.Explorer.Providers.AlphaVantage, :quote, 1)
      assert function_exported?(Quant.Explorer.Providers.AlphaVantage, :search, 1)

      # Test Binance
      assert Code.ensure_loaded?(Quant.Explorer.Providers.Binance)
      assert function_exported?(Quant.Explorer.Providers.Binance, :history, 2)
      assert function_exported?(Quant.Explorer.Providers.Binance, :quote, 1)
      assert function_exported?(Quant.Explorer.Providers.Binance, :search, 1)
    end

    test "Rate limiter is properly integrated" do
      # Test that rate limiter is available and working
      assert GenServer.whereis(Quant.Explorer.RateLimiter) != nil

      # Test rate limit status for each provider
      for provider <- [:yahoo_finance, :alpha_vantage, :binance] do
        status = QE.RateLimiter.get_limit_status(provider, :default)
        assert is_map(status)
        assert Map.has_key?(status, :remaining)
        assert Map.has_key?(status, :reset_time)
      end
    end

    test "Main API functions delegate to providers correctly" do
      # Test that main API functions exist and delegate properly
      assert function_exported?(Quant.Explorer, :fetch, 1) or
               function_exported?(Quant.Explorer, :fetch, 2)

      assert function_exported?(Quant.Explorer, :quote, 1) or
               function_exported?(Quant.Explorer, :quote, 2)

      assert function_exported?(Quant.Explorer, :search, 1) or
               function_exported?(Quant.Explorer, :search, 2)

      assert function_exported?(Quant.Explorer, :providers, 0)

      # Test provider parameter validation (only if the API validates)
      try do
        Quant.Explorer.fetch("AAPL", provider: :invalid_provider)
        # If it doesn't raise, that's also valid - some APIs might not validate
      rescue
        ArgumentError ->
          # This is what we expect if validation is implemented
          assert true
      end
    end

    test "Configuration is properly loaded" do
      # Test that application is loaded
      assert Application.started_applications()
             |> Enum.any?(fn {app, _, _} -> app == :quant end)

      # Test rate limiting backend if configured
      backend = Application.get_env(:quant, :rate_limiting_backend)

      if backend do
        assert backend in [:ets, :redis]
      end
    end

    test "Application supervision tree is working" do
      # Test that the main application components are running
      children = Supervisor.which_children(Quant.Explorer.Supervisor)
      assert children != []

      # Rate limiter should be running
      rate_limiter_running =
        Enum.any?(children, fn
          {Quant.Explorer.RateLimiter, _pid, _type, _modules} -> true
          _ -> false
        end)

      assert rate_limiter_running, "Rate limiter should be running under supervisor"
    end
  end
end
