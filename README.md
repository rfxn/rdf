# RDF - rfxn Development Framework

Convention governance, agent pipelines, and project orchestration for the
rfxn ecosystem. Tool-agnostic by design, currently delivered via Claude Code.

**Version:** 3.0.0 | **License:** GNU GPL v2 | **Author:** Ryan MacDonald <ryan@rfxn.com>

> **This is not a drop-in framework.** RDF is purpose-built for the rfxn
> ecosystem and shared as a reference for what disciplined AI-assisted
> development can look like. The value here is the pattern, not the files.
> Engineering organizations looking to get consistent, reliable output from
> AI coding assistants should study the approach: governance-driven agents,
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

RDF 3.0 is built on five principles:

1. **Canonical-first, adapter-delivered.** All convention content, agent
   prompts, and governance docs live as tool-agnostic markdown in
   `canonical/`. Tool-specific adapters generate deployment artifacts
   from canonical sources. Development happens in `canonical/` -- deployed
   copies are generated output, not editable originals.

2. **Governance-driven agent behavior.** Six universal agents replace the
   prior domain-specific model. Agent behavior is shaped by governance
   files initialized per-project via `/r:init`, not by baking domain
   knowledge into agent prompts. Profiles provide governance seed
   templates, not agent/command bundles.

3. **Unified CLI.** Single `rdf` dispatcher with lazy-sourced subcommand
   modules. Eight subcommands cover the full lifecycle: generate, profile,
   init, doctor, state, refresh, sync, github.

4. **GitHub-native project management.** GitHub Issues + Projects v2 is
   the durable work tracking layer with phase-level tracking: one issue
   per phase (not per task), initiative issues for roadmap planning, and
   release issues for version tracking.

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
|   |-- agents/                      # 6 universal agents (pure markdown)
|   |-- commands/                    # 23 commands under /r: namespace
|   |-- scripts/                     # Hook scripts (bash)
|   +-- reference/                   # Framework-level docs
|
|-- profiles/
|   |-- registry.md                  # Profile catalog
|   |-- core/                        # Core profile
|   |-- shell/                       # Bash/shell projects
|   |-- python/                      # Python projects
|   |-- frontend/                    # Web/frontend
|   |-- database/                    # Database projects
|   +-- go/                          # Go projects
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

**v3 convention:** Universal agents use role-only names. No domain prefix.

| Agent | CC Name | Model | Role |
|-------|---------|-------|------|
| planner | rdf-planner | opus | Research, specs, implementation plans |
| dispatcher | rdf-dispatcher | sonnet | Plan execution orchestrator |
| engineer | rdf-engineer | opus | Universal implementation |
| qa | rdf-qa | sonnet | Verification gate |
| uat | rdf-uat | sonnet | User acceptance testing |
| reviewer | rdf-reviewer | opus | Adversarial review (challenge + sentinel) |

**CC agent names:** `rdf-{file-stem}` (e.g., `rdf-engineer`, `rdf-qa`)
**Slash commands:** `/r-{name}` or `/r:{name}` (e.g., `/r-start` or `/r:start`)

---

## Pipeline

AI models have a fixed context window. Fill it with everything and the
model knows a little about a lot -- it writes plausible code that misses
project-specific constraints. RDF solves this by splitting work across
typed agent personas, each loaded with a small, highly specific context
window scoped to exactly one job.

A QA agent does not see implementation details -- it sees the diff, the
test results, and the verification protocol. A Reviewer agent does not
see the requirements discussion -- it sees the code and runs adversarial
passes. Each agent is a context buffer: a narrow, deep window into
exactly the information that role needs to do its job well.

### Lifecycle Pipeline

```
USER -> /r:spec (design: discover -> brainstorm -> spec -> review)
     -> /r:plan (decompose: spec -> PLAN.md -> review)
     -> [/review --challenge (reviewer)]
     -> /build [N] (dispatcher -> engineer -> qa/reviewer/uat gates)
     -> /r:ship -> MERGE
```

| Role | Agent | Model | Purpose |
|------|-------|-------|---------|
| Spec Designer | rdf-planner | opus | Research, brainstorm, write design specs |
| Planner | rdf-planner | opus | Decompose specs into implementation plans |
| Dispatcher | rdf-dispatcher | sonnet | Plan execution, phase orchestration |
| Engineer | rdf-engineer | opus | Implementation via governance-driven protocol |
| QA | rdf-qa | sonnet | Verification gate -- lint, tests, anti-patterns |
| Reviewer | rdf-reviewer | opus | Adversarial review -- challenge + sentinel modes |
| UAT | rdf-uat | sonnet | User acceptance -- sysadmin persona, real scenarios |

### Audit Pipeline

```
/r:audit
  -> Parallel: reviewer (3x) + qa (1x)
  -> Consolidation
  -> AUDIT.md
```

> See [WORKFORCE.md](WORKFORCE.md) for full pipeline diagrams and
> verification gate details.

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

### Upgrade from 2.x

```bash
# Regenerate (v3 agents and commands replace v2 automatically)
cd /root/admin/work/proj/rdf || exit 1
bin/rdf generate claude-code

# Symlinks remain unchanged -- they point to output/ which is regenerated
```

### Verify Installation

```bash
# Check symlinks resolve
ls -la /root/.claude/commands /root/.claude/agents /root/.claude/scripts

# Check counts
echo "Agents: $(ls /root/.claude/agents/*.md 2>/dev/null | wc -l)"      # 6
echo "Commands: $(ls /root/.claude/commands/*.md 2>/dev/null | wc -l)"   # 23
echo "Scripts: $(ls /root/.claude/scripts/*.sh 2>/dev/null | wc -l)"     # 10

# Health check
bin/rdf doctor
```

---

## CLI Reference

Single `rdf` dispatcher with lazy-sourced subcommand modules.

```
Usage: rdf <command> [subcommand] [options]

RDF 3.0.0 -- rfxn Development Framework

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

Build tool-specific output from canonical sources.

```bash
rdf generate claude-code     # canonical -> CC output
rdf generate gemini-cli      # canonical -> Gemini config
rdf generate codex           # canonical -> Codex config
rdf generate agents-md       # canonical -> AGENTS.md
rdf generate all             # all active adapters
```

Reads `canonical/{agents,commands,scripts}`, applies adapter-specific
metadata (frontmatter, tool config), writes to `adapters/<target>/output/`.
Idempotent -- safe to run repeatedly. All agents and commands are
generated unconditionally (v3 universal model).

### rdf profile

Manage active domain profiles with dependency resolution.

```bash
rdf profile list             # show profiles with dependencies
rdf profile install <name>   # activate + resolve deps
rdf profile remove <name>    # deactivate, warn if dependents active
rdf profile status           # active profiles + governance template status
```

In v3, profiles control governance template selection for `/r:init`,
not agent/command availability. All 6 agents and 23 commands are always
generated regardless of active profiles.

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

Creates CLAUDE.md (from governance template), MEMORY.md, configures
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

Profiles provide governance seed templates for project initialization.
In v3, all agents and commands are universal -- profiles control which
governance template is used by `/r:init`, not which agents are available.

| Profile | Requires | Governance Template | Description |
|---------|----------|---------------------|-------------|
| core | -- | governance-template.md | Framework primitives -- always active |
| shell | core | governance-template.md | Bash/shell projects |
| python | core | governance-template.md | Python projects |
| frontend | core | governance-template.md | Web/frontend |
| database | core | governance-template.md | Database projects |
| go | core | governance-template.md | Go projects |

Each profile contains:
- `governance-template.md` -- domain-specific governance seed
- `reference/` -- domain-specific reference documentation (optional)
- `templates/` -- CLAUDE.md templates for `rdf init` (optional)

---

## Inventory

### Agents (6)

| File | CC Name | Model | Role |
|------|---------|-------|------|
| planner.md | rdf-planner | opus | Research, brainstorming, specs, plans |
| dispatcher.md | rdf-dispatcher | sonnet | Plan execution orchestrator |
| engineer.md | rdf-engineer | opus | Universal implementation engineer |
| qa.md | rdf-qa | sonnet | Verification gate |
| uat.md | rdf-uat | sonnet | User acceptance testing |
| reviewer.md | rdf-reviewer | opus | Adversarial review (challenge + sentinel) |

### Commands (28)

**Lifecycle (14):**

| Command | Slash | Purpose |
|---------|-------|---------|
| r-init | /r:init | Governance initialization |
| r-start | /r:start | Session initialization + warm handoff |
| r-save | /r:save | End-of-session state sync |
| r-spec | /r:spec | Design workflow (discover, brainstorm, spec, review) |
| r-plan | /r:plan | Planning workflow (spec -> PLAN.md -> review) |
| r-mode | /r:mode | Switch operational mode |
| r-status | /r:status | Project health dashboard |
| r-refresh | /r:refresh | Governance refresh |
| r-sync | /r:sync | Canonical source sync |
| r-audit | /r:audit | Full codebase audit |
| r-ship | /r:ship | Release workflow |
| build | /build | Execute plan phase (dispatches dispatcher) |
| verify | /verify | QA verification (dispatches qa) |
| test | /test | UAT acceptance (dispatches uat) |
| review | /review | Adversarial review (dispatches reviewer) |

**Utility (14):**

| Command | Slash | Purpose |
|---------|-------|---------|
| r-util-mem-compact | /r:util:mem-compact | Archive stale MEMORY.md entries |
| r-util-mem-audit | /r:util:mem-audit | Fact-check MEMORY.md against live state |
| r-util-chg-gen | /r:util:chg-gen | Generate changelog from diff |
| r-util-chg-dedup | /r:util:chg-dedup | Deduplicate changelog entries |
| r-util-rel-squash | /r:util:rel-squash | Release branch squash plan + execution |
| r-util-doc-gen | /r:util:doc-gen | Generate documentation |
| r-util-ci-gen | /r:util:ci-gen | Generate CI workflow |
| r-util-lib-sync | /r:util:lib-sync | Cross-project library drift detection |
| r-util-lib-release | /r:util:lib-release | Shared library release lifecycle |
| r-util-proj-cross | /r:util:proj-cross | Cross-project convention drift + overlap |
| r-util-code-scan | /r:util:code-scan | Pattern-class bug finder |
| r-util-code-modernize | /r:util:code-modernize | Codebase modernization assessment |
| r-util-test-dedup | /r:util:test-dedup | Find duplicate/overlapping tests |
| r-util-test-scope | /r:util:test-scope | Test tier + function-to-test impact |

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
| pre-commit-validate.sh | shell | Pre-commit lint + anti-pattern greps |
| post-edit-lint.sh | shell | Post-edit shellcheck on modified files |

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
   # /r:<name> -- What this command does

   ## When to Use
   ...

   ## Protocol
   ...
   ```

2. **Regenerate.** Run `rdf generate claude-code` to produce the
   deployment output. All commands are generated unconditionally.

3. **Verify.** Confirm the command appears in
   `adapters/claude-code/output/commands/` and is accessible via
   the symlink at `/root/.claude/commands/`.

4. **Update inventory.** Add the command to the README.md command table.

**Rules:**
- Canonical files are tool-agnostic -- no `---` YAML frontmatter blocks
- Commands use the `/r:` namespace (lifecycle) or `/r:util:` (utility)
- Commands that dispatch agents reference the universal agent name

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
     "name": "rdf-<name>",
     "description": "One-line description for CC agent picker",
     "tools": ["Bash", "Read", "Write", "Edit", "Glob", "Grep"],
     "model": "sonnet"
   }
   ```

   Use `disallowedTools` for read-only agents (QA, Reviewer, etc.).

3. **Regenerate and verify.** Run `rdf generate claude-code`, confirm
   the agent file in `output/agents/` has correct YAML frontmatter.

**Naming:** Universal agents use role-only names with `rdf-` prefix.

## How To: Add a Profile

Profiles provide governance seed templates for project initialization.

1. **Register the profile.** Add an entry to `profiles/registry.md`
   with name, description, and dependencies.

2. **Create the profile directory.**

   ```
   profiles/<name>/
   |-- governance-template.md   # Governance seed for /r:init
   +-- reference/               # Domain-specific docs (optional)
   ```

3. **Write governance-template.md.** Document domain-specific
   conventions, standards, and constraints. This content seeds the
   governance files created by `/r:init`.

4. **Regenerate and test.** `rdf profile install <name>`, then
   `rdf generate claude-code`, verify governance output.

**Rules:**
- All profiles must depend on `core` (directly or transitively)
- Governance content must not duplicate parent conventions -- extend only

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
- `CLAUDE.md` from the active governance template
- `MEMORY.md` (unless `--no-memory`)
- `.git/info/exclude` entries for working files
- GitHub labels and project board (with `--github`)

For manual onboarding:
1. Create a project-level `CLAUDE.md` following the governance template
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
| [WORKFORCE.md](WORKFORCE.md) | Agent workforce, pipeline diagrams, workflows |
| [reference/diagrams.md](reference/diagrams.md) | Mermaid diagrams: pipeline, architecture, ecosystem |
| [docs/specs/](docs/specs/) | Architecture design specs |
| [docs/plans/](docs/plans/) | Implementation plans |

**Total: 6 agents + 23 commands + 10 scripts = 39 primitives**
