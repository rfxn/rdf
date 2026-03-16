# rfxn Agent Workforce — Architecture & Reference

---

## 1. Organization Chart

```
R-FX NETWORKS — AGENT WORKFORCE
════════════════════════════════════════════════════════════════════

USER
 │
 ├─► po  (sonnet)              Product Owner
 │                              Intake, requirements, scope gating
 │
 └─► mgr  (sonnet)             Engineering Manager
      │                         Prioritize, delegate, quality gates
      │                         Phase issues, initiative lifecycle
      │
      ├─► scope  (sonnet)       Scoping & Research
      │    │                    Impact analysis, phase validation
      │    │
      │    └─► sys-challenger  (sonnet)  Pre-Implementation Adversary
      │                                  Design flaws, edge cases, risks
      │
      ├─► sys-eng  (opus)       Senior Engineer
      │    │                    Implement phases, 7-step protocol
      │    │
      │    ├─── sys-qa  (sonnet)         QA Engineer — read-only
      │    │                              Verify sys-eng work, anti-patterns
      │    │
      │    └─── sys-sentinel  (opus)     Post-Impl Adversary — parallel w/ sys-qa
      │                                  4-pass: anti-slop, regression,
      │                                  security, performance
      │
      ├─► sys-ux  (sonnet)              UX & Output Design
      │                                 CLI, help text, email, man pages
      │
      ├─► sys-uat  (sonnet)    User Acceptance Testing
      │                        Sysadmin persona, Docker, real workflows
      │
      ├─► sec-eng  (opus)      Security Engineer
      │                        Offensive/defensive assessment
      │
      ├─► fe-qa   (sonnet)     Frontend QA
      │                        API contracts, DOM, CSS, JS
      │
      ├─► fe-uat  (sonnet)     Frontend UAT
      │                        Playwright, headless Chromium
      │
      └─► AUDIT PIPELINE  (orchestrator: sonnet)
           │
           ├─ opus    regression · latent · security · modernize
           ├─ sonnet  cli · docs · config · test-coverage · test-exec
           │          install · build-ci · upgrade · interfaces
           │          condense(×2) · compile · context
           └─ haiku   standards · version

════════════════════════════════════════════════════════════════════
PIPELINE FLOW
  USER → [po] → mgr → [scope → sys-eng plan-only → sys-challenger]
       → sys-eng → [sys-sentinel ∥ sys-qa] → [sys-ux] → sys-uat
       → MERGE
════════════════════════════════════════════════════════════════════
```

### Model Summary

| Model  | Agents                                                                          |
|--------|---------------------------------------------------------------------------------|
| opus   | sys-eng, sys-sentinel, sec-eng, audit: regression, latent, security, modernize  |
| sonnet | po, mgr, scope, sys-challenger, sys-qa, sys-ux, sys-uat, fe-qa, fe-uat,        |
|        | audit orchestrator + 11 domain agents                                           |
| haiku  | audit: standards, version                                                       |

---

## 2. Detailed Pipeline Views

### Pipeline 1 — Main Engineering Pipeline

```
 USER REQUEST
      │
      ▼
 ┌─────────────────────────────────────────────────────────────────┐
 │ po  (optional — ambiguous/strategic requests only)  [sonnet]    │
 │  1. Challenge user assumptions                                  │
 │  2. Identify hidden dependencies / cross-project impact         │
 │  3. Write acceptance criteria                                   │
 │  4. Output: scoped problem statement  → mgr                     │
 └───────────────────────────────┬─────────────────────────────────┘
                                 │  bypass with --no-po
                                 ▼
 ┌─────────────────────────────────────────────────────────────────┐
 │ mgr  Engineering Manager  [sonnet]                              │
 │  1. Read all state (CLAUDE.md, MEMORY.md, PLAN.md, AUDIT.md)   │
 │  2. Cross-project dashboard                                     │
 │  3. Stale worktree detection                                    │
 │  4. Build priority queue                                        │
 │  5. Dispatch scope → sys-eng plan-only → sys-challenger (tier 2+)│
 │  6. Dispatch sys-eng with work order                            │
 │  7. Tiered verification gate → sys-qa [+ sys-uat]               │
 │  8. Merge decision + post-merge actions                         │
 └─────┬───────────────────────────────────────────────────────────┘
       │
       ▼  [tier 2+ only]
 ┌──────────────────┐
 │ scope  [sonnet]  │
 │  Work order      │
 │  assembly +      │
 │  context harvest │
 └────────┬─────────┘
          │  scope-workorder → mgr
          ▼
 ┌──────────────────┐    ┌──────────────────────────────┐
 │ sys-eng  [opus]  │───►│ sys-challenger  [sonnet]      │
 │  plan-only mode  │    │  1. Read implementation plan  │
 │  Steps 1-2 only  │    │  2. Design flaw analysis      │
 │  Output:         │    │  3. Edge case / regression    │
 │  implementation- │    │     identification            │
 │  plan.md         │    │  4. Simpler-alternative check │
 └──────────────────┘    │  5. Output: CHALLENGE_FINDINGS │
                         └──────────────────────────────┘
                              │  findings injected into sys-eng work order
                              ▼
 ┌─────────────────────────────────────────────────────────────────┐
 │ sys-eng  Senior Engineer  [opus]   ← see Pipeline 2 (7-step)   │
 │  Executes phase. Writes work-output/phase-N-{status,result}.md │
 └─────────────────────────────────────────────────────────────────┘
      │                                 │
      ▼                                 │  [tier 2+ only, parallel]
 ┌──────────────────┐                   ▼
 │ sys-qa  [sonnet] │         ┌────────────────────────┐
 │ ← Pipeline 3     │         │ sys-sentinel  [opus]    │
 └────────┬─────────┘         │ ← Pipeline 4 (4-pass)  │
          │                   └────────────────────────┘
          │◄──────────────────────────────┘
          │  findings merged into sys-qa Step 5.5
          ▼
 ┌─────────────────────────────────────────────────────────────────┐
 │ sys-ux  (trigger-based)  [sonnet]                               │
 │  Triggers when: CLI output / help text / email / man page changed│
 │  Modes: DESIGN_REVIEW (pre-impl) | OUTPUT_REVIEW (post-impl)    │
 │  bypass with --no-ux                                            │
 └─────────────────────────┬───────────────────────────────────────┘
                           │
                           ▼  [tier 2+ only]
              ┌────────────────────────────┐
              │ sys-uat  [sonnet]           │
              │  Sysadmin persona           │
              │  Docker install + scenarios │
              │  Writes uat-phase-N-verdict │
              └────────────┬───────────────┘
                           │
                           ▼
              ┌────────────────────────────┐
              │ mgr MERGE DECISION         │
              │  See Pipeline 5            │
              └────────────────────────────┘
```

---

### Pipeline 2 — sys-eng 7-Step Protocol

```
 WORK ORDER (from mgr)
      │
      ▼
 Step 1  UNDERSTAND CONTEXT  (MANDATORY)
         Read CLAUDE.md, MEMORY.md, PLAN.md, AUDIT.md
         Read all files in scope. Grep for callers.
         Validate phase refs against actual codebase.
         ─────────────────────────────────────────────
 Step 2  PLAN IMPLEMENTATION
         Design approach. Document trade-offs.
         Identify bash 4.1 compat risks.
         Write plan to work-output/phase-N-status.md [STATUS: RUNNING]
         ─────────────────────────────────────────────
 Step 3  IMPLEMENT
         Edit files. One logical change at a time.
         No global state changes without save/restore.
         No local var=$(…) — declare separately.
         Respond to all CHALLENGE_FINDINGS.
         ─────────────────────────────────────────────
 Step 4  UPDATE CHANGELOGS
         CHANGELOG + CHANGELOG.RELEASE both updated.
         Tagged lines: [New] [Change] [Fix]
         ─────────────────────────────────────────────
 Step 5  VERIFY  (MANDATORY)
         bash -n all shell files
         shellcheck all shell files
         grep: which / egrep / backticks / || true
         grep: hardcoded paths
         Bash 4.1 grep evidence (required, not claimed)
         Run test tier per /test-strategy
         Tee output → /tmp/test-<project>.log
         ─────────────────────────────────────────────
 Step 6  COMMIT
         Stage files by name (never git add -A)
         Message format: VERSION | Description
         Tag every body line: [New] [Change] [Fix]
         Include Ref #<phase-issue> in commit body
         No Co-Authored-By / no AI attribution
         ─────────────────────────────────────────────
 Step 6b POST TASK-COMPLETION COMMENT
         gh issue comment <phase-issue> (Task N.M complete)
         ─────────────────────────────────────────────
 Step 7  REPORT RESULTS
         Write work-output/phase-N-result.md
         Fields: FILES_MODIFIED, TEST_TIER,
                 LINT_STATUS, TESTS_PASSED,
                 SENTINEL_RESPONSE (if sentinel ran)
         Update phase-N-status.md [STATUS: COMPLETE]
      │
      ▼
 back to mgr
```

---

### Pipeline 3 — sys-qa 6-Step Protocol

```
 sys-eng result (work-output/phase-N-result.md)
      │
      ▼
 Step 1  GATHER CONTEXT
         Read CLAUDE.md, MEMORY.md, sys-eng result file
         Get full git diff. Read all modified files.
         ─────────────────────────────────────────────
 Step 2  STRUCTURAL REVIEW
         Shell syntax (bash -n), shellcheck
         Anti-patterns: which/egrep/backtick/|| true
         Code quality: dead code, path validation,
         missing quotes, hardcoded paths
         ─────────────────────────────────────────────
 Step 2.5  BASH 4.1 COMPLIANCE  (MANDATORY — grep, don't trust sys-eng)
         Grep for: ${var,,} mapfile -d declare -n
                   $EPOCHSECONDS declare -A (global)
         Include grep output as evidence.
         ─────────────────────────────────────────────
 Step 3  BEHAVIORAL REVIEW
         Logic correctness, edge cases
         Exit code handling, IFS state
         Empty-path propagation, conditionally-set vars
         ─────────────────────────────────────────────
 Step 4  REGRESSION CHECK  (always run tier 2+)
         Run test suite in Docker (Debian 12 + Rocky 9)
         Compare test counts: before vs after
         Check for silent behavior changes
         ─────────────────────────────────────────────
 Step 5  PATTERN-CLASS SWEEP
         Grep codebase for the same pattern class
         Check all consumers of modified functions
         ─────────────────────────────────────────────
 Step 5.5  SENTINEL INTEGRATION
         If sentinel-N.md exists in work-output/:
           Read all findings
           Verify sys-eng's SENTINEL_RESPONSE is adequate
           Elevate unaddressed MUST-FIX items
         ─────────────────────────────────────────────
 Step 6  VERDICT
         Post QA verdict as comment on phase issue
         Write qa-phase-N-verdict.md
         Findings: MUST-FIX / SHOULD-FIX / INFORMATIONAL
         Verdict: APPROVED | CHANGES_REQUESTED | REJECTED
         Note ESCALATION_RECOMMENDED if complexity exceeded
      │
      ▼
 back to mgr
```

---

### Pipeline 4 — sys-sentinel 4-Pass Protocol  [opus, parallel with sys-qa]

```
 sys-eng result (work-output/phase-N-result.md)
      │
      ▼
 Gather Context
   Read CLAUDE.md, MEMORY.md, sys-eng result
   Full git diff. Read every modified file (whole file).
   Grep callers/consumers of modified functions.
   Read MEMORY.md for past failures on similar changes.
      │
      ▼
 ┌──────────────────────────────────────────────────────────────┐
 │ Pass 1: ANTI-SLOP                                            │
 │  Lens: semantic clarity, naming, duplication, abstraction    │
 │  - Variable names lie about content?                         │
 │  - Copy-paste blocks >5 lines differing only in var names?   │
 │  - Premature abstraction? Under-abstraction (3+ ident blocks)?│
 │  - Non-obvious decisions uncommented?                        │
 │  Default severity: SHOULD-FIX                                │
 │  Escalate to MUST-FIX: name implies type, causes misuse      │
 ├──────────────────────────────────────────────────────────────┤
 │ Pass 2: REGRESSION SENTINEL                                  │
 │  Lens: behavioral continuity                                 │
 │  - Pre-change vs post-change output for all handled inputs   │
 │  - Caller contracts changed?                                 │
 │  - Changed: return values, exit codes, file paths, var names │
 │  - Old state on disk encountered by new code — handled?      │
 │  Default severity: MUST-FIX (coverage gaps: SHOULD-FIX)     │
 ├──────────────────────────────────────────────────────────────┤
 │ Pass 3: SECURITY SENTINEL                                    │
 │  Lens: injection, credential exposure, path traversal        │
 │  - User input unquoted in command context?                   │
 │  - Temp files with predictable names ($RANDOM, $$, PID)?     │
 │  - Credentials logged / echoed / world-readable?             │
 │  - eval with uncontrolled input?                             │
 │  - || true or 2>/dev/null suppressing security-relevant err? │
 │  Default severity: MUST-FIX (hardening w/o vector: SHOULD)  │
 ├──────────────────────────────────────────────────────────────┤
 │ Pass 4: PERFORMANCE SENTINEL                                 │
 │  Lens: O(N²), process spawning, redundant I/O               │
 │  - Loops spawning subshells per iteration?                   │
 │  - Same file parsed multiple times?                          │
 │  - Fixed sleep when event-driven wait works?                 │
 │  Benchmark: 10,000 IPs in ban list — will it complete?       │
 │  Default: SHOULD-FIX. MUST-FIX: observable prod degradation │
 └──────────────────────────────────────────────────────────────┘
      │
      ▼
 Write sentinel-N.md (max 20 findings total across all passes)
 Each finding: PASS / SEVERITY / FILE:LINE / DESCRIPTION /
               EVIDENCE / RECOMMENDATION / VERIFIED
 Post summary comment on phase issue (PASS/PASS WITH NOTES/FAIL)
      │
      ▼
 sys-qa reads sentinel-N.md at Step 5.5
 sys-eng must respond to all BLOCKING_CONCERN + MUST-FIX in result file
```

---

### Pipeline 5 — Verification Gate & Merge Decision

```
 sys-eng result classified by test-strategy tier
      │
      ├── Tier 0 (docs only)
      │   CHANGELOG, README, man pages, comments       ──────────────┐
      │                                                               │
      ├── Tier 1 (single scope)                                       │
      │   One config file, single-file edit, CLI help text  ─────────┤
      │                                                               │
      └── Tier 2+ (multi-file / cross-OS / shared libs)              │
                                                                      │
          ┌──────────────────────────────────────────┐               │
          │  FULL GATE  [parallel]                    │               │
          │  sys-qa (gate mode)  ∥  sys-uat           │               │
          │  sys-sentinel already ran during           │     LITE GATE │
          │  sys-eng phase                            │    sys-qa ◄──┘
          └──────────────────┬───────────────────────┘    only
                             │                             No sys-uat
                             │
                             ▼
 ┌──────────────────────────────────┐   ┌────────────────────────────┐
 │ sys-qa  │ sys-uat │ Action       │   │ sys-qa-lite │ Action       │
 │─────────┼─────────┼──────────────│   │─────────────┼──────────────│
 │APPROVED │APPROVED │ MERGE        │   │APPROVED     │ MERGE        │
 │APPROVED │CONCERNS │ MERGE+note   │   │CHG_REQ      │ sys-eng fix  │
 │APPROVED │REJECTED │ sys-eng fix  │   │ESCALATION   │ → FULL GATE  │
 │CHG_REQ  │any      │ sys-eng fix  │   └────────────────────────────┘
 │REJECTED │any      │ BLOCKED      │
 └──────────────────────────────────┘
      │ MERGE_READY
      ▼
 Post-merge: /mem-save + mark PLAN.md DONE + close phase issue + recommend next phase
```

---

### Pipeline 6 — Look-Ahead Optimization

```
 Eligibility:
   ✓ N+1 prereqs met (N in-progress OK if N+1 doesn't depend on N's output)
   ✓ Planner validated: PARALLEL_SAFE true for N and N+1
   ✓ sys-eng(N) STATUS: COMPLETE

 Standard:  sys-eng(N)──sys-qa(N)──────────────sys-eng(N+1)──sys-qa(N+1)   4 time units
 Pipeline:  sys-eng(N)──sys-qa(N)──────────────────────────────────────
                        sys-eng(N+1, worktree)───sys-qa(N+1)──────────     3 time units

 Safety rules:
   sys-qa(N) APPROVED      → merge N, then merge N+1 after its sys-qa passes
   sys-qa(N) CHG_REQUESTED → hold N+1 worktree until N is re-approved
   sys-qa(N) REJECTED      → discard N+1 worktree, resolve N first
```

---

### Pipeline 7 — Audit Pipeline (3-Round)

```
 /audit or /audit-quick
      │
      ▼
 ┌─────────────────────────────────────────────────────────────────┐
 │ ROUND 1 — DOMAIN AGENTS  (parallel, max 20 findings each)      │
 │                                                                 │
 │  opus    (1) regression   (2) latent    (13) security           │
 │          (15) modernize                                         │
 │                                                                 │
 │  sonnet  (4) cli          (5) docs      (6) config              │
 │          (7) test-cov     (8) test-exec (9) install             │
 │          (10) build-ci    (11) upgrade  (14) interfaces         │
 │                                                                 │
 │  haiku   (3) standards    (12) version                          │
 └──────────────────────┬──────────────────────────────────────────┘
                        │ raw findings
                        ▼
 ┌─────────────────────────────────────────────────────────────────┐
 │ ROUND 2 — CONDENSE + DEDUP  (parallel)  [sonnet]               │
 │  Group A: agents 1-8   → findings-a.md                         │
 │  Group B: agents 9-15  → findings-b.md                         │
 │  Dedup is intra-group (pushed into condense step)              │
 └──────────────────────┬──────────────────────────────────────────┘
                        │ findings-a.md + findings-b.md
                        ▼
 ┌─────────────────────────────────────────────────────────────────┐
 │ ROUND 3 — COMPILE  (sequential)  [sonnet]                      │
 │  Cross-group dedup                                              │
 │  300-line hard cap on AUDIT.md output                           │
 │  P1 findings: expanded detail                                   │
 │  P2 findings: table format                                      │
 │  P3 findings: grouped summary                                   │
 │  Fallback: degraded-mode AUDIT.md if compile stalls            │
 └──────────────────────┬──────────────────────────────────────────┘
                        │
                        ▼
                   AUDIT.md
         + ./audit-output/false-positives.md
```

### 15 Audit Domain Agents

```
+-------+------------+--------+-------+--------+----------------------------------------+
| Agent | Name       | Prefix | Quick | Model  | Domain                                 |
+-------+------------+--------+-------+--------+----------------------------------------+
|   1   | Regression | REG    |  yes  | opus   | Recent changes, regressions            |
|   2   | Latent     | LAT    |  yes  | opus   | Full codebase bug hunting              |
|   3   | Standards  | STD    |  yes  | haiku  | Shell standards, bash 4.1 portability  |
|   4   | CLI        | CLI    |  yes  | sonnet | Case dispatchers, help text, exit codes|
|   5   | Docs       | DOC    |  no   | sonnet | README, man pages, inline comments     |
|   6   | Config     | CFG    |  no   | sonnet | Config files, parsers, load order      |
|   7   | Coverage   | COV    |  no   | sonnet | BATS test suite analysis (read-only)   |
|   8   | Test Exec  | TEX    |  no   | sonnet | Execute BATS suite, capture results    |
|   9   | Install    | INS    |  no   | sonnet | Install/uninstall, path replacement    |
|  10   | Build/CI   | BCI    |  no   | sonnet | Makefiles, CI workflows, Dockerfiles   |
|  11   | Upgrade    | UPG    |  no   | sonnet | Upgrade paths, config migration        |
|  12   | Version    | VER    |  yes  | haiku  | Version/copyright consistency          |
|  13   | Security   | SEC    |  yes  | opus   | Injection, tempfiles, credentials      |
|  14   | Interfaces | INT    |  no   | sonnet | Inter-tool contracts, FIXME/HACK       |
|  15   | Modernize  | MOD    |  no   | opus   | Structural quality, duplication, debt  |
+-------+------------+--------+-------+--------+----------------------------------------+

Quick mode (/audit-quick): Agents 1,2,3,4,12,13 — static analysis only, no tests
Full mode  (/audit):       All 15 agents + test execution
```

---

## 3. Command Cheat Sheet

### Persona Commands — Autonomous Agents

| Command | What It Does | When To Use |
|---------|-------------|-------------|
| `/mgr` | mgr briefing — assess state, prioritize, delegate | Start of session, project planning |
| `/mgr status` | Cross-project status snapshot | Quick overview of all projects |
| `/mgr health` | Live health dashboard | Pre-release sanity check |
| `/mgr <project>` | Focus on one project | Deep-dive on APF, BFD, LMD, etc. |
| `/mgr phase N` | Dispatch sys-eng for phase N | Execute a specific plan phase |
| `/mgr batch` | Batch same-class changes | Cross-project consistency work |
| `/mgr release` | Release coordination mode | Ship a version |
| `/mgr audit` | Full audit pipeline | Comprehensive code review |
| `/po` | Product Owner intake | Ambiguous or strategic requests |
| `/sys-eng` | sys-eng picks next pending phase | Hands-free execution |
| `/sys-eng N` | sys-eng executes phase N | Targeted phase work |
| `/sys-eng <text>` | sys-eng executes freeform task | Ad-hoc engineering work |
| `/sys-qa` | sys-qa reviews latest sys-eng work (full 6-step or lite 3-step) | Post-implementation gate |
| `/sys-uat` | sys-uat validates from user POV (tier 2+ only) | Operational readiness check |
| `/sec-eng` | Security engineer assessment | Offensive/defensive review |

### Audit Commands

| Command | What It Does | When To Use |
|---------|-------------|-------------|
| `/audit` | Full 15-agent audit pipeline | Major releases, new projects |
| `/audit-quick` | 6-agent static analysis only | Quick feedback between commits |
| `/audit-delta` | 3-agent check on changed files | Post-commit regression gate |
| `/audit-plan` | Generate PLAN.md from AUDIT.md | After audit, plan remediation |
| `/audit-feedback` | Harvest false positives | Tune future audit accuracy |

### Release Commands

| Command | What It Does | When To Use |
|---------|-------------|-------------|
| `/rel-prep` | Pre-release checklist | Before any release |
| `/rel-chg-dedup` | Deduplicate changelog entries | Before release, after many commits |
| `/rel-chg-diff` | Generate changelog from diff | After code changes |
| `/rel-scrub` | Remove AI/Claude attribution | Before merge to master |
| `/rel-merge` | Generate squash commit message | PR merge preparation |
| `/rel-ship` | Commit, push, create PR | Ship the release |
| `/rel-notes` | Generate GitHub release notes | After merge to master |

### Code Quality Commands

| Command | What It Does | When To Use |
|---------|-------------|-------------|
| `/code-validate` | bash -n + shellcheck + anti-patterns | Before every commit |
| `/code-grep` | Pattern-class bug finder | Hunt specific anti-patterns |
| `/test-strategy` | Recommend test tier for changes | Decide what to test |
| `/test-impact` | Map functions to BATS tests | Find relevant tests |
| `/test-dedup` | Find duplicate/overlapping tests | Test suite maintenance |

### Project Management Commands

| Command | What It Does | When To Use |
|---------|-------------|-------------|
| `/proj-status` | Project status snapshot | Quick state check |
| `/proj-cross` | Cross-project pattern analysis | Find batch opportunities |
| `/proj-cross-audit` | Cross-project audit coordination | Batch audit findings |
| `/proj-lib-sync` | Shared library drift detection | After library updates |
| `/proj-scaffold` | Scaffold new rfxn project | New project setup |
| `/proj-health` | Live health dashboard | Non-destructive checks |

### Memory & Session Commands

| Command | What It Does | When To Use |
|---------|-------------|-------------|
| `/mem-save` | Persist state to tracking files | After commits, before long ops |
| `/mem-audit` | Detect stale/contradictory memory | Periodic maintenance |
| `/mem-compact` | Archive completed work | When MEMORY.md grows large |

### Infrastructure Commands

| Command | What It Does | When To Use |
|---------|-------------|-------------|
| `/ci-setup` | Generate GitHub Actions workflow | New project or CI refresh |
| `/lib-release` | Shared library release lifecycle | Ship tlog/alert/elog/pkg_lib |
| `/onboard` | Lightweight project intake | First time in unfamiliar project |
| `/reload` | Re-read all context files | Start of session |
| `/modernize` | Assess modernization maturity | Identify technical debt |
| `/doc-author` | Technical documentation drafting | README, man pages, guides |
| `/status` | Quick project state display | Session orientation |

---

## 4. Common Workflows

### Start a New Session
```
/reload                          # Load context
/mgr status                      # See all projects
/proj-health                     # Live health check
```

### Execute Plan Phases (Orchestrated)
```
/mgr bfd                         # mgr assesses BFD state
/mgr phase 3                     # mgr dispatches sys-eng for phase 3
                                 # scope validates refs
                                 # sys-challenger reviews plan (tier 2+)
                                 # sys-eng implements, commits, reports
                                 # sys-sentinel runs adversarial review (tier 2+)
                                 # mgr classifies tier → routes sys-qa-lite or sys-qa+sys-uat
                                 # sys-qa approves or requests changes
```

### Execute Plan Phases (Direct)
```
/sys-eng 3                       # sys-eng executes phase 3 directly
/sys-qa                          # sys-qa reviews the work
```

### Pre-Commit Verification
```
/code-validate                   # Lint + anti-pattern check
/test-strategy                   # What tests to run?
make -C tests test 2>&1 | tee /tmp/test-<project>.log | tail -30
```

### Release a Project
```
/rel-prep                        # Pre-release checklist
/rel-chg-dedup                   # Clean up changelog
/rel-scrub                       # Remove AI attribution
/code-validate                   # Final lint
/rel-ship                        # Commit, push, PR
/rel-notes                       # GitHub release notes
```

### Full Audit Cycle
```
/audit                           # Run all 15 agents
/audit-plan                      # Generate remediation plan
/mgr                             # mgr prioritizes findings
/sys-eng                         # sys-eng fixes phase by phase
```

### Quick Post-Commit Check
```
/audit-delta                     # 3-agent regression check
```

### Cross-Project Maintenance
```
/proj-cross                      # Find patterns across projects
/proj-lib-sync                   # Check shared library drift
/proj-cross-audit                # Batch audit findings
/mgr batch                       # mgr coordinates batch fixes
```

### Shared Library Update
```
cd <canonical-lib>               # Work in canonical repo
/sys-eng                         # Implement changes
/lib-release                     # Release new version
/proj-lib-sync                   # Update all consumers
```

---

## 5. Project Landscape

```
+===========================================================================+
|                        rfxn Project Ecosystem                             |
+===========================================================================+
|                                                                           |
|  PRODUCTS (user-facing)              SHARED LIBRARIES                     |
|  +-------------+                     +-------------+                      |
|  | APF  2.0.2  |----+          +-----| tlog_lib    |---> APF,BFD,LMD     |
|  | Firewall    |    |          |     | v2.0.3      |                      |
|  +-------------+    |          |     +-------------+                      |
|                     |          |     +-------------+                      |
|  +-------------+    +----------+-----| alert_lib   |---> BFD,LMD         |
|  | BFD  2.0.1  |----+          |     | v1.0.4      |                      |
|  | Brute Force |    |          |     +-------------+                      |
|  +-------------+    |          |     +-------------+                      |
|                     +----------+-----| elog_lib    |---> BFD,LMD          |
|  +-------------+    |          |     | v1.0.3      |                      |
|  | LMD  2.0.1  |----+          |     +-------------+                      |
|  | Malware Det |               |     +-------------+                      |
|  +-------------+               +-----| batsman     |---> ALL (test infra) |
|                                      | v1.2.0      |                      |
|  +-------------+                     +-------------+                      |
|  | Sigforge    |                     +-------------+                      |
|  | 1.1.3       |                     | pkg_lib     |                      |
|  +-------------+                     | v1.0.4      |                      |
|                                      +-------------+                      |
|  +-------------+                     +-------------+                      |
|  | geoip_lib   |                     | GPUBench    |                      |
|  | v1.0.2      |                     |             |                      |
|  +-------------+                     +-------------+                      |
+===========================================================================+
```

---

## 6. File-Based Handoff Protocol

```
work-output/
├── current-phase.md          # mgr -> sys-eng: work order with phase details
├── implementation-plan.md    # sys-eng -> sys-challenger: plan-only mode output
├── plan-validation-N.md      # Planner -> mgr: ref validation (or skipped)
├── scope-workorder-P<N>.md   # scope -> mgr: work order draft + context
├── challenge-N.md            # sys-challenger -> sys-eng: pre-impl findings
├── phase-N-status.md         # sys-eng -> mgr: progress updates (in-flight)
├── phase-N-result.md         # sys-eng -> mgr: completion report
├── test-registry-P<N>.md     # sys-eng -> sys-qa: test results (commit, counts, Docker ID)
├── test-lock-P<N>.md         # sys-eng/sys-qa/sys-uat: test execution state coordination
├── sentinel-N.md             # sys-sentinel -> sys-qa: 4-pass findings
├── sentinel-lib-N.md         # sys-sentinel -> sys-qa: 2-pass library integration findings
├── ux-review-N.md            # sys-ux -> sys-eng: design/output review
├── qa-phase-N-status.md      # sys-qa -> mgr: review progress (LITE or FULL mode)
├── qa-phase-N-verdict.md     # sys-qa -> mgr: verdict (QA_MODE: LITE|FULL)
├── uat-phase-N-verdict.md    # sys-uat -> mgr: acceptance (tier 2+ only)
└── pipeline-metrics.jsonl    # mgr: append-only phase completion metrics

audit-output/
├── agent1.md ... agent15.md  # Domain agent raw findings
├── findings-a.md             # Group A condensed+deduped (agents 1-8)
├── findings-b.md             # Group B condensed+deduped (agents 9-15)
├── context.md                # Harvested planning context
└── false-positives.md        # FP database for future audits
```

---

## 7. Pipeline Optimizations

### Tiered Verification Gate

mgr classifies each sys-eng result by test-strategy tier and routes accordingly:

```
+--------+-------------------+-----------+---------+-------------------------+
| Tier   | Change Scope      | QA Mode   | sys-uat | Time Saved              |
+--------+-------------------+-----------+---------+-------------------------+
|  0     | Docs only         | gate-lite | no      | ~3-4 min (skip 3 steps) |
|  1     | Single scope      | gate-lite | no      | ~3-4 min (skip 3 steps) |
|  2     | Multi-file core   | gate full | yes     | baseline                |
|  3-4   | Cross-OS / legacy | gate full | yes     | baseline                |
+--------+-------------------+-----------+---------+-------------------------+

Override to full gate: Planner STALE, shared lib files, sys-eng flagged concerns
```

### Planner Skip Conditions

Planner validation skipped when:
- Phase creates only new files (nothing to validate)
- Phase is docs-only or test-only
- PLAN updated within last 3 commits

Always runs for: core logic mods, cross-project deps, stale PLANs.

### Pipeline Look-Ahead

When consecutive phases have zero file overlap, sys-eng(N+1) starts in a worktree
while sys-qa(N) reviews phase N. sys-qa rejection holds N+1 until resolved.

```
Without:  sys-eng(4) ── sys-qa(4) ── sys-eng(5) ── sys-qa(5)      4 time units
With:     sys-eng(4) ── sys-qa(4) ──────────────────               3 time units
                        sys-eng(5) ── sys-qa(5) ─────────
```

### Test Result Registry

sys-eng writes `test-registry-P<N>.md` after test execution with commit hash, tier,
pass/fail counts, Docker image ID. sys-qa reads this before running tests:
- **Tier 0-1:** sys-qa may trust registry if COMMIT matches, TIER >=, FAILED == 0
- **Tier 2+:** sys-qa always runs independently but reuses Docker images and
  compares baseline counts from the registry

### Agent Test Lock Protocol

`test-lock-P<N>.md` with STATE (IDLE/RUNNING/COMPLETE) enables passive
coordination between sys-eng, sys-qa, and sys-uat. Single-read, no polling — agents read
the lock once, decide whether to proceed or reuse results, and act. Primary
savings come from Docker image reuse, not from skipping test execution.

### Challenger Gate (Two-Dispatch Pattern)

For tier 2+ changes, mgr dispatches sys-eng in `plan-only` mode (Steps 1-2 only),
then dispatches sys-challenger to review the implementation plan, then re-dispatches
sys-eng from Step 3 with challenge findings. Mandatory checkpoint in work orders:
`CHALLENGER: DISPATCHED | SKIPPED (<code>)`.

### Library Integration Sentinel

When a shared library sync introduces updated files in a consumer project,
mgr dispatches sys-sentinel in LIBRARY_INTEGRATION mode — a lightweight 2-pass
review (Regression + Security) focused on sourcing/init patterns, API
mapping, and credential handling. Skips Anti-Slop and Performance (already
done on the canonical library release).

### UX Reviewer Expanded Triggers

sys-ux dispatches automatically in DESIGN_REVIEW mode (pre-implementation)
when phases touch: alert templates, display formatting, machine-readable output,
or when PLAN description mentions display/format/template/output/email keywords.
Shifts template iteration from post-impl (3-5 commits) to pre-impl (1-2).

### Pipeline Metrics

mgr appends one JSONL line to `pipeline-metrics.jsonl` at each successful merge.
`/mem-save` harvests the JSONL into rolling averages stored in the project's
`pipeline-metrics.md` memory file. Tracks: fix cycle rate, sys-challenger dispatch
rate, sys-sentinel effectiveness, test registry trust rate, sys-ux dispatch rate.

### mgr Context Delegation

scope agent assembles work order drafts (`scope-workorder-P<N>.md`) as the
default path for standard phases. mgr reads the ~2-3K token structured summary
instead of doing ~15-20K tokens of raw code search, sustaining 5-8 phases per
session vs 2-3. mgr retains full IC authority and steps in directly when
judgment, speed, or authority is needed.

---

## 8. Quick Reference Card

```
PERSONAS           AUDIT            RELEASE          PROJECT          MEMORY
─────────          ─────            ───────          ───────          ──────
/mgr               /audit           /rel-prep        /proj-status     /mem-save
/po                /audit-quick     /rel-chg-dedup   /proj-cross      /mem-audit
/sys-eng           /audit-delta     /rel-chg-diff    /proj-cross-aud  /mem-compact
/sys-qa            /audit-plan      /rel-scrub       /proj-lib-sync
/sys-uat           /audit-feedback  /rel-merge       /proj-scaffold   CODE
/scope                              /rel-ship        /proj-health     ────
/sys-challenger                     /rel-notes                        /code-validate
/sys-sentinel                                                         /code-grep
/sys-ux            INFRA            TESTING
/sec-eng           ─────            ───────          OTHER
/fe-qa             /ci-setup        /test-strategy   ─────
/fe-uat            /lib-release     /test-impact     /modernize
                                    /test-dedup      /onboard
                                                     /reload
                                                     /status
                                                     /doc-author
```

**Total: 12 agents + ~66 commands + 10 scripts = ~88 primitives + pipeline optimization protocols**
