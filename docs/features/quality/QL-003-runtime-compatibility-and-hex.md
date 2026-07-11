---
id: QL-003
status: partial
domain: quality
owners: [mix]
depends_on: [QL-001, PD-001, PD-002]
---

# QL-003 — Runtime compatibility and Hex readiness

**Status:** partial

## Decision

CI supports the latest stable Elixir and OTP releases only. It intentionally
does not claim compatibility with older runtime versions. The workflow uses
version ranges that exclude pre-releases, so each execution resolves the latest
stable toolchain available to the runner.

## Requirements after decision

- CI compiles and tests the latest stable Elixir/OTP pair on every push and pull
  request.
- The README badge, `mix.exs`, release notes and CI agree.
- Deprecated runtime APIs have compatibility shims or documented exclusions.
- Hex package metadata, documentation generation and installation are tested.

## Non-goal

Claiming an older runtime works without executing the suite on it, or treating
a pre-release as a supported stable runtime.
