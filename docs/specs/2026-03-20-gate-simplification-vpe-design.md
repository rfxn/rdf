# Design: Gate Simplification & VPE Pipeline Orchestrator

**Date:** 2026-03-20
**Author:** Ryan MacDonald / Claude
**Status:** Draft
**Project:** RDF (rfxn Development Framework)

---

## 1. Problem Statement

The RDF 3.0 quality gate system has two remaining complexity problems
that the sentinel-gate-redesign (2026-03-20) did not fully resolve:

**Developer-facing input complexity.** The sentinel-gate-redesign
simplified the developer-facing *output* to ~6 concepts (PASS, MUST-FIX,
CONCERN, SUGGESTION, end-of-plan review, phase status file). But the
*input* surface in r-plan Section 2.3 still requires the planner to tag
each phase with 7 mandatory metadata fields (Mode, Risk, Type, Gates,
Accept, Test, Edge cases), internalize a 6-row gate derivation table
mapping risk×type combinations to numbered gates with depth tiers, and
understand 3 risk levels × 6 type values = 18 possible combinations.
The spec itself says "these are planner hints, not developer
responsibilities" — but they are mandatory plan metadata that the
planner must produce correctly for the dispatcher to function.

Evidence: r-plan.md Section 2.3 contains the full gate derivation table.
Every plan produced by /r:plan includes Risk, Type, and Gates fields per
phase. The planner must read and understand the gate selection matrix to
tag correctly.

**Finding vocabulary lost routing information.** v3 unified all agent
finding vocabularies to a flat MUST-FIX / CONCERN / SUGGESTION scale.
This tells the dispatcher severity but not WHO should act or HOW. In
v2, each agent had a domain-specific vocabulary that self-routed:
QA's MUST-FIX meant "engineer fix code (blocks merge)"; UAT's
WORKFLOW-BREAKING meant "engineer fix workflow"; Challenger's
BLOCKING_CONCERN meant "planner amend the plan." v3's flat vocabulary
requires the dispatcher to maintain an internal lookup table to determine
the correct action for each finding×source combination.

Evidence: v2 sys-sentinel.md (ecb16e8) defined MUST-FIX vs SHOULD-FIX
with per-pass default severities. v2 sys-qa.md defined MUST-FIX /
SHOULD-FIX / INFORMATIONAL with ESCALATION_RECOMMENDED. v2 sys-uat.md
defined WORKFLOW-BREAKING / USER-FACING / COSMETIC with UX ratings.
v2 sys-challenger.md defined BLOCKING_CONCERN / ADVISORY_CONCERN /
RISK_AREA / VERIFIED_SOUND. All collapsed to 3 levels in v3.

**No pipeline orchestrator.** Users who want end-to-end workflow
management must manually invoke /r:spec, /r:plan, /r:build (per phase),
and /r:ship in sequence, managing transitions and context themselves.
v2 had an mgr agent that orchestrated the full lifecycle. v3 removed it
when collapsing 12 agents to 6, replacing it with the dispatcher — but
the dispatcher only manages build phases, not the full pipeline.

Competitive analysis: Agent Teams Lite uses a delegate-only orchestrator
that manages the full DAG (explore→propose→spec→tasks→apply→verify).
CrewAI Flows coordinate multiple crews through a project plan. Both
provide pipeline-level orchestration that RDF currently lacks.

### Metrics

| Metric | Current | Target |
|--------|---------|--------|
| Planner metadata fields per phase | 7 (Mode, Risk, Type, Gates, Accept, Test, Edge cases) | 4 (Mode, Accept, Test, Edge cases) |
| Gate-related concepts planner must know | ~15 (3 risk × 6 type + gate table + depth tiers) | 0 (dispatcher auto-derives) |
| Finding severity scales | 1 flat (3 levels, no routing) | 1 shared (3 levels + agent-scoped qualifiers) |
| Pipeline commands user must invoke manually | 4+ (spec, plan, build ×N, ship) | 1 optional (/r:vpe) or 4 (existing commands unchanged) |
| Developer-facing scope concepts | 0 (gate selection hidden but tags exposed) | 5 (scope levels, read-only, in framework.md) |

---

## 2. Goals

1. Planner tags only Mode, Accept, Test, and Edge cases — Risk, Type, and Gates removed from plan metadata
2. Dispatcher auto-derives scope classification from phase content (file list, description, governance)
3. Scope classification uses 5 self-describing levels: docs, focused, multi-file, cross-cutting, sensitive
4. Each agent produces findings with shared severity spine (MUST-FIX / SHOULD-FIX / INFORMATIONAL) plus agent-scoped qualifiers that carry routing signals
5. `/r:vpe` command provides optional end-to-end pipeline orchestration (spec→plan→build→ship) with conversational intake and approval gates
6. VPE is purely additive — zero changes to existing pipeline commands
7. Existing pipeline commands (/r:spec, /r:plan, /r:build, /r:ship) continue to work independently
8. Agent count remains at 6 — VPE is a command, not an agent

---

## 3. Non-Goals

- Splitting the reviewer back into separate sentinel/challenger agents
- Changing the 6-agent architecture (planner, dispatcher, engineer, qa, uat, reviewer)
- Modifying the engineer agent
- Changing /r:init, /r:refresh, /r:audit behavior
- Changing the counter-hypothesis protocol (reviewer-internal, unchanged)
- Changing FP calibration (dispatcher-internal, unchanged)
- Changing the finding resolution loop (dispatcher-internal, unchanged)
- Modifying execution modes (serial-context, serial-agent, parallel-agent)
- Adding governance file types
- Making VPE mandatory — it is always optional

---

## 4. Architecture

### 4.1 File Map

#### New Files

| File | Est. Lines | Purpose |
|------|-----------|---------|
| `canonical/commands/r-vpe.md` | ~250 | VPE pipeline orchestrator command |

#### Modified Files

| File | Lines (current) | Lines (after) | Changes |
|------|----------------|---------------|---------|
| `canonical/agents/dispatcher.md` | 227 | ~210 | Replace gate selection matrix with scope classification; update finding resolution for qualifier-aware routing |
| `canonical/agents/reviewer.md` | 150 | ~155 | Update severity output format to include qualifiers |
| `canonical/agents/qa.md` | 60 | ~65 | Update severity output format to include qualifiers |
| `canonical/agents/uat.md` | 57 | ~62 | Update severity output format to include qualifiers |
| `canonical/commands/r-plan.md` | 523 | ~460 | Remove Risk, Type, Gates from Section 2.3 and 2.6; remove gate derivation table; update plan quality standard |
| `canonical/commands/r-build.md` | 121 | ~110 | Remove Risk and Type from dispatch payload; add scope derivation note |
| `canonical/commands/r-review.md` | 130 | ~133 | Update finding severity labels in dispatch payload examples |
| `canonical/commands/r-start.md` | 220 | ~225 | Add VPE in-flight detection (vpe-progress.md) |
| `canonical/commands/r-status.md` | 200 | ~205 | Add VPE pipeline stage to dashboard |
| `canonical/reference/framework.md` | 231 | ~240 | Update gate selection section with scope classification summary |
| `reference/diagrams.md` | 476 | ~480 | Update Section 4 (Quality Gates) for scope classification |
| `modes/development/context.md` | 50 | ~50 | Update stale "phase tags" reference to scope-based auto-derivation |
| `canonical/reference/session-safety.md` | 74 | ~78 | Add vpe-progress.md to recovery signals |

#### No-Touch Files

| File | Reason |
|------|--------|
| `canonical/agents/planner.md` | Planner protocol unchanged — it already produces what we need |
| `canonical/agents/engineer.md` | Engineer protocol unchanged |
| `canonical/commands/r-spec.md` | Spec command unchanged — VPE calls it, doesn't modify it |
| `canonical/commands/r-ship.md` | Ship command unchanged — VPE calls it, doesn't modify it |
| `canonical/commands/r-mode.md` | Mode command unchanged |
| `canonical/commands/r-save.md` | Save command unchanged |
| `canonical/commands/r-init.md` | Init command unchanged |
| `canonical/commands/r-refresh.md` | Refresh command unchanged |

### 4.2 Size Comparison

| Component | Before | After | Delta |
|-----------|--------|-------|-------|
| dispatcher.md | 227 | ~210 | -17 (simpler classification replaces matrix) |
| reviewer.md | 150 | ~155 | +5 |
| qa.md | 60 | ~65 | +5 |
| uat.md | 57 | ~62 | +5 |
| r-plan.md | 523 | ~460 | -63 (Risk/Type/Gates/table removed) |
| r-build.md | 121 | ~110 | -11 |
| r-vpe.md (new) | 0 | ~250 | +250 |
| Other files | ~1231 | ~1241 | +10 |
| **Total delta** | | | **+184** |

### 4.3 Dependency Tree

```
r-vpe.md (command, NEW — optional pipeline orchestrator)
  ├── invokes r-spec.md inline (user participates in brainstorming)
  ├── invokes r-plan.md inline (user approves plan)
  ├── invokes r-build.md per phase (dispatches dispatcher subagent)
  │     └── dispatcher.md (subagent)
  │           ├── auto-derives scope classification from phase content
  │           ├── dispatches rdf-engineer
  │           ├── dispatches rdf-qa (qualifier-aware findings)
  │           ├── dispatches rdf-reviewer (qualifier-aware findings)
  │           ├── dispatches rdf-uat (qualifier-aware findings)
  │           ├── routes findings by qualifier
  │           └── end-of-plan sentinel (unchanged)
  └── invokes r-ship.md (existing lifecycle)

r-plan.md (command — simplified tagging)
  └── produces PLAN.md with 4 metadata fields per phase
      (Mode, Accept, Test, Edge cases — no Risk/Type/Gates)

r-build.md (command — simplified dispatch)
  └── dispatches dispatcher without Risk/Type
      (dispatcher derives scope from phase content)
```

### 4.4 Key Changes

**Design principle: one dimension, not two.** The v3 gate selection used
a risk×type matrix (3×6 = 18 combinations mapped to gate configurations).
This is replaced by a single scope dimension with 5 levels, derived by the
dispatcher from the phase content. The scope classification is proven —
v2 used this exact model (as "tiers") across 273 sessions.

**1. Scope classification replaces gate derivation.** The dispatcher
reads the phase's file list, description, and governance, then classifies:

```
scope:docs          — all files are docs/changelog/comments
scope:focused       — 1 file, config, single function
scope:multi-file    — 2+ files, standard feature/refactor work
scope:cross-cutting — install paths, CLI entry points, cross-OS logic
scope:sensitive     — security paths, shared libs, data migration

Gate mapping (dispatcher-internal):
  scope:docs          → G1 only
  scope:focused       → G1 + G2
  scope:multi-file    → G1 + G2 + G3-lite
  scope:cross-cutting → G1 + G2 + G3-full
  scope:sensitive     → G1 + G2 + G3-full

User-facing modifier: if any file is a CLI entry point or help text,
add G4 (UAT) regardless of scope level.
```

**2. Finding vocabulary gains routing qualifiers.** All agents share one
severity spine (MUST-FIX / SHOULD-FIX / INFORMATIONAL). Each agent adds
a qualifier that carries the routing signal:

```
QA:         MUST-FIX(merge-block)      / SHOULD-FIX(advisory)          / INFORMATIONAL
            ESCALATION_RECOMMENDED (special: routes to dispatcher for re-dispatch)
Sentinel:   MUST-FIX(fix-or-refute)    / SHOULD-FIX(pass:<name>)       / INFORMATIONAL
UAT:        MUST-FIX(workflow-breaking) / SHOULD-FIX(user-facing)       / INFORMATIONAL(cosmetic)
Challenger: MUST-FIX(blocking-concern)  / SHOULD-FIX(advisory-concern)  / INFORMATIONAL(risk-area)
            VERIFIED_SOUND (special: positive signal, no action)
```

The dispatcher reads the qualifier to route findings:
- `(merge-block)` → engineer: fix code
- `(fix-or-refute)` → engineer: fix or provide counter-evidence
- `(workflow-breaking)` → engineer: fix workflow
- `(blocking-concern)` → planner: amend plan
- `(advisory-concern)` → log for consideration
- `(user-facing)` → collect for UX review
- `(pass:<name>)` → context for which review pass produced it
- `ESCALATION_RECOMMENDED` → dispatcher re-dispatches at higher scope
- `VERIFIED_SOUND` → positive signal, logged

**3. Planner metadata simplified.** The planner tags each phase with 4
fields (Mode, Accept, Test, Edge cases) instead of 7. Risk, Type, and
Gates are removed entirely. The gate derivation table is removed from
r-plan. The dispatcher derives everything it needs from the phase content.

**4. VPE command added.** `/r:vpe` is a new command (skill, main context)
that provides optional end-to-end pipeline orchestration. It:
- Takes outcome-oriented conversation from the user
- Adaptively improves the prompt (1-4 exchanges based on clarity)
- Invokes /r:spec (user participates in brainstorming)
- Manages transition to /r:plan (user approves plan)
- Invokes /r:build per phase (dispatcher handles execution)
- Manages transition to /r:ship
- Pauses at approval gates between pipeline stages
- Tracks state via `work-output/vpe-progress.md` for crash recovery

The VPE is purely additive. It calls existing commands unchanged. The
existing commands don't know VPE exists.

### 4.5 Dependency Rules

- Scope classification changes must not alter the end-of-plan sentinel
  threshold or parallel failure semantics
- Finding qualifier changes must not alter the counter-hypothesis
  protocol or FP calibration logic
- VPE must not modify any existing command file
- The 5 scope levels are dispatcher constants, not configurable per plan
- Gate mapping from scope levels is dispatcher-internal, not documented
  in developer-facing surfaces

---

## 5. File Contents

### 5.1 `canonical/agents/dispatcher.md` — Scope Classification

**Change inventory:**

| Section | Current behavior | New behavior | Lines affected |
|---------|-----------------|--------------|----------------|
| Gate Selection header | "reads phase tags from PLAN.md as hints" | "auto-derives scope from phase content" | 58-62 |
| Gate Selection matrix | 8 entries mapping risk×type to gates | 5 entries mapping scope levels to gates | 64-71 |
| Finding Resolution | Routes by severity only | Routes by severity + qualifier | 152-207 |
| Dispatch payload parsing | Reads RISK and TYPE from payload | Reads file list and description, derives scope | 13-16 |

**New Scope Classification section (replaces Gate Selection matrix):**

```
### Scope Classification (dispatcher-internal)

The dispatcher classifies each phase by change scope, derived
automatically from the phase's file list, description, and governance
context. The planner does not tag scope — the dispatcher infers it.

Derivation rules:
1. Read the phase file list and description from the dispatch payload
2. Count files. Read file paths and match against governance signals.
3. Classify:

  scope:docs
    All files are documentation, changelog, comments, or README.
    No source code changes.

  scope:focused
    1 file changed, or all changes confined to config/scaffolding.
    Single function modification.

  scope:multi-file
    2+ source files changed. Standard feature or refactor work.
    No install paths, CLI entry points, or security-critical paths.

  scope:cross-cutting
    Changes touch install scripts, CLI entry points, cross-OS logic,
    breaking changes, or paths flagged in governance/constraints.md.

  scope:sensitive
    Changes touch security-critical paths, shared libraries consumed
    by other projects, data migration logic, or credential handling.
    Also: any file path flagged in governance/anti-patterns.md as
    security-sensitive.

Precedence: classify at the highest matching scope level. If any
file matches a higher scope signal, the entire phase is classified
at that level. Evaluation order:
  sensitive > cross-cutting > multi-file > focused > docs

Gate mapping:
  scope:docs          → Gate 1 only
  scope:focused       → Gates 1 + 2
  scope:multi-file    → Gates 1 + 2 + Gate 3 (sentinel-lite, 2-pass)
  scope:cross-cutting → Gates 1 + 2 + Gate 3 (sentinel-full, 4-pass)
  scope:sensitive     → Gates 1 + 2 + Gate 3 (sentinel-full, 4-pass)

User-facing modifier (any scope level):
  If the file list contains CLI entry points, help text, or man pages,
  add Gate 4 (UAT) regardless of scope level.

Default (cannot determine scope): scope:multi-file
```

**Updated Finding Resolution routing (qualifier-aware):**

The existing Finding Resolution protocol (fix/refute loop, escalation
format, developer-facing output) is retained. Changes: (a) replace
CONCERN with SHOULD-FIX throughout, (b) replace SUGGESTION with
INFORMATIONAL throughout, (c) add qualifier-based routing table
before the existing protocol text.

```
### Finding Resolution (dispatcher-owned, qualifier-routed)

The dispatcher reads the finding's qualifier to determine routing:

MUST-FIX routing:
  (merge-block)      → dispatch engineer: "Fix this code issue."
  (fix-or-refute)    → dispatch engineer: "Fix or refute with evidence."
  (workflow-breaking) → dispatch engineer: "Fix this workflow."
  (blocking-concern)  → surface to user: "Design concern — amend plan
                        or override with justification."

SHOULD-FIX routing:
  (advisory)          → collect, present at phase end (non-blocking)
  (pass:<name>)       → collect with pass context (non-blocking)
  (user-facing)       → collect for UX review summary (non-blocking)
  (advisory-concern)  → log for planner consideration (non-blocking)

Special signals:
  ESCALATION_RECOMMENDED → re-derive scope at higher level,
                           re-dispatch affected gates
  VERIFIED_SOUND         → log as positive signal (no action)

INFORMATIONAL:
  All qualifiers → logged to phase status file only
```

### 5.2 `canonical/agents/reviewer.md` — Qualifier-Aware Findings

**Change inventory:**

| Section | Current behavior | New behavior | Lines affected |
|---------|-----------------|--------------|----------------|
| Challenge Mode report | BLOCKING / CONCERN / SUGGESTION | MUST-FIX(blocking-concern) / SHOULD-FIX(advisory-concern) / INFORMATIONAL(risk-area) + VERIFIED_SOUND | 29-36 |
| Sentinel Mode report | MUST-FIX / CONCERN | MUST-FIX(fix-or-refute) / SHOULD-FIX(pass:\<name\>) / INFORMATIONAL | 69-89 |
| Summary line | MUST-FIX: N \| CONCERN: N \| CLEAN: N | MUST-FIX: N \| SHOULD-FIX: N \| INFORMATIONAL: N | 89 |

**New Challenge Mode report format:**

```
## Challenge Review

**Target:** [spec or plan file]
**Verdict:** APPROVE | CONCERNS

### Findings
- MUST-FIX(blocking-concern) {finding}
  Why: {reasoning}
  Alternative: {what to do instead}
- SHOULD-FIX(advisory-concern) {finding}
  Why: {reasoning}
  Suggestion: {alternative approach}
- INFORMATIONAL(risk-area) {finding}
  Mitigation: {how to manage the risk}

### Verified Sound
- {aspect checked and found correct}

Every MUST-FIX(blocking-concern) must be addressed before proceeding.
SHOULD-FIX(advisory-concern) findings should be addressed but do not block.
INFORMATIONAL(risk-area) findings are logged for awareness.
```

**New Sentinel Mode report format:**

```
## Sentinel Review

**Target:** [diff or branch]
**Verdict:** APPROVE | MUST-FIX | CONCERNS

### Pass 1: Anti-Slop
- [CLEAN/FINDING] {details}
  Severity: SHOULD-FIX(pass:anti-slop)

### Pass 2: Regression
- [CLEAN/FINDING] {details}
  Severity: MUST-FIX(fix-or-refute)

### Pass 3: Security
- [CLEAN/FINDING] {details}
  Severity: MUST-FIX(fix-or-refute)

### Pass 4: Performance
- [CLEAN/FINDING] {details}
  Severity: SHOULD-FIX(pass:performance)

### Summary
MUST-FIX: {count} | SHOULD-FIX: {count} | INFORMATIONAL: {count}
```

Note: Verdict labels (APPROVE | MUST-FIX | CONCERNS) are report-level
judgments, distinct from per-finding severity labels (MUST-FIX /
SHOULD-FIX / INFORMATIONAL). Verdict labels are unchanged — "CONCERNS"
as a verdict means "SHOULD-FIX-level findings exist but no MUST-FIX."

Per-pass default severities (from v2, restored):
- Anti-Slop: SHOULD-FIX(pass:anti-slop). Elevate to MUST-FIX(fix-or-refute) when naming/semantic issue causes functional bug.
- Regression: MUST-FIX(fix-or-refute). Always — concrete evidence of behavioral change.
- Security: MUST-FIX(fix-or-refute). Always — concrete exploit path.
- Performance: SHOULD-FIX(pass:performance). Elevate to MUST-FIX(fix-or-refute) when observable degradation under production loads.

### 5.3 `canonical/agents/qa.md` — Qualifier-Aware Findings

**Change inventory:**

| Section | Current behavior | New behavior | Lines affected |
|---------|-----------------|--------------|----------------|
| Report Format findings | PASS/FAIL per check | MUST-FIX(merge-block) / SHOULD-FIX(advisory) / INFORMATIONAL per finding | 43-48 |
| Report Format footer | N/A | Add ESCALATION_RECOMMENDED field | after 48 |

**New report format:**

```
## QA Verification Report

**Scope:** [files or diff reviewed]
**Result:** PASS | FAIL

### Checks
- [PASS/FAIL] Lint: {details}
- [PASS/FAIL] Type checks: {details}
- [PASS/FAIL] Anti-patterns: {details}
- [PASS/FAIL] Tests: {N passed, M failed}
- [PASS/FAIL] Conventions: {details}

### Findings
- MUST-FIX(merge-block) {finding} — blocks merge
  File: path:line
  Fix: {actionable suggestion}
- SHOULD-FIX(advisory) {finding} — advisory
  File: path:line
  Suggestion: {improvement}
- INFORMATIONAL {finding} — observation
  Note: {context}

ESCALATION_RECOMMENDED: true | false
  {if true: reason — e.g., "edge case beyond QA confidence, recommend
  re-dispatch at scope:sensitive"}

### Evidence
{Command output for each check}
```

### 5.4 `canonical/agents/uat.md` — Qualifier-Aware Findings

**Change inventory:**

| Section | Current behavior | New behavior | Lines affected |
|---------|-----------------|--------------|----------------|
| Report Format | Scenario pass/fail list | MUST-FIX(workflow-breaking) / SHOULD-FIX(user-facing) / INFORMATIONAL(cosmetic) per finding | 38-50 |
| Report ratings | N/A | Add UX_RATING, OUTPUT_QUALITY, WORKFLOW_INTEGRITY | after 50 |

**New report format:**

```
## UAT Acceptance Report

**Scope:** [scenarios run]
**Result:** APPROVED | CONCERNS | REJECTED

### Scenarios
- [PASS/FAIL] {scenario name}: {result}

### Findings
- MUST-FIX(workflow-breaking) {finding}
  Scenario: {which scenario}
  Observed: {what happened}
  Expected: {what should have happened}
- SHOULD-FIX(user-facing) {finding}
  Scenario: {which scenario}
  Observed: {current output}
  Recommendation: {concrete UX improvement}
- INFORMATIONAL(cosmetic) {finding}
  Note: {formatting or wording nit}

### Ratings
UX_RATING: GOOD | ACCEPTABLE | POOR
OUTPUT_QUALITY: GOOD | ACCEPTABLE | POOR
WORKFLOW_INTEGRITY: PASS | FAIL
```

**Verdict status rules (from v2, restored):**
- APPROVED — all scenarios pass, UX GOOD or ACCEPTABLE, no MUST-FIX
- CONCERNS — scenarios pass but SHOULD-FIX(user-facing) findings exist
- REJECTED — any scenario fails, MUST-FIX(workflow-breaking), or POOR ratings

### 5.5 `canonical/commands/r-plan.md` — Simplified Phase Metadata

**Change inventory:**

| Section | Current behavior | New behavior | Lines affected |
|---------|-----------------|--------------|----------------|
| Section 2.3 "Tag Each Phase" | Risk (3 levels), Type (6 values), Gates (derivation table) | Mode only — risk/type/gates removed entirely | 232-261 |
| Section 2.6 "Phase Format" | 7 metadata fields | 4 metadata fields (Mode, Accept, Test, Edge cases) | 304-347 |
| Plan Quality Standard item 8 | "Every phase has all 7 metadata fields" | "Every phase has all 4 metadata fields" | 472 |
| Section 2.2 guideline | N/A | Add note: "The dispatcher auto-classifies scope — no risk/type tagging needed" | after 229 |
| Reviewer dispatch checklist item 3 | "Every phase has all 7 metadata fields?" | "Every phase has all 4 metadata fields?" | 382 |

**Section 2.3 replacement (entire section):**

```
### 2.3 Tag Each Phase

For each phase, provide orchestration metadata:

**Execution mode** (how the dispatcher runs it):
- `[serial-context]` — 1 file, simple change, stays in main session
- `[serial-agent]` — 2-5 files or files with dependencies, one subagent
- `[parallel-agent]` — 6+ independent files, parallel subagents

The dispatcher automatically classifies change scope and selects
quality gates based on the phase's file list, description, and
governance context. No risk, type, or gate tagging is needed in the
plan — the dispatcher derives these at execution time.
```

**Section 2.6 phase format replacement:**

```
- **Mode**: {serial-context | serial-agent | parallel-agent}
- **Accept**: {acceptance criteria — concrete, testable, pass/fail}
- **Test**: {test file + test names, or verification commands with expected output}
- **Edge cases**: {spec edge cases covered by this phase, or "none"}
```

**Plan Quality Standard update (items 8, 13 unchanged, item 8 updated):**

```
8. Every phase has all 4 metadata fields (Mode, Accept, Test, Edge cases)
```

### 5.6 `canonical/commands/r-build.md` — Simplified Dispatch Payload

**Change inventory:**

| Section | Current behavior | New behavior | Lines affected |
|---------|-----------------|--------------|----------------|
| Section 5 dispatch payload | Includes RISK and TYPE fields | Removes RISK and TYPE; dispatcher derives scope from FILE list and DESCRIPTION | 67-87 |
| Section 4 governance loading | Conditional on risk:high or type:security | Always load anti-patterns.md and constraints.md (dispatcher needs them for scope derivation) | 56-61 |

**New dispatch payload:**

```
PHASE: <N>
DESCRIPTION: <phase description from PLAN.md>
MODE: <execution mode tag: serial-context | serial-agent | parallel-agent>
FILES: <file list from PLAN.md>
ACCEPT: <acceptance criteria from PLAN.md>
PLAN_PHASE_COUNT: <total phases in PLAN.md>

GOVERNANCE:
  index: .rdf/governance/index.md
  conventions: .rdf/governance/conventions.md
  constraints: .rdf/governance/constraints.md
  verification: .rdf/governance/verification.md
  anti-patterns: .rdf/governance/anti-patterns.md
  architecture: .rdf/governance/architecture.md

OPERATIONAL_MODE: <mode or "development">
PROJECT_ROOT: <absolute path to project root>
```

Note: RISK and TYPE removed. The dispatcher reads FILES and DESCRIPTION
to derive scope classification internally. Governance files always
loaded (dispatcher needs constraints.md and anti-patterns.md for scope
derivation of cross-cutting and sensitive classifications).

### 5.7 `canonical/commands/r-vpe.md` — VPE Pipeline Orchestrator (NEW)

**Function inventory:**

| Section | Purpose | Dependencies |
|---------|---------|--------------|
| Invocation | Parse args (outcome text, --resume) | None |
| Task List Protocol | Create tasks for full pipeline | TaskCreate |
| Intake Protocol | Adaptive conversation, prompt improvement | User interaction |
| Pipeline Orchestration | Invoke spec→plan→build→ship with approval gates | /r:spec, /r:plan, /r:build, /r:ship |
| Crash Recovery | Read/write vpe-progress.md | .rdf/work-output/ |
| Completion | Final status report | None |

**Full command specification:**

```
# /r:vpe — Pipeline Orchestrator

Optional end-to-end pipeline orchestrator. Takes outcome-oriented
conversation from the user and manages the full
spec → plan → build → ship workflow.

This command is purely additive. It calls existing pipeline commands
unchanged. Users who prefer manual control can continue using
/r:spec, /r:plan, /r:build, and /r:ship independently.

## Invocation

/r:vpe                — start new pipeline from conversation
/r:vpe --resume       — resume interrupted pipeline from state file

## Task List Protocol

At command startup, create tasks for the full pipeline:

TaskCreate: "Intake: understand outcome and scope"
  activeForm: "Understanding desired outcome"
TaskCreate: "Design: brainstorm and write spec"
  activeForm: "Designing solution"
TaskCreate: "Plan: decompose spec into phases"
  activeForm: "Planning implementation"
TaskCreate: "Build: execute implementation phases"
  activeForm: "Building"
TaskCreate: "Ship: release workflow"
  activeForm: "Shipping"

## Resume Protocol

If --resume is specified or .rdf/work-output/vpe-progress.md exists:

1. Read the state file
2. Determine pipeline stage reached
3. Present resume state:
   "Resuming pipeline for: {topic}
    Stage: {intake|spec|plan|build|ship}
    Progress: {stage-specific detail}
    Continue? [Y/start fresh]"
4. If continuing: skip completed stages, resume current stage
   (delegate to the appropriate command's own resume mechanism)

## Stage 1: Intake

Mark task "Intake" as in_progress.

### Adaptive Conversation

Read the user's input. Assess clarity:

**Clear input** (actionable problem statement with scope):
  Restate as structured problem statement. Ask for confirmation.
  1 exchange.

**Partially clear** (has direction but missing scope or motivation):
  Ask 1-2 targeted questions:
  - "What's driving this?" (if motivation unclear)
  - "What does success look like?" (if acceptance unclear)
  Then synthesize. 2-3 exchanges.

**Vague input** (general dissatisfaction or broad goal):
  Ask up to 3 questions:
  - "What specific friction are you experiencing?"
  - "What's driving this change now?"
  - "What would success look like?"
  Then synthesize. 3-4 exchanges.

**Max 4 exchanges before synthesizing.** Do not let intake become
an unbounded conversation.

### Problem Statement Synthesis

After intake, present:

"Here's what I understand:

**Problem:** {1-2 sentences describing the current state}
**Goal:** {1-2 sentences describing desired outcome}
**Scope:** {what's in, what's explicitly out}
**Success:** {how to verify it's done}

Ready to design? [Y/adjust]"

Wait for user confirmation.

Write state:
  .rdf/work-output/vpe-progress.md:
    TOPIC: {topic}
    STAGE: intake
    STATUS: complete
    PROBLEM: {problem statement}
    GOAL: {goal}
    SCOPE: {scope}

Mark task "Intake" as completed.

## Stage 2: Design (invokes /r:spec)

Mark task "Design" as in_progress.

Before invoking /r:spec, check docs/specs/ for existing specs. If a
recent spec exists and matches the intake topic, present:
  "Found existing spec: {path}. Use this? [Y/new spec]"
If Y, skip to Stage 3 (Plan).

Otherwise, invoke /r:spec with the synthesized problem statement as
the seed input. The user participates in brainstorming and design
questions as normal — VPE does not suppress or shortcut the /r:spec
workflow.

VPE's role during spec:
- Ensure the problem statement from intake is the starting context
- Let /r:spec handle all brainstorming, research, and spec writing
- After /r:spec completes, read the committed spec path

After spec is committed:

"Spec complete: {spec path}
 Ready to plan the implementation? [Y/pause]"

If user says pause: write state and stop (user can resume with
/r:vpe --resume).

Write state:
  STAGE: spec
  STATUS: complete
  SPEC_PATH: {path}

Mark task "Design" as completed.

## Stage 3: Plan (invokes /r:plan)

Mark task "Plan" as in_progress.

Invoke /r:plan with the spec path. The user approves the plan as
normal — VPE does not suppress the /r:plan workflow.

After plan is committed:

"Plan ready: PLAN.md ({N} phases)
 Ready to build? [Y/pause/build-specific-phase]"

Write state:
  STAGE: plan
  STATUS: complete
  PLAN_PHASES: {N}

Mark task "Plan" as completed.

## Stage 4: Build (invokes /r:build per phase)

Mark task "Build" as in_progress.

For each pending phase in PLAN.md:

1. Invoke /r:build {N}
2. Read the result (PASS or FAIL)
3. If PASS and more phases remain:
   "Phase {N} complete. Continuing to Phase {N+1}..."
   (auto-continue — no approval gate between build phases)
4. If FAIL:
   "Phase {N} failed: {failure context}
    [retry / skip / pause]"
   Wait for user decision.
5. After all phases complete:
   "All {N} phases complete. End-of-plan review: {verdict}.
    Ready to ship? [Y/pause]"

Write state after each phase:
  STAGE: build
  STATUS: in-progress
  CURRENT_PHASE: {N}
  COMPLETED_PHASES: [1, 2, ...]

Mark task "Build" as completed when all phases pass.

## Stage 5: Ship (invokes /r:ship)

Mark task "Ship" as in_progress.

Invoke /r:ship. The user confirms the PR as normal — VPE does not
suppress the /r:ship workflow.

After ship completes:

"> **Pipeline complete** — {project} shipped.
>  Spec: {spec_path}
>  Plan: PLAN.md ({N} phases)
>  Ship: {PR URL}"

Write state:
  STAGE: ship
  STATUS: complete

Mark task "Ship" as completed.

Clean up: vpe-progress.md retained for session log reference.

## Constraints

- Never modify existing pipeline commands — call them as-is
- Never suppress user interaction within pipeline commands
- Never skip approval gates (spec approval, plan approval, ship confirmation)
- Auto-continue between build phases only (phases are already approved
  as a batch when the plan was approved)
- Max 4 exchanges during intake — escalate to /r:spec if more exploration needed
- Track state in vpe-progress.md for crash recovery at every stage transition
```

### 5.8 `canonical/reference/framework.md` — Scope Classification Summary

**Change inventory:**

| Section | Current behavior | New behavior | Lines affected |
|---------|-----------------|--------------|----------------|
| Gate selection paragraph | "dispatcher auto-scales sentinel depth" | Replace with scope classification summary | 163-172 |

**New gate selection block:**

```
**Verification depth** is managed by the dispatcher. It classifies each
phase by change scope, derived automatically from the file list,
description, and governance context:

  docs          — changelog, README, comments
  focused       — single file, config, one function
  multi-file    — 2+ files, standard feature/refactor work
  cross-cutting — install, CLI, cross-OS, breaking changes
  sensitive     — security, shared libs, data migration

Higher scope = more verification. The dispatcher manages this
automatically. See dispatcher.md for the full derivation logic.
```

### 5.9 `canonical/commands/r-start.md` — VPE In-Flight Detection

**Change inventory:**

| Section | Current behavior | New behavior | Lines affected |
|---------|-----------------|--------------|----------------|
| In-flight signals | Detects spec-progress.md, PLAN.md, ship-progress.md | Add vpe-progress.md detection | Section 3 rendering |

**New in-flight signal:**

```
- vpe-progress.md exists → signal: "VPE pipeline: {stage} — {status}"
```

### 5.10 `canonical/commands/r-status.md` — VPE Pipeline Stage

**Change inventory:**

| Section | Current behavior | New behavior | Lines affected |
|---------|-----------------|--------------|----------------|
| Pipeline table | Shows spec/plan/build/ship stages | Add VPE row if vpe-progress.md exists | Pipeline section |

**New pipeline entry (conditional):**

```
| **VPE** | *managing* | Stage: {current stage} |
```

Only shown when vpe-progress.md exists. When VPE is not in use, the
pipeline table is unchanged.

### 5.11 `reference/diagrams.md` — Quality Gates Diagram Update

**Change inventory:**

| Section | Current behavior | New behavior | Lines affected |
|---------|-----------------|--------------|----------------|
| Section 4: Quality Gates | Phase-tag selection matrix (risk×type) | Scope classification flowchart | 180-226 |

Replace the tag-based decision tree with scope-based:

```
Phase Content → Scope Classification → Gate Selection
  file count       scope:docs          G1
  path patterns    scope:focused       G1+G2
  description      scope:multi-file    G1+G2+G3-lite
  governance       scope:cross-cutting G1+G2+G3-full
  signals          scope:sensitive     G1+G2+G3-full
                   + CLI/help files?   +G4
```

### 5.12 `canonical/commands/r-review.md` — Qualifier-Aware Labels

**Change inventory:**

| Section | Current behavior | New behavior | Lines affected |
|---------|-----------------|--------------|----------------|
| Sentinel dispatch payload example | Uses `MUST-FIX \| CONCERN` in report format description | Update to `MUST-FIX(fix-or-refute) \| SHOULD-FIX(pass:<name>)` | ~104-107 |
| Challenge dispatch payload example | Uses `BLOCKING / CONCERN / SUGGESTION` | Update to `MUST-FIX(blocking-concern) / SHOULD-FIX(advisory-concern) / INFORMATIONAL(risk-area)` | ~56-60 |

No structural changes to the command protocol. Only the finding label
text in dispatch payload examples and report format descriptions changes
to match the qualifier-aware vocabulary.

### 5.13 `modes/development/context.md` — Stale Reference Update

**Change inventory:**

| Section | Current behavior | New behavior | Lines affected |
|---------|-----------------|--------------|----------------|
| Quality Gate Overrides | "dispatcher reads phase tags from PLAN.md and selects appropriate gates including sentinel depth" | "dispatcher auto-derives scope classification from phase content and selects appropriate gates" | 25-26 |

One-line text replacement. No structural change.

### 5.14 `canonical/reference/session-safety.md` — VPE Recovery Signal

**Change inventory:**

| Section | Current behavior | New behavior | Lines affected |
|---------|-----------------|--------------|----------------|
| Recovery Protocol signals | 8 signals including spec-progress.md, ship-progress.md | Add vpe-progress.md as signal | Recovery section |

**New recovery signal:**

```
- .rdf/work-output/vpe-progress.md → VPE pipeline state, resume with /r:vpe --resume
```

---

## 5b. Examples

### Example 1: VPE full pipeline — outcome to shipped

```
$ /r:vpe

VPE: What outcome are you looking for?

User: I want to add CSV export to our reporting commands

VPE: Clear scope. Here's what I understand:

  Problem: Reporting commands output text only — no machine-readable format.
  Goal: Add CSV export to all reporting commands.
  Scope: CLI output formatting, not data model changes.
  Success: Every reporting command accepts --csv and produces valid CSV.

  Ready to design? [Y/adjust]

User: Y

  [/r:spec runs — user participates in brainstorming normally]
  [spec committed]

VPE: Spec complete: docs/specs/2026-03-21-csv-export-design.md
     Ready to plan the implementation? [Y/pause]

User: Y

  [/r:plan runs — user approves plan]
  [plan committed]

VPE: Plan ready: PLAN.md (4 phases)
     Ready to build? [Y/pause]

User: Y

  Phase 1 complete. Continuing to Phase 2...
  Phase 2 complete. Continuing to Phase 3...
  Phase 3 complete (1 finding resolved). Continuing to Phase 4...
  Phase 4 complete. All 4 phases complete.
  End-of-plan review: PASS.
  Ready to ship? [Y/pause]

User: Y

  [/r:ship runs — user confirms PR]

> **Pipeline complete** — project shipped.
>  Spec: docs/specs/2026-03-21-csv-export-design.md
>  Plan: PLAN.md (4 phases)
>  Ship: https://github.com/rfxn/project/pull/42
```

### Example 2: Dispatcher scope classification — no planner tagging

```
# PLAN.md phase (new simplified format):

### Phase 3: Add CSV formatter to report engine

Add csv_format() function to lib/report.sh and integrate with
existing report_generate() function.

**Files:**
- Modify: `lib/report.sh` (add csv_format function)
- Modify: `lib/cmd/report.sh` (add --csv flag handling)
- Create: `tests/report-csv.bats` (CSV output tests)

- **Mode**: serial-agent
- **Accept**: `bfd --report --csv | python3 -c "import csv,sys; csv.reader(sys.stdin)"` exits 0
- **Test**: tests/report-csv.bats: @test "csv output valid", @test "csv headers match text columns"
- **Edge cases**: empty report (0 rows), special characters in IP fields

# Dispatcher derives (internally, not in plan):
#   scope:multi-file (3 files, no install/security paths)
#   Gates: G1 + G2 + G3-lite
```

### Example 3: Qualifier-routed finding resolution

```
# Dispatcher receives findings from parallel QA + sentinel:

QA finding:
  MUST-FIX(merge-block) | bash -n fails on lib/report.sh line 42
  → Dispatcher routes to engineer: "Fix syntax error"

Sentinel finding:
  MUST-FIX(fix-or-refute) | csv_format() does not escape commas in IP fields
  → Dispatcher routes to engineer: "Fix or refute with evidence"

UAT finding:
  SHOULD-FIX(user-facing) | --csv flag not shown in -h output
  → Dispatcher collects for phase-end advisory: "1 UX concern"

Engineer fixes syntax error (QA finding resolved).
Engineer refutes sentinel finding: "IPv4/IPv6 addresses cannot contain
  commas — field content is validated by valid_ip() at line 31."
Dispatcher evaluates: cites specific function, explains why, addresses
  the concern. All 3 checks pass → accept refutation.

Developer sees:
  "Phase 3: PASS (2 findings resolved). 1 advisory concern."
```

### Example 4: VPE crash recovery

```
$ /r:vpe --resume

Resuming pipeline for: CSV export for reporting commands
Stage: build
Progress: Phases 1-2 complete, Phase 3 pending

Continue? [Y/start fresh]

User: Y

  Phase 3 complete. Continuing to Phase 4...
  [pipeline continues normally]
```

---

## 6. Conventions

### Developer-Facing Surface (4 concepts)

After this change, the developer interacts with the gate system through
exactly 4 concepts:

1. **PASS** — phase completed, all gates passed (findings resolved internally)
2. **MUST-FIX** — finding that the dispatcher could not resolve, needs human judgment (qualifier tells you the type)
3. **SHOULD-FIX** — advisory finding, non-blocking (qualifier tells you the domain)
4. **Phase status file** — `.rdf/work-output/phase-N-status.md` for post-hoc detail

The scope classification (docs/focused/multi-file/cross-cutting/sensitive)
is visible in framework.md for transparency but requires no developer action.

The VPE is optional — developers who prefer the 4-command pipeline see
no changes.

### Qualifier Vocabulary (dispatcher-internal routing)

| Agent | MUST-FIX qualifier | SHOULD-FIX qualifier | Special signals |
|-------|-------------------|---------------------|-----------------|
| QA | `(merge-block)` | `(advisory)` | `ESCALATION_RECOMMENDED` |
| Sentinel | `(fix-or-refute)` | `(pass:<name>)` | — |
| UAT | `(workflow-breaking)` | `(user-facing)` | — |
| Challenger | `(blocking-concern)` | `(advisory-concern)` | `VERIFIED_SOUND` |

Qualifiers are written by agents in their reports. The dispatcher reads
qualifiers to route findings. Developers see qualifiers in finding
descriptions when findings are escalated — the qualifier provides
context about what kind of action is needed.

### Scope Classification (dispatcher-internal derivation)

| Scope | Signal | Gates | Sentinel depth |
|-------|--------|-------|---------------|
| `docs` | All files are docs/changelog/comments | G1 | none |
| `focused` | 1 file, config, single function | G1+G2 | none |
| `multi-file` | 2+ source files, standard work | G1+G2+G3 | lite (2-pass) |
| `cross-cutting` | Install, CLI, cross-OS, breaking | G1+G2+G3 | full (4-pass) |
| `sensitive` | Security, shared libs, data migration | G1+G2+G3 | full (4-pass) |

User-facing modifier: +G4 (UAT) if CLI entry points or help text in file list.

---

## 7. Interface Contracts

### Dispatch Payload Changes

The `/r:build` dispatch to the dispatcher removes two fields:

```
Removed:
  RISK: <risk tag>
  TYPE: <type tag>
```

The dispatcher now derives scope classification from the remaining
payload fields (FILES, DESCRIPTION) plus governance context.

### Plan Metadata Changes

Phase metadata in PLAN.md changes from 7 fields to 4:

```
Removed:
  - **Risk**: {low | medium | high}
  - **Type**: {config | feature | refactor | ...}
  - **Gates**: {G1 | G1+G2 | ...}
```

### Finding Report Format Changes

All agent reports add qualifier syntax to severity labels:

```
Before: MUST-FIX | {finding description}
After:  MUST-FIX(qualifier) | {finding description}
```

The qualifier is parenthesized immediately after the severity keyword
with no space. This is a backward-compatible extension — parsers that
ignore the parenthetical still read the severity correctly.

### Status File Schema Update

`phase-N-status.md` adds a scope field:

```
SCOPE_CLASSIFICATION: docs | focused | multi-file | cross-cutting | sensitive
```

### New State File

`vpe-progress.md` (written by /r:vpe, read by /r:start and /r:vpe --resume):

```
TOPIC: {topic}
STAGE: intake | spec | plan | build | ship
STATUS: in-progress | complete
PROBLEM: {problem statement from intake}
GOAL: {goal}
SCOPE: {scope boundaries}
SPEC_PATH: {path, if spec written}
PLAN_PHASES: {count, if plan written}
CURRENT_PHASE: {N, if building}
COMPLETED_PHASES: 1,2,3 (comma-separated integers, no spaces)
```

---

## 8. Migration Safety

### Backward Compatibility

- Plans written before this change (with Risk/Type/Gates fields) continue
  to work — the dispatcher ignores unrecognized fields and derives scope
  from content as normal
- Finding reports without qualifiers continue to work — the dispatcher
  treats bare MUST-FIX as MUST-FIX(merge-block) by default
- Existing /r:ship and /r:audit dispatch prompts continue to work
  unchanged — they don't use Risk/Type fields

### Upgrade Path

- No data migration needed — these are agent/command definition changes
- `rdf generate claude-code` regenerates all deployed files from
  canonical sources
- No governance schema changes
- Plans in progress: the dispatcher handles both old-format (with
  Risk/Type/Gates) and new-format (without) plans transparently

### Rollback

Revert the canonical commits and run `rdf generate claude-code`.
Old-format plans (with Risk/Type/Gates) continue to work. No data
migration to undo. Finding reports without qualifiers are handled
by the default routing (bare MUST-FIX → merge-block).

### Test Suite Impact

- No BATS tests affected — RDF tests are manual verification +
  shellcheck + frontmatter-free checks
- Verification: `rdf generate claude-code` produces valid output, diff
  against expected, grep for stale references

---

## 9. Dead Code and Cleanup

| Finding | File | Action |
|---------|------|--------|
| Gate derivation table in r-plan.md Section 2.3 | canonical/commands/r-plan.md | Remove — replaced by scope classification in dispatcher |
| Risk/Type/Gates metadata fields in phase format | canonical/commands/r-plan.md Section 2.6 | Remove |
| RISK and TYPE fields in r-build dispatch payload | canonical/commands/r-build.md | Remove |
| "risk:high or type:security" conditional governance loading | canonical/commands/r-build.md Section 4 | Remove — always load all governance (dispatcher needs it for scope derivation) |
| Plan Quality Standard item referencing "7 metadata fields" | canonical/commands/r-plan.md | Update to "4 metadata fields" |
| Reviewer challenge report BLOCKING/CONCERN/SUGGESTION labels | canonical/agents/reviewer.md | Replace with qualifier-aware labels |
| CONCERN severity (v3 rename from SHOULD-FIX) | canonical/agents/reviewer.md, dispatcher.md | Revert to SHOULD-FIX (v2 alignment, shared severity spine) |

---

## 10a. Test Strategy

| Goal | Test method | Verification |
|------|-------------|--------------|
| Goal 1: Plan metadata reduced to 4 fields | Read r-plan.md | Grep for `Risk` and `Type` and `Gates` in metadata sections — expect 0 |
| Goal 2: Dispatcher scope classification | Read dispatcher.md | Grep for `scope:docs` through `scope:sensitive` — expect 5 levels |
| Goal 3: Scope naming | Read dispatcher.md + framework.md | Grep for `scope:` prefix in both files |
| Goal 4: Qualifier-aware findings | Read all 4 agent files | Grep for qualifier syntax `(merge-block)`, `(fix-or-refute)`, etc. |
| Goal 5: VPE command exists | Read r-vpe.md | File exists, contains Pipeline Orchestrator header |
| Goal 6: VPE is additive | Read r-spec.md, r-plan.md, r-build.md, r-ship.md | Grep for `vpe` — expect 0 hits in all 4 files |
| Goal 7: Existing commands unchanged | Diff r-spec.md, r-ship.md | No changes to these files |
| Goal 8: Agent count unchanged | Count files in canonical/agents/ | Expect 6 |

## 10b. Verification Commands

```bash
# Goal 1: Plan metadata reduced — no Risk/Type/Gates in phase format
grep -c '^\- \*\*Risk\*\*' canonical/commands/r-plan.md
# expect: 0
grep -c '^\- \*\*Type\*\*' canonical/commands/r-plan.md
# expect: 0
grep -c '^\- \*\*Gates\*\*' canonical/commands/r-plan.md
# expect: 0

# Goal 2: Scope classification in dispatcher
grep -c 'scope:docs\|scope:focused\|scope:multi-file\|scope:cross-cutting\|scope:sensitive' canonical/agents/dispatcher.md
# expect: >= 5

# Goal 3: Framework.md has scope summary with labeled levels
grep -c 'docs\b.*changelog\|focused\b.*single\|multi-file\b.*2+\|cross-cutting\b.*install\|sensitive\b.*security' canonical/reference/framework.md
# expect: >= 5

# Goal 4: Qualifier syntax in agent files
grep -c 'merge-block\|fix-or-refute' canonical/agents/qa.md canonical/agents/reviewer.md
# expect: >= 1 per file
grep -c 'workflow-breaking\|user-facing' canonical/agents/uat.md
# expect: >= 2
grep -c 'blocking-concern\|advisory-concern' canonical/agents/reviewer.md
# expect: >= 2

# Goal 5: VPE command exists
test -f canonical/commands/r-vpe.md && echo "exists"
# expect: exists
head -1 canonical/commands/r-vpe.md
# expect: "# /r:vpe — Pipeline Orchestrator"

# Goal 6: VPE is additive — no VPE references in existing pipeline commands
grep -ci 'vpe' canonical/commands/r-spec.md canonical/commands/r-plan.md canonical/commands/r-build.md canonical/commands/r-ship.md
# expect: 0 for each file

# Goal 7: r-spec.md and r-ship.md unchanged
# (verified by diff during implementation — no structural changes)

# Goal 8: Agent count unchanged
ls canonical/agents/*.md | wc -l
# expect: 6

# Cross-reference: no stale gate derivation table
grep -c 'risk:low.*Gate 1\|risk:medium.*Gates 1\|risk:high.*Gates 1' canonical/commands/r-plan.md
# expect: 0

# Cross-reference: RISK and TYPE removed from build dispatch
grep -c '^RISK:\|^TYPE:' canonical/commands/r-build.md
# expect: 0

# rdf generate produces valid output
bash bin/rdf generate claude-code 2>&1 | tail -3
# expect: success message, no errors
```

---

## 11. Risks

1. **Scope mis-classification on ambiguous phases.** A phase described as
   "update config" that actually modifies security-critical config could be
   classified as scope:focused instead of scope:sensitive. *Mitigation:*
   The dispatcher reads governance/constraints.md and anti-patterns.md for
   path-based signals. If a config file is flagged as security-sensitive in
   governance, the dispatcher elevates scope. Additionally, QA's
   ESCALATION_RECOMMENDED signal triggers re-classification.

2. **Qualifier syntax breaks existing parsers.** Any tool that parses
   finding reports by matching `MUST-FIX` literally will still work —
   `MUST-FIX(qualifier)` starts with `MUST-FIX`. But tools matching
   `^MUST-FIX$` exactly will break. *Mitigation:* No external tools parse
   RDF finding reports. The only consumers are the dispatcher and
   developer reading text. The parenthetical is human-readable context.

3. **VPE context window pressure.** The VPE runs in main context across
   the full pipeline. A multi-phase build could accumulate significant
   context. *Mitigation:* Build phases execute as dispatcher subagents
   (isolated context windows). The VPE only sees the build result summary,
   not the full execution trace. Compaction between stages is expected
   and handled — VPE reads state from vpe-progress.md after compaction.

4. **VPE intake conversation drifts.** Adaptive intake (1-4 exchanges)
   could drift into extended design discussion before /r:spec.
   *Mitigation:* Hard ceiling of 4 exchanges. If more exploration needed,
   VPE hands off to /r:spec immediately — /r:spec's brainstorm phase
   is designed for extended exploration.

5. **Backward compatibility gap during transition.** Plans written with
   old-format metadata (Risk/Type/Gates) coexist with new-format plans.
   *Mitigation:* Dispatcher ignores unrecognized fields. Old plans with
   Risk/Type still work — dispatcher derives scope from content regardless.
   New plans without Risk/Type work — dispatcher derives scope as designed.

---

## 11b. Edge Cases

| Scenario | Expected behavior | Handling |
|----------|-------------------|---------|
| Plan has old-format metadata (Risk/Type/Gates) | Dispatcher derives scope from content, ignores old fields | Backward compatible — old fields are harmless extras |
| Phase description says "security" but files are docs-only | scope:docs wins — file list is the primary signal, not keywords | File-based classification takes precedence over description keywords |
| Finding report has bare MUST-FIX (no qualifier) | Dispatcher treats as MUST-FIX(merge-block) — default routing | Backward compatible with pre-qualifier reports |
| VPE session crashes during build Phase 3 of 6 | vpe-progress.md records STAGE:build, CURRENT_PHASE:3 | /r:vpe --resume reads state, invokes /r:build 3 (build's own resume detects in-progress phase) |
| VPE invoked but user wants to skip spec (already has one) | VPE detects existing spec in docs/specs/, asks "Use existing spec?" | Adaptive — VPE reads existing artifacts before starting pipeline |
| /r:vpe and /r:spec both invoked in same session | Both write to work-output/ — no conflict (different state files) | VPE writes vpe-progress.md, spec writes spec-progress.md |
| Dispatcher cannot determine scope (no file list, no description) | Default to scope:multi-file | Safe default — gets QA + sentinel-lite (the common case) |
| QA sends ESCALATION_RECOMMENDED on scope:focused phase | Dispatcher re-derives at scope:cross-cutting, re-dispatches affected gates | Escalation path allows QA to trigger richer verification |
| UAT finding MUST-FIX(workflow-breaking) on a non-user-facing phase | Dispatcher routes to engineer for fix (same as any MUST-FIX) | Qualifier indicates the action type, not the phase classification |
| User runs /r:build directly (no VPE) on a plan without Risk/Type | Dispatcher derives scope from content — works identically | VPE is optional, existing commands work unchanged |
| VPE intake conversation — user input is already a full spec | VPE recognizes structured input, confirms "This looks like a spec. Proceed directly to planning?" | Adaptive intake detects when exploration is unnecessary |

---

## 12. Open Questions

None. All design decisions were resolved during brainstorming:
- Q1: Shared severity spine + agent-scoped qualifiers (Option B)
- Q2: Remove Risk/Type/Gates from planner — 4 metadata fields remain (Option A)
- Q3: VPE conversational intake → pipeline automation with approval gates (Option A)
- Q4: VPE as skill for interactive phases, delegates build via /r:build (Option B)
- Q5: VPE purely additive — zero changes to existing commands (Option A)
- Q6: v2 tier classification with scope: naming (Option B)
- Q7: Adaptive intake conversation, 1-4 exchanges (Option B)
- Q8: VPE command only, no agent file, agent count stays at 6 (Option A)
- Q9: Framework.md gets summary, dispatcher has full logic (Option B)
