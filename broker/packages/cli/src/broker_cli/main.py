"""Root Typer app and command registration."""

from __future__ import annotations

from pathlib import Path

import typer

from broker_cli import agent, audit, daemon, market, orders, portfolio, risk
from broker_cli._common import CLIState, build_typer, load_config, resolve_json_mode

app = build_typer(
    """Broker command-line interface for daemon control, trading, portfolio, risk, and audit workflows.

    Examples:
      broker daemon start --paper
      broker quote AAPL MSFT
      broker order buy AAPL 10 --limit 180
      broker risk check --side buy --symbol AAPL --qty 50
    """
)

app.add_typer(daemon.app, name="daemon")
app.add_typer(market.app)
app.add_typer(orders.order_app, name="order")
app.add_typer(portfolio.app)
app.add_typer(risk.app)
app.add_typer(agent.app, name="agent")
app.add_typer(audit.app, name="audit")

# Flat commands required by spec.
app.command("orders", help="List orders with optional filters.")(orders.orders)
app.command("cancel", help="Cancel one order, or all open orders with --all.")(orders.cancel)
app.command("fills", help="List fills/execution history.")(orders.fills)


@app.callback()
def root(
    ctx: typer.Context,
    json_output: bool = typer.Option(
        False,
        "--json",
        help="Emit machine-readable JSON only.",
    ),
    config: str | None = typer.Option(
        None,
        "--config",
        help="Path to config.toml (default: ~/.broker/config.toml).",
    ),
) -> None:
    config_path = None if config is None else Path(config)
    cfg = load_config(config_path)
    ctx.obj = CLIState(config=cfg, json_output=resolve_json_mode(json_output, cfg), config_path=config_path)


def run() -> None:
    app()
