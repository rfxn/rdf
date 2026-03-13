# rfxn Agent Workforce — Architecture & Reference

---

## 1. Organization Chart

```
R-FX NETWORKS — AGENT WORKFORCE
════════════════════════════════════════════════════════════════════

USER
 │
 ├─► PO  (sonnet)          Product Owner
 │                         Intake, requirements, scope gating
 │
 └─► EM  (sonnet)          Engineering Manager
      │                    Prioritize, delegate, quality gates
      │
      ├─► SCOPE  (sonnet)  Scoping & Research
      │    │               Impact analysis, phase validation
      │    │
      │    └─► CHALLENGER  (sonnet)  Pre-Implementation Adversary
      │                              Design flaws, edge cases, risks
      │
      ├─► SE  (opus)       Senior Engineer
      │    │               Implement phases, 7-step protocol
      │    │
      │    ├─── QA  (sonnet)         QA Engineer — read-only
      │    │                         Verify SE work, anti-patterns
      │    │
      │    └─── SENTINEL  (opus)     Post-Impl Adversary — parallel w/ QA
      │                              4-pass: anti-slop, regression,
      │                              security, performance
      │
      ├─► UX REVIEWER  (sonnet)      UX & Output Design
      │                              CLI, help text, email, man pages
      │
      ├─► UAT  (sonnet)   User Acceptance Testing
      │                   Sysadmin persona, Docker, real workflows
      │
      ├─► FRONTEND QA   (sonnet)     Overwatch only
      │                              API contracts, DOM, CSS, JS
      │
      ├─► FRONTEND UAT  (sonnet)     Overwatch only
      │                              Playwright, headless Chromium
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
  USER → [PO] → EM → [Scope → SE plan-only → Challenger] → SE
       → [Sentinel ∥ QA] → [UX Reviewer] → UAT → MERGE
════════════════════════════════════════════════════════════════════
```

### Model Summary

| Model  | Agents                                                                   |
|--------|--------------------------------------------------------------------------|
| opus   | SE, Sentinel, audit: regression, latent, security, modernize             |
| sonnet | PO, EM, Scope, Challenger, QA, UX Reviewer, UAT, Frontend QA/UAT,       |
|        | audit orchestrator + 11 domain agents                                    |
| haiku  | audit: standards, version                                                |

---

## 2. Detailed Pipeline Views

### Pipeline 1 — Main Engineering Pipeline

```
 USER REQUEST
      │
      ▼
 ┌─────────────────────────────────────────────────────────────────┐
 │ PO  (optional — ambiguous/strategic requests only)  [sonnet]   │
 │  1. Challenge user assumptions                                  │
 │  2. Identify hidden dependencies / cross-project impact         │
 │  3. Write acceptance criteria                                   │
 │  4. Output: scoped problem statement  → EM                      │
 └───────────────────────────────┬─────────────────────────────────┘
                                 │  bypass with --no-po
                                 ▼
 ┌─────────────────────────────────────────────────────────────────┐
 │ EM  Engineering Manager  [sonnet]                               │
 │  1. Read all state (CLAUDE.md, MEMORY.md, PLAN.md, AUDIT.md)   │
 │  2. Cross-project dashboard                                     │
 │  3. Stale worktree detection                                    │
 │  4. Build priority queue                                        │
 │  5. Dispatch Scope → SE plan-only → Challenger (tier 2+)        │
 │  6. Dispatch SE with work order                                 │
 │  7. Tiered verification gate → QA [+ UAT]                       │
 │  8. Merge decision + post-merge actions                         │
 └─────┬───────────────────────────────────────────────────────────┘
       │
       ▼  [tier 2+ only]
 ┌──────────────────┐
 │ SCOPE  [sonnet]  │
 │  Work order      │
 │  assembly +      │
 │  context harvest │
 └────────┬─────────┘
          │  scope-workorder → EM
          ▼
 ┌──────────────────┐    ┌──────────────────────────────┐
 │ SE  [opus]       │───►│ CHALLENGER  [sonnet]          │
 │  plan-only mode  │    │  1. Read implementation plan  │
 │  Steps 1-2 only  │    │  2. Design flaw analysis      │
 │  Output:         │    │  3. Edge case / regression    │
 │  implementation- │    │     identification            │
 │  plan.md         │    │  4. Simpler-alternative check │
 └──────────────────┘    │  5. Output: CHALLENGE_FINDINGS │
                         └──────────────────────────────┘
                              │  findings injected into SE work order
                              ▼
 ┌─────────────────────────────────────────────────────────────────┐
 │ SE  Senior Engineer  [opus]   ← see Pipeline 2 (7-step)        │
 │  Executes phase. Writes work-output/phase-N-{status,result}.md │
 └─────────────────────────────────────────────────────────────────┘
      │                                 │
      ▼                                 │  [tier 2+ only, parallel]
 ┌──────────────────┐                   ▼
 │ QA  [sonnet]     │         ┌────────────────────────┐
 │ ← Pipeline 3     │         │ SENTINEL  [opus]        │
 └────────┬─────────┘         │ ← Pipeline 4 (4-pass)  │
          │                   └────────────────────────┘
          │◄──────────────────────────────┘
          │  findings merged into QA Step 5.5
          ▼
 ┌─────────────────────────────────────────────────────────────────┐
 │ UX REVIEWER  (trigger-based)  [sonnet]                          │
 │  Triggers when: CLI output / help text / email / man page changed│
 │  Modes: DESIGN_REVIEW (pre-impl) | OUTPUT_REVIEW (post-impl)    │
 │  bypass with --no-ux                                            │
 └─────────────────────────┬───────────────────────────────────────┘
                           │
                           ▼  [tier 2+ only]
              ┌────────────────────────────┐
              │ UAT  [sonnet]               │
              │  Sysadmin persona           │
              │  Docker install + scenarios │
              │  Writes uat-phase-N-verdict │
              └────────────┬───────────────┘
                           │
                           ▼
              ┌────────────────────────────┐
              │ EM MERGE DECISION          │
              │  See Pipeline 5            │
              └────────────────────────────┘
```

---

### Pipeline 2 — SE 7-Step Protocol

```
 WORK ORDER (from EM)
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
         No Co-Authored-By / no AI attribution
         ─────────────────────────────────────────────
 Step 7  REPORT RESULTS
         Write work-output/phase-N-result.md
         Fields: FILES_MODIFIED, TEST_TIER,
                 LINT_STATUS, TESTS_PASSED,
                 SENTINEL_RESPONSE (if sentinel ran)
         Update phase-N-status.md [STATUS: COMPLETE]
      │
      ▼
 back to EM
```

---

### Pipeline 3 — QA 6-Step Protocol

```
 SE result (work-output/phase-N-result.md)
      │
      ▼
 Step 1  GATHER CONTEXT
         Read CLAUDE.md, MEMORY.md, SE result file
         Get full git diff. Read all modified files.
         ─────────────────────────────────────────────
 Step 2  STRUCTURAL REVIEW
         Shell syntax (bash -n), shellcheck
         Anti-patterns: which/egrep/backtick/|| true
         Code quality: dead code, path validation,
         missing quotes, hardcoded paths
         ─────────────────────────────────────────────
 Step 2.5  BASH 4.1 COMPLIANCE  (MANDATORY — grep, don't trust SE)
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
           Verify SE's SENTINEL_RESPONSE is adequate
           Elevate unaddressed MUST-FIX items
         ─────────────────────────────────────────────
 Step 6  VERDICT
         Write qa-phase-N-verdict.md
         Findings: MUST-FIX / SHOULD-FIX / INFORMATIONAL
         Verdict: APPROVED | CHANGES_REQUESTED | REJECTED
         Note ESCALATION_RECOMMENDED if complexity exceeded
      │
      ▼
 back to EM
```

---

### Pipeline 4 — Sentinel 4-Pass Protocol  [opus, parallel with QA]

```
 SE result (work-output/phase-N-result.md)
      │
      ▼
 Gather Context
   Read CLAUDE.md, MEMORY.md, SE result
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
      │
      ▼
 QA reads sentinel-N.md at Step 5.5
 SE must respond to all BLOCKING_CONCERN + MUST-FIX in result file
```

---

### Pipeline 5 — Verification Gate & Merge Decision

```
 SE result classified by test-strategy tier
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
          │  QA (gate mode)  ∥  UAT                   │               │
          │  Sentinel already ran during SE phase     │     LITE GATE │
          └──────────────────┬───────────────────────┘    QA only ◄──┘
                             │                             No UAT
                             │
                             ▼
 ┌─────────────────────────────────┐   ┌────────────────────────────┐
 │ QA      │ UAT      │ Action     │   │ QA-lite     │ Action       │
 │─────────┼──────────┼────────────│   │─────────────┼──────────────│
 │APPROVED │APPROVED  │ MERGE ✓    │   │APPROVED     │ MERGE ✓      │
 │APPROVED │CONCERNS  │ MERGE+note │   │CHG_REQ      │ SE fix (×3)  │
 │APPROVED │REJECTED  │ SE fix (×3)│   │ESCALATION   │ → FULL GATE  │
 │CHG_REQ  │any       │ SE fix (×3)│   └────────────────────────────┘
 │REJECTED │any       │ BLOCKED    │
 └─────────────────────────────────┘
      │ MERGE_READY
      ▼
 Post-merge: /mem-save + mark PLAN.md DONE + recommend next phase
```

---

### Pipeline 6 — Look-Ahead Optimization

```
 Eligibility:
   ✓ N+1 prereqs met (N in-progress OK if N+1 doesn't depend on N's output)
   ✓ Planner validated: PARALLEL_SAFE true for N and N+1
   ✓ SE(N) STATUS: COMPLETE

 Standard:  SE(N)──QA(N)──────────────SE(N+1)──QA(N+1)   4 time units
 Pipeline:  SE(N)──QA(N)──────────────────────────────
                   SE(N+1, worktree)───QA(N+1)──────────  3 time units

 Safety rules:
   QA(N) APPROVED      → merge N, then merge N+1 after its QA passes
   QA(N) CHG_REQUESTED → hold N+1 worktree until N is re-approved
   QA(N) REJECTED      → discard N+1 worktree, resolve N first
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
| `/em` | EM briefing — assess state, prioritize, delegate | Start of session, project planning |
| `/em status` | Cross-project status snapshot | Quick overview of all projects |
| `/em health` | Live health dashboard | Pre-release sanity check |
| `/em <project>` | Focus on one project | Deep-dive on APF, BFD, LMD, etc. |
| `/em phase N` | Dispatch SE for phase N | Execute a specific plan phase |
| `/em batch` | Batch same-class changes | Cross-project consistency work |
| `/em release` | Release coordination mode | Ship a version |
| `/em audit` | Full audit pipeline | Comprehensive code review |
| `/po` | Product Owner intake | Ambiguous or strategic requests |
| `/se` | SE picks next pending phase | Hands-free execution |
| `/se N` | SE executes phase N | Targeted phase work |
| `/se <text>` | SE executes freeform task | Ad-hoc engineering work |
| `/qa` | QA reviews latest SE work (full 6-step or lite 3-step) | Post-implementation gate |
| `/uat` | UAT validates from user POV (tier 2+ only) | Operational readiness check |

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

---

## 4. Common Workflows

### Start a New Session
```
/reload                          # Load context
/em status                       # See all projects
/proj-health                     # Live health check
```

### Execute Plan Phases (Orchestrated)
```
/em bfd                          # EM assesses BFD state
/em phase 3                      # EM dispatches SE for phase 3
                                 # Scope validates refs
                                 # Challenger reviews plan (tier 2+)
                                 # SE implements, commits, reports
                                 # Sentinel runs adversarial review (tier 2+)
                                 # EM classifies tier → routes QA-lite or QA+UAT
                                 # QA approves or requests changes
```

### Execute Plan Phases (Direct)
```
/se 3                            # SE executes phase 3 directly
/qa                              # QA reviews the work
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
/em                              # EM prioritizes findings
/se                              # SE fixes phase by phase
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
/em batch                        # EM coordinates batch fixes
```

### Shared Library Update
```
cd <canonical-lib>               # Work in canonical repo
/se                              # Implement changes
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
|  | 1.0.0       |                     | pkg_lib     |                      |
|  +-------------+                     | v1.0.2      |                      |
|                                      +-------------+                      |
|  +-------------+                                                          |
|  | Overwatch   |  Vue 3 dashboard — monitors all projects                 |
|  | 1.5         |                                                          |
|  +-------------+                                                          |
+===========================================================================+
```

---

## 6. File-Based Handoff Protocol

```
work-output/
├── current-phase.md          # EM -> SE: work order with phase details
├── implementation-plan.md    # SE -> Challenger: plan-only mode output
├── plan-validation-N.md      # Planner -> EM: ref validation (or skipped)
├── scope-workorder-P<N>.md   # Scope -> EM: work order draft + context
├── challenge-N.md            # Challenger -> SE: pre-impl findings
├── phase-N-status.md         # SE -> EM: progress updates (in-flight)
├── phase-N-result.md         # SE -> EM: completion report
├── test-registry-P<N>.md     # SE -> QA: test results (commit, counts, Docker ID)
├── test-lock-P<N>.md         # SE/QA/UAT: test execution state coordination
├── sentinel-N.md             # Sentinel -> QA: 4-pass findings
├── sentinel-lib-N.md         # Sentinel -> QA: 2-pass library integration findings
├── ux-review-N.md            # UX Reviewer -> SE: design/output review
├── qa-phase-N-status.md      # QA -> EM: review progress (LITE or FULL mode)
├── qa-phase-N-verdict.md     # QA -> EM: verdict (QA_MODE: LITE|FULL)
├── uat-phase-N-verdict.md    # UAT -> EM: acceptance (tier 2+ only)
└── pipeline-metrics.jsonl    # EM: append-only phase completion metrics

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

EM classifies each SE result by test-strategy tier and routes accordingly:

```
+--------+-------------------+-----------+-----+-------------------------+
| Tier   | Change Scope      | QA Mode   | UAT | Time Saved              |
+--------+-------------------+-----------+-----+-------------------------+
|  0     | Docs only         | gate-lite | no  | ~3-4 min (skip 3 steps) |
|  1     | Single scope      | gate-lite | no  | ~3-4 min (skip 3 steps) |
|  2     | Multi-file core   | gate full | yes | baseline                |
|  3-4   | Cross-OS / legacy | gate full | yes | baseline                |
+--------+-------------------+-----------+-----+-------------------------+

Override to full gate: Planner STALE, shared lib files, SE flagged concerns
```

### Planner Skip Conditions

Planner validation skipped when:
- Phase creates only new files (nothing to validate)
- Phase is docs-only or test-only
- PLAN updated within last 3 commits

Always runs for: core logic mods, cross-project deps, stale PLANs.

### Pipeline Look-Ahead

When consecutive phases have zero file overlap, SE(N+1) starts in a worktree
while QA(N) reviews phase N. QA rejection holds N+1 until resolved.

```
Without:  SE(4) ── QA(4) ── SE(5) ── QA(5)                    4 time units
With:     SE(4) ── QA(4) ──────────────────                    3 time units
                   SE(5) ── QA(5) ─────────
```

### Test Result Registry

SE writes `test-registry-P<N>.md` after test execution with commit hash, tier,
pass/fail counts, Docker image ID. QA reads this before running tests:
- **Tier 0-1:** QA may trust registry if COMMIT matches, TIER >=, FAILED == 0
- **Tier 2+:** QA always runs independently but reuses Docker images and
  compares baseline counts from the registry

### Agent Test Lock Protocol

`test-lock-P<N>.md` with STATE (IDLE/RUNNING/COMPLETE) enables passive
coordination between SE, QA, and UAT. Single-read, no polling — agents read
the lock once, decide whether to proceed or reuse results, and act. Primary
savings come from Docker image reuse, not from skipping test execution.

### Challenger Gate (Two-Dispatch Pattern)

For tier 2+ changes, EM dispatches SE in `plan-only` mode (Steps 1-2 only),
then dispatches Challenger to review the implementation plan, then re-dispatches
SE from Step 3 with challenge findings. Mandatory checkpoint in work orders:
`CHALLENGER: DISPATCHED | SKIPPED (<code>)`.

### Library Integration Sentinel

When a shared library sync introduces updated files in a consumer project,
EM dispatches Sentinel in LIBRARY_INTEGRATION mode — a lightweight 2-pass
review (Regression + Security) focused on sourcing/init patterns, API
mapping, and credential handling. Skips Anti-Slop and Performance (already
done on the canonical library release).

### UX Reviewer Expanded Triggers

UX Reviewer dispatches automatically in DESIGN_REVIEW mode (pre-implementation)
when phases touch: alert templates, display formatting, machine-readable output,
or when PLAN description mentions display/format/template/output/email keywords.
Shifts template iteration from post-impl (3-5 commits) to pre-impl (1-2).

### Pipeline Metrics

EM appends one JSONL line to `pipeline-metrics.jsonl` at each successful merge.
`/mem-save` harvests the JSONL into rolling averages stored in the project's
`pipeline-metrics.md` memory file. Tracks: fix cycle rate, Challenger dispatch
rate, Sentinel effectiveness, test registry trust rate, UX dispatch rate.

### EM Context Delegation

Scope agent assembles work order drafts (`scope-workorder-P<N>.md`) as the
default path for standard phases. EM reads the ~2-3K token structured summary
instead of doing ~15-20K tokens of raw code search, sustaining 5-8 phases per
session vs 2-3. EM retains full IC authority and steps in directly when
judgment, speed, or authority is needed.

---

## 8. Quick Reference Card

```
PERSONAS         AUDIT            RELEASE          PROJECT          MEMORY
─────────        ─────            ───────          ───────          ──────
/em              /audit           /rel-prep        /proj-status     /mem-save
/po              /audit-quick     /rel-chg-dedup   /proj-cross      /mem-audit
/se              /audit-delta     /rel-chg-diff    /proj-cross-aud  /mem-compact
/qa              /audit-plan      /rel-scrub       /proj-lib-sync
/uat             /audit-feedback  /rel-merge       /proj-scaffold   CODE
/scope                            /rel-ship        /proj-health     ────
/modernize                        /rel-notes                        /code-validate
                                                                    /code-grep
INFRA                                              TESTING
─────                                              ───────
/ci-setup                                          /test-strategy
/lib-release                                       /test-impact
                                                   /test-dedup
/onboard
/reload
```

**Total: 10 agents + 65 commands + 11 scripts = 86 primitives + pipeline optimization protocols**
