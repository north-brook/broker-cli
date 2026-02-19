"""Portfolio and account commands."""

from __future__ import annotations

from enum import Enum

import typer

from _common import build_typer, daemon_request, get_state, handle_error, parse_csv_items, print_output, run_async
from broker_daemon.exceptions import BrokerError

app = build_typer("Portfolio and account commands.")


class ExposureBy(str, Enum):
    SECTOR = "sector"
    ASSET_CLASS = "asset_class"
    CURRENCY = "currency"
    SYMBOL = "symbol"


@app.command("positions", help="Show current positions.")
def positions(
    ctx: typer.Context,
    symbol: str | None = typer.Option(None, "--symbol", help="Optional symbol filter."),
) -> None:
    state = get_state(ctx)
    command = "portfolio.positions"
    params: dict[str, object] = {}
    if symbol:
        params["symbol"] = symbol

    try:
        result = run_async(daemon_request(state, command, params))
        print_output(
            result.data.get("positions", []),
            json_output=state.json_output,
            command=command,
            request_id=result.request_id,
            strict=state.strict,
        )
    except BrokerError as exc:
        handle_error(exc, json_output=state.json_output, command=command, strict=state.strict)


@app.command("pnl", help="Show PnL summary for today, a period, or since a date.")
def pnl(
    ctx: typer.Context,
    today: bool = typer.Option(False, "--today", help="Use today's PnL window."),
    period: str | None = typer.Option(None, "--period", help="Named period like 7d."),
    since: str | None = typer.Option(None, "--since", help="Start date (YYYY-MM-DD)."),
) -> None:
    state = get_state(ctx)
    command = "portfolio.pnl"
    selected = int(today) + int(period is not None) + int(since is not None)
    if selected > 1:
        raise typer.BadParameter("choose only one of --today, --period, or --since")

    params: dict[str, object] = {}
    if today:
        params["today"] = True
    if period:
        params["period"] = period
    if since:
        params["since"] = since
    if not params:
        params["today"] = True

    try:
        result = run_async(daemon_request(state, command, params))
        print_output(
            result.data.get("pnl", result.data),
            json_output=state.json_output,
            command=command,
            request_id=result.request_id,
            strict=state.strict,
        )
    except BrokerError as exc:
        handle_error(exc, json_output=state.json_output, command=command, strict=state.strict)


@app.command("balance", help="Show account balances and margin metrics.")
def balance(ctx: typer.Context) -> None:
    state = get_state(ctx)
    command = "portfolio.balance"
    try:
        result = run_async(daemon_request(state, command, {}))
        print_output(
            result.data.get("balance", result.data),
            json_output=state.json_output,
            command=command,
            request_id=result.request_id,
            strict=state.strict,
        )
    except BrokerError as exc:
        handle_error(exc, json_output=state.json_output, command=command, strict=state.strict)


@app.command("exposure", help="Show exposure grouped by symbol/sector/asset class/currency.")
def exposure(
    ctx: typer.Context,
    by: ExposureBy = typer.Option(
        ExposureBy.SYMBOL,
        "--by",
        case_sensitive=False,
        help="Group exposure by sector, asset_class, currency, or symbol.",
    ),
) -> None:
    state = get_state(ctx)
    command = "portfolio.exposure"
    try:
        result = run_async(daemon_request(state, command, {"by": by.value}))
        print_output(
            result.data.get("exposure", []),
            json_output=state.json_output,
            command=command,
            request_id=result.request_id,
            strict=state.strict,
        )
    except BrokerError as exc:
        handle_error(exc, json_output=state.json_output, command=command, strict=state.strict)


@app.command("snapshot", help="Fetch quote/portfolio/risk state in one request.")
def snapshot(
    ctx: typer.Context,
    symbols: str | None = typer.Option(
        None,
        "--symbols",
        help="Optional comma-separated symbols for quote snapshot (defaults to current position symbols).",
    ),
    exposure_by: ExposureBy = typer.Option(
        ExposureBy.SYMBOL,
        "--exposure-by",
        case_sensitive=False,
        help="Exposure grouping for snapshot response.",
    ),
) -> None:
    state = get_state(ctx)
    command = "portfolio.snapshot"
    params: dict[str, object] = {"exposure_by": exposure_by.value}
    if symbols:
        params["symbols"] = parse_csv_items(symbols, field_name="symbols")

    try:
        result = run_async(daemon_request(state, command, params))
        print_output(
            result.data,
            json_output=state.json_output,
            command=command,
            request_id=result.request_id,
            strict=state.strict,
        )
    except BrokerError as exc:
        handle_error(exc, json_output=state.json_output, command=command, strict=state.strict)
