# /r-save — Session State Sync

End-of-session state sync. Updates tracking files to reflect what
actually happened, persists a session summary for the next agent.

Run this before ending a session or swapping context. The counterpart
to `/r-start` — save writes the journal, start reads it.

## Arguments

`$ARGUMENTS` — optional flags:
- No args: full save (all sections)
- `--dry-run`: show what would change without writing
- `--plan-only`: sync PLAN.md only (quick save)

## Progress Tracking

See [reference/progress-tracking.md](../reference/progress-tracking.md).
Create all 6 tasks in ONE batch before starting.

Tasks: `Session diff` · `Plan sync` · `Memory sync` · `Audit resolve` ·
`Session log` · `Session insight`

Fallback checklist (Gemini CLI, Codex):
`- [ ] Session diff` · `- [ ] Plan sync` · `- [ ] Memory sync` ·
`- [ ] Audit resolve` · `- [ ] Session log` · `- [ ] Insight`
(`[-]` for skipped phases)

## Protocol

Run all phases sequentially on the main thread. Batch git commands
where possible — run `git log`, `git diff`, `git status` in a single
shell invocation to minimize round-trips. All phases execute silently;
only the final report (section 8) produces visible output.

### 1. Compute Session Diff

A SessionEnd hook may have precomputed this session's deterministic state.
**Cache selection rule:** if `$RDF_SESSION_ID` is set, look for
`.rdf/work-output/session-end-${RDF_SESSION_ID}.json`; otherwise glob
`.rdf/work-output/session-end-*.json` and take the newest one NOT ending in
`.consumed`. On a hit, parse it, SKIP the `rdf-state.sh --full` re-run, and
rename the file to `*.consumed`. If no cache is found, run:
```bash
bash ~/.rdf/state/rdf-state.sh --full .
```

Read `.diff_categories` from the state JSON and format the top-3 summary from
it — do NOT re-classify files by hand; that classification is now
deterministic in `rdf-state.sh`. (The SessionEnd cache carries only the git
snapshot, not `diff_categories` — a cache hit still requires this one
`rdf-state.sh` call to obtain them.)

This returns JSON with: HEAD, branch, dirty count + file names,
recent commits, unpushed count, plan phases, pipeline position,
session log last entry, and insights. Parse the JSON.

If `rdf-state.sh` is not found, fall back to individual commands:
```bash
echo "HEAD=$(git rev-parse --short HEAD)" && \
echo "BRANCH=$(git branch --show-current)" && \
echo "DIRTY=$(git status --porcelain | wc -l)" && \
echo "UNPUSHED=$(git rev-list --count HEAD...@{u} 2>/dev/null || echo 0)" && \
git log --oneline -20
```

From the state JSON or fallback, identify:
- New commits since the session started (compare HEAD against
  `session_last` field's `head_after`, or MEMORY.md HEAD, or
  fall back to the last 10 commits)
- Uncommitted changes (staged + unstaged)
- Files modified across all new commits
- Upstream status (unpushed count)

**Diff characterization:** The `.diff_categories` object in the state JSON
already classifies changed files by path prefix — keys `commands`, `agents`,
`scripts`, `cli`, `adapters`, `specs`, `docs`, `other`. Read those counts
directly; do NOT re-classify files by hand (the classification is
deterministic in `rdf-state.sh`).

Produce a one-line summary: `"3 commands, 1 spec, 2 docs"` (ordered
by count descending, top 3 categories, remainders grouped as "other").

**Dirty file names:** If dirty count > 0, collect the actual file
names (max 5) for the report.

**Pipeline position:** Determine where in the spec→plan→build→ship
arc the project is:
- `docs/specs/` has files + no active plan → `spec` (design complete, plan next)
- Active plan exists with pending phases → `plan` (plan ready, build next)
- Active plan exists with in-progress phases → `build` (building phase N)
- Active plan exists with all phases complete → `ship` (ready to ship)
- None of the above → `idle`

Record all values for the report.

### 2. Sync the Plan with Git

Source `~/.rdf/state/rdf-bus.sh`; `rdf_session_init`. Resolve the plan:
`plan_path="$(rdf_active_plan_path)"`. If empty, skip.

For each phase in `$plan_path`:

**Detect completion:**
- Cross-reference `git log --oneline` against the phase description
  and file list
- If commits exist that implement the phase's work AND the phase's
  acceptance criteria files are present, mark the phase `complete`
  with the commit hash as evidence

**Record spec path:**
- Source `~/.rdf/state/rdf-bus.sh`; `rdf_session_init`. If
  `.rdf/work-output/spec-progress-${RDF_SESSION_ID}.md` exists,
  read the `SPEC_PATH`. If not, fall back to glob
  `.rdf/work-output/spec-progress-*.md` (most recent by mtime);
  if neither found, fall back to legacy `.rdf/work-output/spec-progress.md` (pre-3.1.0).
  If `SPEC_PATH` is present and non-empty, record it for the session log
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
- Update the progress summary at the top of `$plan_path` if present

Record for report: phases newly completed, phases in-progress,
total phase count.

### 3. Sync MEMORY.md

Locate the project's MEMORY.md in the .rdf/memory/ directory:
`.rdf/memory/MEMORY.md`

If it does not exist, create it with the standard index format.

**Update these fields (preserve everything else):**

- **HEAD hash**: update to current `git rev-parse --short HEAD`
- **Branch**: update to current `git branch --show-current`
- **Version**: grep from source (project-specific — check CLAUDE.md
  for the version grep pattern)
- **Pushed**: check `git status` for ahead/behind upstream

**CRITICAL**: Never forward-copy values from prior MEMORY.md entries.
Always grep from source or git for current values.

**Size guard (auto-act)**: After updating, count total lines. If >=180,
invoke `/r-util-mem-compact` in preview mode and carry its proposed
reduction into the report (§8) as an action line — not a passive warning.

Record for report: whether HEAD changed, commit count recorded,
push status, any warnings.

### 4. Resolve AUDIT.md

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

Append a structured entry to `.rdf/work-output/session-log.jsonl`:

```json
{
  "timestamp": "{ISO 8601 UTC}",
  "project": "{project name}",
  "branch": "{branch}",
  "head_before": "{hash at session start}",
  "head_after": "{current HEAD hash}",
  "commits": {N},
  "files_changed": {N},
  "diff_summary": "{categorized one-line: 3 commands, 1 spec}",
  "pipeline": "{idle|spec|plan|build|ship}",
  "spec_path": "{path to spec file, or null if none}",
  "plan_phases_completed": [{list of phase numbers}],
  "plan_phases_in_progress": [{list of phase numbers}],
  "dirty_files": {N},
  "unpushed": {N},
  "insight": "{punchline text, or null if skipped}"
}
```

Create `.rdf/work-output/` directory if it does not exist.

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
trim the oldest entries from the top in-place. Use `sed -i` — NOT
`tail -30 file > tmp && mv tmp file` — because interactive shells
commonly alias `mv` to `mv -i`, which stalls waiting for overwrite
confirmation. In-place editing sidesteps the alias entirely:

```bash
lines=$(wc -l < ~/.rdf/insights.jsonl)
[ "$lines" -gt 30 ] && sed -i "1,$((lines - 30))d" ~/.rdf/insights.jsonl
```

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
Max 50 entries — run `/r-util-mem-compact` to prune.
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

**Rebuild the lessons index (single writer, F7).** After appending
(y or auto), run:
```bash
bash ~/.rdf/state/rdf-lessons.sh index
```
This rebuilds `~/.rdf/lessons-index.md` AND backfills any missing
`<!-- id:X -->` markers on lessons bullets (idempotent). This is the
ONLY place `lessons-learned.md` / `lessons-index.md` are written
programmatically — the SessionStart inject hook is strictly read-only.
`rdf-lessons.sh index` takes an flock on `lessons-learned.md`, so a
concurrent `/r-util-mem-compact` consolidation cannot interleave.

### 8. Output Report

This is the ONLY visible text output from the entire save operation.
Everything above executes silently — this section consolidates all
results into one compact block.

**Target: under 20 lines of visible output.**

```
## Save: {Project} v{version} · `{branch}` · {pipeline_stage}

`{start_hash}` → `{end_hash}` · {N} commits · {diff_summary}

- [x] **Plan** — {summary}
- [x] **Memory** — HEAD updated, {N} commits recorded
- [x] **Log** — appended
- [ ] **Audit** — *not present*

> **Insight**: {the punchline text}
>
> Commit as lesson learned? **y** / **n** / **auto**

> **Next** — {pipeline-aware hint}
```

**The heading line** packs project identity, branch, and pipeline
stage into one line. Pipeline stage shows where you are in the arc:
- `idle` → no spec or plan
- `spec` → spec exists, plan next
- `plan` → plan ready, `/r-build` next
- `build phase 3/7` → actively building
- `ship` → all phases done, `/r-ship` next

**The diff line** replaces the old 4-column table with a single
dense line: hash range, commit count, and categorized diff summary.
More informative in less space.

**Adaptation rules:**

- Only show action lines for sections that ran — omit skipped
- Audit shows as `[ ]` with *not present* (signals known absence)
- If auto-commit enabled, replace prompt with:
  `> **Insight** *(auto-committed)*: {text}`
- If zero-change session, omit insight block entirely
- If `--dry-run`, prefix heading with `[dry-run]`

**Warnings** — append to the Next blockquote only when triggered:
```
> **Next** — `/r-start` to resume.
> ⚠ {N} unpushed commits — `git push` before switching machines
> ⚠ {N} dirty files: `{file1}`, `{file2}`, `{file3}`
> ▶ MEMORY.md {N}/200 — previewed compaction saves {M} lines; apply? y/n
> ▶ Context ~{N}% — start a fresh session or `/half-clone` now
```

Warning thresholds:
- Unpushed: any (>0 is always shown — this is safety-critical)
- Dirty files: >0 (show up to 5 filenames)
- Memory: >=180 lines → auto-run `/r-util-mem-compact` preview, show reduction
- Context: >60% estimated (rough heuristic: count conversation
  turns × ~2000 tokens, compare to model context limit) → directive
  (fresh session / `/half-clone`), not a passive warning

**Pipeline-aware Next hint:**
- `idle` → `Spec a feature with /r-spec, or plan directly with /r-plan`
- `spec` → `Spec ready — /r-plan to create implementation plan`
- `plan` → `/r-build to start phase 1`
- `build phase N/M` → `/r-build {N+1} to continue` or `/r-ship if complete`
- `ship` → `All phases done — /r-ship to release`

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
- Idempotent: running /r-save twice with no intervening work should
  produce no changes on the second run
