---
id: PF-001
status: implemented
domain: platform
owners: [Quant.Explorer.HttpClient]
depends_on: []
---

# PF-001 — Secure HTTP client

**Status:** implemented

## Requirements

- TLS peer and hostname verification is mandatory.
- Query values are URL encoded and nil values omitted.
- Transport errors use bounded retry with backoff; non-idempotent requests are
  not retried unless explicitly allowed.
- Responses retain status, headers and body for adapter-level classification.

## Acceptance criteria

- Tests reject an invalid certificate configuration.
- Retry tests cover timeout, transient transport error, 429 and 5xx policy.
- No URL, log line or telemetry event contains an API key.
