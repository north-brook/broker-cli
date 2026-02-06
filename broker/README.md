# broker

`broker` is a multi-package workspace for Interactive Brokers execution infrastructure.

## Workspace Layout

- `packages/daemon`: long-running runtime + shared protocol/models (`broker_daemon`)
- `packages/cli`: operator command-line interface (`broker`)
- `packages/sdk/python`: async Python SDK (`from broker_sdk import Client`)
- `packages/sdk/typescript`: strictly typed TypeScript SDK (`@northbrook/broker-sdk-typescript`)

## Operator CLI

The single CLI surface is `broker`. It talks to the daemon only (never directly to IB).

```bash
broker daemon start --paper
broker daemon status
broker quote AAPL MSFT
broker order buy AAPL 10 --limit 180
broker risk check --side buy --symbol AAPL --qty 100
```

## IB Gateway/TWS Requirement

`broker` does not include Interactive Brokers Gateway or TWS.

- You must run IB Gateway or TWS separately on the same machine (or reachable host).
- Authentication happens in Gateway/TWS using your IBKR login session (including 2FA as required).
- The TWS/Gateway socket API does not use API keys.
- Broker connects to that logged-in session over TCP:
  - IB Gateway paper/live: `4002` / `4001`
  - TWS paper/live: `7497` / `7496`

## Plain-English Architecture

- **IB Gateway / TWS**: The official Interactive Brokers app that logs into your brokerage account and keeps the authenticated trading session alive.
- **`broker-daemon`**: The always-on local backend that connects to Gateway/TWS, tracks state, enforces risk rules, and writes audit logs.
- **`broker` CLI**: The terminal command interface for humans. It sends commands to the daemon and formats results.
- **Python SDK (`broker_sdk`)**: Programmatic Python client for agents/services to call daemon commands and streams.
- **TypeScript SDK (`@northbrook/broker-sdk-typescript`)**: Programmatic Node/TypeScript client with strict typings for the same daemon API.

In short:

- Gateway/TWS = authenticated broker connection
- Daemon = state + safety + execution control
- CLI/SDKs = ways to control the daemon

### Ergonomic Defaults

- `-h` and `--help` are both supported on every command group
- command typo suggestions are surfaced for near matches
- enum-like options (`--tif`, `--status`, `--by`, etc.) are validated up front
- JSON mode is auto-enabled when stdout is non-TTY (or forced with `--json`)

## SDK Surfaces

- Python SDK: `broker_sdk.Client` plus exported constants/types for topics, risk params, TIF values, and filters
- TypeScript SDK: strict command/result typing + exported runtime constants (`AGENT_TOPICS`, `RISK_PARAMS`, etc.)

## Development Environment

Recommended local stack:

- Python: `pyenv` (global `3.12.x`)
- Virtualenv/deps: `uv`
- Auto-activation: `direnv`

There is no top-level `requirements.txt`; dependencies are defined in package `pyproject.toml` files.

Bootstrap from `broker/`:

```bash
uv venv --python 3.12 --seed
direnv allow
.venv/bin/python -m pip install -e './packages/daemon[dev]' -e './packages/sdk/python[dev]' -e './packages/cli[dev]'
```

## Documentation

- Setup and first run: `docs/quickstart.md`
- CLI usage patterns: `packages/cli/README.md`
- SDK integration patterns: `docs/agent-integration.md`
- Risk limits and runtime controls: `docs/risk-configuration.md`
- Hardening, recovery tests, load tests, and shell completion generation: `docs/hardening-testing.md`
