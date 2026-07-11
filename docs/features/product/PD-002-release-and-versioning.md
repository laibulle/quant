---
id: PD-002
status: partial
domain: product
owners: [maintainers]
depends_on: [QL-001, PD-001]
---

# PD-002 — Release and versioning policy

**Status:** partial

## Requirements

- `mix.exs`, changelog tags and package links use the same semantic version.
- Alpha/beta compatibility guarantees are explicit.
- Every release includes supported runtimes, provider capability changes and
  migration notes for schema or backtest semantics.
- A release is cut only after QL-001 thresholds and QL-002 fixture contracts
  pass.
- The current pre-release identifier in `mix.exs`, changelog section and Git tag
  must be identical.
