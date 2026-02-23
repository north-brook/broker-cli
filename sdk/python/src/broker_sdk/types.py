"""Shared Python SDK type aliases and discoverable constants."""

from __future__ import annotations

from typing import Literal, TypeAlias

ORDER_SIDES = ("buy", "sell")
TIME_IN_FORCE_VALUES = ("DAY", "GTC", "IOC")
HISTORY_PERIODS = ("1d", "5d", "30d", "90d", "1y")
BAR_SIZES = ("1m", "5m", "15m", "1h", "1d")
OPTION_TYPES = ("call", "put")
CHAIN_FIELDS = ("symbol", "right", "strike", "expiry", "bid", "ask", "implied_vol", "delta", "gamma", "theta", "vega")
QUOTE_INTENTS = ("best_effort", "top_of_book", "last_only")
ORDER_STATUS_FILTERS = ("active", "filled", "cancelled", "all")
EXPOSURE_GROUPS = ("sector", "asset_class", "currency", "symbol")
EVENT_TOPICS = ("orders", "fills", "positions", "pnl", "connection")
AUDIT_TABLES = ("orders", "commands")
AUDIT_SOURCES = ("cli", "sdk", "ts_sdk")

OrderSide: TypeAlias = Literal["buy", "sell"]
TimeInForce: TypeAlias = Literal["DAY", "GTC", "IOC"]
HistoryPeriod: TypeAlias = Literal["1d", "5d", "30d", "90d", "1y"]
BarSize: TypeAlias = Literal["1m", "5m", "15m", "1h", "1d"]
OptionType: TypeAlias = Literal["call", "put"]
ChainField: TypeAlias = Literal["symbol", "right", "strike", "expiry", "bid", "ask", "implied_vol", "delta", "gamma", "theta", "vega"]
QuoteIntent: TypeAlias = Literal["best_effort", "top_of_book", "last_only"]
OrderStatusFilter: TypeAlias = Literal["active", "filled", "cancelled", "all"]
ExposureGroupBy: TypeAlias = Literal["sector", "asset_class", "currency", "symbol"]
EventTopic: TypeAlias = Literal["orders", "fills", "positions", "pnl", "connection"]
AuditTable: TypeAlias = Literal["orders", "commands"]
AuditSource: TypeAlias = Literal["cli", "sdk", "ts_sdk"]
