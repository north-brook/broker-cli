import type { JsonValue } from "./types.js";

export const ORDER_SIDES = ["buy", "sell"] as const;
export const TIME_IN_FORCE_VALUES = ["DAY", "GTC", "IOC"] as const;
export const HISTORY_PERIODS = ["1d", "5d", "30d", "90d", "1y"] as const;
export const BAR_SIZES = ["1m", "5m", "15m", "1h", "1d"] as const;
export const OPTION_TYPES = ["call", "put"] as const;
export const CHAIN_FIELDS = ["symbol", "right", "strike", "expiry", "bid", "ask", "implied_vol", "delta", "gamma", "theta", "vega"] as const;
export const QUOTE_INTENTS = ["best_effort", "top_of_book", "last_only"] as const;
export const ORDER_STATUS_FILTERS = ["active", "filled", "cancelled", "all"] as const;
export const EXPOSURE_GROUPS = ["sector", "asset_class", "currency", "symbol"] as const;
export const EVENT_TOPICS = ["orders", "fills", "positions", "pnl", "connection"] as const;
export const AUDIT_TABLES = ["orders", "commands"] as const;
export const AUDIT_SOURCES = ["cli", "sdk", "ts_sdk"] as const;

export type OrderSide = (typeof ORDER_SIDES)[number];
export type TimeInForce = (typeof TIME_IN_FORCE_VALUES)[number];
export type HistoryPeriod = (typeof HISTORY_PERIODS)[number];
export type BarSize = (typeof BAR_SIZES)[number];
export type OptionType = (typeof OPTION_TYPES)[number];
export type ChainField = (typeof CHAIN_FIELDS)[number];
export type QuoteIntent = (typeof QUOTE_INTENTS)[number];
export type OrderStatusFilter = (typeof ORDER_STATUS_FILTERS)[number];
export type ExposureGroupBy = (typeof EXPOSURE_GROUPS)[number];
export type EventTopic = (typeof EVENT_TOPICS)[number];
export type AuditTable = (typeof AUDIT_TABLES)[number];
export type AuditSource = (typeof AUDIT_SOURCES)[number];

export interface Quote {
  symbol: string;
  bid: number | null;
  ask: number | null;
  last: number | null;
  volume: number | null;
  timestamp: string;
  exchange: string | null;
  currency: string;
  meta?: QuoteMeta | null;
}

export interface QuoteFieldAvailability {
  bid: boolean;
  ask: boolean;
  last: boolean;
  volume: boolean;
}

export interface QuoteMeta {
  source: string;
  market_data_type: number | null;
  fallback_used: boolean;
  fields: QuoteFieldAvailability;
}

export interface QuoteCapabilitySnapshot {
  symbol: string;
  fields: QuoteFieldAvailability;
  source: string | null;
  market_data_type: number | null;
  updated_at: string | null;
}

export interface ProviderQuoteCapabilities {
  provider: string;
  supports: Record<string, boolean>;
  symbols: Record<string, QuoteCapabilitySnapshot>;
  updated_at: string;
}

export interface CapabilityCacheMeta {
  refresh_requested: boolean;
  cache_hit: boolean;
  cache_age_ms: number | null;
  cache_ttl_ms: number;
  refreshed_at: string | null;
}

export interface Bar {
  symbol: string;
  time: string;
  open: number;
  high: number;
  low: number;
  close: number;
  volume: number;
}

export interface OptionChainEntry {
  symbol: string;
  right: "C" | "P";
  strike: number;
  expiry: string;
  bid?: number | null;
  ask?: number | null;
  implied_vol?: number | null;
  delta?: number | null;
  gamma?: number | null;
  theta?: number | null;
  vega?: number | null;
}

export interface OptionChainResponse {
  symbol: string;
  underlying_price: number | null;
  entries: OptionChainEntry[];
  pagination?: {
    total_entries: number;
    offset: number;
    limit: number;
    returned_entries: number;
  };
  fields?: string[];
}

export interface Position {
  symbol: string;
  qty: number;
  avg_cost: number;
  market_price: number | null;
  market_value: number | null;
  unrealized_pnl: number | null;
  realized_pnl: number | null;
  currency: string;
}

export interface Balance {
  account_id: string | null;
  net_liquidation: number | null;
  cash: number | null;
  buying_power: number | null;
  margin_used: number | null;
  margin_available: number | null;
  currency: string;
}

export interface PnLSummary {
  date: string;
  realized: number;
  unrealized: number;
  total: number;
}

export interface ExposureEntry {
  key: string;
  exposure_value: number;
  exposure_pct: number;
}

export interface OrderRecord {
  client_order_id: string;
  ib_order_id: number | null;
  symbol: string;
  side: OrderSide;
  qty: number;
  order_type: string;
  limit_price: number | null;
  stop_price: number | null;
  tif: TimeInForce;
  status: string;
  submitted_at: string;
  filled_at: string | null;
  fill_price: number | null;
  fill_qty: number;
  commission: number | null;
}

export interface FillRecord {
  fill_id: string;
  client_order_id: string;
  ib_order_id: number | null;
  symbol: string;
  side?: OrderSide | null;
  qty: number;
  price: number;
  commission?: number | null;
  timestamp: string;
  decision_id?: string | null;
}

export interface DaemonStatusResponse {
  uptime_seconds: number;
  connection: {
    connected: boolean;
    host: string;
    port: number;
    client_id: number;
    connected_at: string | null;
    server_version: number | null;
    account_id: string | null;
    last_error: string | null;
  };
  provider_capabilities: Record<string, boolean>;
  time_sync_delta_ms: number | null;
  socket: string;
}

export interface DaemonStopResponse {
  stopping: boolean;
}

export interface QuoteSnapshotResponse {
  quotes: Quote[];
  intent?: QuoteIntent;
  provider_capabilities?: ProviderQuoteCapabilities;
  provider_capabilities_cache?: CapabilityCacheMeta;
}

export interface MarketCapabilitiesResponse {
  capabilities: ProviderQuoteCapabilities;
  cache: CapabilityCacheMeta;
}

export interface MarketHistoryResponse {
  bars: Bar[];
}

export interface PortfolioPositionsResponse {
  positions: Position[];
}

export interface PortfolioBalanceResponse {
  balance: Balance;
}

export interface PortfolioPnLResponse {
  pnl: PnLSummary;
}

export interface PortfolioExposureResponse {
  exposure: ExposureEntry[];
  by: string;
}

export interface PortfolioSnapshotResponse {
  timestamp: string;
  symbols: string[];
  quotes: Quote[];
  positions: Position[];
  balance: Balance;
  pnl: PnLSummary;
  exposure: ExposureEntry[];
  exposure_by: string;
  connection: DaemonStatusResponse["connection"];
  provider_capabilities: ProviderQuoteCapabilities;
  provider_capabilities_cache: CapabilityCacheMeta;
}

export interface OrderPlaceResponse {
  order: OrderRecord;
  dry_run: boolean;
}

export interface OrderBracketResponse {
  client_order_id: string;
  ib_order_ids: number[];
  status: string;
}

export interface OrderStatusResponse {
  order: OrderRecord | Record<string, JsonValue>;
}

export interface OrdersListResponse {
  orders: Array<OrderRecord | Record<string, JsonValue>>;
}

export interface OrderCancelResponse {
  client_order_id?: string;
  cancelled: boolean;
  ib_order_id?: number | null;
}

export interface OrdersCancelAllResponse {
  cancelled: boolean;
}

export interface FillsListResponse {
  fills: FillRecord[];
}

export interface KeepaliveResponse {
  ok: boolean;
  latency_ms: number | null;
  connected: boolean;
}

export interface AuditCommandsRow {
  timestamp: string;
  source: string;
  command: string;
  arguments: string;
  result_code: number;
  request_id?: string | null;
}

export interface AuditOrdersRow {
  id: number;
  client_order_id: string;
  ib_order_id: number | null;
  symbol: string;
  side: string;
  qty: number;
  order_type: string;
  limit_price: number | null;
  stop_price: number | null;
  tif: string;
  status: string;
  submitted_at: string;
  filled_at: string | null;
  fill_price: number | null;
  fill_qty: number | null;
  commission: number | null;
}

export interface AuditCommandsResponse {
  commands: AuditCommandsRow[];
}

export interface AuditOrdersResponse {
  orders: AuditOrdersRow[];
}

export interface AuditExportResponse {
  output: string;
  rows: number;
}

export interface EventPayload {
  topic: string;
  data: Record<string, JsonValue>;
  request_id?: string | null;
}

export interface OrderInput {
  side: OrderSide;
  symbol: string;
  qty: number;
  limit?: number;
  stop?: number;
  tif?: TimeInForce;
  client_order_id?: string;
  idempotency_key?: string;
  dry_run?: boolean;
  decision_name?: string;
  decision_summary?: string;
  decision_reasoning?: string;
}

export interface BracketInput {
  side: OrderSide;
  symbol: string;
  qty: number;
  entry: number;
  tp: number;
  sl: number;
  tif?: TimeInForce;
  decision_name?: string;
  decision_summary?: string;
  decision_reasoning?: string;
}

