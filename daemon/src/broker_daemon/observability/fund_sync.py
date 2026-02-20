"""Sync decisions and fills into a git-backed fund observability repository."""

from __future__ import annotations

import asyncio
from datetime import UTC, datetime
import json
import logging
from pathlib import Path
import subprocess
from typing import Any

from broker_daemon.config import ObservabilityConfig
from broker_daemon.models.orders import FillRecord, Side
from broker_daemon.providers.base import BrokerProvider

logger = logging.getLogger(__name__)

FUND_CONFIG = "config.json"
FUND_FILLS = "fills.json"
FUND_CASH_EVENTS = "cash_events.json"
FUND_DECISIONS_DIR = "decisions"


def _utc_now() -> datetime:
    return datetime.now(UTC)


def _iso_utc(ts: datetime | None = None) -> str:
    return (ts or _utc_now()).isoformat()


def _decision_timestamp_id(ts: datetime | None = None) -> str:
    return (ts or _utc_now()).strftime("%Y%m%dT%H%M%S%fZ")


def _safe_float(value: Any, *, default: float = 0.0) -> float:
    try:
        return float(value)
    except Exception:
        return default


def _yaml_quoted(value: str) -> str:
    # JSON quoted strings are valid YAML scalar strings.
    return json.dumps(value)


class FundSyncService:
    """Handles append-only observability file writes and git push behavior."""

    def __init__(self, cfg: ObservabilityConfig, *, provider: BrokerProvider | None = None) -> None:
        self._cfg = cfg
        self._provider = provider
        self._fund_dir = cfg.fund_dir
        self._lock = asyncio.Lock()

    @property
    def enabled(self) -> bool:
        return bool(self._cfg.auto_sync and self._fund_dir)

    async def sync_decision(
        self,
        *,
        decision_id: str,
        symbol: str,
        side: Side,
        title: str,
        summary: str,
        reasoning_markdown: str,
        created_at: datetime | None = None,
    ) -> None:
        if not self.enabled:
            return
        assert self._fund_dir is not None

        try:
            async with self._lock:
                self._ensure_repo_layout()
                decision_file = self._fund_dir / FUND_DECISIONS_DIR / f"{decision_id}.md"
                body = self._decision_markdown(
                    symbol=symbol,
                    side=side,
                    title=title,
                    summary=summary,
                    reasoning_markdown=reasoning_markdown,
                    created_at=created_at,
                )
                changed = self._write_if_changed(decision_file, body)
                if changed:
                    await self._commit_and_push(
                        message=f"decision: {decision_id}",
                        changed_paths=[decision_file],
                    )
        except Exception:
            logger.exception("fund sync: failed to sync decision %s", decision_id)

    async def sync_fill(self, fill: FillRecord) -> None:
        if not self.enabled:
            return
        assert self._fund_dir is not None

        try:
            async with self._lock:
                self._ensure_repo_layout()
                fills_path = self._fund_dir / FUND_FILLS
                rows = self._read_json_array(fills_path)
                if any(str(row.get("id", "")).strip() == fill.fill_id for row in rows):
                    return

                side = self._normalize_side(fill.side)
                rows.append(
                    {
                        "id": fill.fill_id,
                        "symbol": fill.symbol,
                        "side": side,
                        "qty": float(fill.qty),
                        "price": float(fill.price),
                        "commission": float(fill.commission) if fill.commission is not None else 0.0,
                        "timestamp": _iso_utc(fill.timestamp),
                        "decisionId": fill.decision_id,
                    }
                )
                self._write_json_atomic(fills_path, rows)

                changed_paths = [fills_path]
                if await self._sync_interest_from_balance_locked():
                    changed_paths.append(self._fund_dir / FUND_CASH_EVENTS)

                await self._commit_and_push(
                    message=f"fill: {fill.fill_id}",
                    changed_paths=changed_paths,
                )
        except Exception:
            logger.exception("fund sync: failed to sync fill %s", fill.fill_id)

    def _ensure_repo_layout(self) -> None:
        assert self._fund_dir is not None
        self._fund_dir.mkdir(parents=True, exist_ok=True)
        (self._fund_dir / FUND_DECISIONS_DIR).mkdir(parents=True, exist_ok=True)
        self._ensure_json_array_file(self._fund_dir / FUND_FILLS)
        self._ensure_json_array_file(self._fund_dir / FUND_CASH_EVENTS)

    def _ensure_json_array_file(self, path: Path) -> None:
        if path.exists():
            return
        self._write_json_atomic(path, [])

    def _read_json_array(self, path: Path) -> list[dict[str, Any]]:
        if not path.exists():
            return []
        try:
            loaded = json.loads(path.read_text(encoding="utf-8"))
        except Exception:
            return []
        if not isinstance(loaded, list):
            return []
        return [row for row in loaded if isinstance(row, dict)]

    def _read_json_object(self, path: Path) -> dict[str, Any]:
        if not path.exists():
            return {}
        try:
            loaded = json.loads(path.read_text(encoding="utf-8"))
        except Exception:
            return {}
        if not isinstance(loaded, dict):
            return {}
        return loaded

    def _write_if_changed(self, path: Path, content: str) -> bool:
        existing = ""
        if path.exists():
            existing = path.read_text(encoding="utf-8")
        if existing == content:
            return False
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(content, encoding="utf-8")
        return True

    def _write_json_atomic(self, path: Path, payload: Any) -> None:
        path.parent.mkdir(parents=True, exist_ok=True)
        tmp_path = path.with_name(f".{path.name}.tmp")
        tmp_path.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
        tmp_path.replace(path)

    def _decision_markdown(
        self,
        *,
        symbol: str,
        side: Side,
        title: str,
        summary: str,
        reasoning_markdown: str,
        created_at: datetime | None = None,
    ) -> str:
        ts = created_at or _utc_now()
        date_text = ts.date().isoformat()
        reasoning = reasoning_markdown.strip()
        if not reasoning:
            reasoning = "_No decision reasoning provided._"
        return (
            "---\n"
            f"date: {date_text}\n"
            f"type: {side.value}\n"
            f"tickers: [{symbol.upper()}]\n"
            f"title: {_yaml_quoted(title.strip())}\n"
            f"summary: {_yaml_quoted(summary.strip())}\n"
            "---\n\n"
            f"{reasoning}\n"
        )

    def _normalize_side(self, side: Side | None) -> str:
        if side == Side.SELL:
            return "sell"
        return "buy"

    async def _sync_interest_from_balance_locked(self) -> bool:
        if self._provider is None:
            return False
        assert self._fund_dir is not None

        try:
            balance = await self._provider.balance()
        except Exception:
            return False

        if balance.cash is None:
            return False

        config_path = self._fund_dir / FUND_CONFIG
        config = self._read_json_object(config_path)
        initial_capital = _safe_float(config.get("initialCapital"), default=0.0)

        fills = self._read_json_array(self._fund_dir / FUND_FILLS)
        trade_cash_delta = 0.0
        for row in fills:
            qty = _safe_float(row.get("qty"))
            price = _safe_float(row.get("price"))
            commission = _safe_float(row.get("commission"))
            side = str(row.get("side", "")).strip().lower()
            if side == "sell":
                trade_cash_delta += qty * price
            else:
                trade_cash_delta -= qty * price
            trade_cash_delta -= commission

        expected_cash_without_interest = initial_capital + trade_cash_delta
        inferred_total_interest = float(balance.cash) - expected_cash_without_interest

        cash_events_path = self._fund_dir / FUND_CASH_EVENTS
        cash_events = self._read_json_array(cash_events_path)
        known_interest = sum(
            _safe_float(event.get("amount"))
            for event in cash_events
            if str(event.get("type", "")).strip().lower() == "interest"
        )
        delta_interest = round(inferred_total_interest - known_interest, 2)
        if abs(delta_interest) < 0.01:
            return False

        ts = _utc_now()
        cash_events.append(
            {
                "id": f"interest-{_decision_timestamp_id(ts)}",
                "type": "interest",
                "amount": delta_interest,
                "timestamp": _iso_utc(ts),
                "source": "inferred_from_broker_cash_balance",
            }
        )
        self._write_json_atomic(cash_events_path, cash_events)
        return True

    async def _commit_and_push(self, *, message: str, changed_paths: list[Path]) -> None:
        if not changed_paths:
            return
        if not self._is_git_repo():
            logger.warning("fund sync: %s is not a git repository; skipping commit/push", self._fund_dir)
            return

        rel_paths = [str(path.relative_to(self._fund_dir)) for path in changed_paths if path.exists()]
        if not rel_paths:
            return

        await asyncio.to_thread(self._run_git_checked, "add", "--", *rel_paths)
        staged = await asyncio.to_thread(self._run_git, "diff", "--cached", "--quiet", "--")
        if staged.returncode == 0:
            return
        if staged.returncode not in {0, 1}:
            raise RuntimeError(f"git diff --cached failed: {staged.stderr.strip()}")

        await asyncio.to_thread(self._run_git_checked, "commit", "-m", message)

        if not self._cfg.auto_push:
            return

        has_origin = await asyncio.to_thread(self._run_git, "remote", "get-url", "origin")
        if has_origin.returncode != 0:
            logger.warning("fund sync: remote 'origin' is not configured; skipping push")
            return
        await asyncio.to_thread(self._run_git_checked, "push", "origin", "HEAD")

    def _is_git_repo(self) -> bool:
        result = self._run_git("rev-parse", "--is-inside-work-tree")
        return result.returncode == 0 and result.stdout.strip() == "true"

    def _run_git_checked(self, *args: str) -> subprocess.CompletedProcess[str]:
        result = self._run_git(*args)
        if result.returncode != 0:
            stderr = result.stderr.strip()
            stdout = result.stdout.strip()
            details = stderr or stdout or "unknown git error"
            raise RuntimeError(f"git {' '.join(args)} failed: {details}")
        return result

    def _run_git(self, *args: str) -> subprocess.CompletedProcess[str]:
        assert self._fund_dir is not None
        return subprocess.run(
            ["git", "-C", str(self._fund_dir), *args],
            check=False,
            capture_output=True,
            text=True,
        )
