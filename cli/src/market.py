"""Market data commands."""

from __future__ import annotations

from enum import Enum
import json
import time

import typer

from _common import (
    build_typer,
    daemon_request,
    get_state,
    handle_error,
    parse_csv_items,
    print_output,
    run_async,
    validate_allowed_values,
)
from broker_daemon.exceptions import BrokerError

app = build_typer("Market data commands (`quote`, `watch`, `chain`, `history`).")


class HistoryPeriod(str, Enum):
    D1 = "1d"
    D5 = "5d"
    D30 = "30d"
    D90 = "90d"
    Y1 = "1y"


class BarSize(str, Enum):
    M1 = "1m"
    M5 = "5m"
    M15 = "15m"
    H1 = "1h"
    D1 = "1d"


class OptionType(str, Enum):
    CALL = "call"
    PUT = "put"


class QuoteIntent(str, Enum):
    BEST_EFFORT = "best_effort"
    TOP_OF_BOOK = "top_of_book"
    LAST_ONLY = "last_only"


WATCH_FIELDS = {"symbol", "bid", "ask", "last", "volume", "timestamp", "exchange", "currency"}
QUOTE_VALUE_FIELDS = ("bid", "ask", "last", "volume")


@app.command("quote", help="Snapshot quote(s) for one or more symbols.")
def quote(
    ctx: typer.Context,
    symbols: list[str] = typer.Argument(
        ...,
        metavar="SYMBOL...",
        help="One or more symbols. Example: AAPL MSFT GOOG",
    ),
    intent: QuoteIntent | None = typer.Option(
        None,
        "--intent",
        case_sensitive=False,
        help="Quote intent: best_effort, top_of_book, last_only.",
    ),
) -> None:
    state = get_state(ctx)
    try:
        params: dict[str, object] = {"symbols": symbols}
        if intent is not None:
            params["intent"] = intent.value
        data = run_async(daemon_request(state, "quote.snapshot", params))
        quotes = data.get("quotes", [])
        if isinstance(quotes, list):
            _warn_on_quote_results(
                quotes,
                provider=state.config.provider,
                intent=str(data.get("intent") or state.config.market_data.quote_intent_default),
                provider_capabilities=data.get("provider_capabilities"),
            )
        print_output(quotes, json_output=state.json_output, title="Quotes")
    except BrokerError as exc:
        handle_error(exc, json_output=state.json_output)


@app.command("watch", help="Continuously refresh quote fields in the shell (Ctrl+C to stop).")
def watch(
    ctx: typer.Context,
    symbol: str,
    fields: str = typer.Option(
        "bid,ask,last,volume",
        "--fields",
        help="Comma-separated fields (bid,ask,last,volume,timestamp,exchange,currency,symbol).",
    ),
    interval: str = typer.Option("1s", "--interval", help="Refresh interval (e.g. 250ms, 1s, 2m)."),
    intent: QuoteIntent | None = typer.Option(
        None,
        "--intent",
        case_sensitive=False,
        help="Quote intent: best_effort, top_of_book, last_only.",
    ),
) -> None:
    state = get_state(ctx)
    interval_seconds = _parse_interval(interval)
    chosen_fields = _parse_fields(fields)

    try:
        while True:
            params: dict[str, object] = {"symbols": [symbol], "force": True}
            if intent is not None:
                params["intent"] = intent.value
            data = run_async(daemon_request(state, "quote.snapshot", params))
            quote = (data.get("quotes") or [{}])[0]
            row = {field: quote.get(field, "") for field in chosen_fields}
            print(json.dumps(row, default=str, separators=(",", ":")))
            time.sleep(interval_seconds)
    except KeyboardInterrupt:
        return
    except BrokerError as exc:
        handle_error(exc, json_output=state.json_output)


@app.command("chain", help="Fetch an option chain with optional expiry/strike filters.")
def chain(
    ctx: typer.Context,
    symbol: str,
    expiry: str | None = typer.Option(None, "--expiry", help="YYYY-MM"),
    strike_range: str | None = typer.Option(None, "--strike-range", help="0.8:1.2"),
    option_type: OptionType | None = typer.Option(None, "--type", case_sensitive=False, help="call|put"),
) -> None:
    state = get_state(ctx)
    params: dict[str, object] = {"symbol": symbol}
    if expiry:
        params["expiry"] = expiry
    if strike_range:
        params["strike_range"] = strike_range
    if option_type:
        params["type"] = option_type.value

    try:
        data = run_async(daemon_request(state, "market.chain", params))
        print_output(data, json_output=state.json_output)
    except BrokerError as exc:
        handle_error(exc, json_output=state.json_output)


@app.command("history", help="Fetch historical bars for a symbol.")
def history(
    ctx: typer.Context,
    symbol: str,
    period: HistoryPeriod = typer.Option(..., "--period", case_sensitive=False, help="1d, 5d, 30d, 90d, 1y"),
    bar: BarSize = typer.Option(..., "--bar", case_sensitive=False, help="1m, 5m, 15m, 1h, 1d"),
    rth_only: bool = typer.Option(False, "--rth-only", help="Restrict to regular trading hours."),
) -> None:
    state = get_state(ctx)
    try:
        data = run_async(
            daemon_request(
                state,
                "market.history",
                {
                    "symbol": symbol,
                    "period": period.value,
                    "bar": bar.value,
                    "rth_only": rth_only,
                },
            )
        )
        print_output(data.get("bars", []), json_output=state.json_output, title="History")
    except BrokerError as exc:
        handle_error(exc, json_output=state.json_output)


@app.command("capabilities", help="Show detected market-data capabilities for the connected provider.")
def capabilities(
    ctx: typer.Context,
    symbols: list[str] = typer.Argument(
        [],
        metavar="SYMBOL...",
        help="Optional symbols to evaluate (defaults from daemon config probe list).",
    ),
    refresh: bool = typer.Option(
        False,
        "--refresh",
        help="Force a fresh capability probe via provider API calls.",
    ),
) -> None:
    state = get_state(ctx)
    params: dict[str, object] = {"refresh": refresh}
    if symbols:
        params["symbols"] = symbols
    try:
        data = run_async(daemon_request(state, "market.capabilities", params))
        print_output(data.get("capabilities", data), json_output=state.json_output, title="Market Capabilities")
    except BrokerError as exc:
        handle_error(exc, json_output=state.json_output)


def _parse_interval(raw: str) -> float:
    text = raw.strip().lower()
    try:
        if text.endswith("ms"):
            seconds = float(text[:-2]) / 1000.0
        elif text.endswith("s"):
            seconds = float(text[:-1])
        elif text.endswith("m"):
            seconds = float(text[:-1]) * 60.0
        else:
            seconds = float(text)
    except ValueError as exc:
        raise typer.BadParameter(f"invalid interval '{raw}'. examples: 250ms, 1s, 2m") from exc

    if seconds <= 0:
        raise typer.BadParameter("interval must be greater than zero")
    return seconds


def _parse_fields(raw: str) -> list[str]:
    chosen = [item.lower() for item in parse_csv_items(raw, field_name="fields")]
    return validate_allowed_values(chosen, allowed=WATCH_FIELDS, field_name="fields")


def _warn_on_quote_results(
    quotes: list[dict[str, object]],
    *,
    provider: str,
    intent: str,
    provider_capabilities: object | None,
) -> None:
    symbols = _symbols_with_empty_quotes(quotes)
    if symbols:
        symbol_text = ", ".join(symbols)
        if provider == "ib":
            delayed_supported = _provider_supports(provider_capabilities, "delayed")
            delayed_text = "Delayed fallback appears unavailable for this session/account." if not delayed_supported else ""
            typer.echo(
                f"No quote data returned for {symbol_text} (bid/ask/last/volume are null). "
                "Verify IBKR market-data permissions/subscriptions for the requested symbol. "
                f"{delayed_text}".strip(),
                err=True,
            )
            return
        typer.echo(
            f"No quote data returned for {symbol_text} (bid/ask/last/volume are null). "
            "Verify symbol validity and provider market-data permissions.",
            err=True,
        )
        return

    if intent == QuoteIntent.TOP_OF_BOOK.value:
        partial = _symbols_with_missing_top_of_book(quotes)
        if partial:
            typer.echo(
                f"Top-of-book data is incomplete for {', '.join(partial)} (bid and/or ask is null).",
                err=True,
            )
            return

    if intent == QuoteIntent.BEST_EFFORT.value:
        last_only_symbols = _symbols_with_last_only(quotes)
        if last_only_symbols and provider == "ib":
            typer.echo(
                f"Bid/ask unavailable for {', '.join(last_only_symbols)}; showing last price from available market data.",
                err=True,
            )


def _symbols_with_missing_top_of_book(quotes: list[dict[str, object]]) -> list[str]:
    symbols: list[str] = []
    for quote in quotes:
        if quote.get("bid") is None or quote.get("ask") is None:
            symbols.append(str(quote.get("symbol") or "?"))
    return list(dict.fromkeys(symbols))


def _symbols_with_last_only(quotes: list[dict[str, object]]) -> list[str]:
    symbols: list[str] = []
    for quote in quotes:
        has_last = quote.get("last") is not None
        missing_top = quote.get("bid") is None and quote.get("ask") is None
        if has_last and missing_top:
            symbols.append(str(quote.get("symbol") or "?"))
    return list(dict.fromkeys(symbols))


def _provider_supports(provider_capabilities: object | None, capability_name: str) -> bool:
    if not isinstance(provider_capabilities, dict):
        return True
    supports = provider_capabilities.get("supports")
    if not isinstance(supports, dict):
        return True
    value = supports.get(capability_name)
    return bool(value) if isinstance(value, bool) else True


def _symbols_with_empty_quotes(quotes: list[dict[str, object]]) -> list[str]:
    symbols: list[str] = []
    for quote in quotes:
        if all(quote.get(field) is None for field in QUOTE_VALUE_FIELDS):
            symbol = str(quote.get("symbol") or "?")
            symbols.append(symbol)
    return list(dict.fromkeys(symbols))
