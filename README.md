# broker-cli

Give your AI agent a brokerage account.

Broker APIs exist. SDKs exist. But AI agents use the command line. **broker-cli** turns any brokerage into shell commands your agent already understands, with a `SKILL.md` that teaches it everything.

📖 **[brokercli.com](https://brokercli.com)** · 📚 **[Reference](https://brokercli.com/reference)**

## Install

```bash
curl -fsSL https://brokercli.com/install | bash
```

Or clone and install manually:

```bash
git clone https://github.com/north-brook/broker-cli && cd broker-cli && ./install.sh
```

Then finish provider setup from any directory:

```bash
broker setup
```

## Quick Start

```bash
broker setup                   # Choose provider + configure credentials
broker daemon start --paper   # Start in paper trading mode
broker daemon status           # Check connection
broker quote AAPL MSFT         # Get quotes
broker positions               # View portfolio
broker exposure --by symbol    # Exposure analysis
broker order buy AAPL 100 --limit 185   # Place an order
```

## Built for Agents

- **SKILL.md Included** — Ships with a skill file that Codex, Claude Code, and OpenClaw agents read automatically. Your agent knows every command, flag, and workflow without extra prompting.
- **CLI-First, Agent-Ready** — Every action is a shell command. Agents don't need SDKs, API keys, or custom integrations — just bash.
- **Autonomous Execution** — Persistent auth keeps sessions alive 24/7. No manual logins, no token expiry interruptions.
- **Multi-Broker** — Unified commands across E\*Trade and Interactive Brokers. One skill file, one interface.
- **Full Options Support** — Option chains with greeks, expiry filtering, and strike ranges.
- **Risk Guardrails** — Exposure analysis, cancel-all for instant flattening, paper trading mode. Power with built-in safety valves.

## Supported Brokers

| Feature | Interactive Brokers | E\*Trade |
|---|:---:|:---:|
| Real-time quotes | ✅ | ✅ |
| Option chains + greeks | ✅ | ✅ |
| All order types | ✅ | ✅ |
| Cancel all | ✅ | ✅ |
| Positions & P/L | ✅ | ✅ |
| Exposure analysis | ✅ | ✅ |
| Persistent auth | ✅ | ✅ |
| Streaming events | ✅ | — |
| Historical bars | ✅ | — |

## Commands

```
broker daemon start              Start the trading daemon
broker daemon start --paper      Paper trading mode
broker daemon status             Daemon status and connection info
broker daemon stop               Graceful shutdown
broker setup                     Choose provider and configure credentials
broker uninstall                 Remove broker-cli install/setup artifacts
broker quote SYMBOL...           Snapshot quotes
broker watch SYMBOL              Live quote stream
broker chain SYMBOL              Option chain with greeks
broker history SYMBOL            Historical bars
broker order buy SYMBOL QTY      Buy order (market/limit/stop)
broker order sell SYMBOL QTY     Sell order
broker order bracket SYMBOL QTY  Bracket order (entry + TP + SL)
broker order status ORDER_ID     Order status
broker orders                    List orders
broker cancel ORDER_ID           Cancel an order
broker cancel --all              Cancel all open orders
broker fills                     Execution history
broker positions                 Current positions
broker pnl                       P&L summary
broker balance                   Account balances and margin
broker exposure --by symbol      Exposure breakdown
broker risk check                Pre-trade risk validation
broker risk limits               Current risk limits
broker risk set PARAM VALUE      Update a risk limit
broker risk halt                 Emergency halt
broker risk resume               Resume after halt
broker audit orders              Order audit trail
broker audit commands            Command audit trail
```

## E\*Trade Setup

```bash
broker setup
```

### Persistent Auth (Headless)

Keep E\*Trade authenticated across the daily midnight token expiry:

```json
{
  "broker": {
    "provider": "etrade",
    "etrade": {
      "consumer_key": "...",
      "consumer_secret": "...",
      "username": "your_username",
      "password": "your_password",
      "persistent_auth": true
    }
  }
}
```

Or via environment variables:

```bash
export BROKER_ETRADE_USERNAME=your_username
export BROKER_ETRADE_PASSWORD=your_password
export BROKER_ETRADE_PERSISTENT_AUTH=true
```

Requires Playwright: `pip install playwright && playwright install chromium`

> Accounts with 2FA/MFA enabled cannot use persistent auth. Run `broker setup` to complete manual OAuth when needed.

## Uninstall

```bash
broker uninstall
```

Use `broker uninstall --yes` for non-interactive cleanup.

## Configuration

| Path | Description |
|---|---|
| `~/.config/broker/config.json` | Config file |
| `~/.config/broker/etrade_tokens.json` | E\*Trade tokens |
| `~/.local/state/broker/broker.sock` | Daemon socket |
| `~/.local/state/broker/broker.log` | Daemon log |
| `~/.local/share/broker/` | Audit data |

## Repository Layout

```
cli/           CLI package
daemon/        Daemon package
sdk/python/    Python SDK
sdk/typescript/ TypeScript SDK
install/       Installer and bootstrap
website/       Marketing site (brokercli.com)
```

## Development

```bash
bun install    # Install hooks
bun run ci:all # Lint + typecheck + test
```
