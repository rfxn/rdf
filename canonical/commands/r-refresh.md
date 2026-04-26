You are running the /r-refresh governance refresh. This command
re-scans the codebase and updates governance files to match current
reality, preserving user modifications.

## Arguments

$ARGUMENTS — optional scope:
- No args or `all`: full refresh (governance + state files)
- `governance`: refresh .rdf/governance/ files only
- `state`: refresh MEMORY.md and PLAN.md only (v2 behavior)
- `github`: sync GitHub issue state with local plan (deterministic)

## Task List Protocol

At command startup, create tasks for live progress tracking:

TaskCreate: subject: "Re-scan codebase"
  activeForm: "Scanning codebase"
TaskCreate: subject: "Re-ingest authoritative files"
  activeForm: "Ingesting convention files"
TaskCreate: subject: "Update governance files"
  activeForm: "Updating governance"
TaskCreate: subject: "Validate governance accuracy"
  activeForm: "Validating governance"
TaskCreate: subject: "Refresh state files"
  activeForm: "Refreshing state files"
TaskCreate: subject: "Generate output summary"
  activeForm: "Generating summary"

Issue each `TaskCreate` in its own message, in the order shown — see
[reference/progress-tracking.md](../reference/progress-tracking.md)
for why parallel batches break display order.

Lifecycle: all tasks start pending. Before starting each stage,
mark its task in_progress. After completing, mark completed.

---

## Setup

- Read .rdf/governance/index.md to understand current governance
- Check governance file ages (modification times)
- Read .rdf/governance/.user-modified if it exists (list of files
  the user has manually edited — these get merge treatment, not
  overwrite)

## Stage 1: Codebase Re-Scan (init phases 2-3)

Mark task "Re-scan codebase" as in_progress.

Re-run the /r-init codebase analysis against current state:

### 1a. Phase 2 — Codebase Scan
- Language detection (file extensions, shebangs, package manifests)
- Framework detection (package.json deps, imports, config files)
- Directory structure mapping (src/, tests/, lib/, etc.)
- Build system (Makefile, package.json scripts, CI configs)
- Test framework (jest, pytest, bats, go test, etc.)
- Linter/formatter configs (.eslintrc, .prettierrc, shellcheck, etc.)

### 1b. Phase 3 — Tooling & Infrastructure Detection
- CI/CD: .github/workflows/, .gitlab-ci.yml, Jenkinsfile
- Containers: Dockerfile, docker-compose.yml
- Platform targets: CI matrix, target OS in configs
- Dependencies: lockfiles, version constraints
- Git patterns: branch naming, commit conventions (from log)

### 1c. Diff Against Current Governance
- Compare scan results with existing governance files
- Identify: new findings, removed findings, changed findings
- Track drift (governance says X but codebase now shows Y)

### 1d. Anti-Pattern Drift Delta

Run `/r-util-code-scan all` and parse the per-pattern row counts from
its `## Per-Pattern Summary` table (one row per pattern class with
total match count). Compare against `.rdf/governance/.scan-baseline.json`
(the snapshot from the prior refresh or /r-init run).

Snapshot schema — one entry per pattern class:

```json
{
  "version": "3.1.0",
  "timestamp": "2026-04-26T00:00:00Z",
  "patterns": {
    "bare-coreutils": 12,
    "silent-error": 3,
    "backtick-usage": 0
  }
}
```

Delta surface: only pattern classes where the count changed since
the snapshot. Surface in Stage 6c (Drift Detection) — do NOT emit a
full findings table here.

After comparison, overwrite `.scan-baseline.json` with the new
counts so the next refresh measures drift from the current state.

First-run behavior (no snapshot file): create the baseline, emit
`*Baseline created — {N} pattern classes, {M} total hits*` in the
Stage 6 summary, and skip the delta block.

This stage is skipped when `$ARGUMENTS` is `state` or `github` —
anti-pattern drift is governance-scope, not state-scope.

Mark task "Re-scan codebase" as completed.

## Stage 2: Re-Ingest Authoritative Files (init phase 1, partial)

Mark task "Re-ingest authoritative files" as in_progress.

- Re-read CLAUDE.md, AGENTS.md, and other convention files
- Compare against governance references to these files
- If authoritative files have changed, update governance pointers
- Do NOT modify the authoritative files themselves

Mark task "Re-ingest authoritative files" as completed.

## Stage 3: Update Governance Files (init phase 4)

Mark task "Update governance files" as in_progress.

For each governance file in .rdf/governance/:

### 3a. Check User-Modified Status
- If the file is listed in .user-modified: MERGE mode
  - Show the user what would change
  - Ask for confirmation before applying
  - Preserve user additions, update only generated sections
- If the file is NOT user-modified: UPDATE mode
  - Overwrite with regenerated content

### 3b. Update Each File
- index.md — regenerate from current scan (always updated)
- architecture.md — update component map, boundaries
- conventions.md — update coding patterns from scan
- verification.md — update check list from detected tools
- constraints.md — update platform targets, version floors
- anti-patterns.md — update from codebase patterns
- ignore.md — refresh from profiles/core/reference/ignore-defaults.md
  using the same user-modified-merge rule: preserve existing entries,
  append only new defaults under a `# Added by /r-refresh` heading
  if any default is missing from the current file. If ignore.md does
  not exist (pre-3.0.6 project), create it with the full default set
  from ignore-defaults.md.

### 3c. Track Changes
- Record what changed in each file
- Note any new governance files needed (new framework detected, etc.)
- Note any governance files that are now unnecessary (framework removed)

Mark task "Update governance files" as completed.

## Stage 4: Validate (init phase 5)

Mark task "Validate governance accuracy" as in_progress.

- Spot-check updated governance against codebase
- Verify file references in index.md still point to existing files
- Flag low-confidence inferences for user review
- If drift was detected in Stage 1, report it prominently

Mark task "Validate governance accuracy" as completed.

## Stage 5: Refresh State Files (if scope includes state)

Mark task "Refresh state files" as in_progress.

### 5a. Refresh MEMORY.md
- Locate MEMORY.md (.rdf/memory/ or project-local)
- Update version, branch, HEAD hash from git
- Update test count from test files
- Append new commits since last recorded hash
- Cross-reference PLAN.md phase statuses
- Size guard: warn if >= 180 lines

### 5b. Refresh PLAN.md
- Cross-reference phases against git log
- Mark completed phases with commit hash evidence
- Update status summary

### 5c. Sync GitHub Issues (if scope includes github)
- Cross-reference GitHub issues with PLAN.md
- Close phase issues for completed phases
- Reopen issues for incomplete phases marked closed
- Update initiative status if all children complete

Mark task "Refresh state files" as completed.

## Stage 6: Output Summary

Mark task "Generate output summary" as in_progress.

Keep total output under 50 lines. Use tables, task lists, and
blockquotes over prose — see the Formatting Guide section below.

### 6a. Refresh Anchor

A 4-column key-value table identifying the project and refresh scope.

```
### Refresh: {project}
| Property | Value | Property | Value |
|----------|-------|----------|-------|
| **Version** | {version} | **Branch** | `{branch}` |
| **HEAD** | `{hash}` ({age}) | **Scope** | *{all/governance/state/github}* |
| **Governance** | {N} files | **User-modified** | {N} files |
```

### 6b. Governance File Status

Use a table with per-file rows. Status keywords in italic, paths in
inline code.

```
### Governance
| File | Status | Detail |
|------|--------|--------|
| `index.md` | *updated* | regenerated from scan |
| `architecture.md` | *unchanged* | no drift |
| `conventions.md` | *merged* | user-modified — 2 sections preserved |
| `verification.md` | *updated* | added shellcheck rule |
| `constraints.md` | *unchanged* | no drift |
| `anti-patterns.md` | *updated* | 1 new pattern |
```

Status values: *updated*, *unchanged*, *merged* (user-modified file),
*created* (new file), *removed* (stale file deleted).

### 6c. Drift Detection

Use a blockquote with bold header. Only show this section if drift
was detected — omit entirely when clean.

```
> **Drift Detected** — {N} items
> - `constraints.md` says Bash 4.2+ but `files/internals.conf` uses `${var,,}` (Bash 4.0+)
> - `conventions.md` lists pytest but no Python files remain in tree
> - `architecture.md` references `lib/legacy/` which was removed in `a3f1b2c`
> - Anti-pattern drift: `bare-coreutils` +3 since last refresh, `silent-error` -1
```

Each drift item: inline code for file paths and commits, plain text
for the description. Anti-pattern drift lines come from Stage 1d
delta — one summary line listing every pattern class whose count
changed, sign-prefixed (`+N` / `-N`). Do NOT list per-file hits
here — direct the user to `/r-util-code-scan <class>` for detail.

### 6d. State Files

Use a table for state file refresh results. Paths in inline code,
status in italic, detail column for metrics.

```
### State Files
| File | Status | Detail |
|------|--------|--------|
| `MEMORY.md` | *updated* | +3 new commits, 142/200 lines |
| `PLAN.md` | *updated* | 2 phases marked complete |
| `spec-progress-<SESSION_ID>.md` | *updated* | cross-referenced with `docs/specs/` |
| `ship-progress-<SESSION_ID>.md` | *updated* | stage validated against git tags |
| GitHub | *synced* | 4 issues closed, 1 reopened |
```

Recognized state artifacts in `.rdf/work-output/` that refresh should
cross-reference: `session-log.jsonl`, `phase-*-status.md`,
`current-phase.md`, `agent-feed.log`, `spec-progress-<SESSION_ID>.md`,
`ship-progress-<SESSION_ID>.md`.

Status values: *updated*, *skipped* (out of scope), *not found*,
*synced*, *not configured*.

### 6e. Completion Summary

Use a task list to show what was done vs skipped. This provides an
at-a-glance audit trail. Bold each stage label.

```
### Summary
- [x] **Codebase scan** — 6 detectors, 2 changes found
- [x] **Authoritative re-ingest** — `CLAUDE.md` unchanged
- [x] **Governance update** — 3 files updated, 1 merged, 2 unchanged
- [ ] ~~**State refresh**~~ — *skipped (scope: governance only)*
- [ ] ~~**GitHub sync**~~ — *skipped (scope: governance only)*
- [x] **Validation** — all references resolve, 0 low-confidence items
```

Task list styling:
- `[x]` + **bold** = completed stage
- `[ ]` + ~~strikethrough~~ + *italic reason* = skipped stage
- `[ ]` + **bold** + *(in-progress)* = interrupted (partial refresh)

### 6f. Low-Confidence Items

Use a blockquote with bold header. Only show this section if there
are items to review — omit entirely when clean.

```
> **Low-Confidence Items** — review recommended
> - `conventions.md`: inferred `mawk` from Dockerfile but no `.awk` files found
> - `constraints.md`: detected CentOS 6 in CI matrix but no CentOS 6 test target
```

### 6g. Warnings

Collect and display warnings using a blockquote. Only show if there
are warnings. Use inline code for commands and paths.

```
> **Warnings**
> - `MEMORY.md` at 185/200 lines — run `/r-util-mem-compact`
> - User-modified file `conventions.md` had merge conflicts — review manually
> - Governance age was 72h before this refresh
```

## Formatting Guide

Available markdown primitives and when to use them:

| Primitive | Syntax | Best for |
|-----------|--------|----------|
| **Table** | `\| col \| col \|` | File status, dashboards, key-value pairs |
| **Task list** | `- [x]` / `- [ ]` | Completion tracking, stage audit trail |
| **Blockquote** | `>` | Drift, warnings, low-confidence callouts |
| **Bold** | `**text**` | Labels, stage names, section headers in lists |
| **Italic** | `*text*` | Status keywords, scoping reasons, parentheticals |
| **Inline code** | `` `text` `` | Paths, hashes, commands, filenames |
| **Strikethrough** | `~~text~~` | Skipped stages, out-of-scope items |
| **Heading** | `##` / `###` | Major / minor section breaks |

**Do NOT use** (not rendered in Claude Code):
HTML tags, `<details>`, ANSI color codes, Mermaid diagrams, footnotes.

Mark task "Generate output summary" as completed.

## Constraints
- Never overwrite user-modified governance files without confirmation
- Never modify authoritative files (CLAUDE.md, AGENTS.md, etc.)
- Always validate governance after update (phase 5 spot-check)
- State file refresh follows the same rules as v2 /refresh:
  grep from source, never forward-copy stale values
- Do NOT commit — refresh is a working-tree operation only
