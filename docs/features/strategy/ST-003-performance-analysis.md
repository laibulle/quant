---
id: ST-003
status: implemented
domain: strategy
owners: [Quant.Strategy.Performance]
depends_on: [ST-002]
---

# ST-003 — Performance analysis

**Status:** implemented

## Scope

Total and annualised returns, volatility, Sharpe, Sortino, drawdown, win rate
and profit factor from backtest output.

## Requirements

- `periods_per_year` and risk-free rate are caller-configurable.
- Undefined ratios return `nil`, never infinity.
- Trade metrics exclude non-trade zero rows.
- Metrics document whether they are gross or net of costs.

## Planned extension

Benchmark-relative metrics, recovery duration, exposure, turnover and per-asset
attribution after ST-002 multi-asset support.
