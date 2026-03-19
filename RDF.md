# RDF -- rfxn Development Framework

## Overview

Canonical-first convention governance with governance-driven universal agents,
unified CLI, GitHub-native project management (phase-level tracking with
initiative/release/phase hierarchy and two-horizon roadmap), and tool-specific
adapter generation. RDF is the single source of truth for all agent definitions,
commands, scripts, and governance deployed into Claude Code, Gemini CLI,
Codex, or AGENTS.md environments.

**Version:** 3.0.0
**License:** GNU GPL v2

---

## Architecture

### Core Principles

- **Canonical-first, adapter-delivered:** All convention content, agent prompts,
  and governance docs live as tool-agnostic markdown in `canonical/`. Tool-specific
  adapters generate deployment artifacts from canonical sources. Development happens
  in `canonical/` -- deployed copies are generated output, not editable originals.
- **RDF is authoritative:** The repo is the source of truth. `/root/.claude/` and
  other tool-specific directories are deployment targets populated by `rdf generate`.
  Emergency edits to deployed copies are pulled back via `rdf sync`.
- **Governance-driven agent behavior:** Six universal agents (planner, dispatcher,
  engineer, qa, uat, reviewer) replace the prior 12+ domain-specific agents. Agent
  behavior is shaped by governance files initialized per-project via `/r:init`, not
  by baking domain knowledge into agent prompts. Profiles provide governance seed
  templates, not agent/command bundles.
- **Unified CLI:** Single `rdf` dispatcher with lazy-sourced subcommand modules
  (`rdf generate`, `rdf profile`, `rdf init`, `rdf doctor`, `rdf state`,
  `rdf refresh`, `rdf sync`, `rdf github`).
- **Not a runtime:** Claude Code / Gemini CLI / Codex IS the runtime. RDF is the
  governance layer that tells the runtime how to behave.
- **Plugin is an adapter, not the architecture:** Claude Code plugin structure
  is one delivery mechanism. The canonical source works regardless of tool.
- **GitHub-native project management:** GitHub Issues + Projects v2 is the durable
  work tracking layer using phase-level tracking (v2 issue model). The issue
  hierarchy is: initiative (planning horizon) -> release (committed version) ->
  phase (execution unit) -> task comments (progress trail).

### Naming Convention

**v3 convention:** Universal agents use role-only names with `rdf-` prefix.

| Agent | CC Name | Model | Role |
|-------|---------|-------|------|
| planner | rdf-planner | opus | Research, specs, implementation plans |
| dispatcher | rdf-dispatcher | sonnet | Plan execution orchestrator |
| engineer | rdf-engineer | opus | Universal implementation |
| qa | rdf-qa | sonnet | Verification gate |
| uat | rdf-uat | sonnet | User acceptance testing |
| reviewer | rdf-reviewer | opus | Adversarial review (challenge + sentinel) |

**Slash commands:** `/r-{name}` (lifecycle) or `/r-util-{name}` (utility)

---

## Target Directory Structure

```
rdf/                                 # Repository root
|-- bin/
|   +-- rdf                          # Thin wrapper dispatcher (~55 lines)
|
|-- lib/
|   |-- rdf_common.sh                # Shared init, version, config, cleanup
|   +-- cmd/                         # Subcommand handlers (sourced, not executed)
|       |-- generate.sh              # rdf generate <claude-code|gemini-cli|codex|agents-md|all>
|       |-- profile.sh               # rdf profile <list|install|remove|status>
|       |-- init.sh                  # rdf init <path> [--type] [--batch] [--tools] [--github]
|       |-- doctor.sh                # rdf doctor [path] [--all] [--scope]
|       |-- state.sh                 # rdf state [path] -> JSON to stdout
|       |-- refresh.sh               # rdf refresh [path] [--scope memory|plan|github|all]
|       |-- sync.sh                  # rdf sync -> pull /root/.claude/ back to canonical
|       +-- github.sh                # rdf github <setup|sync-labels|ecosystem-init|ecosystem-add>
|
|-- canonical/                       # Tool-agnostic framework content
|   |-- agents/                      # 6 universal agents (pure markdown)
|   |   |-- planner.md               # Research, specs, plans
|   |   |-- dispatcher.md            # Plan execution orchestrator
|   |   |-- engineer.md              # Universal implementation
|   |   |-- qa.md                    # Verification gate
|   |   |-- uat.md                   # User acceptance testing
|   |   +-- reviewer.md              # Adversarial review (challenge + sentinel)
|   |
|   |-- commands/                    # 23 commands under /r: namespace
|   |   |-- r-init.md                # Governance initialization
|   |   |-- r-start.md               # Session initialization
|   |   |-- r-plan.md                # Planning workflow
|   |   |-- r-mode.md                # Mode switching
|   |   |-- r-status.md              # Project health dashboard
|   |   |-- r-refresh.md             # Governance refresh
|   |   |-- r-sync.md                # Canonical source sync
|   |   |-- r-audit.md               # Full codebase audit
|   |   |-- r-ship.md                # Release workflow
|   |   |-- r-build.md               # Plan phase execution
|   |   |-- r-verify.md              # QA verification
|   |   |-- r-test.md                # UAT acceptance
|   |   |-- r-review.md              # Adversarial review
|   |   |-- r-util-*.md              # 10 utility commands
|   |   +-- templates/               # Governance template docs
|   |
|   |-- scripts/                     # Hook scripts (bash, tool-agnostic)
|   +-- reference/                   # Framework-level docs
|
|-- profiles/
|   |-- registry.md                  # Profile catalog
|   |-- core/                        # Core profile
|   |   +-- governance-template.md   # Governance seed for /r:init
|   |-- shell/                       # Bash/shell projects
|   |-- python/                      # Python projects
|   |-- frontend/                    # Web/frontend
|   |-- database/                    # Database projects
|   +-- go/                          # Go projects
|
|-- adapters/
|   |-- claude-code/
|   |   |-- adapter.sh               # CC-specific generation logic
|   |   |-- agent-meta.json          # YAML frontmatter values per agent
|   |   |-- command-meta-v3.json     # Command dispatch metadata
|   |   |-- teams-meta.json          # Agent Teams configuration
|   |   |-- hooks/
|   |   |   +-- hooks.json           # CC hook event mapping
|   |   +-- output/                  # GENERATED by 'rdf generate claude-code'
|   |-- gemini-cli/
|   |-- codex/
|   +-- agents-md/
|
|-- state/
|   +-- rdf-state.sh                 # Project state -> JSON (<1s, no LLM)
|
|-- CLAUDE.md                        # RDF project's own instructions
|-- VERSION                          # "3.0.0"
|-- CHANGELOG
|-- CHANGELOG.RELEASE
|-- RDF.md                           # Architecture doc (this file)
|-- WORKFORCE.md                     # Agent workforce + pipelines
+-- README.md                        # Public-facing docs
```

---

## Scope

**In scope:**

- Canonical agent/command/script storage with tool-agnostic content
- 6 universal agents with governance-driven behavior
- 23 commands under `/r:` namespace (13 lifecycle + 10 utility)
- Unified CLI (`rdf generate`, `rdf profile`, `rdf init`, `rdf doctor`, `rdf state`,
  `rdf refresh`, `rdf sync`, `rdf github`)
- Tool-specific adapters (Claude Code, Gemini CLI, Codex, AGENTS.md)
- Governance initialization via `/r:init` with profile-based templates
- GitHub Issues + Projects v2 integration
- Health checking (`rdf doctor`) with drift detection
- Deterministic state helper (`rdf state`)
- Emergency reverse sync (`rdf sync`)

**Out of scope (deferred):**

- Plugin marketplace publishing
- Additional discipline profiles beyond core/shell/python/frontend/database/go
- SQLite state store (evaluate if flat files become unwieldy at 30+ projects)

---

## Risk Assessment

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| Governance template gap for new domain | Medium | Medium | Profile system seeds templates; engineer reads project CLAUDE.md |
| Adapter adds complexity without value | Low | Medium | Proven by v2 pipeline; 6 months production use |
| CLI scope creep delays delivery | Medium | Medium | Lazy-sourced modules; each subcommand is independent |
| GitHub integration couples to API changes | Low | Medium | All operations use `gh` CLI; adapter isolated from API versioning |
| Agent Teams API instability | High | Low | Feature-flagged; subagent mode is default |
| Cross-reference breakage during rename | Low | High | Automated stale-name grep in rdf doctor |

---

## Success Metrics

- All active projects pass `rdf doctor --all` with OK status
- `rdf generate claude-code` produces 6 agents + 23 commands
- `rdf state` returns accurate JSON for any project in <1 second
- Zero convention drift between canonical source and deployed copies
- Zero stale v2 references in active code
- Framework adds <5 minutes overhead per session
