from __future__ import annotations

import pytest

from broker_daemon.config import AppConfig, LoggingConfig, RuntimeConfig
from broker_daemon.daemon.server import DaemonServer
from broker_daemon.exceptions import ErrorCode, BrokerError
from broker_daemon.models.market import OptionChain, OptionChainEntry
from broker_daemon.models.risk import RiskCheckResult
from broker_daemon.protocol import Request
from broker_daemon.risk.engine import RiskContext


def _test_config(tmp_path) -> AppConfig:
    return AppConfig(
        logging=LoggingConfig(
            audit_db=tmp_path / "audit.db",
            log_file=tmp_path / "broker.log",
        ),
        runtime=RuntimeConfig(
            socket_path=tmp_path / "broker.sock",
            pid_file=tmp_path / "broker-daemon.pid",
            request_timeout_seconds=5,
        ),
    )


@pytest.mark.asyncio
async def test_dispatch_quote_requires_symbols(tmp_path) -> None:
    server = DaemonServer(_test_config(tmp_path))
    req = Request(command="quote.snapshot", params={})

    with pytest.raises(BrokerError) as exc:
        await server._dispatch(req)  # noqa: SLF001

    assert exc.value.code == ErrorCode.INVALID_ARGS
    assert "symbols" in exc.value.message


@pytest.mark.asyncio
async def test_dispatch_rejects_invalid_chain_type(tmp_path) -> None:
    server = DaemonServer(_test_config(tmp_path))
    req = Request(command="market.chain", params={"symbol": "AAPL", "type": "straddle"})

    with pytest.raises(BrokerError) as exc:
        await server._dispatch(req)  # noqa: SLF001

    assert exc.value.code == ErrorCode.INVALID_ARGS
    assert "option type" in exc.value.message


@pytest.mark.asyncio
async def test_dispatch_rejects_invalid_quote_intent(tmp_path) -> None:
    server = DaemonServer(_test_config(tmp_path))
    req = Request(command="quote.snapshot", params={"symbols": ["AAPL"], "intent": "invalid"})

    with pytest.raises(BrokerError) as exc:
        await server._dispatch(req)  # noqa: SLF001

    assert exc.value.code == ErrorCode.INVALID_ARGS
    assert "quote intent" in exc.value.message


@pytest.mark.asyncio
async def test_dispatch_rejects_invalid_order_status_filter(tmp_path) -> None:
    server = DaemonServer(_test_config(tmp_path))
    req = Request(command="orders.list", params={"status": "pending"})

    with pytest.raises(BrokerError) as exc:
        await server._dispatch(req)  # noqa: SLF001

    assert exc.value.code == ErrorCode.INVALID_ARGS
    assert "unsupported orders status" in exc.value.message


@pytest.mark.asyncio
async def test_dispatch_market_capabilities_returns_payload(tmp_path) -> None:
    server = DaemonServer(_test_config(tmp_path))
    req = Request(command="market.capabilities", params={"symbols": ["AAPL"], "refresh": False})

    data = await server._dispatch(req)  # noqa: SLF001
    capabilities = data.get("capabilities", {})
    assert capabilities.get("provider")
    assert "supports" in capabilities
    assert "cache" in data
    assert "cache_age_ms" in data["cache"]


@pytest.mark.asyncio
async def test_dispatch_history_strict_raises_on_empty(monkeypatch: pytest.MonkeyPatch, tmp_path) -> None:
    server = DaemonServer(_test_config(tmp_path))
    server._provider.capabilities["history"] = True  # noqa: SLF001

    async def fake_history(**_: object) -> list[object]:
        return []

    monkeypatch.setattr(server._provider, "history", fake_history)  # noqa: SLF001

    req = Request(
        command="market.history",
        params={"symbol": "INVALID", "period": "5d", "bar": "1d", "strict": True},
    )

    with pytest.raises(BrokerError) as exc:
        await server._dispatch(req)  # noqa: SLF001

    assert exc.value.code == ErrorCode.INVALID_SYMBOL


@pytest.mark.asyncio
async def test_dispatch_chain_applies_limit_offset_and_fields(monkeypatch: pytest.MonkeyPatch, tmp_path) -> None:
    server = DaemonServer(_test_config(tmp_path))
    server._provider.capabilities["option_chain"] = True  # noqa: SLF001

    async def fake_chain(**_: object) -> OptionChain:
        return OptionChain(
            symbol="AAPL",
            underlying_price=200.0,
            entries=[
                OptionChainEntry(symbol="AAPL", right="C", strike=190.0, expiry="2026-03-20", bid=1.2, ask=1.3),
                OptionChainEntry(symbol="AAPL", right="C", strike=200.0, expiry="2026-03-20", bid=2.2, ask=2.3),
                OptionChainEntry(symbol="AAPL", right="C", strike=210.0, expiry="2026-03-20", bid=3.2, ask=3.3),
            ],
        )

    monkeypatch.setattr(server._provider, "option_chain", fake_chain)  # noqa: SLF001

    req = Request(
        command="market.chain",
        params={"symbol": "AAPL", "limit": 1, "offset": 1, "fields": ["strike", "expiry"]},
    )
    data = await server._dispatch(req)  # noqa: SLF001

    assert data["pagination"]["total_entries"] == 3
    assert data["pagination"]["returned_entries"] == 1
    assert data["entries"] == [{"strike": 200.0, "expiry": "2026-03-20"}]


@pytest.mark.asyncio
async def test_dispatch_order_place_dry_run_preview(monkeypatch: pytest.MonkeyPatch, tmp_path) -> None:
    server = DaemonServer(_test_config(tmp_path))

    async def fake_risk_context() -> RiskContext:
        return RiskContext(nlv=1_000_000.0, daily_pnl=0.0, open_orders=0, mark_prices={"AAPL": 200.0})

    called: dict[str, bool] = {"place_order": False}

    async def fake_place_order(*_: object, **__: object) -> object:
        called["place_order"] = True
        raise AssertionError("place_order should not be called for dry-run")

    def fake_check_order(*_: object, **__: object) -> RiskCheckResult:
        return RiskCheckResult(ok=True, reasons=[], details={"notional": 200.0})

    async def fake_log_risk_event(*_: object, **__: object) -> None:
        return None

    monkeypatch.setattr(server._orders, "_risk_context", fake_risk_context)  # noqa: SLF001
    monkeypatch.setattr(server._orders, "place_order", fake_place_order)  # noqa: SLF001
    monkeypatch.setattr(server._risk, "check_order", fake_check_order)  # noqa: SLF001
    monkeypatch.setattr(server._audit, "log_risk_event", fake_log_risk_event)  # noqa: SLF001

    req = Request(
        command="order.place",
        params={"side": "buy", "symbol": "AAPL", "qty": 1, "limit": 200, "dry_run": True},
    )
    data = await server._dispatch(req)  # noqa: SLF001

    assert called["place_order"] is False
    assert data["dry_run"] is True
    assert data["submit_allowed"] is True
    assert data["order"]["status"].startswith("DryRun")


@pytest.mark.asyncio
async def test_dispatch_schema_get_returns_schema(tmp_path) -> None:
    server = DaemonServer(_test_config(tmp_path))
    req = Request(command="schema.get", params={"command": "quote.snapshot"})

    data = await server._dispatch(req)  # noqa: SLF001
    assert data["schema_version"] == "v1"
    assert data["command"] == "quote.snapshot"
    assert "params" in data["schema"]
