# RDF — Visual Reference

---

## 1. RDF Architecture

System-level overview: canonical sources, profiles, adapters, CLI tools.

```mermaid
flowchart TD
    subgraph Canonical["Canonical Source (tool-agnostic)"]
        Agents[agents/*.md\n6 universal agents]
        Commands[commands/*.md\n23 commands]
        Scripts[scripts/*.sh]
        Reference[reference/*.md]
    end

    subgraph Profiles["Profile System"]
        Core[core/\ngovernance-template.md\nreference/framework.md]
        Shell[shell/\ngovernance-template.md\nreference/os-compat.md]
        Python[python/\ngovernance-template.md]
        Frontend[frontend/\ngovernance-template.md\nreference/browser-matrix.md]
        Database[database/\ngovernance-template.md]
        Go[go/\ngovernance-template.md]
    end

    Core --> Shell
    Core --> Python
    Core --> Frontend
    Core --> Database
    Core --> Go

    subgraph Adapters["Adapters (tool-specific)"]
        CC[Claude Code\nagent-meta.json\nhooks.json\noutput/]
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
        Generate[rdf generate\nadapter builder]
        ProfileCmd[rdf profile\nprofile manager]
        Init[rdf init\nproject onboarding]
        Doctor[rdf doctor\ndrift detection]
        State[rdf state\nproject JSON]
    end

    style Agents fill:#553c9a,color:#fff
    style Commands fill:#553c9a,color:#fff
    style Scripts fill:#553c9a,color:#fff
    style Reference fill:#553c9a,color:#fff
    style Core fill:#2b6cb0,color:#fff
    style Shell fill:#2b6cb0,color:#fff
    style Python fill:#2b6cb0,color:#fff
    style Frontend fill:#2b6cb0,color:#fff
    style Database fill:#2b6cb0,color:#fff
    style Go fill:#2b6cb0,color:#fff
    style CC fill:#276749,color:#fff
    style Gemini fill:#276749,color:#fff
    style AgentsMD fill:#276749,color:#fff
    style Generate fill:#975a16,color:#fff
    style ProfileCmd fill:#975a16,color:#fff
    style Init fill:#975a16,color:#fff
    style Doctor fill:#975a16,color:#fff
    style State fill:#975a16,color:#fff
```

---

## 2. Project Ecosystem

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

## 3. Engineering Pipeline

The v3 lifecycle from user request to merge. Quality gates are selected by
scope classification, derived automatically from the phase's file list and
governance context.

```mermaid
flowchart TD
    User([User Request])

    User --> Planner

    subgraph PlanPhase["Planning"]
        Planner{{planner — research + spec + plan}}
    end

    Planner -->|spec ready| ChallengeReview

    subgraph PreImpl["Pre-Implementation"]
        ChallengeReview{{reviewer — challenge mode}}
    end

    ChallengeReview -->|challenge findings| Planner
    Planner -->|PLAN.md approved| Dispatch

    subgraph Execution["Execution Loop"]
        Dispatch[dispatcher — orchestrator]
        Dispatch -->|phase context| Eng
        Eng[engineer — TDD]
        Eng -->|result + evidence| Dispatch
        Dispatch --> Gate1[Gate 1: Self-Report]
        Gate1 --> Gate2[Gate 2: qa]
        Gate2 --> Gate3[Gate 3: reviewer sentinel]
        Gate3 --> Gate4[Gate 4: uat]
    end

    Gate4 --> Decision{All selected\ngates pass?}

    Decision -->|yes| MorePhases{More phases?}
    Decision -->|no, retries left| Eng
    Decision -->|retries exhausted| Escalate([Surface to User])

    MorePhases -->|yes| Dispatch
    MorePhases -->|no| Ship([/r:ship — Merge])

    style User fill:#4a5568,color:#fff,stroke:#2d3748
    style Ship fill:#276749,color:#fff,stroke:#22543d
    style Escalate fill:#9b2c2c,color:#fff,stroke:#742a2a
    style Planner fill:#2b6cb0,color:#fff,stroke:#2c5282
    style ChallengeReview fill:#9b2c2c,color:#fff,stroke:#742a2a
    style Dispatch fill:#2b6cb0,color:#fff,stroke:#2c5282
    style Eng fill:#553c9a,color:#fff,stroke:#44337a
    style Gate1 fill:#553c9a,color:#fff,stroke:#44337a
    style Gate2 fill:#975a16,color:#fff,stroke:#744210
    style Gate3 fill:#9b2c2c,color:#fff,stroke:#742a2a
    style Gate4 fill:#975a16,color:#fff,stroke:#744210
    style Decision fill:#2b6cb0,color:#fff,stroke:#2c5282
    style MorePhases fill:#2b6cb0,color:#fff,stroke:#2c5282
```

---

## 4. Quality Gates (Scope Classification)

Phase content determines which gates the dispatcher activates. Scope is
derived automatically from the file list, description, and governance
context — no manual tagging required.

```
Phase Content → Scope Classification → Gate Selection

  file count       scope:docs          G1
  path patterns    scope:focused       G1+G2
  description      scope:multi-file    G1+G2+G3-lite
  governance       scope:cross-cutting G1+G2+G3-full
  signals          scope:sensitive     G1+G2+G3-full
                   + CLI/help files?   +G4
```

```mermaid
flowchart TD
    Result([Engineer Result]) --> Scope{Scope\nClassification}

    Scope -->|"scope:docs\nchangelog, README, comments"| G1Only[Gate 1 Only\nEngineer Self-Report]
    Scope -->|"scope:focused\nsingle file, config, one function"| G1G2[Gates 1 + 2\nSelf-Report + QA]
    Scope -->|"scope:multi-file\n2+ files, standard feature/refactor"| G1G2G3L[Gates 1 + 2 + 3-lite\nSelf-Report + QA + Sentinel 2-pass]
    Scope -->|"scope:cross-cutting\ninstall, CLI, cross-OS, breaking"| G1G2G3F[Gates 1 + 2 + 3-full\nSelf-Report + QA + Sentinel 4-pass]
    Scope -->|"scope:sensitive\nsecurity, shared libs, data migration"| G1G2G3S[Gates 1 + 2 + 3-full\nSelf-Report + QA + Sentinel 4-pass]
    Scope -->|"+ CLI/help files"| G4[Add Gate 4\n+ UAT]

    G1Only --> Verdict
    G1G2 --> Verdict
    G1G2G3L --> Verdict
    G1G2G3F --> Verdict
    G1G2G3S --> Verdict
    G4 --> Verdict

    Verdict{Verdict}

    Verdict -->|APPROVED| Complete([Phase Complete])
    Verdict -->|CHANGES_REQUESTED| Fix([Engineer Fix\n3 max retries])
    Verdict -->|REJECTED| Blocked([Surface to User])

    style Result fill:#553c9a,color:#fff
    style Scope fill:#2b6cb0,color:#fff
    style G1Only fill:#553c9a,color:#fff
    style G1G2 fill:#553c9a,color:#fff
    style G1G2G3L fill:#975a16,color:#fff
    style G1G2G3F fill:#9b2c2c,color:#fff
    style G1G2G3S fill:#9b2c2c,color:#fff
    style G4 fill:#975a16,color:#fff
    style Complete fill:#276749,color:#fff
    style Fix fill:#9b2c2c,color:#fff
    style Blocked fill:#9b2c2c,color:#fff
    style Verdict fill:#2b6cb0,color:#fff
```

| Scope | Description | Gates | Agents |
|---|---|---|---|
| `docs` | changelog, README, comments | 1 | engineer (self-report) |
| `focused` | single file, config, one function | 1 + 2 | engineer + qa |
| `multi-file` | 2+ files, standard feature/refactor | 1 + 2 + 3-lite | engineer + qa + reviewer (2-pass) |
| `cross-cutting` | install, CLI, cross-OS, breaking changes | 1 + 2 + 3-full | engineer + qa + reviewer (4-pass) |
| `sensitive` | security, shared libs, data migration | 1 + 2 + 3-full | engineer + qa + reviewer (4-pass) |
| any + CLI/help files | user-facing output or help text | add Gate 4 | + uat |

---

## 5. File-Based Handoff

Detailed sequence showing the full v3 lifecycle with file artifacts.

```mermaid
sequenceDiagram
    participant User
    participant Planner as planner
    participant Reviewer as reviewer
    participant Dispatcher as dispatcher
    participant Engineer as engineer
    participant QA as qa
    participant UAT as uat

    User->>Planner: /r:plan
    activate Planner
    Planner->>Planner: discover, brainstorm, spec

    opt Challenge Gate
        Planner->>Reviewer: dispatch challenge mode
        activate Reviewer
        Reviewer->>Planner: challenge findings
        deactivate Reviewer
        Planner->>Planner: revise spec
    end

    Planner->>Planner: decompose spec into PLAN.md
    Planner->>User: PLAN.md ready
    deactivate Planner

    User->>Dispatcher: /build [N]
    activate Dispatcher
    Dispatcher->>Dispatcher: read PLAN.md phase N
    Dispatcher->>Dispatcher: load governance, select gates

    Dispatcher->>Engineer: phase context + governance
    activate Engineer
    Note over Engineer: TDD: red, green, refactor
    Note over Engineer: writes phase-N-status.md
    Engineer->>Dispatcher: phase-N-result.md
    deactivate Engineer

    opt Gate 2: QA
        Dispatcher->>QA: verification scope
        activate QA
        QA->>Dispatcher: qa-phase-N-verdict.md
        deactivate QA
    end

    opt Gate 3: Reviewer Sentinel
        Dispatcher->>Reviewer: sentinel mode
        activate Reviewer
        Reviewer->>Dispatcher: sentinel-N.md
        deactivate Reviewer
    end

    opt Gate 4: UAT
        Dispatcher->>UAT: acceptance scope
        activate UAT
        UAT->>Dispatcher: uat-phase-N-verdict.md
        deactivate UAT
    end

    alt All gates pass
        Dispatcher->>Dispatcher: commit, update PLAN.md
    else Gate failure, retries left
        Dispatcher->>Engineer: feedback, re-enter TDD
    else Retries exhausted
        Dispatcher->>User: surface failure context
    end

    deactivate Dispatcher
```

---

## 6. Engineer TDD Protocol

The engineer's implementation cycle, dispatched by the dispatcher.

```mermaid
flowchart LR
    Phase([Phase Context]) --> Setup

    Setup[Setup\nRead governance:\nconventions\nconstraints\nanti-patterns] --> Red

    Red[RED\nWrite Failing Test] --> Green[GREEN\nMinimum Code]
    Green --> Refactor[REFACTOR\nClean, Keep Green]
    Refactor -->|next requirement| Red
    Refactor -->|all requirements met| Report

    Report[Evidence Report\ntest names\nred/green output\ncoverage delta\nfiles changed] --> Result([Result to Dispatcher])

    style Setup fill:#553c9a,color:#fff
    style Red fill:#9b2c2c,color:#fff
    style Green fill:#276749,color:#fff
    style Refactor fill:#553c9a,color:#fff
    style Report fill:#975a16,color:#fff
    style Phase fill:#4a5568,color:#fff
    style Result fill:#276749,color:#fff
```

**Steps:**
1. **Setup** — Read governance index, load conventions, constraints, anti-patterns.
2. **Red** — Write a failing test for the acceptance criteria.
3. **Green** — Minimum implementation to pass.
4. **Refactor** — Clean up, keep green. Repeat for each requirement.
5. **Evidence** — Structured report: test names, red/green output, coverage, files.

---

## 7. Reviewer Modes

The reviewer operates in two modes depending on invocation.

```mermaid
flowchart TD
    Input([Dispatch]) --> Mode{Mode?}

    Mode -->|"--challenge\n(pre-impl)"| C1
    Mode -->|"--sentinel\n(post-impl)"| P1

    C1[Design Flaws\narchitectural risks] --> COut
    C2[Edge Cases\nboundary conditions] --> COut
    C3[Simpler Alternatives\nover-engineering] --> COut
    C4[Risk Assessment\nblast radius] --> COut
    Mode -->|"--challenge"| C2
    Mode -->|"--challenge"| C3
    Mode -->|"--challenge"| C4

    COut([Challenge Report\nMUST-FIX / SHOULD-FIX / INFORMATIONAL])

    P1[Pass 1: Anti-Slop\nnaming, copy-paste, scope creep] --> SOut
    P2[Pass 2: Regression\nbehavior, contracts, exit codes] --> SOut
    P3[Pass 3: Security\ninjection, credentials, eval] --> SOut
    P4[Pass 4: Performance\nO n2, spawning, redundant I/O] --> SOut
    Mode -->|"--sentinel"| P2
    Mode -->|"--sentinel"| P3
    Mode -->|"--sentinel"| P4

    SOut([Sentinel Report\nMUST-FIX / SHOULD-FIX / INFORMATIONAL])

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

| Mode | Lenses | Focus | Invoked By |
|------|--------|-------|------------|
| Challenge | Design, edge cases, alternatives, risk | Specs and plans | planner, `/review --challenge` |
| Sentinel | Anti-slop, regression, security, performance | Diffs | dispatcher, `/review --sentinel` |

---

## 8. Audit Pipeline

`/r:audit` dispatches 4 parallel subagents, deduplicates findings, outputs AUDIT.md.

```mermaid
flowchart TD
    Trigger([/r:audit]) --> Scope[Build audit context\nfrom governance]

    Scope --> Rev1[reviewer sentinel\nregression + anti-slop]
    Scope --> Rev2[reviewer sentinel\nsecurity focus]
    Scope --> Rev3[reviewer sentinel\nperformance focus]
    Scope --> QA1[qa\nstandards + lint + tests]

    Rev1 --> Dedup[Collect + Deduplicate\nmerge overlaps\nnormalize severity]
    Rev2 --> Dedup
    Rev3 --> Dedup
    QA1 --> Dedup

    Dedup --> Output([AUDIT.md\ncritical / major / minor\nremediation roadmap])

    style Trigger fill:#4a5568,color:#fff
    style Scope fill:#2b6cb0,color:#fff
    style Rev1 fill:#9b2c2c,color:#fff
    style Rev2 fill:#9b2c2c,color:#fff
    style Rev3 fill:#9b2c2c,color:#fff
    style QA1 fill:#975a16,color:#fff
    style Dedup fill:#2b6cb0,color:#fff
    style Output fill:#276749,color:#fff
```

---

## 9. Issue Hierarchy

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
