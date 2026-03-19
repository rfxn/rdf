# /r:start — Session Initialization

Reload context and display project health. This is the recommended
first command in any session. It gives the agent a warm handoff —
enough context to continue where the last session left off.

## Protocol

### 1. Clear Context

Run /clear to reset conversation context before loading fresh state.

### 2. Gather State

Run all data gathering in parallel where possible. Target: under
5 seconds wall time. Do NOT display results as they are gathered —
all output is consolidated into the single dashboard in section 3.

**From governance index** (`.claude/governance/index.md`):
- Project name (from `## Project` section)
- Operational mode (from `Mode:` line)
- Plan progress summary (from `Plan:` line)
- Governance file count

If governance does not exist, note it for the fallback display.

**From git** (single-project — cwd is a git repo):
- Current branch: `git branch --show-current`
- HEAD hash: `git rev-parse --short HEAD`
- Dirty state: `git status --porcelain | wc -l`
- Last commit age: `git log -1 --format=%cr`
- Recent commits: `git log --oneline -5`

**From git** (parent workspace — cwd is NOT a git repo):
- Enumerate sub-project repos: directories containing `.git/`
- For each: branch, HEAD hash, dirty count, last commit age
- Aggregate: total repos, repos with commits <24h (active), total
  dirty files, most recent commit (project + hash + age)

**From PLAN.md** (if present):
- Total phase count and per-phase status
- Current/next pending phase number and description
- Any phases marked in-progress

**From work-output/** (if present):
- Phase status files: `work-output/phase-*-status.md`
- Stale status files (mtime >1 hour)

**Governance age:**
- Stat mtime of `.claude/governance/index.md`
- Calculate hours since last modification

**In-flight work detection** (run in parallel with other checks):

Scan for signals of interrupted or ongoing workstreams. These are
lightweight checks — grep for status keywords, check file existence,
read first lines only.

- `HANDOFF.md` in cwd: if present, read the `# Handoff:` title line
  and `## Current Progress` section (first 3 lines after the heading)
  to extract what was interrupted and how far it got
- `work-output/spec-progress.md`: if present, read `TOPIC` and
  `PHASE` lines to determine spec subject and current phase
- `work-output/ship-progress.md`: if present, read `STAGE` line
  to determine current shipping stage
- `work-output/current-phase.md`: if present, read `PROJECT_NAME`,
  `PHASE`, and `PHASE_TITLE` lines. Flag as stale if mtime >24h
- `PLAN-*.md` at workspace root: for each, grep for table rows
  containing `in-progress` or `blocked`. Ignore files where all
  phases are `complete` or `pending` with none in-progress
- `*/PLAN.md` in sub-projects: same grep — find any project with
  phases marked `in-progress` or `blocked`
- `work-output/session-log.jsonl`: if present, read last entry for
  the previous session's end-state

**In-flight suppression rules:**
- Plans where ALL phases are `complete`: omit entirely
- Plans where all non-complete phases are `pending` and no phases
  are `in-progress` or `blocked`: show only if the plan was modified
  within the last 7 days (recent intent, not ancient debris)
- `current-phase.md` older than 30 days: omit (dead context)

**Insights** (parallel with other checks):
- Read `~/.rdf/insights.jsonl` for display in the dashboard
- Read `~/.rdf/lessons-learned.md` to confirm it exists (for the
  agent's own awareness, not for display)

### 3. Display Dashboard

All output is ONE consolidated block. This is the only visible
output from the entire start operation. Target: under 25 lines.

**Single-project dashboard:**

```
### {Project} {version} — `{branch}` @ `{hash}` ({age})

| Plan | Dirty | Mode | Governance |
|------|-------|------|------------|
| {M}/{N} phases | {N} files | {mode} | {N} files ({T}h) |

{in-flight block — only if signals exist}

{plan progress — only if PLAN.md exists}

{recent commits OR last session summary}

{warnings — inline, only if any}

---

{insights block — only if insights exist}
```

**Parent workspace dashboard:**

```
### {workspace} — {N} repos, {N} active

| Last Activity | Dirty | MEMORY.md |
|---------------|-------|-----------|
| {project}: `{hash}` ({age}) | {N} files / {M} repos | {N}/200 |

{in-flight block}

{recent activity across repos}

---

{insights block}
```

### Section details

**In-flight block** — show only if signals fire. Compact format:

```
> **In Flight**: {one-line per signal, semicolon-separated if <=2}

> **In Flight** — {N} signals
> - **Handoff**: {title} — {progress}
> - **Plan**: `PLAN.md` — Phase 4 *in-progress*
> - **Spec**: {topic} — Phase {N}
```

For 1-2 signals, use a single `>` line with semicolons. For 3+
signals, use the bulleted list format. Signal priority order:
Handoff > Spec > Ship > Plan (in-progress) > Plan (pending) >
Dispatch (stale).

**Plan progress** — task list checkboxes:

```
- [x] Phase 1 — {desc, 30c max}
- [ ] **Phase 3 — {desc}** *(in-progress)*
- [ ] Phase 4 — {desc}

Next: Phase 3 — {full description}
```

Phase styling:
- `[x]` + plain text = complete
- `[ ]` + **bold** + *(in-progress)* italic = current work
- `[ ]` + plain text = pending
- `[ ]` + ~~strikethrough~~ + *(blocked)* italic = blocked

If no PLAN.md: `Plan: none — `/r:plan` to create one.`

**Recent commits / last session** — prefer session log if available:

From session log:
```
Last session ({age}): {N} commits — {summary of work}
```

Fallback to git log (3 commits max):
```
- `{hash}` {message} *({age})*
- `{hash}` {message} *({age})*
- `{hash}` {message} *({age})*
```

**Warnings** — inline blockquote, only if warnings exist:

```
> **Warn**: Governance {T}h old — `/r:refresh` | MEMORY.md {N}/200 — `/r:util:mem-compact`
```

Use pipe `|` separators for multiple warnings on one line.
Only show if thresholds are exceeded:
- Governance stale: >24 hours
- Dirty state: >5 files
- Status file stale: >1 hour
- Memory size: >=180 lines

**Insights block** — separated by horizontal rule, at the bottom:

```
---

### Insights

> - **{project}**: {insight text} *— {tool}, {age}*
> - {insight text} *— {project}, {tool}, {age}*
> - {insight text} *— {project}, {tool}, {age}*
```

Selection (two-tier, 3 max):
1. Most recent project-matching entry = pinned (bold project name)
2. 2 most recent from remaining entries = universal
3. No project match = 3 most recent universal
4. Fewer than 3 total = show what exists

If no insights exist, omit the rule and the entire section.

### 4. Load CLAUDE.md

Read the project's `CLAUDE.md` (if present) to internalize project
instructions. Do NOT display its contents — just confirm it was
loaded as the last line of output.

## Rules
- Do NOT load full governance file contents (architecture.md, etc.)
  — only the index. Agents load what they need just-in-time.
- Do NOT read full PLAN.md prose — extract phase names and statuses
  only. The plan is read in full when work begins.
- Do NOT read MEMORY.md — it is loaded into context automatically
  and is human-facing, not operational.
- Do NOT run tests, lint, or any expensive operations.
- Keep total output under 25 lines. Consolidate into the single
  dashboard — no incremental per-section displays.
- Target under 5 seconds wall time — all git commands can run in
  parallel.
