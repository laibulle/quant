---
id: DF-010
status: implemented
domain: data
owners: [Quant.Explorer.Providers.YahooFinance]
depends_on: [DF-001, DF-002, PF-001, PF-002]
---

# DF-010 — Yahoo Finance adapter

**Status:** implemented

## Scope

Historical bars, batch quotes, symbol search, asset information and options
chains through the Yahoo endpoints.

## Acceptance criteria

- Supports the standard interval and period mapping, including `1w` → `1wk`.
- Converts chart timestamps to UTC and reports provider errors without exposing
  raw credentials.
- Batch failures identify the failing symbol; stream behaviour is documented.
- Recorded-response tests cover success, empty result, rate limit and symbol
  not found.

## Constraints

Yahoo is an unofficial upstream interface; availability and historical windows
are not contractual.
