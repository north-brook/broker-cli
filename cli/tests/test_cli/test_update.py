from __future__ import annotations

import json
from pathlib import Path

import pytest
from typer.testing import CliRunner

import update
from main import app


@pytest.fixture
def runner() -> CliRunner:
    return CliRunner()


def test_update_syncs_to_origin_main_and_reinstalls(monkeypatch: pytest.MonkeyPatch, runner: CliRunner) -> None:
    repo_root = Path("/tmp/broker-cli")
    monkeypatch.setattr(update, "_find_repo_root", lambda: repo_root)
    monkeypatch.setattr(update, "_ensure_git_available", lambda: None)

    head_values = iter(["aaa111", "bbb222"])
    git_calls: list[tuple[str, ...]] = []
    reinstall_calls: list[Path] = []

    def fake_git(_: Path, *args: str) -> str:
        git_calls.append(args)
        if args == ("rev-parse", "HEAD"):
            return next(head_values)
        if args == ("status", "--porcelain"):
            return ""
        return ""

    def fake_reinstall(path: Path) -> None:
        reinstall_calls.append(path)

    monkeypatch.setattr(update, "_git", fake_git)
    monkeypatch.setattr(update, "_reinstall_editable_packages", fake_reinstall)

    result = runner.invoke(app, ["update"])
    assert result.exit_code == 0, result.stdout

    payload = json.loads(result.stdout)
    assert payload == {
        "ok": True,
        "repo": str(repo_root),
        "branch": "main",
        "from": "aaa111",
        "to": "bbb222",
        "updated": True,
        "reinstalled": True,
    }
    assert ("fetch", "origin", "main") in git_calls
    assert ("checkout", "-B", "main", "origin/main") in git_calls
    assert reinstall_calls == [repo_root]


def test_update_fails_when_worktree_is_dirty_without_force(monkeypatch: pytest.MonkeyPatch, runner: CliRunner) -> None:
    repo_root = Path("/tmp/broker-cli")
    monkeypatch.setattr(update, "_find_repo_root", lambda: repo_root)
    monkeypatch.setattr(update, "_ensure_git_available", lambda: None)

    git_calls: list[tuple[str, ...]] = []

    def fake_git(_: Path, *args: str) -> str:
        git_calls.append(args)
        if args == ("rev-parse", "HEAD"):
            return "aaa111"
        if args == ("status", "--porcelain"):
            return " M cli/src/main.py"
        return ""

    monkeypatch.setattr(update, "_git", fake_git)

    result = runner.invoke(app, ["update"])
    assert result.exit_code == 1, result.stdout

    payload = json.loads(result.stdout)
    assert payload["ok"] is False
    assert payload["error"]["code"] == "UPDATE_FAILED"
    assert "Re-run with --force" in payload["error"]["message"]
    assert ("fetch", "origin", "main") not in git_calls
