# DF-002 — Data contract and integrity

**Status:** partial  
**Owner module:** `Quant.Explorer.SchemaStandardizer`

## Goal

Define the semantic contract for bars, quotes and searches independently of the
upstream API format.

## Requirements

- A bar timestamp denotes the bar open in UTC; provider timezone is metadata.
- `nil` remains missing data. It must not become `0`, `DateTime.utc_now/0`, or a
  rounded substitute.
- Prices retain provider precision; no global decimal rounding is applied.
- `volume` is base-asset volume where known. Quote volume is separately named.
- All history returned to strategies is sorted ascending by timestamp per symbol.

## Acceptance criteria

- Property tests reject malformed timestamps and inverted ranges.
- Fixtures cover nulls, duplicate timestamps, DST boundaries and mixed symbols.
- Every standard column has type, unit and nullability documented.

## Open decisions

Whether `adj_close` should remain nullable or fall back to `close` is provider-
and asset-class-specific and must be declared per adapter.
