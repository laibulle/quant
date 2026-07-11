# ST-004 — Parameter optimisation

**Status:** implemented

## Scope

Grid, parallel, streaming and walk-forward optimisation; results ranking,
sensitivity and export.

## Requirements

- Each run records strategy, parameters, costs, data window and metric version.
- Parallel results equal serial results for identical inputs.
- Walk-forward splits have no overlap between train and evaluation data.
- Optimisation results warn when the underlying backtest assumptions are
single-instrument/long-only.
