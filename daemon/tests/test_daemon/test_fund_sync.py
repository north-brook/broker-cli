from __future__ import annotations

import json
from pathlib import Path

import pytest

from broker_daemon.config import ObservabilityConfig
from broker_daemon.models.orders import FillRecord, Side
from broker_daemon.models.portfolio import Balance
from broker_daemon.observability.fund_sync import FundSyncService


class _FakeProvider:
    async def balance(self) -> Balance:
        return Balance(cash=1_000.0, net_liquidation=1_000.0)


@pytest.mark.asyncio
async def test_sync_decision_and_fill_writes_expected_files(tmp_path: Path) -> None:
    fund_dir = tmp_path / "fund-atlas"
    fund_dir.mkdir(parents=True)
    (fund_dir / "config.json").write_text(
        json.dumps(
            {
                "name": "Atlas Fund",
                "slug": "atlas",
                "inception": "2026-02-20T00:00:00Z",
                "currency": "USD",
                "initialCapital": 1000.0,
                "benchmarks": [],
            }
        )
        + "\n",
        encoding="utf-8",
    )

    sync = FundSyncService(
        ObservabilityConfig(
            fund_dir=fund_dir,
            auto_sync=True,
            auto_push=False,
        ),
        provider=_FakeProvider(),
    )

    await sync.sync_decision(
        decision_id="20260220T120000000000Z",
        symbol="AAPL",
        side=Side.BUY,
        title="Initiate AAPL Position",
        summary="Start a core position",
        reasoning_markdown="## Thesis\nBuy quality compounder.",
    )

    await sync.sync_fill(
        FillRecord(
            fill_id="fill-1",
            client_order_id="cid-1",
            ib_order_id=101,
            symbol="AAPL",
            side=Side.BUY,
            qty=2,
            price=100.0,
            commission=1.0,
            decision_id="20260220T120000000000Z",
        )
    )

    decision_file = fund_dir / "decisions" / "20260220T120000000000Z.md"
    assert decision_file.exists()
    assert "Initiate AAPL Position" in decision_file.read_text(encoding="utf-8")

    fills = json.loads((fund_dir / "fills.json").read_text(encoding="utf-8"))
    assert len(fills) == 1
    assert fills[0]["id"] == "fill-1"
    assert fills[0]["side"] == "buy"
    assert fills[0]["decisionId"] == "20260220T120000000000Z"

    cash_events = json.loads((fund_dir / "cash_events.json").read_text(encoding="utf-8"))
    assert cash_events
    assert cash_events[0]["type"] == "interest"


@pytest.mark.asyncio
async def test_sync_fill_deduplicates_by_fill_id(tmp_path: Path) -> None:
    fund_dir = tmp_path / "fund-atlas"
    fund_dir.mkdir(parents=True)
    (fund_dir / "config.json").write_text(
        json.dumps({"initialCapital": 1000.0}) + "\n",
        encoding="utf-8",
    )

    sync = FundSyncService(
        ObservabilityConfig(
            fund_dir=fund_dir,
            auto_sync=True,
            auto_push=False,
        ),
        provider=_FakeProvider(),
    )

    fill = FillRecord(
        fill_id="fill-dup",
        client_order_id="cid-dup",
        ib_order_id=11,
        symbol="MSFT",
        side=Side.SELL,
        qty=1.0,
        price=200.0,
    )
    await sync.sync_fill(fill)
    await sync.sync_fill(fill)

    rows = json.loads((fund_dir / "fills.json").read_text(encoding="utf-8"))
    assert len(rows) == 1
    assert rows[0]["id"] == "fill-dup"
