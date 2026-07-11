# RS-001 — Technical indicators

**Status:** implemented

## Scope

Explorer-first SMA, EMA, WMA, HMA, DEMA, TEMA, KAMA, MACD and RSI indicators.

## Requirements

- Input validation names the missing/invalid column and period.
- Output column names are deterministic and configurable.
- Missing-data policy is explicit.
- Numerical behaviour is cross-validated against an independent reference.

## Acceptance criteria

- Python reference tests cover normal, short, constant and missing-data series.
- Indicators do not mutate the input DataFrame.
- Documentation states smoothing conventions, especially RSI/Wilder and EMA
  initialization.
