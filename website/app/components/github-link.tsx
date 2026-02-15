"use client";

import { useState, useEffect } from "react";
import { Github, Star } from "lucide-react";

export function GitHubLink({ className = "" }: { className?: string }) {
  const [stars, setStars] = useState<number | null>(null);

  useEffect(() => {
    fetch("https://api.github.com/repos/north-brook/broker-cli", {
      headers: { Accept: "application/vnd.github.v3+json" },
    })
      .then((r) => r.json())
      .then((d) => {
        if (typeof d.stargazers_count === "number")
          setStars(d.stargazers_count);
      })
      .catch(() => {});
  }, []);

  return (
    <a
      href="https://github.com/north-brook/broker-cli"
      target="_blank"
      rel="noopener noreferrer"
      className={`flex items-center gap-1.5 rounded-lg border border-[var(--border)] px-3 py-1.5 text-sm text-[var(--muted)] hover:border-[var(--accent-dim)] hover:text-[var(--foreground)] transition-colors ${className}`}
    >
      <Github size={16} />
      {stars !== null && (
        <>
          <Star className="fill-amber-400 text-amber-400" size={12} />
          <span className="tabular-nums">{stars}</span>
        </>
      )}
    </a>
  );
}
