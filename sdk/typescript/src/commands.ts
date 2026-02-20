import type { JsonValue } from "./types.js";
import type {
  EventTopic,
  KeepaliveResponse,
  AuditSource,
  AuditCommandsResponse,
  AuditExportResponse,
  AuditTable,
  AuditOrdersResponse,
  AuditRiskResponse,
  BarSize,
  DaemonStatusResponse,
  DaemonStopResponse,
  ExposureGroupBy,
  FillsListResponse,
  HistoryPeriod,
  MarketHistoryResponse,
  MarketCapabilitiesResponse,
  ChainField,
  OptionType,
  OptionChainResponse,
  OrderBracketResponse,
  OrderCancelResponse,
  OrderSide,
  OrderPlaceResponse,
  OrderStatusFilter,
  OrderStatusResponse,
  OrdersCancelAllResponse,
  OrdersListResponse,
  PortfolioBalanceResponse,
  PortfolioExposureResponse,
  PortfolioPnLResponse,
  PortfolioPositionsResponse,
  PortfolioSnapshotResponse,
  QuoteSnapshotResponse,
  QuoteIntent,
  RiskParam,
  RiskCheckResult,
  RiskHaltResponse,
  RiskLimitsResponse,
  RiskOverrideResponse,
  RiskResumeResponse,
  TimeInForce,
  RiskSetResponse
} from "./sdk-types.js";

export interface CommandSpec<Params, Result> {
  params: Params;
  result: Result;
}

export interface CommandMap {
  "daemon.status": CommandSpec<Record<string, never>, DaemonStatusResponse>;
  "daemon.stop": CommandSpec<Record<string, never>, DaemonStopResponse>;
  "quote.snapshot": CommandSpec<{ symbols: string[]; force?: boolean; intent?: QuoteIntent }, QuoteSnapshotResponse>;
  "market.capabilities": CommandSpec<{ symbols?: string[]; refresh?: boolean }, MarketCapabilitiesResponse>;
  "market.history": CommandSpec<
    {
      symbol: string;
      period: HistoryPeriod;
      bar: BarSize;
      rth_only?: boolean;
      strict?: boolean;
    },
    MarketHistoryResponse
  >;
  "market.chain": CommandSpec<
    {
      symbol: string;
      expiry?: string;
      strike_range?: string;
      type?: OptionType;
      limit?: number;
      offset?: number;
      fields?: ChainField[];
      strict?: boolean;
    },
    OptionChainResponse
  >;
  "portfolio.positions": CommandSpec<{ symbol?: string }, PortfolioPositionsResponse>;
  "portfolio.balance": CommandSpec<Record<string, never>, PortfolioBalanceResponse>;
  "portfolio.pnl": CommandSpec<Record<string, never>, PortfolioPnLResponse>;
  "portfolio.exposure": CommandSpec<{ by?: ExposureGroupBy }, PortfolioExposureResponse>;
  "portfolio.snapshot": CommandSpec<{ symbols?: string[]; exposure_by?: ExposureGroupBy }, PortfolioSnapshotResponse>;
  "order.place": CommandSpec<
    {
      side: OrderSide;
      symbol: string;
      qty: number;
      tif?: TimeInForce;
      limit?: number;
      stop?: number;
      client_order_id?: string;
      idempotency_key?: string;
      dry_run?: boolean;
      decision_name?: string;
      decision_summary?: string;
      decision_reasoning?: string;
    },
    OrderPlaceResponse
  >;
  "order.bracket": CommandSpec<
    {
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
    },
    OrderBracketResponse
  >;
  "order.status": CommandSpec<{ order_id: string }, OrderStatusResponse>;
  "orders.list": CommandSpec<{ status?: OrderStatusFilter; since?: string }, OrdersListResponse>;
  "order.cancel": CommandSpec<{ order_id: string }, OrderCancelResponse>;
  "orders.cancel_all": CommandSpec<{ confirm?: boolean; json_mode?: boolean }, OrdersCancelAllResponse>;
  "fills.list": CommandSpec<{ since?: string; symbol?: string }, FillsListResponse>;
  "risk.check": CommandSpec<
    {
      side: OrderSide;
      symbol: string;
      qty: number;
      tif?: TimeInForce;
      limit?: number;
      stop?: number;
    },
    RiskCheckResult
  >;
  "risk.limits": CommandSpec<Record<string, never>, RiskLimitsResponse>;
  "risk.set": CommandSpec<{ param: RiskParam; value: JsonValue }, RiskSetResponse>;
  "risk.halt": CommandSpec<Record<string, never>, RiskHaltResponse>;
  "risk.resume": CommandSpec<Record<string, never>, RiskResumeResponse>;
  "risk.override": CommandSpec<
    {
      param: RiskParam;
      value: JsonValue;
      duration: string;
      reason: string;
    },
    RiskOverrideResponse
  >;
  "runtime.keepalive": CommandSpec<{ sent_at?: number }, KeepaliveResponse>;
  "audit.commands": CommandSpec<{ source?: AuditSource; since?: string; request_id?: string }, AuditCommandsResponse>;
  "audit.orders": CommandSpec<{ status?: OrderStatusFilter; since?: string }, AuditOrdersResponse>;
  "audit.risk": CommandSpec<{ type?: string }, AuditRiskResponse>;
  "audit.export": CommandSpec<
    {
      output: string;
      table?: AuditTable;
      format?: "csv";
      since?: string;
      status?: OrderStatusFilter;
      source?: AuditSource;
      request_id?: string;
      type?: string;
    },
    AuditExportResponse
  >;
  "schema.get": CommandSpec<{ command?: string }, Record<string, JsonValue>>;
  "events.subscribe": CommandSpec<{ topics: EventTopic[] }, { subscribed: string[] }>;
}

export type CommandName = keyof CommandMap;
export type CommandParams<C extends CommandName> = CommandMap[C]["params"];
export type CommandResult<C extends CommandName> = CommandMap[C]["result"];
