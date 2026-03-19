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

Execute sections 1-7 silently — do NOT display per-section output.
All results feed into the single consolidated report in section 8.
Tool calls (git commands, file reads/writes) provide activity
feedback in the terminal; text output is reserved for the report.

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

Record values for the report: commit count, start hash, end hash,
files changed count, dirty count, branch name.

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

Record for report: phases newly completed, phases in-progress,
total phase count.

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

**CRITICAL**: Never forward-copy values from prior MEMORY.md entries.
Always grep from source or git for current values.

**Size guard**: After updating, count total lines. If >=180, record
a warning for the report.

Record for report: whether HEAD changed, commit count recorded,
push status, any warnings.

### 4. Resolve AUDIT.md (if exists)

If `AUDIT.md` exists in the project root:

- Read the findings/remediation section
- For each unresolved finding, cross-reference against `git log`
  and current source
- If a finding's recommended fix was committed (commit exists AND
  code change verified), annotate: `RESOLVED (hash)`
- Update executive summary counts if findings were resolved
- Do NOT delete findings — only annotate resolution status

Record for report: findings resolved count, findings remaining.

If no `AUDIT.md`: skip silently.

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
  "dirty_files": {N},
  "insight": "{punchline text, or null if skipped}"
}
```

Create `work-output/` directory if it does not exist.

The `head_before` value comes from: the last session-log entry's
`head_after`, or MEMORY.md's HEAD field, or the oldest of the
session's commits. If no commits were made, `head_before` equals
`head_after`.

### 6. Generate Session Insight

**Zero-change sessions:** If the session produced 0 commits and 0
dirty files, skip insight generation entirely — there is no session
to reflect on.

Reflect on the full session — what was built, how it was built, what
went smoothly, what caused friction or rework. Distill a single
punchline insight: sage advice for how to better operate with the
harness or get better output from the model in future sessions.

**The insight must be:**
- One sentence, max two — a punchline, not a paragraph
- Actionable — the reader should be able to DO something different
- About the harness/workflow/model interaction, not about the code
  itself — "name commands consistently from the start" not "fix the
  bug in parser.sh"
- Novel — do not repeat an insight already in the last 5 entries

**Read the last 5 entries** from `~/.rdf/insights.jsonl` to check
for duplicates. If the file does not exist, create it. Create the
`~/.rdf/` directory if it does not exist.

**Append one entry:**

```json
{
  "timestamp": "{ISO 8601 UTC}",
  "project": "{project name from cwd basename}",
  "tool": "{claude-code|gemini-cli|codex}",
  "insight": "{the punchline}",
  "tags": ["{category}", "{category}"]
}
```

Tags are 1-3 categories from: `git`, `naming`, `testing`, `commands`,
`context`, `planning`, `review`, `performance`, `workflow`, `scope`.

**Cap at 30 entries.** If the file exceeds 30 lines after appending,
trim the oldest entries (from the top) to keep 30.

### 7. Lessons Learned Prompt

**Check auto-commit setting:** Read `~/.rdf/config.json` (if it
exists) for the `auto_commit_insights` key.

- If `true`: automatically append the insight to
  `~/.rdf/lessons-learned.md` under the appropriate category heading.
  Note `(auto-committed)` in the report. Skip the prompt.
- If `false` or config does not exist: include the prompt in the
  report (see section 8).

**Appending to lessons-learned.md:**

When committing (either auto or user-confirmed), append the insight
as a bullet under the matching category heading in
`~/.rdf/lessons-learned.md`. If the file does not exist, create it
with the standard header (see below). If the category heading does
not exist, add it.

Standard header for new file:
```markdown
# Lessons Learned

Cross-session operational wisdom, promoted from session insights.
Referenced by all AI tools via project CLAUDE.md / GEMINI.md.
Max 50 entries — run `/r:util:mem-compact` to prune.
```

Category headings map from insight tags:
- `git` → `## Git`
- `naming` → `## Naming`
- `testing` → `## Testing`
- `commands` → `## Commands`
- `context` → `## Context Management`
- `planning` → `## Planning`
- `review` → `## Review`
- `performance` → `## Performance`
- `workflow` → `## Workflow`
- `scope` → `## Scope`

Use the first tag as the category. Bullet format:
`- {insight text}`

**Cap at 50 entries.** If the file exceeds 50 bullets after
appending, note it as a warning in the report.

### 8. Output Report

This is the ONLY visible text output from the entire save operation.
Everything above executes silently — this section consolidates all
results into one compact block.

**Target: under 15 lines of visible output.**

```
## Save: {Project} v{version} (`{branch}`)

| Commits | HEAD | Files | Dirty |
|---------|------|-------|-------|
| {N} new | `{start}` → `{end}` | {N} changed | {N} |

- [x] **Plan** — {summary: "Phase 2 complete, Phase 3 in-progress" or "7 pending, no changes" or "no PLAN.md"}
- [x] **Memory** — HEAD `{old}` → `{new}`, {N} commits recorded
- [x] **Log** — appended to `session-log.jsonl`
- [ ] **Audit** — *not present*

> **Insight**: {the punchline text}
>
> Commit as lesson learned? **y** / **n** / **auto**
> *(auto saves future insights to `~/.rdf/lessons-learned.md`)*

> **Next** — `/r:start` to resume. {context hint}
```

**Adaptation rules:**

- Only show action lines for sections that ran — omit lines for
  sections that were entirely skipped (no PLAN.md = omit Plan line)
- Exception: Audit line shows as `[ ]` with *not present* when
  AUDIT.md does not exist (signals absence is known, not an error)
- If auto-commit is enabled, replace the prompt block with:
  `> **Insight** *(auto-committed)*: {text}`
- If zero-change session (no insight generated), omit the insight
  block entirely
- If `--dry-run`, prefix heading with `[dry-run]` and append:
  `> **Dry run** — no files were modified.`
- Warnings (MEMORY.md >=180 lines, behind upstream) append to the
  Next blockquote as additional `>` lines

**After displaying the report:** If the prompt is shown (not
auto-commit), wait for the user's response:
- **y**: Append insight to `~/.rdf/lessons-learned.md` per section 7.
  Confirm: `Saved to lessons-learned.md`
- **n**: Do nothing. Insight stays in rolling pool only.
- **auto**: Write `{"auto_commit_insights": true}` to
  `~/.rdf/config.json` (merge if file exists). Append this insight.
  Confirm: `Auto-commit enabled. Saved to lessons-learned.md`

## Rules

- Execute sections 1-7 silently — the report is the only output
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
