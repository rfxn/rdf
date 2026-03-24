# /r-status — Project Health Dashboard

Display a structured overview of project health: plan progress, phase
outcomes, governance freshness, and recent activity.

## Protocol

### 1. Read Governance Index

Read `.rdf/governance/index.md` for project metadata.

If missing, display minimal status from git only (branch, HEAD, recent
commits) and note that governance is not initialized.

### 2. Read Plan Progress

Read `PLAN.md` from the project root.

If present, extract:
- Total phase count
- Per-phase status (pending, in-progress, complete)
- Current/next pending phase number and description
- Execution mode tags per phase

If absent, display: "No active plan. Run /r-plan to create one."

### 3. Read Phase Status Files

Scan `.rdf/work-output/` for phase status files written by the dispatcher.
These files follow the pattern `.rdf/work-output/phase-N-status.md`.

For each status file found, extract:
- Phase number
- Result (pass/fail)
- Gate results (which gates ran, pass/fail per gate)
- Timestamp

### 4. Check Governance Freshness

Stat `.rdf/governance/index.md` for mtime. Calculate age in hours.
Flag if >24h stale.

### 5. Gather Git Activity

Run:
- `git log --oneline -5` for recent commits
- `git status --porcelain | wc -l` for dirty file count

### 6. Render Dashboard

Use the formatting guide below for all output. Target under 40 lines.

**Session anchor** — 4-column table for at-a-glance project identity:

```
### Session Anchor
| Property | Value | Property | Value |
|----------|-------|----------|-------|
| **Project** | {name} | **Branch** | `{branch}` |
| **HEAD** | `{hash}` ({age}) | **Dirty** | {N} files |
| **Plan** | {M}/{N} phases | **Mode** | {mode} |
| **Governance** | {N} files ({T}h old) | **Last commit** | {1-line summary} |
```

**Plan progress** — task list checkboxes communicate completion at a glance:

```
### Plan Progress
- [x] Phase 1 — {desc}
- [x] Phase 2 — {desc}
- [ ] **Phase 3 — {desc}** *(in-progress)*
- [ ] Phase 4 — {desc}
- [ ] ~~Phase 5 — {desc}~~ *(blocked)*
```

Phase styling:
- `[x]` + plain text = *complete*
- `[ ]` + **bold** + *(in-progress)* italic = current work
- `[ ]` + plain text = *pending*
- `[ ]` + ~~strikethrough~~ + *(blocked)* italic = blocked

If no PLAN.md: `Plan: none — run /r-plan to create one.`

### Pipeline

Show the 4-stage spec-plan-build-ship pipeline position as a table.

```
### Pipeline
| Stage | Status | Artifact |
|-------|--------|----------|
| **Spec** | *complete* | `docs/specs/2026-03-19-foo.md` |
| **Plan** | *complete* | `PLAN.md` (8 phases) |
| **Build** | *in-progress* | Phase 3/8 |
| **Ship** | *pending* | — |
```

**Detection logic:**
- **Spec**: scan `docs/specs/` for spec files. If any exist, show the
  most recent file path as the artifact. Status: *complete* if the file
  exists and is not referenced by `.rdf/work-output/spec-progress.md`,
  *in-progress* if `spec-progress.md` exists, *pending* otherwise.
- **Plan**: check for `PLAN.md` in the project root. If present, show
  total phase count as the artifact. Status: *complete* if all phases
  are complete, *in-progress* if any phase is in-progress, *pending*
  if no PLAN.md exists.
- **Build**: derived from PLAN.md phase statuses. Show current phase
  number and total as the artifact. Status: *complete* if all phases
  are complete, *in-progress* if any phase is in-progress or has
  commits, *pending* if no phases have started.
- **Ship**: check for `.rdf/work-output/ship-progress.md`. If present,
  read the `STAGE` line for the current stage. Status: *complete*
  if stage is "released", *in-progress* if the file exists with
  an active stage, *pending* otherwise.
- **VPE** (conditional — only shown when `.rdf/work-output/vpe-progress.md`
  exists): read the current stage and status from the file. Show as:
  `| **VPE** | *managing* | Stage: {current stage} |`
- **Build** (conditional — only shown when `.rdf/work-output/build-progress.md`
  exists and `DISPATCH_MODE` is `parallel`): read the current batch and phase
  counts. This entry *replaces* the standard Build line above (not shown
  alongside it). Show as:
  `| **Build** | *parallel* | Batch {N}/{total}: Phases {list} |`

**Phase outcomes** — table for structured gate results from `.rdf/work-output/`:

```
### Phase Outcomes
| Phase | Result | Gates | Retries | Timestamp |
|-------|--------|-------|---------|-----------|
| 1 | **PASS** | G1+G2 | 0 | 2026-03-18 |
| 2 | **FAIL** | G1 | 1 | 2026-03-18 |
```

**Recent commits** — inline code for hashes, parenthetical age:

```
### Recent Commits
- `{hash}` {message} ({age})
- `{hash}` {message} ({age})
- `{hash}` {message} ({age})
```

**Warnings** — blockquote with bold header, only shown when warnings exist:

```
> **Warnings**
> - Governance is {T}h old — run `/r-refresh`
> - {N} uncommitted files
> - Phase {N} status file is stale (>1h) — likely interrupted
> - Phase {N} **FAIL** — review `.rdf/work-output/phase-{N}-status.md`
```

Thresholds:
- Governance stale: >24 hours
- Dirty state: >5 files
- Status file stale: >1 hour

---

**Minimal dashboard** — when there is no plan and no governance:

```
### Session Anchor
| Property | Value | Property | Value |
|----------|-------|----------|-------|
| **Project** | {basename} | **Branch** | `{branch}` |
| **HEAD** | `{hash}` | **Dirty** | {N} files |
| **Governance** | not initialized | **Plan** | none |

### Recent Commits
- `{hash}` {message} ({age})

> **Next Steps**
> - Run `/r-init` to generate governance
> - Run `/r-plan` to create a plan
```

## Formatting Guide

Available markdown primitives and when to use them:

| Primitive | Syntax | Best for |
|-----------|--------|----------|
| **Table** | `\| col \| col \|` | Structured data, dashboards, key-value pairs |
| **Task list** | `- [x]` / `- [ ]` | Phase progress, checklists |
| **Blockquote** | `>` | Warnings, callouts, anything needing visual separation |
| **Bold** | `**text**` | Labels, section headers within lists |
| **Italic** | `*text*` | Status keywords, secondary info, parentheticals |
| **Inline code** | `` `text` `` | Paths, hashes, commands, values that need to pop |
| **Strikethrough** | `~~text~~` | Blocked/suppressed items |
| **Heading** | `##` / `###` | Major / minor section breaks |
| **Rule** | `---` | Lightweight section divider (lighter than heading) |

**Do NOT use** (not rendered in Claude Code):
HTML tags, `<details>`, ANSI color codes, Mermaid diagrams, footnotes.

## Rules
- Read-only — do NOT modify any files
- Do NOT run tests or lint — this is a status check
- Do NOT load full governance files — index only
- If `.rdf/work-output/` does not exist or is empty, skip the phase outcomes
  section silently
- Only show the warnings block if there are warnings to display
- Keep total output under 40 lines — use tables, task lists, and
  blockquotes over prose
- Target under 5 seconds wall time — all git commands can run in
  parallel
