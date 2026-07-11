# DF-011 — Alpha Vantage adapter

**Status:** partial

## Scope

Historical OHLCV, quotes and symbol search with an API key.

## Requirements

- Missing credentials return `{:error, :api_key_missing}`.
- A requested date range requests `full` output and is filtered locally.
- The public interval mapping is translated to Alpha Vantage names.

## Gaps

Provider limits make full-history retrieval and intraday coverage tier-dependent.
Live contract tests must run only with a dedicated key.
