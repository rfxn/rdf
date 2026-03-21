You are running the /r:audit full codebase audit. This command
dispatches multiple reviewer and qa subagents in parallel to scan the
entire codebase for latent issues, then synthesizes findings into a
structured AUDIT.md.

## Arguments

$ARGUMENTS — optional scope:
- No args: full codebase audit
- File/directory path: scoped audit of specific area
- `--quick`: skip subagent dispatch, run inline checks only

## Setup

- Read .rdf/governance/index.md to understand the project
- Load governance/verification.md for project-specific checks
- Load governance/anti-patterns.md for known pitfalls
- Load governance/constraints.md for platform/compat requirements
- Create `.rdf/work-output/` directory if it does not exist
- Remove stale audit files from prior run: `rm -f .rdf/work-output/audit-*.md`

## Task List Protocol

At command startup, create tasks for live progress tracking:

```
TaskCreate:
  subject: "Load governance context and determine scope"
  activeForm: "Loading governance context"
TaskCreate:
  subject: "Dispatch audit subagents"
  activeForm: "Dispatching audit agents"
TaskCreate:
  subject: "Collect and deduplicate findings"
  activeForm: "Collecting findings"
TaskCreate:
  subject: "Synthesize AUDIT.md"
  activeForm: "Writing AUDIT.md"
TaskCreate:
  subject: "Present audit summary"
  activeForm: "Presenting summary"
```

Lifecycle: all tasks start pending. Before starting each stage,
mark its task in_progress. After completing, mark completed.

For Stage 2 (parallel subagent dispatch), update the activeForm
as agents complete: "Dispatching audit agents: 3/4 complete..."

---

## Stage 1: Governance Context

Mark task "Load governance context and determine scope" as `in_progress`.

### 1a. Build Audit Context
- Extract from governance: language, framework, test framework,
  linter configs, platform targets, known anti-patterns
- Identify high-risk areas from governance/architecture.md
  (security boundaries, data flows, external interfaces)
- Build a context summary for subagent dispatch prompts

### 1b. Determine Scope
- Full audit: all source files in the project
- Scoped audit: files matching the provided path argument
- Quick audit: inline checks only, no subagent dispatch

Mark task "Load governance context and determine scope" as `completed`.

## Stage 2: Dispatch Parallel Subagents

Mark task "Dispatch audit subagents" as `in_progress`.

Dispatch 4 subagents simultaneously. Each receives the audit context
from Stage 1 plus focus-specific instructions.

### 2a. Reviewer — Regression + Anti-Slop Focus
Dispatch reviewer subagent in sentinel mode:
- Focus passes: anti-slop (pass 1) and regression (pass 2)
- Scope: entire codebase (not just a diff)
- Extra context: governance/anti-patterns.md
- Write results to: .rdf/work-output/reviewer-regression.md

### 2b. Reviewer — Security Focus
Dispatch reviewer subagent in sentinel mode:
- Focus pass: security (pass 3)
- Scope: entire codebase with emphasis on:
  - Input validation boundaries
  - Authentication/authorization paths
  - Data serialization/deserialization
  - File operations with user-influenced paths
  - External command execution
- Extra context: governance/constraints.md (platform targets affect
  attack surface)
- Write results to: .rdf/work-output/reviewer-security.md

### 2c. Reviewer — Performance Focus
Dispatch reviewer subagent in sentinel mode:
- Focus pass: performance (pass 4)
- Scope: entire codebase with emphasis on hot paths, loops,
  data structure choices, I/O patterns
- Write results to: .rdf/work-output/reviewer-performance.md

### 2d. QA — Standards + Lint Verification
Dispatch qa subagent:
- Run every check in governance/verification.md
- Focus on: lint compliance, convention adherence, test coverage
  gaps, documentation drift
- Write results to: .rdf/work-output/qa-standards.md

### 2e. Wait and Monitor
- Track subagent completion (check for output files)
- Report progress: `Audit: N/4 agents complete`
- Timeout after 15 minutes per agent — proceed with available results

Mark task "Dispatch audit subagents" as `completed`.

## Stage 3: Collect and Deduplicate

Mark task "Collect and deduplicate findings" as `in_progress`.

### 3a. Health Check
For each expected output file:
- File exists with content -> COMPLETE
- File exists but empty/truncated -> PARTIAL (warn, include anyway)
- File missing -> FAILED (exclude, note in report)

Report: `Agent Health: N/4 complete, N partial, N failed`

### 3b. Deduplicate Findings
- Read all completed output files
- Identify duplicate findings (same file + same issue, reported by
  multiple agents)
- When duplicates exist, keep the most detailed version
- Merge complementary details from duplicates into the kept finding
- Track dedup count for the report

Mark task "Collect and deduplicate findings" as `completed`.

## Stage 4: Synthesize AUDIT.md

Mark task "Synthesize AUDIT.md" as `in_progress`.

### 4a. Classify Findings
Assign severity to each unique finding:
- **Critical**: security vulnerabilities, data loss risk, crash bugs
- **Major**: correctness issues, regression risk, significant
  anti-pattern violations
- **Minor**: style issues, optimization opportunities, documentation
  gaps

Assign category:
- regression, security, performance, standards, anti-pattern

### 4b. Write AUDIT.md

Write structured audit report:

    # Audit Report: {project} {version}

    **Date:** {YYYY-MM-DD}
    **Scope:** {full codebase / scoped path}
    **Agents:** {N}/4 completed ({N} partial, {N} failed)

    ## Summary
    - Critical: {count}
    - Major: {count}
    - Minor: {count}
    - Total unique findings: {count} (deduplicated from {raw count})

    ## Critical Findings
    | # | Category | File:Line | Finding | Fix |
    |---|----------|-----------|---------|-----|
    (one row per critical finding)

    ## Major Findings
    | # | Category | File:Line | Finding | Fix |
    |---|----------|-----------|---------|-----|
    (one row per major finding)

    ## Minor Findings
    | # | Category | File:Line | Finding | Fix |
    |---|----------|-----------|---------|-----|
    (one row per minor finding)

    ## Agent Reports
    - Regression/Anti-Slop: {verdict} — {summary}
    - Security: {verdict} — {summary}
    - Performance: {verdict} — {summary}
    - Standards/Lint: {verdict} — {summary}

    ## Recommendations
    (prioritized action items derived from critical + major findings)

Mark task "Synthesize AUDIT.md" as `completed`.

## Stage 5: Present Summary

Mark task "Present audit summary" as `in_progress`.

- Display the Summary and Critical Findings sections inline
- Report the full AUDIT.md path
- If critical findings exist, recommend immediate action
- If only minor findings, report clean status with improvement notes

Mark task "Present audit summary" as `completed`.

## Quick Mode (--quick)

When `--quick` is passed, skip Stage 2 entirely:
- Run lint/shellcheck inline (from governance/verification.md)
- Grep for anti-patterns inline (from governance/anti-patterns.md)
- Produce a lightweight AUDIT.md with inline-only findings
- No subagent dispatch, no deduplication stage

## Constraints
- Never modify source files — audit is read-only
- Write findings to .rdf/work-output/ and AUDIT.md only
- Every finding must include file:line and a suggested fix
- Deduplicate aggressively — same issue from multiple agents is one
  finding
- If governance files are missing, warn and proceed with generic
  checks
