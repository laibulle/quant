---
id: DF-012
status: partial
domain: data
owners: [Quant.Explorer.Providers.Binance]
depends_on: [DF-001, DF-002, PF-001, PF-002]
---

# DF-012 — Binance adapter

**Status:** partial

## Scope

Spot klines, 24-hour tickers, exchange-info search and trading-pair discovery.

## Requirements

- Standard dates map to Binance millisecond `startTime` and `endTime`.
- Endpoint weights are supplied to the rate limiter.
- Kline history returns UTC bar-open timestamps and original values.

## Planned extension

[DF-020](DF-020-binance-paginated-history.md) defines retrieval of ranges over
the 1,000-kline upstream limit.
