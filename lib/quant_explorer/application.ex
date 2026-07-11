defmodule Quant.Explorer.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  alias Quant.Explorer.{Config, RateLimiting}

  @impl true
  def start(_type, _args) do
    rate_limiting = Config.rate_limiting_config()

    backend =
      case rate_limiting.backend do
        :ets ->
          RateLimiting.EtsBackend

        unsupported ->
          raise ArgumentError, "unsupported rate limiting backend: #{inspect(unsupported)}"
      end

    children = [
      {Quant.Explorer.Cache, ttl: Config.cache_ttl(), limit: Config.get(:cache_limit, 10_000)},
      {Quant.Explorer.RateLimiter,
       [
         backend: backend,
         backend_opts: rate_limiting.backend_opts
       ]}
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Quant.Explorer.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
