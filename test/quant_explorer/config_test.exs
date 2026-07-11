defmodule Quant.Explorer.ConfigTest do
  use ExUnit.Case, async: false

  alias Quant.Explorer.Config

  setup do
    original_config = Application.get_all_env(:quant)

    on_exit(fn ->
      Application.get_all_env(:quant)
      |> Keyword.keys()
      |> Enum.each(&Application.delete_env(:quant, &1))

      Enum.each(original_config, fn {key, value} ->
        Application.put_env(:quant, key, value)
      end)
    end)

    :ok
  end

  test "resolves defaults, nested settings and provider overrides" do
    Application.put_env(:quant, :providers, %{
      demo: %{base_url: "https://api.example.test", timeout: 250}
    })

    Application.put_env(:quant, :rate_limits, %{demo: 12})
    Application.put_env(:quant, :http_timeout, 500)

    assert "https://api.example.test" = Config.get([:providers, :demo, :base_url])
    assert :fallback = Config.get([:providers, :unknown], :fallback)
    assert 12 = Config.rate_limit(:demo)
    assert 60 = Config.rate_limit(:unknown)

    assert %{rate_limit: 12, timeout: 250, api_key: nil, base_url: "https://api.example.test"} =
             Config.provider_config(:demo)
  end

  test "resolves API keys from literals and environment variables" do
    System.put_env("QUANT_CONFIG_TEST_KEY", "from-environment")

    on_exit(fn -> System.delete_env("QUANT_CONFIG_TEST_KEY") end)

    Application.put_env(:quant, :api_keys, %{
      literal: "literal-key",
      environment: {:system, "QUANT_CONFIG_TEST_KEY"},
      fallback: {:system, "QUANT_CONFIG_TEST_DEFAULT", "fallback-key"},
      invalid: :unsupported
    })

    assert "literal-key" = Config.api_key(:literal)
    assert "from-environment" = Config.api_key(:environment)
    assert "fallback-key" = Config.api_key(:fallback)
    assert nil == Config.api_key(:invalid)

    assert %{literal: "literal-key", environment: "from-environment", fallback: "fallback-key"} =
             Config.api_keys()
  end

  test "reports missing mandatory settings and exposes derived configurations" do
    Enum.each([:rate_limits, :http_timeout, :cache_ttl], &Application.delete_env(:quant, &1))

    assert {:error, missing_keys} = Config.validate_config()
    assert Enum.sort(missing_keys) == [:cache_ttl, :http_timeout, :rate_limits]

    Application.put_env(:quant, :cache_ttl, 123)
    Application.put_env(:quant, :cache_limit, 45)
    Application.put_env(:quant, :cache_stats, false)
    Application.put_env(:quant, :rate_limiting_backend, :ets)

    assert [ttl: 123, limit: 45, stats: false] = Config.cache_config()
    assert %{backend: :ets, enable_stats: true} = Config.rate_limiting_config()
  end
end
