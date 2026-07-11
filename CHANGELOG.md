# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Changed
- Historical requests now preserve `adjusted: false`, translate Yahoo weekly intervals correctly, and reject inverted date ranges.
- Binance consumes standardized date ranges; CoinGecko consumes standardized currency options.
- Historical data is cached locally in ETS and emits a `[:quant, :explorer, :history]` telemetry event.
- The HTTP client always verifies TLS certificates and hostnames.
- Backtests execute close-derived signals on the following bar's open by default; same-bar execution is opt-in.
- Performance analysis now returns return, risk, drawdown and trade metrics.

### Removed
- Redis is no longer advertised as a supported rate-limiting backend. The checked-in implementation uses ETS only.

## [0.1.0] - 2025-01-15

### Added
- **Comprehensive Financial Data Library** with standardized API across multiple providers
- **Universal Parameters**: Same interface works with Yahoo Finance, Alpha Vantage, Binance, CoinGecko, Twelve Data
- **Identical Output Schemas**: All providers return exact 12-column DataFrames for seamless analysis
- **Mathematical Indicators** with Python-validated accuracy:
  - RSI (Relative Strength Index) - 100% accuracy vs Python
  - DEMA (Double Exponential Moving Average) - 99.96% accuracy
  - HMA (Hull Moving Average) - 100% accuracy vs Python
  - KAMA (Kaufman Adaptive Moving Average) - 100% accuracy vs Python
  - TEMA (Triple Exponential Moving Average) - 99.9988% accuracy
  - WMA (Weighted Moving Average) - 100% accuracy vs Python
- **Cross-Language Validation Framework**: Comprehensive Python validation tests ensuring mathematical accuracy
- **Multi-Provider Support**:
  - Yahoo Finance (free, no API key required)
  - Alpha Vantage (premium, API key required)
  - Binance (free crypto data, no API key required)
  - CoinGecko (free crypto data, no API key required)
  - Twelve Data (premium, API key required)
- **Advanced Rate Limiting**: ETS and Redis backends with provider-specific patterns
- **Zero External HTTP Dependencies**: Uses built-in Erlang `:httpc` for maximum reliability
- **Comprehensive Test Suite**: 335 tests with 0 failures, including integration tests
- **Production-Ready Architecture**: Optimized for high-throughput financial analysis

### Technical Features
- **Explorer DataFrame First**: All data returns as Explorer DataFrames for immediate analysis
- **Standardization Engine**: Automatic parameter translation and schema normalization
- **Flexible API Keys**: Pass inline or configure globally
- **Streaming Support**: Handle large datasets efficiently
- **Type Safety**: Full Dialyzer type specifications
- **Error Handling**: Comprehensive error types and graceful degradation

### Documentation
- Complete API documentation with examples
- Troubleshooting guide for common API issues
- Standardization guide explaining universal parameters
- Testing guide with both mocked and integration tests
- Livebook-ready examples for data science workflows

### License
- **Creative Commons Attribution-NonCommercial 4.0 International License**
- Free for personal, educational, research, and non-profit use
- Commercial licensing available separately
- Protects against unauthorized commercial exploitation while ensuring community access

[Unreleased]: https://github.com/the-nerd-company/quant/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/the-nerd-company/quant/releases/tag/v0.1.0
