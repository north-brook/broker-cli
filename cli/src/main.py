"""Root Typer app and command registration."""

from __future__ import annotations

import typer

import audit
import daemon
import market
import orders
import portfolio
import risk
import schema_cmd
import update
from _common import CLIState, build_typer, load_config

app = build_typer(
    """Broker command-line interface for trading, portfolio, risk, and audit workflows.

    Examples:
      broker quote AAPL MSFT
      broker order buy AAPL 10 --limit 180
      broker check --side buy --symbol AAPL --qty 50
    """
)

app.add_typer(daemon.app, name="daemon")
app.add_typer(market.app)
app.add_typer(orders.order_app, name="order")
app.add_typer(portfolio.app)
app.add_typer(risk.app)
app.add_typer(audit.app, name="audit")

# Flat commands required by spec.
app.command("orders", help="List orders with optional filters.")(orders.orders)
app.command("cancel", help="Cancel one order, or all open orders with --all.")(orders.cancel)
app.command("fills", help="List fills/execution history.")(orders.fills)
app.command("update", help="Sync broker-cli source checkout to latest origin/main.")(update.update)
app.command("schema", help="Show machine-readable JSON schema for daemon command payloads.")(schema_cmd.schema)


@app.callback()
def root(
    ctx: typer.Context,
    strict: bool = typer.Option(
        False,
        "--strict/--no-strict",
        help="Enable strict mode for commands that can treat empty market payloads as errors.",
    ),
) -> None:
    cfg = load_config()
    ctx.obj = CLIState(config=cfg, json_output=True, strict=strict)


def run() -> None:
    app()
