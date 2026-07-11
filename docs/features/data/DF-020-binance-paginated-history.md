---
id: DF-020
status: planned
domain: data
owners: [Quant.Explorer.Providers.Binance]
depends_on: [DF-012, PF-002, QL-002]
---

# DF-020 — Binance paginated history

**Status:** planned  
**Depends on:** DF-012, PF-002, QL-002

## Goal

Fetch an arbitrary supported Binance time range without silently truncating at
1,000 klines.

## Requirements

- Split an inclusive date range into chronological requests of at most 1,000
  bars.
- Consume the correct Binance endpoint weight for every page.
- Deduplicate boundary timestamps and return one ascending DataFrame.
- Stop immediately on a page failure and return page context in the error.
- Support cancellation and configurable page concurrency of `1` by default.

## Acceptance criteria

- A 2,001-bar fixture performs three requests with no duplicates or gaps.
- Rate-limit and partial-page failure tests prove no partial DataFrame is
  returned as success.
- Pagination is transparent to `Quant.Explorer.history/2` and direct provider
  calls.
