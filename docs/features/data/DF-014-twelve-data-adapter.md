---
id: DF-014
status: partial
domain: data
owners: [Quant.Explorer.Providers.TwelveData]
depends_on: [DF-001, DF-002, PF-001, PF-002]
---

# DF-014 — Twelve Data adapter

**Status:** partial

## Scope

Time series, quotes, profiles, search and FX rates backed by an API key.

## Requirements

- Runtime or inline credentials produce `:api_key_missing` rather than an
  exception when absent.
- Standard intervals and requested output sizes are translated explicitly.
- Provider errors preserve status category (`symbol_not_found`, `rate_limited`,
  `api_key_error`) where possible.

## Gap

Date-range semantics depend on upstream plan and need dedicated integration
fixtures.
