import type { Metadata } from "next";

export const metadata: Metadata = {
  title: "Reference — broker-cli",
  description:
    "Complete command reference for broker-cli. Every command, flag, and option documented.",
};

function Cmd({
  name,
  description,
  usage,
  flags,
  example,
  notes,
}: {
  name: string;
  description: string;
  usage: string;
  flags?: { flag: string; description: string; default?: string }[];
  example?: string;
  notes?: string;
}) {
  return (
    <div className="border border-[var(--border)] rounded-lg overflow-hidden">
      <div className="px-5 py-4 bg-[var(--card)]">
        <div className="flex items-baseline gap-3 mb-1">
          <code className="text-[var(--accent)] font-semibold text-sm">
            {name}
          </code>
        </div>
        <p className="text-sm text-[var(--muted)]">{description}</p>
      </div>
      <div className="px-5 py-3 border-t border-[var(--border)] bg-[var(--background)]">
        <pre className="text-sm font-mono text-[var(--foreground)] overflow-x-auto">
          {usage}
        </pre>
      </div>
      {flags && flags.length > 0 && (
        <div className="px-5 py-3 border-t border-[var(--border)]">
          <table className="w-full text-sm">
            <tbody>
              {flags.map((f) => (
                <tr key={f.flag} className="border-b border-[var(--border)] last:border-0">
                  <td className="py-1.5 pr-4 font-mono text-[var(--foreground)] whitespace-nowrap">
                    {f.flag}
                  </td>
                  <td className="py-1.5 text-[var(--muted)]">
                    {f.description}
                    {f.default && (
                      <span className="ml-2 text-xs opacity-60">
                        (default: {f.default})
                      </span>
                    )}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
      {example && (
        <div className="px-5 py-3 border-t border-[var(--border)] bg-[var(--card)]">
          <pre className="text-sm font-mono text-[var(--muted)] overflow-x-auto whitespace-pre-wrap">
            {example}
          </pre>
        </div>
      )}
      {notes && (
        <div className="px-5 py-3 border-t border-[var(--border)]">
          <p className="text-xs text-[var(--muted)] leading-relaxed">{notes}</p>
        </div>
      )}
    </div>
  );
}

function Section({
  id,
  title,
  description,
  children,
}: {
  id: string;
  title: string;
  description?: string;
  children: React.ReactNode;
}) {
  return (
    <section id={id} className="scroll-mt-20">
      <h2 className="text-xl font-bold mb-1">{title}</h2>
      {description && (
        <p className="text-sm text-[var(--muted)] mb-5">{description}</p>
      )}
      {!description && <div className="mb-5" />}
      <div className="space-y-4">{children}</div>
    </section>
  );
}

const sections = [
  { id: "setup", label: "Setup" },
  { id: "daemon", label: "Daemon" },
  { id: "market", label: "Market Data" },
  { id: "orders", label: "Orders" },
  { id: "portfolio", label: "Portfolio" },
  { id: "risk", label: "Risk" },
  { id: "audit", label: "Audit" },
  { id: "config", label: "Configuration" },
];

export default function ReferencePage() {
  return (
    <div className="max-w-6xl mx-auto px-6 py-12 flex gap-12">
      {/* Sidebar nav */}
      <nav className="hidden lg:block w-48 shrink-0 sticky top-20 self-start">
        <p className="text-xs font-semibold text-[var(--muted)] uppercase tracking-wider mb-3">
          Sections
        </p>
        <ul className="space-y-1.5">
          {sections.map((s) => (
            <li key={s.id}>
              <a
                href={`#${s.id}`}
                className="text-sm text-[var(--muted)] hover:text-[var(--foreground)] transition-colors"
              >
                {s.label}
              </a>
            </li>
          ))}
        </ul>
      </nav>

      {/* Content */}
      <div className="flex-1 min-w-0 space-y-16">
        <div>
          <h1 className="text-3xl font-bold mb-2">Command Reference</h1>
          <p className="text-[var(--muted)]">
            Complete reference for every broker-cli command. Every response uses a stable JSON envelope:
            <code className="mx-1 text-[var(--foreground)]">{`{ok,data,error,meta}`}</code>
            with request IDs for tracing and audit correlation.
            Use global <code className="mx-1 text-[var(--foreground)]">--strict</code> (or command-level strict flags where available)
            when agents should treat empty market payloads as errors.
          </p>
        </div>

        {/* Setup */}
        <Section
          id="setup"
          title="Setup"
          description="Install-time onboarding and cleanup. E*Trade OAuth is handled inside `broker setup`."
        >
          <Cmd
            name="broker setup"
            description="Interactive setup wizard: choose provider, configure credentials, and complete E*Trade OAuth."
            usage="broker setup"
            notes="Use this command for all provider onboarding."
          />
          <Cmd
            name="broker update"
            description="Sync broker-cli source checkout to the latest commit on origin/main."
            usage="broker update [OPTIONS]"
            flags={[
              { flag: "--force", description: "Discard tracked local changes before syncing" },
              { flag: "--reinstall / --no-reinstall", description: "Reinstall editable packages after syncing" },
            ]}
            example={`$ broker update\n{"ok":true,"data":{"updated":true,"branch":"main","from":"...","to":"..."},"error":null,"meta":{"schema_version":"v1","command":"update.sync","request_id":"...","timestamp":"..."}}`}
          />
          <Cmd
            name="broker schema"
            description="Return machine-readable JSON Schema for command params/results."
            usage="broker schema [COMMAND]"
            example={`$ broker schema quote.snapshot\n{"ok":true,"data":{"schema_version":"v1","command":"quote.snapshot","schema":{"params":{...},"result":{...}},"envelope":{...}},"error":null,"meta":{"schema_version":"v1","command":"schema.get","request_id":"...","timestamp":"..."}}`}
            notes="Use this in agent bootstrapping to validate payloads before command execution."
          />
          <Cmd
            name="broker uninstall"
            description="Remove broker-cli install/setup artifacts (config, state, data, runtime, wrappers, completions)."
            usage="broker uninstall [OPTIONS]"
            flags={[
              { flag: "--yes", description: "Skip interactive confirmation" },
              { flag: "--keep-ib-app", description: "Keep installed IB Gateway app" },
              { flag: "--keep-source", description: "Keep source checkout under ~/.local/share/broker/source" },
            ]}
          />
        </Section>

        {/* Daemon */}
        <Section
          id="daemon"
          title="Daemon"
          description="Manage the broker daemon process. The daemon maintains the broker connection and handles all API communication."
        >
          <Cmd
            name="broker daemon start"
            description="Start the trading daemon and wait for socket readiness."
            usage="broker daemon start [OPTIONS]"
            flags={[
              { flag: "--paper", description: "Use paper trading port (4002)" },
              { flag: "--gateway HOST:PORT", description: "Override gateway endpoint" },
              { flag: "--client-id INT", description: "Override IB client ID" },
            ]}
            example={`$ broker daemon start\n{"ok":true,"data":{"socket":"~/.local/state/broker/broker.sock"},"error":null,"meta":{"schema_version":"v1","command":"daemon.start","request_id":"...","timestamp":"..."}}\n\n$ broker daemon start --paper\n{"ok":true,"data":{"socket":"~/.local/state/broker/broker.sock"},"error":null,"meta":{"schema_version":"v1","command":"daemon.start","request_id":"...","timestamp":"..."}}`}
          />
          <Cmd
            name="broker daemon stop"
            description="Request graceful daemon shutdown."
            usage="broker daemon stop"
            example={`$ broker daemon stop\n{"ok":true,"data":{"stopping":true},"error":null,"meta":{"schema_version":"v1","command":"daemon.stop","request_id":"...","timestamp":"..."}}`}
          />
          <Cmd
            name="broker daemon status"
            description="Show daemon uptime, broker connection state, and risk halt status."
            usage="broker daemon status"
            example={`$ broker daemon status\n{"ok":true,"data":{"uptime_seconds":3421.4,"connection":{"connected":true,"account_id":"..."},"risk_halted":false,"socket":"~/.local/state/broker/broker.sock"},"error":null,"meta":{"schema_version":"v1","command":"daemon.status","request_id":"...","timestamp":"..."}}`}
          />
          <Cmd
            name="broker daemon restart"
            description="Stop then start the daemon."
            usage="broker daemon restart [OPTIONS]"
            flags={[
              { flag: "--paper", description: "Restart using paper trading port" },
            ]}
          />
        </Section>

        {/* Market Data */}
        <Section
          id="market"
          title="Market Data"
          description="Real-time quotes, streaming, option chains, and historical bars."
        >
          <Cmd
            name="broker quote"
            description="Snapshot quote for one or more symbols."
            usage="broker quote SYMBOL [SYMBOL...]"
            example={`$ broker quote AAPL MSFT\n{"ok":true,"data":[{"symbol":"AAPL","bid":185.2,"ask":185.25,"last":185.22,"volume":48291033},{"symbol":"MSFT","bid":412.1,"ask":412.15,"last":412.12,"volume":22104891}],"error":null,"meta":{"schema_version":"v1","command":"quote.snapshot","request_id":"...","timestamp":"..."}}`}
          />
          <Cmd
            name="broker watch"
            description="Continuously refresh quote fields in the terminal. Ctrl+C to stop."
            usage="broker watch SYMBOL [OPTIONS]"
            flags={[
              {
                flag: "--fields FIELDS",
                description: "Comma-separated: bid, ask, last, volume, timestamp, exchange, currency, symbol",
                default: "bid,ask,last,volume",
              },
              { flag: "--interval INTERVAL", description: "Refresh rate (e.g. 250ms, 1s, 2m)", default: "1s" },
            ]}
            example={`$ broker watch AAPL --fields bid,ask,last --interval 500ms\n{"ok":true,"data":{"bid":185.2,"ask":185.25,"last":185.22},"error":null,"meta":{"schema_version":"v1","command":"quote.watch","request_id":"...","timestamp":"..."}}`}
          />
          <Cmd
            name="broker chain"
            description="Fetch an option chain with paging and field selection controls for agent-efficient payloads."
            usage="broker chain SYMBOL [OPTIONS]"
            flags={[
              { flag: "--expiry YYYY-MM", description: "Filter by expiration month" },
              { flag: "--strike-range LOW:HIGH", description: "Relative range around current price", default: "0.9:1.1" },
              { flag: "--type call|put", description: "Filter by option type" },
              { flag: "--limit INT", description: "Max entries returned after filtering", default: "200" },
              { flag: "--offset INT", description: "Offset into filtered entries", default: "0" },
              { flag: "--fields LIST", description: "Comma-separated entry fields (e.g. strike,expiry,bid,ask)" },
              { flag: "--strict / --no-strict", description: "Error if no entries match filters" },
            ]}
            example={`$ broker chain AAPL --type call --strike-range 0.95:1.05 --limit 5 --fields strike,expiry,bid,ask\n{"ok":true,"data":{"symbol":"AAPL","underlying_price":263.3,"entries":[{"strike":252.5,"expiry":"2026-02-20","bid":null,"ask":null}],"pagination":{"total_entries":80,"offset":0,"limit":5,"returned_entries":5},"fields":["strike","expiry","bid","ask"]},"error":null,"meta":{"schema_version":"v1","command":"market.chain","request_id":"...","timestamp":"..."}}`}
          />
          <Cmd
            name="broker history"
            description="Fetch historical price bars for a symbol."
            usage="broker history SYMBOL --period PERIOD --bar SIZE [OPTIONS]"
            flags={[
              { flag: "--period 1d|5d|30d|90d|1y", description: "Lookback period" },
              { flag: "--bar 1m|5m|15m|1h|1d", description: "Bar size" },
              { flag: "--rth-only", description: "Restrict to regular trading hours" },
              { flag: "--strict / --no-strict", description: "Error when no bars are returned" },
            ]}
            example={`$ broker history AAPL --period 5d --bar 1h\n{"ok":true,"data":[{"symbol":"AAPL","time":"2026-02-18T00:00:00","open":265.1,"close":263.29}],"error":null,"meta":{"schema_version":"v1","command":"market.history","request_id":"...","timestamp":"..."}}`}
            notes="Available on Interactive Brokers only."
          />
        </Section>

        {/* Orders */}
        <Section
          id="orders"
          title="Orders"
          description="Place, monitor, and cancel orders. Supports market, limit, stop, and bracket orders."
        >
          <Cmd
            name="broker order buy"
            description="Place a buy order. Market by default unless --limit or --stop is set."
            usage="broker order buy SYMBOL QTY [OPTIONS]"
            flags={[
              { flag: "--limit PRICE", description: "Limit price (creates limit order)" },
              { flag: "--stop PRICE", description: "Stop trigger price (creates stop order)" },
              { flag: "--tif DAY|GTC|IOC", description: "Time in force", default: "DAY" },
              { flag: "--dry-run", description: "Evaluate order risk but do not submit" },
              { flag: "--idempotency-key KEY", description: "Stable retry key mapped to client_order_id" },
            ]}
            example={`$ broker order buy AAPL 100 --limit 185.00 --idempotency-key rebalance-aapl-1\n{"ok":true,"data":{"order":{"client_order_id":"rebalance-aapl-1","status":"Submitted"},"dry_run":false,"risk_check":{"ok":true,"reasons":[]},"submit_allowed":true},"error":null,"meta":{"schema_version":"v1","command":"order.place","request_id":"...","timestamp":"..."}}\n\n$ broker order buy AAPL 10 --limit 185 --dry-run\n{"ok":true,"data":{"order":{"client_order_id":"dryrun-...","status":"DryRunAccepted"},"dry_run":true,"risk_check":{"ok":true,"reasons":[]},"submit_allowed":true},"error":null,"meta":{"schema_version":"v1","command":"order.place","request_id":"...","timestamp":"..."}}`}
          />
          <Cmd
            name="broker order sell"
            description="Place a sell order. Market by default unless --limit or --stop is set."
            usage="broker order sell SYMBOL QTY [OPTIONS]"
            flags={[
              { flag: "--limit PRICE", description: "Limit price" },
              { flag: "--stop PRICE", description: "Stop trigger price" },
              { flag: "--tif DAY|GTC|IOC", description: "Time in force", default: "DAY" },
              { flag: "--dry-run", description: "Evaluate order risk but do not submit" },
              { flag: "--idempotency-key KEY", description: "Stable retry key mapped to client_order_id" },
            ]}
            example={`$ broker order sell AAPL 50 --limit 190.00 --tif GTC`}
          />
          <Cmd
            name="broker order bracket"
            description="Place a bracket order: entry + take profit + stop loss."
            usage="broker order bracket SYMBOL QTY --entry PRICE --tp PRICE --sl PRICE [OPTIONS]"
            flags={[
              { flag: "--entry PRICE", description: "Entry limit price (required)" },
              { flag: "--tp PRICE", description: "Take-profit price (required)" },
              { flag: "--sl PRICE", description: "Stop-loss price (required)" },
              { flag: "--side buy|sell", description: "Order side", default: "buy" },
              { flag: "--tif DAY|GTC|IOC", description: "Time in force", default: "DAY" },
            ]}
            example={`$ broker order bracket AAPL 100 --entry 185 --tp 195 --sl 180`}
            notes="Available on Interactive Brokers only."
          />
          <Cmd
            name="broker order status"
            description="Show status for a single order by client order ID."
            usage="broker order status ORDER_ID"
            example={`$ broker order status a1b2c3\n{"ok":true,"data":{"client_order_id":"a1b2c3","status":"Filled","fill_qty":100,"fill_price":185.02},"error":null,"meta":{"schema_version":"v1","command":"order.status","request_id":"...","timestamp":"..."}}`}
          />
          <Cmd
            name="broker orders"
            description="List orders with optional status and date filters."
            usage="broker orders [OPTIONS]"
            flags={[
              { flag: "--status active|filled|cancelled|all", description: "Filter by status", default: "all" },
              { flag: "--since YYYY-MM-DD", description: "Filter by date" },
            ]}
            example={`$ broker orders --status active\n{"ok":true,"data":[{"client_order_id":"...","status":"Submitted","symbol":"AAPL"}],"error":null,"meta":{"schema_version":"v1","command":"orders.list","request_id":"...","timestamp":"..."}}`}
          />
          <Cmd
            name="broker cancel"
            description="Cancel a single order by ID, or all open orders with --all."
            usage="broker cancel [ORDER_ID] [OPTIONS]"
            flags={[
              { flag: "--all", description: "Cancel all open orders" },
              { flag: "--confirm", description: "Required with --all in interactive mode" },
            ]}
            example={`$ broker cancel a1b2c3\n{"ok":true,"data":{"client_order_id":"a1b2c3","cancelled":true},"error":null,"meta":{"schema_version":"v1","command":"order.cancel","request_id":"...","timestamp":"..."}}\n\n$ broker cancel --all\n{"ok":true,"data":{"cancelled":true},"error":null,"meta":{"schema_version":"v1","command":"orders.cancel_all","request_id":"...","timestamp":"..."}}`}
          />
          <Cmd
            name="broker fills"
            description="List fill/execution history."
            usage="broker fills [OPTIONS]"
            flags={[
              { flag: "--since YYYY-MM-DD", description: "Filter by date" },
              { flag: "--symbol SYMBOL", description: "Filter by symbol" },
            ]}
            example={`$ broker fills --since 2026-02-01 --symbol AAPL\n{"ok":true,"data":[{"fill_id":"...","symbol":"AAPL","qty":100,"price":185.02}],"error":null,"meta":{"schema_version":"v1","command":"fills.list","request_id":"...","timestamp":"..."}}`}
          />
        </Section>

        {/* Portfolio */}
        <Section
          id="portfolio"
          title="Portfolio"
          description="Positions, P&L, balances, and exposure analysis."
        >
          <Cmd
            name="broker positions"
            description="Show current positions with unrealized P&L."
            usage="broker positions [OPTIONS]"
            flags={[
              { flag: "--symbol SYMBOL", description: "Filter to a single symbol" },
            ]}
            example={`$ broker positions\n{"ok":true,"data":[{"symbol":"AAPL","qty":200,"avg_cost":178.5,"market_value":37044.0,"unrealized_pnl":344.0},{"symbol":"MSFT","qty":100,"avg_cost":405.2,"market_value":41212.0,"unrealized_pnl":692.0}],"error":null,"meta":{"schema_version":"v1","command":"portfolio.positions","request_id":"...","timestamp":"..."}}`}
          />
          <Cmd
            name="broker pnl"
            description="Show P&L summary for today, a named period, or since a specific date."
            usage="broker pnl [OPTIONS]"
            flags={[
              { flag: "--today", description: "Today's P&L window" },
              { flag: "--period PERIOD", description: "Named period (e.g. 7d)" },
              { flag: "--since YYYY-MM-DD", description: "Custom start date" },
            ]}
            example={`$ broker pnl --today\n{"ok":true,"data":{"date":"2026-02-19","realized":1250.0,"unrealized":1036.0,"total":2286.0},"error":null,"meta":{"schema_version":"v1","command":"portfolio.pnl","request_id":"...","timestamp":"..."}}`}
            notes="Only one of --today, --period, or --since can be used. Defaults to --today."
          />
          <Cmd
            name="broker balance"
            description="Show account balances and margin metrics."
            usage="broker balance"
            example={`$ broker balance\n{"ok":true,"data":{"net_liquidation":125000.0,"cash":42000.0,"buying_power":84000.0,"margin_used":41000.0},"error":null,"meta":{"schema_version":"v1","command":"portfolio.balance","request_id":"...","timestamp":"..."}}`}
          />
          <Cmd
            name="broker exposure"
            description="Show portfolio exposure grouped by dimension. Returns percentage of net liquidation value."
            usage="broker exposure [OPTIONS]"
            flags={[
              {
                flag: "--by symbol|sector|asset_class|currency",
                description: "Grouping dimension",
                default: "symbol",
              },
            ]}
            example={`$ broker exposure --by symbol\n{"ok":true,"data":[{"key":"AAPL","exposure_pct":29.6},{"key":"MSFT","exposure_pct":33.0},{"key":"cash","exposure_pct":37.4}],"error":null,"meta":{"schema_version":"v1","command":"portfolio.exposure","request_id":"...","timestamp":"..."}}\n\n$ broker exposure --by sector\n{"ok":true,"data":[{"key":"Technology","exposure_pct":62.6},{"key":"cash","exposure_pct":37.4}],"error":null,"meta":{"schema_version":"v1","command":"portfolio.exposure","request_id":"...","timestamp":"..."}}`}
          />
          <Cmd
            name="broker snapshot"
            description="Single-call state snapshot for agent loops: quotes, positions, balance, pnl, exposure, limits, and connection."
            usage="broker snapshot [OPTIONS]"
            flags={[
              { flag: "--symbols SYMBOLS", description: "Comma-separated symbol list for quote snapshot" },
              { flag: "--exposure-by symbol|sector|asset_class|currency", description: "Exposure grouping", default: "symbol" },
            ]}
            example={`$ broker snapshot --symbols AAPL,MSFT\n{"ok":true,"data":{"symbols":["AAPL","MSFT"],"quotes":[...],"positions":[...],"balance":{...},"pnl":{...},"exposure":[...],"risk_limits":{...},"connection":{"connected":true}},"error":null,"meta":{"schema_version":"v1","command":"portfolio.snapshot","request_id":"...","timestamp":"..."}}`}
          />
        </Section>

        {/* Risk */}
        <Section
          id="risk"
          title="Risk Management"
          description="Pre-trade risk checks, runtime limits, emergency controls, and temporary overrides."
        >
          <Cmd
            name="broker check"
            description="Dry-run an order against risk limits without submitting. Use to validate before placing."
            usage="broker check --side SIDE --symbol SYMBOL --qty QTY [OPTIONS]"
            flags={[
              { flag: "--side buy|sell", description: "Order side (required)" },
              { flag: "--symbol SYMBOL", description: "Ticker symbol (required)" },
              { flag: "--qty QTY", description: "Quantity to evaluate (required)" },
              { flag: "--limit PRICE", description: "Limit price" },
              { flag: "--stop PRICE", description: "Stop trigger price" },
              { flag: "--tif DAY|GTC|IOC", description: "Time in force", default: "DAY" },
            ]}
            example={`$ broker check --side buy --symbol AAPL --qty 500 --limit 185\n{"ok":true,"data":{"ok":true,"reasons":[],"details":{"notional":92500.0}},"error":null,"meta":{"schema_version":"v1","command":"risk.check","request_id":"...","timestamp":"..."}}\n\n$ broker check --side buy --symbol AAPL --qty 50000 --limit 185\n{"ok":true,"data":{"ok":false,"reasons":["order notional ... exceeds max_order_value ..."],"details":{"notional":9250000.0},"suggestion":"reduce quantity to <= ..."},"error":null,"meta":{"schema_version":"v1","command":"risk.check","request_id":"...","timestamp":"..."}}`}
          />
          <Cmd
            name="broker limits"
            description="Show current runtime risk limit parameters."
            usage="broker limits"
            example={`$ broker limits\n{"ok":true,"data":{"max_position_pct":10.0,"max_order_value":50000.0,"max_daily_loss_pct":2.0,"max_open_orders":20,"halted":false},"error":null,"meta":{"schema_version":"v1","command":"risk.limits","request_id":"...","timestamp":"..."}}`}
          />
          <Cmd
            name="broker set"
            description="Update a risk limit parameter at runtime."
            usage="broker set PARAM VALUE"
            example={`$ broker set max_order_value 25000\n{"ok":true,"data":{"max_order_value":25000.0,"halted":false},"error":null,"meta":{"schema_version":"v1","command":"risk.set","request_id":"...","timestamp":"..."}}`}
          />
          <Cmd
            name="broker halt"
            description="Emergency halt: cancels all open orders and rejects new orders until resumed."
            usage="broker halt"
            example={`$ broker halt\n{"ok":true,"data":{"halted":true},"error":null,"meta":{"schema_version":"v1","command":"risk.halt","request_id":"...","timestamp":"..."}}`}
          />
          <Cmd
            name="broker resume"
            description="Resume normal trading after a risk halt."
            usage="broker resume"
            example={`$ broker resume\n{"ok":true,"data":{"halted":false},"error":null,"meta":{"schema_version":"v1","command":"risk.resume","request_id":"...","timestamp":"..."}}`}
          />
          <Cmd
            name="broker override"
            description="Apply a temporary risk limit override. Requires a reason and duration for audit trail."
            usage="broker override --param PARAM --value VALUE --reason TEXT --duration DURATION"
            flags={[
              { flag: "--param PARAM", description: "Risk parameter to override" },
              { flag: "--value VALUE", description: "Temporary override value" },
              { flag: "--reason TEXT", description: "Required explanation for the override" },
              { flag: "--duration DURATION", description: "How long the override lasts (e.g. 1h, 30m)" },
            ]}
            example={`$ broker override --param max_order_value --value 25000 --reason "large rebalance" --duration 1h\n{"ok":true,"data":{"param":"max_order_value","value":25000.0,"reason":"large rebalance","expires_at":"..."},"error":null,"meta":{"schema_version":"v1","command":"risk.override","request_id":"...","timestamp":"..."}}`}
          />
        </Section>

        {/* Audit */}
        <Section
          id="audit"
          title="Audit"
          description="Query order history, command invocations, and risk events. Export to CSV."
        >
          <Cmd
            name="broker audit orders"
            description="Query order lifecycle records from audit storage."
            usage="broker audit orders [OPTIONS]"
            flags={[
              { flag: "--since YYYY-MM-DD", description: "Filter by date" },
              { flag: "--status active|filled|cancelled|all", description: "Filter by status" },
            ]}
          />
          <Cmd
            name="broker audit commands"
            description="Query command invocation audit records."
            usage="broker audit commands [OPTIONS]"
            flags={[
              { flag: "--source cli|sdk|ts_sdk", description: "Filter by source" },
              { flag: "--since YYYY-MM-DD", description: "Filter by date" },
              { flag: "--request-id ID", description: "Filter to a single command execution trace" },
            ]}
            example={`$ broker audit commands --request-id 647a8306-...\n{"ok":true,"data":[{"timestamp":"...","source":"cli","command":"order.place","result_code":0,"request_id":"647a8306-..."}],"error":null,"meta":{"schema_version":"v1","command":"audit.commands","request_id":"...","timestamp":"..."}}`}
          />
          <Cmd
            name="broker audit risk"
            description="Query risk event audit records (halts, overrides, limit violations)."
            usage="broker audit risk [OPTIONS]"
          />
          <Cmd
            name="broker audit export"
            description="Export audit rows to CSV."
            usage="broker audit export --table TABLE [OPTIONS]"
            flags={[
              { flag: "--table orders|commands|risk", description: "Which audit table to export" },
              { flag: "--format csv", description: "Output format", default: "csv" },
              { flag: "--request-id ID", description: "When table=commands, filter export by request_id" },
            ]}
          />
        </Section>

        {/* Configuration */}
        <Section
          id="config"
          title="Configuration"
          description="broker-cli uses a JSON config file and supports environment variable overrides."
        >
          <div className="border border-[var(--border)] rounded-lg overflow-hidden">
            <div className="px-5 py-4 bg-[var(--card)]">
              <h3 className="font-semibold text-sm mb-2">Config file</h3>
              <p className="text-sm text-[var(--muted)]">
                Default location:{" "}
                <code className="text-[var(--foreground)]">
                  ~/.config/broker/config.json
                </code>
              </p>
            </div>
            <div className="px-5 py-4 border-t border-[var(--border)]">
              <pre className="text-sm font-mono text-[var(--muted)] overflow-x-auto whitespace-pre">{`{
  "broker": {
    "provider": "ib",
    "etrade": {
      "consumer_key": "...",
      "consumer_secret": "...",
      "persistent_auth": true,
      "username": "...",
      "password": "...",
      "sandbox": false
    },
    "gateway": {
      "host": "127.0.0.1",
      "port": 4002,
      "client_id": 1
    },
    "runtime": {
      "request_timeout_seconds": 15
    }
  }
}`}</pre>
            </div>
          </div>

          <div className="border border-[var(--border)] rounded-lg overflow-hidden">
            <div className="px-5 py-4 bg-[var(--card)]">
              <h3 className="font-semibold text-sm mb-2">
                Environment variables
              </h3>
              <p className="text-sm text-[var(--muted)]">
                Environment variables override config file values.
              </p>
            </div>
            <div className="px-5 py-3 border-t border-[var(--border)]">
              <table className="w-full text-sm">
                <tbody>
                  {[
                    ["BROKER_PROVIDER", "Provider name (etrade, ib)"],
                    ["BROKER_ETRADE_CONSUMER_KEY", "E*Trade consumer key"],
                    ["BROKER_ETRADE_CONSUMER_SECRET", "E*Trade consumer secret"],
                    ["BROKER_ETRADE_USERNAME", "E*Trade username (persistent auth)"],
                    ["BROKER_ETRADE_PASSWORD", "E*Trade password (persistent auth)"],
                    ["BROKER_ETRADE_PERSISTENT_AUTH", "Enable persistent auth (true/false)"],
                    ["BROKER_GATEWAY_HOST", "IB gateway host"],
                    ["BROKER_GATEWAY_PORT", "IB gateway port (4001=live, 4002=paper)"],
                    ["BROKER_GATEWAY_CLIENT_ID", "IB client ID"],
                  ].map(([name, desc]) => (
                    <tr key={name} className="border-b border-[var(--border)] last:border-0">
                      <td className="py-1.5 pr-4 font-mono text-[var(--foreground)] whitespace-nowrap text-xs">
                        {name}
                      </td>
                      <td className="py-1.5 text-[var(--muted)]">{desc}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          </div>

          <div className="border border-[var(--border)] rounded-lg overflow-hidden">
            <div className="px-5 py-4 bg-[var(--card)]">
              <h3 className="font-semibold text-sm mb-2">File locations</h3>
            </div>
            <div className="px-5 py-3 border-t border-[var(--border)]">
              <table className="w-full text-sm">
                <tbody>
                  {[
                    ["Config", "~/.config/broker/config.json"],
                    ["E*Trade tokens", "~/.config/broker/etrade_tokens.json"],
                    ["Daemon socket", "~/.local/state/broker/broker.sock"],
                    ["Daemon log", "~/.local/state/broker/broker.log"],
                    ["Audit data", "~/.local/share/broker/"],
                  ].map(([label, path]) => (
                    <tr key={label} className="border-b border-[var(--border)] last:border-0">
                      <td className="py-1.5 pr-4 text-[var(--foreground)] whitespace-nowrap">
                        {label}
                      </td>
                      <td className="py-1.5 font-mono text-[var(--muted)] text-xs">
                        {path}
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          </div>
        </Section>

      </div>
    </div>
  );
}
