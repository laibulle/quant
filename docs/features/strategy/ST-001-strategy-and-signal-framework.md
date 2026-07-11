---
id: ST-001
status: implemented
domain: strategy
owners: [Quant.Strategy]
depends_on: [RS-001, DF-002]
---

# ST-001 — Strategy and signal framework

**Status:** implemented

## Scope

Moving-average, momentum, volatility and composite strategies that add a
normalized `signal` column.

## Requirements

- Signal meaning is stable: `1` long entry, `-1` long exit/short signal, `0`
  neutral.
- Strategy validation declares required columns and minimum observations.
- Composite strategy conflict resolution is explicit and tested.

## Constraint

A signal is not an order. Execution timing is defined by ST-002.
