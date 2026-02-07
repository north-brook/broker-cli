export type JobStatus = "scheduled" | "queued_for_pi_dev" | "cancelled";

export interface ScheduledJob {
  id: string;
  timestamp: string;
  agentId: string;
  prompt: string;
  status: JobStatus;
  createdAt: string;
  updatedAt: string;
  queuedAt?: string;
}

export interface JobsDocument {
  version: 1;
  framework: "pi.dev";
  jobs: ScheduledJob[];
}

export interface AgentsDaemonStatus {
  ok: boolean;
  running: boolean;
  framework: "pi.dev";
  mode: "stub";
  pid: number | null;
  started_at: string | null;
  uptime_seconds: number | null;
  workspace: string;
  jobs_file: string;
  jobs: {
    total: number;
    scheduled: number;
    queued_for_pi_dev: number;
    overdue: number;
    next_timestamp: string | null;
  };
  services: {
    scheduled_jobs: "stub_active" | "inactive";
    heartbeats: "stub";
    scheduler: "stub";
  };
  last_tick_at: string | null;
  last_error: string | null;
}
