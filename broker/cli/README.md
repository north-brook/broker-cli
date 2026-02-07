# cli

Single operator CLI for the broker stack.

## Entry Point

- Command: `broker`
- Transport: Unix socket RPC to `broker-daemon`
- Shared SDK transport: `broker-sdk-python`
- External dependency: IB Gateway or TWS must be running and logged in; the CLI/daemon do not authenticate to IBKR directly.

## Command Surface

- Market: `broker quote|watch|chain|history`
- Orders: `broker order buy|sell|bracket|status`, `broker orders`, `broker cancel`, `broker fills`
- Portfolio: `broker positions|pnl|balance|exposure`
- Risk: `broker check|limits|set|halt|resume|override`
- Agent: `broker agent heartbeat|subscribe`
- Audit: `broker audit orders|commands|risk|export`

## Ergonomics

- `-h` and `--help` are available on all groups and commands.
- Mistyped commands return close-match suggestions.
- Enum-style arguments are validated with clear error messages.
- Human output defaults to Rich tables; JSON is automatic for non-TTY stdout.

## Examples

```bash
nb start --paper
broker quote AAPL MSFT
broker order buy AAPL 5 --limit 180 --tif DAY
broker set max_order_value 25000
broker audit export --table orders --format csv --output trades.csv
```

## Common Error Paths

- `DAEMON_NOT_RUNNING`: start Northbrook with `nb` or check `nb status`.
- `IB_DISCONNECTED`: start/login IB Gateway or TWS and verify host/port/client id.
- `INVALID_ARGS`: run `broker --help` or `<command> --help`.
- `RISK_HALTED`: inspect limits/events, then run `broker resume` when appropriate.

## Shell Completion

Generate completion scripts for bash/zsh/fish:

```bash
bash scripts/generate-completions.sh
```

## Dev Workflow

From `broker/`:

```bash
uv venv --python 3.12 --seed
direnv allow
.venv/bin/python -m pip install -e './daemon[dev]' -e './sdk/python[dev]' -e './cli[dev]'
```
