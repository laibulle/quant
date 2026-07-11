---
id: PF-003
status: partial
domain: platform
owners: [Quant.Explorer.Cache]
depends_on: [DF-001, PF-004]
---

# PF-003 — Cache evolution

**Status:** partial  
**Current implementation:** local ETS cache for successful historical requests,
with statistics, targeted invalidation and same-key miss coalescence.

## Goal

Provide safe reuse of immutable market-data responses without stale quote data
or cross-provider contamination.

## Implemented requirements

- [x] Targeted invalidation by provider, symbol and interval via
  `Quant.Explorer.invalidate_cache/1`.
- [x] Invalidation by overlapping explicit `start_date`/`end_date` ranges and
  explicit expiry purge via `Quant.Explorer.purge_expired_cache/0`.
- [x] Hit/miss/eviction statistics and cache telemetry metadata.
- [x] Single-flight request coalescing on cache miss.

## Planned requirements

- Optional persistent and distributed backends behind a behaviour.
- Cache keys include schema version and never contain credentials.

## Acceptance criteria

- [x] Local statistics expose entry count, capacity, TTL, hit rate, hits,
  misses, writes, evictions, expirations and clears.
- [x] Concurrent identical requests perform one upstream call.
- [x] Invalidation cannot remove unrelated provider data.
- Persistence and distributed backends pass the same contract suite.
