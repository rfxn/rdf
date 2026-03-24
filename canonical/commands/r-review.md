You are the review command. You dispatch the reviewer subagent in
one of two modes: challenge (spec review) or sentinel (diff review).

## Invocation

`/r-review [--challenge <file>] [--sentinel] [scope]`

- `--challenge <file>` — review a spec or plan file for design flaws,
  missed edge cases, and simpler alternatives
- `--sentinel [scope]` — review a diff for anti-slop, regression,
  security, and performance issues
- No flags — defaults to `--sentinel` against current branch diff

## Protocol

### 1. Parse Mode and Arguments

- If `$ARGUMENTS` contains `--challenge`:
  - Extract the file path argument following `--challenge`
  - Validate the file exists and is a readable markdown file
  - If no file path provided: report error "Usage: /r-review
    --challenge <spec-file>" and stop
  - Set mode to `challenge`
- If `$ARGUMENTS` contains `--sentinel`:
  - Extract optional scope (file paths, directories) after the flag
  - If no scope: use current branch diff
    (`git diff main...HEAD` or detect base branch)
  - Set mode to `sentinel`
- If no flags in `$ARGUMENTS`:
  - Default to sentinel mode
  - If arguments contain a path to a `.md` file in `docs/specs/`:
    infer challenge mode (convenience shortcut)
  - Otherwise use current branch diff as scope

### 2. Determine Diff Scope (sentinel mode)

- If scope is specified: use those files/directories
- If no scope: compute branch diff
  - Detect base branch (main, master, or parent branch)
  - Run `git diff <base>...HEAD --name-only` to identify changed files
  - If no diff found (clean branch, no divergence from base):
    fall back to `git diff --name-only` + `git diff --cached --name-only`
    for uncommitted changes
  - If still no changes: report "No changes found to review.
    Specify a scope or make changes first." and stop

### 3. Load Governance Context

- Read `.rdf/governance/index.md`
  - If governance index does not exist, warn: "No governance found.
    Review will use general best practices only. Run /r-init for
    project-specific review criteria."
- Governance files loaded depend on mode:
  - **Challenge mode**: architecture.md, constraints.md (for design
    review context)
  - **Sentinel mode**: anti-patterns.md, constraints.md,
    conventions.md (for code review context)

### 4. Assemble Dispatch Payload

**Challenge mode:**

```
MODE: challenge
TARGET: <absolute path to spec/plan file>
FILE_CONTENT: <contents of the target file>

GOVERNANCE:
  index: .rdf/governance/index.md
  architecture: .rdf/governance/architecture.md
  constraints: .rdf/governance/constraints.md

PROJECT_ROOT: <absolute path to project root>
```

**Sentinel mode:**

```
MODE: sentinel
SCOPE: <file list or "branch diff">
CHANGED_FILES: <list of files in scope>
BASE_BRANCH: <base branch name>
DEPTH: full

GOVERNANCE:
  index: .rdf/governance/index.md
  anti-patterns: .rdf/governance/anti-patterns.md
  constraints: .rdf/governance/constraints.md
  conventions: .rdf/governance/conventions.md

REPORT_FORMAT:
  Include per-finding: file, line, severity, description, why,
  suggested fix, CH_RESULT, CH_REASON.
  Include footer: DISCARDED_FINDINGS count and log.

PROJECT_ROOT: <absolute path to project root>
```

### 5. Dispatch Reviewer Subagent

Dispatch the `rdf-reviewer` subagent with the assembled payload.

- Challenge mode: reviewer performs design review and produces a
  challenge report with MUST-FIX(blocking-concern) / SHOULD-FIX(advisory-concern) / INFORMATIONAL(risk-area) findings
- Sentinel mode: reviewer performs 4-pass adversarial review
  (anti-slop, regression, security, performance) and produces a
  sentinel report with MUST-FIX(fix-or-refute) | SHOULD-FIX(pass:<name>) findings

### 6. Report Result

After the reviewer subagent returns:
- Display the review report directly to the user
- **Challenge mode**: highlight MUST-FIX findings that must be
  resolved before implementation; summarize SHOULD-FIX and INFORMATIONAL
  counts
- **Sentinel mode**: highlight MUST-FIX findings; summarize verdict
  (APPROVE / MUST-FIX / CONCERNS)

## Constraints

- Never modify source files — review is read-only
- Never commit — review is advisory
- If governance is missing, dispatch anyway — reviewer uses general
  best practices and notes that project-specific anti-patterns and
  constraints were unavailable
- Challenge mode requires a file argument — it does not operate on
  diffs
- Sentinel mode defaults to branch diff — it does not operate on
  individual spec files (use challenge mode for that)
