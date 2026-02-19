"""Daemon lifecycle commands."""

from __future__ import annotations

import os
from pathlib import Path
import signal
import time

import typer

from _common import build_typer, daemon_request, get_state, handle_error, print_output, run_async, start_daemon_process
from broker_daemon.config import AppConfig
from broker_daemon.exceptions import BrokerError

app = build_typer("Daemon lifecycle commands (`start`, `stop`, `status`, `restart`).")


@app.command("start", help="Start broker-daemon and wait for socket readiness.")
def start(
    ctx: typer.Context,
    gateway: str | None = typer.Option(None, "--gateway", help="Override gateway endpoint as HOST:PORT."),
    client_id: int | None = typer.Option(None, "--client-id", help="Override IB client id."),
    paper: bool = typer.Option(False, "--paper", help="Force paper trading port (4002)."),
) -> None:
    state = get_state(ctx)

    env: dict[str, str] = {}
    if gateway:
        host, _, port = gateway.partition(":")
        env["BROKER_GATEWAY_HOST"] = host
        if port:
            env["BROKER_GATEWAY_PORT"] = port
    if client_id is not None:
        env["BROKER_GATEWAY_CLIENT_ID"] = str(client_id)
    if paper:
        env["BROKER_GATEWAY_PORT"] = "4002"

    code = start_daemon_process(state.config, extra_env=env or None)
    if code != 0:
        typer.echo("Failed to start daemon. Check broker log (default: ~/.local/state/broker/broker.log).", err=True)
        raise typer.Exit(code=1)

    print_output(
        {"socket": str(state.config.runtime.socket_path)},
        json_output=state.json_output,
        command="daemon.start",
        strict=state.strict,
    )


@app.command("stop", help="Request graceful daemon shutdown.")
def stop(ctx: typer.Context) -> None:
    state = get_state(ctx)
    command = "daemon.stop"
    try:
        result = run_async(daemon_request(state, command, {}))
        print_output(
            result.data,
            json_output=state.json_output,
            command=command,
            request_id=result.request_id,
            strict=state.strict,
        )
    except BrokerError as exc:
        handle_error(exc, json_output=state.json_output, command=command, strict=state.strict)


@app.command("status", help="Show daemon uptime, IB connection state, and risk halt status.")
def status(ctx: typer.Context) -> None:
    state = get_state(ctx)
    command = "daemon.status"
    try:
        result = run_async(daemon_request(state, command, {}))
        print_output(
            result.data,
            json_output=state.json_output,
            command=command,
            request_id=result.request_id,
            strict=state.strict,
        )
    except BrokerError as exc:
        handle_error(exc, json_output=state.json_output, command=command, strict=state.strict)


@app.command("restart", help="Stop then start the daemon.")
def restart(
    ctx: typer.Context,
    paper: bool = typer.Option(False, "--paper", help="Restart using paper trading port (4002)."),
) -> None:
    state = get_state(ctx)
    stop_command = "daemon.stop"
    try:
        run_async(daemon_request(state, stop_command, {}))
    except Exception:
        pass

    if not _wait_for_daemon_shutdown(state.config, timeout_seconds=10):
        pid = _read_pid_file(state.config.runtime.pid_file)
        if pid is not None and _is_pid_running(pid):
            try:
                os.kill(pid, signal.SIGTERM)
            except OSError:
                pass
            if not _wait_for_daemon_shutdown(state.config, timeout_seconds=5):
                typer.echo(
                    "Timed out waiting for daemon shutdown. Check for stale broker-daemon processes and retry.",
                    err=True,
                )
                raise typer.Exit(code=1)
        else:
            typer.echo(
                "Timed out waiting for daemon shutdown. Check for stale broker-daemon processes and retry.",
                err=True,
            )
            raise typer.Exit(code=1)

    env = {"BROKER_GATEWAY_PORT": "4002"} if paper else None
    code = start_daemon_process(state.config, extra_env=env)
    if code != 0:
        typer.echo("Failed to restart daemon. Check broker log (default: ~/.local/state/broker/broker.log).", err=True)
        raise typer.Exit(code=1)
    print_output(
        {"restarted": True},
        json_output=state.json_output,
        command="daemon.restart",
        strict=state.strict,
    )


def _wait_for_daemon_shutdown(cfg: AppConfig, *, timeout_seconds: float) -> bool:
    deadline = time.time() + timeout_seconds
    while time.time() < deadline:
        socket_exists = cfg.runtime.socket_path.exists()
        pid = _read_pid_file(cfg.runtime.pid_file)
        pid_running = pid is not None and _is_pid_running(pid)

        daemon_responding = False
        if socket_exists:
            try:
                run_async(daemon_request(_status_state(cfg), "daemon.status", {}))
                daemon_responding = True
            except Exception:
                daemon_responding = False

        if socket_exists and not daemon_responding and not pid_running:
            cfg.runtime.socket_path.unlink(missing_ok=True)
            socket_exists = False

        if not socket_exists and not daemon_responding and not pid_running:
            return True
        time.sleep(0.1)
    return False


def _status_state(cfg: AppConfig):
    from _common import CLIState

    return CLIState(cfg, json_output=True, strict=False)


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
