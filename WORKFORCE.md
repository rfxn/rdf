# RDF 3.0 Agent Workforce

---

## 1. Organization Chart

```
RDF 3.0 — UNIVERSAL AGENT WORKFORCE
════════════════════════════════════════════════════════════════════

USER
 │
 ├─► /r-plan ──► planner  (opus)      Research & Planning
 │                                     Specs, plans, brainstorming
 │
 ├─► /r-start ─► dispatcher  (sonnet) Plan Execution
 │   /r-build     │                    Phase orchestration, quality gates
 │                │
 │                ├─► engineer  (opus)  Universal Implementation
 │                │                    TDD, governance-driven protocol
 │                │
 │                ├─► qa  (sonnet)     Verification Gate — read-only
 │                │                    Lint, tests, anti-patterns
 │                │
 │                ├─► reviewer  (opus) Adversarial Review — read-only
 │                │                    Challenge mode (pre-impl)
 │                │                    Sentinel mode (post-impl 4-pass)
 │                │
 │                └─► uat  (sonnet)   User Acceptance — read-only
 │                                    End-user persona, real scenarios
 │
 └─► /r-audit ──► reviewer(×3) + qa   Full Codebase Audit
                   parallel dispatch

════════════════════════════════════════════════════════════════════
LIFECYCLE PIPELINE
  USER → /r-plan (planner)
       → [/r-review --challenge (reviewer)]
       → /r-build [N] (dispatcher → engineer → qa/reviewer/uat gates)
       → /r-ship → MERGE
════════════════════════════════════════════════════════════════════
```

### Model Summary

| Model  | Agents                          |
|--------|---------------------------------|
| opus   | planner, engineer, reviewer     |
| sonnet | dispatcher, qa, uat             |

---

## 2. Agent Details

### planner (opus)

Research-driven collaborative planner. Brainstorms ideas, researches best
practices, challenges assumptions, writes specs and implementation plans.
Invoked via `/r-plan`.

### dispatcher (sonnet)

Plan execution orchestrator. Reads PLAN.md, executes phases via TDD,
dispatches engineer/qa/uat/reviewer subagents, enforces quality gates.
Invoked via `/r-start` or `/r-build`.

### engineer (opus)

Universal implementation engineer. Follows TDD, reads governance files
for domain-specific conventions and constraints. Behavior is shaped by
the project's governance files, not by baked-in domain knowledge.
Dispatched by the dispatcher for plan phase execution.

### qa (sonnet)

Verification gate. Reads governance files for project-specific checks
(lint commands, test commands, anti-pattern patterns). Read-only -- cannot
modify source files. Dispatched by dispatcher or invoked via `/r-verify`.

### uat (sonnet)

User acceptance testing. Runs real-world scenarios from an end-user
persona. Read-only -- cannot modify source files. Dispatched by
dispatcher or invoked via `/r-test`.

### reviewer (opus)

Adversarial reviewer with two modes:
- **Challenge mode** (pre-impl): Reviews specs and plans for design flaws,
  edge cases, missing considerations, and simpler alternatives. In Challenge
  mode, falsifiable MUST-FIX assertions require a `/r-verify-claim` probe
  before the finding is emitted.
- **Sentinel mode** (post-impl): 4-pass code review -- anti-slop,
  regression, security, performance.

Read-only -- cannot modify source files. Dispatched by planner,
dispatcher, or invoked via `/r-review`.

---

## 3. Command Reference

### Lifecycle Commands (20)

| Command | Slash | Dispatches | Purpose |
|---------|-------|------------|---------|
| r-init | /r-init | -- | Governance initialization |
| r-start | /r-start | dispatcher | Session initialization |
| r-save | /r-save | -- | Session state sync |
| r-plan | /r-plan | planner | Planning workflow |
| r-spec | /r-spec | -- | Specification authoring |
| r-mode | /r-mode | -- | Switch operational mode |
| r-status | /r-status | -- | Project health dashboard |
| r-tasks | /r-tasks | -- | Task list status |
| r-refresh | /r-refresh | -- | Governance refresh |
| r-sync | /r-sync | -- | Canonical source sync |
| r-context-audit | /r-context-audit | -- | Context-window overhead audit |
| r-audit | /r-audit | reviewer, qa | Full codebase audit |
| r-audit-slop | /r-audit-slop | 3x engineer + sentinel | Discovery-first AI slop audit |
| r-ship | /r-ship | qa, reviewer | Release workflow |
| r-build | /r-build | dispatcher | Execute plan phase |
| r-vpe | /r-vpe | -- | Pipeline orchestrator |
| r-verify | /r-verify | qa | QA verification |
| r-verify-claim | /r-verify-claim | -- | Falsifiable claim verification (5 classes) |
| r-test | /r-test | uat | UAT acceptance |
| r-review | /r-review | reviewer | Adversarial review |

### Utility Commands (14)

| Command | Slash | Purpose |
|---------|-------|---------|
| r-util-mem-compact | /r-util-mem-compact | Archive stale MEMORY.md entries |
| r-util-mem-audit | /r-util-mem-audit | Fact-check MEMORY.md against live state |
| r-util-chg-gen | /r-util-chg-gen | Generate changelog from diff |
| r-util-chg-dedup | /r-util-chg-dedup | Deduplicate changelog entries |
| r-util-rel-squash | /r-util-rel-squash | Release branch squash plan + execution |
| r-util-doc-gen | /r-util-doc-gen | Generate documentation |
| r-util-ci-gen | /r-util-ci-gen | Generate CI workflow |
| r-util-lib-sync | /r-util-lib-sync | Cross-project library drift detection |
| r-util-lib-release | /r-util-lib-release | Shared library release lifecycle |
| r-util-proj-cross | /r-util-proj-cross | Cross-project convention drift analysis |
| r-util-code-scan | /r-util-code-scan | Pattern-class bug finder |
| r-util-code-modernize | /r-util-code-modernize | Codebase modernization assessment |
| r-util-test-dedup | /r-util-test-dedup | Find duplicate/overlapping tests |
| r-util-test-scope | /r-util-test-scope | Test tier recommendation + impact mapping |

---

## 4. Common Workflows

### Start a New Session
```
/r-start                         # Load context, scan state
/r-status                        # Project health dashboard
```

### Plan and Execute
```
/r-plan                          # Planner researches + writes spec/plan
/r-build 1                       # Dispatcher executes phase 1
/r-verify                        # QA verification
/r-test                          # UAT acceptance
```

### Pre-Commit Verification
```
/r-verify                        # QA lint + anti-pattern check
```

### Adversarial Review
```
/r-review --challenge PLAN.md    # Pre-implementation challenge
/r-review --sentinel             # Post-implementation 4-pass review
```

### Release a Project
```
/r-ship                          # Full release workflow
```

### Full Audit Cycle
```
/r-audit                         # Parallel reviewer + qa audit
```

### Cross-Project Maintenance
```
/r-util-lib-sync                 # Check shared library drift
/r-util-lib-release              # Ship canonical library update
```

---

## 5. v2 to v3 Migration Reference

| v2 Agent | v3 Equivalent | Notes |
|----------|---------------|-------|
| mgr | dispatcher | Orchestration moved to dispatcher |
| po | planner | Requirements analysis moved to planner |
| scope | planner | Scoping folded into planner |
| sys-eng | engineer | Universal, governance-driven |
| sys-qa | qa | Universal, governance-driven |
| sys-uat | uat | Universal, governance-driven |
| sys-sentinel | reviewer (sentinel mode) | Merged into reviewer |
| sys-challenger | reviewer (challenge mode) | Merged into reviewer |
| sys-ux | reviewer (challenge mode) | UX review via challenge mode |
| sec-eng | engineer + governance | Security via governance files |
| fe-qa | qa + governance | Frontend QA via governance files |
| fe-uat | uat + governance | Frontend UAT via governance files |

| v2 Command | v3 Equivalent |
|------------|---------------|
| /mgr | /r-start, /r-build |
| /po | /r-plan |
| /scope | /r-plan |
| /sys-eng | /r-build |
| /sys-qa | /r-verify |
| /sys-uat | /r-test |
| /sys-sentinel | /r-review --sentinel |
| /sys-challenger | /r-review --challenge |
| /reload | /r-start |
| /status, /proj-status | /r-status |
| /audit | /r-audit |
| /rel-ship | /r-ship |
| /mem-compact | /r-util-mem-compact |
| /rel-chg-dedup | /r-util-chg-dedup |
| /test-dedup | /r-util-test-dedup |

**Total: 6 agents + 31 commands + 10 scripts = 47 primitives**
