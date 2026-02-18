"""Market-data cache and polling helpers."""

from __future__ import annotations

import asyncio
from datetime import UTC, datetime, timedelta
from typing import AsyncIterator

from broker_daemon.config import MarketDataConfig
from broker_daemon.models.market import ProviderQuoteCapabilities, Quote, QuoteFieldAvailability, QuoteIntent, QuoteMeta
from broker_daemon.providers import BrokerProvider


class MarketDataService:
    def __init__(
        self,
        provider: BrokerProvider,
        *,
        settings: MarketDataConfig,
        cache_ttl_seconds: int = 2,
    ) -> None:
        self._provider = provider
        self._settings = settings
        self._cache_ttl = timedelta(seconds=cache_ttl_seconds)
        self._quotes: dict[str, Quote] = {}
        self._updated_at: dict[str, datetime] = {}
        self._capabilities_cache: ProviderQuoteCapabilities | None = None
        self._capabilities_cached_at: datetime | None = None
        self._capabilities_ttl = timedelta(seconds=settings.capability_ttl_seconds)

    async def quote(
        self,
        symbols: list[str],
        *,
        force_refresh: bool = False,
        intent: QuoteIntent = "best_effort",
    ) -> list[Quote]:
        now = datetime.now(UTC)
        uncached: list[str] = []
        for symbol in symbols:
            sym = symbol.upper()
            cached_at = self._updated_at.get(sym)
            if force_refresh or cached_at is None or now - cached_at > self._cache_ttl:
                uncached.append(sym)

        if uncached:
            fresh = await self._provider.quote(uncached, intent=intent)
            if intent in {"best_effort", "last_only"} and self._settings.allow_history_last_fallback:
                fresh = await self._apply_last_price_history_fallback(fresh)
            for quote in fresh:
                self._quotes[quote.symbol] = quote
                self._updated_at[quote.symbol] = now

            self._capabilities_cached_at = None

        result: list[Quote] = []
        for symbol in symbols:
            sym = symbol.upper()
            quote = self._quotes.get(sym)
            if quote is not None:
                result.append(quote)
        return result

    async def watch(self, symbol: str, fields: list[str], interval_seconds: float) -> AsyncIterator[dict[str, float | None]]:
        sym = symbol.upper()
        while True:
            quotes = await self.quote([sym], force_refresh=True, intent=self._settings.quote_intent_default)
            if quotes:
                q = quotes[0]
                yield {field: getattr(q, field, None) for field in fields}
            await asyncio.sleep(interval_seconds)

    async def quote_capabilities(
        self,
        symbols: list[str] | None = None,
        *,
        refresh: bool = False,
    ) -> ProviderQuoteCapabilities:
        requested = [s.upper().strip() for s in (symbols or self._settings.probe_symbols) if s.strip()]
        now = datetime.now(UTC)
        cache_is_valid = (
            not refresh
            and self._capabilities_cache is not None
            and self._capabilities_cached_at is not None
            and now - self._capabilities_cached_at <= self._capabilities_ttl
        )

        if not cache_is_valid:
            self._capabilities_cache = await self._provider.quote_capabilities(requested, refresh=refresh)
            self._capabilities_cached_at = now
            return self._capabilities_cache

        if self._capabilities_cache is None:
            self._capabilities_cache = await self._provider.quote_capabilities(requested, refresh=refresh)
            self._capabilities_cached_at = now
            return self._capabilities_cache

        missing = [symbol for symbol in requested if symbol not in self._capabilities_cache.symbols]
        if missing:
            refreshed = await self._provider.quote_capabilities(missing, refresh=True)
            merged_symbols = dict(self._capabilities_cache.symbols)
            merged_symbols.update(refreshed.symbols)
            self._capabilities_cache = ProviderQuoteCapabilities(
                provider=refreshed.provider or self._capabilities_cache.provider,
                supports=dict(refreshed.supports or self._capabilities_cache.supports),
                symbols=merged_symbols,
                updated_at=refreshed.updated_at,
            )
            self._capabilities_cached_at = now
        return self._capabilities_cache

    async def _apply_last_price_history_fallback(self, quotes: list[Quote]) -> list[Quote]:
        if not self._provider.capabilities.get("history"):
            return quotes

        symbols_missing_last = [quote.symbol for quote in quotes if quote.last is None]
        if not symbols_missing_last:
            return quotes

        filled: dict[str, Quote] = {}
        for symbol in symbols_missing_last:
            try:
                bars = await self._provider.history(symbol=symbol, period="1d", bar="1m", rth_only=False)
            except Exception:
                continue
            if not bars:
                continue
            last_bar = bars[-1]
            filled_quote = next((quote for quote in quotes if quote.symbol == symbol), None)
            if filled_quote is None:
                continue
            if filled_quote.last is None:
                filled_quote.last = last_bar.close
                filled_quote.timestamp = last_bar.time
                if filled_quote.meta is None:
                    filled_quote.meta = QuoteMeta(
                        source="history",
                        fallback_used=True,
                        fields=QuoteFieldAvailability(last=True),
                    )
                else:
                    filled_quote.meta.source = "history"
                    filled_quote.meta.fallback_used = True
                    filled_quote.meta.fields.last = True
            filled[symbol] = filled_quote

        if not filled:
            return quotes
        return [filled.get(quote.symbol, quote) for quote in quotes]
