from __future__ import annotations

import os
from pathlib import Path

import pytest


@pytest.fixture
def fake_home(tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> Path:
    home = tmp_path / "home"
    home.mkdir(parents=True)
    monkeypatch.setenv("HOME", str(home))
    monkeypatch.setenv("BROKER_RUNTIME_SOCKET_PATH", str(home / ".northbrook" / "broker.sock"))
    monkeypatch.setenv("BROKER_LOGGING_AUDIT_DB", str(home / ".northbrook" / "audit.db"))
    monkeypatch.setenv("BROKER_LOGGING_LOG_FILE", str(home / ".northbrook" / "broker.log"))
    return home


@pytest.fixture(autouse=True)
def clear_broker_env(monkeypatch: pytest.MonkeyPatch) -> None:
    for key in list(os.environ.keys()):
        if key.startswith("BROKER_"):
            monkeypatch.delenv(key, raising=False)
