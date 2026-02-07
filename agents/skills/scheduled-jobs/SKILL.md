# Scheduled Jobs Skill (pi.dev-aligned)

This skill manages background scheduled jobs for Northbrook agents.

## Purpose

Provide an agent-friendly scheduling interface while the full pi.dev agent loop integration is still in progress.

Current status:
- Create/list/edit/remove jobs is fully implemented.
- Daemon execution is a **stub** that marks due jobs as `queued_for_pi_dev`.
- Final dispatch into pi.dev agent executors will be added in a future milestone.

## Data Model

Jobs are stored in `~/.northbrook/workspace/scheduled-jobs.json`.

Each job includes at minimum:
- `timestamp` (ISO-8601)
- `agentId`
- `prompt`

Additional metadata supports safe operations and future pi.dev execution handoff:
- `id`, `status`, `createdAt`, `updatedAt`, optional `queuedAt`

## CLI

Use via `nb jobs`:

```bash
nb jobs create --agent <agentId> --in 30m --prompt "Review overnight earnings"
nb jobs list
nb jobs show <jobId>
nb jobs edit <jobId> --prompt "Updated prompt"
nb jobs remove <jobId>
```

## pi.dev Alignment Notes

- `framework` marker is persisted as `pi.dev`.
- Due jobs transition to `queued_for_pi_dev` to model dispatch intent.
- Execution intents are logged to `~/.northbrook/agents/scheduled-job-executions.jsonl`.
- Future pi.dev handoff should consume queued jobs, execute prompts in agent runtime contexts, then update job lifecycle state.
