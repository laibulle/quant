# PF-004 — Runtime configuration and telemetry

**Status:** partial

## Scope

Configuration resolution, environment-backed keys and operational events.

## Requirements

- API keys resolve at runtime and are absent from logs, cache keys and errors.
- Configuration validates supported backends on startup.
- Every public provider operation emits duration, provider, operation, result
  and cache metadata when telemetry is enabled.
- Telemetry is disabled or captured in deterministic tests.

## Gap

History emits telemetry today; quote, search and info events remain to be
implemented with the same event contract.
