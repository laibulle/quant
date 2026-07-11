# DF-001 — Unified market-data API

**Status:** partial  
**Owner module:** `Quant.Explorer`

## Goal

Expose `history/2`, `quote/2`, `search/2` and `info/2` through one Explorer
DataFrame-first API, while making provider differences explicit.

## Requirements

- Historical, quote and search responses use documented, stable column order.
- Invalid provider, interval, period, currency, date range and missing API key
  return tagged errors.
- Provider-specific unsupported capability returns `{:error, :not_supported}`.
- `history/2` may cache only successful historical responses; callers can set
  `cache: false`.

## Acceptance criteria

- Contract tests cover every public schema and every provider adapter.
- The API never fabricates a timestamp, a price or a volume when source data is
  invalid or missing.
- Documentation carries a capability matrix rather than promising equivalent
  market coverage.

## Non-goals

Cross-provider price reconciliation, corporate-action reconciliation and a
guarantee of provider availability.
