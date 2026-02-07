import { useStore } from "zustand";
import { createStore } from "zustand/vanilla";
import {
  loadPositions,
  loadResearch,
  loadStrategies,
} from "../lib/data-loader.js";
import { screens } from "../lib/keymap.js";
import type {
  BrokerOrder,
  BrokerPosition,
  ChatMessage,
  PositionEntry,
  StrategyEntry,
  TerminalStore,
} from "./types.js";

let _msgId = 0;

function listLengthForScreen(state: TerminalStore): number {
  switch (state.screen) {
    case "strategies":
      return state.strategies.length;
    case "positions":
      return state.positions.length;
    case "research":
      return state.research.length;
    default:
      return 0;
  }
}

/** Build a symbol→BrokerPosition lookup from the broker positions array. */
function buildPositionMap(
  positions: BrokerPosition[]
): Map<string, BrokerPosition> {
  const map = new Map<string, BrokerPosition>();
  for (const p of positions) {
    map.set(p.symbol.toUpperCase(), p);
  }
  return map;
}

/** Merge raw markdown positions with live broker data. */
function mergePositions(state: TerminalStore): {
  positions: PositionEntry[];
  totalValue: number;
} {
  const rawPositions = loadPositions();
  const brokerMap = buildPositionMap(state.brokerPositions);
  let totalValue = 0;

  const positions: PositionEntry[] = rawPositions.map((raw) => {
    const bp = brokerMap.get(raw.symbol.toUpperCase());
    const isOpen = bp != null && bp.qty > 0;
    const marketValue = bp?.marketValue ?? 0;
    totalValue += marketValue;

    return {
      ...raw,
      status: isOpen ? "open" : "closed",
      qty: bp?.qty ?? 0,
      avgCost: bp?.avgCost ?? 0,
      marketValue,
      unrealizedPnl: bp?.unrealizedPnl ?? null,
      marketPrice: bp?.marketPrice ?? null,
    };
  });

  return { positions, totalValue };
}

/** Merge raw markdown strategies with live broker data. */
function mergeStrategies(brokerPositions: BrokerPosition[]): {
  strategies: StrategyEntry[];
  dayGL: number;
  totalGL: number;
} {
  const rawStrategies = loadStrategies();
  const brokerMap = buildPositionMap(brokerPositions);
  let dayGL = 0;
  let totalGL = 0;

  const strategies: StrategyEntry[] = rawStrategies.map((raw) => {
    let dayGainLoss = 0;
    let totalGainLoss = 0;
    let positionCount = 0;

    for (const sym of raw.positions) {
      const bp = brokerMap.get(sym.toUpperCase());
      if (bp && bp.qty > 0) {
        positionCount++;
        dayGainLoss += bp.unrealizedPnl ?? 0;
        totalGainLoss += bp.unrealizedPnl ?? 0;
      }
    }

    dayGL += dayGainLoss;
    totalGL += totalGainLoss;

    return {
      ...raw,
      dayGainLoss,
      totalGainLoss,
      positionCount,
    };
  });

  return { strategies, dayGL, totalGL };
}

export const store = createStore<TerminalStore>()((set, get) => ({
  // ── Data ──────────────────────────────────────────────────────
  strategies: [],
  positions: [],
  research: [],
  portfolioDayGainLoss: 0,
  portfolioTotalGainLoss: 0,
  portfolioTotalValue: 0,

  loadAll() {
    const state = get();
    const research = loadResearch();

    const { positions, totalValue } = mergePositions(state);
    const { strategies, dayGL, totalGL } = mergeStrategies(
      state.brokerPositions
    );

    // Use broker balance for total value when available, else sum of position market values
    const portfolioTotalValue =
      state.brokerBalance?.netLiquidation ?? totalValue;

    set({
      strategies,
      positions,
      research,
      portfolioDayGainLoss: dayGL,
      portfolioTotalGainLoss: totalGL,
      portfolioTotalValue,
    });
  },

  // ── Navigation ────────────────────────────────────────────────
  screen: "command",
  viewMode: "list",
  selectedIndex: 0,
  scrollOffset: 0,

  setScreen(screen) {
    set({ screen, viewMode: "list", selectedIndex: 0, scrollOffset: 0 });
  },

  moveSelection(delta) {
    const state = get();
    const len = listLengthForScreen(state);
    if (len === 0) {
      return;
    }
    const next = Math.max(0, Math.min(len - 1, state.selectedIndex + delta));
    set({ selectedIndex: next });
  },

  openDetail() {
    const state = get();
    if (state.screen === "command") {
      return;
    }
    const len = listLengthForScreen(state);
    if (len === 0) {
      return;
    }
    set({ viewMode: "detail", scrollOffset: 0 });
  },

  goBack() {
    const state = get();
    if (state.viewMode === "chat") {
      set({
        viewMode: "list",
        activeSession: null,
        chatFocused: false,
        chatInput: "",
      });
      return;
    }
    if (state.viewMode === "detail") {
      set({ viewMode: "list", scrollOffset: 0 });
      return;
    }
  },

  cycleTab() {
    const state = get();
    const idx = screens.indexOf(state.screen);
    const next = screens[(idx + 1) % screens.length];
    set({
      screen: next,
      viewMode: "list",
      selectedIndex: 0,
      scrollOffset: 0,
      chatFocused: false,
      chatInput: "",
    });
  },

  scroll(delta) {
    set((s) => ({ scrollOffset: Math.max(0, s.scrollOffset + delta) }));
  },

  // ── Chat ──────────────────────────────────────────────────────
  activeSession: null,
  chatInput: "",
  chatFocused: false,

  setChatInput(value) {
    set({ chatInput: value });
  },

  focusChat() {
    set({ chatFocused: true });
  },

  blurChat() {
    set({ chatFocused: false });
  },

  submitChat() {
    const state = get();
    const text = state.chatInput.trim();
    if (!text) {
      return;
    }

    const userMsg: ChatMessage = {
      id: `msg-${++_msgId}`,
      role: "user",
      content: text,
      timestamp: Date.now(),
    };

    let session = state.activeSession;
    if (!session) {
      session = {
        id: `session-${Date.now()}`,
        originScreen: state.screen,
        messages: [],
        createdAt: Date.now(),
      };
    }

    const assistantMsg: ChatMessage = {
      id: `msg-${++_msgId}`,
      role: "assistant",
      content: "I'm a placeholder response. Agent integration coming soon.",
      timestamp: Date.now(),
    };

    set({
      activeSession: {
        ...session,
        messages: [...session.messages, userMsg, assistantMsg],
      },
      chatInput: "",
      chatFocused: false,
      viewMode: "chat",
    });
  },

  exitChat() {
    set({
      viewMode: "list",
      activeSession: null,
      chatFocused: false,
      chatInput: "",
    });
  },

  // ── Connection ────────────────────────────────────────────────
  connected: false,
  error: null,
  lastPing: null,
  brokerPositions: [],
  brokerBalance: null,
  brokerOrders: [],

  async fetchBrokerData() {
    try {
      const { getBrokerClient } = await import("../lib/broker.js");
      const client = await getBrokerClient();

      const [posRes, balRes, ordRes] = await Promise.allSettled([
        client.positions(),
        client.balance(),
        client.orders("all"),
      ]);

      const brokerPositions: BrokerPosition[] =
        posRes.status === "fulfilled"
          ? posRes.value.positions.map((p) => ({
              symbol: p.symbol,
              qty: p.qty,
              avgCost: p.avg_cost,
              marketPrice: p.market_price,
              marketValue: p.market_value,
              unrealizedPnl: p.unrealized_pnl,
              realizedPnl: p.realized_pnl,
            }))
          : [];

      const brokerBalance =
        balRes.status === "fulfilled"
          ? {
              netLiquidation: balRes.value.balance.net_liquidation,
              cash: balRes.value.balance.cash,
            }
          : null;

      const brokerOrders: BrokerOrder[] =
        ordRes.status === "fulfilled"
          ? ordRes.value.orders.map((o) => ({
              clientOrderId: (o.client_order_id as string) ?? "",
              symbol: (o.symbol as string) ?? "",
              status: (o.status as string) ?? "",
              side: (o.side as string) ?? "",
              qty: (o.qty as number) ?? 0,
              filledAt: (o.filled_at as string) ?? null,
            }))
          : [];

      set({
        brokerPositions,
        brokerBalance,
        brokerOrders,
        connected: true,
        error: null,
        lastPing: Date.now(),
      });
    } catch {
      set({
        connected: false,
        brokerPositions: [],
        brokerBalance: null,
        brokerOrders: [],
      });
    }
  },
}));

export function useTerminal(): TerminalStore;
export function useTerminal<T>(selector: (s: TerminalStore) => T): T;
export function useTerminal<T>(selector?: (s: TerminalStore) => T) {
  // biome-ignore lint/style/noNonNullAssertion: overloaded selector pattern requires assertion
  return useStore(store, selector!);
}

export type { TerminalStore } from "./types.js";
