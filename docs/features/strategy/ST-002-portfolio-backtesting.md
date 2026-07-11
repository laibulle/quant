# ST-002 — Portfolio backtesting

**Status:** partial

## Current scope

Single-instrument, long-only simulation. Close-derived signals execute at the
next bar open by default; same-close execution is explicit opt-in.

## Target scope

- Multi-asset portfolio with independent positions, cash and exposure limits.
- Long and short positions, borrow costs and margin rules.
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
