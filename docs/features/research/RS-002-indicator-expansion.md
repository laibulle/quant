# RS-002 — Indicator expansion

**Status:** planned

## Scope

Trend (ADX, Parabolic SAR), volatility (ATR, Bollinger Bands), and volume
(OBV, VWAP, MFI) indicators.

## Requirements

- Follow the RS-001 validation, naming and reference-test contract.
- Define warm-up, missing-data and zero-volume behaviour before implementation.
- Document asset-class assumptions; VWAP and volume indicators are not valid for
all provider data.
