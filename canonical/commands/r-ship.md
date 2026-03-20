You are running the /r:ship release workflow. This is a composite
workflow that verifies readiness, dispatches quality gates, prepares
release artifacts, and publishes a PR.

## Arguments

$ARGUMENTS — optional: base branch override (default: auto-detect via
`git symbolic-ref refs/remotes/origin/HEAD` or fall back to `main`)

## Setup

- Read .rdf/governance/index.md to understand the project
- Load governance/verification.md for project-specific release checks
- Load governance/conventions.md for commit/changelog format
- Determine project name, version, and branch from governance index

## Resume Detection

If `.rdf/work-output/ship-progress.md` exists on startup:

1. Read the STAGE and STATUS fields
2. Offer: "Found interrupted ship session at stage {stage}. Resume from here? [Y/n]"
3. If Y: skip stages already marked complete, resume from the current stage
4. If N: delete `ship-progress.md` and start fresh

After each stage completes, write state to `.rdf/work-output/ship-progress.md`:
```
STAGE: {preflight|verify|prep|publish|report}
STATUS: {complete|in-progress}
PR_URL: {if created}
VERSION: {version string}
```

## Stage 1: Preflight

Run all three checks and display results as a task list. Each check
is pass/fail — a checked box means the gate passed.

### 1a. Plan Completion Check
- Read PLAN.md — verify ALL phases are marked complete
- If any phases are incomplete, report which ones and STOP
- If no PLAN.md exists, skip this check (ad-hoc release)

### 1b. Working Tree Check
- Run `git status` (never `-uall`), `git diff --stat`
- If there are uncommitted changes, list them and ask the user
  whether to commit, stash, or abort
- If working tree is clean, proceed

### 1c. Branch Check
- Verify current branch is not `main`/`master` (should be a
  feature/release branch)
- Identify base branch for PR target
- Run `git log --oneline $(git merge-base HEAD origin/{base})..HEAD`
  to summarize branch changes

### Preflight Display

Present results as a task list with inline code for values:

```
### Preflight
- [x] **Plan**: all phases complete (`12`/`12`)
- [x] **Working tree**: clean
- [ ] **Branch**: on `main` — *expected a feature/release branch*
```

If a check fails, use an unchecked box and add an italic reason.
If a check is skipped, use a checked box with *(skipped)* annotation.

> **Blocked** — preflight failed: {reason}

Use a blockquote for any blocker that halts the workflow.

## Stage 2: Verification (dispatches subagents)

Dispatch two subagents in parallel:

### 2a. QA Verification
Dispatch qa subagent with:
- Scope: full branch diff against base
- Instruction: run every check in governance/verification.md
- Instruction: produce structured pass/fail report

### 2b. Reviewer Sentinel
Dispatch reviewer subagent in sentinel mode with:
- Scope: full branch diff against base
- Instruction: run all 4 passes (anti-slop, regression, security,
  performance)
- Instruction: produce structured verdict report

### 2c. Gate Evaluation
- Collect both subagent reports
- If QA reports FAIL: show failures, ask user to fix or override
- If reviewer reports MUST-FIX: show findings, ask user to fix or
  override
- If both pass: proceed to Stage 3
- User can override gate failures with explicit confirmation

### Gate Display

Present gate results as a task list — checked = passed, unchecked =
failed or pending:

```
### Verification Gates
- [x] **QA**: *PASS* — `672` tests, `0` failures
- [ ] **Reviewer**: *MUST-FIX* — 2 findings (1 security, 1 regression)
```

If a gate fails, show the findings immediately below in a blockquote:

> **QA Gate Failed** — 3 test failures
> - `test/core.bats` line 42: expected `0`, got `1`
> - `test/trust.bats` line 118: timeout after 30s
> - `test/cli.bats` line 55: missing output line

Ask user to fix or explicitly override.

## Stage 3: Release Prep (main context)

### 3a. Changelog Generation
- Read existing CHANGELOG (and CHANGELOG.RELEASE if present)
- Generate entries from `git log` since last tag/release
- Use governance/conventions.md for changelog format
- Deduplicate entries (absorbs v2 rel-chg-dedup logic)
- Present changelog diff to user for approval

### 3b. AI Attribution Scrub
- If governance requires it (check conventions.md for attribution
  policy): grep for Co-Authored-By, AI attribution, Claude/Anthropic
  references in staged files
- Report any findings and offer to remove them

### 3c. Version String Verification
- Grep for version strings across the codebase (VERSION file,
  package.json, setup.py, Cargo.toml, etc.)
- Verify all version references are consistent
- If mismatches found, report and ask user to fix

### 3d. Commit Release Prep
- Stage changelog updates and any scrub fixes
- Commit with project's message format from governance/conventions.md
- Push branch to origin

### Release Prep Display

Present release prep results as a task list:

```
### Release Prep
- [x] **Changelog**: updated — `12` entries added to `CHANGELOG`
- [x] **Attribution scrub**: clean — no AI references found
- [ ] **Version strings**: *mismatch* — `VERSION` says `2.0.2`, `setup.py` says `2.0.1`
- [x] **Commit**: `a1b2c3d` pushed to `origin/2.0.2`
```

If version mismatches are found, use a blockquote:

> **Version Mismatch** — resolve before proceeding
> - `files/apf`: `VERSION="2.0.2"`
> - `setup.py`: `version="2.0.1"`

## Stage 4: Publish (main context, user confirmation required)

### 4a. Create PR
- Use `gh pr create` with:
  - Short title (under 70 chars) summarizing the release
  - Structured body with ## Summary (from changelog), ## Verification
    (QA + reviewer verdicts), ## Test Plan
- If PR already exists for this branch, print URL and skip creation
- Capture PR number and URL

### 4b. Monitor CI (if configured)
- Check for CI status checks on the PR
- If CI is running, poll periodically (up to 10 minutes)
- Report CI results as they complete
- If CI fails, report which checks failed

### 4c. User Confirmation
- Present final summary and ask user to confirm merge readiness
- Do NOT auto-merge — the user decides

### Publish Display

After PR creation, show a brief confirmation. Use inline code for
the PR URL and number so they stand out:

```
### PR Created
**PR** `#42`: {title}
**URL**: {url}
```

For CI monitoring, use a task list that updates as checks complete:

```
### CI Status
- [x] **lint**: *pass* (12s)
- [x] **test-debian12**: *pass* (1m 42s)
- [ ] **test-rocky9**: *running*
- [ ] **test-centos7**: *pending*
```

When CI completes, collapse into a single line in the final report.

## Stage 5: Final Report

Present a structured summary using tables, task lists, and
blockquotes. This is the final output the user sees — it must be
scannable at a glance.

```
## Ship Report: {project} `{version}`

| Property | Value | Property | Value |
|----------|-------|----------|-------|
| **PR** | {url} | **Commits** | `{count}` |
| **Branch** | `{branch}` -> `{base}` | **HEAD** | `{hash}` |

---

### Verification Gates
- [x] **QA**: *PASS* — `{test_count}` tests, `{fail_count}` failures
- [x] **Reviewer**: *APPROVE* — {summary}

### Release Prep
- [x] **Changelog**: updated — `{entry_count}` entries
- [x] **Attribution scrub**: clean
- [x] **Version strings**: consistent (`{version}`)
- [x] **Commit**: `{hash}` pushed to `origin/{branch}`

### CI
- [x] **Status**: *pass* — all checks green

---

### Verdict
**READY TO MERGE** — all gates passed, PR awaiting review
```

**Verdict styling** — use bold for the verdict keyword and a brief
reason. Three possible verdicts:

- **READY TO MERGE** — all gates passed, no action needed
- **ACTION NEEDED** — non-blocking findings or overridden gates
- **BLOCKED** — unresolved gate failures

When the verdict is not READY TO MERGE, use a blockquote to
highlight what needs attention:

> **ACTION NEEDED** — reviewer flagged 1 concern (overridden by user)

When the verdict is BLOCKED, list the blockers:

> **BLOCKED** — cannot merge
> - QA gate: *FAIL* — 3 test failures
> - Version strings: *mismatch* in `setup.py`

After presenting the final report, output the completion handoff:

> **Released** — PR `{url}`
> Merge when CI passes. Pipeline complete.

Delete `.rdf/work-output/ship-progress.md` after successful completion.

## Formatting Guide

All output from this workflow uses the markdown primitives below.
Follow these consistently across every stage.

| Primitive | Syntax | Use in this workflow |
|-----------|--------|----------------------|
| **Table** | `\| col \| col \|` | Ship report summary, PR metadata |
| **Task list** | `- [x]` / `- [ ]` | Preflight checks, gate results, release prep, CI status |
| **Blockquote** | `>` | Blockers, warnings, gate failures, version mismatches |
| **Bold** | `**text**` | Labels (PR, Branch, QA), verdict keywords |
| **Italic** | `*text*` | Status keywords (*PASS*, *FAIL*, *running*, *skipped*) |
| **Inline code** | `` `text` `` | Versions, hashes, branch names, paths, commands, counts |
| **Rule** | `---` | Section dividers in final report |

**Do NOT use** (not rendered in Claude Code):
HTML tags, `<details>`, ANSI color codes, Mermaid diagrams, footnotes.

**Conventions:**
- Task lists give instant pass/fail state — checked = passed,
  unchecked = failed or pending
- Blockquotes draw the eye to blockers — use for anything that
  halts the workflow or needs user action
- Inline code makes values scannable — always wrap versions,
  hashes, branch names, paths, and commands
- Bold labels on the left, values on the right — consistent
  across task lists and tables
- Italic for status keywords only — keeps them visually distinct
  from labels and values

## Constraints
- Never auto-merge — user must confirm
- Never force-push
- Always show verification results before creating PR
- If governance/verification.md is missing, warn but proceed with
  default checks (lint, test execution)
- Respect project commit protocol from governance/conventions.md
