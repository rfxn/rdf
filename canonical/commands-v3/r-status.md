# /r:status — Project Health Dashboard

Display a structured overview of project health: plan progress, phase
outcomes, governance freshness, and recent activity.

## Protocol

### 1. Read Governance Index

Read `.claude/governance/index.md` for project metadata.

If missing, display minimal status from git only (branch, HEAD, recent
commits) and note that governance is not initialized.

### 2. Read Plan Progress

Read `PLAN.md` from the project root.

If present, extract:
- Total phase count
- Per-phase status (pending, in-progress, complete)
- Current/next pending phase number and description
- Execution mode tags per phase

If absent, display: "No active plan. Run /r:plan to create one."

### 3. Read Phase Status Files

Scan `work-output/` for phase status files written by the dispatcher.
These files follow the pattern `work-output/phase-N-status.md`.

For each status file found, extract:
- Phase number
- Result (pass/fail)
- Gate results (which gates ran, pass/fail per gate)
- Timestamp

### 4. Check Governance Freshness

Stat `.claude/governance/index.md` for mtime. Calculate age in hours.
Flag if >24h stale.

### 5. Gather Git Activity

Run:
- `git log --oneline -5` for recent commits
- `git status --porcelain | wc -l` for dirty file count

### 6. Render Dashboard

```
## {Project} — {branch}

### Plan Progress
| Phase | Description          | Mode            | Status      |
|-------|----------------------|-----------------|-------------|
| 1     | {desc}               | serial-context  | complete    |
| 2     | {desc}               | serial-agent    | in-progress |
| 3     | {desc}               | parallel-agent  | pending     |

Progress: {M}/{N} phases complete

### Phase Outcomes (from work-output/)
| Phase | Result | Gates          | Retries | Timestamp  |
|-------|--------|----------------|---------|------------|
| 1     | PASS   | G1+G2          | 0       | 2026-03-18 |

### Governance
- Files: {N} governance files
- Age: {T}h since last refresh
- Mode: {mode}
{if stale: "⚠ Stale — run /r:refresh"}

### Recent Commits
- {hash} — {message}
- {hash} — {message}
- {hash} — {message}

### Warnings
{dirty state, stale governance, failed phases, blocked phases}
```

If there is no plan and no governance, display a minimal dashboard:

```
## {basename} — {branch}

HEAD: {hash} | Dirty: {N} files
Governance: not initialized
Plan: none

Recent commits:
- {hash} — {message}

Next steps: Run /r:init to generate governance, then /r:plan.
```

## Rules
- Read-only — do NOT modify any files
- Do NOT run tests or lint — this is a status check
- Do NOT load full governance files — index only
- If work-output/ does not exist or is empty, skip the phase outcomes
  section silently
- Keep output structured and scannable — tables over prose
