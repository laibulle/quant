---
id: QL-001
status: partial
domain: quality
owners: [test]
depends_on: []
---

# QL-001 — Test and coverage strategy

**Status:** partial

## Goal

Make correctness claims proportionate to automated evidence.

## Requirements

- Unit tests cover schemas, parameter translation, data integrity, provider
  error mapping, cache behaviour, rate limits and execution semantics.
- Contract tests run every provider against recorded fixtures.
- Coverage is measured in CI with thresholds per critical module, not only a
  global percentage.
- The HTTP client and data transformer have dedicated success and failure tests.

## Targets

- 90% relevant-line coverage for `HttpClient`, `DataTransformer`,
  `SchemaStandardizer`, cache and rate limiter.
- 80% relevant-line coverage for each provider adapter.
- No test warning from support-file discovery or deliberate invalid-type tests.

## Implemented coverage

- [x] `DataTransformer` is covered for timestamp, number and volume
  normalization, list/map history and quote transformation, search results, CSV
  conversion and schema-specific cleaning.
- [x] `HttpClient` is covered for JSON decoding, status classification, provider
  error extraction and unsupported-method rejection without network access.
- [x] `HttpClient` is exercised against a local TCP HTTP server for encoded GET
  queries, filtered headers, POST bodies and content types.
- [x] `Config` is covered for nested lookup, runtime API-key resolution,
  provider overrides, derived settings and missing-config validation.
- [x] `RateLimiter` is covered end to end for pre-flight checks, consumption,
  reset, provider quota exhaustion, Binance weights and immediate availability.
- [x] `SchemaStandardizer` is covered for provider parameter translation,
  validation, historical/quote/search normalization and strict numeric parsing.
- [x] `TwelveData` is covered for intraday timestamp parsing, provider quote
  timestamps, malformed numeric values, company profiles and forex rates.
- [x] `CoinGecko` is covered for source timestamps on simple prices and market
  ranking data, incomplete metadata and nullable market values.
- [x] `AlphaVantage` is covered for intraday timestamps, quote trading dates
  and strict numeric parsing.
- [x] `YahooFinance` is covered for source quote timestamps, empty historical
  data, company information and option chains.
- [x] The public `Quant.Explorer` API is covered for provider dispatch, `fetch`
  compatibility, cached and uncached histories, metadata and unknown providers.
- [x] Rate-limiting request metadata and every supported algorithm configuration
  are covered at the behaviour boundary.
- [x] `HttpClientConfig` is covered for default/configured client selection and
  GET, POST and JSON delegation.
