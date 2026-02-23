---
name: broker-cli
description: Complete reference for the broker CLI. Use when translating trading intentions into exact `broker` commands. Covers all commands, flags, defaults, workflows, and error handling.
---

# Broker CLI

`broker` is a CLI that provides programmatic access to a brokerage account (Interactive Brokers or E*Trade). The daemon is already running — use the commands below to trade.

## Output Format

Every command returns JSON with this envelope:

```json
{"ok": true, "data": {...}, "error": null, "meta": {"schema_version": "v1", "command": "...", "request_id": "...", "timestamp": "..."}}
```

On error, `ok` is `false`, `data` is `null`, and `error` contains:

```json
{"code": "ERROR_CODE", "message": "...", "details": {...}, "suggestion": "..."}
```

The `suggestion` field, when present, tells you what to do next. The `request_id` in `meta` can be used to correlate commands in the audit log.

## Order Types

The order type is determined by which price flags you provide:

| Flags | Order type |
|---|---|
| _(none)_ | market |
| `--limit` | limit |
| `--stop` | stop |
| `--limit` + `--stop` | stop-limit |
| `broker order bracket` | bracket (entry + take-profit + stop-loss) |

## Decision Flags (Required)

Every order submission (`buy`, `sell`, `bracket`) requires three decision flags. Orders without them are rejected.

- `--decision-name "Title Case Name"` — title-case, single-line, plain text
- `--decision-summary "Single line summary"` — single-line, plain text
- `--decision-reasoning "## Markdown reasoning"` — long-form markdown thesis

These are stored in the fund observability repo as decision records. Write substantive reasoning — it becomes the audit trail for every trade.

## Risk Limit Defaults

These are the default risk limits. Query live values with `broker limits`.

| Parameter | Default | Description |
|---|---|---|
| `max_position_pct` | 10.0 | Max % of NLV in one position |
| `max_order_value` | 50000 | Max dollar value per order |
| `max_daily_loss_pct` | 2.0 | Max daily loss as % of NLV |
| `max_sector_exposure_pct` | 30.0 | Max % exposure to one sector |
| `max_single_name_pct` | 10.0 | Max % of NLV in a single name |
| `max_open_orders` | 20 | Max simultaneous open orders |
| `order_rate_limit` | 10 | Max orders per minute |
| `duplicate_window_seconds` | 60 | Window for duplicate order detection |
| `symbol_allowlist` | _(empty = all allowed)_ | Only these symbols are tradeable |
| `symbol_blocklist` | _(empty = none blocked)_ | These symbols are blocked |

## Workflows

### Research a trade

```bash
broker quote AAPL
broker history AAPL --period 30d --bar 1d
broker chain AAPL --expiry 2026-03 --type call
broker snapshot --symbols AAPL
broker check --side buy --symbol AAPL --qty 50 --limit 180
```

### Dry-run then place an order

```bash
# Test against risk limits without submitting
broker order buy AAPL 50 --limit 180 --dry-run \
  --decision-name "AAPL Accumulation" \
  --decision-summary "Adding to AAPL on pullback to 180 support" \
  --decision-reasoning "## Thesis\nAAPL pulled back to 180 support with RSI oversold."

# If ok=true, submit for real (same command without --dry-run)
broker order buy AAPL 50 --limit 180 \
  --decision-name "AAPL Accumulation" \
  --decision-summary "Adding to AAPL on pullback to 180 support" \
  --decision-reasoning "## Thesis\nAAPL pulled back to 180 support with RSI oversold."
```

### Safe retry with idempotency

```bash
broker order buy AAPL 50 --limit 180 --idempotency-key "aapl-buy-20260222" \
  --decision-name "AAPL Accumulation" \
  --decision-summary "Adding to AAPL on pullback to 180 support" \
  --decision-reasoning "## Thesis\nAAPL pulled back to 180 support with RSI oversold."
# Safe to retry — daemon deduplicates by idempotency key within the duplicate window.
```

### Verify an order

```bash
broker order status <CLIENT_ORDER_ID>   # check status
broker fills --symbol AAPL              # confirm execution
```

### Monitor portfolio

```bash
broker snapshot                         # positions + balance + exposure in one call
broker positions
broker balance
broker exposure --by sector
broker pnl --today
```

### Risk management

```bash
broker limits                           # view current limits
broker set max_order_value 25000        # tighten a limit
broker override --param max_order_value --value 75000 --duration 1h --reason "large block trade"
broker halt                             # emergency: cancel all + reject new orders
broker resume                           # re-enable trading after halt
```

---

## Command Reference

### Market Data

#### `broker quote`

Snapshot quotes for one or more symbols.

```bash
broker quote SYMBOL [SYMBOL...] [--intent best_effort|top_of_book|last_only]
```

- `--intent`: Quote intent. Default: `best_effort`.
  - `best_effort` — returns whatever data is available (delayed fallback if live unavailable)
  - `top_of_book` — requires bid+ask; warns if incomplete
  - `last_only` — only last trade price

#### `broker watch`

Continuously refresh quote fields until interrupted (Ctrl+C).

```bash
broker watch SYMBOL [--fields CSV] [--interval DURATION] [--intent best_effort|top_of_book|last_only]
```

- `--fields`: default `bid,ask,last,volume`. Allowed: `symbol`, `bid`, `ask`, `last`, `volume`, `timestamp`, `exchange`, `currency`
- `--interval`: default `1s`. Examples: `250ms`, `1s`, `2m`

#### `broker chain`

Fetch option chain for a symbol.

```bash
broker chain SYMBOL [--expiry YYYY-MM] [--strike-range LOW:HIGH] [--type call|put] \
  [--limit N] [--offset N] [--fields CSV] [--strict/--no-strict]
```

- `--strike-range`: default `0.9:1.1` (near the money)
- `--limit`: max entries to return. Default: `200`
- `--offset`: offset into filtered results. Default: `0`
- `--fields`: comma-separated. Allowed: `symbol`, `right`, `strike`, `expiry`, `bid`, `ask`, `implied_vol`, `delta`, `gamma`, `theta`, `vega`
- `--strict/--no-strict`: treat empty chain results as errors

#### `broker history`

Fetch historical bars.

```bash
broker history SYMBOL --period PERIOD --bar BAR [--rth-only] [--strict/--no-strict]
```

- `--period` (required): `1d`, `5d`, `30d`, `90d`, `1y`
- `--bar` (required): `1m`, `5m`, `15m`, `1h`, `1d`
- `--rth-only`: restrict to regular trading hours
- `--strict/--no-strict`: treat empty history as error

#### `broker capabilities`

Query what market data types the connected provider supports.

```bash
broker capabilities [SYMBOL...] [--refresh]
```

- Without symbols: uses daemon probe list (default: `AAPL`)
- `--refresh`: force fresh probe via provider API

---

### Orders

#### `broker order buy`

Place a buy order. Market by default unless `--limit` and/or `--stop` is set.

```bash
broker order buy SYMBOL QTY [--limit PRICE] [--stop PRICE] [--tif DAY|GTC|IOC] \
  [--dry-run] [--idempotency-key KEY] \
  --decision-name "Title" --decision-summary "Summary" --decision-reasoning "Reasoning"
```

- `QTY`: must be > 0 (supports fractional)
- `--tif`: default `DAY`
- `--dry-run`: evaluate against risk only, do not submit
- `--idempotency-key`: stable key for safe retries (maps to `client_order_id`)
- Decision flags are **required** for submitted orders (not required for `--dry-run`)

#### `broker order sell`

Place a sell order. Same flags as `buy`.

```bash
broker order sell SYMBOL QTY [--limit PRICE] [--stop PRICE] [--tif DAY|GTC|IOC] \
  [--dry-run] [--idempotency-key KEY] \
  --decision-name "Title" --decision-summary "Summary" --decision-reasoning "Reasoning"
```

#### `broker order bracket`

Place a bracket order (entry + take-profit + stop-loss). Interactive Brokers only.

```bash
broker order bracket SYMBOL QTY --entry PRICE --tp PRICE --sl PRICE \
  [--side buy|sell] [--tif DAY|GTC|IOC] \
  --decision-name "Title" --decision-summary "Summary" --decision-reasoning "Reasoning"
```

- `--entry`, `--tp`, `--sl`: all required
- `--side`: default `buy`
- `--tif`: default `DAY`

#### `broker order status`

Show status for one order.

```bash
broker order status ORDER_ID
```

#### `broker orders`

List orders.

```bash
broker orders [--status active|filled|cancelled|all] [--since YYYY-MM-DD]
```

- `--status`: default `all`

#### `broker cancel`

Cancel one order or all open orders.

```bash
broker cancel ORDER_ID
broker cancel --all [--confirm]
```

- Do not pass `ORDER_ID` with `--all`.
- `--confirm` may be required for `--all`.

#### `broker fills`

List fills / execution history.

```bash
broker fills [--since YYYY-MM-DD] [--symbol SYMBOL]
```

---

### Portfolio

#### `broker snapshot`

Fetch positions, balance, and exposure in one request.

```bash
broker snapshot [--symbols COMMA_SEPARATED] [--exposure-by symbol|sector|asset_class|currency]
```

- `--symbols`: comma-separated symbols for quote snapshot. Defaults to current position symbols.
- `--exposure-by`: default `symbol`

#### `broker positions`

```bash
broker positions [--symbol SYMBOL]
```

#### `broker pnl`

```bash
broker pnl [--today | --period 7d | --since YYYY-MM-DD]
```

- Choose only one. Defaults to `--today`.

#### `broker balance`

```bash
broker balance
```

#### `broker exposure`

```bash
broker exposure [--by symbol|sector|asset_class|currency]
```

- Default `--by`: `symbol`

---

### Risk

#### `broker check`

Dry-run an order against risk limits (no submission).

```bash
broker check --side buy|sell --symbol SYMBOL --qty QTY [--limit PRICE] [--stop PRICE] [--tif DAY|GTC|IOC]
```

- `--side`, `--symbol`, `--qty` are required
- `--tif`: default `DAY`

#### `broker limits`

Show current runtime risk limits.

```bash
broker limits
```

#### `broker set`

Set a risk parameter at runtime.

```bash
broker set PARAM VALUE
```

Valid params: `max_position_pct`, `max_order_value`, `max_daily_loss_pct`, `max_sector_exposure_pct`, `max_single_name_pct`, `max_open_orders`, `order_rate_limit`, `duplicate_window_seconds`, `symbol_allowlist`, `symbol_blocklist`

#### `broker halt`

Emergency halt — cancels all open orders and rejects new orders.

```bash
broker halt
```

#### `broker resume`

Resume trading after halt.

```bash
broker resume
```

#### `broker override`

Temporary risk override with required reason and duration.

```bash
broker override --param PARAM --value VALUE --duration DURATION --reason TEXT
```

- All flags required.
- `--duration`: `30m`, `1h`, `1d` (or raw seconds)

---

### Audit

#### `broker audit orders`

```bash
broker audit orders [--since YYYY-MM-DD] [--status active|filled|cancelled|all]
```

#### `broker audit commands`

```bash
broker audit commands [--source cli|sdk|ts_sdk] [--since YYYY-MM-DD] [--request-id ID]
```

#### `broker audit risk`

```bash
broker audit risk [--type EVENT_TYPE]
```

#### `broker audit export`

```bash
broker audit export --output PATH [--format csv] [--table orders|commands|risk] \
  [--since YYYY-MM-DD] [--status STATUS] [--source SOURCE] [--request-id ID] [--type EVENT_TYPE]
```

- `--output`: required
- `--format`: `csv` only
- `--table`: default `orders`

---

### Utility

#### `broker schema`

Query daemon command schemas. Useful for discovering parameter types and valid values.

```bash
broker schema [COMMAND]
```

- Without argument: list all commands
- With argument (e.g. `quote.snapshot`): return schema for that command

---

## Error Handling

| Error Code | Exit | What to do |
|---|---|---|
| `DAEMON_NOT_RUNNING` | 3 | Run `broker daemon start` |
| `IB_DISCONNECTED` | 4 | Verify IB Gateway/TWS is running, wait and retry |
| `IB_REJECTED` | 1 | Check order params (symbol, qty, price) |
| `RISK_CHECK_FAILED` | 5 | Check `broker limits`, adjust order size/price or use `broker override` |
| `RISK_HALTED` | 6 | Trading is halted — review situation, then `broker resume` |
| `RATE_LIMITED` | 1 | Wait and retry (default: 10 orders/min) |
| `DUPLICATE_ORDER` | 1 | Identical order within duplicate window — wait or use different `--idempotency-key` |
| `INVALID_SYMBOL` | 1 | Check symbol with `broker quote` |
| `INVALID_ARGS` | 2 | Check command syntax with `-h` |
| `TIMEOUT` | 10 | Retry the command |
| `INTERNAL_ERROR` | 1 | Retry; if persistent, check `broker daemon status` |

## Fund Observability

When configured, decisions and fills auto-sync to a git-backed fund repo. The `--decision-name`, `--decision-summary`, and `--decision-reasoning` flags on orders become markdown files in the repo's `decisions/` directory. Fills append to `fills.json`. This happens automatically — no manual management needed.
