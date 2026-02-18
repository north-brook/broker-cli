"""Repository update command for syncing broker-cli to origin/main."""

from __future__ import annotations

import os
from pathlib import Path
import shutil
import subprocess
import sys

import typer

from _common import get_state, print_output


class UpdateCommandError(RuntimeError):
    """Raised when broker update cannot complete."""


def update(
    ctx: typer.Context,
    force: bool = typer.Option(
        False,
        "--force",
        help="Discard tracked local changes before syncing.",
    ),
    reinstall: bool = typer.Option(
        True,
        "--reinstall/--no-reinstall",
        help="Reinstall editable broker packages after syncing.",
    ),
) -> None:
    """Sync the local broker-cli checkout to the latest commit on origin/main."""

    state = get_state(ctx)

    try:
        repo_root = _find_repo_root()
        _ensure_git_available()

        before_sha = _git(repo_root, "rev-parse", "HEAD")
        dirty = bool(_git(repo_root, "status", "--porcelain"))
        if dirty and not force:
            raise UpdateCommandError("Working tree has local changes. Re-run with --force to discard tracked changes.")
        if dirty and force:
            _git(repo_root, "reset", "--hard", "HEAD")

        _git(repo_root, "fetch", "origin", "main")
        _git(repo_root, "checkout", "-B", "main", "origin/main")
        after_sha = _git(repo_root, "rev-parse", "HEAD")

        reinstalled = False
        if reinstall:
            _reinstall_editable_packages(repo_root)
            reinstalled = True

        print_output(
            {
                "ok": True,
                "repo": str(repo_root),
                "branch": "main",
                "from": before_sha,
                "to": after_sha,
                "updated": before_sha != after_sha,
                "reinstalled": reinstalled,
            },
            json_output=state.json_output,
        )
    except UpdateCommandError as exc:
        print_output(
            {
                "ok": False,
                "error": {
                    "code": "UPDATE_FAILED",
                    "message": str(exc),
                },
            },
            json_output=state.json_output,
        )
        raise typer.Exit(code=1)


def _ensure_git_available() -> None:
    if shutil.which("git") is None:
        raise UpdateCommandError("git is not available on PATH.")


def _find_repo_root() -> Path:
    env_root = os.environ.get("BROKER_ROOT", "").strip()
    candidates: list[Path] = []
    if env_root:
        candidates.append(Path(env_root).expanduser().resolve())

    current = Path(__file__).resolve()
    candidates.extend(current.parents)

    seen: set[Path] = set()
    for candidate in candidates:
        if candidate in seen:
            continue
        seen.add(candidate)
        if _looks_like_repo_root(candidate):
            return candidate

    try:
        detected = Path(_run(["git", "rev-parse", "--show-toplevel"], cwd=Path.cwd())).resolve()
    except UpdateCommandError:
        detected = None

    if detected is not None and _looks_like_repo_root(detected):
        return detected

    raise UpdateCommandError("Could not locate a broker-cli source checkout for update.")


def _looks_like_repo_root(path: Path) -> bool:
    return (path / "cli").is_dir() and (path / "daemon").is_dir() and (path / ".git").exists()


def _reinstall_editable_packages(repo_root: Path) -> None:
    _run(
        [
            sys.executable,
            "-m",
            "pip",
            "install",
            "-e",
            "./daemon",
            "-e",
            "./sdk/python",
            "-e",
            "./cli",
        ],
        cwd=repo_root,
    )


def _git(repo_root: Path, *args: str) -> str:
    return _run(["git", *args], cwd=repo_root)


def _run(cmd: list[str], *, cwd: Path) -> str:
    completed = subprocess.run(
        cmd,
        cwd=str(cwd),
        check=False,
        capture_output=True,
        text=True,
    )
    if completed.returncode != 0:
        message = completed.stderr.strip() or completed.stdout.strip() or "command failed"
        raise UpdateCommandError(message)
    return completed.stdout.strip()
