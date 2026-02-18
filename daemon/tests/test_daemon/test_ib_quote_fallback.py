from __future__ import annotations

import builtins
from datetime import UTC, datetime
import types

import pytest

from broker_daemon.config import GatewayConfig
from broker_daemon.providers.ib import IBProvider


class _FakeEvent:
    def __init__(self) -> None:
        self.handlers: list[object] = []

    def __iadd__(self, handler: object):  # type: ignore[override]
        self.handlers.append(handler)
        return self


class _FakeContract:
    def __init__(self, symbol: str, exchange: str, currency: str) -> None:
        self.symbol = symbol
        self.exchange = exchange
        self.currency = currency


class _FakeTicker:
    def __init__(self, contract: _FakeContract, last: float | None) -> None:
        self.contract = contract
        self.bid = None if last is None else last - 0.01
        self.ask = None if last is None else last + 0.01
        self.last = last
        self.volume = None if last is None else 1000.0
        self.time = datetime.now(UTC)


class _FakeIB:
    instances: list["_FakeIB"] = []
    live_by_symbol: dict[str, float | None] = {}
    delayed_by_symbol: dict[str, float | None] = {}

    def __init__(self) -> None:
        self.connected = False
        self.market_data_type = 1
        self.market_data_type_calls: list[int] = []
        self.req_tickers_calls: list[tuple[str, ...]] = []
        self.req_ticker_contracts: list[tuple[_FakeContract, ...]] = []
        self.disconnectedEvent = _FakeEvent()
        self.orderStatusEvent = _FakeEvent()
        self.execDetailsEvent = _FakeEvent()
        self.errorEvent = _FakeEvent()
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

    async def qualifyContractsAsync(self, *contracts: _FakeContract) -> list[_FakeContract]:
        return list(contracts)

    def reqMarketDataType(self, market_data_type: int) -> None:
        self.market_data_type = market_data_type
        self.market_data_type_calls.append(market_data_type)

    async def reqTickersAsync(self, *contracts: _FakeContract) -> list[_FakeTicker]:
        self.req_ticker_contracts.append(tuple(contracts))
        self.req_tickers_calls.append(tuple(contract.symbol for contract in contracts))
        source = _FakeIB.delayed_by_symbol if self.market_data_type == 3 else _FakeIB.live_by_symbol
        return [_FakeTicker(contract, source.get(contract.symbol)) for contract in contracts]


@pytest.fixture
def fake_ib_module(monkeypatch: pytest.MonkeyPatch) -> type[_FakeIB]:
    _FakeIB.instances.clear()
    _FakeIB.live_by_symbol = {}
    _FakeIB.delayed_by_symbol = {}

    fake_module = types.SimpleNamespace(IB=_FakeIB, Stock=_FakeContract)
    original_import = builtins.__import__

    def _fake_import(name: str, *args: object, **kwargs: object) -> object:
        if name == "ib_async":
            return fake_module
        return original_import(name, *args, **kwargs)

    monkeypatch.setattr(builtins, "__import__", _fake_import)
    return _FakeIB


@pytest.mark.asyncio
async def test_quote_retries_with_delayed_data_when_live_snapshot_empty(fake_ib_module: type[_FakeIB]) -> None:
    fake_ib_module.live_by_symbol = {"AAPL": None}
    fake_ib_module.delayed_by_symbol = {"AAPL": 185.22}

    provider = IBProvider(GatewayConfig())
    quotes = await provider.quote(["AAPL"])
    await provider.stop()

    ib = fake_ib_module.instances[-1]
    assert quotes[0].symbol == "AAPL"
    assert quotes[0].last == pytest.approx(185.22)
    assert quotes[0].meta is not None
    assert quotes[0].meta.source == "delayed"
    assert quotes[0].meta.fallback_used is True
    assert ib.req_tickers_calls == [("AAPL",), ("AAPL",)]
    assert ib.market_data_type_calls == [3, 1]


@pytest.mark.asyncio
async def test_quote_keeps_live_data_when_available(fake_ib_module: type[_FakeIB]) -> None:
    fake_ib_module.live_by_symbol = {"AAPL": 190.01}
    fake_ib_module.delayed_by_symbol = {"AAPL": 185.22}

    provider = IBProvider(GatewayConfig())
    quotes = await provider.quote(["AAPL"])
    await provider.stop()

    ib = fake_ib_module.instances[-1]
    assert quotes[0].last == pytest.approx(190.01)
    assert quotes[0].meta is not None
    assert quotes[0].meta.source == "live"
    assert ib.req_tickers_calls == [("AAPL",)]
    assert all(contract.exchange == "SMART" for contract in ib.req_ticker_contracts[0])
    assert ib.market_data_type_calls == []


@pytest.mark.asyncio
async def test_quote_retries_missing_symbols_after_recent_market_data_block(fake_ib_module: type[_FakeIB]) -> None:
    fake_ib_module.live_by_symbol = {"AAPL": 190.01, "MSFT": None}
    fake_ib_module.delayed_by_symbol = {"AAPL": 185.22, "MSFT": 410.52}

    provider = IBProvider(GatewayConfig())
    provider._on_error(-1, 10197, "No market data during competing live session", None)  # noqa: SLF001

    quotes = await provider.quote(["AAPL", "MSFT"])
    await provider.stop()

    ib = fake_ib_module.instances[-1]
    by_symbol = {quote.symbol: quote for quote in quotes}
    assert by_symbol["AAPL"].last == pytest.approx(190.01)
    assert by_symbol["MSFT"].last == pytest.approx(410.52)
    assert by_symbol["AAPL"].meta is not None
    assert by_symbol["MSFT"].meta is not None
    assert by_symbol["AAPL"].meta.source == "live"
    assert by_symbol["MSFT"].meta.source == "delayed"
    assert ib.req_tickers_calls == [("AAPL", "MSFT"), ("MSFT",)]
    assert ib.market_data_type_calls == [3, 1]


@pytest.mark.asyncio
async def test_quote_capabilities_reflect_observed_fields(fake_ib_module: type[_FakeIB]) -> None:
    fake_ib_module.live_by_symbol = {"AAPL": 190.01}

    provider = IBProvider(GatewayConfig())
    await provider.quote(["AAPL"])
    capabilities = await provider.quote_capabilities(["AAPL"], refresh=False)
    await provider.stop()

    assert capabilities.provider == "ib"
    assert capabilities.supports["live"] is True
    assert capabilities.symbols["AAPL"].fields.last is True
    assert capabilities.symbols["AAPL"].fields.bid is True
    assert capabilities.symbols["AAPL"].fields.ask is True
