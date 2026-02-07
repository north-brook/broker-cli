import path from "node:path";
import { homedir } from "node:os";

const HOME = process.env.NORTHBROOK_HOME ?? path.join(homedir(), ".northbrook");

export const paths = {
  northbrookHome: HOME,
  workspaceDir: process.env.NORTHBROOK_WORKSPACE ?? path.join(HOME, "workspace"),
  agentsDir: process.env.NORTHBROOK_AGENTS_HOME ?? path.join(HOME, "agents"),
  jobsFile: process.env.NORTHBROOK_JOBS_FILE ?? path.join(HOME, "workspace", "scheduled-jobs.json"),
  pidFile: process.env.NORTHBROOK_AGENTS_PID_FILE ?? path.join(HOME, "agents", "agents-daemon.pid"),
  statusFile: process.env.NORTHBROOK_AGENTS_STATUS_FILE ?? path.join(HOME, "agents", "agents-daemon.status.json"),
  logFile: process.env.NORTHBROOK_AGENTS_LOG_FILE ?? path.join(HOME, "agents", "agents-daemon.log"),
  executionsLogFile:
    process.env.NORTHBROOK_AGENTS_EXECUTIONS_LOG_FILE ?? path.join(HOME, "agents", "scheduled-job-executions.jsonl")
};
