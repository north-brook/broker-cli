from __future__ import annotations

import asyncio
import builtins
import types

import pytest

from broker_daemon.config import GatewayConfig
from broker_daemon.daemon.connection import IBConnectionManager
from broker_daemon.exceptions import ErrorCode, BrokerError


class _FakeEvent:
    def __init__(self) -> None:
        self.handlers: list[object] = []

    def __iadd__(self, handler: object):  # type: ignore[override]
        self.handlers.append(handler)
        return self


class _FakeIB:
    instances: list["_FakeIB"] = []

    def __init__(self) -> None:
        self.connected = False
        self.disconnectedEvent = _FakeEvent()
        self.orderStatusEvent = _FakeEvent()
        self.execDetailsEvent = _FakeEvent()
        self.client = types.SimpleNamespace(serverVersion=lambda: 180)
        _FakeIB.instances.append(self)

    async def connectAsync(self, *_: object, **__: object) -> None:
        self.connected = True

    def isConnected(self) -> bool:
        return self.connected

    def disconnect(self) -> None:
        self.connected = False

    def managedAccounts(self) -> list[str]:
        return ["DU123456"]

    async def reqCurrentTimeAsync(self) -> int:
        return 1700000000


@pytest.mark.asyncio
async def test_connect_registers_event_handlers_after_reconnect(monkeypatch: pytest.MonkeyPatch) -> None:
    import broker_daemon.daemon.connection as connection_mod

    _FakeIB.instances.clear()
    fake_module = types.SimpleNamespace(IB=_FakeIB)
    original_import = builtins.__import__

    def _fake_import(name: str, *args: object, **kwargs: object) -> object:
        if name == "ib_async":
            return fake_module
        return original_import(name, *args, **kwargs)

    monkeypatch.setattr(builtins, "__import__", _fake_import)

    manager = IBConnectionManager(GatewayConfig())
    assert await manager.connect() is True
    first = _FakeIB.instances[-1]
    assert len(first.disconnectedEvent.handlers) == 1
    assert len(first.orderStatusEvent.handlers) == 1
    assert len(first.execDetailsEvent.handlers) == 1

    await manager.stop()
    assert await manager.connect() is True
    second = _FakeIB.instances[-1]
    assert second is not first
    assert len(second.disconnectedEvent.handlers) == 1
    assert len(second.orderStatusEvent.handlers) == 1
    assert len(second.execDetailsEvent.handlers) == 1


@pytest.mark.asyncio
async def test_on_disconnected_resets_listener_flag_and_schedules_reconnect(monkeypatch: pytest.MonkeyPatch) -> None:
    manager = IBConnectionManager(GatewayConfig())
    manager._listeners_registered = True  # noqa: SLF001

    called = asyncio.Event()

    async def _fake_loop() -> None:
        called.set()

    monkeypatch.setattr(manager, "_reconnect_loop", _fake_loop)
    manager._on_disconnected()  # noqa: SLF001

    assert manager._listeners_registered is False  # noqa: SLF001
    if manager._reconnect_task is not None:  # noqa: SLF001
        await manager._reconnect_task  # noqa: SLF001
    assert called.is_set()


@pytest.mark.asyncio
async def test_exposure_rejects_unknown_group() -> None:
    manager = IBConnectionManager(GatewayConfig())
    with pytest.raises(BrokerError) as exc:
        await manager.exposure("invalid-group")
    assert exc.value.code == ErrorCode.INVALID_ARGS


# --- Health check tests ---


def _make_connected_manager(monkeypatch: pytest.MonkeyPatch) -> IBConnectionManager:
    """Return an IBConnectionManager with a fake IB client that appears connected."""
    _FakeIB.instances.clear()
    fake_module = types.SimpleNamespace(IB=_FakeIB)
    original_import = builtins.__import__

    def _fake_import(name: str, *args: object, **kwargs: object) -> object:
        if name == "ib_async":
            return fake_module
        return original_import(name, *args, **kwargs)

    monkeypatch.setattr(builtins, "__import__", _fake_import)
    manager = IBConnectionManager(GatewayConfig())
    # Directly set up internal state to simulate a connected session.
    fake_ib = _FakeIB()
    fake_ib.connected = True
    manager._ib = fake_ib  # noqa: SLF001
    from datetime import UTC, datetime

    manager._connected_at = datetime.now(UTC)  # noqa: SLF001
    return manager


@pytest.mark.asyncio
async def test_check_health_returns_true_when_alive(monkeypatch: pytest.MonkeyPatch) -> None:
    manager = _make_connected_manager(monkeypatch)
    assert manager.is_connected
    result = await manager.check_health()
    assert result is True


@pytest.mark.asyncio
async def test_check_health_forces_disconnect_on_timeout(monkeypatch: pytest.MonkeyPatch) -> None:
    manager = _make_connected_manager(monkeypatch)

    async def _hang() -> None:
        await asyncio.sleep(60)

    manager._ib.reqCurrentTimeAsync = _hang  # noqa: SLF001

    reconnect_called = asyncio.Event()

    async def _fake_reconnect() -> None:
        reconnect_called.set()

    monkeypatch.setattr(manager, "_reconnect_loop", _fake_reconnect)

    result = await manager.check_health()
    assert result is False
    assert manager._connected_at is None  # noqa: SLF001
    if manager._reconnect_task is not None:  # noqa: SLF001
        await manager._reconnect_task  # noqa: SLF001
    assert reconnect_called.is_set()


@pytest.mark.asyncio
async def test_check_health_forces_disconnect_on_exception(monkeypatch: pytest.MonkeyPatch) -> None:
    manager = _make_connected_manager(monkeypatch)

    async def _raise() -> None:
        raise ConnectionError("session dead")

    manager._ib.reqCurrentTimeAsync = _raise  # noqa: SLF001

    reconnect_called = asyncio.Event()

    async def _fake_reconnect() -> None:
        reconnect_called.set()

    monkeypatch.setattr(manager, "_reconnect_loop", _fake_reconnect)

    result = await manager.check_health()
    assert result is False
    assert manager._connected_at is None  # noqa: SLF001
    if manager._reconnect_task is not None:  # noqa: SLF001
        await manager._reconnect_task  # noqa: SLF001
    assert reconnect_called.is_set()


@pytest.mark.asyncio
async def test_check_health_skips_when_not_connected() -> None:
    manager = IBConnectionManager(GatewayConfig())
    assert not manager.is_connected
    result = await manager.check_health()
    assert result is False


@pytest.mark.asyncio
async def test_check_health_skips_when_reconnect_in_progress(monkeypatch: pytest.MonkeyPatch) -> None:
    manager = _make_connected_manager(monkeypatch)

    # Simulate a reconnect task that is still running.
    never_done: asyncio.Future[None] = asyncio.get_event_loop().create_future()
    manager._reconnect_task = asyncio.ensure_future(never_done)  # noqa: SLF001

    result = await manager.check_health()
    assert result is False

    # Clean up the dangling future.
    never_done.cancel()
    try:
        await manager._reconnect_task  # noqa: SLF001
    except asyncio.CancelledError:
        pass
