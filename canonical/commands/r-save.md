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

Display:
```
## Session Summary
Commits: {N} new
Files changed: {N} ({committed} committed, {uncommitted} uncommitted)
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
- Format: `- **Status**: complete (a3f7c12)`

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

**Size guard**: After updating, count total lines. If >=180:
```
WARNING: MEMORY.md is {N} lines (limit: 200). Run /r:util:mem-compact.
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

If no AUDIT.md: skip silently.
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

If `--dry-run`: show the entry that would be appended.

### 6. Output Report

```
## Save: {Project} v{version} ({branch})

Session: {N} commits, {N} files changed
PLAN.md: {phase changes, e.g., "Phase 4 → complete (a3f7c12)"}
MEMORY.md: {N} new commits recorded, HEAD updated to {hash}
AUDIT.md: {N} findings resolved (or "no changes" or "not present")
Session log: appended to work-output/session-log.jsonl

Next session: /r:start to resume from Phase {N}
```

If `--dry-run`, prefix with: `[dry-run] No files were modified.`

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
