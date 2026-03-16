# RDF - rfxn Development Framework

Convention governance, agent pipelines, and project orchestration for the
rfxn ecosystem. Tool-agnostic by design, currently delivered via Claude Code.

**Version:** 2.1.0 | **License:** GNU GPL v2 | **Author:** Ryan MacDonald <ryan@rfxn.com>

> **This is not a drop-in framework.** RDF is purpose-built for the rfxn
> ecosystem and shared as a reference for what disciplined AI-assisted
> development can look like. The value here is the pattern, not the files.
> Engineering organizations looking to get consistent, reliable output from
> AI coding assistants should study the approach: typed agent pipelines,
> adversarial quality gates, convention inheritance, and context window
> management. The goal is autonomous execution that does not require
> babysitting the model on every commit.

---

## Table of Contents

- [Why This Exists](#why-this-exists)
- [Production Scale](#production-scale)
- [Architecture](#architecture)
- [Pipeline](#pipeline)
- [Installation](#installation)
- [CLI Reference](#cli-reference)
- [Profiles](#profiles)
- [Inventory](#inventory)
- [Project Ecosystem](#project-ecosystem)
- [How To: Add a Command](#how-to-add-a-command)
- [How To: Add an Agent](#how-to-add-an-agent)
- [How To: Add a Profile](#how-to-add-a-profile)
- [How To: Add an Adapter](#how-to-add-an-adapter)
- [How To: Onboard a Project](#how-to-onboard-a-project)
- [Contributing](#contributing)
- [Detailed References](#detailed-references)

---

## Why This Exists

This framework emerged from 6 months of daily AI-assisted development
across the full rfxn product ecosystem.

AI coding assistants are powerful, but they have no memory between sessions,
no concept of project conventions, and no quality gates. Left unsupervised,
they introduce subtle regressions, ignore platform constraints, and produce
code that passes lint but fails in production.

Over 6 months across 10 production projects, we learned this the hard way.
Bugs that linters cannot catch -- silent behavior changes in refactored
functions, empty variable propagation, compatibility violations across
target platforms, regressions introduced by code that looks correct in
isolation but breaks integration contracts -- kept recurring. Each incident
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

## Architecture

### Core Design

RDF is built on five principles:

1. **Canonical-first, adapter-delivered.** All convention content, agent
   prompts, and governance docs live as tool-agnostic markdown in
   `canonical/`. Tool-specific adapters generate deployment artifacts
   from canonical sources. Development happens in `canonical/` -- deployed
   copies are generated output, not editable originals.

2. **Profile system for discipline selection.** Core framework primitives
   are always active. Domain profiles (systems-engineering, security,
   frontend, future disciplines) bundle relevant agents, commands,
   conventions, and reference docs. Multiple profiles can be active
   simultaneously with dependency resolution.

3. **Unified CLI.** Single `rdf` dispatcher with lazy-sourced subcommand
   modules. Eight subcommands cover the full lifecycle: generate, profile,
   init, doctor, state, refresh, sync, github.

4. **GitHub-native project management.** GitHub Issues + Projects v2 is
   the durable work tracking layer with phase-level tracking: one issue
   per phase (not per task), initiative issues for roadmap planning, and
   release issues for version tracking. A two-horizon roadmap provides
   both planning visibility (Target Date) and execution status (Release
   iteration). PLAN.md and MEMORY.md remain as session-local agent
   context but GitHub Issues is the source of truth for queue state.

5. **Not a runtime.** Claude Code / Gemini CLI / Codex IS the runtime.
   RDF is the governance layer that tells the runtime how to behave.

### Data Flow

```
canonical/          Adapter            Tool Deployment
  agents/*.md  -->  adapter.sh  -->  output/agents/*.md  -->  ~/.claude/agents/
  commands/*.md     (frontmatter      output/commands/*.md    ~/.claude/commands/
  scripts/*.sh       injection)       output/scripts/*.sh     ~/.claude/scripts/
                                                            (symlinks)
```

**Normal flow:** Edit in `canonical/` -> `rdf generate claude-code` ->
symlinks auto-update since they point to `output/`.

**Emergency flow:** Edit in `~/.claude/` directly -> `rdf sync` pulls
changes back to canonical (strips tool-specific frontmatter).

**Drift detection:** `rdf doctor --scope sync` compares canonical and
generated output, reports any divergence.

### Directory Structure

```
rdf/
|-- bin/rdf                          # CLI dispatcher (~55 lines)
|
|-- lib/
|   |-- rdf_common.sh                # Shared init, version, paths, helpers
|   +-- cmd/                         # Subcommand handlers (sourced)
|       |-- generate.sh              # rdf generate
|       |-- profile.sh               # rdf profile
|       |-- init.sh                  # rdf init
|       |-- doctor.sh                # rdf doctor
|       |-- state.sh                 # rdf state
|       |-- refresh.sh               # rdf refresh
|       |-- sync.sh                  # rdf sync
|       +-- github.sh                # rdf github
|
|-- canonical/                       # Tool-agnostic source of truth
|   |-- agents/                      # Pure markdown, no frontmatter
|   |-- commands/                    # Pure markdown (~66 commands)
|   |-- scripts/                     # Hook scripts (bash)
|   +-- reference/                   # Framework-level docs
|
|-- profiles/
|   |-- registry.json                # Profile catalog + dep graph
|   |-- core/                        # Core profile
|   |-- systems-engineering/         # Bash/shell projects
|   |-- security/                    # Security assessment
|   +-- frontend/                    # Web/frontend
|
|-- adapters/
|   |-- claude-code/                 # CC adapter + metadata + output/
|   |-- gemini-cli/                  # Gemini CLI adapter
|   |-- codex/                       # Codex adapter
|   +-- agents-md/                   # AGENTS.md adapter
|
|-- state/
|   +-- rdf-state.sh                 # Project state -> JSON (<1s)
|
|-- docs/specs/                      # Architecture specs
+-- docs/plans/                      # Implementation plans
```

### Naming Convention

**Pattern:** `{domain}-{role}` for domain-specific, `{role}` for core.

| Tier | Prefix | Examples | Rationale |
|------|--------|---------|-----------|
| Core | none | mgr, po, scope | Orchestrate across any domain |
| Domain | {domain}- | sys-eng, sys-qa, sys-sentinel | Domain expertise in agent prompt |
| Specialist | {domain}- | sec-eng, fe-qa, fe-uat | Cross-cutting or domain-scoped |

**Domain registry:**

| Shortcode | Profile | Domain |
|-----------|---------|--------|
| sys | systems-engineering | Bash/shell, Linux, security tooling |
| sec | security | Offensive/defensive security assessment |
| fe | frontend | Vue/React, CSS, Playwright |
| php | php-backend | PHP, MySQL (future) |
| py | python-backend | Python/Perl (future) |
| iaas | infrastructure | IaaS, API, cloud (future) |
| fs | full-stack | Cross-stack coordination (future) |

**CC agent names:** `rfxn-{file-stem}` (e.g., `rfxn-sys-eng`, `rfxn-mgr`)
**Slash commands:** `/{file-stem}` (e.g., `/sys-eng`, `/mgr`)

---

## Pipeline

AI models have a fixed context window. Fill it with everything and the
model knows a little about a lot -- it writes plausible code that misses
project-specific constraints. RDF solves this by splitting work across
typed agent personas, each loaded with a small, highly specific context
window scoped to exactly one job.

A QA agent does not see implementation details -- it sees the diff, the
test results, and the verification protocol. A Sentinel agent does not
see the requirements discussion -- it sees the code and runs four
adversarial passes. Each agent is a context buffer: a narrow, deep
window into exactly the information that role needs to do its job well.

### Engineering Pipeline

```
USER -> [PO] -> mgr -> [scope -> sys-eng plan-only -> sys-challenger]
     -> sys-eng -> [sys-sentinel || sys-qa] -> [sys-ux] -> sys-uat
     -> MERGE
```

| Role | Model | Purpose |
|------|-------|---------|
| Engineering Manager - mgr | sonnet | Orchestrator - prioritize, delegate, quality gates |
| Product Owner - po | sonnet | Requirements translation, scope gating (optional) |
| Scoping & Work Orders - scope | sonnet | Work order assembly, impact analysis |
| Pre-Impl Adversary - sys-challenger | sonnet | Design flaws, edge cases, simpler alternatives |
| Senior Engineer - sys-eng | opus | 7-step execution protocol, implementation |
| QA Engineer - sys-qa | sonnet | Verification gate - 6-step review, bash 4.1 compliance |
| Post-Impl Adversary - sys-sentinel | opus | 4-pass review: anti-slop, regression, security, performance |
| UX & Output Design - sys-ux | sonnet | CLI output, help text, error messages (trigger-based) |
| User Acceptance Testing - sys-uat | sonnet | Sysadmin persona - Docker install, real-world scenarios |
| Security Engineer - sec-eng | opus | Offensive/defensive security assessment |
| Frontend QA - fe-qa | sonnet | API contracts, DOM, CSS, JS patterns |
| Frontend UAT - fe-uat | sonnet | Playwright headless scenarios |

### Audit Pipeline (3-Round)

```
/audit or /audit-quick
  -> Round 1: 15 domain agents in parallel (opus/sonnet/haiku by domain)
  -> Round 2: Condense + dedup in parallel (2 groups)
  -> Round 3: Compile (sequential, 300-line cap)
  -> AUDIT.md
```

15 domain agents: regression, latent, standards, cli, docs, config,
test-coverage, test-exec, install, build-ci, upgrade, version, security,
interfaces, modernize. Quick mode runs 6 static-analysis agents.

> See [WORKFORCE.md](WORKFORCE.md) for full pipeline diagrams, protocol
> details, and verification gate decision matrix.

---

## Installation

### Fresh Install

```bash
# Clone
git clone https://github.com/rfxn/rdf.git
cd rdf || exit 1

# Generate Claude Code deployment
bin/rdf generate claude-code

# Deploy (symlinks)
ln -sf "$(pwd)/adapters/claude-code/output/commands" /root/.claude/commands
ln -sf "$(pwd)/adapters/claude-code/output/agents" /root/.claude/agents
ln -sf "$(pwd)/adapters/claude-code/output/scripts" /root/.claude/scripts
```

### Upgrade from Pre-2.0

```bash
# Remove old direct-file deployment
rm -rf /root/.claude/commands /root/.claude/agents /root/.claude/scripts

# Generate and symlink
cd /root/admin/work/proj/rdf || exit 1
bin/rdf generate claude-code

ln -sf "$(pwd)/adapters/claude-code/output/commands" /root/.claude/commands
ln -sf "$(pwd)/adapters/claude-code/output/agents" /root/.claude/agents
ln -sf "$(pwd)/adapters/claude-code/output/scripts" /root/.claude/scripts
```

### Verify Installation

```bash
# Check symlinks resolve
ls -la /root/.claude/commands /root/.claude/agents /root/.claude/scripts

# Check counts
echo "Agents: $(ls /root/.claude/agents/*.md 2>/dev/null | wc -l)"      # 12
echo "Commands: $(ls /root/.claude/commands/*.md 2>/dev/null | wc -l)"   # ~66
echo "Scripts: $(ls /root/.claude/scripts/*.sh 2>/dev/null | wc -l)"     # 10

# Health check
bin/rdf doctor
```

---

## CLI Reference

Single `rdf` dispatcher with lazy-sourced subcommand modules.

```
Usage: rdf <command> [subcommand] [options]

RDF 2.1.0 -- rfxn Development Framework

Commands:
  generate   Build tool-specific files from canonical sources
  profile    Manage active domain profiles
  init       Initialize projects with RDF conventions
  doctor     Check project health and convention drift
  state      Deterministic project state snapshot (JSON)
  refresh    Agent-driven state file updates
  sync       Pull /root/.claude/ changes back to canonical
  github     GitHub Issues + Projects integration

Options:
  help       Show this help
  version    Show version

Run 'rdf <command> help' for subcommand details.
```

### rdf generate

Build tool-specific output from canonical sources and active profiles.

```bash
rdf generate claude-code     # canonical + profiles -> CC output
rdf generate gemini-cli      # canonical + profiles -> Gemini config
rdf generate codex           # canonical + profiles -> Codex config
rdf generate agents-md       # canonical + profiles -> AGENTS.md
rdf generate all             # all active adapters
```

Reads `canonical/{agents,commands,scripts}`, applies adapter-specific
metadata (frontmatter, tool config), writes to `adapters/<target>/output/`.
Idempotent -- safe to run repeatedly.

### rdf profile

Manage active domain profiles with dependency resolution.

```bash
rdf profile list             # show profiles with dependencies
rdf profile install <name>   # activate + resolve deps + regenerate
rdf profile remove <name>    # deactivate, warn if dependents active
rdf profile status           # active profiles + component counts
```

Profiles control which agents, commands, governance docs, and reference
material are included in generation output. Installing a profile
automatically installs its dependencies (e.g., `systems-engineering`
pulls in `core`).

### rdf init

Initialize a project with RDF conventions, templates, and optional
GitHub scaffolding.

```bash
rdf init <path> [options]
  --type shell|lib|frontend|security|minimal
  --tools claude-code,gemini-cli,codex
  --version X.Y.Z
  --no-memory
  --github              # create labels + repo project board
  --batch               # process multiple directories
```

Creates CLAUDE.md (from profile template), MEMORY.md, configures
`.git/info/exclude`, and optionally bootstraps GitHub Issues
infrastructure.

### rdf doctor

Check project health: artifact presence, convention drift, memory
freshness, plan consistency, GitHub sync, and canonical/output drift.

```bash
rdf doctor [<path>] [options]
  --all                 # all workspace projects
  --scope artifacts|drift|memory|plan|github|sync
```

Six check categories:
- **artifacts** -- CLAUDE.md, MEMORY.md, PLAN.md, CHANGELOG existence
- **drift** -- convention violations, stale patterns
- **memory** -- freshness, line count, consistency
- **plan** -- phase status accuracy, stale refs
- **github** -- issue state sync, label taxonomy
- **sync** -- canonical vs generated output divergence

### rdf state

Deterministic project state snapshot as JSON to stdout. No LLM calls,
completes in under 1 second.

```bash
rdf state [<path>]
```

Returns: project name, version, git branch, dirty state, uncommitted
file count, last commit hash/age, MEMORY/PLAN/AUDIT existence, plan
phase counts, and work output file inventory.

### rdf refresh

Agent-driven state file updates -- MEMORY.md, PLAN.md, and GitHub
issue state.

```bash
rdf refresh [<path>] [options]
  --scope memory|plan|github|all
```

### rdf sync

Pull changes from `/root/.claude/` back to canonical sources. Used as an
emergency escape hatch when files are edited directly in the deployment
target. Strips tool-specific frontmatter during import.

```bash
rdf sync [options]
  --dry-run             # show what would change without writing
```

### rdf github

GitHub Issues + Projects v2 integration with phase-level tracking and
two-horizon roadmap planning.

**Issue hierarchy (v2 model):**

```
Initiative (type:initiative)  -- planning horizon, directional timing
  +-- Release (type:release)  -- committed version, specific timeline
       +-- Phase (type:phase) -- execution unit, tracked on boards
            +-- Tasks (comments) -- progress trail, async visibility
```

Phases are the unit of work on GitHub -- one issue per phase, not per
task. Task progress is tracked via comments on the phase issue.
Initiatives provide roadmap planning; releases track versioned
deliverables.

**Two-horizon roadmap** on the ecosystem project:
- **Planning Roadmap** -- initiatives and releases on a Target Date timeline
- **Execution Roadmap** -- phase issues in active releases by iteration

```bash
rdf github setup [--repo <owner/repo>]       # labels + repo project
rdf github sync-labels [--org <org>]         # sync taxonomy across repos
rdf github ecosystem-init [--org <org>]      # org-level project + fields
rdf github ecosystem-add <owner/repo>        # add repo to ecosystem project
```

See [docs/specs/2026-03-16-github-issue-model-v2-design.md](docs/specs/2026-03-16-github-issue-model-v2-design.md)
for the full specification.

---

## Profiles

Profiles bundle agents, commands, governance, and reference docs for a
domain discipline. Multiple profiles can be active simultaneously.

| Profile | Requires | Agents | Description |
|---------|----------|--------|-------------|
| core | -- | mgr, po, scope | Framework primitives -- always active |
| systems-engineering | core | sys-eng, sys-qa, sys-uat, sys-sentinel, sys-challenger, sys-ux | Bash/shell projects |
| security | core | sec-eng | Security assessment |
| frontend | core | fe-qa, fe-uat | Web/frontend (generic, framework-agnostic) |

Each profile contains:
- `profile.json` -- component list (agents, commands, scripts, reference docs)
- `governance.md` -- domain-specific conventions and standards
- `templates/` -- CLAUDE.md templates for `rdf init`
- `reference/` -- domain-specific reference documentation (optional)

---

## Inventory

### Agents (12)

**Core (3):**

| File | CC Name | Model | Role |
|------|---------|-------|------|
| mgr.md | rfxn-mgr | sonnet | Engineering Manager - orchestrate, delegate, quality gates |
| po.md | rfxn-po | sonnet | Product Owner - intake, requirements, scope gating |
| scope.md | rfxn-scope | sonnet | Scoping & research - impact analysis, work order assembly |

**Systems Engineering (6):**

| File | CC Name | Model | Role |
|------|---------|-------|------|
| sys-eng.md | rfxn-sys-eng | opus | Senior Engineer - 7-step execution protocol |
| sys-qa.md | rfxn-sys-qa | sonnet | QA Engineer - 6-step verification gate |
| sys-uat.md | rfxn-sys-uat | sonnet | UAT - sysadmin persona, Docker scenarios |
| sys-sentinel.md | rfxn-sys-sentinel | opus | Post-impl adversary - 4-pass review |
| sys-challenger.md | rfxn-sys-challenger | sonnet | Pre-impl adversary - design flaws, edge cases |
| sys-ux.md | rfxn-sys-ux | sonnet | UX/output design - CLI, help text, man pages |

**Security (1):**

| File | CC Name | Model | Role |
|------|---------|-------|------|
| sec-eng.md | rfxn-sec-eng | opus | Security engineer - offensive/defensive assessment |

**Frontend (2):**

| File | CC Name | Model | Role |
|------|---------|-------|------|
| fe-qa.md | rfxn-fe-qa | sonnet | Frontend QA - API contracts, DOM, CSS, JS |
| fe-uat.md | rfxn-fe-uat | sonnet | Frontend UAT - Playwright headless scenarios |

### Commands (~66)

**Personas (12):** `mgr`, `sys-eng`, `sys-qa`, `sys-uat`, `po`, `scope`,
`sys-sentinel`, `sys-challenger`, `sys-ux`, `sec-eng`, `fe-qa`, `fe-uat`

**Audit pipeline (24):** `audit`, `audit-quick`, `audit-delta`,
`audit-compile`, `audit-condense`, `audit-context`, `audit-plan`,
`audit-feedback`, `audit-schema`, `audit-regression`, `audit-latent`,
`audit-security`, `audit-standards`, `audit-version`, `audit-cli`,
`audit-docs`, `audit-config`, `audit-test-coverage`, `audit-test-exec`,
`audit-install`, `audit-build-ci`, `audit-upgrade`, `audit-interfaces`,
`audit-modernize`
*(+ 2 deprecated stubs: `audit-dedup`, `audit-synthesis`)*

**Release (7):** `rel-prep`, `rel-ship`, `rel-merge`, `rel-notes`,
`rel-chg-dedup`, `rel-chg-diff`, `rel-scrub`

**Project (6):** `proj-status`, `proj-health`, `proj-cross`,
`proj-cross-audit`, `proj-lib-sync`, `proj-scaffold`

**Code quality (5):** `code-validate`, `code-grep`, `test-strategy`,
`test-impact`, `test-dedup`

**Memory (3):** `mem-save`, `mem-audit`, `mem-compact`

**Other (8):** `modernize`, `onboard`, `reload`, `refresh`, `status`,
`ci-setup`, `lib-release`, `doc-author`

### Scripts (10)

| Script | Profile | Purpose |
|--------|---------|---------|
| context-bar.sh | core | Status line - project, branch, phase, model |
| clone-conversation.sh | core | Fork current conversation to new session |
| half-clone-conversation.sh | core | Fork recent half of conversation |
| check-context.sh | core | Context window utilization check |
| setup.sh | core | First-run environment setup |
| color-preview.sh | core | Terminal color palette preview |
| test-half-clone.sh | core | Test harness for half-clone |
| subagent-stop.sh | core | Capture agent completion events |
| pre-commit-validate.sh | systems-engineering | Pre-commit lint + anti-pattern greps |
| post-edit-lint.sh | systems-engineering | Post-edit shellcheck on modified files |

---

## Project Ecosystem

```
PRODUCTS                         SHARED LIBRARIES
+---------------+                +--------------+
| APF  2.0.2    |----------------| tlog_lib     | v2.0.3
| BFD  2.0.1    |----------------| alert_lib    | v1.0.4
| LMD  2.0.1    |----------------| elog_lib     | v1.0.3
+---------------+                | pkg_lib      | v1.0.4
+---------------+                | batsman      | v1.2.0
| Sigforge      | 1.1.3         +--------------+
| geoip_lib     | v1.0.2
+---------------+
```

All projects share: batsman test infrastructure, parent CLAUDE.md
conventions, RDF governance pipeline, GitHub label taxonomy.

---

## How To: Add a Command

Commands are slash-invokable skills scoped to specific tasks.

1. **Create the canonical file.** Write `canonical/commands/<name>.md`
   with pure markdown content -- no tool-specific frontmatter, no YAML
   headers. The first line should be a descriptive title.

   ```markdown
   # /my-command -- What this command does

   ## When to Use
   ...

   ## Protocol
   ...
   ```

2. **Assign to a profile.** Add the command name to the `commands` array
   in the appropriate `profiles/<profile>/profile.json`.

3. **Regenerate.** Run `rdf generate claude-code` to produce the
   deployment output.

4. **Verify.** Confirm the command appears in
   `adapters/claude-code/output/commands/` and is accessible via
   the symlink at `/root/.claude/commands/`.

5. **Update inventory.** Add the command to `README.md` and
   `WORKFORCE.md` command tables.

**Rules:**
- Canonical files are tool-agnostic -- no `---` YAML frontmatter blocks
- Cross-references use canonical names (`/sys-eng`, not `/syseng`)
- Commands that dispatch agents reference the canonical agent filename

## How To: Add an Agent

Agents are typed personas with defined protocols and model assignments.

1. **Create the canonical file.** Write `canonical/agents/<name>.md`
   with pure markdown -- the agent's role, protocol, constraints, and
   output format.

2. **Add adapter metadata.** Add an entry to
   `adapters/claude-code/agent-meta.json` with the CC-specific
   frontmatter values:

   ```json
   "<name>": {
     "name": "rfxn-<name>",
     "description": "One-line description for CC agent picker",
     "tools": ["Bash", "Read", "Write", "Edit", "Glob", "Grep"],
     "model": "sonnet"
   }
   ```

   Use `disallowedTools` for read-only agents (QA, Sentinel, etc.).

3. **Assign to a profile.** Add to `profiles/<profile>/profile.json`.

4. **Create the dispatch command.** Write a corresponding
   `canonical/commands/<name>.md` that tells the runtime how to
   invoke and configure the agent.

5. **Regenerate and verify.** Run `rdf generate claude-code`, confirm
   the agent file in `output/agents/` has correct YAML frontmatter.

**Naming:** Follow `{domain}-{role}` convention. Core agents (mgr, po,
scope) have no domain prefix. Domain agents use the registered shortcode
(sys, sec, fe).

## How To: Add a Profile

Profiles bundle agents, commands, governance, and reference docs for a
new domain discipline.

1. **Register the profile.** Add an entry to `profiles/registry.json`
   with name, description, dependencies, and domain shortcode.

2. **Create the profile directory.**

   ```
   profiles/<name>/
   |-- profile.json           # Component lists
   |-- governance.md          # Domain-specific conventions
   +-- templates/
       +-- claude-<type>.md.tmpl   # CLAUDE.md template for rdf init
   ```

3. **Write profile.json.** List the agents, commands, scripts, and
   reference docs this profile includes:

   ```json
   {
     "name": "<name>",
     "requires": ["core"],
     "agents": ["<domain>-eng", "<domain>-qa"],
     "commands": ["<domain>-eng", "<domain>-qa"],
     "scripts": [],
     "reference": []
   }
   ```

4. **Write governance.md.** Document domain-specific conventions,
   standards, and constraints. This content is injected into project
   CLAUDE.md files by `rdf init`.

5. **Create templates.** Write `.tmpl` files with variable placeholders
   (`{{PROJECT_NAME}}`, `{{VERSION}}`, etc.) for `rdf init` to use.

6. **Update `rdf generate`** if the profile needs adapter-specific
   handling beyond the default copy/frontmatter-inject pattern.

7. **Regenerate and test.** `rdf profile install <name>`, then
   `rdf generate claude-code`, verify output includes the new
   profile's components.

**Rules:**
- All profiles must depend on `core` (directly or transitively)
- Governance content must not duplicate parent conventions -- extend only
- Profile governance follows `canonical/reference/memory-standards.md`

## How To: Add an Adapter

Adapters generate tool-specific output from canonical sources.

1. **Create the adapter directory.**

   ```
   adapters/<tool>/
   |-- adapter.sh             # Generation logic (sourced by rdf generate)
   +-- output/                # GENERATED -- never edit manually
   ```

2. **Write adapter.sh.** Implement the generation functions. The adapter
   must implement a `<prefix>_generate_all` function that reads from
   `canonical/` and writes to `output/`. Study
   `adapters/claude-code/adapter.sh` as the reference implementation.

3. **Register in `rdf generate`.** Add a case branch in
   `lib/cmd/generate.sh` for the new adapter target.

4. **Document.** Add the adapter to `rdf generate help` output and
   the README CLI reference.

**Contract:** Adapters read from `${RDF_CANONICAL}` and adapter-specific
metadata. They write to their own `output/` directory. They never modify
canonical sources.

## How To: Onboard a Project

Onboard an existing or new project into the RDF ecosystem.

```bash
# Initialize with appropriate type
rdf init /path/to/project --type shell --tools claude-code --github

# Or for batch initialization of multiple projects
rdf init /root/admin/work/proj --batch
```

This creates:
- `CLAUDE.md` from the active profile template
- `MEMORY.md` (unless `--no-memory`)
- `.git/info/exclude` entries for working files
- GitHub labels and project board (with `--github`)

For manual onboarding:
1. Create a project-level `CLAUDE.md` following the template
2. Add `.git/info/exclude` entries: `CLAUDE.md`, `PLAN*.md`, `AUDIT.md`,
   `MEMORY.md`, `.claude/`
3. Run `rdf github setup --repo owner/repo` for GitHub infrastructure
4. Run `rdf doctor` to verify setup

---

## Contributing

### Principles

- **Canonical files are tool-agnostic.** No YAML frontmatter, no
  tool-specific syntax in `canonical/`. Adapter metadata is separate
  from content.

- **Adapter metadata is separate from content.** Tool-specific
  configuration (CC frontmatter, Gemini config) lives in adapter
  metadata files, not in canonical markdown.

- **Profile governance follows memory-standards.md.** Convention
  documents must follow the standards defined in
  `canonical/reference/memory-standards.md`.

- **RDF is authoritative.** Develop in `rdf/canonical/`, deploy via
  `rdf generate`. Never treat deployed files as the source of truth.

### Sync Protocol

```
rdf/canonical/  --[rdf generate]-->  rdf/adapters/*/output/
                                          |
                                     (symlinks)
                                          |
                                     ~/.claude/{commands,agents,scripts}
```

**Direction:** Develop in `rdf/canonical/` -> `rdf generate` -> deploy.

**Emergency:** Edit `~/.claude/` directly -> `rdf sync` -> back to canonical.

**Drift check:** `rdf doctor --scope sync` detects divergence.

### Commit Protocol

- Free-form descriptive messages (no version prefix)
- Tag body lines: `[New]` `[Change]` `[Fix]` `[Remove]`
- No `Co-Authored-By` or AI attribution
- Stage files explicitly by name -- never `git add -A` or `git add .`
- Never commit: PLAN*.md, AUDIT.md, MEMORY.md, .claude/

---

## Detailed References

| Document | Content |
|----------|---------|
| [RDF.md](RDF.md) | Architecture, scope, risk, directory structure |
| [WORKFORCE.md](WORKFORCE.md) | Org chart, pipeline diagrams, command cheat sheet, workflows |
| [reference/diagrams.md](reference/diagrams.md) | Mermaid diagrams: pipeline, architecture, ecosystem |
| [docs/specs/](docs/specs/) | Architecture design specs |
| [docs/plans/](docs/plans/) | Phase implementation plans |

**Total: 12 agents + ~66 commands + 10 scripts = ~88 primitives + pipeline optimization protocols**
