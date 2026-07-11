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
- Every market or conditional fill is exposed on the result row
  (`order_status`, `order_type`, `order_side`, `order_trigger_price`,
  `fill_price`, `fee`, `slippage_cost`, `order_reason`).
- Entry signals accept `:market`, `{:limit, price}` or `{:stop, price}`. Limit
  and stop entries remain pending until a later bar reaches their OHLC trigger.
- An opposing signal cancels an unfilled entry order deterministically.
- Signal exits accept `:market`, `{:limit, price}` or `{:stop, price}` and use
  the same deterministic pending-order lifecycle as entries.
- Conditional orders can be partially filled with
  `max_volume_participation: ratio`; every fill is capped at `ratio` of the
  current bar's reported volume. The option is deliberately inactive when no
  volume is available.
- Open shorts can incur a deterministic `short_borrow_rate_per_bar`; the cost
  is visible in `borrow_cost` and deducted before the current bar's signals.
- Maintenance margin is measured as portfolio equity divided by gross short
  exposure. A breach of `short_maintenance_margin` closes the affected short
  at the bar close with the `margin_liquidation` order reason.

## Explicit current constraints

- `max_positions` limits concurrent open symbols; position sizing is evaluated
  sequentially against the available shared cash balance.
- Signals close an opposing position; they do not silently flip from long to
  short (or the reverse) in the same bar.
- Initial-margin requirements, broker-specific collateral segregation and
  bankruptcy handling are not modelled yet.

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
