# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :quant,
  # Rate limiting (legacy - for backwards compatibility)
  rate_limits: %{
    yahoo_finance: 100,
    alpha_vantage: 5,
    binance: 1200,
    coin_gecko: 50,
    twelve_data: 8
  },

  # Advanced rate limiting configuration (ETS is the built-in backend)
  rate_limiting_backend: :ets,
  rate_limiting_backend_opts: [
    # ETS options
    table_opts: [:set, :public, :named_table]
  ],
  rate_limiting_cleanup_interval: :timer.minutes(5),
  rate_limiting_enable_stats: true,

  # Caching settings
  cache_ttl: :timer.minutes(5),
  cache_limit: 10_000,
  cache_stats: true,

  # HTTP settings
  http_timeout: 10_000,
  user_agent: "Quant.Explorer/0.1.0 (Elixir)",

  # Telemetry and logging
  telemetry_enabled: true,
  log_level: :info,

  # API keys (override in runtime.exs with system environment variables)
  api_keys: %{
    alpha_vantage: {:system, "ALPHA_VANTAGE_API_KEY"},
    twelve_data: {:system, "TWELVE_DATA_API_KEY"},
    binance: {:system, "BINANCE_API_KEY"},
    coin_gecko: {:system, "COINGECKO_API_KEY"}
  },

  # Provider-specific configuration
  providers: %{
    yahoo_finance: %{
      base_url: "https://query1.finance.yahoo.com",
      crumb_url: "https://fc.yahoo.com"
    },
    alpha_vantage: %{
      base_url: "https://www.alphavantage.co/query"
    },
    binance: %{
      base_url: "https://api.binance.com/api/v3"
    },
    coin_gecko: %{
      base_url: "https://api.coingecko.com/api/v3"
    },
    twelve_data: %{
      base_url: "https://api.twelvedata.com"
    }
  }

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
