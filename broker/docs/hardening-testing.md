# Hardening and Testing

This guide covers reliability testing, stress testing, and shell completion generation for `broker`.

## 1) Test Matrix

Recommended test passes:

```bash
# from broker/
.venv/bin/python -m pytest packages/daemon/tests packages/cli/tests packages/sdk/python/tests -q -rs

# ts sdk typing
cd packages/sdk/typescript && npm run typecheck
```

If your environment is missing dependencies, bootstrap from `docs/quickstart.md` first.

Current expected skip:

- `packages/daemon/tests/test_integration/test_paper_placeholder.py`
  reason: local IB paper gateway integration test placeholder.

## 2) Error Handling Coverage

Hardening additions include:

- Request validation errors mapped to `INVALID_ARGS` instead of generic internal errors
- Daemon command typo suggestions and richer invalid-argument details
- Risk engine code specificity for:
  - `RATE_LIMITED`
  - `DUPLICATE_ORDER`
- Connection-layer error mapping with actionable suggestions for:
  - `IB_DISCONNECTED`
  - `INVALID_SYMBOL`
  - `TIMEOUT`
  - `IB_REJECTED`

## 3) Connection Loss / Recovery Testing

New daemon tests cover:

- Listener registration across reconnect cycles
- Disconnection state reset and reconnect scheduling
- Dispatch validation for malformed requests

Key files:

- `packages/daemon/tests/test_daemon/test_connection_manager.py`
- `packages/daemon/tests/test_daemon/test_dispatch_validation.py`

## 4) Load Testing (Rapid Order Submission)

Two layers are provided:

### Unit stress tests

- `packages/daemon/tests/test_daemon/test_load_order_manager.py`
- Exercises burst submissions and rate-limit behavior in-process.

### Runtime load harness

Script:

- `scripts/load_test_orders.py`

Example (safe mode: risk checks only):

```bash
python scripts/load_test_orders.py --mode risk-check --count 500 --concurrency 50
```

Example (real order submit path; use paper account):

```bash
python scripts/load_test_orders.py --mode order --count 100 --concurrency 20 --symbol AAPL --limit 100
```

JSON output for automation:

```bash
python scripts/load_test_orders.py --json
```

## 5) Shell Completions (bash, zsh, fish)

Generate static completion scripts:

```bash
bash scripts/generate-completions.sh
```

Output defaults to `completions/` under the `broker` workspace:

- `completions/broker.bash`
- `completions/broker.zsh`
- `completions/broker.fish`

Override output directory:

```bash
bash scripts/generate-completions.sh /tmp/broker-completions
```

If `broker` is not on your `PATH`, set:

```bash
BROKER_BIN=/path/to/broker bash scripts/generate-completions.sh
```
