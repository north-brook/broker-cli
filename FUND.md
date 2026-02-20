# Fund Repository Format

This document defines the exact on-disk shape of a broker-cli fund observability repository.

The broker setup flow can create this repository automatically, and broker-daemon keeps it updated during trading.

## Directory Layout

```text
<fund-dir>/
  config.json
  fills.json
  cash_events.json
  decisions/
    <timestamp>.md
```

Notes:
- `<fund-dir>` is configured in broker config at `broker.observability.fund_dir`.
- Decision filenames are timestamp IDs (for example: `20260220T153012123456Z.md`).

## `config.json`

Fund metadata and initialization parameters.

Example:

```json
{
  "name": "Atlas Fund",
  "slug": "atlas",
  "inception": "2026-02-20T15:12:30Z",
  "currency": "USD",
  "initialCapital": 100000.0,
  "benchmarks": [],
  "cashInterestPolicy": {
    "enabled": true,
    "source": "inferred_from_broker_cash_balance"
  }
}
```

Fields:
- `name: string`
- `slug: string`
- `inception: string` (ISO-8601 timestamp)
- `currency: "USD"`
- `initialCapital: number`
- `benchmarks: string[]`
- `cashInterestPolicy.enabled: boolean`
- `cashInterestPolicy.source: string`

## `fills.json`

Append-only array of executed fills.

Example entry:

```json
{
  "id": "fill-001",
  "symbol": "NVDA",
  "side": "buy",
  "qty": 50,
  "price": 480.25,
  "commission": 1.0,
  "timestamp": "2026-02-20T15:16:07.184321+00:00",
  "decisionId": "20260220T151530112233Z"
}
```

Fields:
- `id: string` (unique fill identifier, dedup key)
- `symbol: string`
- `side: "buy" | "sell"`
- `qty: number`
- `price: number`
- `commission: number`
- `timestamp: string` (ISO-8601 timestamp)
- `decisionId: string | null`

## `cash_events.json`

Append-only array of cash adjustments not represented by trade notional directly.

Current event type:
- `interest` (cash interest inferred from broker cash balance reconciliation)

Example entry:

```json
{
  "id": "interest-20260220T160001987654Z",
  "type": "interest",
  "amount": 3.42,
  "timestamp": "2026-02-20T16:00:01.987654+00:00",
  "source": "inferred_from_broker_cash_balance"
}
```

Fields:
- `id: string`
- `type: string` (currently `"interest"`)
- `amount: number` (positive or negative)
- `timestamp: string` (ISO-8601 timestamp)
- `source: string`

## `decisions/<timestamp>.md`

Markdown decision files with YAML frontmatter.

Example:

```markdown
---
date: 2026-02-20
type: buy
tickers: [NVDA]
title: "Initiate NVDA Position"
summary: "Started a core position after earnings revision."
---

## Thesis

Long-form markdown reasoning content...
```

Frontmatter fields:
- `date: string` (ISO date)
- `type: "buy" | "sell"`
- `tickers: string[]`
- `title: string`
- `summary: string`

Body:
- Free-form markdown reasoning (from `--decision-reasoning`).

## Sync Behavior

When observability sync is enabled:
- Decision files are written when orders are placed.
- Fills are appended on executions.
- Cash interest events are appended when inferred deltas are detected.
- Changes are committed and pushed to `origin` automatically.

Git behavior assumptions:
- `<fund-dir>` is a git repository.
- `origin` remote exists and is pushable from the runtime environment.
