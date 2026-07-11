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
