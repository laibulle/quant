defmodule Quant.Explorer.MixProject do
  @moduledoc false
  use Mix.Project

  def project do
    [
      app: :quant,
      version: "0.1.0-alpha.1",
      elixir: "~> 1.20",
      elixirc_options: [warnings_as_errors: true],
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description: description(),
      package: package(),
      test_coverage: [
        tool: ExCoveralls,
        output_dir: "cover/",
        preferred_cli_env: [
          coveralls: :test,
          "coveralls.detail": :test,
          "coveralls.post": :test,
          "coveralls.html": :test,
          "coveralls.cobertura": :test
        ]
      ],
      dialyzer: [
        plt_file: {:no_warn, "priv/plts/dialyzer.plt"},
        plt_add_apps: [
          :mix,
          :ex_unit
        ],
        plt_core_path: "priv/plts/core.plt",
        plt_add_deps: :apps_direct,
        plt_ignore_apps: [],
        flags: [:unmatched_returns, :error_handling, :no_opaque]
      ]
    ]
  end

  def cli do
    [
      preferred_envs: [
        coveralls: :test,
        "coveralls.detail": :test,
        "coveralls.post": :test,
        "coveralls.html": :test,
        "coveralls.cobertura": :test
      ]
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger, :inets, :ssl],
      mod: {Quant.Explorer.Application, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:explorer, "~> 0.12"},
      {:nx, "~> 0.10"},
      {:decimal, "~> 3.1"},
      {:telemetry, "~> 1.0"},
      {:certifi, "~> 2.15"},
      {:ex_doc, "~> 0.31", only: :dev, runtime: false},
      {:git_hooks, "0.8.1", only: :dev, runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:excoveralls, "~> 0.18", only: :test},
      {:pythonx, "~> 0.2", only: :test}
    ]
  end

  defp description do
    "Standardized financial data API for Elixir with Explorer DataFrames. " <>
      "Fetch from multiple providers with universal parameters. " <>
      "Includes technical indicators (RSI, DEMA, HMA, KAMA, TEMA, WMA) with Python-validated accuracy."
  end

  defp package do
    [
      name: "quant",
      licenses: ["CC-BY-NC-4.0"],
      links: %{
        "GitHub" => "https://github.com/the-nerd-company/quant"
      },
      maintainers: ["Guillaume Dott"],
      files: ~w(lib mix.exs README.md LICENSE CHANGELOG.md),
      exclude_patterns: ["test/", "docs/", "examples/", "_build/", "deps/", "cover/"]
    ]
  end
end
