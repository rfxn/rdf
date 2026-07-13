# Design: Sentinel Integration & Quality Gate Redesign

**Date:** 2026-03-20
**Author:** Ryan MacDonald / Claude
**Status:** Reviewed (v2)
**Project:** RDF (rfxn Development Framework)

---

## 1. Problem Statement

The RDF 3.0 quality gate system has degraded from what RDF 2.x provided.
Four specific regressions:

**Gate coverage regression.** The dispatcher's gate selection matrix makes
sentinel review conditional — only `risk:high` or `type:security` phases
trigger Gate 3. The default for untagged phases is Gates 1 + 2 (engineer
self-report + QA). This means the majority of implementation phases —
ordinary feature work at medium risk — receive zero adversarial code
review. The parent CLAUDE.md states: "Adversarial Inputs Are Required
Before Merge — at minimum one adversarial challenge must occur per tier
2+ change." The current gate matrix violates this governance principle.

Evidence: In the 8-phase profile/mode expansion plan (2026-03-20), zero
phases were tagged `risk:high`. All received Gates 1 + 2 only. The
sentinel review that caught cross-cutting issues (stale references,
governance doc inaccuracy, anti-slop in 5 files) was run manually as an
afterthought, not triggered by the gate system.

**Counter-hypothesis protocol dropped.** The FP-prevention spec
(2026-03-18) defined a detailed protocol for `sys-sentinel.md` and
`sys-qa.md`: per-finding hypothesis/counter-hypothesis, 5-check
counter-evidence evaluation, location-specific evidence floor, verdict
weighting, and suppression logging. When these agents were collapsed into
the universal `reviewer.md` (84 lines covering both challenge and
sentinel modes), the entire protocol was dropped. The reviewer contains
zero references to counter-hypothesis, suppression logging,
false-positives.md, or any FP prevention mechanism.

Evidence: The FP-prevention spec was motivated by measured data — 14 FPs
from tlog_lib in a single audit cycle, 37% FP rate on BFD test dedup,
phantom function findings in APF from name-only matching.

**Orchestration intelligence lost.** The RDF 2.x `mgr` agent had FP
calibration: flag discard-exceeds-report anomalies, resolve Sentinel/QA
disagreements, detect zero-finding anomalies on tier 2+ changes. The 3.0
dispatcher has none of this — it treats gate results as simple pass/fail.

Additionally, there is no end-of-plan sentinel review. Each phase passes
gates independently. Cross-phase regressions — where phase 3 introduces
a pattern that conflicts with phase 7's change — are invisible at the
phase level.

**Orchestrator ownership inverted.** In RDF 2.x, the mgr owned gate
selection and finding resolution — the developer saw pass/fail outcomes,
not gate machinery. In RDF 3.0, gate selection became tag-driven (the
developer must tag phases correctly) and finding resolution has no
automated loop (findings surface directly to the user).

Competitive analysis of 14 frameworks (GSD, Copilot, Cursor, Aider,
CrewAI, LangGraph, BMAD, ASDLC.io, etc.) confirms the industry
pattern: developers should not think about gates. Gates are either
invisible (Aider, Copilot), human-approval-based (OpenAgentsControl),
or CI-pipeline-shaped (GSD). No framework uses a tag-driven gate
selection matrix. The ASDLC.io taxonomy names two gate types —
deterministic (lint/test) and adversarial (semantic review) — and both
are orchestrator-managed, not developer-managed.

RDF's differentiator is adversarial review + FP prevention — no other
framework combines both. But the developer surface must return to
RDF 2.x simplicity: the dispatcher owns the machinery, the developer
sees TDD-shaped outcomes (pass/fail/findings).

### Metrics

| Metric | Current | Target |
|--------|---------|--------|
| Phases receiving sentinel review | ~15% (risk:high only) | ~85% (all non-trivial) |
| FP prevention protocol coverage | 0 lines in reviewer.md | ~40 lines structural protocol |
| Dispatcher calibration checks | 0 | 3 (zero-finding, discard ratio, disagreement) |
| End-of-plan holistic sentinel | none | mandatory for 3+ phase plans |
| QA/sentinel execution model | sequential | parallel with dedup |
| Developer-facing gate concepts | ~15 (tag matrix, depth tiers) | ~6 (pass/fail + finding severities) |
| Finding resolution ownership | developer | dispatcher (escalate only unresolved) |

---

## 2. Goals

1. Dispatcher automatically runs sentinel on all non-trivial phases (tiered depth, no developer tagging required)
2. End-of-plan sentinel review is mandatory for plans with 3+ phases
3. QA and sentinel execute in parallel when both are triggered
4. Dispatcher owns finding resolution: fix/refute cycle with engineer, escalate only what it can't resolve
5. Counter-hypothesis protocol is restored in the reviewer's sentinel mode (internal, not developer-facing)
6. Dispatcher performs FP calibration silently (log anomalies, auto-investigate, escalate only confirmed anomalies)
7. Developer sees exactly 3 finding severities: MUST-FIX, CONCERN, SUGGESTION — and only for findings the dispatcher couldn't resolve
8. `/r-review --sentinel` standalone dispatch includes full operational protocol

---

## 3. Non-Goals

- Splitting the reviewer back into separate sentinel/challenger agents
- Changing the challenge mode protocol
- Modifying the engineer or planner agents
- Changing the UAT agent or Gate 4 behavior
- Modifying `/r-spec` or `/r-plan` command behavior
- Adding new governance file types
- Changing the 6-agent architecture
- Exposing gate selection mechanics to the developer

---

## 4. Architecture

### 4.1 File Map

#### Modified Files

| File | Lines (current) | Lines (after) | Changes |
|------|----------------|---------------|---------|
| `canonical/agents/dispatcher.md` | 89 | ~175 | Gate selection matrix, parallel QA+sentinel, end-of-plan sentinel, FP calibration, finding trust model |
| `canonical/agents/reviewer.md` | 84 | ~130 | Counter-hypothesis protocol in sentinel mode, lite sentinel mode definition |
| `canonical/commands/r-review.md` | 124 | ~155 | Enriched sentinel dispatch payload with operational protocol |
| `canonical/commands/r-build.md` | 114 | ~130 | End-of-plan sentinel trigger, updated completion message |
| `canonical/reference/framework.md` | 225 | ~235 | Updated gate selection table |
| `modes/development/context.md` | 54 | ~60 | Updated gate selection table |
| `reference/diagrams.md` | 472 | ~487 | Updated gate selection flowchart (Section 4 only, lines 180-226) |

#### No-Touch Files

| File | Reason |
|------|--------|
| `canonical/agents/engineer.md` | No changes to engineer protocol |
| `canonical/agents/qa.md` | QA protocol unchanged; parallel execution is dispatcher-managed |
| `canonical/agents/uat.md` | No changes to UAT |
| `canonical/agents/planner.md` | No changes to planner |
| `canonical/commands/r-plan.md` | Update Section 2.3 gate derivation table to match new dispatcher matrix |
| `canonical/commands/r-spec.md` | Spec command unchanged |
| `canonical/commands/r-review.md` (Section 6) | Rename SHOULD-FIX to CONCERN in Report Result text (line 101) |
| `reference/diagrams.md` (Section 7) | Rename SHOULD-FIX to CONCERN in Reviewer Modes diagram |
| `canonical/commands/r-ship.md` | Ship already has sentinel dispatch; no changes needed |
| `canonical/commands/r-audit.md` | Audit already dispatches parallel reviewers; no changes needed |

### 4.2 Size Comparison

| Component | Before | After | Delta |
|-----------|--------|-------|-------|
| dispatcher.md | 89 lines | ~175 lines | +86 |
| reviewer.md | 84 lines | ~135 lines | +51 |
| r-review.md | 124 lines | ~150 lines | +26 |
| r-build.md | 114 lines | ~130 lines | +16 |
| framework.md | 225 lines | ~235 lines | +10 |
| development/context.md | 54 lines | ~60 lines | +6 |
| diagrams.md (Section 4) | 472 lines | ~487 lines | +15 |
| **Total delta** | | | **+210** |

### 4.3 Dependency Tree

```
r-build.md (command)
  └── dispatches rdf-dispatcher (subagent)
        ├── reads PLAN.md (phase tags → gate selection)
        ├── dispatches rdf-engineer (subagent)
        ├── dispatches rdf-qa (subagent)         ─┐
        ├── dispatches rdf-reviewer (subagent)    │ parallel when both triggered
        │     └── reads governance/* (JIT)        ─┘
        ├── deduplicates QA+reviewer findings
        ├── runs FP calibration checks
        ├── dispatches engineer for finding resolution
        └── [NEW] end-of-plan sentinel (if 3+ phases)
              └── dispatches rdf-reviewer (full 4-pass on cumulative diff)

r-review.md (command, standalone)
  └── dispatches rdf-reviewer (subagent)
        └── reads governance/* (JIT)

r-ship.md (command)
  ├── dispatches rdf-qa (subagent)         ─┐
  └── dispatches rdf-reviewer (subagent)    │ already parallel
                                           ─┘

r-audit.md (command)
  └── dispatches 3x rdf-reviewer + 1x rdf-qa (already parallel)
```

### 4.4 Key Changes

**Design principle: dispatcher owns the gate machinery.** The developer
sees TDD-shaped outcomes — pass/fail per phase, with findings when human
judgment is needed. All gate selection, depth scaling, FP prevention,
calibration, and finding resolution are dispatcher-internal. This
restores the RDF 2.x model (mgr decides) updated for 3.0's universal
agents.

**1. Dispatcher auto-scales sentinel depth** — the dispatcher decides
lite (2-pass: anti-slop + regression) vs full (4-pass) based on phase
tags from the planner. Tags are planner hints to the dispatcher, not
developer responsibilities. If no tags, the dispatcher defaults to lite.

**2. Parallel QA+sentinel** — when both gates fire, the dispatcher
spawns them simultaneously and deduplicates findings internally by
file:line proximity. Disagreements are resolved by the dispatcher
(escalated to the user only if genuinely ambiguous).

**3. End-of-plan sentinel** — after the last phase of a 3+ phase plan,
the dispatcher automatically runs a full 4-pass sentinel on the
cumulative diff. This catches cross-cutting regressions that per-phase
reviews structurally cannot see.

**4. Counter-hypothesis restored (reviewer-internal)** — the reviewer's
sentinel mode carries the structural FP prevention protocol (~40 lines).
Findings that survive counter-hypothesis are reported. Discarded findings
are logged in the internal suppression log. The developer sees cleaner
findings, not the machinery that produced them.

**5. Dispatcher owns finding resolution** — MUST-FIX findings go to the
engineer for fix/refute cycles (max 3). The dispatcher evaluates
refutations and re-verifies fixes. Only findings the dispatcher cannot
resolve reach the developer. CONCERNs are collected and presented as
advisory at phase end. SUGGESTIONs are logged only.

**6. FP calibration is dispatcher-internal** — three heuristic checks
(zero-finding on large diffs, discard ratio anomaly, QA/sentinel
disagreement). When anomalies are detected, the dispatcher
auto-investigates (e.g., re-dispatches at full depth). Only confirmed
anomalies that the dispatcher cannot resolve are escalated to the user.

### 4.5 Dependency Rules

- Dispatcher changes must not alter the commit strategy or parallel
  failure semantics
- Reviewer changes must not affect challenge mode behavior
- Gate selection changes must propagate to all documentation surfaces
  (dispatcher, framework.md, modes/development/context.md, diagrams.md)
- The 3-phase threshold for end-of-plan sentinel is a dispatcher
  constant, not configurable per plan

---

## 5. File Contents

### 5.1 `canonical/agents/dispatcher.md` — Dispatcher Intelligence

**Change inventory:**

| Section | Current behavior | New behavior | Lines affected |
|---------|-----------------|--------------|----------------|
| Gate 3 description | "Conditional: risk:high or type:security" | "Tiered: dispatcher auto-selects lite or full" | 48-50 |
| Gate Selection matrix | 6 entries, sentinel on 2 | 8 entries, sentinel on all non-trivial (dispatcher-internal) | 56-64 |
| (new) Parallel Gate Execution | N/A | QA+sentinel parallel dispatch, dedup protocol | new section after line 64 |
| (new) End-of-Plan Sentinel | N/A | 3+ phase threshold, full 4-pass on cumulative diff | new section after Red/Green |
| (new) FP Calibration | N/A | 3 silent heuristic checks with auto-investigation | new section after Red/Green |
| (new) Finding Resolution | N/A | Dispatcher-owned fix/refute cycle, escalation protocol | new section after FP Calibration |

**New Gate Definitions:**

```
Gate 1 — Engineer self-report:
  TDD evidence: test names, red/green output, coverage delta

Gate 2 — QA verification (deterministic gate):
  Reads governance/verification.md for project-specific checks
  Produces structured pass/fail report

Gate 3 — Reviewer sentinel (adversarial gate, auto-scaled):
  Dispatcher selects depth based on phase tags from planner:
    lite (2-pass): anti-slop + regression
    full (4-pass): anti-slop, regression, security, performance
  Tags are planner hints, not developer responsibilities.

Gate 4 — UAT (conditional):
  For type:user-facing phases
  Real-world scenarios, install flows, CLI interactions

### Gate Selection (dispatcher-internal)

The dispatcher reads phase tags from PLAN.md as hints and selects
gates automatically. The developer never needs to understand this
matrix — it is orchestrator intelligence, like RDF 2.x's mgr.

- risk:low, type:config → Gate 1 only
- risk:medium, type:feature → Gates 1 + 2 + 3-lite
- risk:medium, type:refactor → Gates 1 + 2 + 3-full
- risk:high (any type) → Gates 1 + 2 + 3-full
- type:security (any risk) → Gates 1 + 2 + 3-full
- type:user-facing, risk:medium → Gates 1 + 2 + 3-lite + 4
- type:user-facing, risk:high → All 4 gates (3-full)
- Default (no tags): Gates 1 + 2 + 3-lite
```

**New Parallel Gate Execution section:**

```
### Parallel Gate Execution (dispatcher-internal)

When both Gate 2 (QA) and Gate 3 (sentinel) are triggered, dispatch
both subagents simultaneously. Do NOT wait for QA before dispatching
sentinel — they operate independently.

After both return, deduplicate findings:

1. Match findings by file:line proximity (±5 lines of each other in
   the same file = same finding)
2. Same finding, same severity → merge, cite both agents
3. Same finding, different severity → take higher severity
4. QA-only finding → include as-is
5. Sentinel-only finding → include as-is
6. Disagreement: take higher-severity assessment, log disagreement
   to status file. Escalate to user only if agents produced
   contradictory MUST-FIX conclusions about the same code.

Gate verdict: PASS only if both agents pass (after dedup). A MUST-FIX
from either agent enters the Finding Resolution loop.
```

**New End-of-Plan Sentinel section:**

```
### End-of-Plan Sentinel

After the last phase of a plan completes (all phases status: complete),
if the plan contained 3 or more phases, run a mandatory full 4-pass
sentinel review on the cumulative diff:

1. Compute diff: git diff from the commit before phase 1 to HEAD
2. Dispatch reviewer in sentinel mode (full 4-pass) with scope set
   to the cumulative diff
3. Apply the Finding Trust Model to results
4. If MUST-FIX findings exist: dispatch engineer to resolve, then
   re-run sentinel (max 2 cycles)
5. Write end-of-plan sentinel results to
   .rdf/work-output/sentinel-plan-final.md

Plans with 1-2 phases skip this step — per-phase sentinel is
sufficient for small plans.

This is separate from /r-ship's sentinel — /r-ship provides a
second layer at release time.
```

**New FP Calibration section:**

```
### FP Calibration (dispatcher-internal)

After receiving QA and/or sentinel reports, run three calibration
checks. These are silent heuristics — the dispatcher acts on
anomalies internally and only escalates to the user when it
cannot resolve them.

1. Zero-finding anomaly:
   IF sentinel report has 0 findings AND 0 discarded findings
   AND the phase diff is 50+ changed lines
   THEN: re-dispatch sentinel at full depth (4-pass) automatically.
   If full-depth review also produces 0 findings: accept as clean,
   log "zero-finding verified at full depth" to status file.
   If full-depth finds issues: process findings normally.
   Diffs under 50 lines: no action (zero findings expected).

2. Discard ratio anomaly:
   IF sentinel report has DISCARDED_FINDINGS count > 2× REPORTED
   count (and DISCARDED > 4 absolute)
   THEN: log anomaly to status file with suppression log excerpt.
   The dispatcher does NOT block the pipeline — this is
   informational for post-hoc review. If the discard ratio
   exceeds 5× REPORTED, escalate to user:
     "Sentinel suppressed {D} findings. Review suppression log?"

3. QA/Sentinel disagreement:
   IF QA and sentinel disagree on a finding (one REPORTED, one
   would not have flagged it): take the higher-severity assessment.
   Log the disagreement to status file. Escalate to user only if
   both agents produced MUST-FIX findings that contradict each
   other (rare — requires opposing conclusions about the same code).
```

**New Finding Resolution Protocol section:**

```
### Finding Resolution (dispatcher-owned)

The dispatcher owns the finding resolution loop. The developer sees
only what the dispatcher cannot resolve internally. This restores
the RDF 2.x model where the mgr handled gate outcomes.

MUST-FIX findings — dispatcher resolves:
  1. Dispatch engineer: "Fix this issue, or refute with
     counter-evidence explaining why the code is correct."
  2. Engineer responds: FIXED (with diff) or REFUTED (with evidence)
  3. FIXED: dispatcher verifies fix passes gates, proceeds
  4. REFUTED: dispatcher evaluates evidence quality using 3 checks:
     (a) Does the refutation cite the specific file and line?
     (b) Does it explain WHY the code is correct, not just THAT it is?
     (c) Does it address the specific concern raised by sentinel?
     All 3 yes → accept refutation, log, proceed.
     Any check fails → reject refutation, re-dispatch engineer with
     feedback on which check failed.
  5. Max 3 fix/refute cycles per finding

  Finding-fix dispatch payload (different from TDD phase dispatch):
  ```
  TASK: fix-finding
  FINDING: {file:line — description from sentinel/QA}
  SEVERITY: MUST-FIX
  CONTEXT: {sentinel's "why" + suggested fix from finding}
  INSTRUCTION: "Fix this issue, or refute with counter-evidence.
    If fixing: make the minimal change, run existing tests, report diff.
    If refuting: cite specific code, explain why it is correct."
  ```

  Escalation to developer (only when dispatcher exhausts options):
  - Engineer cannot fix after 3 attempts
  - Engineer's refutation evidence is insufficient after 3 attempts
  - Finding involves architectural judgment beyond code-level fix
  Escalation format:
    "MUST-FIX (unresolved): {file:line} — {description}.
     Engineer attempted: {fix/refute summary}. Action needed."

CONCERN findings — advisory:
  1. Dispatcher collects all CONCERNs from the phase
  2. Presents to developer at phase end (non-blocking):
     "Phase N: PASS. {N} advisory concerns — review at your
     discretion."
  3. Listed in phase status output, no action required to proceed

SUGGESTION findings — logged:
  1. Written to .rdf/work-output/phase-N-status.md
  2. No output to developer unless they read the status file
  3. Available for review but never block, never prompt

Developer-facing output per phase:
  ✓ "Phase N: PASS" — all gates passed, findings resolved internally
  ✓ "Phase N: PASS (2 findings resolved)" — dispatcher handled them
  ⚠ "Phase N: PASS. 3 advisory concerns." — non-blocking, FYI
  ✗ "Phase N: MUST-FIX (1 unresolved)" — needs human judgment
```

### 5.2 `canonical/agents/reviewer.md` — Sentinel Mode Enhancements

**Change inventory:**

| Section | Current behavior | New behavior | Lines affected |
|---------|-----------------|--------------|----------------|
| Sentinel Mode header | "Reviews diffs across four passes" | "Reviews diffs across two or four passes (lite or full)" | 38-40 |
| (new) Sentinel Depth | N/A | Lite (2-pass) vs Full (4-pass) definition | new after line 40 |
| (new) Counter-Hypothesis Protocol | N/A | Structural FP prevention protocol | new section before Constraints |
| (new) Suppression Log | N/A | DISCARDED_FINDINGS footer format | appended to report format |

**New Sentinel Depth definition:**

```
Sentinel reviews operate at one of two depths, specified in the
dispatch prompt:

**Lite (2-pass)** — for routine risk:medium phases:
  1. Anti-slop
  2. Regression

**Full (4-pass)** — for risk:high, type:security, type:refactor,
end-of-plan, /r-ship, and /r-audit:
  1. Anti-slop
  2. Regression
  3. Security
  4. Performance

Default to full if the dispatch prompt does not specify depth.
```

**New Counter-Hypothesis Protocol:**

```
### Counter-Hypothesis Protocol (sentinel mode, unconditional)

This protocol is always active in sentinel mode. No dispatch-level
opt-in required. Every sentinel invocation — build-time gates,
/r-review standalone, /r-ship, /r-audit — applies this protocol.

Before reporting any MUST-FIX or CONCERN finding, apply this
protocol. CLEAN findings and SUGGESTION-level findings are exempt.

1. **Hypothesis**: State what you believe is wrong:
   "Line N of file.sh does X, which causes Y"

2. **Counter-hypothesis**: Formulate why the code might be correct:
   "This might be intentional if Z"

3. **Seek counter-evidence** — check ALL of the following (do not
   stop at first match; weigh collectively):
   (a) Does governance/anti-patterns.md list this as a known
       intentional pattern FOR THIS FILE or function?
   (b) Is there an inline comment within 5 lines explaining the
       choice?
   (c) Does the project CLAUDE.md document this as intentional?
   (d) Does surrounding code (20+ lines) contain guards, wrappers,
       or callers that handle the concern?

   **Evidence floor**: Counter-evidence must be LOCATION-SPECIFIC —
   same file and function (or direct caller). A project-wide pattern
   match is not sufficient to discard a finding.

4. **Verdict** (based on weight of ALL checks):
   - Counter-evidence specific and compelling across 2+ checks →
     DISCARD (do not report)
   - Counter-evidence present but single check or ambiguous →
     DEMOTE severity one level, note the ambiguity
   - No location-specific counter-evidence →
     REPORT at assessed severity

5. **Record**: For REPORTED and DEMOTED findings, include:
   ```
   CH_RESULT: REPORTED | DEMOTED from <X> to <Y>
   CH_REASON: <one-line counter-evidence evaluation>
   ```

6. **Suppression log** at end of report, after Summary:
   ```
   ### Suppression Log
   DISCARDED_FINDINGS: <N>
     D-001: <file:line> | <hypothesis> | <discard reason>
   ```
```

### 5.3 `canonical/commands/r-review.md` — Enriched Sentinel Dispatch

**Change inventory:**

| Section | Current behavior | New behavior | Lines affected |
|---------|-----------------|--------------|----------------|
| Sentinel dispatch payload | 12-line MODE/SCOPE/GOVERNANCE block | Adds DEPTH and REPORT_FORMAT fields | 76-91 |
| (new) Depth selection | N/A | Full depth when standalone (user explicitly requested review) | new logic in step 4 |

**New sentinel dispatch payload:**

```
MODE: sentinel
DEPTH: full
SCOPE: <file list or "branch diff">
CHANGED_FILES: <list of files in scope>
BASE_BRANCH: <base branch name>

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

Counter-hypothesis is unconditional in sentinel mode (defined in the
reviewer agent, not dispatch-dependent). No opt-in field needed.

Standalone `/r-review --sentinel` always uses `DEPTH: full` — the user
explicitly requested a review, so they get the full 4-pass treatment.
Lite depth is only used by the dispatcher for routine per-phase gates.

### 5.4 `canonical/commands/r-build.md` — End-of-Plan Sentinel

**Change inventory:**

| Section | Current behavior | New behavior | Lines affected |
|---------|-----------------|--------------|----------------|
| Section 7: Report Result | Reports PASS/FAIL, suggests next phase or /r-ship | Adds end-of-plan sentinel trigger before "all complete" message | 94-106 |
| Dispatch payload | Includes RISK and TYPE | Adds PLAN_PHASE_COUNT for dispatcher threshold check | 67-86 |

**New logic in Report Result:**

```
### 7. Report Result

After the dispatcher returns:
- Read the dispatcher's status output from .rdf/work-output/
- Report phase result to the user: PASS or FAIL

- If PASS and more phases remain:
  > **Phase {N} complete** — {description}
  > Next: Phase {N+1} — {description}. Run `/r-build` to continue.

- If PASS and all phases are complete:
  - Count total phases in PLAN.md
  - If 3+ phases: trigger end-of-plan sentinel via dispatcher
    (dispatcher handles this internally when it detects all
    phases complete and PLAN_PHASE_COUNT >= 3)
  - After end-of-plan sentinel passes:
    > **All {N} phases complete.** End-of-plan sentinel: {verdict}.
    > Run `/r-ship` to begin the release workflow.
```

**New field in dispatch payload:**

```
PLAN_PHASE_COUNT: <total phases in PLAN.md>
```

### 5.5 `canonical/reference/framework.md` — Gate Selection Update

**Change inventory:**

| Section | Current behavior | New behavior | Lines affected |
|---------|-----------------|--------------|----------------|
| Gate selection table | 4 entries, sentinel on risk:high only | Simplified 3-entry summary emphasizing dispatcher ownership | 162-167 |

**New gate selection block:**

```
**Gate selection** is managed by the dispatcher based on planner-assigned
phase tags. The developer does not interact with gate selection directly.

Summary:
- Trivial changes (risk:low) → deterministic checks only (engineer + QA)
- Standard changes → deterministic + adversarial review (+ sentinel)
- User-facing changes → add UAT acceptance testing

The dispatcher auto-scales sentinel depth (2-pass or 4-pass) based on
risk level and change type. See dispatcher.md for the full matrix.
```

### 5.6 `modes/development/context.md` — Gate Selection Update

**Change inventory:**

| Section | Current behavior | New behavior | Lines affected |
|---------|-----------------|--------------|----------------|
| Quality Gate Overrides table | 5 rows developer-facing | Replaced with dispatcher-ownership statement | 28-34 |

**New content:**

```
## Quality Gate Overrides

None — development mode uses the dispatcher's automatic gate selection.
The dispatcher reads phase tags from PLAN.md and selects appropriate
gates including sentinel depth. No developer configuration required.

The dispatcher resolves findings internally (engineer fix/refute cycles)
and surfaces only unresolved findings to the developer.
```

---

## 5b. Examples

### Example 1: Routine phase — developer sees pass

```
$ /r-build 3

Building Phase 3: Create starter profiles...

> **Phase 3 complete** — Create starter profiles (2 findings resolved)
> Next: Phase 4 — Create new modes. Run `/r-build` to continue.
```

Behind the scenes (in `.rdf/work-output/phase-3-status.md`): engineer
TDD green, QA PASS, sentinel-lite APPROVE with 2 CONCERN findings that
the dispatcher collected as advisory. Developer sees one line.

### Example 2: End-of-plan sentinel — dispatcher resolves internally

```
$ /r-build 8

Building Phase 8: Regenerate and verify...

All 8 phases complete. Running end-of-plan review...

> **All 8 phases complete.** End-of-plan review: PASS (2 findings
> resolved — stale doc counts in r-mode.md and framework.md).
> Run `/r-ship` to begin the release workflow.
```

Behind the scenes: sentinel found 2 MUST-FIX (stale counts).
Dispatcher dispatched engineer, engineer fixed both, sentinel re-run
approved. Developer never had to intervene.

### Example 3: Unresolved finding — escalated to developer

```
$ /r-build 5

Building Phase 5: Update registry and detection rules...

> **Phase 5: MUST-FIX** (1 unresolved finding)
>
> `lib/cmd/init.sh:142` — profile detection loop scans all
> profiles on every invocation. Engineer attempted refutation:
> "n is bounded at ~20 profiles." Sentinel re-flagged: the loop
> also reads each profile's governance-template.md (disk I/O).
>
> Action needed: accept risk, or optimize the scan path.
> [accept / fix manually / dispatch engineer with guidance]
```

This is the only case where the developer sees gate details — when the
dispatcher exhausted its resolution options (3 fix/refute cycles).

### Example 4: Advisory concerns — non-blocking

```
$ /r-build 7

Building Phase 7: Update canonical commands...

> **Phase 7 complete** — Update canonical commands.
> 2 advisory concerns (review at your discretion).
> Next: Phase 8 — Regenerate and verify. Run `/r-build` to continue.
```

CONCERNs are in the status file if the developer wants to review them.
They do not block, do not prompt, do not require action.

---

## 6. Conventions

### Developer-Facing Surface (6 concepts)

The developer interacts with the gate system through exactly 6 concepts:

1. **PASS** — phase completed, all gates passed (findings resolved internally)
2. **MUST-FIX** — finding that the dispatcher could not resolve, needs human judgment
3. **CONCERN** — advisory finding, non-blocking, review at your discretion
4. **SUGGESTION** — logged improvement idea, never surfaces unless you read the status file
5. **End-of-plan review** — automatic holistic review after multi-phase plans
6. **Phase status file** — `.rdf/work-output/phase-N-status.md` for post-hoc detail

That's it. The developer does not need to understand gate selection,
sentinel depth, counter-hypothesis, FP calibration, dedup rules, or
fix/refute cycles. Those are dispatcher-internal.

### Dispatcher-Internal Conventions

These conventions govern the agents and dispatcher. They are documented
here for spec completeness but are not developer-facing.

**Sentinel depth tag** — dispatch prompt to reviewer:
```
DEPTH: lite    — 2-pass (anti-slop + regression)
DEPTH: full    — 4-pass (anti-slop + regression + security + performance)
```
Reviewer defaults to `full` if `DEPTH` is absent. This ensures
backward compatibility with existing dispatch patterns (r-ship, r-audit).

**Severity terminology (unified):**
- **MUST-FIX** — blocking, requires resolution
- **CONCERN** — non-blocking, advisory
- **SUGGESTION** — logged only

Note: The existing reviewer.md `SHOULD-FIX` is renamed to `CONCERN`
to unify terminology across both reviewer modes.

Disambiguation: `CONCERN` (singular) is a **finding severity** — one
finding at this level. `CONCERNS` (plural) is a **verdict** — the
reviewer's overall assessment when CONCERN-level findings exist but no
MUST-FIX findings. These are different things at different granularities.

**Counter-hypothesis output fields (internal to reviewer report):**
```
CH_RESULT: REPORTED | DEMOTED from <original> to <new>
CH_REASON: <one-line summary>
```
These fields appear in the internal sentinel report that the dispatcher
reads. They do NOT appear in developer-facing output.

**Suppression log (internal to reviewer report):**
```
### Suppression Log
DISCARDED_FINDINGS: <N>
  D-001: <file:line> | <hypothesis> | <discard reason>
```
Read by the dispatcher for FP calibration. Available in the status file
for post-hoc review but never presented to the developer during the
build flow.

**Dedup proximity rule (dispatcher-internal):**
Two findings from QA and sentinel are considered the same if they
reference the same file and lines within ±5 of each other. The
dispatcher merges them, taking the higher severity.

---

## 7. Interface Contracts

### Phase Tag Vocabulary (expanded)

No new tags added. The existing tag vocabulary is sufficient:

- **Risk levels**: `risk:low`, `risk:medium`, `risk:high`
- **Type values**: `type:config`, `type:feature`, `type:refactor`,
  `type:security`, `type:user-facing`, `type:data-migration`

The change is in what gates each combination triggers, not in the
tag vocabulary itself.

### Dispatch Payload Changes

The dispatcher's dispatch to the reviewer adds one field:

```
DEPTH: lite | full
```

Counter-hypothesis is unconditional in sentinel mode (no dispatch
field needed — the reviewer always applies it).

The `/r-build` dispatch to the dispatcher adds one field:

```
PLAN_PHASE_COUNT: <N>
```

### Status File Schema Update

`phase-N-status.md` adds new fields:

```
SENTINEL_DEPTH: lite | full | none
SENTINEL_VERDICT: APPROVE | MUST-FIX | CONCERNS
SENTINEL_FINDINGS: <count>
SENTINEL_DISCARDED: <count>
QA_SENTINEL_DISAGREEMENTS: <count>
FP_CALIBRATION: clean | anomaly-reported | anomaly-confirmed
FINDING_RESOLUTIONS:
  - F-001: FIXED | REFUTED | ACCEPTED
```

`sentinel-plan-final.md` (new file, written after end-of-plan sentinel):

```
SCOPE: cumulative diff (phase 1 through phase N)
DEPTH: full
VERDICT: APPROVE | MUST-FIX | CONCERNS
FINDINGS: <count>
DISCARDED: <count>
RESOLUTIONS:
  - F-001: <file:line> | <severity> | FIXED | REFUTED
```

---

## 8. Migration Safety

### Backward Compatibility

- Plans written before this change (no sentinel depth concept) continue
  to work — the reviewer defaults to `full` when `DEPTH` is absent
- Plans without `PLAN_PHASE_COUNT` in the dispatch payload skip
  end-of-plan sentinel (dispatcher treats missing field as threshold
  not met)
- Existing `/r-ship` and `/r-audit` dispatch prompts continue to work
  unchanged — they don't specify `DEPTH`, so the reviewer uses `full`

### Upgrade Path

- No data migration needed — these are agent/command definition changes
- `rdf generate claude-code` regenerates all deployed files from
  canonical sources
- No `.rdf/governance/` schema changes — FP data flows through existing
  governance files

### Test Suite Impact

- No BATS tests affected — RDF tests are manual verification +
  shellcheck + frontmatter-free checks
- Verification: `rdf generate claude-code` produces valid output, diff
  against expected, grep for stale gate references

---

## 9. Dead Code and Cleanup

| Finding | File | Action |
|---------|------|--------|
| RDF 2.x FP-prevention spec references `sys-sentinel.md`, `sys-qa.md`, `mgr.md` | `docs/specs/2026-03-18-fp-prevention-design.md` | No action — historical spec, not operational |
| `sentinel-N.md` artifact in framework.md references reviewer but doesn't mention depth | `canonical/reference/framework.md:73` | Update to note lite vs full |
| diagrams.md gate flowchart shows old 5-entry matrix | `reference/diagrams.md:184-226` | Update to new matrix |

---

## 10a. Test Strategy

| Goal | Test method | Verification |
|------|-------------|--------------|
| Goal 1: Auto sentinel on non-trivial | Read dispatcher.md gate matrix | Grep for `3-lite` in gate selection, verify default includes sentinel |
| Goal 2: End-of-plan sentinel | Read dispatcher.md end-of-plan section | Grep for `3 or more phases` |
| Goal 3: Parallel QA+sentinel | Read dispatcher.md parallel section | Grep for `simultaneously` and dedup rules |
| Goal 4: Dispatcher owns resolution | Read dispatcher.md finding resolution | Grep for `dispatcher-owned` and fix/refute cycle |
| Goal 5: Counter-hypothesis | Read reviewer.md | Grep for `Counter-Hypothesis Protocol` section |
| Goal 6: FP calibration silent | Read dispatcher.md | Grep for `dispatcher-internal` in FP Calibration section |
| Goal 7: Developer surface ~6 concepts | Read dispatcher.md + framework.md + context.md | Verify no developer-facing gate matrix, only pass/fail + severity levels |
| Goal 8: Review dispatch enriched | Read r-review.md | Grep for `DEPTH` and `REPORT_FORMAT` in dispatch payload |

RDF agent definitions are markdown — testing is structural verification
(section exists, content matches spec), not runtime execution.

## 10b. Verification Commands

```bash
# Goal 1: Gate matrix includes 3-lite for risk:medium
grep -c '3-lite' canonical/agents/dispatcher.md
# expect: >= 2

# Goal 2: End-of-plan sentinel section exists with 3-phase threshold
grep -c 'End-of-Plan Sentinel' canonical/agents/dispatcher.md
# expect: 1
grep 'or more phases' canonical/agents/dispatcher.md
# expect: "3 or more phases"

# Goal 3: Parallel gate execution section exists
grep -c 'Parallel Gate Execution' canonical/agents/dispatcher.md
# expect: 1

# Goal 4: Dedup proximity rule documented
grep '±5' canonical/agents/dispatcher.md
# expect: line proximity matching reference

# Goal 5: Counter-hypothesis protocol in reviewer
grep -c 'Counter-Hypothesis Protocol' canonical/agents/reviewer.md
# expect: 1
grep 'CH_RESULT' canonical/agents/reviewer.md
# expect: at least 1 match

# Goal 6: FP calibration is dispatcher-internal (not developer-facing)
grep -c 'dispatcher-internal' canonical/agents/dispatcher.md
# expect: >= 2 (FP Calibration + Parallel Gate sections)
grep -c 'ask user\|prompt.*user\|pause.*user' canonical/agents/dispatcher.md
# expect: <= 1 (only for extreme anomalies, not routine)

# Goal 7: Developer surface is simple — no gate matrix in framework.md/context.md
grep -c 'dispatcher.*automatic\|dispatcher.*owns\|dispatcher.*manages' canonical/reference/framework.md
# expect: >= 1
grep -c 'Gates 1 + 2 + 3-lite' modes/development/context.md
# expect: 0 (gate matrix removed from developer-facing docs)

# Goal 8: Enriched sentinel dispatch
grep 'DEPTH' canonical/commands/r-review.md
# expect: at least 1 match
grep 'REPORT_FORMAT' canonical/commands/r-review.md
# expect: at least 1 match

# Cross-reference: 3-lite is dispatcher-internal only
grep -c '3-lite' canonical/agents/dispatcher.md
# expect: >= 2 (gate matrix entries)
grep -c '3-lite' canonical/reference/framework.md modes/development/context.md
# expect: 0 (gate matrix removed from developer-facing docs)

# framework.md and context.md reference dispatcher ownership
grep 'dispatcher' canonical/reference/framework.md
# expect: mentions dispatcher managing gate selection
grep 'dispatcher' modes/development/context.md
# expect: mentions dispatcher automatic selection

# rdf generate produces valid output
bash bin/rdf generate claude-code 2>&1 | tail -3
# expect: success message, no errors
```

---

## 11. Risks

1. **Sentinel fatigue on large plans** — An 8-phase plan now runs 8 lite
   sentinels + 1 full end-of-plan sentinel. If phases produce small
   diffs (< 20 lines), the lite sentinel adds time with minimal value.
   *Mitigation:* Lite sentinel is 2-pass only (anti-slop + regression),
   not full 4-pass. On small diffs, this adds seconds, not minutes.
   The FP calibration zero-finding threshold (50 lines) prevents false
   anomaly alerts on small diffs.

2. **Parallel dedup false merges** — The ±5 line proximity rule may
   merge two genuinely distinct findings that happen to be near each
   other in the same file. *Mitigation:* The merge takes the higher
   severity and cites both agents. Even if falsely merged, the more
   serious assessment is preserved. Users reviewing findings see both
   agents' descriptions.

3. **Counter-hypothesis suppression bias** — The protocol could
   suppress too aggressively, reducing sentinel value. *Mitigation:*
   Three safeguards: (a) evidence floor requires location-specific
   counter-evidence, (b) single-check evidence only demotes, doesn't
   discard, (c) FP calibration in the dispatcher flags anomalous
   discard ratios.

4. **Engineer refutation rubber-stamping** — Engineers might routinely
   refute MUST-FIX findings without genuine counter-evidence.
   *Mitigation:* The "refute with evidence" requirement is explicit —
   "REFUTED" without a grep output, file reference, or code citation is
   not valid. The dispatcher can flag empty refutations (future
   enhancement, not in this spec).

5. **End-of-plan sentinel on already-reviewed phases** — If every phase
   already got a per-phase sentinel, the end-of-plan sentinel reviews
   the same code again. *Mitigation:* The end-of-plan sentinel serves a
   different purpose — cross-cutting analysis that per-phase reviews
   structurally cannot provide (stale references, doc count drift,
   inter-phase regressions). Overlap is intentional.

---

## 11b. Edge Cases

| Scenario | Expected behavior | Handling |
|----------|-------------------|---------|
| Plan has exactly 3 phases | End-of-plan sentinel fires | Threshold is >= 3, so 3-phase plans get the holistic review |
| Plan has 2 phases tagged risk:high | Per-phase 3-full runs, no end-of-plan sentinel | Below 3-phase threshold — per-phase full sentinel is sufficient |
| Phase has no tags at all | Default: risk:medium, type:feature → Gates 1 + 2 + 3-lite | Backward compatible — old plans that omit tags now get lite sentinel instead of no sentinel |
| Sentinel and QA both produce 0 findings on a 200-line diff | Dispatcher auto-escalates to full depth sentinel | If full-depth also clean: accept, log "verified at full depth". No developer prompt. |
| QA fails but sentinel approves | Gate fails (QA FAIL is blocking) | QA failure blocks regardless of sentinel approval — both must pass |
| Sentinel discards 10, reports 2 | FP calibration logs anomaly (10 > 2× 2) | Logged to status file for post-hoc review. Pipeline continues. Escalate only if ratio exceeds 5×. |
| Engineer refutes all 3 MUST-FIX findings | Dispatcher evaluates evidence quality per refutation | If evidence is specific (grep output, code citations): accept all. If vague: re-dispatch. Escalate only after 3 failed cycles. |
| /r-review --sentinel invoked standalone | Full 4-pass, counter-hypothesis enabled | Standalone review always uses full depth — user explicitly requested it |
| /r-audit dispatches reviewer | Full 4-pass (existing behavior) | No DEPTH field in audit dispatch → reviewer defaults to full |
| Operational mode is security-assessment | Reviewer weights security pass more heavily (existing behavior) | Gate selection unchanged — mode affects reviewer focus, not gate triggers |
| Plan has 10 phases, phase 7 fails 3 retries | Phases 1-6 complete, phase 7 failed, phases 8-10 pending | No end-of-plan sentinel — plan is incomplete. Sentinel only fires when all phases reach status: complete |
| End-of-plan sentinel finds new MUST-FIX on cycle 2 re-run (after fixing original) | Surface to user — max 2 sentinel re-run cycles exhausted | User decides: fix manually, run `/r-review --sentinel` for another pass, or accept and proceed to /r-ship |

---

## 12. Open Questions

None. All design decisions were resolved during brainstorming and
competitive analysis:
- Q1: Tiered sentinel depth (lite on medium, full on high)
- Q2: End-of-plan sentinel with 3-phase threshold
- Q3: Parallel QA+sentinel with tiebreaker dedup
- Q4: Counter-hypothesis protocol in reviewer, FP data in governance
- Q5: Threshold-gated FP calibration (dispatcher-internal)
- Q6: Severity-tiered finding trust model (dispatcher-owned resolution)
- Q7: Dispatcher owns gate machinery, developer sees ~6 concepts
  (informed by RDF 2.x mgr model + competitive analysis of 14 frameworks)
