# Implementation Plan: Reviewer ROI Improvements — 3.1.1

**Goal:** Recover ~5–6 reviewer-hours per major build cycle by pre-empting upstream the three classes of findings reviewer absorbed in the blacklight corpus (~106 distinct findings, ~11.7 active reviewer hours over 53 stops).

**Three areas:**

| Area | Change | Findings prevented |
|------|--------|--------------------|
| A. Plan validation | Plan-schema Rule 9 (test-count self-consistency) + planner protocol step that pins helper rc-contracts in the plan preamble | 35 spec/plan defects |
| B. Scope-aware sentinel | Reviewer Sentinel `target-class` switch + early-exit when Pass 1+2 are clean | over-deployed full sentinels |
| C. Build-time hygiene + boundary-guard | Pre-commit hook anti-pattern grep (extension of Wave A hook) + engineer Setup step for input-boundary sweep on cross-cutting/sensitive phases | ~25 hygiene + security findings |

**Architecture:** 5 phases. Most edits are prose protocol additions to existing agent and command markdown files (planner.md, reviewer.md, dispatcher.md, engineer.md, r-plan.md, r-build.md, plan-schema.md). One phase modifies the existing pre-commit hook with bash code + a small BATS suite. No new skills, no separate reference docs — the protocol prose lives in the agent files where it executes. Final phase is the release.

**Tech Stack:** Bash 4.1+ (CentOS 6 floor), markdown (canonical content; frontmatter-free), BATS via existing batsman submodule.

**Spec:** None — design rationale embedded in this plan's preamble. See blacklight reviewer-findings digest (memory) for empirical findings catalog.

**Phases:** 5

**Plan Version:** 3.0.6

---

## Conventions

**Commit message format:** Free-form descriptive (RDF — no version prefix). Tag body lines with `[New]` `[Change]` `[Fix]`. One commit per phase.

**Canonical content:** All edits to `canonical/**/*.md` are frontmatter-free. Adapter regen (`rdf generate claude-code`) happens in P5 only.

**Staging:** `git add <path>` explicitly per file. `docs/plans/` and `docs/specs/` ARE committed (per RDF CLAUDE.md); other working files (`PLAN.md`, `MEMORY.md`, `.rdf/`) are excluded via `.git/info/exclude`.

**CHANGELOG / CHANGELOG.RELEASE:** P5 batches all entries into a single 3.1.1 section.

**Shell standards:** `#!/usr/bin/env bash`, `set -euo pipefail`, `command cp/mv/rm/cat`, double-quote variables.

**Version bump:** 3.1.0 → 3.1.1. Patch — additive primitives. Rule 9 is conditional (existing plans without count assertions are unaffected). Target-class defaults to `code` (current 3-pass behavior). Pre-commit hook patterns are opt-in per-project via `governance/ignore.md`.

**CRITICAL — do NOT:**
- Touch Wave B / Wave C primitives.
- Add new skill files (`/r-util-*`) — protocol prose belongs in the agent files where it executes.
- Modify `lib/cmd/`, `bin/rdf`, or `adapters/*/adapter.sh`.
- Edit `~/.claude/` directly — canonical only, regen in P5.
- Land Rule 9 as STRICT — must be CONDITIONAL on count-assertion presence.
- Change reviewer behavior on existing `code`-class dispatches — target-class defaults preserve current 3-pass.

---

## File Map

### New Files
| File | Lines | Purpose | Test File |
|------|------:|---------|-----------|
| `tests/pre-commit-anti-patterns.bats` | ~80 | 5 BATS tests: clean fixture passes; bare-coreutils blocks; suppression-no-comment blocks; same-line `#` suppresses; `governance/ignore.md` opts-out per pattern class | N/A |
| `tests/fixtures/pre-commit-anti-patterns/clean.sh` | ~10 | Fixture: passes all patterns | N/A |
| `tests/fixtures/pre-commit-anti-patterns/dirty.sh` | ~10 | Fixture: triggers each anti-pattern | N/A |

### Modified Files
| File | Changes | Test File |
|------|---------|-----------|
| `canonical/reference/plan-schema.md` | Add Rule 9: phase test-count self-consistency. Conditional rule (fires only when phase asserts a test count). Failure-message format and three-call-site enforcement parity with Rule 8. | `tests/adapter.bats` |
| `canonical/agents/planner.md` | Add Step 1.5 ("RC-contract evidence"): for every caller-helper-fn referenced in the plan, planner reads the helper's body in source and pastes a per-call-site rc table into the plan preamble. Inline grep instructions — no separate skill. | `tests/adapter.bats` |
| `canonical/agents/reviewer.md` | Sentinel Mode: add `target-class` switch (`prose | code | schema | mixed`) with per-class default severity ladders; add Early-Exit rubric (Pass 1+2 clean + diff <300 lines + no security/hot-path file → skip Pass 3). Challenge Mode: reference Rule 9 + verify "RC Contract Evidence" presence. | `tests/adapter.bats` |
| `canonical/agents/dispatcher.md` | Sentinel-dispatch: derive `target-class` from phase scope + file extensions (`.md` → prose, `.json/.yaml` → schema, source files → code, mixed → mixed); pass via dispatch payload. | `tests/adapter.bats` |
| `canonical/agents/engineer.md` | Setup: add step 7 ("Boundary-guard sweep"). On `scope:cross-cutting` or `scope:sensitive` phases, engineer greps schema directories for input fields lacking `pattern`/`enum`/`format` constraints, cross-references against call-site sinks (filesystem path, shell command, JSONL append), and pastes the result table into EVIDENCE. Inline grep instructions — no separate skill. | `tests/adapter.bats` |
| `canonical/commands/r-plan.md` | Step 2.7: add Rule 9 check + RC-contract-evidence section presence check; halt before reviewer dispatch on either failure. | `tests/adapter.bats` |
| `canonical/commands/r-build.md` | §1: add Rule 9 check (parity with /r-plan Step 2.7). | `tests/adapter.bats` |
| `state/git-hooks/pre-commit` | Append anti-pattern grep section after the existing scope-enforcement block. Patterns: bare-coreutils-no-prefix, `$$`/`$RANDOM` in `/tmp` paths, `2>/dev/null` w/o same-line `#`, tombstone phrases (`replaces .* stub`, `was: .*`, `# removed:`), `local var=$(...)` rc-mask. Same-line `#` suppresses; `governance/ignore.md` `# anti-pattern-skip: <class>` opts-out per class. Pattern table inline as comments — no separate reference doc. | `tests/pre-commit-anti-patterns.bats` |
| `tests/adapter.bats` | Add cases verifying canonical edits regenerate (Rule 9, planner Step 1.5, reviewer target-class + early-exit, dispatcher target-class derivation, engineer Setup step 7, r-plan/r-build Rule 9 wiring). | N/A |
| `VERSION` | 3.1.0 → 3.1.1 | N/A |
| `RDF.md` | Version reference 3.1.1 | N/A |
| `README.md` | Version badge 3.1.1 | N/A |
| `CHANGELOG` | New `## 3.1.1` section | N/A |
| `CHANGELOG.RELEASE` | New `## 3.1.1` release-notes section | N/A |

### Deleted Files
None.

---

## Phase Dependencies

- P1 (Plan validation: Rule 9 + planner Step 1.5 + r-plan/r-build/reviewer-challenge wiring): none
- P2 (Scope-aware sentinel: reviewer target-class + early-exit + dispatcher derivation): none
- P3 (Pre-commit hook anti-pattern extension): none
- P4 (Engineer boundary-guard Setup step): none
- P5 (Release): [P1, P2, P3, P4]

```
   P1 ──┐
   P2 ──┤
   P3 ──┼── P5 (release)
   P4 ──┘
```

Eligible parallel batches:
- Batch 1: [P1, P2, P3, P4] — all independent
- Batch 2: [P5]

---

### Phase 1: Plan validation discipline — Rule 9 + planner RC-contract evidence

Bundle all Area A changes into one phase. Add Rule 9 to plan-schema.md (conditional test-count self-consistency rule). Add Step 1.5 to planner.md (planner greps source for every caller-helper-fn referenced in the plan, extracts rcs from case-statement / return paths, pastes table into plan preamble's "RC Contract Evidence" section). Wire Rule 9 + RC-evidence presence into r-plan.md Step 2.7, r-build.md §1, and reviewer.md Challenge Mode. All edits are markdown only.

**Files:**
- Modify: `canonical/reference/plan-schema.md` (test: `tests/adapter.bats`)
- Modify: `canonical/agents/planner.md` (test: `tests/adapter.bats`)
- Modify: `canonical/agents/reviewer.md` (test: `tests/adapter.bats`)
- Modify: `canonical/commands/r-plan.md` (test: `tests/adapter.bats`)
- Modify: `canonical/commands/r-build.md` (test: `tests/adapter.bats`)

- **Mode**: serial-agent
- **Accept**: plan-schema.md contains "Rule 9: Phase Test-Count Self-Consistency" with trigger condition, counter logic, failure message, and three-call-site enforcement table parity. planner.md contains "Step 1.5: RC-contract evidence" with inline grep instructions (no skill reference). reviewer.md Challenge Mode references Rule 9 + RC-evidence section. r-plan.md Step 2.7 and r-build.md §1 both run Rule 9 validation. Adapter regen produces matching output.
- **Test**: `tests/adapter.bats::@test "plan-schema Rule 9 regenerates"`, `::@test "planner Step 1.5 regenerates"`, `::@test "reviewer challenge cites Rule 9"`, `::@test "r-plan Step 2.7 cites Rule 9"`, `::@test "r-build §1 cites Rule 9"`. Run with `bats tests/adapter.bats` — expect 5 tests pass.
- **Edge cases**: phase asserts test count via prose only ("11 tests cover this") — Rule 9 must extract the integer; phase has multiple heredocs with own counts — Rule 9 sums; phase asserts a count for a future test ("expect: 14 tests after P3") — Rule 9 honors `**TODO:**` markers and skips; planner Step 1.5 short-circuits if no caller-helper-fn names appear in the plan; ambiguous helper resolution (multiple definitions of same name) — planner picks the first match and logs ambiguity.
- **Regression-case**: N/A — refactor — content-additive plan-schema rule (Rule 9 conditional; existing plans unaffected) and additive planner protocol step.

- [ ] **Step 1: Add Rule 9 to plan-schema.md** — between Rule 8 and "Adding a New Rule" section. Subsections: 9a (trigger — count assertion present), 9b (counter logic — count `@test` blocks + `# expect:` lines + heredoc counts), 9c (mismatch detection + failure message), 9d (three-call-site enforcement, parity with Rule 8 table).
- [ ] **Step 2: Add Step 1.5 to planner.md** — between current Step 1 and Step 2. Specify: when to run (any plan referencing caller-helper-fns), how to find helpers (grep source for `^<name> *\(\)` + `def <name>` + `func <name>`), how to extract rcs (case-statement parse for bash; return-tuple grep for python; switch parse for go), output table format (`call-site-file:line | helper | expected-rc | rc-source`), placement in plan preamble.
- [ ] **Step 3: Edit reviewer.md Challenge Mode** — add sub-step "Verify Rule 9 + RC Contract Evidence presence" with example failure shape.
- [ ] **Step 4: Edit r-plan.md Step 2.7** — add Rule 9 check + RC-evidence-section presence check; halt before reviewer dispatch on either failure.
- [ ] **Step 5: Edit r-build.md §1** — add Rule 9 check (parity with r-plan).
- [ ] **Step 6: Verify** — markdown-only; spot-check by greping `Rule 9`, `Step 1.5`, `RC Contract Evidence` across edited files.
- [ ] **Step 7: Commit** — message: `Plan validation: add Rule 9 (test-count consistency) + planner Step 1.5 (RC-contract evidence)`. Body tags: `[New]` for Rule 9 + Step 1.5, `[Change]` for r-plan/r-build/reviewer wiring.

---

### Phase 2: Scope-aware sentinel — target-class switch + early-exit + dispatcher derivation

Bundle Area B. Add `target-class` switch to reviewer.md Sentinel Mode with per-class default severity ladders (`prose | code | schema | mixed`). Add Early-Exit rubric (Pass 1+2 clean + diff <300 lines + no security/hot-path file → skip Pass 3). Update dispatcher.md to derive target-class from phase scope + file extensions and pass via the sentinel dispatch payload. All edits are markdown only.

**Files:**
- Modify: `canonical/agents/reviewer.md` (test: `tests/adapter.bats`)
- Modify: `canonical/agents/dispatcher.md` (test: `tests/adapter.bats`)

- **Mode**: serial-agent
- **Accept**: reviewer.md Sentinel Mode contains target-class switch table (per-class default severities for each pass) + Early-Exit rubric subsection (four required conditions) + verdict marker `pass_3_skipped: true` when applicable. dispatcher.md sentinel-dispatch section contains target-class derivation pseudocode (extension table + fallback rule) + payload example showing `target_class: <derived>`. Adapter regen produces matching output.
- **Test**: `tests/adapter.bats::@test "reviewer target-class switch present"`, `::@test "reviewer Early-Exit rubric present"`, `::@test "dispatcher target-class derivation present"`, `::@test "dispatcher payload includes target_class"`. Run with `bats tests/adapter.bats` — expect 4 tests pass.
- **Edge cases**: target-class default is `code` (preserves current 3-pass behavior on every dispatch that does not specify target-class); Early-Exit requires ALL four conditions; mismatched signal — reviewer falls back to `code` and logs warning; phase touches only `.md` → `prose`; phase has no Files declaration (legacy plan) → `code` fallback; mixed source + schema → `mixed` (max-of-any default ladder).
- **Regression-case**: N/A — refactor — additive switch with default that preserves current behavior.

- [ ] **Step 1: Edit reviewer.md** — Sentinel Mode section: insert target-class switch table (4 rows × 3 passes); Early-Exit rubric subsection with the four conditions and the `pass_3_skipped` verdict marker; for the `prose` row, push anti-slop and regression severities to INFO defaults.
- [ ] **Step 2: Edit dispatcher.md** — sentinel-dispatch section: insert target-class derivation pseudocode (extension dispatch table: `.md`→prose, `.json/.yaml/.proto`→schema, source files→code, mixed→mixed; fallback `code` if all extensions unrecognized); update payload example to include `target_class: <derived>`.
- [ ] **Step 3: Verify** — markdown-only; grep `target-class`, `target_class:`, `pass_3_skipped`.
- [ ] **Step 4: Commit** — message: `Sentinel: target-class switch + early-exit rubric + dispatcher derivation`. Body tags: `[New]` for target-class + Early-Exit, `[Change]` for sentinel-dispatch payload.

---

### Phase 3: Pre-commit hook — anti-pattern grep extension

Append anti-pattern grep section to `state/git-hooks/pre-commit` after the existing scope-enforcement block. Pattern table inline as bash comments. Same-line `#` justification suppresses; `governance/ignore.md` `# anti-pattern-skip: <class>` opts-out per class.

**Files:**
- Modify: `state/git-hooks/pre-commit` (test: `tests/pre-commit-anti-patterns.bats`)
- Create: `tests/pre-commit-anti-patterns.bats` (test: N/A — is the test file)
- Create: `tests/fixtures/pre-commit-anti-patterns/clean.sh` (test: N/A — fixture)
- Create: `tests/fixtures/pre-commit-anti-patterns/dirty.sh` (test: N/A — fixture)

- **Mode**: serial-agent
- **Accept**: hook contains anti-pattern section after existing scope check. Five pattern classes covered: bare-coreutils-no-prefix (`\b(sha256sum|md5sum|cp|mv|rm|chmod|mkdir|cat|touch|ln)\b` without `command ` prefix), tmp-file-with-pid (`/tmp/[^"]*\$\$|/tmp/[^"]*\$RANDOM`), suppression-no-comment (`2>/dev/null` and `\|\| true` lines without same-line `#`), tombstone-phrases (`replaces .* stub|was: .*|# removed:`), local-rc-mask (`^\s*local [a-z_]+=\$\(`). Suppression and opt-out work. `bash -n` and `shellcheck` clean on the modified hook. All BATS tests pass.
- **Test**: `tests/pre-commit-anti-patterns.bats::@test "clean fixture passes"`, `::@test "bare-coreutils blocks"`, `::@test "same-line # suppresses"`, `::@test "ignore.md anti-pattern-skip opts-out per class"`, `::@test "scope-check ordering preserved (scope first, anti-pattern second)"`. Run with `bats tests/pre-commit-anti-patterns.bats` — expect 5 tests pass.
- **Edge cases**: hook processes only staged files (incremental); suppression `#` must be on the same line; opt-out reads `governance/` from project root, not from worktree (the hook may be inside `.git/worktrees/<name>/hooks/`); word-boundary regex (`\bsha256sum\b`) avoids matching `sha256sum_helper`; printf/echo are bash builtins — exclude from coreutils pattern; vendored libraries (per parent CLAUDE.md, advisory-only) — opt-out class for vendor paths.
- **Regression-case**: `tests/pre-commit-anti-patterns.bats::@test "scope-check ordering preserved (scope first, anti-pattern second)"` — guards Wave A scope-enforcement path is unchanged.

- [ ] **Step 1: Write fixtures** — `clean.sh` (~10 lines, all patterns clean) and `dirty.sh` (~10 lines triggering each anti-pattern; one comment per pattern indicating which it triggers).
- [ ] **Step 2: Write BATS file** — 5 tests per Test field above. RED phase.
- [ ] **Step 3: Run BATS, confirm RED** — expect failures (hook unchanged).
- [ ] **Step 4: Edit `state/git-hooks/pre-commit`** — append anti-pattern section after existing scope check. Use parallel indexed arrays for pattern classes (no `declare -A` global state per shell standards). For each staged file, iterate patterns; grep with word-boundary regex; suppress via same-line `#`; opt-out via `governance/ignore.md` parse.
- [ ] **Step 5: Run BATS, confirm GREEN** — all 5 pass.
- [ ] **Step 6: Verify** — `bash -n state/git-hooks/pre-commit`, `shellcheck state/git-hooks/pre-commit`. Manual sanity: stage a fixture and run the hook directly.
- [ ] **Step 7: Commit** — message: `Pre-commit hook: extend with anti-pattern grep section`. Body tags: `[Change]` for hook, `[New]` for bats + 2 fixtures.

---

### Phase 4: Engineer Setup — boundary-guard sweep step

Add Setup step 7 to engineer.md. On `scope:cross-cutting` or `scope:sensitive` phases, engineer greps schema directories for input fields lacking `pattern`/`enum`/`format` constraints, cross-references against call-site sinks (filesystem path, shell command, JSONL append), and pastes the result table into EVIDENCE. Inline grep instructions — no separate skill file. Markdown only.

**Files:**
- Modify: `canonical/agents/engineer.md` (test: `tests/adapter.bats`)

- **Mode**: serial-agent
- **Accept**: engineer.md Setup section contains step 7 with: (a) trigger conditions (`scope:cross-cutting` or `scope:sensitive`), (b) inline grep instructions (find schemas in `schemas/` or `*.json` near source; jq-extract field names; for each field, grep call sites for unguarded paths reaching `/tmp/`, shell commands, JSONL appends; cross-reference against the schema's `pattern`/`enum`/`format`), (c) EVIDENCE table format (`field | source-schema | call-site | guard? | sink-class | risk`), (d) resolution requirement (add guard or cite refute-evidence per EVIDENCE schema). Adapter regen produces matching output.
- **Test**: `tests/adapter.bats::@test "engineer Setup step 7 boundary-guard present"`. Run with `bats tests/adapter.bats` — expect 1 test pass.
- **Edge cases**: phase has no schema files in scope (step 7 short-circuits with INFO marker, no MUST-FIX from missing-schema); phase declares `scope:focused` (step 7 does not run — current Setup unchanged); refute-evidence shape must match EVIDENCE schema (`<claim>: <path>:<line>`); engineer pastes the full table even when 0 findings (proof-of-execution); step 7 runs after the Pre-aggregation Precondition (Wave A's Setup addition).
- **Regression-case**: N/A — refactor — additive Setup step gated on scope class.

- [ ] **Step 1: Read current engineer.md** — find Setup section + numbered step list; note current step count and Pre-aggregation Precondition placement.
- [ ] **Step 2: Draft step 7 prose** — trigger conditions, inline grep recipe (schema discovery + field extraction + sink heuristics + cross-reference), EVIDENCE table format, resolution requirement.
- [ ] **Step 3: Edit engineer.md** — insert step 7 after the Pre-aggregation Precondition step.
- [ ] **Step 4: Verify** — markdown-only; grep `Step 7: Boundary-guard sweep`.
- [ ] **Step 5: Commit** — message: `Engineer: add Setup step 7 boundary-guard sweep on cross-cutting/sensitive phases`. Body tag: `[New]`.

---

### Phase 5: Release — adapter regen, version bump, CHANGELOG, sentinel review

Aggregate release. Run `rdf generate claude-code` to regenerate adapter output; bump VERSION 3.1.0 → 3.1.1; update RDF.md + README.md version references; write CHANGELOG and CHANGELOG.RELEASE entries batching all 4 prior phases; verify `rdf doctor --all` is clean; dispatch end-of-plan sentinel.

**Files:**
- Modify: `VERSION` (test: N/A — release metadata)
- Modify: `RDF.md` (test: N/A)
- Modify: `README.md` (test: N/A)
- Modify: `CHANGELOG` (test: N/A)
- Modify: `CHANGELOG.RELEASE` (test: N/A)
- Generate (no commit): `adapters/claude-code/output/**` via `rdf generate claude-code`

- **Mode**: serial-agent
- **Accept**: VERSION reads `3.1.1`; README.md badge says `3.1.1`; RDF.md VERSION comment says `3.1.1`; CHANGELOG has new `## 3.1.1` section with batched [New]/[Change] entries from P1–P4; CHANGELOG.RELEASE has new `## 3.1.1` release-notes section summarizing the three Areas; adapter output regenerates without errors; `rdf doctor --all` returns 0; end-of-plan sentinel verdict APPROVE (≤2 cosmetic SHOULD-FIX acceptable; 0 MUST-FIX).
- **Test**: `tests/adapter.bats` full suite passes; `bash -n` and `shellcheck` clean; `rdf doctor --all` exits 0; `/r-review --sentinel --diff main..HEAD` → APPROVE.
- **Edge cases**: per Wave A memory entry, deployment was rolled back during concurrent sessions — operator must verify no concurrent sessions remain before running `rdf generate`; if MUST-FIX surfaces from sentinel, fixup commit lands before P5 closes; CHANGELOG.RELEASE summary should note backwards-compat statements (target-class default `code`; Rule 9 conditional; hook anti-pattern check opt-in via ignore.md).
- **Regression-case**: N/A — docs — release-metadata-only commit; no behavior change.

- [ ] **Step 1: Pre-flight** — verify no concurrent Claude Code sessions on RDF before regen.
- [ ] **Step 2: Run `rdf generate claude-code`** from `/root/admin/work/proj/rdf`.
- [ ] **Step 3: Bump VERSION** — `3.1.0` → `3.1.1`.
- [ ] **Step 4: Update RDF.md + README.md** — version references.
- [ ] **Step 5: Write CHANGELOG entry** — new `## 3.1.1` section batching P1–P4 under [New]/[Change] tags.
- [ ] **Step 6: Write CHANGELOG.RELEASE entry** — new `## 3.1.1` release-notes section: three Areas summary, motivating evidence, backwards-compat statement.
- [ ] **Step 7: Run `rdf doctor --all`** — expect exit 0.
- [ ] **Step 8: Dispatch end-of-plan sentinel** — `/r-review --sentinel --diff main..HEAD`; if findings, fix in a follow-on commit before merge.
- [ ] **Step 9: Verify** — `git log --oneline -6` shows 4 phase commits + release commit (+ sentinel-fixup if any).
- [ ] **Step 10: Commit** — message: `Version 3.1.1 — Reviewer ROI Improvements release`. Body: brief three-Areas summary; tags `[Change]` for VERSION/RDF.md/README, `[New]` for CHANGELOG sections.

---

## Risk Assessment

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| Pre-commit hook produces false positives, blocks legitimate commits | Medium | High | P3 fixtures cover suppression + opt-out paths; opt-in via `governance/ignore.md`; suppression on same-line `#` |
| Rule 9 incorrectly fires on plans without count assertions | Low | Medium | Rule 9 trigger is explicit (count present); reviewer falls back to advisory if ambiguous |
| Target-class signal mismatched between dispatcher and reviewer | Low | Low | reviewer fallback to `code` on missing/invalid signal |
| Boundary-guard sweep finds many existing violations on first run in rfxn projects | Medium | Medium | Step 7 gated on cross-cutting/sensitive scopes; refute-evidence path is escape valve |
| Adapter regen during P5 collides with concurrent Claude Code session on RDF | Medium | Medium | Pre-P5 step verifies no concurrent sessions |

---

## Success Metrics

- 5 phases land on main (or feature branch then merged) — one commit per phase + 1 release commit (+ optional sentinel fixup).
- `rdf doctor --all` returns 0 after P5.
- End-of-plan sentinel returns APPROVE.
- Smoke test against blacklight reviewer-findings corpus: Rule 9 catches the PLAN-M8 13-vs-14 typo; planner Step 1.5 catches the `bl_api_call` 65-vs-71 rc mismatch; target-class skips Pass 3 on the M6 P1 clean diff; hook blocks the bare-`sha256sum` from spM8 finding 5; engineer Setup step 7 flags the `step_id`/`case_id`/`--user`/`--reason` paths from M9.5.

---

## Out of Scope (defer to follow-on)

- Wave B / Wave C concurrent-sessions primitives.
- MUST-FIX qualifier collapse (originally bundled with target-class) — separate concern, defer.
- Counter-Hypothesis tightening (E8) — indirect effect, defer.
- Schema-enum reconciliation gate (E4) — separate plan.
- Per-flag spec-time table (E6) — blacklight-shaped, next /r-spec primitive update.
- Default-on hook for upstream rfxn projects — opt-in until FP rate baselined.
