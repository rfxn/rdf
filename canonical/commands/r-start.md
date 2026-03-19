# /r:start — Session Initialization

Reload context and display project health. This is the recommended
first command in any session. It gives the agent a warm handoff —
enough context to continue where the last session left off.

## Progress Tracking

**If TaskCreate tool is available** (Claude Code):
```
TaskCreate: subject: "Initialize session"
  activeForm: "Loading project context"
```
Mark `in_progress` at start, `completed` before the dashboard.

**If TaskCreate is NOT available** (Gemini CLI, Codex):
Output `- [ ] Loading project context...` before starting.
Replace with `- [x] Session loaded` when complete.

## Protocol

### 1. Clear Context

Run /clear to reset conversation context before loading fresh state.

### 2. Gather State

Run all data gathering in parallel where possible. Target: under
5 seconds wall time. Batch git commands into single invocations.
Do NOT display results — all output consolidates into section 3.

**Git state** (single-project — cwd is a git repo):
```bash
# Run these in ONE bash call:
git branch --show-current
git rev-parse --short HEAD
git log -1 --format=%cr
git status --porcelain | wc -l
git log --oneline -5
```

**Git state** (parent workspace — cwd is NOT a git repo):
- Enumerate sub-project repos: directories containing `.git/`
- For each: branch, HEAD hash, dirty count, last commit age
- Aggregate: total repos, active (commits <24h), total dirty

**Governance** (`.rdf/governance/index.md` or `.claude/governance/index.md`):
- Project name, operational mode, plan progress, file count
- Governance age: stat mtime, calculate hours since modification
- If governance does not exist, note for fallback display

**PLAN.md** (if present):
- Total phase count and per-phase status (complete/in-progress/pending/blocked)
- Current/next pending phase number and description

**Pipeline position** (same logic as r-save):
- `docs/specs/` has files + no PLAN.md → `spec`
- PLAN.md with pending phases → `plan`
- PLAN.md with in-progress phases → `build phase N/M`
- PLAN.md with all complete → `ship`
- None → `idle`

**In-flight work** (lightweight checks, parallel with git):
- `HANDOFF.md`: read title + first 3 progress lines
- `work-output/spec-progress.md`: read TOPIC + PHASE
- `work-output/ship-progress.md`: read STAGE
- `work-output/current-phase.md`: read PROJECT_NAME, PHASE, PHASE_TITLE
- `PLAN.md` / `PLAN-*.md`: grep for `in-progress` or `blocked`
- `work-output/session-log.jsonl`: read last entry

**Suppression rules:**
- Plans with ALL phases `complete`: omit
- Plans with only `pending` (no in-progress/blocked): show only if
  modified within 7 days
- `current-phase.md` older than 30 days: omit

**Session log** (if exists):
- Read last entry for: commits, diff_summary, pipeline, insight
- Calculate age for "Last session" display

**Insights:**
- Read `~/.rdf/insights.jsonl` for display
- Read `~/.rdf/lessons-learned.md` to confirm it exists

### 3. Display Dashboard

ONE consolidated block. This is the ONLY visible output from the
entire start operation.

**Target: under 20 lines for single-project, under 15 for workspace.**

---

**Single-project dashboard:**

```
### {Project} {version} — `{branch}` @ `{hash}` ({age}) · {pipeline}

| Plan | Dirty | Mode | Governance |
|------|-------|------|------------|
| {M}/{N} phases | {N} files | {mode} | {N} files ({T}h) |

{in-flight — only if signals exist}

{plan progress — capped at 5 phases}

{last session line}

{warnings — only if thresholds exceeded}

{insights — only if entries exist}
```

**Parent workspace dashboard:**

```
### {workspace} — {N} repos, {N} active · {most_recent_pipeline}

| Last Activity | Dirty | MEMORY.md |
|---------------|-------|-----------|
| {project}: `{hash}` ({age}) | {N} files / {M} repos | {N}/200 |

{in-flight signals across repos}

{recent activity — top 3 commits across repos}

{warnings}

{insights}
```

---

### Section rendering

**Heading** — one dense line packing: project, version, branch,
hash, age, and pipeline stage. Pipeline stage at the end tells the
user where they are in the arc (idle/spec/plan/build/ship).

**Status table** — one row, four columns. No multi-row tables.
If governance doesn't exist, replace that cell with `none — /r:init`.

**In-flight** — show only if signals fire:

```
> **In Flight**: {signal summary}
```

For 1-2 signals, pack into one line with semicolons:
```
> **In Flight**: Spec — pipeline design, Phase 2; Plan — 7 pending phases
```

For 3+ signals, use bulleted blockquote:
```
> **In Flight** — {N} signals
> - **Handoff**: {title} — {progress}
> - **Plan**: Phase 4 *in-progress*
> - **Spec**: {topic} — Phase {N}
```

Signal priority: Handoff > Spec > Ship > Plan (in-progress) >
Plan (pending) > Dispatch (stale).

**Plan progress** — task list, capped at 5 visible phases:

```
- [x] Phase 1 — {desc, 30c max}
- [x] Phase 2 — {desc}
- [ ] **Phase 3 — {desc}** *(in-progress)*
- [ ] Phase 4 — {desc}
- [ ] Phase 5 — {desc}
  *+ 2 more phases*
```

Phase styling:
- `[x]` + plain = complete
- `[ ]` + **bold** + *(in-progress)* = current work
- `[ ]` + plain = pending
- `[ ]` + ~~strikethrough~~ + *(blocked)* = blocked

If >5 phases: show first 2 complete + current + next 2 pending,
then `*+ N more phases*` in italic. Full list is in PLAN.md.

If no PLAN.md: omit section entirely. Pipeline stage in the
heading already signals `idle`.

**Last session** — one line, prefer session log over git log:

From session log (if exists):
```
Last: {N} commits · {diff_summary} · {pipeline} *({age})*
```

Fallback (no session log) — 3 most recent commits:
```
- `{hash}` {message} *({age})*
- `{hash}` {message} *({age})*
- `{hash}` {message} *({age})*
```

**Warnings** — one blockquote line, pipe-separated:

```
> ⚠ Governance {T}h old — `/r:refresh` | MEMORY.md {N}/200 — `/r:util:mem-compact`
```

Thresholds:
- Governance stale: >24 hours
- Dirty state: >5 files
- Status file stale: >1 hour
- Memory size: >=180 lines

If no thresholds exceeded, omit entirely.

**Insights** — at the bottom, no heading or rule needed:

```
> **Insights**
> - **{project}**: {insight text} *— {tool}, {age}*
> - {insight text} *— {project}, {tool}, {age}*
```

Selection (two-tier, 3 max):
1. Most recent project-matching entry = pinned (bold project name)
2. 2 most recent from remaining entries = universal
3. No project match = 3 most recent universal
4. Fewer than 3 total = show what exists

If no insights exist, omit entirely.

### 4. Load CLAUDE.md

Read the project's `CLAUDE.md` (if present) to internalize project
instructions. Do NOT display its contents — just confirm loaded.

## Rules
- Do NOT load full governance file contents — only the index
- Do NOT read full PLAN.md prose — extract phase names and statuses
- Do NOT read MEMORY.md — it loads automatically
- Do NOT run tests, lint, or any expensive operations
- Keep total output under 20 lines
- Target under 5 seconds wall time — batch git commands
