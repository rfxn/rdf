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
- Agent feed: last 5 entries from `work-output/agent-feed.log`
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
  the previous session's end-state (already gathered in step 5)

### 3. Display Session Anchor

Use a 4-column markdown table with meaningful headers. The anchor
answers: "Where am I? What's the state? What needs attention?"

**Single-project anchor** (inside a git repo):

```
### Session Anchor
| Property | Value | Property | Value |
|----------|-------|----------|-------|
| **Project** | {name} {version} | **Branch** | {branch} |
| **HEAD** | {hash} ({age}) | **Dirty** | {N} files |
| **Plan** | {M/N} phases | **Mode** | {mode} |
| **Governance** | {N} files ({T}h old) | **Last commit** | {1-line summary} |
```

**Parent workspace anchor** (not a git repo, multiple sub-projects):

Gather aggregate state: count sub-project directories that contain
`.git/`, sum dirty files across all, find the most recent commit
across all projects.

```
### Session Anchor
| Property | Value | Property | Value |
|----------|-------|----------|-------|
| **Workspace** | {basename} | **Projects** | {N} repos |
| **Active** | {N} with commits <24h | **Dirty** | {N} files across {M} repos |
| **Last activity** | {project}: {hash} ({age}) | **MEMORY.md** | {N}/200 lines |
```

Drop governance row for parent workspaces — governance is per-project.
Drop date — the terminal and system context already provide it.
MEMORY.md line count belongs here only for parent workspaces (the
constraint is workspace-scoped); for single projects it moves to
the warnings section at >=180 lines.

### 4. Display In-Flight Work

Show this section only if at least one signal fires. It answers:
"Is there interrupted work I should resume or clean up?"

Use a blockquote header with task list items. Task lists give
instant visual state — unchecked = needs attention, checked = resolved
or acknowledged. The blockquote draws the eye to this section.

```
> **In Flight** — {N} signals

- [ ] **Handoff**: {title} — {progress summary}
- [ ] **Spec**: {topic} — Phase {N} *{phase name}*
- [ ] **Ship**: {current stage}
- [ ] **Plan**: `brute-force-detection/PLAN.md` — Phase 4 *in-progress*
- [ ] **Plan**: `PLAN-pkglib.md` — 3 pending phases
- [ ] **Dispatch**: `current-phase.md` — pkg_lib Phase 1 *(stale, 12d)*
```

**Signal priority** (display order):
1. **Handoff** — explicit interrupted session. Always show first.
2. **Spec** — active spec design. Show topic and current phase from
   `work-output/spec-progress.md`.
3. **Ship** — active shipping workflow. Show current stage from
   `work-output/ship-progress.md`.
4. **Plan (in-progress/blocked)** — active workstreams. Show project
   name, which phases are in-progress or blocked. Use *italic* for
   the status keyword.
5. **Plan (has pending phases)** — dormant plans with unfinished work.
   Show count of pending phases only (no per-phase detail).
6. **Dispatch** — stale `current-phase.md`. Show project, phase, age
   in *(italic parenthetical)*.

**Suppression rules:**
- Plans where ALL phases are `complete`: omit entirely
- Plans where all non-complete phases are `pending` and no phases
  are `in-progress` or `blocked`: show only if the plan was modified
  within the last 7 days (recent intent, not ancient debris)
- `current-phase.md` older than 30 days: omit (dead context)
- If no signals fire, skip this section entirely

**For parent workspaces:** scan both root `PLAN-*.md` files and
`*/PLAN.md` inside sub-project directories. For single-project
workspaces: scan only `PLAN.md` in cwd.

### 5. Display Plan Status

If PLAN.md exists and has phases, use task list checkboxes — they
communicate completion state at a glance without needing a status
column. Bold the in-progress phase to draw focus.

```
### Plan Progress
- [x] Phase 1 — {desc, truncated to 30c}
- [x] Phase 2 — {desc}
- [ ] **Phase 3 — {desc}** *(in-progress)*
- [ ] Phase 4 — {desc}

Next: Phase 3 — {full description}
```

Phase styling:
- `[x]` + plain text = complete
- `[ ]` + **bold** + *(in-progress)* italic = current work
- `[ ]` + plain text = pending
- `[ ]` + ~~strikethrough~~ + *(blocked)* italic = blocked

If no PLAN.md: `Plan: none — run /r:plan to create one.`

### 6. Display Last Session Summary

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

### 7. Display Agent Activity

If work-output/agent-feed.log exists and has entries newer than the
last commit, show the last 3 agent completions:

```
### Agent Activity
- {timestamp} {agent_type} on {project} — {preview}
- {timestamp} {agent_type} on {project} — {preview}
```

### 8. Warnings

Collect and display warnings using a blockquote. The vertical bar
naturally reads as "pay attention" and visually separates warnings
from the data sections above.

```
> **Warnings**
> - Governance is {T}h old — run `/r:refresh`
> - {N} uncommitted files across {M} repos
> - Phase {N} status file is stale (>1h) — likely interrupted
> - MEMORY.md at {N}/200 lines — run `/r:util:mem-compact`
```

Only show the warnings block if there are warnings to display.
Use inline code for command references so they stand out as
actionable.

Governance stale threshold: >24 hours.
Dirty state threshold: >5 files.
Status file stale threshold: >1 hour.
Memory size threshold: >=180 lines.

### 9. Load CLAUDE.md

Read the project's `CLAUDE.md` (if present) to internalize project
instructions. Do NOT display its contents — just confirm it was loaded.

## Formatting Guide

Available markdown primitives and when to use them:

| Primitive | Syntax | Best for |
|-----------|--------|----------|
| **Table** | `\| col \| col \|` | Structured data, dashboards, key-value pairs |
| **Task list** | `- [x]` / `- [ ]` | Phase progress, in-flight items, checklists |
| **Blockquote** | `>` | Warnings, callouts, anything needing visual separation |
| **Bold** | `**text**` | Labels, section headers within lists |
| **Italic** | `*text*` | Status keywords, secondary info, parentheticals |
| **Bold+italic** | `***text***` | Urgent emphasis (use sparingly) |
| **Inline code** | `` `text` `` | Paths, hashes, commands, values that need to pop |
| **Strikethrough** | `~~text~~` | Blocked/suppressed items |
| **Heading** | `##` / `###` | Major / minor section breaks |
| **Rule** | `---` | Lightweight section divider (lighter than heading) |

**Do NOT use** (not rendered in Claude Code):
HTML tags, `<details>`, ANSI color codes, Mermaid diagrams, footnotes.

## Rules
- Do NOT load full governance file contents (architecture.md, etc.)
  — only the index. Agents load what they need just-in-time.
- Do NOT read full PLAN.md prose — extract phase names and statuses
  only. The plan is read in full when work begins.
- Do NOT read MEMORY.md — it is loaded into context automatically
  and is human-facing, not operational.
- Do NOT run tests, lint, or any expensive operations.
- Keep total output under 40 lines. Use tables, task lists, and
  blockquotes over prose — see Formatting Guide above.
- Target under 5 seconds wall time — all git commands can run in
  parallel.
