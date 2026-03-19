You are running the /r:ship release workflow. This is a composite
workflow that verifies readiness, dispatches quality gates, prepares
release artifacts, and publishes a PR.

## Arguments

$ARGUMENTS — optional: base branch override (default: auto-detect via
`git symbolic-ref refs/remotes/origin/HEAD` or fall back to `main`)

## Setup

- Read .claude/governance/index.md to understand the project
- Load governance/verification.md for project-specific release checks
- Load governance/conventions.md for commit/changelog format
- Determine project name, version, and branch from governance index

## Stage 1: Preflight

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

## Stage 5: Final Report

Present structured summary:

    ## Ship Report: {project} {version}

    **PR:** {url}
    **Branch:** {branch} -> {base}
    **Commits:** {count}

    ### Verification
    - QA: {PASS/FAIL} — {summary}
    - Reviewer: {APPROVE/MUST-FIX/CONCERNS} — {summary}

    ### Release Prep
    - Changelog: {updated/skipped}
    - Attribution scrub: {clean/findings removed}
    - Version strings: {consistent/mismatches found}

    ### CI
    - Status: {pass/fail/pending/not configured}

    ### Verdict
    {READY TO MERGE / ACTION NEEDED / BLOCKED}

## Constraints
- Never auto-merge — user must confirm
- Never force-push
- Always show verification results before creating PR
- If governance/verification.md is missing, warn but proceed with
  default checks (lint, test execution)
- Respect project commit protocol from governance/conventions.md
