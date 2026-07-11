---
id: PF-003
status: partial
domain: platform
owners: [Quant.Explorer.Cache]
depends_on: [DF-001, PF-004]
---

# PF-003 — Cache evolution

**Status:** partial  
**Current implementation:** local ETS cache for successful historical requests.

## Goal

Provide safe reuse of immutable market-data responses without stale quote data
or cross-provider contamination.

## Planned requirements

- Targeted invalidation by provider, symbol, interval and date range.
- Hit/miss/eviction statistics and telemetry.
- Single-flight request coalescing on cache miss.
- Optional persistent and distributed backends behind a behaviour.
- Cache keys include schema version and never contain credentials.

## Acceptance criteria

- Concurrent identical requests perform one upstream call.
- Invalidation cannot remove unrelated provider data.
- Persistence and distributed backends pass the same contract suite.
