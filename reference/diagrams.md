# RDF — Visual Reference

---

## 1. Engineering Pipeline

The main work pipeline from user request to merge. Optional stages in dashed borders.
Tier 2+ changes activate the full gate (Scope, Challenger, Sentinel, UAT).

```mermaid
flowchart TD
    User([User Request])

    User --> PO

    subgraph Intake
        PO{{PO — Product Owner}}
    end

    PO -->|scoped problem| EM

    subgraph Orchestration
        EM[EM — Engineering Manager]
    end

    EM -->|tier 2+: Scope workorder| Scope
    EM -->|tier 0-1| SE

    subgraph Pre-Implementation
        Scope[Scope — Work Order Assembly]
        Scope -->|plan-only dispatch| SEPlan[SE — Plan Only]
        SEPlan -->|implementation-plan.md| Challenger
        Challenger{{Challenger — Pre-Impl Adversary}}
    end

    Challenger -->|challenge findings| SE
    Scope -->|scope-workorder| EM

    subgraph Implementation
        SE[SE — Senior Engineer]
        Registry[(test-registry-P N .md\ntest-lock-P N .md)]
    end

    SE -->|writes| Registry
    SE -->|result| QAGate

    subgraph Verification
        direction LR
        QAGate[QA — Verification Gate]
        Sentinel{{Sentinel — 4-Pass Review}}
    end

    Registry -->|reads: Docker reuse + baseline| QAGate
    SE -->|tier 2+ parallel| Sentinel
    Sentinel -->|findings| QAGate

    QAGate -->|touches output| UX

    subgraph Review
        UX{{UX Reviewer}}
    end

    UX --> UAT

    subgraph Acceptance
        UAT{{UAT — User Acceptance}}
    end

    UAT -->|verdict| Merge
    QAGate -->|tier 0-1| Merge

    Merge([Merge])

    style User fill:#4a5568,color:#fff,stroke:#2d3748
    style Merge fill:#276749,color:#fff,stroke:#22543d
    style SE fill:#553c9a,color:#fff,stroke:#44337a
    style SEPlan fill:#553c9a,color:#fff,stroke:#44337a
    style EM fill:#2b6cb0,color:#fff,stroke:#2c5282
    style QAGate fill:#975a16,color:#fff,stroke:#744210
    style Sentinel fill:#9b2c2c,color:#fff,stroke:#742a2a
    style Challenger fill:#9b2c2c,color:#fff,stroke:#742a2a
    style PO fill:#2b6cb0,color:#fff,stroke:#2c5282
    style Scope fill:#2b6cb0,color:#fff,stroke:#2c5282
    style UX fill:#2b6cb0,color:#fff,stroke:#2c5282
    style UAT fill:#2b6cb0,color:#fff,stroke:#2c5282
    style Registry fill:#276749,color:#fff,stroke:#22543d
```

---

## 2. SE 7-Step Protocol

```mermaid
flowchart LR
    subgraph SE Protocol
        direction LR
        S1[1. Context] --> S2[2. Plan]
        S2 --> S3[3. Implement]
        S3 --> S4[4. Changelog]
        S4 --> S5[5. Verify]
        S5 --> S6[6. Commit]
        S6 --> S7[7. Report]
    end

    WO([Work Order]) --> S1
    S7 --> Result([Result File])

    style S1 fill:#553c9a,color:#fff
    style S2 fill:#553c9a,color:#fff
    style S3 fill:#553c9a,color:#fff
    style S4 fill:#553c9a,color:#fff
    style S5 fill:#553c9a,color:#fff
    style S6 fill:#553c9a,color:#fff
    style S7 fill:#553c9a,color:#fff
    style WO fill:#4a5568,color:#fff
    style Result fill:#276749,color:#fff
```

**Step details:**
1. **Context** — Read CLAUDE.md, MEMORY.md, PLAN.md, AUDIT.md. Grep callers.
2. **Plan** — Design approach. Document trade-offs. Identify bash 4.1 risks.
3. **Implement** — Edit files. Respond to challenge findings.
4. **Changelog** — Update CHANGELOG + CHANGELOG.RELEASE with tagged lines.
5. **Verify** — `bash -n`, shellcheck, anti-pattern greps, run tests, bash 4.1 evidence.
6. **Commit** — Stage by name. Message format per project. No AI attribution.
7. **Report** — Write result file with status, commit hash, verification results.

---

## 3. Sentinel Review (Standard + Library Integration)

```mermaid
flowchart TD
    Input([SE Result + Full Diff]) --> Mode{Mode?}

    Mode -->|Standard 4-pass| Gather[Gather Context]
    Mode -->|LIBRARY_INTEGRATION| GatherLib[Gather Context\nfocus: source/init/API]

    Gather --> P1 & P2 & P3 & P4

    P1[Pass 1\nAnti-Slop]
    P2[Pass 2\nRegression]
    P3[Pass 3\nSecurity]
    P4[Pass 4\nPerformance]

    P1 & P2 & P3 & P4 --> Output([sentinel-N.md\nmax 20 findings])

    GatherLib --> LP2[Pass 2\nRegression\nsource guard, init, API mapping]
    GatherLib --> LP3[Pass 3\nSecurity\ncredentials, permissions]

    LP2 & LP3 --> LibOutput([sentinel-lib-N.md])

    Output --> QA([QA reads at Step 5.5])
    LibOutput --> QA

    style P1 fill:#9b2c2c,color:#fff
    style P2 fill:#9b2c2c,color:#fff
    style P3 fill:#9b2c2c,color:#fff
    style P4 fill:#9b2c2c,color:#fff
    style LP2 fill:#9b2c2c,color:#fff
    style LP3 fill:#9b2c2c,color:#fff
    style Input fill:#4a5568,color:#fff
    style Output fill:#975a16,color:#fff
    style LibOutput fill:#975a16,color:#fff
    style QA fill:#975a16,color:#fff
    style Gather fill:#4a5568,color:#fff
    style GatherLib fill:#4a5568,color:#fff
    style Mode fill:#2b6cb0,color:#fff
```

| Pass | Lens | Default Severity | Library Integration |
|------|------|-----------------|---------------------|
| Anti-Slop | Naming lies, copy-paste, premature abstraction | SHOULD-FIX | Skipped |
| Regression | Behavioral continuity, caller contracts, exit codes | MUST-FIX | Included |
| Security | Injection, credentials, temp files, eval | MUST-FIX | Included |
| Performance | O(N²), process spawning, redundant I/O | SHOULD-FIX | Skipped |

---

## 4. Audit Pipeline (3-Round)

```mermaid
flowchart TD
    Trigger([/audit or /audit-quick]) --> R1

    subgraph R1[Round 1 — Domain Agents — parallel]
        direction LR
        opus[opus\nregression · latent\nsecurity · modernize]
        sonnet[sonnet\ncli · docs · config\ntest-cov · test-exec\ninstall · build-ci\nupgrade · interfaces]
        haiku[haiku\nstandards · version]
    end

    R1 --> R2

    subgraph R2[Round 2 — Condense + Dedup — parallel]
        direction LR
        GA[Group A\nagents 1-8\n→ findings-a.md]
        GB[Group B\nagents 9-15\n→ findings-b.md]
    end

    R2 --> R3

    subgraph R3[Round 3 — Compile — sequential]
        Compile[Cross-group dedup\n300-line cap\nP1 expanded · P2 table · P3 grouped]
    end

    R3 --> Output([AUDIT.md])

    style Trigger fill:#4a5568,color:#fff
    style Output fill:#276749,color:#fff
    style opus fill:#553c9a,color:#fff
    style sonnet fill:#2b6cb0,color:#fff
    style haiku fill:#718096,color:#fff
    style GA fill:#2b6cb0,color:#fff
    style GB fill:#2b6cb0,color:#fff
    style Compile fill:#2b6cb0,color:#fff
```

---

## 5. Verification Gate (Tiered)

```mermaid
flowchart TD
    SE([SE Result]) --> Classify{EM classifies tier}

    Classify -->|Tier 0-1| Lite[QA-Lite\n3-step review]
    Classify -->|Tier 2+| Full[Full Gate]

    subgraph Full Gate
        direction LR
        QAFull[QA — Full 6-step]
        UATFull[UAT — Docker scenarios]
    end

    Lite --> LiteDecision{QA verdict}
    Full --> FullDecision{QA + UAT verdict}

    LiteDecision -->|APPROVED| MergeLite([Merge])
    LiteDecision -->|CHANGES_REQUESTED| FixLite([SE fix ×3 max])
    LiteDecision -->|ESCALATION| Full

    FullDecision -->|Both APPROVED| MergeFull([Merge])
    FullDecision -->|QA CHANGES_REQUESTED| FixFull([SE fix ×3 max])
    FullDecision -->|QA REJECTED| Blocked([Blocked])

    style SE fill:#553c9a,color:#fff
    style Classify fill:#2b6cb0,color:#fff
    style Lite fill:#975a16,color:#fff
    style QAFull fill:#975a16,color:#fff
    style UATFull fill:#2b6cb0,color:#fff
    style MergeLite fill:#276749,color:#fff
    style MergeFull fill:#276749,color:#fff
    style FixLite fill:#9b2c2c,color:#fff
    style FixFull fill:#9b2c2c,color:#fff
    style Blocked fill:#9b2c2c,color:#fff
```

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
        Sig[Sigforge 1.0.0\nSignature Engine]
        OW[Overwatch 1.5\nDashboard]
    end

    subgraph Libraries["Shared Libraries"]
        tlog[tlog_lib v2.0.3]
        alert[alert_lib v1.0.4]
        elog[elog_lib v1.0.2]
        pkg[pkg_lib v1.0.2]
        bats[batsman v1.2.0]
    end

    tlog --> APF & BFD & LMD
    alert --> BFD & LMD
    elog --> BFD & LMD
    bats --> APF & BFD & LMD & Sig & OW

    style APF fill:#2b6cb0,color:#fff
    style BFD fill:#2b6cb0,color:#fff
    style LMD fill:#2b6cb0,color:#fff
    style Sig fill:#553c9a,color:#fff
    style OW fill:#553c9a,color:#fff
    style tlog fill:#276749,color:#fff
    style alert fill:#276749,color:#fff
    style elog fill:#276749,color:#fff
    style pkg fill:#276749,color:#fff
    style bats fill:#276749,color:#fff
```

---

## 8. File-Based Handoff

```mermaid
sequenceDiagram
    participant EM
    participant Scope
    participant Challenger
    participant SE
    participant Sentinel
    participant QA
    participant UAT

    EM->>Scope: workorder mode (phase N)
    activate Scope
    Scope->>EM: scope-workorder-P<N>.md
    deactivate Scope

    opt Tier 2+ Challenger Gate
        EM->>SE: plan-only mode
        activate SE
        SE->>EM: implementation-plan.md (PLAN_COMPLETE)
        deactivate SE
        EM->>Challenger: review plan
        activate Challenger
        Challenger->>EM: challenge-N.md
        deactivate Challenger
    end

    EM->>SE: current-phase.md (work order)
    activate SE
    SE-->>SE: phase-N-status.md (progress)
    SE-->>SE: test-registry-P<N>.md (after tests)
    SE->>EM: phase-N-result.md
    deactivate SE

    par Parallel verification
        EM->>QA: dispatch review
        activate QA
        Note over QA: reads test-registry-P<N>.md
        EM->>Sentinel: dispatch review
        activate Sentinel
        Sentinel->>QA: sentinel-N.md (findings)
        deactivate Sentinel
    end

    QA->>EM: qa-phase-N-verdict.md
    deactivate QA

    opt Tier 2+
        EM->>UAT: dispatch acceptance
        activate UAT
        UAT->>EM: uat-phase-N-verdict.md
        deactivate UAT
    end

    EM-->>EM: merge decision
    EM-->>EM: append pipeline-metrics.jsonl
```
