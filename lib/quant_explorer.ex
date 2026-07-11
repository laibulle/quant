defmodule Quant.Explorer do
  @moduledoc """
  Quant.Explorer - High-performance standardized financial data API for Elixir.

  Fetch financial and cryptocurrency data from multiple providers with universal
  parameters and identical output schemas for seamless analysis.

  ## Key Features

  - **Universal Parameters**: Same parameters work with ALL providers
  - **Identical Schemas**: All DataFrames have consistent column structures
  - **High Performance**: Built on Explorer's Polars backend
  - **Type Safety**: Strong typing and validation throughout
  - **Multi-Provider**: Yahoo Finance, Alpha Vantage, Binance, CoinGecko, Twelve Data

  ## Quick Start

      # Universal parameters work with any provider
      {:ok, df} = Quant.Explorer.history("AAPL",
        provider: :yahoo_finance, interval: "1d", period: "1y")

      {:ok, df} = Quant.Explorer.history("BTCUSDT",
        provider: :binance, interval: "1d", period: "1y")

      # All DataFrames have identical schemas - combine seamlessly
      DataFrame.concat_rows(df1, df2)

  ## Standardized Parameters

  - `:provider` - Data provider (:yahoo_finance, :alpha_vantage, :binance, :coin_gecko, :twelve_data)
  - `:interval` - Standard intervals: "1m", "5m", "15m", "30m", "1h", "1d", "1w", "1mo"
  - `:period` - Standard periods: "1d", "5d", "1mo", "3mo", "6mo", "1y", "2y", "5y", "10y", "max"
  - `:limit` - Number of data points (1-5000)
  - `:start_date`/`:end_date` - Date range (Date, DateTime, or ISO string)
  - `:currency` - Base currency: "usd", "eur", "btc", "eth"
  - `:api_key` - API key for authentication
  """

  alias Explorer.DataFrame
  alias Quant.Explorer.{Cache, Config, SchemaStandardizer}

  @type symbol :: String.t()
  @type symbols :: [symbol()]
  @type provider :: atom()
  @type options :: keyword()

  @doc """
  Fetches standardized historical data with universal parameters.

  All providers return identical DataFrame schemas with these columns:
  - `symbol`, `timestamp`, `open`, `high`, `low`, `close`, `volume`
  - `adj_close`, `market_cap`, `provider`, `currency`, `timezone`

  ## Examples

      # Same parameters work with any provider
      {:ok, df} = Quant.Explorer.history("AAPL", provider: :yahoo_finance, interval: "1d", period: "1y")
      {:ok, df} = Quant.Explorer.history("BTCUSDT", provider: :binance, interval: "1d", period: "1y")

      # Combine data from multiple providers seamlessly
      DataFrame.concat_rows(df1, df2)
  """
  @spec history(symbol() | symbols(), options()) :: {:ok, DataFrame.t()} | {:error, term()}
  def history(symbols, opts \\ []) do
    case Keyword.get(opts, :provider) do
      nil ->
        {:error, :provider_required}

      provider ->
        with {:ok, standardized_params} <- SchemaStandardizer.standardize_params(opts, provider),
             {:ok, provider_module} <- get_provider_module(provider) do
          cache_key = {:history, provider, symbols, Keyword.delete(standardized_params, :api_key)}

          history_request(
            cache_key,
            opts,
            provider_module,
            symbols,
            standardized_params,
            provider
          )
        else
          {:error, reason} -> {:error, reason}
        end
    end
  end

  @doc """
  Fetches standardized real-time quotes with universal parameters.

  All providers return identical DataFrame schemas with these columns:
  - `symbol`, `price`, `change`, `change_percent`, `volume`, `high_24h`, `low_24h`
  - `market_cap`, `timestamp`, `provider`, `currency`, `market_state`
  """
  @spec quote(symbol() | symbols(), options()) :: {:ok, DataFrame.t()} | {:error, term()}
  def quote(symbols, opts \\ []) do
    case Keyword.get(opts, :provider) do
      nil ->
        {:error, :provider_required}

      provider ->
        with {:ok, standardized_params} <- SchemaStandardizer.standardize_params(opts, provider),
             {:ok, provider_module} <- get_provider_module(provider),
             {:ok, raw_df} <- provider_module.quote(symbols, standardized_params),
             {:ok, standardized_df} <-
               SchemaStandardizer.standardize_quote_schema(raw_df,
                 provider: provider,
                 currency: standardized_params[:currency]
               ) do
          {:ok, standardized_df}
        else
          {:error, reason} -> {:error, reason}
        end
    end
  end

  @doc """
  Searches for symbols with standardized results.

  All providers return identical DataFrame schemas with these columns:
  - `symbol`, `name`, `type`, `exchange`, `currency`, `country`
  - `sector`, `industry`, `market_cap`, `provider`, `match_score`
  """
  @spec search(String.t(), options()) :: {:ok, DataFrame.t()} | {:error, term()}
  def search(query, opts \\ []) do
    case Keyword.get(opts, :provider) do
      nil ->
        {:error, :provider_required}

      provider ->
        with {:ok, standardized_params} <- SchemaStandardizer.standardize_params(opts, provider),
             {:ok, provider_module} <- get_provider_module(provider),
             {:ok, raw_df} <- provider_module.search(query, standardized_params),
             {:ok, standardized_df} <-
               SchemaStandardizer.standardize_search_schema(raw_df,
                 provider: provider
               ) do
          {:ok, standardized_df}
        else
          {:error, reason} -> {:error, reason}
        end
    end
  end

  @doc """
  Fetches company/asset information.
  Note: Info structure varies between providers and is not fully standardized.
  """
  @spec info(symbol(), options()) :: {:ok, map()} | {:error, term()}
  def info(symbol, opts \\ []) do
    case Keyword.get(opts, :provider) do
      nil ->
        {:error, :provider_required}

      provider ->
        with {:ok, standardized_params} <- SchemaStandardizer.standardize_params(opts, provider),
             {:ok, provider_module} <- get_provider_module(provider) do
          provider_module.info(symbol, standardized_params)
        else
          {:error, reason} -> {:error, reason}
        end
    end
  end

  # Convenience aliases for backward compatibility (redirected to standardized API)
  @doc """
  Alias for history/2. Deprecated - use history/2 directly.
  """
  @spec fetch(symbol() | symbols(), options()) :: {:ok, DataFrame.t()} | {:error, term()}
  def fetch(symbols, opts \\ []), do: history(symbols, opts)

  @doc """
  Returns statistics for the local historical-data cache.
  """
  @spec cache_stats() :: map()
  def cache_stats, do: Cache.stats()

  @doc """
  Clears all local cached historical responses.
  """
  @spec clear_cache() :: :ok
  def clear_cache, do: Cache.clear()

  @doc """
  Invalidates cached historical responses by `:provider`, `:symbol`,
  standardized `:interval` and/or an overlapping `:start_date`/`:end_date`.
  """
  @spec invalidate_cache(keyword()) :: {:ok, non_neg_integer()} | {:error, term()}
  def invalidate_cache(filters \\ []), do: Cache.invalidate(filters)

  @doc """
  Removes expired local cache entries and returns the number purged.
  """
  @spec purge_expired_cache() :: non_neg_integer()
  def purge_expired_cache, do: Cache.purge_expired()

  @doc """
  Lists supported standard intervals.
  """
  @spec supported_intervals() :: [String.t()]
  def supported_intervals, do: SchemaStandardizer.supported_intervals()

  @doc """
  Lists supported standard periods.
  """
  @spec supported_periods() :: [String.t()]
  def supported_periods, do: SchemaStandardizer.supported_periods()

  @doc """
  Lists supported currencies for crypto providers.
  """
  @spec supported_currencies() :: [String.t()]
  def supported_currencies, do: SchemaStandardizer.supported_currencies()

  @doc """
  Lists all available providers and their status.
  """
  @spec providers() :: map()
  def providers do
    providers = [:yahoo_finance, :alpha_vantage, :binance, :coin_gecko, :twelve_data]

    Enum.reduce(providers, %{}, fn provider, acc ->
      provider_info = %{
        rate_limit: Config.rate_limit(provider),
        api_key_configured: Config.api_key(provider) != nil,
        # All providers now use standardized schemas
        standardized: true,
        timezone: get_provider_timezone(provider),
        supported_intervals: get_provider_intervals(provider),
        supported_currencies: get_provider_currencies(provider)
      }

      Map.put(acc, provider, provider_info)
    end)
  end

  @doc """
  Gets configuration information for the library.
  """
  @spec config() :: map()
  def config do
    %{
      version: Mix.Project.config()[:version],
      standardized_api: true,
      supported_intervals: supported_intervals(),
      supported_periods: supported_periods(),
      supported_currencies: supported_currencies(),
      http_timeout: Config.http_timeout(),
      cache_ttl: Config.cache_ttl(),
      telemetry_enabled: Config.telemetry_enabled?(),
      user_agent: Config.user_agent()
    }
  end

  # Private helper functions

  defp get_provider_module(provider) do
    case lookup_provider_module(provider) do
      {:ok, module} -> validate_provider_module(module, provider)
      error -> error
    end
  end

  defp lookup_provider_module(provider) do
    module =
      case provider do
        :yahoo_finance -> Quant.Explorer.Providers.YahooFinance
        :alpha_vantage -> Quant.Explorer.Providers.AlphaVantage
        :binance -> Quant.Explorer.Providers.Binance
        :coin_gecko -> Quant.Explorer.Providers.CoinGecko
        :twelve_data -> Quant.Explorer.Providers.TwelveData
        _ -> nil
      end

    case module do
      nil -> {:error, {:unknown_provider, provider}}
      mod -> {:ok, mod}
    end
  end

  defp validate_provider_module(module, provider) do
    case Code.ensure_loaded(module) do
      {:module, ^module} -> {:ok, module}
      {:error, :nofile} -> {:error, {:provider_not_implemented, provider}}
      {:error, reason} -> {:error, {:provider_load_error, reason}}
    end
  end

  defp get_provider_timezone(provider) do
    case provider do
      :yahoo_finance -> "America/New_York"
      :alpha_vantage -> "America/New_York"
      :binance -> "UTC"
      :coin_gecko -> "UTC"
      :twelve_data -> "America/New_York"
      _ -> "UTC"
    end
  end

  defp get_provider_intervals(provider) do
    case provider do
      :yahoo_finance -> ["1m", "5m", "15m", "30m", "1h", "1d", "1w", "1mo"]
      :alpha_vantage -> ["1m", "5m", "15m", "30m", "1h", "1d", "1w", "1mo"]
      :binance -> ["1m", "5m", "15m", "30m", "1h", "1d", "1w"]
      :coin_gecko -> ["1d"]
      :twelve_data -> ["1m", "5m", "15m", "30m", "1h", "1d", "1w", "1mo"]
      _ -> ["1d"]
    end
  end

  defp get_provider_currencies(provider) do
    case provider do
      :coin_gecko -> ["usd", "eur", "btc", "eth"]
      :binance -> ["usdt", "btc", "eth", "bnb"]
      _ -> ["usd"]
    end
  end

  defp fetch_standardized_history(provider_module, symbols, standardized_params, provider) do
    with {:ok, raw_df} <- provider_module.history(symbols, standardized_params) do
      SchemaStandardizer.standardize_history_schema(raw_df,
        provider: provider,
        currency: standardized_params[:currency],
        timezone: get_provider_timezone(provider)
      )
    end
  end

  defp history_request(cache_key, opts, provider_module, symbols, standardized_params, provider) do
    fetcher = fn ->
      fetch_standardized_history(provider_module, symbols, standardized_params, provider)
    end

    cached_or_fetch(cache_key, Keyword.get(opts, :cache, true), fetcher)
  end

  defp cached_or_fetch(_cache_key, false, fetcher) do
    started_at = System.monotonic_time(:microsecond)
    observe_history(fetcher.(), false, started_at)
  end

  defp cached_or_fetch(cache_key, true, fetcher) do
    started_at = System.monotonic_time(:microsecond)
    {cache_status, result} = Cache.fetch(cache_key, fetcher)
    observe_history(result, cache_status, started_at)
  end

  defp observe_history(result, cache_status, started_at) do
    if Config.telemetry_enabled?() do
      :telemetry.execute(
        [:quant, :explorer, :history],
        %{duration: System.monotonic_time(:microsecond) - started_at},
        %{cache_status: cache_status, result: result_status(result)}
      )
    end

    result
  end

  defp result_status({:ok, _}), do: :ok
  defp result_status({:error, reason}), do: {:error, reason}
end
