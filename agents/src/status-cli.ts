#!/usr/bin/env bun

import { readFile } from "node:fs/promises";

import { readJobsDocument } from "./lib/jobs-store.js";
import { paths } from "./lib/paths.js";
import { formatDuration } from "./lib/time.js";
import type { AgentsDaemonStatus } from "./lib/types.js";

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

async function readPid(): Promise<number | null> {
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

function defaultStatus(): AgentsDaemonStatus {
  return {
    ok: true,
    running: false,
    framework: "pi.dev",
    mode: "stub",
    pid: null,
    started_at: null,
    uptime_seconds: null,
    workspace: paths.workspaceDir,
    jobs_file: paths.jobsFile,
    jobs: {
      total: 0,
      scheduled: 0,
      queued_for_pi_dev: 0,
      overdue: 0,
      next_timestamp: null
    },
    services: {
      scheduled_jobs: "inactive",
      heartbeats: "stub",
      scheduler: "stub"
    },
    last_tick_at: null,
    last_error: null
  };
}

async function readStatusFile(): Promise<AgentsDaemonStatus | null> {
  try {
    const raw = await readFile(paths.statusFile, "utf8");
    return JSON.parse(raw) as AgentsDaemonStatus;
  } catch {
    return null;
  }
}

function countJobs(status: Awaited<ReturnType<typeof readJobsDocument>>): AgentsDaemonStatus["jobs"] {
  const now = Date.now();
  const scheduled = status.jobs.filter((job) => job.status === "scheduled");
  const queued = status.jobs.filter((job) => job.status === "queued_for_pi_dev");
  const overdue = scheduled.filter((job) => new Date(job.timestamp).getTime() <= now);
  const next = scheduled
    .map((job) => new Date(job.timestamp).getTime())
    .filter((ts) => Number.isFinite(ts))
    .sort((a, b) => a - b)[0];

  return {
    total: status.jobs.length,
    scheduled: scheduled.length,
    queued_for_pi_dev: queued.length,
    overdue: overdue.length,
    next_timestamp: Number.isFinite(next) ? new Date(next).toISOString() : null
  };
}

function printHuman(status: AgentsDaemonStatus): void {
  const state = status.running ? "RUNNING" : "STOPPED";
  const uptime = status.uptime_seconds ? formatDuration(status.uptime_seconds) : "-";
  const nextRun = status.jobs.next_timestamp ?? "-";

  console.log("agents daemon status");
  console.log("====================");
  console.log(`state: ${state}`);
  console.log(`framework: ${status.framework} (${status.mode})`);
  console.log(`pid: ${status.pid ?? "-"}`);
  console.log(`uptime: ${uptime}`);
  console.log(`jobs: total=${status.jobs.total} scheduled=${status.jobs.scheduled} queued=${status.jobs.queued_for_pi_dev}`);
  console.log(`next job: ${nextRun}`);
  console.log(`workspace: ${status.workspace}`);
}

async function main(): Promise<void> {
  const jsonMode = process.argv.includes("--json");
  const pid = await readPid();
  const running = pid !== null && isPidRunning(pid);

  const jobs = countJobs(await readJobsDocument());
  const fromFile = await readStatusFile();
  const base = fromFile ?? defaultStatus();
  const status: AgentsDaemonStatus = running
    ? {
        ...base,
        running: true,
        pid,
        jobs
      }
    : {
        ...base,
        running: false,
        pid: null,
        started_at: null,
        uptime_seconds: null,
        jobs,
        services: {
          ...base.services,
          scheduled_jobs: "inactive"
        }
      };

  if (jsonMode) {
    console.log(JSON.stringify(status));
    return;
  }

  printHuman(status);
}

await main();
