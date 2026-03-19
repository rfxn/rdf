# RDF — Visual Reference

---

## 1. Engineering Pipeline

The v3 lifecycle from user request to merge. Quality gates are selected by
phase tags (risk level + type), not tier classification.

```mermaid
flowchart TD
    User([User Request])

    User --> Planner

    subgraph Planning
        Planner{{planner — research + spec + plan}}
    end

    Planner -->|spec ready| ReviewChallenge

    subgraph Pre-Implementation
        ReviewChallenge{{reviewer — challenge mode}}
    end

    ReviewChallenge -->|challenge findings| Planner
    Planner -->|PLAN.md approved| Dispatcher

    subgraph Orchestration
        Dispatcher[dispatcher — execution orchestrator]
    end

    Dispatcher -->|phase context + governance| Engineer

    subgraph Implementation
        Engineer[engineer — TDD implementation]
    end

    Engineer -->|result + TDD evidence| Dispatcher

    Dispatcher -->|phase tags select gates| Gates

    subgraph Quality Gates
        direction LR
        Gate1[Gate 1\nEngineer Self-Report]
        Gate2[Gate 2\nqa — verification]
        Gate3[Gate 3\nreviewer — sentinel]
        Gate4[Gate 4\nuat — acceptance]
    end

    Gates --> GateDecision{All gates pass?}

    GateDecision -->|yes| NextPhase{More phases?}
    GateDecision -->|no, retries left| Engineer
    GateDecision -->|no, retries exhausted| UserEscalation([Surface to User])

    NextPhase -->|yes| Dispatcher
    NextPhase -->|no| Ship

    Ship([/r:ship → Merge])

    style User fill:#4a5568,color:#fff,stroke:#2d3748
    style Ship fill:#276749,color:#fff,stroke:#22543d
    style UserEscalation fill:#9b2c2c,color:#fff,stroke:#742a2a
    style Planner fill:#2b6cb0,color:#fff,stroke:#2c5282
    style ReviewChallenge fill:#9b2c2c,color:#fff,stroke:#742a2a
    style Dispatcher fill:#2b6cb0,color:#fff,stroke:#2c5282
    style Engineer fill:#553c9a,color:#fff,stroke:#44337a
    style Gate1 fill:#553c9a,color:#fff,stroke:#44337a
    style Gate2 fill:#975a16,color:#fff,stroke:#744210
    style Gate3 fill:#9b2c2c,color:#fff,stroke:#742a2a
    style Gate4 fill:#975a16,color:#fff,stroke:#744210
    style GateDecision fill:#2b6cb0,color:#fff,stroke:#2c5282
    style NextPhase fill:#2b6cb0,color:#fff,stroke:#2c5282
```

---

## 2. Engineer TDD Protocol

```mermaid
flowchart LR
    subgraph Setup
        S1[Read Governance\nconventions · constraints\nverification · anti-patterns]
    end

    subgraph TDD Cycle
        direction LR
        Red[RED\nWrite Failing Test] --> Green[GREEN\nMinimum Implementation]
        Green --> Refactor[REFACTOR\nClean Up — Keep Green]
        Refactor -->|next requirement| Red
    end

    subgraph Evidence
        Report[Report Back\ntest names · red/green output\ncoverage delta · files changed]
    end

    Phase([Phase Context\nfrom dispatcher]) --> S1
    S1 --> Red
    Refactor --> Report
    Report --> Result([Result to Dispatcher])

    style S1 fill:#553c9a,color:#fff
    style Red fill:#9b2c2c,color:#fff
    style Green fill:#276749,color:#fff
    style Refactor fill:#553c9a,color:#fff
    style Report fill:#975a16,color:#fff
    style Phase fill:#4a5568,color:#fff
    style Result fill:#276749,color:#fff
```

**Step details:**
1. **Setup** — Read governance index, load conventions.md, constraints.md, verification.md, anti-patterns.md for the target project.
2. **Red** — Write a failing test that defines the acceptance criteria from the phase description.
3. **Green** — Write the minimum implementation to make the test pass.
4. **Refactor** — Clean up implementation while keeping all tests green. Repeat Red-Green-Refactor for each requirement.
5. **Evidence** — Report structured evidence: test names, red/green output, coverage delta, files changed.

---

## 3. Reviewer Modes

```mermaid
flowchart TD
    Input([Dispatch from\nplanner or dispatcher]) --> Mode{Mode?}

    Mode -->|challenge| Challenge
    Mode -->|sentinel| Sentinel

    subgraph Challenge Mode — Pre-Implementation
        direction LR
        C1[Design Flaws\narchitectural risks\nmissing constraints]
        C2[Edge Cases\nboundary conditions\nfailure modes]
        C3[Simpler Alternatives\nover-engineering\nexisting solutions]
        C4[Risk Assessment\nblast radius\nrollback complexity]
    end

    Challenge --> COut([challenge findings\nto planner])

    subgraph Sentinel Mode — Post-Implementation
        direction LR
        P1[Pass 1\nAnti-Slop\nnaming lies · copy-paste\npremature abstraction]
        P2[Pass 2\nRegression\nbehavioral continuity\ncaller contracts · exit codes]
        P3[Pass 3\nSecurity\ninjection · credentials\ntemp files · eval]
        P4[Pass 4\nPerformance\nO n² · process spawning\nredundant I/O]
    end

    Sentinel --> SOut([sentinel findings\nmax 20 · to dispatcher])

    style C1 fill:#9b2c2c,color:#fff
    style C2 fill:#9b2c2c,color:#fff
    style C3 fill:#9b2c2c,color:#fff
    style C4 fill:#9b2c2c,color:#fff
    style P1 fill:#9b2c2c,color:#fff
    style P2 fill:#9b2c2c,color:#fff
    style P3 fill:#9b2c2c,color:#fff
    style P4 fill:#9b2c2c,color:#fff
    style Input fill:#4a5568,color:#fff
    style Mode fill:#2b6cb0,color:#fff
    style COut fill:#975a16,color:#fff
    style SOut fill:#975a16,color:#fff
```

| Mode | Lens | Focus | Invoked By |
|------|------|-------|------------|
| Challenge | Design flaws, edge cases, simpler alternatives, risk | Specs and plans (pre-impl) | planner, `/review --challenge` |
| Sentinel: Anti-Slop | Naming lies, copy-paste, premature abstraction | Diffs (post-impl) | dispatcher, `/review --sentinel` |
| Sentinel: Regression | Behavioral continuity, caller contracts, exit codes | Diffs (post-impl) | dispatcher, `/review --sentinel` |
| Sentinel: Security | Injection, credentials, temp files, eval | Diffs (post-impl) | dispatcher, `/review --sentinel` |
| Sentinel: Performance | O(n²), process spawning, redundant I/O | Diffs (post-impl) | dispatcher, `/review --sentinel` |

---

## 4. Audit Pipeline

```mermaid
flowchart TD
    Trigger([/r:audit]) --> Dispatch

    Dispatch[dispatcher\nreads PLAN.md + codebase scope]

    Dispatch --> Par

    subgraph Par[Parallel Subagents]
        direction LR
        R1[reviewer — sentinel\nregression + anti-slop]
        R2[reviewer — sentinel\nsecurity]
        R3[reviewer — sentinel\nperformance]
        Q1[qa — standards\nlint · conventions · tests]
    end

    Par --> Collect

    subgraph Collect[Collect + Deduplicate]
        Dedup[Cross-agent dedup\nmerge overlapping findings\nnormalize severity]
    end

    Collect --> Output([AUDIT.md\n300-line cap\nP1 expanded · P2 table · P3 grouped])

    style Trigger fill:#4a5568,color:#fff
    style Dispatch fill:#2b6cb0,color:#fff
    style R1 fill:#9b2c2c,color:#fff
    style R2 fill:#9b2c2c,color:#fff
    style R3 fill:#9b2c2c,color:#fff
    style Q1 fill:#975a16,color:#fff
    style Dedup fill:#2b6cb0,color:#fff
    style Output fill:#276749,color:#fff
```

---

## 5. Quality Gates (Phase-Tag Based)

```mermaid
flowchart TD
    Engineer([Engineer Result]) --> Tags{Phase tags\nin PLAN.md}

    Tags -->|"risk:low\ntype:config"| G1Only[Gate 1 Only\nEngineer Self-Report]
    Tags -->|"risk:medium\ntype:feature\n(default)"| G1G2[Gates 1 + 2\nSelf-Report + QA]
    Tags -->|"risk:high\nor type:security"| G1G2G3[Gates 1 + 2 + 3\n+ Reviewer Sentinel]
    Tags -->|"type:user-facing"| G1G2G4[Gates 1 + 2 + 4\n+ UAT]
    Tags -->|"risk:high\ntype:user-facing"| AllGates[All 4 Gates]

    G1Only --> Decide
    G1G2 --> Decide
    G1G2G3 --> Decide
    G1G2G4 --> Decide
    AllGates --> Decide

    Decide{All selected\ngates pass?}

    Decide -->|APPROVED| Merge([Phase Complete])
    Decide -->|CHANGES_REQUESTED| Fix([Engineer Fix\n×3 max retries])
    Decide -->|REJECTED| Blocked([Surface to User])

    style Engineer fill:#553c9a,color:#fff
    style Tags fill:#2b6cb0,color:#fff
    style G1Only fill:#553c9a,color:#fff
    style G1G2 fill:#975a16,color:#fff
    style G1G2G3 fill:#9b2c2c,color:#fff
    style G1G2G4 fill:#975a16,color:#fff
    style AllGates fill:#9b2c2c,color:#fff
    style Merge fill:#276749,color:#fff
    style Fix fill:#9b2c2c,color:#fff
    style Blocked fill:#9b2c2c,color:#fff
    style Decide fill:#2b6cb0,color:#fff
```

| Phase Tags | Gates | Agents Involved |
|---|---|---|
| `risk:low, type:config` | 1 | engineer (self-report) |
| `risk:medium, type:feature` (default) | 1 + 2 | engineer + qa |
| `risk:high` or `type:security` | 1 + 2 + 3 | engineer + qa + reviewer sentinel |
| `type:user-facing` | 1 + 2 + 4 | engineer + qa + uat |
| `risk:high, type:user-facing` | 1 + 2 + 3 + 4 | engineer + qa + reviewer sentinel + uat |

---

## 6. RDF Architecture (Target State)

```mermaid
flowchart TD
    subgraph Canonical["Canonical Source (tool-agnostic)"]
        Agents[agents/*.md]
        Commands[commands/*.md]
        Scripts[scripts/*.sh]
        Reference[reference/*.md]
    end

    subgraph Profiles["Profile System"]
        Core[core/\ncommit protocol\nmemory standards\nsession safety]
        SysEng[systems-engineering/\nbash 4.1 floor\nshell standards\nportability\ntesting]
        Frontend[frontend/\nVue/React conventions\nCSS standards\naccessibility]
    end

    Core --> SysEng
    Core --> Frontend

    subgraph Adapters["Adapters (tool-specific)"]
        CC[Claude Code\n.claude/ layout\nYAML frontmatter\nhooks.json]
        Gemini[Gemini CLI\nGEMINI.md\n.gemini/ config]
        AgentsMD[AGENTS.md\ncross-tool standard]
    end

    Canonical --> CC
    Canonical --> Gemini
    Canonical --> AgentsMD
    Profiles --> CC
    Profiles --> Gemini
    Profiles --> AgentsMD

    subgraph Tools["CLI Tools"]
        Init[rdf-init\nproject onboarding]
        Doctor[rdf-doctor\ndrift detection]
        Profile[rdf-profile\nprofile manager]
        Generate[rdf-generate\nadapter builder]
        State[rdf-state.sh\nproject state → JSON]
    end

    style Agents fill:#553c9a,color:#fff
    style Commands fill:#553c9a,color:#fff
    style Scripts fill:#553c9a,color:#fff
    style Reference fill:#553c9a,color:#fff
    style Core fill:#2b6cb0,color:#fff
    style SysEng fill:#2b6cb0,color:#fff
    style Frontend fill:#2b6cb0,color:#fff
    style CC fill:#276749,color:#fff
    style Gemini fill:#276749,color:#fff
    style AgentsMD fill:#276749,color:#fff
    style Init fill:#975a16,color:#fff
    style Doctor fill:#975a16,color:#fff
    style Profile fill:#975a16,color:#fff
    style Generate fill:#975a16,color:#fff
    style State fill:#975a16,color:#fff
```

---

## 7. Project Ecosystem

```mermaid
flowchart LR
    subgraph Products["Products"]
        APF[APF 2.0.2\nFirewall]
        BFD[BFD 2.0.1\nBrute Force Detection]
        LMD[LMD 2.0.1\nMalware Detection]
        Sig[Sigforge 1.1.3\nSignature Engine]
        Geo[geoscope 0.1.0\nGeoIP Pipeline]
    end

    subgraph Libraries["Shared Libraries"]
        tlog[tlog_lib v2.0.3]
        alert[alert_lib v1.0.4]
        elog[elog_lib v1.0.3]
        pkg[pkg_lib v1.0.4]
        geoip[geoip_lib v1.0.2]
        bats[batsman v1.2.0]
    end

    tlog --> APF & BFD & LMD
    alert --> BFD & LMD
    elog --> BFD & LMD
    pkg --> APF & BFD & LMD
    geoip --> APF & BFD
    bats --> APF & BFD & LMD & Sig & Geo

    style APF fill:#2b6cb0,color:#fff
    style BFD fill:#2b6cb0,color:#fff
    style LMD fill:#2b6cb0,color:#fff
    style Sig fill:#553c9a,color:#fff
    style Geo fill:#553c9a,color:#fff
    style tlog fill:#276749,color:#fff
    style alert fill:#276749,color:#fff
    style elog fill:#276749,color:#fff
    style pkg fill:#276749,color:#fff
    style geoip fill:#276749,color:#fff
    style bats fill:#276749,color:#fff
```

---

## 8. File-Based Handoff

```mermaid
sequenceDiagram
    participant User
    participant Planner
    participant Reviewer
    participant Dispatcher
    participant Engineer
    participant QA
    participant UAT

    User->>Planner: /r:plan (research + scope)
    activate Planner
    Planner->>Planner: discover → brainstorm → spec

    opt Challenge Gate (spec review)
        Planner->>Reviewer: dispatch challenge mode
        activate Reviewer
        Reviewer->>Planner: challenge findings
        deactivate Reviewer
        Planner->>Planner: address findings, revise spec
    end

    Planner->>Planner: decompose spec → PLAN.md
    Planner->>User: PLAN.md ready for review
    deactivate Planner

    User->>Dispatcher: /r:build [N]
    activate Dispatcher
    Dispatcher->>Dispatcher: read PLAN.md → identify phase N
    Dispatcher->>Dispatcher: read governance index → load context
    Dispatcher->>Dispatcher: determine gates from phase tags

    Dispatcher->>Engineer: phase context + governance + file boundaries
    activate Engineer
    Engineer->>Engineer: read governance (conventions, constraints)
    Engineer->>Engineer: TDD: red → green → refactor
    Note over Engineer: work-output/phase-N-status.md (progress)
    Engineer->>Dispatcher: phase-N-result.md (TDD evidence)
    deactivate Engineer

    Note over Dispatcher: Gate selection based on phase tags

    opt Gate 2: QA Verification
        Dispatcher->>QA: dispatch verification
        activate QA
        QA->>QA: lint + tests + anti-pattern greps
        QA->>Dispatcher: qa-phase-N-verdict.md
        deactivate QA
    end

    opt Gate 3: Reviewer Sentinel (risk:high or type:security)
        Dispatcher->>Reviewer: dispatch sentinel mode
        activate Reviewer
        Reviewer->>Reviewer: 4-pass: anti-slop, regression, security, performance
        Reviewer->>Dispatcher: sentinel-N.md (max 20 findings)
        deactivate Reviewer
    end

    opt Gate 4: UAT (type:user-facing)
        Dispatcher->>UAT: dispatch acceptance
        activate UAT
        UAT->>UAT: real-world scenarios, CLI interactions
        UAT->>Dispatcher: uat-phase-N-verdict.md
        deactivate UAT
    end

    alt All gates pass
        Dispatcher->>Dispatcher: commit, update PLAN.md status
        Dispatcher->>Dispatcher: next phase or complete
    else Gate failure (retries left)
        Dispatcher->>Engineer: feedback + re-enter TDD
    else Retries exhausted
        Dispatcher->>User: surface failure context
    end

    deactivate Dispatcher
```

---

## 9. Issue Hierarchy (v2)

GitHub issue granularity: initiatives for planning, releases for versions,
phases for execution, and task-completion comments for progress tracking.

```mermaid
flowchart TD
    Init([type:initiative\nPlanning Roadmap]) -->|matures into| Rel([type:release\nPlanning + Execution Roadmap])
    Rel -->|contains| Phase([type:phase\nPer-project board + Execution Roadmap])
    Phase -->|progress via| Comments([Task comments\nAppend-only on phase issue])

    style Init fill:#7057FF,color:#fff
    style Rel fill:#1D76DB,color:#fff
    style Phase fill:#5319E7,color:#fff
    style Comments fill:#276749,color:#fff
```

---

## 10. Two-Horizon Roadmap

The ecosystem project provides two roadmap views: Planning (big-picture
timeline by Target Date) and Execution (active work by Release iteration).

```mermaid
flowchart LR
    subgraph Ecosystem["Ecosystem Project (#4)"]
        subgraph PlanView["Planning Roadmap\n(Target Date field)"]
            I1[Initiative:\nMessenger Service\nQ3 2026]
            I2[Initiative:\ngeoscope v1.0\nQ2 2026]
            R1[Release:\nAPF 2.1.0\nApril 2026]
        end
        subgraph ExecView["Execution Roadmap\n(Release iteration)"]
            P1[Phase 1: NAT plumbing\nIn Progress]
            P2[Phase 2: Config\nReady]
            P3[Phase 3: Tests\nBacklog]
        end
    end

    I1 -.->|spawns| R1
    R1 -->|contains| P1 & P2 & P3

    style I1 fill:#7057FF,color:#fff
    style I2 fill:#7057FF,color:#fff
    style R1 fill:#1D76DB,color:#fff
    style P1 fill:#5319E7,color:#fff
    style P2 fill:#5319E7,color:#fff
    style P3 fill:#5319E7,color:#fff
```
