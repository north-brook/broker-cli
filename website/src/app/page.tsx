"use client";

import { useState } from "react";

const INSTALL_CMD = "curl -fsSL brokercli.com/install | bash";

function CopyButton({ text }: { text: string }) {
  const [copied, setCopied] = useState(false);
  return (
    <button
      onClick={() => {
        navigator.clipboard.writeText(text);
        setCopied(true);
        setTimeout(() => setCopied(false), 2000);
      }}
      className="shrink-0 px-3 py-1.5 text-sm rounded border border-[var(--border)] hover:border-[var(--accent)] hover:text-[var(--accent)] transition-colors cursor-pointer"
    >
      {copied ? "Copied!" : "Copy"}
    </button>
  );
}

const features = [
  {
    title: "Multi-Broker",
    description:
      "Connect to E*Trade and Interactive Brokers through a unified interface. Switch providers without changing your code.",
    icon: "⚡",
  },
  {
    title: "Option Chains",
    description:
      "Full option chain data with greeks, expiry filtering, and strike ranges. Built for derivatives traders.",
    icon: "📊",
  },
  {
    title: "Exposure Analysis",
    description:
      "Real-time portfolio exposure grouped by symbol, currency, sector, or asset class. Know your risk at a glance.",
    icon: "🎯",
  },
  {
    title: "Order Management",
    description:
      "Place, monitor, and cancel orders. Bulk cancel-all for open orders when you need to flatten fast.",
    icon: "📋",
  },
  {
    title: "Persistent Auth",
    description:
      "Headless re-authentication keeps sessions alive. No manual browser logins interrupting your strategies.",
    icon: "🔐",
  },
  {
    title: "Python SDK",
    description:
      "Daemon architecture with a clean Python SDK. Import broker_cli and build strategies in minutes.",
    icon: "🐍",
  },
];

export default function Home() {
  return (
    <main className="max-w-4xl mx-auto px-6 py-20">
      {/* Hero */}
      <section className="text-center mb-24">
        <h1 className="text-5xl sm:text-6xl font-bold tracking-tight mb-4">
          broker-cli
        </h1>
        <p className="text-xl text-[var(--muted)] mb-12 max-w-2xl mx-auto">
          Algorithmic trading from your terminal. Connect to brokerages,
          manage portfolios, and execute strategies — all from the command line.
        </p>

        {/* Install command */}
        <div className="inline-flex items-center gap-3 bg-[var(--card)] border border-[var(--border)] rounded-lg px-5 py-4 font-mono text-sm sm:text-base">
          <span className="text-[var(--accent)]">$</span>
          <code className="select-all">{INSTALL_CMD}</code>
          <CopyButton text={INSTALL_CMD} />
        </div>

        <div className="mt-6 flex items-center justify-center gap-6 text-sm text-[var(--muted)]">
          <a
            href="https://github.com/north-brook/broker-cli"
            className="hover:text-[var(--foreground)] transition-colors"
          >
            GitHub ↗
          </a>
          <span>·</span>
          <span>Open Source</span>
          <span>·</span>
          <span>Python 3.12+</span>
        </div>
      </section>

      {/* Features */}
      <section className="grid sm:grid-cols-2 lg:grid-cols-3 gap-6 mb-24">
        {features.map((f) => (
          <div
            key={f.title}
            className="bg-[var(--card)] border border-[var(--border)] rounded-lg p-6 hover:border-[var(--accent-dim)] transition-colors"
          >
            <div className="text-2xl mb-3">{f.icon}</div>
            <h3 className="font-semibold mb-2">{f.title}</h3>
            <p className="text-sm text-[var(--muted)] leading-relaxed">
              {f.description}
            </p>
          </div>
        ))}
      </section>

      {/* Architecture */}
      <section className="mb-24">
        <h2 className="text-2xl font-bold mb-6">How it works</h2>
        <div className="bg-[var(--card)] border border-[var(--border)] rounded-lg p-6 font-mono text-sm leading-relaxed">
          <pre className="text-[var(--muted)] overflow-x-auto">{`┌─────────────┐     ┌──────────────┐     ┌─────────────────┐
│  Your Code  │────▶│ broker-cli   │────▶│   E*Trade API   │
│  (Python)   │     │   daemon     │     │   IB Gateway    │
└─────────────┘     └──────────────┘     └─────────────────┘
                          │
                    ┌─────┴─────┐
                    │ Persistent│
                    │   Auth    │
                    └───────────┘`}</pre>
        </div>
      </section>

      {/* Quick start */}
      <section className="mb-24">
        <h2 className="text-2xl font-bold mb-6">Quick start</h2>
        <div className="space-y-4 font-mono text-sm">
          <div className="bg-[var(--card)] border border-[var(--border)] rounded-lg p-5 overflow-x-auto">
            <p className="text-[var(--muted)] mb-2"># Install</p>
            <p>
              <span className="text-[var(--accent)]">$</span> {INSTALL_CMD}
            </p>
          </div>
          <div className="bg-[var(--card)] border border-[var(--border)] rounded-lg p-5 overflow-x-auto">
            <p className="text-[var(--muted)] mb-2"># Start the daemon</p>
            <p>
              <span className="text-[var(--accent)]">$</span> broker start
            </p>
          </div>
          <div className="bg-[var(--card)] border border-[var(--border)] rounded-lg p-5 overflow-x-auto">
            <p className="text-[var(--muted)] mb-2"># Check your portfolio</p>
            <p>
              <span className="text-[var(--accent)]">$</span> broker portfolio
            </p>
            <p>
              <span className="text-[var(--accent)]">$</span> broker exposure
              --by symbol
            </p>
            <p>
              <span className="text-[var(--accent)]">$</span> broker
              option-chain AAPL --type call
            </p>
          </div>
        </div>
      </section>

      {/* Footer */}
      <footer className="text-center text-sm text-[var(--muted)] border-t border-[var(--border)] pt-8">
        <p>
          Built by{" "}
          <a
            href="https://northbrook.com"
            className="hover:text-[var(--foreground)] transition-colors"
          >
            North Brook
          </a>
        </p>
      </footer>
    </main>
  );
}
