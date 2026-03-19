Commit, push, create a PR against the main branch, then monitor for Codex
automated review. While waiting, conduct your own independent PR review.
Triage all findings (yours and Codex's) and propose fixes for confirmed issues.

## Arguments
- `$ARGUMENTS` — optional: base branch override (default: auto-detect via
  `git symbolic-ref refs/remotes/origin/HEAD` or fall back to `master`)

## Phase 1: Ship the PR

### 1a. Pre-flight
- Run `git status` (never `-uall`), `git diff --stat`, `git log --oneline -5`
- If there are uncommitted changes, assess whether they should be staged.
  Follow the project's CLAUDE.md commit protocol (explicit staging by filename,
  tagged line items, no Co-Authored-By, no working files).
- If there is nothing to commit and the branch is already pushed with an open
  PR, skip to Phase 2 using the existing PR.

### 1b. Commit (if needed)
- Stage files explicitly by name (NEVER `git add -A` or `git add .`)
- Commit with the project's message format and tagged line items
- Exclude working files: CLAUDE.md, PLAN*.md, AUDIT.md, MEMORY.md, .claude/

### 1c. Push
- Push the current branch to origin with `-u` flag
- If the branch has no upstream, set it: `git push -u origin HEAD`

### 1d. Create PR
- Detect base branch: use `$ARGUMENTS` if provided, otherwise auto-detect
- Use `gh pr create` with:
  - Short title (under 70 chars) summarizing the branch's full scope
  - Body with `## Summary` (bullet points from `git log`) and `## Test plan`
- If a PR already exists for this branch, print its URL and skip creation
- Capture the PR number and URL for Phase 2

## Phase 2: Await Codex review (concurrent with Phase 3)

Codex is a GitHub bot that reviews PRs. Its workflow:
1. Reacts with an **eyeball** emoji on the PR body (means: "reviewing")
2. Then either:
   - Replaces eyeball with **thumbs-up** (+1) emoji (means: "approved, no findings"), OR
   - Posts one or more **review comments** on the PR (means: "findings to address")
   - The thumbs-up will appear after comments are posted (means: "review complete")

### 2a. Wait for initial reaction (up to 5 minutes)
```bash
# Poll every 30s for up to 5 minutes
# gh api repos/{owner}/{repo}/issues/{pr}/reactions
```
- Look for Codex bot's reaction (eyeball or +1) on the PR body
- If no reaction after 5 minutes, warn and continue with Phase 3 results only

### 2b. Wait for review completion (up to 15 minutes after eyeball)
Once the eyeball appears, Codex is actively reviewing. Now wait for resolution:

- **Poll every 30s** for up to 15 minutes (or until thumbs-up appears):
  - Check PR reactions: `gh api repos/{owner}/{repo}/issues/{pr}/reactions`
  - Check PR review comments: `gh api repos/{owner}/{repo}/pulls/{pr}/comments`
  - Check PR reviews: `gh api repos/{owner}/{repo}/pulls/{pr}/reviews`
  - Check issue comments: `gh api repos/{owner}/{repo}/issues/{pr}/comments`
- **Thumbs-up without comments** = clean review, report "Codex: APPROVED" and
  proceed to final summary
- **Comments appear** = findings to triage. Collect ALL comments before
  proceeding (wait for thumbs-up or timeout to ensure completeness)
- **Timeout** = warn "Codex review incomplete" and proceed with whatever data
  we have

### 2c. Parse Codex findings
For each Codex comment/review:
- Extract the file, line, and description
- Categorize: bug, security, performance, style, suggestion
- Prepare for triage in Phase 4

## Phase 3: Independent PR review (concurrent with Phase 2)

While waiting for Codex, perform your own thorough review of ALL changes in
the PR (not just the latest commit — the full diff against base branch).

```bash
git diff $(git merge-base HEAD origin/{base})...HEAD
```

### Review dimensions — be critical:

**Regressions:**
- Does any change break existing behavior or API contracts?
- Are there callers that depend on the old behavior?
- Do error codes, exit statuses, or output formats change?

**Security:**
- Input validation gaps (path traversal, injection, unquoted variables)
- Privilege escalation vectors (world-writable files, unsafe temp files)
- Secrets or sensitive paths exposed

**Performance:**
- Unnecessary subshells or forks in hot paths
- O(n^2) patterns (nested loops over arrays, repeated greps)
- Large file reads where incremental reads suffice

**Correctness:**
- Edge cases: empty input, missing files, concurrent access
- Arithmetic overflow or unvalidated numeric contexts
- Race conditions (TOCTOU in file operations)

**Code quality:**
- Dead code, unreachable branches
- Duplicated logic that should be factored
- Inconsistency with existing project patterns

**Documentation drift:**
- Do CHANGELOG entries match actual changes?
- Are new functions/options documented in help text and README?
- Do comments match the code they describe?

**Test coverage:**
- Are new code paths tested?
- Are edge cases and error paths covered?
- Do tests verify false-positive conditions (things that should NOT happen)?

Produce a structured list of your own findings with severity and file:line.

## Phase 4: Triage and remediation

Combine findings from Codex (Phase 2) and your own review (Phase 3).

### For each finding:

1. **Verify against actual code** — read the file and surrounding context.
   Many automated findings are false positives. Check thoroughly.

2. **Classify:**
   - **FALSE POSITIVE** — explain why (code already handles this, finding
     misreads context, pattern doesn't apply here). Be specific.
   - **CONFIRMED — Fix needed** — describe the fix, severity, and which
     file(s) to change
   - **CONFIRMED — Deferred** — real issue but out of scope for this PR
     (pre-existing, affects unrelated code). Note for future work.
   - **STYLE/NIT** — not wrong but could be improved. Note without blocking.

3. **Double-check your triage** — re-read the finding and the code one more
   time. False negatives (dismissing real bugs) are worse than false positives.

### Produce the triage report:

```
## Codex Findings Triage

| # | Finding | Verdict | Rationale |
|---|---------|---------|-----------|
| 1 | ... | FP / Fix / Defer / Nit | ... |

## Self-Review Findings

| # | Severity | File:Line | Finding | Action |
|---|----------|-----------|---------|--------|
| 1 | ... | ... | ... | Fix / Defer / Nit |
```

### Propose fixes for confirmed items:
- For each CONFIRMED fix-needed finding, describe the specific change
- If the fix is small and safe, offer to implement it immediately
- If the fix is complex or risky, recommend a follow-up commit
- Group related fixes that should be committed together

## Phase 4b: GitHub issue lifecycle (post-merge)

After the PR is merged (or when confirmed ready to merge):

- Close the `type:release` issue for this version (if not already closed):
  ```bash
  gh issue close <release-issue-number> --repo <repo>
  ```
- Verify all `type:phase` issues for this release are already closed
- If a parent `type:initiative` exists and all its child releases are now
  complete, update the initiative body Status to "Complete" and close it
- Reference the release issue in commit messages: `Ref #<release-issue>`

## Phase 5: Final summary

```
# PR Ship Report: <repo> #<pr_number>

**PR:** <url>
**Branch:** <branch> -> <base>
**Commits:** <count>

## Codex Review
- Status: APPROVED / FINDINGS / TIMEOUT / NO RESPONSE
- Findings: <count> (<count> FP, <count> confirmed, <count> deferred)

## Self-Review
- Findings: <count> (<count> by severity)

## Confirmed Issues Requiring Action
1. [severity] file:line — description — proposed fix

## False Positives (for reference)
1. finding — rationale

## Verdict
- CLEAN: No issues found — PR is good to merge
- ACTION NEEDED: <count> confirmed issues — fixes proposed above
- DEFERRED: <count> items noted for future work
```
