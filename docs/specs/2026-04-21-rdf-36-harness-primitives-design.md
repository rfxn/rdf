# RDF 3.6 — Harness Primitives Design

**Date:** 2026-04-21
**Status:** Design (awaiting review)
**Research:** `docs/specs/2026-04-21-rdf-36-harness-primitives-research.md`

Scope: 5 primitives promoted from the 2026-04-21 harness research — `/r-verify-claim` slash command (#2), `EVIDENCE:` schema on engineer result files (#5), `.rdf/governance/ignore.md` ignore-list (#6), `REGRESSION_CASE:` field on plan phases (#10), and rewrite of `adapters/agents-md/` (#13). Item #1 (SessionStart hook) dropped by user.

---

## Codebase Inventory

Every file in scope was read before writing this spec. Line-count and function/section data comes from direct reading, not inference.

| File | Lines | Key Sections / Functions | Touches in this spec | Test file |
|------|-------|--------------------------|----------------------|-----------|
| `canonical/reference/framework.md` | 241 | Engineer result schema (L79-90), QA verdict schema (L92-102), agent naming (L116), command naming (L118-120) | Extend engineer schema with EVIDENCE block; add ignore.md to governance artifact table | `tests/adapter.bats` |
| `canonical/agents/engineer.md` | 55 | Role (L4-10), Protocol/Setup (L13-17), TDD Cycle (L19-30), Evidence (L32-38), Constraints (L40-55) | Patch Evidence block to require structured EVIDENCE lines citing file+line or cmd→output | `tests/adapter.bats` |
| `canonical/agents/dispatcher.md` | 308 | Load (L13-16), Execute modes (L18-36), Quality Gates (L41-62), Scope Classification (L64-109), Model routing (L111-131), Gate verdict logic (L150-157), Finding Resolution (L167-170) | Add structural EVIDENCE block check to Gate 1 (engineer self-report); gate on REGRESSION_CASE field when reading PLAN phase | `tests/adapter.bats` |
| `canonical/agents/reviewer.md` | 177 | Challenge mode (L6-45), Sentinel mode (L46-117), Counter-hypothesis protocol (L119-167) | Patch Challenge mode to invoke /r-verify-claim before asserting "code is broken" MUST-FIX | `tests/adapter.bats` |
| `canonical/agents/qa.md` | 70 | Role, Protocol, Verdict schema | Patch Protocol to re-validate EVIDENCE lines when dispatch scope ≥ multi-file | `tests/adapter.bats` |
| `canonical/commands/r-plan.md` | 521 | Phase template (L310-342), Mandatory metadata fields (L344-352), Quality standard (L381-391), Reviewer dispatch (L371-419) | Add REGRESSION_CASE field to template; add quality checklist item | `tests/adapter.bats` |
| `canonical/commands/r-build.md` | 291 | Minimum schema validation (L23-29), Identify Target Phase (L31-41), Dispatcher dispatch (later) | Add REGRESSION_CASE to minimum schema validation | `tests/adapter.bats` |
| `canonical/commands/r-init.md` | 793 | Generate: constraints.md (L483-506), Authoritative file handoff (L558) | Add "Generate: ignore.md" step with conservative defaults | `tests/adapter.bats` |
| `canonical/commands/r-refresh.md` | 299 | Stage 3b per-file refresh (enumerates index.md, architecture.md, conventions.md, verification.md, constraints.md, anti-patterns.md) | Add `ignore.md` to the per-file refresh list so existing projects gain it on `/r-refresh` | `tests/adapter.bats` |
| `adapters/agents-md/adapter.sh` | 145 | `_amd_extract_governance_section()` (L16-57), `_amd_agent_roster()` (L60-74), `amd_generate_all()` (L77-145) | Rewrite: drop `_amd_extract_governance_section`, source from canonical reference files instead | `tests/adapter.bats` |
| `adapters/agents-md/sections.json` | 38 | max_lines=150, 6 sections (Project Context, Build & Test, Code Style, Git Workflows, Agent Roster, Constraints) | Rewrite sections to canonical-source pointers | `tests/adapter.bats` |
| `adapters/agents-md/output/AGENTS.md` | 11 | Broken output: "(governance file not found)" at line 11 | Regenerated; expect 80-120 lines | N/A (artifact) |
| `lib/cmd/generate.sh` | 152 | `agents-md` dispatch (L102-106), `all` dispatch (L127-129) | No change | N/A |
| `canonical/commands/r-spec.md` | ~600 | Phase 3.1 spec template | No change (existing template unchanged; REGRESSION_CASE lives in PLAN not spec) | N/A |

Dependency chain read:

```
r-build.md  ──reads──▶  PLAN.md  ◀──reads──  dispatcher.md
                           │
                           └─ REGRESSION_CASE field (NEW)

engineer.md ──writes──▶ phase-N-result.md ──reads──▶ dispatcher.md
                            │                          │
                            └─ EVIDENCE block (NEW)    └─ structural check (NEW)

qa.md ──reads──▶ phase-N-result.md (scope >= multi-file, NEW behavior)

reviewer.md ──invokes──▶ /r-verify-claim (NEW) before MUST-FIX assertions

/r-init.md ──generates──▶ .rdf/governance/ignore.md (NEW)

adapters/agents-md/adapter.sh ──reads──▶ canonical/reference/framework.md (NEW source)
                              ──reads──▶ CLAUDE.md.ref (NEW source)
                              ──reads──▶ canonical/agents/*.md (existing)
```

Existing patterns observed:
- Agent personas use numbered section headers and `## Role / ## Protocol / ## Constraints` triad.
- Result file schemas live in `canonical/reference/framework.md` (authoritative) and are referenced from agent personas.
- `sections.json` in adapters is the declarative config pattern (avoid hardcoding content in adapter.sh).
- `rdf doctor` runs structural + content-drift checks. New artifacts must be compatible.

---

## 1. Problem Statement

The 2026-04-21 harness primitives research surveyed 12+ external frameworks and identified 22 candidate primitives. After adversarial review, 6 were recommended for 3.6; one was dropped by the user. The remaining 5 fall into three themes:

**Theme A — Evidence becomes mechanical** (#2, #5, #10). RDF's `CLAUDE.md.ref` contains 6 operating primitives that are constitutionally asserted but not mechanically enforced. "Cite evidence for every 'done'" (Trust but Verify) depends on model discipline and reviewer vigilance. When the reviewer is at 60k tokens, asserted claims pass without grep verification. This creates two measurable failure modes:

1. **Silent claim drift.** Engineer reports "Phase 3 landed" with test output that doesn't actually prove the claim. Dispatcher reads STATUS: DONE and advances. Three phases later, a sentinel catches the unresolved issue — but now the fix requires rewinding 3 commits.
2. **Regression gaps.** Planner writes phases whose behavior changes have no named regression test. `/r-build` has no schema check for this. Post-merge regressions are the most common source of revert commits in the 2026-03 and 2026-04 ship-logs.

**Theme B — Context hygiene** (#6). In long sessions, `grep -rn` returns hundreds of hits inside `node_modules/`, `vendor/`, build artifacts, and `.rdf/work-output/`. Cline's own docs cite `.clineignore` as their single biggest context-reduction tool (200k → 50k). RDF has no governance-declared path exclusion; each agent has to rediscover which directories are noise.

**Theme C — Broken primitive** (#13). `adapters/agents-md/adapter.sh` exists and is wired into `rdf generate all`, but its output at `adapters/agents-md/output/AGENTS.md` reads:

```
## Build & Test

(governance file not found)
```

The adapter calls `_amd_extract_governance_section` on `profiles/shell/governance.md` — a path that does not exist (the actual file is `profiles/shell/governance-template.md`). Root cause: the adapter was written assuming a consumer-project governance layout, but it runs in RDF-the-project which has no generated governance — only templates.

Measurement: `adapters/agents-md/output/AGENTS.md` is 11 lines with 1 data-bearing line and 2 failures printed in place of content.

---

## 2. Goals

Numbered, measurable, pass/fail verifiable.

1. `/r-verify-claim` command exists at `canonical/commands/r-verify-claim.md` and is deployed to `~/.claude/commands/r-verify-claim.md` by `rdf generate claude-code`.
2. Engineer result files produced after this spec ships MUST contain a non-empty `EVIDENCE:` block with at least 1 structured line (`path:line` or `cmd → output`).
3. Dispatcher rejects an engineer result with missing or empty `EVIDENCE:` by emitting verdict `NEEDS_CONTEXT` with fix guidance.
4. `.rdf/governance/ignore.md` exists on any project initialized by `/r-init`, containing ≥ 6 default exclusions.
5. `/r-plan` template includes a `Regression-case:` metadata field on every phase, adjacent to existing Mode/Accept/Test/Edge-cases fields.
6. `/r-build` refuses to dispatch a phase whose `Regression-case:` field is missing OR whose N/A value is not in the closed category set.
7. `adapters/agents-md/output/AGENTS.md` is ≥ 60 lines after regeneration, contains zero "(governance file not found)" error strings, and cites canonical reference files by name in each section.
8. `rdf doctor` reports 0 FAIL and ≤ 1 WARN on a fresh deployment of this change.
9. The 5 items are implemented in ≤ 7 phases, each individually revertable.

---

## 3. Non-Goals

- **No new agent types.** All changes are persona patches. No dispatcher logic flow changes — only schema checks added.
- **No dispatcher model-routing changes.** Scope classification (L64-109) and model routing (L111-131) are untouched.
- **No migration of existing engineer result files.** The `EVIDENCE:` block requirement applies to results produced *after* the change ships; prior results stay as-is.
- **No changes to `/r-ship`, `/r-vpe`, `/r-audit`, `/r-audit-slop`.** Out of scope.
- **No new CI workflow gates.** Field-data collection in the first 4 weeks of 3.6 drives whether /r-build's new check graduates to CI enforcement in 3.6.x.
- **No migration of existing consumer-project `.rdf/governance/` directories.** Consumer projects that run `/r-refresh` after 3.6 lands will receive the new `ignore.md` file; pre-existing governance is left alone.
- **No changes to the spec template (`canonical/commands/r-spec.md`).** REGRESSION_CASE lives in the PLAN, not the SPEC. Spec continues to describe regression cases in free-form §10a (Test Strategy).
- **No removal of existing engineer result schema fields.** TDD_EVIDENCE (L85-87 of framework.md) remains; EVIDENCE is additive and operates at a different level (TDD_EVIDENCE proves tests exist; EVIDENCE proves claims).

---

## 4. Architecture

### 4.1 File Map

**New files:**

| File | Est. lines | Purpose |
|------|-----------:|---------|
| `canonical/commands/r-verify-claim.md` | 120 | Slash command driver: takes a claim, produces triage report with grep/stat/log commands and PASS/FAIL verdict |
| `profiles/core/reference/ignore-defaults.md` | 40 | Conservative default exclusions shipped by `/r-init` when writing governance/ignore.md |
| `tests/adapter.bats` additions | +50 | 5 new @test cases (one per goal class) |

**Modified files:**

| File | Change |
|------|--------|
| `canonical/reference/framework.md` | §Engineer result schema: add `EVIDENCE:` block (structural grammar + examples). §Governance artifacts table: add `ignore.md` row. |
| `canonical/agents/engineer.md` | §Evidence (L32-38): replace narrative "Your result MUST include" with structured EVIDENCE grammar. |
| `canonical/agents/dispatcher.md` | §Quality Gates Gate 1 (L41-44): add EVIDENCE structural check before accepting STATUS: DONE. §Load (L13-16): add "parse REGRESSION_CASE field from target phase" before dispatch. |
| `canonical/agents/qa.md` | §Protocol: when scope ≥ multi-file, re-run the engineer's EVIDENCE commands; record PASS/FAIL to verdict. |
| `canonical/agents/reviewer.md` | §Challenge Mode (L10-44): patch — before asserting "code is broken" MUST-FIX, run `/r-verify-claim` and cite result. |
| `canonical/commands/r-plan.md` | §Phase template (L321-324): insert `Regression-case:` field. §Mandatory metadata fields (L344): add REGRESSION_CASE to list. §Quality checklist (L381-391): add check #12 for regression schema. |
| `canonical/commands/r-build.md` | §Minimum schema validation (L23-29): add REGRESSION_CASE to required fields; reject on missing or unknown category. |
| `canonical/commands/r-init.md` | §After "Generate: constraints.md" (L483-506): insert "Generate: ignore.md" step with template merge from `profiles/core/reference/ignore-defaults.md`. |
| `canonical/commands/r-refresh.md` | Stage 3b per-file refresh list: add `ignore.md` alongside `constraints.md`. Apply the same user-modified-merge rule as other governance files. See §5.12. |
| `adapters/agents-md/adapter.sh` | Rewrite: drop `_amd_extract_governance_section()`. New sources are canonical reference files + `CLAUDE.md.ref`. `_amd_agent_roster()` unchanged. |
| `adapters/agents-md/sections.json` | Rewrite sections to canonical-source pointers (source kind: `canonical`, path: relative to RDF_CANONICAL). max_lines raised to 200. |
| `tests/adapter.bats` | +5 @test cases for the new artifacts. |
| `CHANGELOG` + `CHANGELOG.RELEASE` | Per-commit entries. |

**Deleted files:** none. Existing adapter output at `adapters/agents-md/output/AGENTS.md` is regenerated, not deleted.

### 4.2 Size Comparison

| Surface | Before | After | Δ |
|---|---:|---:|---:|
| `canonical/commands/` | 33 commands | 34 commands | +1 |
| `canonical/reference/` | 4 docs | 4 docs | 0 |
| `canonical/agents/engineer.md` | 55 lines | ~80 lines | +25 |
| `canonical/agents/dispatcher.md` | 308 lines | ~335 lines | +27 |
| `canonical/agents/reviewer.md` | 177 lines | ~185 lines | +8 |
| `canonical/agents/qa.md` | 70 lines | ~90 lines | +20 |
| `canonical/commands/r-plan.md` | 521 lines | ~540 lines | +19 |
| `canonical/commands/r-build.md` | 291 lines | ~310 lines | +19 |
| `canonical/commands/r-init.md` | 793 lines | ~823 lines | +30 |
| `adapters/agents-md/adapter.sh` | 145 lines | ~130 lines | -15 |
| `adapters/agents-md/sections.json` | 38 lines | ~50 lines | +12 |
| `adapters/agents-md/output/AGENTS.md` | 11 lines | ~100 lines | +89 |
| `tests/adapter.bats` | 7 tests | 12 tests | +5 |

Total delta: +259 lines across source + ~100 lines of regenerated output. No net tool additions, no new runtime dependencies.

### 4.3 Dependency Tree

```
/r-verify-claim (new command)
    ├─ deployed by: lib/cmd/generate.sh (existing; no wire change needed —
    │                generate.sh auto-deploys all canonical/commands/*.md)
    └─ invoked by: reviewer.md (new reference in Challenge Mode)
                   user (typed as /r-verify-claim)
                   other agents (optional)

EVIDENCE schema
    ├─ defined in: canonical/reference/framework.md (§Engineer result schema)
    ├─ produced by: engineer.md (writes phase-N-result.md with EVIDENCE block)
    ├─ structurally checked by: dispatcher.md (Gate 1 — rejects missing/empty)
    └─ semantically re-run by: qa.md (scope >= multi-file only)

.rdf/governance/ignore.md
    ├─ seeded from: profiles/core/reference/ignore-defaults.md
    ├─ generated by: r-init.md (Generate: ignore.md step)
    ├─ refreshed by: r-refresh.md (governance scope; preserves user-modified)
    └─ consumed by: (reference doc; no automatic tool consumption in 3.6 —
                    agents read it during setup, grep manually)

REGRESSION_CASE:
    ├─ defined in: r-plan.md (phase template)
    ├─ written by: planner.md (implicitly via /r-plan)
    ├─ validated by: r-build.md (minimum schema check)
    └─ read by: dispatcher.md (included in engineer dispatch context)

agents-md adapter (rewritten)
    ├─ reads: canonical/reference/framework.md (section extraction)
    ├─ reads: CLAUDE.md.ref (operating primitives)
    ├─ reads: canonical/agents/*.md (roster)
    └─ writes: adapters/agents-md/output/AGENTS.md
```

### 4.4 Key Architectural Decisions

**D1: EVIDENCE is additive, not replacement.** The existing `TDD_EVIDENCE` field (framework.md:85-87) proves tests were written and ran. The new `EVIDENCE` field proves claims in the phase *description* (e.g., "Phase removes all bare `cp` calls from lib/" must cite grep output showing zero matches). Both ship together in the result file.

**D2: Dispatcher check is structural, QA check is semantic.** Dispatcher scans for presence of non-empty EVIDENCE lines matching `<path>:<line>` or `<cmd>` → `<output>` grammar. It does NOT re-run the commands. QA re-runs them only for scope ≥ multi-file (gate already fires; no extra dispatch cost). Rationale: structural gate is 0-cost and prevents blank blocks; semantic re-validation costs QA time and is wasted on docs/focused phases.

**D3: Reviewer invokes /r-verify-claim at the point of doubt, not always.** The persona patch is: "Before asserting a MUST-FIX that claims 'code is broken', run `/r-verify-claim` and paste the output into the finding." Opt-in at the point where the finding is being authored. This addresses the reviewer context budget concern — reviewer is already at 60k+ tokens; making verification mandatory on every finding would push over.

**D4: REGRESSION_CASE closed-set categories.** Free text becomes `# TODO add test` boilerplate (this is kill criterion #10 in the research report). Closed set: `docs` / `performance` / `logging` / `refactor`. Every other phase must name a test. Planner can still elect N/A but must pick a category and give a reason:

```
Regression-case: tests/foo.bats::@test "bar does baz"
Regression-case: N/A — refactor (no behavior change; unit tests unchanged)
```

**D5: ignore.md is reference, not enforcement.** RDF does not ship a glob-match engine. Agents read ignore.md during setup and use it as input to their grep invocations (`grep -r --exclude-dir=node_modules ...`). Enforcement graduates to tooling in 3.7 if field data shows adoption.

**D7: ignore.md is a separate file, not an extension to constraints.md.** The research report (item #6) proposed extending constraints.md with an `EXCLUDED_PATHS` section — ~15 lines vs ~40 lines in a new file. The spec chooses the separate-file path for three reasons: (a) `constraints.md` carries hard platform/version constraints that must never be skipped by any agent or tool — mixing soft "grep convenience" paths into that file dilutes the semantic; (b) `constraints.md` is read by dispatcher scope classification (L64-109) — adding glob lists would force the classifier to ignore a portion of its input or add parsing overhead; (c) a dedicated file pattern-matches the .gitignore convention users already know. Cost: agents load one additional file. Benefit: semantic integrity of constraints.md is preserved.

**D6: agents-md adapter sources from canonical, not profiles.** The prior design reached for `profiles/<profile>/governance.md` which doesn't exist. New design: source from `canonical/reference/framework.md` (which IS the authoritative RDF framework description) and `CLAUDE.md.ref` (the operating primitives). Per-profile governance belongs to consumer projects' AGENTS.md, which they generate themselves via `/r-init` — out of scope here.

### 4.5 Dependency Rules

- Every new artifact in `canonical/` must be deployable by `rdf generate claude-code` without changes to `lib/cmd/generate.sh`. Achieved: `/r-verify-claim` is a standard `canonical/commands/*.md` file.
- `canonical/` content remains frontmatter-free (RDF convention).
- EVIDENCE and REGRESSION_CASE schemas must be documented in `canonical/reference/framework.md` (authoritative source), with agent personas linking back — never redefining.
- `sections.json` is the declarative surface for the agents-md adapter; new sources must not hardcode content in `adapter.sh`.

---

## 5. File Contents

### 5.1 New file: `canonical/commands/r-verify-claim.md`

Function inventory (sections):

| Section | Purpose | Dependencies |
|---------|---------|--------------|
| Preamble | Slash-command description; invocation forms; when the model should self-invoke | None |
| Argument parsing | Detect: free-text claim; `--commit <sha>` claim anchor; `--grep <pattern>` shortcut; `--from-finding <sentinel-N.md>` for reviewer use | None |
| Triage classifier | 5 claim classes: *commit-landed*, *pattern-absent*, *pattern-present*, *file-unchanged*, *behavior-observable*. Classifier runs on claim text. | None |
| Per-class probes | Each class emits a specific probe set. Table of `<class> → <commands>` with expected-output rubric | `git`, `grep`, `stat`, `test` |
| Verdict logic | PASS if all probes match expected; FAIL if any contradict; UNVERIFIABLE if claim cannot be operationalized | None |
| Output format | Structured markdown report with probes + results + verdict + suggested next action | None |
| Integration note | Reviewer persona calls into this before MUST-FIX assertions | reviewer.md |

### 5.2 Modified: `canonical/reference/framework.md` — Engineer result schema

Current schema (L79-90):

```
STATUS: DONE | DONE_WITH_CONCERNS | BLOCKED | NEEDS_CONTEXT
PHASE: <N>
COMMIT_HASH: <sha>
FILES_CHANGED: <list>
TDD_EVIDENCE:
  TESTS: <test names, red/green output>
  COVERAGE_DELTA: <if measurable>
GOVERNANCE_APPLIED: <constraints and how>
CONCERNS: <if DONE_WITH_CONCERNS>
```

New schema (adds EVIDENCE block after TDD_EVIDENCE):

```
STATUS: DONE | DONE_WITH_CONCERNS | BLOCKED | NEEDS_CONTEXT
PHASE: <N>
COMMIT_HASH: <sha>
FILES_CHANGED: <list>
TDD_EVIDENCE:
  TESTS: <test names, red/green output>
  COVERAGE_DELTA: <if measurable>
EVIDENCE:
  - <claim>: <path>:<line> | <cmd> → <output>
  - <claim>: <path>:<line> | <cmd> → <output>
GOVERNANCE_APPLIED: <constraints and how>
CONCERNS: <if DONE_WITH_CONCERNS>
```

Grammar for each EVIDENCE line:
- Claim is free text, human-readable, anchored to phase description or Accept criterion.
- After the colon, at least one of:
  - `<path>:<line>` — file reference, proof-by-existence or proof-by-absence
  - `<cmd> → <output>` — command + its output snippet (truncated to ≤120 chars per line)
  - `<sha> <message>` — git log entry proving commit landed
- Multiple citations per claim are permitted (pipe-separated).
- Minimum: 1 line for STATUS: DONE; 0 lines permitted only for STATUS: BLOCKED or NEEDS_CONTEXT.

Structural check (dispatcher Gate 1):
- Block exists (regex: `^EVIDENCE:` followed by indented `-` lines)
- At least one line matches the grammar when STATUS: DONE or DONE_WITH_CONCERNS
- Fail: STATUS: DONE with empty EVIDENCE block → verdict NEEDS_CONTEXT, feedback: "EVIDENCE block missing at least one citation line"
- Arrow accepted in either U+2192 (`→`) or ASCII (`->`) form — both are valid per grammar in §6.2

### 5.3 Modified: `canonical/agents/engineer.md` — §Evidence

Current (L32-38):
```
### Evidence

Your result MUST include:
- Files created or modified (with paths)
- Test names and their red→green progression
- Final test output (pass/fail)
- Coverage delta if measurable
- Any governance constraints you applied and how
```

New (L32-50 approx):
```
### Evidence

Your result has two evidence sections:

**TDD_EVIDENCE** — proves tests exist and run:
- Test names and their red→green progression
- Final test output (pass/fail)
- Coverage delta if measurable

**EVIDENCE** — proves phase claims are true in the codebase:
- One line per claim from the phase description or Accept criterion
- Each line cites file+line, command+output, or commit SHA
- Empty EVIDENCE is rejected by dispatcher Gate 1 when STATUS: DONE
- Grammar defined in canonical/reference/framework.md

Example EVIDENCE line:
  - "bare cp removed from lib/": grep -rn '^\s*cp ' lib/ → (no output)
  - "Phase 3 landed": 0224097 Require sequential TaskCreate for multi-phase task lists
```

### 5.4 Modified: `canonical/agents/dispatcher.md` — Gate 1

Current (L41-44):
```
Gate 1 — Engineer self-report:
  TDD evidence: test names, red/green output, coverage delta
```

New:
```
Gate 1 — Engineer self-report:
  TDD evidence: test names, red/green output, coverage delta
  EVIDENCE block: structural check that block exists and contains
    at least one line matching `<claim>: <path>:<line>` or
    `<claim>: <cmd> → <output>` when STATUS is DONE or DONE_WITH_CONCERNS.
    Empty or missing → verdict NEEDS_CONTEXT with feedback
    "EVIDENCE block missing required citation".
```

Also extend §Load (L13-16) to parse REGRESSION_CASE from the target phase before dispatch, and pass it to the engineer subagent in the dispatch prompt.

### 5.5 Modified: `canonical/agents/qa.md` — Protocol

Insert new step between existing "Run linters" and "Run tests":

```
### EVIDENCE re-validation (scope-gated)

If dispatch scope ≥ multi-file:
  1. Derive the result file path: `.rdf/work-output/phase-<N>-result.md`
     where <N> is the phase number passed in the dispatch payload
  2. Read the EVIDENCE block from that file
  3. For each EVIDENCE line:
     - Extract the command (right of the pipe or after the claim colon)
     - Execute in the project working directory
     - Compare output to the output stated in the EVIDENCE line
     - Record result as PASS (matches) or FAIL (differs)
     - If no command is present (e.g., pure path:line citation),
       run `test -f <path>` to confirm existence; record accordingly

Add EVIDENCE_CHECK to the verdict schema:
  EVIDENCE_CHECK: PASS | FAIL | SKIPPED(scope)

For scope in {docs, focused}: record SKIPPED(scope) and continue.
If the result file does not exist (unexpected for scope ≥ multi-file):
record EVIDENCE_CHECK: FAIL with reason "result file not found".
```

### 5.6 Modified: `canonical/agents/reviewer.md` — Challenge Mode

After existing "Report format" block (L22-37), insert:

```
### Verification protocol (MUST-FIX assertions)

Before reporting a MUST-FIX(blocking-concern) that claims "code is
broken", "file is missing", "function doesn't do X", or similar
falsifiable runtime assertions:

1. Run /r-verify-claim with the exact claim text
2. Paste the verify-claim output into the finding body
3. If /r-verify-claim returns PASS (contradicts the finding): downgrade
   or drop the finding
4. If FAIL or UNVERIFIABLE: proceed; include the probe output in the
   finding as concrete evidence

This applies only to falsifiable claims about current state. Design
opinions, style findings, and SHOULD-FIX suggestions are exempt.
```

### 5.7 Modified: `canonical/commands/r-plan.md` — Phase template

Current (L321-324):
```
- **Mode**: {serial-context | serial-agent | parallel-agent}
- **Accept**: {acceptance criteria — concrete, testable, pass/fail}
- **Test**: {test file + test names, or verification commands with expected output}
- **Edge cases**: {spec edge cases covered by this phase, or "none"}
```

New:
```
- **Mode**: {serial-context | serial-agent | parallel-agent}
- **Accept**: {acceptance criteria — concrete, testable, pass/fail}
- **Test**: {test file + test names, or verification commands with expected output}
- **Edge cases**: {spec edge cases covered by this phase, or "none"}
- **Regression-case**: {tests/foo.bats::@test "named test" | N/A — <category> — <reason>}
  - Category must be one of: docs | performance | logging | refactor
  - Named test MUST reference a test that exists at plan time OR is
    created as part of this phase. `# TODO: add test` is rejected.
```

§Mandatory metadata fields (L344) updates:
```
**Mandatory phase metadata fields:** Mode, Accept, Test, Edge cases, Regression-case.
```

§Plan preamble template additions (L140-154 of r-plan.md) — add a single line after `**Phases:**`:
```
**Plan Version:** 3.6
```
This marker is what `/r-build` keys on for version-aware schema validation. Plans written by `/r-plan` from 3.6 onward include it; pre-3.6 plans do not, and `/r-build` skips the Regression-case check for those.

§Quality standard checklist adds (after current #11):
```
12. Regression-case present on every phase?
    Check: every phase has a Regression-case field with either a
    named test reference or a closed-category N/A entry
```

### 5.8 Modified: `canonical/commands/r-build.md` — Minimum schema validation

Current (L23-29):
```
- Validate minimum schema — each phase must have:
  - `## Phase N: <description>`
  - `**Mode**: serial-context | serial-agent | parallel-agent`
  - `**Accept**: <acceptance criteria>`
  - `**Test**: <test file + test names, or verification commands>`
  - `**Edge cases**: <spec edge cases covered, or "none">`
- If schema validation fails, report which fields are missing and stop
```

New (append):
```
  - `**Regression-case**: <named-test-ref | N/A — <category> — <reason>>`
- If schema validation fails, report which fields are missing and stop
- For Regression-case: if the value is N/A, validate the category is
  one of {docs, performance, logging, refactor, security}. Unknown
  category → stop with error "Regression-case category '<value>' not
  in allowed set"
- For Regression-case: if the value is a test reference, validate the
  shape matches `<path>::@test "<name>"` or similar known framework
  syntax. Shape mismatch → stop with error "Regression-case '<value>'
  does not match a known test reference pattern"
- For Regression-case with category `security`: the reason field must
  contain a CVE identifier, upstream bug reference, or internal
  issue reference. Absent → stop with error "Regression-case security
  N/A requires CVE/bug/issue reference in reason"

Plan-version awareness: before running Regression-case validation,
check the plan preamble for `**Plan Version:** 3.6` or higher.
If absent (legacy pre-3.6 plan), skip Regression-case validation
with INFO log "Legacy plan detected (no Plan Version marker);
Regression-case not enforced." All other schema checks still fire.
```

### 5.9 Modified: `canonical/commands/r-init.md` — Generate: ignore.md

Insert after §Generate: constraints.md (L507). Insert the following block (using 4-backtick outer fence to safely nest the 3-backtick structure example):

````
### Generate: ignore.md

Content sources: Phase 2 directory scan for known noise patterns
(node_modules/, vendor/, dist/, build/, target/, __pycache__/,
.venv/, venv/), Phase 3 CI config for artifact directories,
profiles/core/reference/ignore-defaults.md for conservative defaults
that apply to every project.

Structure:
```
# Excluded Paths

> Paths that agents and grep-based tooling should skip.
> .gitignore-style glob syntax. Comments begin with #.

# Build / dependency trees
node_modules/
vendor/
dist/
build/
target/

# Python / virtualenvs
__pycache__/
.venv/
venv/
*.pyc

# RDF working state (never contains source)
.rdf/work-output/

# Generated spec/plan state (user-local)
docs/specs/
```

Merge behavior: if `ignore.md` already exists, treat as user-modified
(preserve entries, append new defaults under a "# Added by /r-init" heading).
````

### 5.12 Modified: `canonical/commands/r-refresh.md` — Stage 3b

Current (L3b, enumerates per-file refresh targets):
```
- index.md — regenerate from current scan (always updated)
- architecture.md — update component map, boundaries
- conventions.md — update coding patterns from scan
- verification.md — update check list from detected tools
- constraints.md — update platform targets, version floors
- anti-patterns.md — update from codebase patterns
```

New (add `ignore.md` row with merge semantics):
```
- index.md — regenerate from current scan (always updated)
- architecture.md — update component map, boundaries
- conventions.md — update coding patterns from scan
- verification.md — update check list from detected tools
- constraints.md — update platform targets, version floors
- anti-patterns.md — update from codebase patterns
- ignore.md — refresh from profiles/core/reference/ignore-defaults.md
  using the same user-modified-merge rule: preserve existing entries,
  append only new defaults under "# Added by /r-refresh" heading if
  any default is missing from the current file. If ignore.md does not
  exist (pre-3.6 project), create it with the full default set.
```

This closes the upgrade-path promise in §8.2: existing consumer projects get `ignore.md` on their next `/r-refresh` governance-scope run.

### 5.10 Modified: `adapters/agents-md/adapter.sh` — rewrite

Current function inventory:

| Function | Signature | Current behavior | New behavior |
|----------|-----------|------------------|--------------|
| `_amd_extract_governance_section` | `(gov_file, keyword)` | Reads `profiles/<profile>/governance.md` (does not exist); outputs "(governance file not found)" | **DELETE** |
| `_amd_extract_canonical_section` | `(canonical_file, heading)` | — | **NEW** — extract section by heading from `canonical/reference/framework.md` or `CLAUDE.md.ref`; 30-line extraction cap |
| `_amd_agent_roster` | `()` | Reads `canonical/agents/*.md`, emits bullet list | UNCHANGED |
| `amd_generate_all` | `()` | Reads sections.json; dispatches on source type `static`/`governance`/`agents` | Replace `governance` dispatch with `canonical`; rest unchanged |

### 5.11 Modified: `adapters/agents-md/sections.json` — rewrite

Current source types: `static`, `governance`, `agents`.

New source types: `static`, `canonical`, `agents`.

New sections:

| Heading | Source | Content / pointer |
|---------|--------|-------------------|
| Project Context | static | Unchanged |
| Operating Primitives | canonical | `CLAUDE.md.ref` (full content, preserved) |
| Architecture Overview | canonical | `canonical/reference/framework.md` § "Categories" (components table) |
| Result File Artifacts | canonical | `canonical/reference/framework.md` § "Engineer result schema" and "QA verdict schema" |
| Agent Roster | agents | Unchanged |
| Commands | canonical | `canonical/reference/framework.md` § "Command naming" (both command categories) |
| Conventions | static | Naming rules, frontmatter-free canonical, CHANGELOG pattern |

`max_lines` raised from 150 to 200 (new content is information-dense, still fits the budget).

---

## 5b. Examples

### 5b.1 `/r-verify-claim` invocation

Input:
```
$ /r-verify-claim "bare cp removed from lib/"
```

Expected stdout (markdown):
```markdown
## Claim Verification

**Claim:** bare cp removed from lib/
**Class:** pattern-absent

### Probes

| # | Command | Expected | Actual | Result |
|---|---------|----------|--------|--------|
| 1 | `grep -rn '^\s*cp ' lib/` | no output | no output | PASS |
| 2 | `grep -rn '\bcp\b' lib/ \| grep -v 'command cp'` | no output | no output | PASS |

**Verdict:** PASS — claim holds as of HEAD 0224097.

**Evidence line for result file:**
  - "bare cp removed from lib/": grep -rn '^\s*cp ' lib/ → (no output)
```

Failure case:
```
$ /r-verify-claim "Phase 4 landed"

## Claim Verification

**Claim:** Phase 4 landed
**Class:** commit-landed

### Probes

| # | Command | Expected | Actual | Result |
|---|---------|----------|--------|--------|
| 1 | `git log --oneline origin/main..HEAD \| grep -i "phase 4"` | 1+ matches | (no output) | FAIL |

**Verdict:** FAIL — no commit matching "phase 4" found on HEAD.

**Suggested next action:** Either (a) the commit hasn't landed —
re-check PLAN.md status, or (b) the commit message doesn't contain
"phase 4" — provide commit SHA explicitly with --commit <sha>.
```

### 5b.2 Engineer result file with EVIDENCE

```
STATUS: DONE
PHASE: 3
COMMIT_HASH: abc1234
FILES_CHANGED: canonical/agents/engineer.md, canonical/reference/framework.md
TDD_EVIDENCE:
  TESTS: tests/adapter.bats::@test "engineer persona declares EVIDENCE block"
  COVERAGE_DELTA: +1 test
EVIDENCE:
  - "EVIDENCE section added to engineer.md": canonical/agents/engineer.md:34
  - "EVIDENCE grammar defined in framework.md": canonical/reference/framework.md:88
  - "@test case exists": grep -c '@test "engineer persona declares EVIDENCE block"' tests/adapter.bats → 1
GOVERNANCE_APPLIED: frontmatter-free canonical content; one-line function headers
```

### 5b.3 Plan phase with REGRESSION_CASE

```
### Phase 4: Add EVIDENCE schema to engineer result

**Files:**
- Modify: `canonical/agents/engineer.md` (§Evidence section rewrite)
- Modify: `canonical/reference/framework.md` (engineer result schema)

- **Mode**: serial-agent
- **Accept**: engineer.md §Evidence references EVIDENCE grammar; framework.md includes EVIDENCE block in schema
- **Test**: tests/adapter.bats::@test "engineer persona declares EVIDENCE block"
- **Edge cases**: empty EVIDENCE on STATUS: BLOCKED (allowed); empty on DONE (rejected)
- **Regression-case**: tests/adapter.bats::@test "engineer persona declares EVIDENCE block"
```

N/A example:
```
### Phase 7: Changelog entries for 3.6 release

- **Mode**: serial-context
- **Accept**: CHANGELOG and CHANGELOG.RELEASE have entries for each 3.6 change
- **Test**: grep -c '3\.6' CHANGELOG → >=5
- **Edge cases**: none
- **Regression-case**: N/A — docs — no behavior change, changelog-only edit
```

### 5b.4 `.rdf/governance/ignore.md` (default output of /r-init)

```markdown
# Excluded Paths

> Paths that agents and grep-based tooling should skip.
> .gitignore-style glob syntax. Comments begin with #.

# Build / dependency trees
node_modules/
vendor/
dist/
build/
target/

# Python / virtualenvs
__pycache__/
.venv/
venv/
*.pyc

# RDF working state (never contains source)
.rdf/work-output/

# Generated spec/plan state (user-local)
docs/specs/
```

### 5b.5 Regenerated `adapters/agents-md/output/AGENTS.md` (excerpt)

```markdown
# AGENTS.md — rfxn Development Framework

Cross-tool project instructions. Generated by `rdf generate agents-md`.

## Project Context

rfxn Development Framework (RDF) — convention governance, agent
pipelines, and project orchestration for the rfxn ecosystem.

## Operating Primitives

- Trust but Verify — cite grep output, file path, or commit hash
  for every "done". Green lint is not correct code...

## Architecture Overview

RDF is organized into 5 categories:
| Category | Role |
|----------|------|
| Canonical | Authoritative content ...

[... continues for ~100 lines total ...]
```

### 5b.6 Error case — dispatcher rejects empty EVIDENCE

Engineer result:
```
STATUS: DONE
PHASE: 4
COMMIT_HASH: xyz9876
FILES_CHANGED: canonical/agents/engineer.md
TDD_EVIDENCE:
  TESTS: tests/adapter.bats::@test "..." (pass)
EVIDENCE:
```

Dispatcher verdict output:
```
Gate 1 — FAIL (structural)
  EVIDENCE block present but empty.
  Re-dispatch with STATUS: NEEDS_CONTEXT, feedback:
  "EVIDENCE block requires at least one citation line when STATUS: DONE.
   Grammar: - <claim>: <path>:<line> | <cmd> → <output> | <sha> <msg>"
```

---

## 6. Conventions

### 6.1 `/r-verify-claim` probe grammar

Each per-class probe entry in r-verify-claim.md is a row:
```
| <claim-class> | <command template with {placeholders}> | <expected pattern> |
```

Claim classes are closed-set:
- `commit-landed` → `git log --oneline {range} | grep -i "{text}"`
- `pattern-absent` → `grep -rn '{pattern}' {path}`
- `pattern-present` → `grep -c '{pattern}' {path}`
- `file-unchanged` → `git diff {ref} -- {path}` returns zero lines
- `behavior-observable` → user-provided command; UNVERIFIABLE verdict if no command supplied

### 6.2 EVIDENCE line format

```
  - <claim>: <citation> [| <citation>]*
```
- 2-space indent (matches existing TDD_EVIDENCE indentation)
- Leading `- ` bullet
- Claim ends at first unescaped colon
- Citation is one of:
  - `<path>:<line>` (no space around colon, relative path)
  - `<cmd> → <output>` (arrow is U+2192 or literal `->`)
  - `<sha> <message>` (7+ char sha, space, commit message snippet)
- Multiple citations separated by ` | ` (space-pipe-space)

### 6.3 REGRESSION_CASE value format

- Named test: `<relative/path>::@test "<name>"` for BATS; `<path>::<function>` for pytest/go; exact framework match acceptable
- N/A form: `N/A — <category> — <reason>` (em-dash separators, both required)

### 6.4 Adapter section config

`sections.json` schema addition: `source: "canonical"` requires:
- `path` (string, relative to RDF_HOME)
- `heading` (string, optional — if set, extract only the named section)
- `max_lines` (int, optional — section-specific cap, else uses file-level default)

### 6.5 Governance file conventions (applied)

- Frontmatter-free canonical markdown (RDF convention)
- Copyright: current year only for new files (`(C) 2026 R-fx Networks`)
- One-line function headers in adapter.sh rewrite (`# name args — purpose`)
- `command <util>` prefix on all coreutils in shell source
- `set -euo pipefail` in adapter.sh (already present)

---

## 7. Interface Contracts

### 7.1 New CLI surface

- `/r-verify-claim <claim>` — new slash command
- `/r-verify-claim --commit <sha> <claim>` — optional commit anchor
- `/r-verify-claim --grep <pattern> <path>` — shortcut for pattern-absent/present class
- `/r-verify-claim --from-finding <sentinel-N.md>` — reviewer convenience

### 7.2 Config format changes

- `adapters/agents-md/sections.json`: `source` values extend from `{static, governance, agents}` to `{static, canonical, agents}`. `governance` removed. This is a **breaking change** to the sections.json schema — but sections.json is shipped by RDF, not user-edited, so no user impact.

### 7.3 File format changes

- `phase-N-result.md` — adds EVIDENCE block between TDD_EVIDENCE and GOVERNANCE_APPLIED. Additive; old result files (without EVIDENCE) remain valid historical records.
- `PLAN.md` phase — adds `Regression-case:` line adjacent to existing metadata fields.
- `.rdf/governance/ignore.md` — new file; no prior file to migrate.
- `adapters/agents-md/output/AGENTS.md` — regenerated; prior content was broken anyway.

### 7.4 Agent dispatch payload changes

- Engineer dispatch: payload now includes REGRESSION_CASE from the target phase.
- QA dispatch: payload includes `scope` field (already present via dispatcher context; new use is EVIDENCE re-validation decision) AND the phase number `N`. QA derives the result file path from `N` using the convention `.rdf/work-output/phase-<N>-result.md` — no new field needed in the payload if `N` is already present.

### 7.5 Contracts unchanged

- Agent dispatcher's scope classification (L64-109): unchanged
- Model routing (L111-131): unchanged
- End-of-plan sentinel protocol (L158-170): unchanged
- `rdf generate claude-code` output paths: unchanged
- `rdf generate agents-md` command existence: unchanged

---

## 8. Migration Safety

### 8.1 Test suite impact

- `tests/adapter.bats`: +5 new @test cases. Existing 7 cases are not modified.
- Test expansion covers: verify-claim command deployment; EVIDENCE grammar parse; REGRESSION_CASE schema validation; ignore-defaults content; agents-md regeneration.

### 8.2 Install/upgrade path

- Fresh install (`rdf init`): gains all 5 primitives by default.
- Existing RDF project (`rdf sync` then next `/r-refresh`): gains `/r-verify-claim` on next `rdf generate claude-code`; gains `ignore.md` on next `/r-refresh` governance scope run (with user-modified merge behavior).
- Consumer-project impact on old PLAN.md files: no change required until next `/r-plan` run. Old plans continue to build via `/r-build` (Regression-case enforcement fires only on phases that have the field — missing-field behavior is backward-compatible with legacy PLAN.md).

**Wait — this contradicts Goal #6.** Resolution: `/r-build` schema check fires only on phases in plans generated after 3.6. Detection: look for a `## Plan Version: 3.6+` preamble marker, or if absent, skip the Regression-case check with an INFO log ("legacy plan — Regression-case not enforced").

### 8.3 Backward compatibility

- Engineer result files without EVIDENCE: dispatcher rejects with NEEDS_CONTEXT. This is a behavior change — phases in-flight at the time of 3.6 deployment will fail their first dispatch. Mitigation: the existing dispatcher retry-loop (max 3 cycles, dispatcher.md L155-157) handles this naturally — the engineer receives the feedback string "EVIDENCE block missing required citation", re-runs, and produces the citation. No grace-period flag is added; the retry loop is already the right mechanism.
- PLAN.md files without Regression-case: /r-build skips the check when no `## Plan Version: 3.6+` marker is present. Existing plans continue to build unchanged.
- Prior `adapters/agents-md/output/AGENTS.md` is overwritten on next `rdf generate all`. Old content was non-functional, so no semantic loss.

### 8.4 Rollback

- Revert commit for each phase is clean (no cross-phase state dependencies except the new grammar references in framework.md).
- Full rollback = revert all 3.6 commits; no persistent state to clean up.

### 8.5 Uninstall

- N/A — RDF has no uninstall path for its own content.
- Consumer projects: `rdf doctor` lists excess artifacts; removing `.rdf/governance/ignore.md` returns the project to pre-3.6 state.

---

## 9. Dead Code and Cleanup

Dead code discovered during codebase reading:

| File | Lines | Finding | Disposition |
|------|-------|---------|-------------|
| `adapters/agents-md/adapter.sh` | 16-57 | `_amd_extract_governance_section` outputs "(governance file not found)" every invocation | DELETE as part of Phase 6 |
| `adapters/agents-md/output/AGENTS.md` | 11 | Literal "(governance file not found)" string in deployed output | OVERWRITTEN by regeneration in Phase 6 |

No other dead code encountered.

---

## 10a. Test Strategy

Each goal maps to at least one test. Tests live in `tests/adapter.bats` (project convention — single bats file for adapter + framework assertions).

| Goal | Test file | Test description |
|------|-----------|------------------|
| 1 (/r-verify-claim deployed) | `tests/adapter.bats` | `@test "r-verify-claim command deploys to claude-code adapter output"` |
| 2+3 (EVIDENCE schema) | `tests/adapter.bats` | `@test "engineer persona declares EVIDENCE block with grammar reference"` |
| 2+3 (dispatcher check) | `tests/adapter.bats` | `@test "dispatcher Gate 1 references EVIDENCE structural check"` |
| 4 (ignore.md) | `tests/adapter.bats` | `@test "r-init generates ignore.md with conservative defaults"` |
| 5+6 (REGRESSION_CASE) | `tests/adapter.bats` | `@test "r-plan template declares Regression-case field"` |
| 5+6 (build validation) | `tests/adapter.bats` | `@test "r-build minimum schema includes Regression-case"` |
| 7 (agents-md fix) | `tests/adapter.bats` | `@test "agents-md output contains no governance-not-found strings"` |
| 8 (rdf doctor clean) | `tests/adapter.bats` | `@test "rdf doctor returns zero FAILs after generate"` — runs `rdf generate agents-md` then `rdf doctor`, asserts FAIL count = 0 and WARN count <= 1 |
| 9 (phase count) | N/A — verified by plan review | Plan structure is enforced by `/r-plan` quality standard (Section 3.1.3 checklist) and human review at plan-approval time; not a code property. Explicitly acknowledged as gap rather than gamed into an automated test. |

Test approach: each test is a string-match assertion against the canonical source file (not the deployed output — that's a separate existing test). Structural assertions, not runtime. Runtime behavior (dispatcher actually rejecting) is validated by the per-phase dispatcher QA gate during `/r-build` execution of Phase 2.

---

## 10b. Verification Commands

Each goal has a one-line verification command with expected output.

```bash
# Goal 1: /r-verify-claim deployed
rdf generate claude-code && ls ~/.claude/commands/r-verify-claim.md
# expect: /root/.claude/commands/r-verify-claim.md

# Goal 2: EVIDENCE block grammar documented
grep -c '^EVIDENCE:' canonical/reference/framework.md
# expect: 1

# Goal 3: dispatcher EVIDENCE structural check documented
grep -c 'EVIDENCE block' canonical/agents/dispatcher.md
# expect: >=1

# Goal 4: ignore.md defaults present
test -f profiles/core/reference/ignore-defaults.md && wc -l profiles/core/reference/ignore-defaults.md
# expect: 40+ lines

# Goal 5: Regression-case in plan template
grep -c '\*\*Regression-case\*\*' canonical/commands/r-plan.md
# expect: >=1

# Goal 6: Regression-case in build schema
grep -c 'Regression-case' canonical/commands/r-build.md
# expect: >=1

# Goal 7: agents-md output clean + substantial
rdf generate agents-md && wc -l adapters/agents-md/output/AGENTS.md
# expect: 60+ lines
grep -c 'governance file not found' adapters/agents-md/output/AGENTS.md
# expect: 0

# Goal 8: rdf doctor clean (split into two checks)
bash bin/rdf doctor 2>&1 | grep -c 'FAIL'
# expect: 0
bash bin/rdf doctor 2>&1 | grep -c 'WARN'
# expect: <=1

# Goal 9: phase count
grep -c '^### Phase ' PLAN.md
# expect: <=7
```

---

## 11. Risks

| # | Risk | Probability | Mitigation |
|---|------|:-----------:|------------|
| R1 | EVIDENCE block becomes boilerplate ("- claim: file.md:1") | Medium | QA re-validation on scope ≥ multi-file catches syntactically-valid-but-semantically-fake evidence. Kill criterion: if QA EVIDENCE_CHECK FAIL rate <5% after 4 weeks, the check isn't catching fraud — redesign. |
| R2 | `/r-verify-claim` generates wrong grep patterns | Medium | Closed-set claim classifier with pre-written probe templates per class. Model chooses the class, not the command. UNVERIFIABLE is a valid verdict. |
| R3 | REGRESSION_CASE enforcement breaks in-flight 3.5 plans | Low | Plan-version marker (§8.2) — legacy plans (no `**Plan Version:** 3.6` preamble) skip the Regression-case check with INFO log. In-flight engineer results use the existing max-3 dispatcher retry loop (§8.3). |
| R4 | Reviewer persona patch causes reviewer to exceed context budget by invoking /r-verify-claim on many findings | Low | Patch is narrowly scoped — only for MUST-FIX with falsifiable runtime claims. Review only includes 2-5 such findings per session on average (source: 2026-03 and 2026-04 sentinel-N.md files). |
| R5 | agents-md rewrite breaks a consumer somehow | Low | Current output is already broken; any output is an improvement. Post-deployment spot-check that `rdf doctor` remains clean. |
| R6 | ignore.md defaults are too aggressive (hide a real bug) | Low | Defaults are the universally-noisy set (node_modules, build artifacts). Users can delete lines they don't want. |
| R7 | Dispatcher NEEDS_CONTEXT verdict loops (engineer can't produce EVIDENCE) | Low | Max 3 retry loops already enforced in dispatcher (L155-157 of existing dispatcher.md). Existing protocol handles this. |

### 11.1 Post-ship kill criteria (from research §4)

Field data from the first 4 weeks of 3.6 deployment drives whether each primitive keeps its spot. Record in MEMORY.md at each measurement point.

- **/r-verify-claim** — drop if >30% of invocations produce commands that error (generated grep pattern invalid, file path nonexistent, etc.). Measurement: grep `.rdf/work-output/agent-feed.log` for `/r-verify-claim` invocations and count those that emit FAIL or UNVERIFIABLE *due to tool error* vs legitimate claim-falsification.
- **EVIDENCE schema** — drop (or redesign) if QA EVIDENCE_CHECK FAIL rate < 5% after 4 weeks. Rationale: a gate that never bites is ceremony. Measurement: count `EVIDENCE_CHECK: FAIL` occurrences in `qa-phase-N-verdict.md` files.
- **.rdf/governance/ignore.md** — drop or narrow defaults if a post-mortem ever cites "bug was in an ignored path". Also revisit defaults quarterly based on user-modification patterns across consumer projects.
- **REGRESSION_CASE** — drop if qa verdicts with regression-PASS are accompanied by real-world regressions landing. Measurement: cross-reference revert commits against the REGRESSION_CASE field of their original phase.
- **agents-md adapter** — drop if `rdf doctor` never flags a drift that the adapter was supposed to catch. (This one has the weakest kill criterion — the adapter is mostly maintenance infrastructure.)

---

## 11b. Edge Cases

| Scenario | Expected behavior | Handling |
|----------|-------------------|----------|
| Engineer STATUS: BLOCKED, no EVIDENCE | Accept result; EVIDENCE is required only for DONE/DONE_WITH_CONCERNS | Dispatcher Gate 1 check: STATUS predicate gates the EVIDENCE requirement |
| PLAN.md without `Plan Version: 3.6+` marker (legacy) | `/r-build` skips Regression-case check with INFO log | Version-aware schema validation in r-build.md |
| `/r-verify-claim` invoked on a claim with no probe class | Emit UNVERIFIABLE verdict with suggestion to provide `--commit` or rephrase | Classifier returns `unknown` → output template includes fallback guidance |
| `.rdf/governance/ignore.md` exists before /r-init runs | Treat as user-modified; append only new entries under "# Added by /r-init" heading | Same merge rule as constraints.md / anti-patterns.md (existing pattern) |
| Agents-md source file (framework.md) has renamed section | Adapter extract function returns empty; fallback message rather than silent blank | `_amd_extract_canonical_section` returns "(section not found: <heading>)" — visible failure, not silent |
| Engineer result has EVIDENCE with claim-only lines (no citation after colon) | Reject as malformed | Dispatcher Gate 1 structural check regex requires non-empty right-of-colon |
| REGRESSION_CASE references a test that doesn't exist at build time | /r-build logs WARN but proceeds (engineer may create the test during the phase) | Gate 2 (QA) runs the referenced test and catches non-existence |
| `/r-verify-claim` invoked inside reviewer agent (subagent context) | Works — command is deployed, subagent can slash-invoke | Existing skill/slash-command invocation pattern; no new wiring |
| Multiple EVIDENCE lines with the same claim text | Accept — deduplicating is caller's responsibility | Structural check counts non-empty lines, doesn't enforce uniqueness |
| `adapters/agents-md/sections.json` user-edited to old governance source | Adapter emits warning "source 'governance' deprecated; use 'canonical'"; falls back to the 'static' path if present | Backward-compat path in amd_generate_all switch |

---

## 12. Open Questions

None. All design questions were resolved in Phase 2 brainstorm and recorded in `.rdf/work-output/spec-progress.md`.

---

## Appendix A — Plan Preview (for /r-plan)

Sketch for the planner (not binding):

- **Phase 1:** Add `EVIDENCE:` to engineer result schema in `canonical/reference/framework.md` + patch `canonical/agents/engineer.md §Evidence`.
- **Phase 2:** Add dispatcher Gate 1 structural check in `canonical/agents/dispatcher.md`. Add QA re-validation (scope-gated) in `canonical/agents/qa.md`.
- **Phase 3:** Add `Regression-case:` to `canonical/commands/r-plan.md` phase template + quality checklist. Update `canonical/commands/r-build.md` minimum schema + category validation.
- **Phase 4:** Create `canonical/commands/r-verify-claim.md`. Patch `canonical/agents/reviewer.md §Challenge Mode` to reference it.
- **Phase 5:** Create `profiles/core/reference/ignore-defaults.md`. Patch `canonical/commands/r-init.md` with Generate: ignore.md step. Patch `canonical/commands/r-refresh.md` to include `ignore.md` in per-file refresh list (Stage 3b).
- **Phase 6:** Rewrite `adapters/agents-md/adapter.sh` + `sections.json`. Run `rdf generate agents-md` to regenerate output.
- **Phase 7:** Add 5 @test cases to `tests/adapter.bats`. Run `rdf doctor` and `tests/Makefile` locally. Update `CHANGELOG` + `CHANGELOG.RELEASE` + `VERSION` to 3.6.0.

Dependencies: Phase 1 blocks Phase 2 (dispatcher references schema). Others are independent of each other; can run parallel batch {3, 4, 5, 6} after {1, 2}. Phase 7 depends on all.

---

## Appendix B — Files Explicitly NOT Touched

Lists enforced by reviewer to prevent scope creep:

- `canonical/commands/r-ship.md`
- `canonical/commands/r-vpe.md`
- `canonical/commands/r-audit.md`
- `canonical/commands/r-audit-slop.md`
- `canonical/commands/r-spec.md` (REGRESSION_CASE lives in PLAN, not spec)
- `canonical/commands/r-save.md`
- `canonical/commands/r-start.md`
- `lib/cmd/generate.sh` (no wire changes needed)
- `lib/cmd/init.sh` (no shell-side changes; all init changes live in canonical/commands/r-init.md)
- `lib/cmd/deploy.sh`
- `lib/cmd/doctor.sh`
- `lib/cmd/sync.sh`
- `bin/rdf`
- `state/*.sh`
- `adapters/claude-code/**` — adapter is regenerated automatically by `rdf generate claude-code`; no manual edits
- `adapters/codex/**`
- `adapters/gemini-cli/**`
- `modes/**`
- `WORKFORCE.md`, `RDF.md`, `README.md` (except version bump in Phase 7)
- `.github/workflows/ci.yml` (no CI changes in 3.6)
