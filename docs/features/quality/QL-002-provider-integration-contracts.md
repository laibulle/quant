---
id: QL-002
status: partial
domain: quality
owners: [test.integration]
depends_on: [QL-001, DF-010, DF-011, DF-012, DF-013, DF-014]
---

# QL-002 — Provider integration contracts

**Status:** partial

## Scope

Opt-in live checks plus deterministic recorded-response contracts.

## Requirements

- Live tests are tagged, use dedicated credentials and never run by default.
- Each provider has fixtures for success, empty data, malformed payload, 401,
  404, 429 and 5xx where applicable.
- Recorded payloads include capture date and provider API version/endpoint.
- CI runs fixture tests on every change and live smoke tests on a controlled
  schedule.
