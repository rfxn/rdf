Lightweight post-commit regression check. Runs 3 scoped agents on files
changed since the last audit, producing a standalone delta report. Does NOT
overwrite AUDIT.md — this is a quick guard between full audits.

## Prerequisites

Read CLAUDE.md to understand project structure and conventions.

## Step 1: Determine Audit Baseline

If AUDIT.md exists, extract the timestamp or commit hash from the header
(look for "Generated:" or "Baseline:" line). Use that as the baseline.

If no AUDIT.md exists, use `git merge-base HEAD master` as the baseline.

```bash
baseline_commit=$(git log --format='%H' --after="<audit_date>" --reverse | head -1)
# or if using merge-base:
baseline_commit=$(git merge-base HEAD master)
```

## Step 2: Scope Changed Files

```bash
git diff --name-only "$baseline_commit"..HEAD -- '*.sh' '*.conf' '*.bats'
```

Also include files from the project's shell file list (e.g., `files/maldet`,
`files/internals/functions`, etc.) if they appear in the diff.

If no files changed, report "No changes since last audit." and stop.

## Step 3: Dispatch 3 Scoped Agents

Launch these agents in parallel using the Agent tool, each scoped to ONLY
the changed files:

### Agent 1: Regression Check (REG-delta)
Focus: Do the changes break existing behavior?
- Read each changed file's diff (`git diff "$baseline_commit"..HEAD -- <file>`)
- Check for: removed error handling, changed return values, modified API contracts,
  broken callers, removed validation
- Cross-reference against tests that exercise changed functions

### Agent 2: Standards Check (STD-delta)
Focus: Do the changes violate shell coding standards?
- Run `shellcheck` on changed files only
- Check for: unquoted variables, backticks, hardcoded paths, bare `which`,
  deprecated `egrep`, `$[expr]` arithmetic, missing `local` declarations
- Compare against CLAUDE.md coding conventions

### Agent 3: Security Check (SEC-delta)
Focus: Do the changes introduce security issues?
- Check for: command injection vectors, unsafe temp files, world-readable
  sensitive files, path traversal, unvalidated input, TOCTOU races
- Review any new `eval`, `source`, or dynamic command construction

Each agent outputs findings in this format:
```
FINDING: <severity> | <file>:<line> | <description>
```

## Step 4: Collect and Deduplicate

Gather findings from all 3 agents. Deduplicate by:
- Same file + same line range (within 5 lines) → keep higher severity
- Same description pattern across files → group as one finding

## Step 5: Cross-Reference AUDIT.md

If AUDIT.md exists, check each finding against existing entries:
- If the finding matches a RESOLVED item that regressed → flag as REGRESSION
- If the finding matches an existing OPEN item → flag as KNOWN
- If the finding is new → flag as NEW

## Step 6: Output Delta Report

```
# Audit Delta Report

Baseline: <commit_hash> (<date>)
HEAD: <commit_hash> (<date>)
Files changed: <N>
Agents: REG-delta, STD-delta, SEC-delta

## Findings (<N> total: <new> new, <known> known, <regression> regressions)

| # | Severity | File:Line | Agent | Status | Description |
|---|----------|-----------|-------|--------|-------------|
| 1 | Major    | file:42   | SEC   | NEW    | Unvalidated input in... |
| 2 | Minor    | file:18   | STD   | KNOWN  | Unquoted variable... |

## Regressions (<N>)
<list any findings that match previously RESOLVED audit items>

## Recommendation
- CLEAN: No new findings — safe to continue
- REVIEW: <N> new findings — consider addressing before release
- BLOCK: <N> major/critical new findings — address before merge
```

## Rules

- Do NOT modify AUDIT.md — this is a standalone delta report
- Do NOT re-run the full audit pipeline — only 3 focused agents
- Scope agents strictly to changed files (no full-codebase scanning)
- Use the Agent tool with model haiku for speed on the 3 sub-agents
- If more than 50 files changed, warn and suggest running `/audit` instead
