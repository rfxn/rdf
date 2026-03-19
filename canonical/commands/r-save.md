# /r:save — Session State Sync

End-of-session state sync. Updates tracking files to reflect what
actually happened, persists a session summary for the next agent.

Run this before ending a session or swapping context. The counterpart
to `/r:start` — save writes the journal, start reads it.

## Arguments

`$ARGUMENTS` — optional flags:
- No args: full save (all sections)
- `--dry-run`: show what would change without writing
- `--plan-only`: sync PLAN.md only (quick save)

## Protocol

### 1. Compute Session Diff

Determine what happened this session by examining git state:

```bash
git log --oneline -20
git diff --name-only
git diff --cached --name-only
```

Identify:
- New commits since the session started (use the HEAD hash from
  the last session-log entry, or from MEMORY.md "HEAD:" field, or
  fall back to the last 10 commits)
- Uncommitted changes (staged + unstaged)
- Files modified across all new commits

Display as a key-value table:
```
### Session Diff
| Property | Value |
|----------|-------|
| **Commits** | {N} new since `{start_hash}` |
| **Files changed** | {committed} committed, {uncommitted} uncommitted |
| **Branch** | `{branch}` |
```

### 2. Sync PLAN.md with Git

Read `PLAN.md` from the project root. If it does not exist, skip.

For each phase in PLAN.md:

**Detect completion:**
- Cross-reference `git log --oneline` against the phase description
  and file list
- If commits exist that implement the phase's work AND the phase's
  acceptance criteria files are present, mark the phase `complete`
  with the commit hash as evidence

**Record spec path:**
- If `work-output/spec-progress.md` exists, read the `SPEC_PATH`
  line. If present and non-empty, record it for the session log
  `spec_path` field.

**Detect in-progress work:**
- If files listed in a pending phase have uncommitted changes
  (`git diff --name-only` matches), mark the phase `in-progress`
- If a phase was previously in-progress and its files have new
  commits, check whether the work is complete or still partial

**Rules:**
- Do NOT mark anything complete without verifying the commit exists
- Do NOT reorder phases or change descriptions
- Do NOT change phases that are already marked complete (idempotent)
- Update the progress summary at the top of PLAN.md if present
  (e.g., "Phases 1-4 complete, Phase 5 in progress")

Display plan sync results as a task list showing what changed:
```
### Plan Sync
- [x] Phase 1 — *complete* (`a3f7c12`)
- [x] Phase 2 — *complete* (`b4e8d23`) *(newly detected)*
- [ ] **Phase 3** — *in-progress* (uncommitted changes)
- [ ] Phase 4 — *pending* (no changes)
```

Phase styling:
- `[x]` + plain text = already complete (no change)
- `[x]` + *(newly detected)* italic = marked complete this save
- `[ ]` + **bold** + *in-progress* italic = current work
- `[ ]` + plain text + *pending* = untouched

If no phases changed: `Plan: no changes — all phases up to date.`

If `--dry-run`: show proposed changes without writing.

### 3. Sync MEMORY.md

Locate the project's MEMORY.md in the Claude auto-memory directory:
`/root/.claude/projects/{path-encoded}/memory/MEMORY.md`

If it does not exist, create it with the standard index format.

**Update these fields (preserve everything else):**

- **HEAD hash**: update to current `git rev-parse --short HEAD`
- **Branch**: update to current `git branch --show-current`
- **Version**: grep from source (project-specific — check CLAUDE.md
  for the version grep pattern)
- **Pushed**: check `git status` for ahead/behind upstream

**Record recent work:**
- Find the last recorded HEAD hash in MEMORY.md
- Run `git log {last_hash}..HEAD --oneline` to get new commits
- If there are new commits, note them in the project state section

**CRITICAL**: Never forward-copy values from prior MEMORY.md entries.
Always grep from source or git for current values.

Display MEMORY.md updates as a task list showing what was saved:
```
### Memory Sync
- [x] **HEAD** updated: `a3f7c12` → `d5e9f01`
- [x] **Branch** confirmed: `2.0.2`
- [x] **Version** confirmed: `2.0.2`
- [x] **Commits** recorded: {N} new (`{oldest_hash}`..`{newest_hash}`)
- [ ] **Pushed**: *behind upstream by {N} commits*
```

Use `[x]` for fields that were updated or confirmed current. Use
`[ ]` for fields that need attention (behind upstream, version
mismatch, etc.).

**Size guard**: After updating, count total lines. If >=180, append
a warning using a blockquote:
```
> **Warning** — `MEMORY.md` is {N}/200 lines. Run `/r:util:mem-compact`.
```

If `--dry-run`: show proposed changes without writing.

### 4. Resolve AUDIT.md (if exists)

If `AUDIT.md` exists in the project root:

- Read the findings/remediation section
- For each unresolved finding, cross-reference against `git log`
  and current source
- If a finding's recommended fix was committed (commit exists AND
  code change verified), annotate: `RESOLVED (hash)`
- Update executive summary counts if findings were resolved
- Do NOT delete findings — only annotate resolution status

Display audit resolution as a task list (only if findings changed):
```
### Audit Sync
- [x] **F-003**: path traversal guard — *resolved* (`c7d2e41`)
- [x] **F-007**: missing input validation — *resolved* (`c7d2e41`)
- [ ] **F-012**: race condition in lock file — *unresolved*
```

If no `AUDIT.md`: skip silently (no output).
If no findings changed: `Audit: no changes.`
If `--dry-run`: show which findings would be marked resolved.

### 5. Write Session Log

Append a structured entry to `work-output/session-log.jsonl`:

```json
{
  "timestamp": "{ISO 8601 UTC}",
  "project": "{project name}",
  "branch": "{branch}",
  "head_before": "{hash at session start}",
  "head_after": "{current HEAD hash}",
  "commits": {N},
  "files_changed": {N},
  "spec_path": "{path to spec file, or null if none}",
  "plan_phases_completed": [{list of phase numbers}],
  "plan_phases_in_progress": [{list of phase numbers}],
  "dirty_files": {N}
}
```

Create `work-output/` directory if it does not exist.

The `head_before` value comes from: the last session-log entry's
`head_after`, or MEMORY.md's HEAD field, or the oldest of the
session's commits. If no commits were made, `head_before` equals
`head_after`.

Display the session log entry as a key-value table:
```
### Session Log
| Property | Value |
|----------|-------|
| **Timestamp** | `2026-03-18T14:32:00Z` |
| **HEAD** | `a3f7c12` → `d5e9f01` |
| **Commits** | {N} |
| **Files** | {N} changed, {N} dirty |
| **Phases completed** | {list} |
| **Written to** | `work-output/session-log.jsonl` |
```

If `--dry-run`: show the entry that would be appended.

### 6. Output Report

The final report consolidates all sections into a compact summary.
Use the session anchor table from r-start's style, a task list of
actions taken, and a blockquote for the next-session hint.

```
## Save: {Project} v{version} (`{branch}`)

### Summary
| Property | Value | Property | Value |
|----------|-------|----------|-------|
| **Commits** | {N} new | **HEAD** | `{start_hash}` → `{end_hash}` |
| **Files** | {committed} committed, {uncommitted} dirty | **Branch** | `{branch}` |

### Actions
- [x] **Session diff** — {N} commits, {N} files
- [x] **Plan sync** — Phase {N} → *complete* (`{hash}`), Phase {M} *in-progress*
- [x] **Memory sync** — HEAD updated, {N} commits recorded
- [ ] **Audit sync** — *not present*
- [x] **Session log** — appended to `work-output/session-log.jsonl`

> **Next session** — run `/r:start` to resume from Phase {N}.
```

Action styling:
- `[x]` = action completed successfully
- `[ ]` = action skipped (file not present, no changes, etc.)
- Use *italic* for status keywords (*complete*, *in-progress*,
  *not present*, *no changes*)
- Use inline code for paths, hashes, and commands

Adapt the line content to what actually happened — do not show
placeholder lines for sections that were skipped. Examples:
- Plan does not exist: `- [ ] **Plan sync** — *no* `PLAN.md` *found*`
- Audit resolved findings: `- [x] **Audit sync** — {N} findings *resolved*`
- No commits this session: `- [x] **Session diff** — 0 commits, {N} dirty files`

If `--dry-run`, prefix the report heading with `[dry-run]` and
append a blockquote:
```
> **Dry run** — no files were modified. Review the proposed changes above.
```

## Formatting Guide

Available markdown primitives and when to use them:

| Primitive | Syntax | Best for |
|-----------|--------|----------|
| **Table** | `\| col \| col \|` | Session diff, session log, final summary |
| **Task list** | `- [x]` / `- [ ]` | Plan sync, memory sync, audit sync, actions |
| **Blockquote** | `>` | Warnings, next-session hint, dry-run notice |
| **Bold** | `**text**` | Labels, property names, phase/finding identifiers |
| **Italic** | `*text*` | Status keywords (*complete*, *in-progress*, *pending*) |
| **Inline code** | `` `text` `` | Paths, hashes, commands, branch names |

**Do NOT use** (not rendered in Claude Code):
HTML tags, `<details>`, ANSI color codes, Mermaid diagrams, footnotes.

**Output size target:** Keep the final consolidated report (section 6)
under 20 lines. The per-section displays (sections 1-5) are shown
incrementally as work progresses and do not count toward this limit.

## Rules

- Read before writing — never overwrite content you haven't read
- Preserve all existing content structure and formatting
- Only update facts that are verifiably stale (confirmed via git)
- NEVER use values from prior MEMORY.md entries as source — always
  grep from source files or git for current values
- Do NOT stage, commit, or push — this is a save operation only
- Do NOT modify CLAUDE.md — it contains conventions, not volatile
  state
- Do NOT run tests or lint — this is a state sync, not verification
- Idempotent: running /r:save twice with no intervening work should
  produce no changes on the second run
