# QL-003 — Runtime compatibility and Hex readiness

**Status:** decision-required

## Decision

Choose the minimum supported Elixir/OTP pair before lowering `mix.exs` bounds.
The choice must be based on APIs used by the library (including built-in JSON),
Explorer/Nx compatibility and the project support policy.

## Requirements after decision

- CI compiles and tests the complete supported Elixir/OTP matrix.
- The README badge, `mix.exs`, release notes and CI agree.
- Deprecated runtime APIs have compatibility shims or documented exclusions.
- Hex package metadata, documentation generation and installation are tested.

## Non-goal

Claiming an older runtime works without executing the suite on it.
