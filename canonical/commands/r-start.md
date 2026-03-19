# /r:start — Session Initialization

Reload context and display project health. This is the recommended
first command in any session. It gives the agent a warm handoff —
enough context to continue where the last session left off.

## Protocol

### 1. Clear Context

Run /clear to reset conversation context before loading fresh state.

### 2. Gather State

Run all data gathering in parallel where possible. Target: under
5 seconds wall time.

**From governance index** (`.claude/governance/index.md`):
- Project name (from `## Project` section)
- Operational mode (from `Mode:` line)
- Plan progress summary (from `Plan:` line)
- Governance file count

If governance does not exist, note it for the fallback display.

**From git:**
- Current branch: `git branch --show-current`
- HEAD hash: `git rev-parse --short HEAD`
- Dirty state: `git status --porcelain | wc -l`
- Last commit age: `git log -1 --format=%cr`
- Recent commits: `git log --oneline -5`

**From PLAN.md** (if present):
- Total phase count and per-phase status
- Current/next pending phase number and description
- Any phases marked in-progress

**From work-output/** (if present):
- Phase status files: `work-output/phase-*-status.md`
- Agent feed: last 5 entries from `work-output/agent-feed.log`
- Stale status files (mtime >1 hour)

**Governance age:**
- Stat mtime of `.claude/governance/index.md`
- Calculate hours since last modification

### 3. Display Session Anchor

```
+-- Session Anchor ------------------------------------------------+
| Project: {name}              Branch: {branch}                    |
| HEAD:    {hash} ({age})      Dirty: {N} files                   |
| Plan:    {M/N} phases        Mode: {mode}                       |
| Governance: {N} files        Age: {T}h since refresh             |
+------------------------------------------------------------------+
```

**Fallback (no governance):**

```
+-- Session Anchor ------------------------------------------------+
| Project: {basename of cwd}   Branch: {branch}                   |
| HEAD:    {hash} ({age})      Dirty: {N} files                   |
| Governance: not initialized                                      |
+------------------------------------------------------------------+
```

### 4. Display Plan Status

If PLAN.md exists and has phases, show a compact progress table:

```
### Plan Progress
| Phase | Description              | Status      |
|-------|--------------------------|-------------|
| 1     | {desc, truncated to 30c} | complete    |
| 2     | {desc}                   | complete    |
| 3     | {desc}                   | in-progress |
| 4     | {desc}                   | pending     |

Next: Phase 3 — {full description}
```

If no PLAN.md: `Plan: none — run /r:plan to create one.`

### 5. Display Last Session Summary

If `work-output/session-log.jsonl` exists, read the last entry and
display what happened in the previous session:

```
### Last Session ({age} ago)
- {N} commits on {branch}
- Completed: Phase {N} ({description})
- In progress: Phase {N} ({description})
```

If the session log does not exist, fall back to recent git commits:

```
### Recent Commits
- {hash} {message} ({age})
- {hash} {message} ({age})
- {hash} {message} ({age})
```

### 6. Display Agent Activity

If work-output/agent-feed.log exists and has entries newer than the
last commit, show the last 3 agent completions:

```
### Agent Activity
- {timestamp} {agent_type} on {project} — {preview}
- {timestamp} {agent_type} on {project} — {preview}
```

### 7. Warnings

Collect and display all warnings at the end:

```
### Warnings
- ⚠ Governance is {T}h old. Run /r:refresh to update.
- ⚠ {N} uncommitted files. Consider committing or stashing.
- ⚠ Phase {N} has stale status file (>1h old) — likely interrupted.
- ⚠ MEMORY.md is {N} lines (limit: 200). Run /r:util:mem-compact.
```

Only show the warnings section if there are warnings to display.

Governance stale threshold: >24 hours.
Dirty state threshold: >5 files.
Status file stale threshold: >1 hour.
Memory size threshold: >=180 lines.

### 8. Load CLAUDE.md

Read the project's `CLAUDE.md` (if present) to internalize project
instructions. Do NOT display its contents — just confirm it was loaded.

## Rules
- Do NOT load full governance file contents (architecture.md, etc.)
  — only the index. Agents load what they need just-in-time.
- Do NOT read full PLAN.md prose — extract phase names and statuses
  only. The plan is read in full when work begins.
- Do NOT read MEMORY.md — it is loaded into context automatically
  and is human-facing, not operational.
- Do NOT run tests, lint, or any expensive operations.
- Keep total output under 40 lines. Use tables over prose.
- Target under 5 seconds wall time — all git commands can run in
  parallel.
