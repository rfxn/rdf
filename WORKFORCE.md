# RDF Agent Workforce

---

## 1. Organization Chart

```
RDF — UNIVERSAL AGENT WORKFORCE
════════════════════════════════════════════════════════════════════

USER
 │
 ├─► /r-start    (self-contained)     Session Init — loads context,
 │                                     scans state; dispatches nothing
 │
 ├─► /r-plan     (planner inline,      Research & Planning
 │                session model;       Specs, plans; mandatory challenge
 │                Fable session        review before presenting for approval
 │                advised; direct
 │                dispatch available)
 │                └─► reviewer         Challenge Mode — pre-impl (opus·high)
 │
 ├─► /r-build ─► dispatcher  (opus)   Plan Execution
 │                │                    Phase orchestration, quality gates
 │                │
 │                ├─► engineer  (opus)  Universal Implementation (xhigh; focused variant medium)
 │                │                    TDD, governance-driven protocol
 │                │
 │                ├─► qa  (opus)       Verification Gate — read-only
 │                │                    Lint, tests, anti-patterns
 │                │
 │                ├─► reviewer         Adversarial Review — read-only
 │                │                    Challenge mode (pre-impl, opus·high)
 │                │                    Sentinel mode (post-impl, opus·xhigh, 2-3 pass)
 │                │
 │                └─► uat  (opus)     User Acceptance — read-only
 │                                    End-user persona, real scenarios
 │
 └─► /r-audit ──► reviewer(×3) + qa   Full Codebase Audit
                   parallel dispatch

════════════════════════════════════════════════════════════════════
LIFECYCLE PIPELINE
  USER → /r-plan (planner + mandatory reviewer challenge pass, opus·high)
       → /r-build [N] (dispatcher → engineer → qa/reviewer/uat gates)
       → /r-ship → MERGE
════════════════════════════════════════════════════════════════════
```

### Model Summary

| Agent                          | Model · Effort          |
|--------------------------------|-------------------------|
| planner                        | fable · high            |
| dispatcher                     | opus · high             |
| engineer / engineer-focused    | opus · xhigh / medium   |
| reviewer / reviewer-challenge  | opus · xhigh / high     |
| qa, uat                        | opus · medium           |

Routing is by agent name: the dispatcher sends `scope:docs`/`scope:focused`
phases to rdf-engineer-focused and escalates a failed focused phase to
rdf-engineer; challenge reviews dispatch rdf-reviewer-challenge. Model and
effort live in `adapters/claude-code/agent-meta.json`.

### Concurrent-Session Primitives (3.1.0)

| Primitive | Owner | Purpose |
|-----------|-------|---------|
| `RDF_SESSION_ID` (CC session id, else UUIDv7) | session shell + every subagent | Identity inherited via env |
| Scoped state filenames | engineer, qa, reviewer, dispatcher | `<basepath>-<SESSION_ID>.<ext>` |
| Worktree pre-commit hook | dispatcher (installer), engineer's own commit | Physical scope enforcement |
| Pre-aggregation dirty check | engineer Setup | Fail fast before build steps |
| `**Tests-may-touch:**` (plan schema Rule 8) | planner declares, all three call sites enforce | Pre-authorized flex zone (≤30 lines, ≤3 files) |

Helpers: `state/rdf-bus.sh` (`rdf_session_init`, `rdf_scoped_filename`,
`rdf_session_short`, `rdf_parse_phase_scope`).
Hook source: `state/git-hooks/pre-commit`.

---

## 2. Agent Details

### planner (fable · high)

Research-driven collaborative planner. Brainstorms ideas, researches best
practices, challenges assumptions, writes specs and implementation plans.
Runs inline in `/r-spec` and `/r-plan` (the command bodies are the
planner protocol); direct dispatch via the Agent tool is also available.

### dispatcher (opus · high)

Plan execution orchestrator. Reads PLAN.md, executes phases via TDD,
dispatches engineer/qa/uat/reviewer subagents, enforces quality gates.
Invoked via `/r-build`.

### engineer (opus · xhigh; focused variant medium)

Universal implementation engineer. Follows TDD, reads governance files
for domain-specific conventions and constraints. Behavior is shaped by
the project's governance files, not by baked-in domain knowledge.
Dispatched by the dispatcher for plan phase execution.

### qa (opus · medium)

Verification gate. Reads governance files for project-specific checks
(lint commands, test commands, anti-pattern patterns). Read-only -- cannot
modify source files. Dispatched by dispatcher or invoked via `/r-verify`.

### uat (opus · medium)

User acceptance testing. Runs real-world scenarios from an end-user
persona. Read-only -- cannot modify source files. Dispatched by
dispatcher or invoked via `/r-test`.

### reviewer (opus · xhigh sentinel / high challenge variant)

Adversarial reviewer with two modes:
- **Challenge mode** (pre-impl): Reviews specs and plans for design flaws,
  edge cases, missing considerations, and simpler alternatives. In Challenge
  mode, falsifiable MUST-FIX assertions require a `/r-verify-claim` probe
  before the finding is emitted.
- **Sentinel mode** (post-impl): 2-pass lite (anti-slop, regression) or
  3-pass full (adds security) code review.

Read-only -- cannot modify source files. Dispatched by planner,
dispatcher, or invoked via `/r-review`.

---

## 3. Command Reference

### Lifecycle Commands (21)

| Command | Slash | Dispatches | Purpose |
|---------|-------|------------|---------|
| r-init | /r-init | -- | Governance initialization |
| r-start | /r-start | -- | Session initialization |
| r-save | /r-save | -- | Session state sync |
| r-plan | /r-plan | reviewer | Planning workflow (planner runs inline) |
| r-spec | /r-spec | reviewer | Specification authoring |
| r-mode | /r-mode | -- | Switch operational mode |
| r-status | /r-status | -- | Project health dashboard |
| r-tasks | /r-tasks | -- | Task list status |
| r-refresh | /r-refresh | -- | Governance refresh |
| r-sync | /r-sync | -- | Canonical source sync |
| r-context-audit | /r-context-audit | -- | Context-window overhead audit |
| r-audit | /r-audit | reviewer, qa | Full codebase audit |
| r-audit-slop | /r-audit-slop | engineer, reviewer | Discovery-first AI slop audit (engineer x3, reviewer sentinel) |
| r-ship | /r-ship | qa, reviewer | Release workflow |
| r-build | /r-build | dispatcher, qa | Execute plan phase |
| r-vpe | /r-vpe | -- | Pipeline orchestrator |
| r-verify | /r-verify | qa | QA verification |
| r-verify-claim | /r-verify-claim | -- | Falsifiable claim verification (5 classes) |
| r-test | /r-test | uat | UAT acceptance |
| r-review | /r-review | reviewer | Adversarial review |
| r-review-answer | /r-review-answer | -- | Route review findings (FIX/REBUT/DEFER) |

### Utility Commands (16)

| Command | Slash | Purpose |
|---------|-------|---------|
| r-util-mem-compact | /r-util-mem-compact | Archive stale MEMORY.md entries |
| r-util-mem-audit | /r-util-mem-audit | Fact-check MEMORY.md against live state |
| r-util-claudemd-review | /r-util-claudemd-review | Review CLAUDE.md for improvements + drift |
| r-util-chg-gen | /r-util-chg-gen | Generate changelog from diff |
| r-util-chg-dedup | /r-util-chg-dedup | Deduplicate changelog entries |
| r-util-rel-squash | /r-util-rel-squash | Release branch squash plan + execution |
| r-util-doc-gen | /r-util-doc-gen | Generate documentation |
| r-util-ci-gen | /r-util-ci-gen | Generate CI workflow |
| r-util-lib-sync | /r-util-lib-sync | Cross-project library drift detection |
| r-util-lib-release | /r-util-lib-release | Shared library release lifecycle |
| r-util-proj-cross | /r-util-proj-cross | Cross-project convention drift analysis |
| r-util-code-scan | /r-util-code-scan | Pattern-class bug finder |
| r-util-code-map | /r-util-code-map | AST-style structural map for large source files |
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
/r-review --sentinel             # Post-implementation sentinel review (2-3 pass)
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

**Total: 6 agents + 37 commands + 16 scripts = 59 primitives**
