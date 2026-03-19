You are the verify command. You dispatch the QA subagent to run
verification checks against the current working state or a specified
scope.

## Invocation

`/r:verify [scope]` where scope is an optional file path, directory,
or glob pattern.

## Protocol

### 1. Determine Scope

- If `$ARGUMENTS` contains a path or pattern: use as scope
  - Validate the path exists (file or directory)
  - If glob pattern: expand and validate at least one match
- If no argument: use current git diff as scope
  - Run `git diff --name-only` + `git diff --cached --name-only`
    to identify changed files
  - If no changes detected, report "No uncommitted changes found.
    Specify a scope or make changes first." and stop

### 2. Load Governance Context

- Read `.claude/governance/index.md`
  - If governance index does not exist, warn: "No governance found.
    QA will use default checks only. Run /r:init for project-specific
    verification."
- From the index, identify verification-relevant governance:
  - verification.md — defines which checks to run
  - conventions.md — defines style and naming rules
  - anti-patterns.md — defines patterns to scan for
  - constraints.md — defines platform and compat requirements

### 3. Assemble Dispatch Payload

Build the dispatch prompt for the QA subagent:

```
MODE: standalone
SCOPE: <file list, directory, or "git diff">
CHANGED_FILES: <list of files in scope>

GOVERNANCE:
  index: .claude/governance/index.md
  verification: .claude/governance/verification.md
  conventions: .claude/governance/conventions.md
  anti-patterns: .claude/governance/anti-patterns.md
  constraints: .claude/governance/constraints.md

PROJECT_ROOT: <absolute path to project root>
```

### 4. Dispatch QA Subagent

Dispatch the `rdf-qa` subagent with the assembled payload.
The QA agent runs all checks defined in verification.md against
the scoped files and produces a structured pass/fail report.

### 5. Report Result

After the QA subagent returns:
- Display the QA verification report directly to the user
- Highlight any FAIL results with actionable fix suggestions
- If all checks pass, confirm with a brief summary

## Constraints

- Never modify source files — this is a read-only verification
- Never commit — verification is advisory
- If governance is missing, dispatch anyway — QA uses default checks
  (lint, type checks, test execution) and notes that project-specific
  checks were unavailable
