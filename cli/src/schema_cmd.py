"""Command schema discovery for agentic clients."""

from __future__ import annotations

import typer

from _common import daemon_request, get_state, handle_error, print_output, run_async
from broker_daemon.exceptions import BrokerError


def schema(
    ctx: typer.Context,
    command: str | None = typer.Argument(
        None,
        help="Optional daemon command name (example: quote.snapshot). Omit to list all schemas.",
    ),
) -> None:
    state = get_state(ctx)
    rpc_command = "schema.get"
    params: dict[str, object] = {}
    if command:
        params["command"] = command

    try:
        result = run_async(daemon_request(state, rpc_command, params))
        print_output(
            result.data,
            json_output=state.json_output,
            command=rpc_command,
            request_id=result.request_id,
            strict=state.strict,
        )
    except BrokerError as exc:
        handle_error(exc, json_output=state.json_output, command=rpc_command, strict=state.strict)
