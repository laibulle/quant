---
id: ST-002
status: partial
domain: strategy
owners: [Quant.Strategy.Backtest]
depends_on: [ST-001, DF-002, ST-003]
---

# ST-002 — Portfolio backtesting

**Status:** partial

## Current scope

- Multi-asset portfolio with a shared cash balance and independent positions.
- Long positions and opt-in short positions (`allow_short: true`).
- Deterministic per-symbol ordering by timestamp then symbol.
- Close-derived signals execute at the next bar open by default; same-close
  execution is explicit opt-in.
- Optional close-out on each symbol's last bar (`close_final_position: true`).
- Commission and slippage are applied to long and short fills.
- Intrabar stop-loss/take-profit exits use OHLC, with an explicit collision
  policy (`:stop_first` by default or `:take_profit_first`).

## Explicit current constraints

- `max_positions` limits concurrent open symbols; position sizing is evaluated
  sequentially against the available shared cash balance.
- Signals close an opposing position; they do not silently flip from long to
  short (or the reverse) in the same bar.
- Borrow costs, margin calls and limit/stop order lifecycles are not implemented
  yet.

## Target scope

- Exposure limits beyond `max_positions`.
- Borrow costs and margin rules for short positions.
- Market, limit and stop orders with lifecycle states.
- Intrabar stop-loss/take-profit policy using OHLC and deterministic collision
  rules.
- Optional close-out of open positions at the final bar.
- Corporate actions, delistings and FX conversion as explicit data inputs.

## Acceptance criteria

- Deterministic fixtures prove no look-ahead bias.
- A multi-symbol portfolio preserves per-symbol timestamp ordering.
- Every fill records requested order, fill price, fee, slippage and reason.
- Unsupported assumptions fail explicitly; they are never simulated silently.
