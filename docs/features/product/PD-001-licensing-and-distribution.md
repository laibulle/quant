---
id: PD-001
status: implemented
domain: product
owners: [maintainers]
depends_on: []
---

# PD-001 — Licensing and distribution

## Current state

The repository license is CC BY-NC 4.0. This restricts commercial use and is
not the usual license choice for an Elixir/Hex library.

## Decision

Retain **CC BY-NC 4.0**. Its NonCommercial term prohibits use primarily
intended for commercial advantage or monetary compensation. No commercial
license and no commercial support are offered.

## Acceptance criteria

- `LICENSE`, `mix.exs`, README, Hex metadata and contributor guidance state the
  same CC BY-NC policy.
- The change log records the effective date and compatibility implications.
- Contribution terms must not imply that commercial permissions or support can
  be obtained from the maintainers.

## References

- [Creative Commons CC BY-NC 4.0](https://creativecommons.org/licenses/by-nc/4.0/)
