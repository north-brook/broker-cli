"""Market-data domain models."""

from __future__ import annotations

from datetime import UTC, datetime
from typing import Literal

from pydantic import BaseModel, Field

QuoteIntent = Literal["best_effort", "top_of_book", "last_only"]
QUOTE_INTENTS: tuple[QuoteIntent, ...] = ("best_effort", "top_of_book", "last_only")


class QuoteFieldAvailability(BaseModel):
    bid: bool = False
    ask: bool = False
    last: bool = False
    volume: bool = False


class QuoteMeta(BaseModel):
    source: str = "live"
    market_data_type: int | None = None
    fallback_used: bool = False
    fields: QuoteFieldAvailability = Field(default_factory=QuoteFieldAvailability)


class Quote(BaseModel):
    symbol: str
    bid: float | None = None
    ask: float | None = None
    last: float | None = None
    volume: float | None = None
    timestamp: datetime = Field(default_factory=lambda: datetime.now(UTC))
    exchange: str | None = None
    currency: str = "USD"
    meta: QuoteMeta | None = None


class QuoteCapabilitySnapshot(BaseModel):
    symbol: str
    fields: QuoteFieldAvailability = Field(default_factory=QuoteFieldAvailability)
    source: str | None = None
    market_data_type: int | None = None
    updated_at: datetime | None = None


class ProviderQuoteCapabilities(BaseModel):
    provider: str
    supports: dict[str, bool] = Field(default_factory=dict)
    symbols: dict[str, QuoteCapabilitySnapshot] = Field(default_factory=dict)
    updated_at: datetime = Field(default_factory=lambda: datetime.now(UTC))


class Bar(BaseModel):
    symbol: str
    time: datetime
    open: float
    high: float
    low: float
    close: float
    volume: float


class OptionChainEntry(BaseModel):
    symbol: str
    right: str
    strike: float
    expiry: str
    bid: float | None = None
    ask: float | None = None
    implied_vol: float | None = None
    delta: float | None = None
    gamma: float | None = None
    theta: float | None = None
    vega: float | None = None


class OptionChain(BaseModel):
    symbol: str
    underlying_price: float | None = None
    entries: list[OptionChainEntry] = Field(default_factory=list)
