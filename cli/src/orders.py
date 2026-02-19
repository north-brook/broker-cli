"""Order entry and execution-history commands."""

from __future__ import annotations

from enum import Enum

import typer

from _common import build_typer, daemon_request, get_state, handle_error, print_output, run_async
from broker_daemon.exceptions import BrokerError
from broker_daemon.models.orders import Side, TIF

order_app = build_typer("Order entry and lifecycle commands.")


class OrderListStatus(str, Enum):
    ACTIVE = "active"
    FILLED = "filled"
    CANCELLED = "cancelled"
    ALL = "all"


@order_app.command("buy", help="Place a buy order (market by default, unless --limit/--stop is set).")
def buy(
    ctx: typer.Context,
    symbol: str = typer.Argument(..., help="Ticker symbol."),
    qty: float = typer.Argument(..., min=0.000001, help="Order quantity (> 0)."),
    limit: float | None = typer.Option(None, "--limit", help="Limit price."),
    stop: float | None = typer.Option(None, "--stop", help="Stop trigger price."),
    tif: TIF = typer.Option(TIF.DAY, "--tif", case_sensitive=False, help="Time in force: DAY, GTC, IOC."),
    dry_run: bool = typer.Option(False, "--dry-run", help="Evaluate order only; do not submit."),
    idempotency_key: str | None = typer.Option(
        None,
        "--idempotency-key",
        help="Stable key for safe retries (maps to client_order_id).",
    ),
) -> None:
    _place(
        ctx,
        Side.BUY.value,
        symbol,
        qty,
        limit=limit,
        stop=stop,
        tif=tif,
        dry_run=dry_run,
        idempotency_key=idempotency_key,
    )


@order_app.command("sell", help="Place a sell order (market by default, unless --limit/--stop is set).")
def sell(
    ctx: typer.Context,
    symbol: str = typer.Argument(..., help="Ticker symbol."),
    qty: float = typer.Argument(..., min=0.000001, help="Order quantity (> 0)."),
    limit: float | None = typer.Option(None, "--limit", help="Limit price."),
    stop: float | None = typer.Option(None, "--stop", help="Stop trigger price."),
    tif: TIF = typer.Option(TIF.DAY, "--tif", case_sensitive=False, help="Time in force: DAY, GTC, IOC."),
    dry_run: bool = typer.Option(False, "--dry-run", help="Evaluate order only; do not submit."),
    idempotency_key: str | None = typer.Option(
        None,
        "--idempotency-key",
        help="Stable key for safe retries (maps to client_order_id).",
    ),
) -> None:
    _place(
        ctx,
        Side.SELL.value,
        symbol,
        qty,
        limit=limit,
        stop=stop,
        tif=tif,
        dry_run=dry_run,
        idempotency_key=idempotency_key,
    )


@order_app.command("bracket", help="Place a bracket order (entry + take profit + stop loss).")
def bracket(
    ctx: typer.Context,
    symbol: str = typer.Argument(..., help="Ticker symbol."),
    qty: float = typer.Argument(..., min=0.000001, help="Order quantity (> 0)."),
    entry: float = typer.Option(..., "--entry", help="Entry limit price."),
    tp: float = typer.Option(..., "--tp", help="Take-profit price."),
    sl: float = typer.Option(..., "--sl", help="Stop-loss price."),
    side: Side = typer.Option(Side.BUY, "--side", case_sensitive=False, help="buy or sell."),
    tif: TIF = typer.Option(TIF.DAY, "--tif", case_sensitive=False, help="DAY, GTC, IOC."),
) -> None:
    state = get_state(ctx)
    command = "order.bracket"
    try:
        result = run_async(
            daemon_request(
                state,
                command,
                {
                    "symbol": symbol,
                    "qty": qty,
                    "entry": entry,
                    "tp": tp,
                    "sl": sl,
                    "side": side.value,
                    "tif": tif.value,
                },
            )
        )
        print_output(
            result.data,
            json_output=state.json_output,
            command=command,
            request_id=result.request_id,
            strict=state.strict,
        )
    except BrokerError as exc:
        handle_error(exc, json_output=state.json_output, command=command, strict=state.strict)


@order_app.command("status", help="Show status for a single client order id.")
def status(
    ctx: typer.Context,
    order_id: str = typer.Argument(..., help="Client order ID."),
) -> None:
    state = get_state(ctx)
    command = "order.status"
    try:
        result = run_async(daemon_request(state, command, {"order_id": order_id}))
        print_output(
            result.data.get("order", result.data),
            json_output=state.json_output,
            command=command,
            request_id=result.request_id,
            strict=state.strict,
        )
    except BrokerError as exc:
        handle_error(exc, json_output=state.json_output, command=command, strict=state.strict)


def orders(
    ctx: typer.Context,
    status: OrderListStatus = typer.Option(
        OrderListStatus.ALL,
        "--status",
        case_sensitive=False,
        help="Order status filter.",
    ),
    since: str | None = typer.Option(None, "--since", help="YYYY-MM-DD"),
) -> None:
    state = get_state(ctx)
    command = "orders.list"
    params: dict[str, object] = {"status": status.value}
    if since:
        params["since"] = since

    try:
        result = run_async(daemon_request(state, command, params))
        print_output(
            result.data.get("orders", []),
            json_output=state.json_output,
            command=command,
            request_id=result.request_id,
            strict=state.strict,
        )
    except BrokerError as exc:
        handle_error(exc, json_output=state.json_output, command=command, strict=state.strict)


def cancel(
    ctx: typer.Context,
    order_id: str | None = typer.Argument(None, help="Client order ID."),
    all_orders: bool = typer.Option(False, "--all", help="Cancel all open orders"),
    confirm: bool = typer.Option(False, "--confirm", help="Required for --all in human mode"),
) -> None:
    state = get_state(ctx)
    command = "orders.cancel_all" if all_orders else "order.cancel"

    try:
        if all_orders and order_id:
            raise typer.BadParameter("do not provide ORDER_ID when using --all")
        if all_orders:
            result = run_async(
                daemon_request(
                    state,
                    command,
                    {"confirm": confirm, "json_mode": state.json_output},
                )
            )
        else:
            if not order_id:
                raise typer.BadParameter("ORDER_ID is required unless --all is specified")
            result = run_async(daemon_request(state, command, {"order_id": order_id}))

        print_output(
            result.data,
            json_output=state.json_output,
            command=command,
            request_id=result.request_id,
            strict=state.strict,
        )
    except BrokerError as exc:
        handle_error(exc, json_output=state.json_output, command=command, strict=state.strict)


def fills(
    ctx: typer.Context,
    since: str | None = typer.Option(None, "--since", help="YYYY-MM-DD"),
    symbol: str | None = typer.Option(None, "--symbol", help="Filter fills by symbol."),
) -> None:
    state = get_state(ctx)
    command = "fills.list"
    params: dict[str, object] = {}
    if since:
        params["since"] = since
    if symbol:
        params["symbol"] = symbol

    try:
        result = run_async(daemon_request(state, command, params))
        print_output(
            result.data.get("fills", []),
            json_output=state.json_output,
            command=command,
            request_id=result.request_id,
            strict=state.strict,
        )
    except BrokerError as exc:
        handle_error(exc, json_output=state.json_output, command=command, strict=state.strict)


def _place(
    ctx: typer.Context,
    side: str,
    symbol: str,
    qty: float,
    *,
    limit: float | None,
    stop: float | None,
    tif: TIF,
    dry_run: bool,
    idempotency_key: str | None,
) -> None:
    state = get_state(ctx)
    command = "order.place"
    params: dict[str, object] = {
        "side": side,
        "symbol": symbol,
        "qty": qty,
        "tif": tif.value,
    }
    if limit is not None:
        params["limit"] = limit
    if stop is not None:
        params["stop"] = stop
    if dry_run:
        params["dry_run"] = True
    if idempotency_key:
        params["idempotency_key"] = idempotency_key

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
