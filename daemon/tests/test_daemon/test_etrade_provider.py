from __future__ import annotations

import asyncio
import math
from pathlib import Path

import pytest

import broker_daemon.config as broker_config
from broker_daemon.config import ETradeConfig
from broker_daemon.exceptions import BrokerError, ErrorCode
from broker_daemon.models.market import Quote
from broker_daemon.models.portfolio import Balance, Position
from broker_daemon.providers.etrade import (
    ETradeProvider,
    _as_float,
    _build_option_chain_entry,
    _chunks,
    _extract_option_expiry,
    _extract_option_pairs,
    _extract_option_strike,
    _extract_underlying_price,
    _first_float,
    _format_expiry,
    _is_open_order_status,
    _normalized_expiry_prefix,
    _option_chain_type,
    _parse_expiry_prefix,
)
import broker_daemon.providers.etrade as etrade_mod


def _cfg(tmp_path: Path, **overrides: object) -> ETradeConfig:
    base: dict[str, object] = {
        "consumer_key": "consumer-key",
        "consumer_secret": "consumer-secret",
        "token_path": tmp_path / "etrade-tokens.json",
        "username": "alice",
        "password": "secret",
        "persistent_auth": True,
    }
    base.update(overrides)
    return ETradeConfig.model_validate(base)


@pytest.mark.asyncio
async def test_attempt_persistent_auth_updates_tokens(monkeypatch: pytest.MonkeyPatch, tmp_path: Path) -> None:
    provider = ETradeProvider(_cfg(tmp_path))
    called: dict[str, object] = {}

    async def _fake_headless_reauth(**kwargs: object) -> tuple[str, str]:
        called.update(kwargs)
        return "fresh-token", "fresh-secret"

    monkeypatch.setattr(etrade_mod, "headless_reauth", _fake_headless_reauth)

    ok = await provider._attempt_persistent_auth()  # noqa: SLF001

    assert ok is True
    assert provider._oauth_token == "fresh-token"  # noqa: SLF001
    assert provider._oauth_token_secret == "fresh-secret"  # noqa: SLF001
    assert provider._token_valid is True  # noqa: SLF001
    assert provider._client is not None  # noqa: SLF001
    assert called["username"] == "alice"
    assert called["password"] == "secret"
    await provider.stop()


@pytest.mark.asyncio
async def test_attempt_persistent_auth_requires_credentials(monkeypatch: pytest.MonkeyPatch, tmp_path: Path) -> None:
    provider = ETradeProvider(_cfg(tmp_path, username="", password=""))
    invoked = False

    async def _fake_headless_reauth(**_: object) -> tuple[str, str]:
        nonlocal invoked
        invoked = True
        return "unused", "unused"

    monkeypatch.setattr(etrade_mod, "headless_reauth", _fake_headless_reauth)

    ok = await provider._attempt_persistent_auth()  # noqa: SLF001

    assert ok is False
    assert invoked is False


@pytest.mark.asyncio
async def test_start_uses_persistent_auth_when_tokens_missing(monkeypatch: pytest.MonkeyPatch, tmp_path: Path) -> None:
    provider = ETradeProvider(_cfg(tmp_path))
    monkeypatch.setattr(etrade_mod, "load_etrade_tokens", lambda _path: None)

    attempts = 0

    async def _fake_attempt() -> bool:
        nonlocal attempts
        attempts += 1
        await provider._set_oauth_tokens("generated-token", "generated-secret")  # noqa: SLF001
        return True

    renew_calls: list[bool] = []

    async def _fake_renew(*, initial: bool = False) -> None:
        renew_calls.append(initial)

    async def _fake_discover() -> None:
        provider._account_id_key = "ACC123"  # noqa: SLF001

    async def _fake_log_connection(_event: str, _details: dict[str, object]) -> None:
        return None

    async def _fake_renew_loop() -> None:
        await asyncio.sleep(3600)

    monkeypatch.setattr(provider, "_attempt_persistent_auth", _fake_attempt)  # noqa: SLF001
    monkeypatch.setattr(provider, "_renew_access_token", _fake_renew)  # noqa: SLF001
    monkeypatch.setattr(provider, "_discover_account_id_key", _fake_discover)  # noqa: SLF001
    monkeypatch.setattr(provider, "_log_connection", _fake_log_connection)  # noqa: SLF001
    monkeypatch.setattr(provider, "_renew_loop", _fake_renew_loop)  # noqa: SLF001

    await provider.start()

    assert attempts == 1
    assert renew_calls == [True]
    await provider.stop()


@pytest.mark.asyncio
async def test_start_reauths_when_initial_renew_reports_auth_expired(
    monkeypatch: pytest.MonkeyPatch,
    tmp_path: Path,
) -> None:
    provider = ETradeProvider(_cfg(tmp_path))
    monkeypatch.setattr(etrade_mod, "load_etrade_tokens", lambda _path: ("old-token", "old-secret"))

    attempts = 0

    async def _fake_attempt() -> bool:
        nonlocal attempts
        attempts += 1
        await provider._set_oauth_tokens("fresh-token", "fresh-secret")  # noqa: SLF001
        return True

    renew_attempts = 0

    async def _fake_renew(*, initial: bool = False) -> None:
        nonlocal renew_attempts
        renew_attempts += 1
        if renew_attempts == 1:
            raise BrokerError(
                ErrorCode.IB_DISCONNECTED,
                "expired",
                details={"auth_expired": True},
            )

    async def _fake_discover() -> None:
        provider._account_id_key = "ACC123"  # noqa: SLF001

    async def _fake_log_connection(_event: str, _details: dict[str, object]) -> None:
        return None

    async def _fake_renew_loop() -> None:
        await asyncio.sleep(3600)

    monkeypatch.setattr(provider, "_attempt_persistent_auth", _fake_attempt)  # noqa: SLF001
    monkeypatch.setattr(provider, "_renew_access_token", _fake_renew)  # noqa: SLF001
    monkeypatch.setattr(provider, "_discover_account_id_key", _fake_discover)  # noqa: SLF001
    monkeypatch.setattr(provider, "_log_connection", _fake_log_connection)  # noqa: SLF001
    monkeypatch.setattr(provider, "_renew_loop", _fake_renew_loop)  # noqa: SLF001

    await provider.start()

    assert attempts == 1
    assert renew_attempts == 2
    await provider.stop()


@pytest.mark.asyncio
async def test_renew_loop_attempts_persistent_auth_before_disconnect(
    monkeypatch: pytest.MonkeyPatch,
    tmp_path: Path,
) -> None:
    provider = ETradeProvider(_cfg(tmp_path))
    monkeypatch.setattr(etrade_mod, "RENEW_INTERVAL_SECONDS", -1)
    monkeypatch.setattr(etrade_mod, "RENEW_LOOP_SLEEP_SECONDS", 0)

    async def _fake_renew(*, initial: bool = False) -> None:
        raise BrokerError(
            ErrorCode.IB_DISCONNECTED,
            "expired",
            details={"auth_expired": True},
        )

    attempts = 0

    async def _fake_attempt() -> bool:
        nonlocal attempts
        attempts += 1
        return False

    events: list[tuple[str, dict[str, object]]] = []

    async def _fake_log_connection(event: str, details: dict[str, object]) -> None:
        events.append((event, details))

    monkeypatch.setattr(provider, "_renew_access_token", _fake_renew)  # noqa: SLF001
    monkeypatch.setattr(provider, "_attempt_persistent_auth", _fake_attempt)  # noqa: SLF001
    monkeypatch.setattr(provider, "_log_connection", _fake_log_connection)  # noqa: SLF001
    monkeypatch.setattr(provider, "_should_midnight_reauth", lambda: False)  # noqa: SLF001

    await provider._renew_loop()  # noqa: SLF001

    assert attempts == 1
    assert events == [("disconnected", {"reason": "token_expired"})]


@pytest.mark.parametrize(
    ("value", "expected"),
    [
        ("2025", (2025, None, None)),
        ("2025-06", (2025, 6, None)),
        ("2025-06-21", (2025, 6, 21)),
    ],
)
def test_parse_expiry_prefix_valid_values(value: str, expected: tuple[int, int | None, int | None]) -> None:
    assert _parse_expiry_prefix(value) == expected


@pytest.mark.parametrize("value", ["20250", "2025-060", "2025-06-210"])
def test_parse_expiry_prefix_rejects_invalid_lengths(value: str) -> None:
    with pytest.raises(BrokerError, match="invalid expiry"):
        _parse_expiry_prefix(value)


@pytest.mark.parametrize("value", ["2025-00", "2025-13"])
def test_parse_expiry_prefix_rejects_invalid_months(value: str) -> None:
    with pytest.raises(BrokerError, match="invalid expiry month"):
        _parse_expiry_prefix(value)


@pytest.mark.parametrize(
    ("value", "expected"),
    [
        (None, "CALLPUT"),
        ("call", "CALL"),
        ("put", "PUT"),
    ],
)
def test_option_chain_type_supported_values(value: str | None, expected: str) -> None:
    assert _option_chain_type(value) == expected


def test_option_chain_type_rejects_invalid_value() -> None:
    with pytest.raises(BrokerError, match="unsupported option type"):
        _option_chain_type("straddle")


def test_normalized_expiry_prefix() -> None:
    assert _normalized_expiry_prefix(None) == ""
    assert _normalized_expiry_prefix(" 2025-06-21 ") == "20250621"
    assert _normalized_expiry_prefix("2025/06") == "202506"
    assert _normalized_expiry_prefix("no digits") == ""


def test_format_expiry() -> None:
    assert _format_expiry(2025, 6, 21) == "2025-06-21"
    assert _format_expiry(2025, 0, 21) is None
    assert _format_expiry(2025, 6, 0) is None
    assert _format_expiry("x", 6, 21) is None


def test_extract_option_strike_from_leg() -> None:
    assert _extract_option_strike({"strikePrice": "145.5"}, {}) == pytest.approx(145.5)


def test_extract_option_strike_from_pair() -> None:
    assert _extract_option_strike({}, {"strike": "210"}) == pytest.approx(210.0)


def test_extract_option_strike_from_nested_dict() -> None:
    strike = _extract_option_strike({"strikePrice": {"displayValue": "180.25"}}, {})
    assert strike == pytest.approx(180.25)


def test_extract_option_expiry_prefers_leg_then_falls_back() -> None:
    leg_expiry = _extract_option_expiry(
        leg={"expiryYear": 2025, "expiryMonth": 6, "expiryDay": 21},
        pair={"expiryYear": 2025, "expiryMonth": 7, "expiryDay": 19},
        body={"expiryYear": 2025, "expiryMonth": 8, "expiryDay": 16},
    )
    assert leg_expiry == "2025-06-21"

    pair_expiry = _extract_option_expiry(
        leg={},
        pair={"expirationYear": 2025, "expirationMonth": 7, "expirationDay": 19},
        body={},
    )
    assert pair_expiry == "2025-07-19"

    body_expiry = _extract_option_expiry(
        leg={},
        pair={},
        body={"selectedED": {"year": 2025, "month": 8, "day": 16}},
    )
    assert body_expiry == "2025-08-16"


def test_extract_underlying_price_from_top_level_fields() -> None:
    payload = {"OptionChainResponse": {"underlierPrice": "423.17"}}
    assert _extract_underlying_price(payload) == pytest.approx(423.17)


def test_extract_underlying_price_from_quote_data_fallback() -> None:
    payload = {
        "OptionChainResponse": {
            "QuoteData": [{"All": {"lastTrade": "101.5", "bid": "101.0", "ask": "102.0"}}],
        }
    }
    assert _extract_underlying_price(payload) == pytest.approx(101.5)


def test_build_option_chain_entry_full_with_greeks() -> None:
    entry = _build_option_chain_entry(
        symbol="AAPL",
        right="C",
        leg={
            "bid": "1.2",
            "ask": "1.4",
            "strikePrice": "180",
            "OptionGreeks": {
                "iv": "0.31",
                "delta": "0.55",
                "gamma": "0.07",
                "theta": "-0.02",
                "vega": "0.12",
            },
        },
        pair={"expiryYear": 2025, "expiryMonth": 6, "expiryDay": 21},
        body={},
    )

    assert entry is not None
    assert entry.symbol == "AAPL"
    assert entry.right == "C"
    assert entry.strike == pytest.approx(180.0)
    assert entry.expiry == "2025-06-21"
    assert entry.bid == pytest.approx(1.2)
    assert entry.ask == pytest.approx(1.4)
    assert entry.implied_vol == pytest.approx(0.31)
    assert entry.delta == pytest.approx(0.55)
    assert entry.gamma == pytest.approx(0.07)
    assert entry.theta == pytest.approx(-0.02)
    assert entry.vega == pytest.approx(0.12)


def test_build_option_chain_entry_returns_none_when_missing_strike() -> None:
    entry = _build_option_chain_entry(
        symbol="AAPL",
        right="P",
        leg={"bid": "1.2", "ask": "1.4"},
        pair={"expiryYear": 2025, "expiryMonth": 6, "expiryDay": 21},
        body={},
    )
    assert entry is None


def test_build_option_chain_entry_returns_none_when_missing_expiry() -> None:
    entry = _build_option_chain_entry(
        symbol="AAPL",
        right="P",
        leg={"bid": "1.2", "ask": "1.4", "strikePrice": "180"},
        pair={},
        body={},
    )
    assert entry is None


def test_extract_option_pairs_filters_non_dict_rows() -> None:
    payload = {
        "OptionChainResponse": {
            "OptionPair": [{"Call": {"strikePrice": "180"}}, "invalid", 123, {"Put": {"strikePrice": "180"}}]
        }
    }
    assert _extract_option_pairs(payload) == [
        {"Call": {"strikePrice": "180"}},
        {"Put": {"strikePrice": "180"}},
    ]


@pytest.mark.asyncio
@pytest.mark.parametrize(
    ("option_type", "expected_chain_type", "expected_rights"),
    [
        (None, "CALLPUT", ["C", "P", "C", "P"]),
        ("call", "CALL", ["C", "C"]),
        ("put", "PUT", ["P", "P"]),
    ],
)
async def test_option_chain_filters_by_option_type(
    monkeypatch: pytest.MonkeyPatch,
    tmp_path: Path,
    option_type: str | None,
    expected_chain_type: str,
    expected_rights: list[str],
) -> None:
    provider = ETradeProvider(_cfg(tmp_path))
    calls: list[dict[str, object]] = []
    payload = {
        "OptionChainResponse": {
            "underlierPrice": "184.5",
            "OptionPair": [
                {
                    "Call": {"strikePrice": "180", "expiryYear": 2025, "expiryMonth": 6, "expiryDay": 21},
                    "Put": {"strikePrice": "180", "expiryYear": 2025, "expiryMonth": 6, "expiryDay": 21},
                },
                {
                    "Call": {"strikePrice": "190", "expiryYear": 2025, "expiryMonth": 7, "expiryDay": 19},
                    "Put": {"strikePrice": "190", "expiryYear": 2025, "expiryMonth": 7, "expiryDay": 19},
                },
            ],
        }
    }

    async def _fake_request_json(
        method: str,
        path: str,
        *,
        params: dict[str, object] | None = None,
        json_body: dict[str, object] | None = None,
        operation: str,
        require_connected: bool = True,
    ) -> dict[str, object]:
        calls.append(
            {
                "method": method,
                "path": path,
                "params": params or {},
                "json_body": json_body or {},
                "operation": operation,
                "require_connected": require_connected,
            }
        )
        return payload

    monkeypatch.setattr(provider, "_request_json", _fake_request_json)  # noqa: SLF001

    chain = await provider.option_chain("aapl", None, None, option_type)

    assert chain.symbol == "AAPL"
    assert chain.underlying_price == pytest.approx(184.5)
    assert [entry.right for entry in chain.entries] == expected_rights
    assert calls and calls[0]["path"] == "/v1/market/optionchains"
    assert calls[0]["params"]["chainType"] == expected_chain_type


@pytest.mark.asyncio
async def test_option_chain_filters_by_expiry_prefix(monkeypatch: pytest.MonkeyPatch, tmp_path: Path) -> None:
    provider = ETradeProvider(_cfg(tmp_path))
    seen_params: dict[str, object] = {}
    payload = {
        "OptionChainResponse": {
            "underlierPrice": "184.5",
            "OptionPair": [
                {
                    "Call": {"strikePrice": "180", "expiryYear": 2025, "expiryMonth": 6, "expiryDay": 21},
                    "Put": {"strikePrice": "180", "expiryYear": 2025, "expiryMonth": 6, "expiryDay": 21},
                },
                {
                    "Call": {"strikePrice": "190", "expiryYear": 2025, "expiryMonth": 7, "expiryDay": 19},
                    "Put": {"strikePrice": "190", "expiryYear": 2025, "expiryMonth": 7, "expiryDay": 19},
                },
            ],
        }
    }

    async def _fake_request_json(
        method: str,
        path: str,
        *,
        params: dict[str, object] | None = None,
        json_body: dict[str, object] | None = None,
        operation: str,
        require_connected: bool = True,
    ) -> dict[str, object]:
        del method, path, json_body, operation, require_connected
        seen_params.update(params or {})
        return payload

    monkeypatch.setattr(provider, "_request_json", _fake_request_json)  # noqa: SLF001

    chain = await provider.option_chain("aapl", "2025-06", None, None)

    assert seen_params["expiryYear"] == 2025
    assert seen_params["expiryMonth"] == 6
    assert "expiryDay" not in seen_params
    assert {entry.expiry for entry in chain.entries} == {"2025-06-21"}
    assert len(chain.entries) == 2


@pytest.mark.asyncio
async def test_option_chain_returns_empty_entries_and_quote_fallback(
    monkeypatch: pytest.MonkeyPatch,
    tmp_path: Path,
) -> None:
    provider = ETradeProvider(_cfg(tmp_path))

    async def _fake_request_json(
        method: str,
        path: str,
        *,
        params: dict[str, object] | None = None,
        json_body: dict[str, object] | None = None,
        operation: str,
        require_connected: bool = True,
    ) -> dict[str, object]:
        del method, path, params, json_body, operation, require_connected
        return {"OptionChainResponse": {"OptionPair": []}}

    async def _fake_quote(symbols: list[str]) -> list[Quote]:
        assert symbols == ["MSFT"]
        return [Quote(symbol="MSFT", last=321.1)]

    monkeypatch.setattr(provider, "_request_json", _fake_request_json)  # noqa: SLF001
    monkeypatch.setattr(provider, "quote", _fake_quote)

    chain = await provider.option_chain("msft", None, None, None)

    assert chain.symbol == "MSFT"
    assert chain.underlying_price == pytest.approx(321.1)
    assert chain.entries == []


@pytest.mark.asyncio
async def test_exposure_grouped_by_symbol_uses_balance_nlv(monkeypatch: pytest.MonkeyPatch, tmp_path: Path) -> None:
    provider = ETradeProvider(_cfg(tmp_path))

    async def _fake_positions() -> list[Position]:
        return [
            Position(symbol="AAPL", qty=10, avg_cost=100, market_value=1200, currency="USD"),
            Position(symbol="AAPL", qty=-5, avg_cost=100, market_value=-600, currency="USD"),
            Position(symbol="SAP", qty=4, avg_cost=50, market_value=220, currency="EUR"),
        ]

    async def _fake_balance() -> Balance:
        return Balance(account_id="ACC", net_liquidation=4000)

    monkeypatch.setattr(provider, "positions", _fake_positions)
    monkeypatch.setattr(provider, "balance", _fake_balance)

    rows = await provider.exposure(by="symbol")

    assert [row.key for row in rows] == ["AAPL", "SAP"]
    assert rows[0].exposure_value == pytest.approx(1800.0)
    assert rows[0].exposure_pct == pytest.approx(45.0)
    assert rows[1].exposure_value == pytest.approx(220.0)
    assert rows[1].exposure_pct == pytest.approx(5.5)


@pytest.mark.asyncio
async def test_exposure_grouped_by_currency_uses_fallback_nlv(
    monkeypatch: pytest.MonkeyPatch,
    tmp_path: Path,
) -> None:
    provider = ETradeProvider(_cfg(tmp_path))

    async def _fake_positions() -> list[Position]:
        return [
            Position(symbol="BMW", qty=2, avg_cost=50, market_value=None, currency="EUR"),
            Position(symbol="AAPL", qty=3, avg_cost=100, market_value=330, currency="USD"),
        ]

    async def _fake_balance() -> Balance:
        return Balance(account_id="ACC", net_liquidation=0)

    monkeypatch.setattr(provider, "positions", _fake_positions)
    monkeypatch.setattr(provider, "balance", _fake_balance)

    rows = await provider.exposure(by="currency")

    assert [row.key for row in rows] == ["EUR", "USD"]
    assert rows[0].exposure_value == pytest.approx(100.0)
    assert rows[1].exposure_value == pytest.approx(330.0)
    assert rows[0].exposure_pct == pytest.approx((100.0 / 330.0) * 100.0)
    assert rows[1].exposure_pct == pytest.approx((330.0 / 330.0) * 100.0)


@pytest.mark.asyncio
async def test_exposure_rejects_invalid_group(tmp_path: Path) -> None:
    provider = ETradeProvider(_cfg(tmp_path))
    with pytest.raises(BrokerError, match="unsupported exposure group") as exc:
        await provider.exposure(by="desk")
    assert exc.value.code == ErrorCode.INVALID_ARGS


@pytest.mark.asyncio
async def test_cancel_all_with_no_open_orders(monkeypatch: pytest.MonkeyPatch, tmp_path: Path) -> None:
    provider = ETradeProvider(_cfg(tmp_path))

    async def _fake_account_id() -> str:
        return "ACC123"

    async def _fake_list_orders() -> list[dict[str, object]]:
        return [{"orderId": "1001", "status": "FILLED"}, {"orderId": "1002", "status": "CANCELLED"}]

    async def _fake_request_json(
        method: str,
        path: str,
        *,
        params: dict[str, object] | None = None,
        json_body: dict[str, object] | None = None,
        operation: str,
        require_connected: bool = True,
    ) -> dict[str, object]:
        del method, path, params, json_body, operation, require_connected
        raise AssertionError("cancel endpoint should not be called when no open orders exist")

    monkeypatch.setattr(provider, "_require_account_id_key", _fake_account_id)  # noqa: SLF001
    monkeypatch.setattr(provider, "_list_orders_raw", _fake_list_orders)  # noqa: SLF001
    monkeypatch.setattr(provider, "_request_json", _fake_request_json)  # noqa: SLF001

    result = await provider.cancel_all()

    assert result == {
        "cancelled": False,
        "requested": 0,
        "cancelled_count": 0,
        "failed": [],
    }


@pytest.mark.asyncio
async def test_cancel_all_successful(monkeypatch: pytest.MonkeyPatch, tmp_path: Path) -> None:
    provider = ETradeProvider(_cfg(tmp_path))
    cancelled_order_ids: list[str] = []

    async def _fake_account_id() -> str:
        return "ACC123"

    async def _fake_list_orders() -> list[dict[str, object]]:
        return [
            {"orderId": "11", "status": "OPEN"},
            {"orderId": "12", "status": "WORKING"},
            {"orderId": "13", "status": "FILLED"},
        ]

    async def _fake_request_json(
        method: str,
        path: str,
        *,
        params: dict[str, object] | None = None,
        json_body: dict[str, object] | None = None,
        operation: str,
        require_connected: bool = True,
    ) -> dict[str, object]:
        del method, path, params, operation, require_connected
        assert json_body is not None
        cancelled_order_ids.append(str(json_body["CancelOrderRequest"]["orderId"]))
        return {"CancelOrderResponse": {"status": "success"}}

    monkeypatch.setattr(provider, "_require_account_id_key", _fake_account_id)  # noqa: SLF001
    monkeypatch.setattr(provider, "_list_orders_raw", _fake_list_orders)  # noqa: SLF001
    monkeypatch.setattr(provider, "_request_json", _fake_request_json)  # noqa: SLF001

    result = await provider.cancel_all()

    assert cancelled_order_ids == ["11", "12"]
    assert result["cancelled"] is True
    assert result["requested"] == 2
    assert result["cancelled_count"] == 2
    assert result["cancelled_order_ids"] == [11, 12]
    assert result["failed"] == []


@pytest.mark.asyncio
async def test_cancel_all_partial_failures(monkeypatch: pytest.MonkeyPatch, tmp_path: Path) -> None:
    provider = ETradeProvider(_cfg(tmp_path))

    async def _fake_account_id() -> str:
        return "ACC123"

    async def _fake_list_orders() -> list[dict[str, object]]:
        return [
            {"orderId": "21", "status": "OPEN"},
            {"orderId": "22", "status": "WORKING"},
            {"orderId": "23", "status": "PENDING"},
        ]

    async def _fake_request_json(
        method: str,
        path: str,
        *,
        params: dict[str, object] | None = None,
        json_body: dict[str, object] | None = None,
        operation: str,
        require_connected: bool = True,
    ) -> dict[str, object]:
        del method, path, params, operation, require_connected
        assert json_body is not None
        order_id = str(json_body["CancelOrderRequest"]["orderId"])
        if order_id == "22":
            raise BrokerError(ErrorCode.IB_REJECTED, "upstream timeout")
        if order_id == "23":
            return {"CancelOrderResponse": {"status": "failed"}}
        return {"CancelOrderResponse": {"status": "success"}}

    monkeypatch.setattr(provider, "_require_account_id_key", _fake_account_id)  # noqa: SLF001
    monkeypatch.setattr(provider, "_list_orders_raw", _fake_list_orders)  # noqa: SLF001
    monkeypatch.setattr(provider, "_request_json", _fake_request_json)  # noqa: SLF001

    result = await provider.cancel_all()

    assert result["cancelled"] is False
    assert result["requested"] == 3
    assert result["cancelled_count"] == 1
    assert result["cancelled_order_ids"] == [21]
    assert result["failed"] == [
        {"order_id": 22, "error": "upstream timeout"},
        {"order_id": 23, "error": "cancel rejected"},
    ]


@pytest.mark.parametrize(
    "status",
    ["OPEN", "WORKING", "PENDING", "ACKNOWLEDGED", "PENDING_CANCEL", "PENDING_SUBMIT", "LIVE"],
)
def test_is_open_order_status_open_values(status: str) -> None:
    assert _is_open_order_status(status) is True


@pytest.mark.parametrize("status", ["EXECUTED", "FILLED", "CANCELLED", "REJECTED", "INACTIVE"])
def test_is_open_order_status_closed_values(status: str) -> None:
    assert _is_open_order_status(status) is False


def test_first_float_returns_first_parseable_value() -> None:
    assert _first_float(None, "bad", "2.5", 3) == pytest.approx(2.5)
    assert _first_float(None, {}, []) is None


def test_as_float_edge_cases() -> None:
    assert _as_float(None) is None
    assert _as_float("12.34") == pytest.approx(12.34)
    assert _as_float(7) == pytest.approx(7.0)
    assert _as_float(" ") is None
    assert _as_float({"value": "1"}) is None
    parsed_nan = _as_float("nan")
    assert parsed_nan is not None and math.isnan(parsed_nan)


def test_chunks() -> None:
    assert _chunks([], 3) == []
    assert _chunks(["A", "B", "C", "D", "E"], 2) == [["A", "B"], ["C", "D"], ["E"]]


def test_etrade_capabilities_include_new_features(tmp_path: Path) -> None:
    provider = ETradeProvider(_cfg(tmp_path))
    capabilities = provider.capabilities
    assert capabilities["option_chain"] is True
    assert capabilities["exposure"] is True
    assert capabilities["cancel_all"] is True
    assert capabilities["persistent_auth"] is True


def test_etrade_config_persistent_auth_field() -> None:
    assert ETradeConfig.model_validate({}).persistent_auth is False
    assert ETradeConfig.model_validate({"persistent_auth": True}).persistent_auth is True


def test_etrade_config_persistent_auth_env_override(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setenv("BROKER_ETRADE_PERSISTENT_AUTH", "true")
    merged = broker_config._apply_env_overrides({})  # noqa: SLF001
    cfg = ETradeConfig.model_validate(merged.get("etrade", {}))
    assert cfg.persistent_auth is True
