#!/usr/bin/env bun

import { appendFile, mkdir, readFile, unlink, writeFile } from "node:fs/promises";
import path from "node:path";

import { findJobById, readJobsDocument, writeJobsDocument } from "./lib/jobs-store.js";
import { paths } from "./lib/paths.js";
import { nowIso } from "./lib/time.js";
import type { AgentsDaemonStatus } from "./lib/types.js";

const TICK_INTERVAL_MS = 5_000;

const startedAt = new Date();
let lastTickAt: string | null = null;
let lastError: string | null = null;
let timer: NodeJS.Timeout | null = null;

function isPidRunning(pid: number): boolean {
  if (!Number.isInteger(pid) || pid <= 0) {
    return false;
  }
  try {
    process.kill(pid, 0);
    return true;
  } catch {
    return false;
  }
}

async function readPidFile(): Promise<number | null> {
  try {
    const raw = await readFile(paths.pidFile, "utf8");
    const pid = Number.parseInt(raw.trim(), 10);
    if (Number.isInteger(pid) && pid > 0) {
      return pid;
    }
    return null;
  } catch {
    return null;
  }
}

function countJobs(doc: Awaited<ReturnType<typeof readJobsDocument>>): AgentsDaemonStatus["jobs"] {
  const now = Date.now();
  const scheduled = doc.jobs.filter((job) => job.status === "scheduled");
  const queued = doc.jobs.filter((job) => job.status === "queued_for_pi_dev");
  const overdue = scheduled.filter((job) => new Date(job.timestamp).getTime() <= now);
  const next = scheduled
    .map((job) => new Date(job.timestamp).getTime())
    .filter((ts) => Number.isFinite(ts))
    .sort((a, b) => a - b)[0];

  return {
    total: doc.jobs.length,
    scheduled: scheduled.length,
    queued_for_pi_dev: queued.length,
    overdue: overdue.length,
    next_timestamp: Number.isFinite(next) ? new Date(next).toISOString() : null
  };
}

async function buildStatus(running: boolean): Promise<AgentsDaemonStatus> {
  const jobsDoc = await readJobsDocument();
  const pid = running ? process.pid : null;

  return {
    ok: true,
    running,
    framework: "pi.dev",
    mode: "stub",
    pid,
    started_at: running ? startedAt.toISOString() : null,
    uptime_seconds: running ? Math.floor((Date.now() - startedAt.getTime()) / 1000) : null,
    workspace: paths.workspaceDir,
    jobs_file: paths.jobsFile,
    jobs: countJobs(jobsDoc),
    services: {
      scheduled_jobs: running ? "stub_active" : "inactive",
      heartbeats: "stub",
      scheduler: "stub"
    },
    last_tick_at: lastTickAt,
    last_error: lastError
  };
}

async function writeStatus(running: boolean): Promise<void> {
  const status = await buildStatus(running);
  await mkdir(path.dirname(paths.statusFile), { recursive: true });
  await writeFile(paths.statusFile, `${JSON.stringify(status, null, 2)}\n`, "utf8");
}

async function appendExecutionIntent(entry: {
  job_id: string;
  timestamp: string;
  agent_id: string;
  prompt: string;
}): Promise<void> {
  const line = {
    ...entry,
    framework: "pi.dev",
    mode: "stub",
    queued_at: nowIso(),
    note: "Scheduled job queued for future pi.dev executor"
  };
  await appendFile(paths.executionsLogFile, `${JSON.stringify(line)}\n`, "utf8");
}

async function processScheduledJobs(): Promise<void> {
  const document = await readJobsDocument();
  const now = Date.now();
  let changed = false;

  for (const job of document.jobs) {
    if (job.status !== "scheduled") {
      continue;
    }
    const dueAt = new Date(job.timestamp).getTime();
    if (!Number.isFinite(dueAt) || dueAt > now) {
      continue;
    }

    const existing = findJobById(document, job.id);
    if (!existing) {
      continue;
    }

    await appendExecutionIntent({
      job_id: existing.id,
      timestamp: existing.timestamp,
      agent_id: existing.agentId,
      prompt: existing.prompt
    });

    existing.status = "queued_for_pi_dev";
    existing.queuedAt = nowIso();
    existing.updatedAt = nowIso();
    changed = true;
  }

  if (changed) {
    await writeJobsDocument(document);
  }
}

async function tick(): Promise<void> {
  try {
    await processScheduledJobs();
    lastError = null;
  } catch (error) {
    lastError = error instanceof Error ? error.message : String(error);
  } finally {
    lastTickAt = nowIso();
    await writeStatus(true);
  }
}

async function shutdown(): Promise<void> {
  if (timer) {
    clearInterval(timer);
    timer = null;
  }

  await writeStatus(false);
  await unlink(paths.pidFile).catch(() => undefined);
  process.exit(0);
}

async function main(): Promise<void> {
  await mkdir(paths.agentsDir, { recursive: true });
  await mkdir(paths.workspaceDir, { recursive: true });
  await mkdir(path.dirname(paths.jobsFile), { recursive: true });

  const existingPid = await readPidFile();
  if (existingPid && existingPid !== process.pid && isPidRunning(existingPid)) {
    console.error(`agents-daemon already running (pid ${existingPid})`);
    process.exit(0);
  }

  await writeFile(paths.pidFile, `${process.pid}\n`, "utf8");

  process.once("SIGTERM", () => {
    void shutdown();
  });
  process.once("SIGINT", () => {
    void shutdown();
  });

  await tick();
  timer = setInterval(() => {
    void tick();
  }, TICK_INTERVAL_MS);
}

await main();
