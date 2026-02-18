"""Provider abstraction for broker integrations."""

from __future__ import annotations

from abc import ABC, abstractmethod
from datetime import datetime
from typing import Any

from pydantic import BaseModel

from broker_daemon.models.market import Bar, OptionChain, ProviderQuoteCapabilities, Quote, QuoteIntent
from broker_daemon.models.orders import FillRecord, OrderRequest
from broker_daemon.models.portfolio import Balance, ExposureEntry, PnLSummary, Position


class ConnectionStatus(BaseModel):
    connected: bool
    host: str
    port: int
    client_id: int
    connected_at: datetime | None = None
    server_version: int | None = None
    account_id: str | None = None
    last_error: str | None = None


class BrokerProvider(ABC):
    @property
    def capabilities(self) -> dict[str, bool]:
        return {
            "history": False,
            "option_chain": False,
            "exposure": False,
            "bracket_orders": False,
            "streaming": False,
            "cancel_all": False,
            "persistent_auth": False,
            "quote_live": False,
            "quote_delayed": False,
            "quote_delayed_frozen": False,
        }

    @abstractmethod
    async def start(self) -> None:
        raise NotImplementedError

    @abstractmethod
    async def stop(self) -> None:
        raise NotImplementedError

    @abstractmethod
    async def ensure_connected(self) -> None:
        raise NotImplementedError

    @abstractmethod
    def status(self) -> ConnectionStatus:
        raise NotImplementedError

    @property
    @abstractmethod
    def is_connected(self) -> bool:
        raise NotImplementedError

    @abstractmethod
    async def quote(self, symbols: list[str], *, intent: QuoteIntent = "best_effort") -> list[Quote]:
        raise NotImplementedError

    async def quote_capabilities(
        self,
        symbols: list[str],
        *,
        refresh: bool = False,
    ) -> ProviderQuoteCapabilities:
        _ = refresh
        return ProviderQuoteCapabilities(
            provider=self.__class__.__name__.replace("Provider", "").lower(),
            supports={
                "live": True,
                "delayed": False,
                "delayed_frozen": False,
            },
            symbols={},
        )

    async def history(self, symbol: str, period: str, bar: str, rth_only: bool) -> list[Bar]:
        raise NotImplementedError

    async def option_chain(
        self,
        symbol: str,
        expiry_prefix: str | None,
        strike_range: tuple[float, float] | None,
        option_type: str | None,
    ) -> OptionChain:
        raise NotImplementedError

    @abstractmethod
    async def positions(self) -> list[Position]:
        raise NotImplementedError

    @abstractmethod
    async def balance(self) -> Balance:
        raise NotImplementedError

    @abstractmethod
    async def pnl(self) -> PnLSummary:
        raise NotImplementedError

    async def exposure(self, by: str) -> list[ExposureEntry]:
        raise NotImplementedError

    @abstractmethod
    async def place_order(self, order: OrderRequest, client_order_id: str) -> dict[str, Any]:
        raise NotImplementedError

    async def place_bracket(
        self,
        *,
        side: str,
        symbol: str,
        qty: float,
        entry: float,
        tp: float,
        sl: float,
        tif: str,
        client_order_id: str,
    ) -> dict[str, Any]:
        raise NotImplementedError

    @abstractmethod
    async def cancel_order(self, client_order_id: str | None = None, ib_order_id: int | None = None) -> dict[str, Any]:
        raise NotImplementedError

    async def cancel_all(self) -> dict[str, Any]:
        raise NotImplementedError

    @abstractmethod
    async def trades(self) -> list[dict[str, Any]]:
        raise NotImplementedError

    @abstractmethod
    async def fills(self) -> list[FillRecord]:
        raise NotImplementedError
