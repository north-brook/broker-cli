"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import { GitHubLink } from "./github-link";

export function Header() {
  const pathname = usePathname();

  return (
    <header className="sticky top-0 z-50 border-b border-[var(--border)] bg-[var(--background)]/80 backdrop-blur-md">
      <div className="max-w-6xl mx-auto flex items-center justify-between px-6 h-14">
        <Link
          href="/"
          className="font-semibold text-[var(--foreground)] hover:text-[var(--accent)] transition-colors tracking-tight"
        >
          Broker CLI
        </Link>
        <span className="ml-2 px-1.5 py-0.5 text-[10px] font-medium uppercase tracking-wider rounded bg-amber-500/15 text-amber-500 border border-amber-500/25 leading-none">
          WIP
        </span>

        <div className="flex items-center gap-4">
          <Link
            href="/blog"
            className={`text-sm transition-colors ${
              pathname.startsWith("/blog")
                ? "text-[var(--foreground)]"
                : "text-[var(--muted)] hover:text-[var(--foreground)]"
            }`}
          >
            Blog
          </Link>
          <Link
            href="/reference"
            className={`text-sm transition-colors ${
              pathname === "/reference"
                ? "text-[var(--foreground)]"
                : "text-[var(--muted)] hover:text-[var(--foreground)]"
            }`}
          >
            Reference
          </Link>
          <GitHubLink />
        </div>
      </div>
    </header>
  );
}
