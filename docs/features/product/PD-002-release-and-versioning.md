# PD-002 — Release and versioning policy

**Status:** partial

## Requirements

- `mix.exs`, changelog tags and package links use the same semantic version.
- Alpha/beta compatibility guarantees are explicit.
- Every release includes supported runtimes, provider capability changes and
  migration notes for schema or backtest semantics.
- A release is cut only after QL-001 thresholds and QL-002 fixture contracts
  pass.
