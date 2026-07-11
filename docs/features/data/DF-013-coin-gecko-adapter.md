---
id: DF-013
status: partial
domain: data
owners: [Quant.Explorer.Providers.CoinGecko]
depends_on: [DF-001, DF-002, PF-001, PF-002]
---

# DF-013 — CoinGecko adapter

**Status:** partial

## Scope

Coin market-chart history, current prices, search, information and rankings.

## Requirements

- `currency` maps to CoinGecko `vs_currency`/`vs_currencies`.
- Market-chart pseudo-OHLC bars are labelled as derived data in documentation.
- API key selection uses runtime configuration without leaking keys.

## Constraint

Market-chart values are not exchange candles and must not be treated as
executable OHLC data by a trading simulator.
