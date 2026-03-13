# RDF - rfxn Development Framework

Convention governance, agent pipelines, and project orchestration for the
rfxn ecosystem. Tool-agnostic by design, currently delivered via Claude Code.

**License:** GNU GPL v2 | **Author:** Ryan MacDonald <ryan@rfxn.com>

> **This is not a drop-in framework.** RDF is purpose-built for the rfxn
> ecosystem and shared as a reference for what disciplined AI-assisted
> development can look like. The value here is the pattern, not the files.
> Engineering organizations looking to get consistent, reliable output from
> AI coding assistants should study the approach: typed agent pipelines,
> adversarial quality gates, convention inheritance, and context window
> management. The goal is autonomous execution that does not require
> babysitting the model on every commit.

---

## Why This Exists

This framework emerged from 6 months of daily AI-assisted development
across the full rfxn product ecosystem.

AI coding assistants are powerful, but they have no memory between sessions,
no concept of project conventions, and no quality gates. Left unsupervised,
they introduce subtle regressions, ignore platform constraints, and produce
code that passes lint but fails in production.

Over 6 months across 10 production projects, we learned this the hard way.
Bugs that linters cannot catch — silent behavior changes in refactored
functions, empty variable propagation, compatibility violations across
target platforms, regressions introduced by code that looks correct in
isolation but breaks integration contracts — kept recurring. Each incident
added a rule. Each rule needed enforcement. Manual enforcement does not
scale across 10 projects and 6 shared libraries.

RDF is the result: a governance layer that sits between the human and the AI
runtime. It encodes what we learned into typed agent personas with defined
protocols, adversarial review gates, and convention inheritance that every
project gets automatically. The AI still writes the code. RDF makes sure
it writes it correctly.

| Metric | Value |
|--------|-------|
| Active servers | ~350,000 |
| Daily check-ins | Signatures, updates, telemetry |
| Total commits | 1,686 |
| Code (production) | 31,176 lines |
| Test code (BATS) | 70,965 lines |
| Test cases | 5,764 |
| Governance framework | 14,204 lines |
| Overwatch dashboard | 5,949 lines |
| Net code churn | +271K / -111K lines |

Every convention, anti-pattern rule, and quality gate in this framework
exists because a real bug, regression, or production incident taught us
it was necessary. When your code runs on 350,000 servers and a bad push
changes their security posture overnight, the margin for error is zero.

---

## Production Scale

The rfxn product line is production security infrastructure deployed
across approximately 350,000 active servers. Every day, those servers
pull signature updates, version checks, and telemetry. A bad push is
not a GitHub issue -- it is a security event across hundreds of thousands
of machines.

**What these tools protect:**

- **APF** (Advanced Policy Firewall) -- network-level access control,
  rate limiting, and connection-state enforcement
- **LMD** (Linux Malware Detect) -- filesystem malware scanning with
  daily signature updates, quarantine, and alerting
- **BFD** (Brute Force Detection) -- real-time authentication attack
  detection and automated blocking

**Where they run:**

The install base reaches well beyond web hosting. Cloudflare ASN
telemetry shows daily check-ins from government agencies (NIST, NOAA,
NIH), defense networks (NATO CCDCOE), universities (Stanford, Harvard,
National Taiwan University), and national research networks across
Europe (DFN, RENATER, JANET, SURFnet, RedIRIS, GARR).

Enterprise and telecom networks include AWS, Microsoft, Google, Deutsche
Telekom, Vodafone, and Telefonica. Hosting and infrastructure providers
span Liquid Web, DigitalOcean, Hetzner, OVHcloud, Vultr, Bluehost,
Contabo, and Leaseweb. Deployments run across cPanel, Plesk, and
DirectAdmin environments as well as bare-metal and cloud configurations.

**What goes wrong when code is wrong:**

A false positive in LMD signature matching quarantines legitimate files
on every server that pulls the update -- at scale, that is a mass outage
disguised as a security response. A regression in APF rule parsing can
lock administrators out of their own servers or silently degrade firewall
posture. A behavior change in BFD threshold logic either floods block
lists with false positives or stops detecting real attacks. These are
security tools. A regression does not break a feature -- it changes the
security posture of every server running the update.

This is why RDF exists. The governance overhead is proportional to the
blast radius.

---

## What This Is

AI models have a fixed context window. Fill it with everything and the
model knows a little about a lot — it writes plausible code that misses
project-specific constraints. RDF solves this by splitting work across
typed agent personas, each loaded with a small, highly specific context
window scoped to exactly one job.

A QA agent does not see implementation details — it sees the diff, the
test results, and the verification protocol. A Sentinel agent does not
see the requirements discussion — it sees the code and runs four
adversarial passes. Each agent is a context buffer: a narrow, deep
window into exactly the information that role needs to do its job well.

The 64 slash commands work the same way. Each command is a skill scoped
to a specific task — `/rel-prep` knows how to verify a release is ready,
`/audit-security` knows how to hunt for injection vectors, `/test-impact`
knows how to map a code change to the test files that cover it. The
agent does not need to figure out how to do the job. The command tells it
exactly what to check, in what order, and what output to produce.

Together, the agents and commands form a typed engineering pipeline:

- **Agent personas** — context-buffered roles with defined protocols,
  each seeing only what that role needs
- **Commands** (slash-invokable skills) — 64 task-specific procedures
  for audit, release, testing, and project management
- **Hook scripts** — pre-commit validation, context display, and event
  capture that run automatically
- **Convention governance** — inherited by every project via CLAUDE.md
  so standards are structural, not aspirational

RDF is not a runtime. Claude Code (or Gemini CLI) is the runtime. RDF
tells the runtime how to behave — and more importantly, what to focus on.

> **Detailed references:**
> [RDF.md](RDF.md) - Architecture, scope, risk, target structure
> [WORKFORCE.md](WORKFORCE.md) - Org chart, pipeline views, command cheat sheet, workflows
> [reference/diagrams.md](reference/diagrams.md) - Visual pipeline and architecture diagrams (Mermaid)

---

## Pipeline

```mermaid
flowchart TD
    User([User Request]) --> PO{{PO - Product Owner}}
    PO -->|scoped problem| EM[EM - Engineering Manager]
    EM -->|tier 2+: work order| Scope[Scope - Work Order Assembly]
    EM -->|tier 0-1| SE
    Scope -->|plan-only dispatch| SEPlan[SE - Plan Only]
    SEPlan -->|implementation-plan.md| Challenger{{Challenger - Adversary}}
    Challenger -->|findings| SE[SE - Senior Engineer]
    SE -->|result| QA[QA - Verification Gate]
    SE -->|tier 2+| Sentinel{{Sentinel - 4-Pass Review}}
    Sentinel -->|findings| QA
    QA -->|touches output| UX{{UX Reviewer}}
    UX --> UAT{{UAT - Acceptance}}
    QA -->|tier 0-1| Merge([Merge])
    UAT --> Merge

    style User fill:#4a5568,color:#fff,stroke:#2d3748
    style Merge fill:#276749,color:#fff,stroke:#22543d
    style SE fill:#553c9a,color:#fff,stroke:#44337a
    style SEPlan fill:#553c9a,color:#fff,stroke:#44337a
    style EM fill:#2b6cb0,color:#fff,stroke:#2c5282
    style QA fill:#975a16,color:#fff,stroke:#744210
    style Sentinel fill:#9b2c2c,color:#fff,stroke:#742a2a
    style Challenger fill:#9b2c2c,color:#fff,stroke:#742a2a
    style PO fill:#2b6cb0,color:#fff,stroke:#2c5282
    style Scope fill:#2b6cb0,color:#fff,stroke:#2c5282
    style UX fill:#2b6cb0,color:#fff,stroke:#2c5282
    style UAT fill:#2b6cb0,color:#fff,stroke:#2c5282
```

> See [reference/diagrams.md](reference/diagrams.md) for all 8 diagrams:
> SE protocol, Sentinel passes, audit pipeline, verification gate,
> RDF architecture, project ecosystem, and file-based handoff sequence.

| Role | Model | Purpose |
|------|-------|---------|
| Engineering Manager - EM | sonnet | Orchestrator - prioritize, delegate, quality gates |
| Product Owner - PO | sonnet | Requirements translation, scope gating (optional) |
| Scoping & Work Orders - Scope | sonnet | Work order assembly, impact analysis, complexity assessment |
| Pre-Impl Adversary - Challenger | sonnet | Design flaws, edge cases, simpler alternatives |
| Senior Engineer - SE | opus | 7-step execution protocol, implementation |
| QA Engineer - QA | sonnet | Verification gate - 6-step review, bash 4.1 compliance |
| Post-Impl Adversary - Sentinel | opus | 4-pass review: anti-slop, regression, security, performance |
| UX & Output Design - UX Reviewer | sonnet | CLI output, help text, error messages (trigger-based) |
| User Acceptance Testing - UAT | sonnet | Sysadmin persona - Docker install, real-world scenarios |
| Frontend QA Engineer - Frontend QA | sonnet | API contracts, DOM, CSS, JS patterns (Overwatch) |
| Frontend UAT Engineer - Frontend UAT | sonnet | Playwright headless scenarios (Overwatch) |

---

## Inventory

### Agents - `claude/agents/` (10)

| File | Name | Model | Role |
|------|------|-------|------|
| se.md | rfxn-se | opus | Senior Engineer - 7-step execution |
| qa.md | rfxn-qa | sonnet | QA gate - structural + behavioral review |
| uat.md | rfxn-uat | sonnet | User acceptance testing in Docker |
| challenger.md | rfxn-challenger | sonnet | Pre-impl adversary |
| sentinel.md | rfxn-sentinel | opus | Post-impl 4-pass review |
| scope.md | rfxn-scope | sonnet | Scoping and research |
| po.md | rfxn-po | sonnet | Product owner intake |
| ux-review.md | rfxn-ux-reviewer | sonnet | UX and output design review |
| frontend-qa.md | frontend-qa | sonnet | Overwatch frontend QA |
| frontend-uat.md | frontend-uat | sonnet | Overwatch frontend UAT |

### Commands - `claude/commands/` (65)

**Personas** (6): `em`, `se`, `qa`, `uat`, `po`, `scope`

**Audit pipeline** (24): `audit`, `audit-quick`, `audit-delta`,
`audit-compile`, `audit-condense`, `audit-context`, `audit-plan`,
`audit-feedback`, `audit-schema`, `audit-regression`, `audit-latent`,
`audit-security`, `audit-standards`, `audit-version`, `audit-cli`,
`audit-docs`, `audit-config`, `audit-test-coverage`, `audit-test-exec`,
`audit-install`, `audit-build-ci`, `audit-upgrade`, `audit-interfaces`,
`audit-modernize`
*(+ 2 deprecated: `audit-dedup`, `audit-synthesis`)*

**Release** (7): `rel-prep`, `rel-ship`, `rel-merge`, `rel-notes`,
`rel-chg-dedup`, `rel-chg-diff`, `rel-scrub`

**Project** (6): `proj-status`, `proj-health`, `proj-cross`,
`proj-cross-audit`, `proj-lib-sync`, `proj-scaffold`

**Code quality** (5): `code-validate`, `code-grep`, `test-strategy`,
`test-impact`, `test-dedup`

**Memory** (3): `mem-save`, `mem-audit`, `mem-compact`

**Adversarial** (3): `challenger`, `sentinel`, `ux-review`

**Frontend** (2): `frontend-qa`, `frontend-uat`

**Other** (7): `modernize`, `onboard`, `reload`, `status`,
`ci-setup`, `lib-release`, `doc-author`

### Scripts - `claude/scripts/` (11)

| Script | Purpose |
|--------|---------|
| pre-commit-validate.sh | Pre-commit lint + anti-pattern greps |
| post-edit-lint.sh | Post-edit shellcheck on modified files |
| subagent-stop.sh | Capture agent completion events |
| overwatch-hook.sh | Write spool JSONL for Overwatch collectors |
| context-bar.sh | Status line - project, branch, phase, model |
| clone-conversation.sh | Fork current conversation to new session |
| half-clone-conversation.sh | Fork recent half of conversation |
| check-context.sh | Context window utilization check |
| setup.sh | First-run environment setup |
| color-preview.sh | Terminal color palette preview |
| test-half-clone.sh | Test harness for half-clone |

---

## Project Ecosystem

```
PRODUCTS                         SHARED LIBRARIES
┌─────────────┐                  ┌─────────────┐
│ APF  2.0.2  │──────────────────│ tlog_lib    │ v2.0.3
│ BFD  2.0.1  │──────────────────│ alert_lib   │ v1.0.4
│ LMD  2.0.1  │──────────────────│ elog_lib    │ v1.0.3
└─────────────┘                  │ pkg_lib     │ v1.0.2
┌─────────────┐                  │ batsman     │ v1.2.0
│ Sigforge    │ 1.0.0            └─────────────┘
│ Overwatch   │ 1.5
│ GPUBench    │
└─────────────┘
```

---

## Installation

```bash
# Clone
git clone https://github.com/rfxn/rdf.git

# Install - symlinks claude/ contents into ~/.claude/
cd rdf && ./install.sh

# Or sync from ~/.claude back to repo
./sync.sh
```

---

## Sync Protocol

The `claude/` directory in this repo is the canonical source for all
agent definitions, commands, and scripts. The live environment at
`~/.claude/` is a deployment target.

**Direction:** Develop in `~/.claude/` → sync to repo → commit → push.

```bash
# After making changes in ~/.claude/
./sync.sh          # Copies ~/.claude/{agents,commands,scripts} → claude/
git add claude/
git commit -m "Sync primitives from ~/.claude"
git push
```

To deploy from repo to a fresh machine:
```bash
./install.sh       # Copies claude/ → ~/.claude/
```

