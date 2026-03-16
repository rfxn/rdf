Refresh project state files (MEMORY.md and PLAN.md) to match current git reality.

`$ARGUMENTS` determines scope:

- **No args or `all`** — refresh both MEMORY.md and PLAN.md
- **`memory`** — refresh MEMORY.md only
- **`plan`** — refresh PLAN.md only
- **`github`** — sync GitHub issue state with local plan (deterministic, no LLM)

---

## Procedure

### 1. Collect State

Run `rdf state` (or `state/rdf-state.sh` directly) against the current project
directory to get deterministic JSON state. Parse the output for:

- `project`, `version`, `branch`, `dirty`, `uncommitted_files`
- `last_commit_hash`, `last_commit_age_hours`, `commits_since_tag`
- `memory_exists`, `memory_age_hours`
- `plan_exists`, `plan_phases.total`, `plan_phases.completed`, `plan_phases.active`
- `audit_exists`, `work_output_files`

Also collect recent commits:
```bash
git log --oneline -20
```

And current test count (if applicable):
```bash
grep -rc '@test' tests/*.bats 2>/dev/null | awk -F: '{s+=$2}END{print s}'
```

### 2. Refresh MEMORY.md (scope: memory or all)

Read the project's MEMORY.md. If it does not exist, skip this section.

**Locate MEMORY.md:** Check the Claude auto-memory location first:
`/root/.claude/projects/-<path-encoded>/memory/MEMORY.md`. If not found, check
project-local `./MEMORY.md`.

**Update the following sections (preserve all others):**

- **Project Status / Version**: Update version string, branch, HEAD hash from
  rdf-state JSON. Do NOT forward-copy from prior entries — always use the values
  from `rdf state` output.

- **Test Count**: Replace with actual count from `grep -rc '@test'`. Only if
  the project has BATS tests.

- **Completed Work / Recent Commits**: Identify the last recorded commit hash
  in MEMORY.md. Run `git log <last_hash>..HEAD --oneline` to get new commits.
  Prepend them to the completed work section. If no last hash found, use
  last 10 commits.

- **Open Items / Phase Status**: Cross-reference PLAN.md phase statuses.
  Update any phase that has transitioned since the last memory save.

**Size guard**: After updating, count total lines. If >= 180, append a warning:
`WARNING: MEMORY.md is <N> lines (limit: 200). Run /mem-compact to archive.`

### 3. Refresh PLAN.md (scope: plan or all)

Read the project's PLAN.md. If it does not exist, skip this section.

**For each phase/item in PLAN.md:**

- Cross-reference against `git log --oneline -50` — if a commit message
  references the phase and the code change is present, mark it COMPLETED
  with commit hash
- If work was started but not finished, mark IN PROGRESS with notes
- Do NOT mark anything COMPLETED without verifying the commit exists
- Do NOT reorder phases or change priority tags
- Update the status summary line at the top

**Evidence requirement:** For each status change, include the commit hash as
proof. Example: `Phase 3 — COMPLETED (abc1234)`.

### 4. Refresh GitHub (scope: github or all)

This scope is deterministic — no LLM judgment required. Run:

```bash
rdf refresh --scope github [--dry-run]
```

Or if the `rdf` CLI is not available, use `gh` directly:

- List phase issues: `gh issue list --label "type:phase" --state all --json number,title,state`
- List task issues: `gh issue list --label "type:task" --state all --json number,title,state`
- Cross-reference with PLAN.md statuses
- Close issues whose phases are COMPLETE in PLAN.md
- Reopen issues whose phases are not COMPLETE but are CLOSED on GitHub
- Report mismatches resolved

### 5. Output Summary

Print a structured summary:

```
## Refresh: <Project> v<version> (<branch>)

MEMORY.md: <updated|skipped|not found> — <N> new commits recorded
PLAN.md: <updated|skipped|not found> — <N> phases updated
GitHub: <synced|skipped|not configured> — <N> mismatches resolved
State age: <N>h since last commit
```

---

## Rules

- Read before writing — never overwrite content you haven't read
- Preserve all existing content structure and formatting
- Only update facts that are verifiably stale (confirmed via git/source)
- NEVER use values from prior MEMORY.md entries as source — always grep from
  source files or git for current values
- Do NOT create files that don't already exist (except MEMORY.md on first save)
- Do NOT stage, commit, or push — this is a refresh operation only
- The `/mem-save` command handles session-end saves with metrics harvest;
  `/refresh` is for mid-session or startup state sync
