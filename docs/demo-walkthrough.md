# RDF Workflow Demo

A walkthrough of the spec-plan-build-ship pipeline using a real
development scenario on Linux Malware Detect (LMD) — a production
malware scanner deployed on ~350,000 servers.

RDF is the governance layer, not a runtime. Claude Code is the
runtime. RDF tells it how to behave via governance files, agent
definitions, and quality gates.

---

## The Scenario

LMD's compound signature (CSIG) scanner is 75-94x slower than it
needs to be. Each file spawns 310,000 subshell forks through
separate HEX and CSIG batch workers. We need to merge them into a
single pass that extracts hex once and runs both matching stages on
the same buffer.

This is a real change that shipped in LMD v2.0.1.

---

## 1. `/r-start` — Session Initialization

Load project context in one command. The state helper (`rdf-state.sh`)
returns a JSON snapshot in <100ms — no LLM calls, no file scanning.

```
you: /r-start
```

```markdown
### LMD 2.0.1 — `2.0.1` @ `badb200` (4h ago) · idle

| Plan | Dirty | Mode | Governance |
|------|-------|------|------------|
| — | 0 files | development | 6 files (2h) |

- `badb200` [Fix] Audit remediation batch 4: F-015, S-002, S-003 *(4h)*
- `398f97f` [Fix] Audit remediation batch 3: F-012, F-013, F-014 *(5h)*
- `ce90a12` [Fix] Audit remediation batch 2: F-004, F-005, F-006 *(6h)*

CLAUDE.md loaded.
```

One block, under 20 lines. Project version, branch, HEAD, age,
pipeline position — all from a single JSON call. No plan active,
governance is fresh, working tree is clean. Ready to work.

---

## 2. `/r-spec` — Design

The spec command runs an interactive three-phase design workflow:
discover the problem space, brainstorm options with research, then
write and challenge-review the spec.

```
you: /r-spec
     "CSIG scanning is way too slow — we need to merge the HEX and
      CSIG batch workers into a single pass"
```

### Phase 1: Discover

The agent reads governance files (architecture, constraints,
anti-patterns) and scopes the work.

```markdown
### Scope Assessment

| Property     | Value                                           |
|--------------|-------------------------------------------------|
| Area         | Scan engine — HEX + CSIG batch workers          |
| Files        | `files/internals/functions` (lines 3100-3400)   |
| Constraints  | Bash 4.1 floor, mawk compat, 8 OS targets       |
| Tests        | `tests/03-scan-hex.bats`, `tests/29-scan-csig.bats` |
| Risk         | High — core scan pipeline, performance-critical  |
| Type         | Single spec                                      |

Proceed with design? [Y/n]
```

```
you: y
```

### Phase 2: Brainstorm

The agent identifies key design questions and researches each one.
For each question: options with trade-offs, a recommendation, and
your decision recorded for crash safety.

```markdown
**Q1: Worker merge strategy**

| Option | Description | Pros | Cons |
|--------|-------------|------|------|
| A | Merge at caller level | Simple, keep existing workers | Still 2 passes over files |
| B | Single worker, shared hex buffer | One extraction, two match stages | Larger function, more complex |
| C | Pipeline: hex → HEX match → CSIG match | Stream-based, composable | Extra IPC overhead |

Recommendation: **B** — eliminates the 310K fork bottleneck at the
source. One hex extraction feeds both matching stages in memory.

Your choice?
```

```
you: B — and we should benchmark the POC against the current
     implementation on a real scan of ~10k files
```

```markdown
Recorded: Q1 → Option B (single worker, shared hex buffer) + POC benchmark requirement

**Q2: CSIG rule evaluation model**
...
```

After 5-6 design questions are resolved:

```markdown
### Decision Summary

| Question | Choice | Rationale |
|----------|--------|-----------|
| Q1: Worker merge | B: Single worker | Eliminates 310K forks |
| Q2: Rule evaluation | Set-based | Process all rules per file, not per rule |
| Q3: Subsig dedup | Compile-time | Dedup shared hex patterns during sig compilation |
| Q4: Progress reporting | Merged label | "hex+csig" when both active |
| Q5: Backward compat | Feature-gated | `scan_csig_batch=1` default, fallback to legacy |

All questions resolved. Proceed to spec? [Y/n]
```

### Phase 3: Write + Challenge

The agent reads all code in scope, writes a full spec, then dispatches
the **reviewer** in challenge mode to stress-test the design.

```markdown
Spec written: `docs/specs/2026-03-17-csig-batch-engine-design.md`
12 sections | 847 words | 3 risks identified | 5 edge cases

Dispatching challenge review...
```

The reviewer examines the spec against 12 quality criteria:

```markdown
### Challenge Review — 2 findings

**BLOCKING**: POC benchmark section references `_csig_batch_worker()`
but the merged function is named `_hex_csig_batch_worker()` in the
architecture section. Inconsistent naming will confuse implementation.

**CONCERN**: Edge case table doesn't address empty CSIG ruleset
(scan_csig=0 but csig.dat present). What happens in the merged worker?

Fixing BLOCKING finding... Updated spec. Re-dispatching review...

Review: PASS — 0 blocking, 1 concern (presented above). Proceed? [Y/n]
```

```
you: the concern is valid — add a guard that skips CSIG matching
     when scan_csig=0, even if csig.dat exists
```

```markdown
Updated edge case table. Spec committed.

> Spec complete — `docs/specs/2026-03-17-csig-batch-engine-design.md`
> Run `/r-plan` to decompose into implementation phases.
```

**Artifacts:**
- `docs/specs/2026-03-17-csig-batch-engine-design.md` (committed)
- `.rdf/work-output/spec-progress.md` (crash recovery state)

---

## 3. `/r-plan` — Planning

The plan command auto-detects the most recent spec and decomposes it
into execution-grade phases with metadata that drives gate selection.

```
you: /r-plan
```

```markdown
Detected spec: `docs/specs/2026-03-17-csig-batch-engine-design.md`
Reading codebase...
```

The **planner** agent reads the spec and all files in scope, then
writes PLAN.md with a preamble and phase breakdown:

```markdown
Plan written: **PLAN.md** — 5 phases

| Phase | Description | Mode | Risk | Type | Gates |
|-------|-------------|------|------|------|-------|
| 1 | Compiler extension + batch compilation tests | serial-context | medium | feature | G1+G2+G3-lite |
| 2 | Merged _hex_csig_batch_worker() | serial-agent | high | refactor | G1+G2+G3-full |
| 3 | Wire into scan pipeline + feature gate | serial-agent | medium | feature | G1+G2+G3-lite |
| 4 | Benchmark + progress label update | serial-context | low | config | G1 |
| 5 | Legacy worker cleanup + test migration | serial-agent | medium | refactor | G1+G2+G3-full |

Dispatching challenge review...
```

The reviewer challenges the plan structure:

```markdown
Challenge review: PASS — 1 suggestion (non-blocking)

> Plan approved — 5 phases, all sequential.
> Run `/r-build` to begin Phase 1.
```

**What the plan contains for each phase:**

```markdown
### Phase 2: Merged _hex_csig_batch_worker()

Implement the single-pass worker that extracts hex once and runs
both HEX matching (grep -F literals + per-ERE wildcards) and CSIG
matching (set-based rule evaluation) on the same buffer.

**Files:**
- Modify: `files/internals/functions` (lines 3100-3400)
- Modify: `tests/29-scan-csig.bats` (add batch-specific tests)

**Metadata:**
- Mode: serial-agent
- Risk: high
- Type: refactor
- Gates: G1 + G2 + G3-full
- Accept: merged worker produces identical hit output to separate workers
- Test: `make -C tests test` (Debian 12) — 492+ tests pass
- Edge cases: empty CSIG ruleset, single-subsig rules, mawk compat

**Steps:**
- [ ] Step 1: Write failing test — scan with CSIG sigs, assert hits match
- [ ] Step 2: Implement `_hex_csig_batch_worker()` ...
- [ ] Step 3: Verify `grep -rn '_csig_batch_worker\|_hex_batch_worker' files/`
- [ ] Step 4: Commit
```

The developer never sees gate configuration. They see `Risk: high`
and `Type: refactor` — the dispatcher derives `G1+G2+G3-full`
internally.

**Artifacts:**
- `PLAN.md` (committed)

---

## 4. `/r-build` — Execution

Build executes one phase at a time. The dispatcher reads the phase
metadata from PLAN.md and orchestrates the TDD cycle, quality gates,
and commit.

```
you: /r-build
```

### Phase 1 — Compiler extension (medium, feature → G1+G2+G3-lite)

Task tracking shows the full plan with current progress:

```markdown
- [ ] **Phase 1 — Compiler extension** *(in-progress)*
- [ ] Phase 2 — Merged batch worker
- [ ] Phase 3 — Wire into scan pipeline
- [ ] Phase 4 — Benchmark + progress label
- [ ] Phase 5 — Legacy cleanup
```

The dispatcher dispatches the **engineer** subagent, which follows TDD:
write failing test, implement, verify green. Then quality gates run:

```markdown
### Phase 1 Gates

| Gate | Agent | Result | Detail |
|------|-------|--------|--------|
| G1 | Engineer | PASS | TDD: 3 new tests red→green, 492 total pass |
| G2 | QA | PASS | bash -n clean, shellcheck clean, 0 anti-pattern hits |
| G3-lite | Sentinel | PASS | 2-pass (anti-slop + regression), 0 findings |

> **Phase 1 complete** — `a1b2c3d` [New] Dual-format CSIG batch compilation
> Next: Phase 2 — Merged batch worker. Run `/r-build` to continue.
```

### Phase 2 — Merged worker (high, refactor → G1+G2+G3-full)

```
you: /r-build
```

This is the core change — `risk:high` and `type:refactor` triggers
the full 4-pass sentinel review:

```markdown
### Phase 2 Gates

| Gate | Agent | Result | Detail |
|------|-------|--------|--------|
| G1 | Engineer | PASS | TDD: 5 tests red→green, merged worker matches hit output |
| G2 | QA | PASS | 495 tests pass (Debian 12), 0 anti-pattern hits |
| G3-full | Sentinel | PASS | 4-pass, 2 findings (S-001 SHOULD-FIX, S-002 SHOULD-FIX) |
```

The sentinel found real issues:

```markdown
**S-001** (SHOULD-FIX): `rm -f "$tmpdir"/.csig_all.*` runs
unconditionally on every rule iteration — unnecessary fork when
candidate file was a SID match, not a temp file.

**S-002** (SHOULD-FIX): Progress label still displays "hex" but the
merged worker now handles both HEX and CSIG patterns.

Both are SHOULD-FIX (not MUST-FIX) — the counter-hypothesis protocol
confirmed they don't cause incorrect results, only waste and
misleading UX. Logged to status file, deferred to Phase 4.
```

```markdown
> **Phase 2 complete** — `d4e5f6a` [Change] Merge HEX+CSIG into single batch worker
```

### Phases 3-5 — (abbreviated)

```
you: /r-build    # Phase 3: wire + feature gate
you: /r-build    # Phase 4: benchmark + fix S-001/S-002 from sentinel
you: /r-build    # Phase 5: legacy cleanup
```

Phase 4 (`risk:low`, `type:config`) runs G1 only — just the engineer
self-report. No QA dispatch, no sentinel. Fast.

Phase 5 (`risk:medium`, `type:refactor`) gets G1+G2+G3-full again
because refactors always need the full sentinel to catch regressions.

### End-of-Plan Sentinel

After Phase 5, the dispatcher automatically triggers a cumulative
review — this plan has 5 phases (above the 3-phase threshold):

```markdown
### End-of-Plan Sentinel

Scope: `git diff badb200..HEAD` (5 phases, 8 commits, 14 files)
Depth: full (4-pass)

| Pass | Findings |
|------|----------|
| Anti-slop | 0 |
| Regression | 0 |
| Security | 0 |
| Performance | 0 |

Verdict: **APPROVE**

> **All 5 phases complete.** End-of-plan sentinel: APPROVE.
> Run `/r-ship` to begin release workflow.
```

**Task tracking at completion:**

```markdown
- [x] Phase 1 — Compiler extension
- [x] Phase 2 — Merged batch worker
- [x] Phase 3 — Wire into scan pipeline
- [x] Phase 4 — Benchmark + progress label
- [x] Phase 5 — Legacy cleanup
```

**Artifacts per phase:**
- `.rdf/work-output/phase-N-result.md` — commits, files, verification evidence
- `.rdf/work-output/phase-N-status.md` — gate verdicts, sentinel findings
- Git commits (one per phase)

---

## 5. `/r-ship` — Release

Ship is a five-stage pipeline: preflight, verification, release prep,
publish, and final report.

```
you: /r-ship
```

### Preflight

```markdown
### Preflight
- [x] **Plan**: all phases complete (5/5)
- [x] **Working tree**: clean
- [x] **Branch**: `2.0.1` — 8 commits ahead of `main`
```

### Verification (parallel)

QA and sentinel dispatch simultaneously — wall time is max(QA, sentinel),
not the sum:

```markdown
### Verification Gates
- [x] **QA**: PASS — 598 tests, 0 failures, shellcheck clean
- [x] **Sentinel**: APPROVE — 4-pass, 0 MUST-FIX findings
```

### Release Prep

```markdown
### Release Prep
- [x] **Changelog**: 8 entries added to CHANGELOG + CHANGELOG.RELEASE
- [x] **Attribution scrub**: clean — no AI references
- [x] **Version strings**: consistent (2.0.1)
- [x] **Commit**: `f7a8b9c` pushed to origin/2.0.1
```

### Publish

```markdown
### PR Created
**PR** #471: Merge HEX+CSIG batch workers — 63x scan speedup
**URL**: https://github.com/rfxn/linux-malware-detect/pull/471
```

### Final Report

```markdown
## Ship Report: LMD 2.0.1

| Property | Value | Property | Value |
|----------|-------|----------|-------|
| **PR** | #471 | **Commits** | 8 |
| **Branch** | `2.0.1` → `main` | **HEAD** | `f7a8b9c` |

### Verdict
**READY TO MERGE** — all gates passed, PR awaiting review
```

---

## What RDF Handled Behind the Scenes

The developer typed 7 commands across the session. Here's what they
didn't have to think about:

**Gate selection** — The dispatcher read phase metadata (risk, type)
and auto-selected gate depth. Phase 2 (`risk:high`, `type:refactor`)
got a full 4-pass sentinel; Phase 4 (`risk:low`, `type:config`) got
engineer self-report only. The developer never configured this.

**Governance loading** — Each agent received project-specific
conventions (Bash 4.1 floor, mawk compatibility, CLI freeze) and
anti-patterns (FreeBSD sed traps, IFS collapsing, `find -regex`
anchoring). The engineer wrote code that follows these constraints
without being told each one.

**False positive prevention** — The sentinel's counter-hypothesis
protocol checked each finding against governance docs, inline
comments, and surrounding code before reporting. Findings that
survive this filter are high-signal.

**Crash recovery** — The spec recorded decisions after each question
to `spec-progress.md`. If the session died mid-brainstorm,
`/r-spec --resume` picks up where it left off. Plans and ship
stages have the same resume protocol.

**Cross-phase consistency** — The end-of-plan sentinel reviewed the
cumulative diff across all 5 phases. Per-phase gates catch local
issues; the holistic review catches regressions between phases
(e.g., Phase 2 adds a function that Phase 5 accidentally removes).

**Session telemetry** — Every session logged to `session-log.jsonl`:
commits, files changed, plan progress, and an operational insight.
The next `/r-start` dashboard surfaces this history automatically.

---

## Command Reference

| Command | Purpose | Dispatches |
|---------|---------|-----------|
| `/r-start` | Load context, display dashboard | — |
| `/r-spec` | Design: discover → brainstorm → write → challenge | reviewer (challenge) |
| `/r-plan` | Decompose spec into phases | planner + reviewer (challenge) |
| `/r-build [N]` | Execute phase N (or next pending) | dispatcher → engineer + qa + sentinel + uat |
| `/r-ship` | Release: preflight → verify → prep → publish | qa + reviewer (sentinel) |
| `/r-review` | On-demand adversarial review | reviewer |
| `/r-verify` | On-demand QA verification | qa |
| `/r-test` | On-demand UAT scenarios | uat |

## Agent Roster

| Agent | Model | Role | Read-only? |
|-------|-------|------|------------|
| Planner | opus | Research, brainstorm, spec/plan authoring | No |
| Dispatcher | sonnet | Phase orchestration, gate selection, finding resolution | No |
| Engineer | opus | TDD implementation, follows governance | No |
| QA | sonnet | Lint, tests, convention checks | Yes |
| Reviewer | opus | Adversarial: challenge (design) or sentinel (code) | Yes |
| UAT | sonnet | End-user scenarios, real-world testing | Yes |
