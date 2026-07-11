---
id: PF-002
status: implemented
domain: platform
owners: [Quant.Explorer.RateLimiter]
depends_on: []
---

# PF-002 — Provider-aware rate limiting

**Status:** implemented

## Scope

Local ETS rate limiting with sliding-window, weighted and burst policies.

## Requirements

- Each actual provider endpoint request consumes exactly one configured limit.
- Binance weight derives from endpoint parameters.
- Status exposes remaining capacity and retry delay.
- Configuration selects the supported ETS backend at application startup.

## Non-goals

Distributed limiting. Redis is not a supported backend until a maintained
dependency, atomic scripts and operational tests are introduced.
