"""Shared CLI context, rendering, and daemon RPC helpers."""

from __future__ import annotations

import asyncio
from difflib import get_close_matches
import json
import os
from pathlib import Path
import signal
import subprocess
import sys
import time
from dataclasses import dataclass
from typing import Any

import click
import typer
from typer.core import TyperGroup

from broker_daemon.config import AppConfig, load_config
from broker_daemon.exceptions import ErrorCode, BrokerError
from broker_sdk import Client

HELP_CONTEXT_SETTINGS = {
    "help_option_names": ["-h", "--help"],
    "max_content_width": 110,
}


@dataclass
class CLIState:
    config: AppConfig
    json_output: bool


class SuggestionGroup(TyperGroup):
    """Click command group that appends close-match suggestions for unknown commands."""

    def resolve_command(
        self,
        ctx: click.Context,
        args: list[str],
    ) -> tuple[str | None, click.Command | None, list[str]]:
        try:
            return super().resolve_command(ctx, args)
        except click.UsageError as exc:
            if args:
                attempted = args[0]
                matches = get_close_matches(attempted, list(self.list_commands(ctx)), n=3, cutoff=0.45)
                if matches:
                    exc.message = f"{exc.message}\n\nDid you mean: {', '.join(matches)}"
            raise


def build_typer(help_text: str) -> typer.Typer:
    """Create Typer apps with consistent help ergonomics across command groups."""

    return typer.Typer(
        help=help_text,
        cls=SuggestionGroup,
        no_args_is_help=True,
        rich_markup_mode="markdown",
        context_settings=HELP_CONTEXT_SETTINGS,
    )


def get_state(ctx: typer.Context) -> CLIState:
    value = ctx.obj
    if not isinstance(value, CLIState):
        raise RuntimeError("CLI context not initialized")
    return value


def run_async(awaitable: Any) -> Any:
    return asyncio.run(awaitable)


def print_output(data: Any, *, json_output: bool, title: str | None = None) -> None:
    _ = json_output
    _ = title
    print(json.dumps(data, default=str, separators=(",", ":")))


def parse_csv_items(raw: str, *, field_name: str) -> list[str]:
    values = [value.strip() for value in raw.split(",") if value.strip()]
    if not values:
        raise typer.BadParameter(f"{field_name} must contain at least one value")
    return values


def validate_allowed_values(
    values: list[str],
    *,
    allowed: set[str],
    field_name: str,
) -> list[str]:
    invalid = [value for value in values if value not in allowed]
    if invalid:
        valid_text = ", ".join(sorted(allowed))
        raise typer.BadParameter(f"unsupported {field_name}: {', '.join(invalid)}. valid values: {valid_text}")
    return values


def handle_error(exc: BrokerError, *, json_output: bool) -> None:
    suggestion = exc.suggestion or _default_suggestion(exc.code)
    error_payload = exc.to_error_payload()
    if suggestion and "suggestion" not in error_payload:
        error_payload["suggestion"] = suggestion
    payload = {"ok": False, "error": error_payload}
    _ = json_output
    print(json.dumps(payload, default=str, separators=(",", ":")))
    raise typer.Exit(code=exc.exit_code)


async def daemon_request(state: CLIState, command: str, params: dict[str, Any] | None = None) -> Any:
    async with Client(socket_path=state.config.runtime.socket_path, timeout_seconds=state.config.runtime.request_timeout_seconds) as cli:
        return await cli._request(command, params or {}, source="cli")


def start_daemon_process(
    cfg: AppConfig,
    *,
    extra_env: dict[str, str] | None = None,
) -> int:
    socket_was_stale = False
    if cfg.runtime.socket_path.exists():
        try:
            status = run_async(daemon_request(CLIState(cfg, json_output=True), "daemon.status", {}))
            if status:
                return 0
        except Exception:
            socket_was_stale = True

    pid = _read_pid_file(cfg.runtime.pid_file)
    if pid is not None and _is_pid_running(pid):
        # Process exists but daemon is not healthy/reachable; terminate stale owner before restarting.
        _terminate_pid(pid)
        if _wait_for_pid_exit(pid, timeout_seconds=5):
            cfg.runtime.pid_file.unlink(missing_ok=True)
        else:
            return 1

    if socket_was_stale:
        cfg.runtime.socket_path.unlink(missing_ok=True)

    cmd = [sys.executable, "-m", "broker_daemon.daemon.server"]

    env = dict(os.environ)
    if extra_env:
        env.update(extra_env)

    subprocess.Popen(
        cmd,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        start_new_session=True,
        env=env,
    )

    deadline = time.time() + 8
    while time.time() < deadline:
        if cfg.runtime.socket_path.exists():
            try:
                run_async(daemon_request(CLIState(cfg, json_output=True), "daemon.status", {}))
                return 0
            except Exception:
                pass
        time.sleep(0.1)
    return 1


def _read_pid_file(path: Path) -> int | None:
    try:
        raw = path.read_text(encoding="utf-8").strip()
    except OSError:
        return None
    if not raw:
        return None
    try:
        return int(raw)
    except ValueError:
        return None


def _is_pid_running(pid: int) -> bool:
    if pid <= 0:
        return False
    try:
        os.kill(pid, 0)
        return True
    except OSError:
        return False


def _terminate_pid(pid: int) -> None:
    try:
        os.kill(pid, signal.SIGTERM)
    except OSError:
        return


def _wait_for_pid_exit(pid: int, *, timeout_seconds: float) -> bool:
    deadline = time.time() + timeout_seconds
    while time.time() < deadline:
        if not _is_pid_running(pid):
            return True
        time.sleep(0.1)
    return not _is_pid_running(pid)


def _default_suggestion(code: ErrorCode) -> str | None:
    suggestions = {
        ErrorCode.DAEMON_NOT_RUNNING: "Start the daemon with `broker daemon start`.",
        ErrorCode.IB_DISCONNECTED: "Verify IB Gateway/TWS is running and the gateway host/port are correct.",
        ErrorCode.INVALID_ARGS: "Run `broker --help` or `<command> --help` for valid usage.",
        ErrorCode.TIMEOUT: "Retry the command or increase `runtime.request_timeout_seconds` in config.",
        ErrorCode.RISK_HALTED: "Review `broker risk limits`, then run `broker risk resume` when appropriate.",
    }
    return suggestions.get(code)
