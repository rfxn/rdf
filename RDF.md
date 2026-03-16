# RDF — rfxn Development Framework

## Overview

Canonical-first convention governance with profile-based discipline selection,
unified CLI, GitHub-native project management, and tool-specific adapter
generation. RDF is the single source of truth for all agent definitions,
commands, scripts, and governance deployed into Claude Code, Gemini CLI,
Codex, or AGENTS.md environments.

**Version target:** 2.0.0
**License:** GNU GPL v2

---

## Architecture

### Core Principles

- **Canonical-first, adapter-delivered:** All convention content, agent prompts,
  and governance docs live as tool-agnostic markdown in `canonical/`. Tool-specific
  adapters generate deployment artifacts from canonical sources. Development happens
  in `canonical/` — deployed copies are generated output, not editable originals.
- **RDF is authoritative:** The repo is the source of truth. `/root/.claude/` and
  other tool-specific directories are deployment targets populated by `rdf generate`.
  Emergency edits to deployed copies are pulled back via `rdf sync`.
- **Profile system for discipline selection:** Core framework primitives are
  always active. Domain profiles (systems-engineering, security, frontend, future
  disciplines) bundle relevant agents, commands, conventions, and reference docs.
  Multiple profiles can be active simultaneously with dependency resolution.
- **Unified CLI:** Single `rdf` dispatcher with lazy-sourced subcommand modules
  (`rdf generate`, `rdf profile`, `rdf init`, `rdf doctor`, `rdf state`,
  `rdf refresh`, `rdf sync`, `rdf github`). Replaces the previous `rdf-init`,
  `rdf-doctor`, `rdf-generate` standalone scripts.
- **Not a runtime:** Claude Code / Gemini CLI / Codex IS the runtime. RDF is the
  governance layer that tells the runtime how to behave.
- **Plugin is an adapter, not the architecture:** Claude Code plugin structure
  is one delivery mechanism. The canonical source works regardless of tool.
- **GitHub-native project management:** GitHub Issues + Projects v2 is the durable
  work tracking layer. PLAN.md and MEMORY.md remain as session-local agent context
  but GitHub Issues is the source of truth for queue state.

### Naming Convention

**Pattern:** `{domain}-{role}` for domain-specific, `{role}` for core.

Three tiers:

| Tier | Prefix | Agents | Rationale |
|------|--------|--------|-----------|
| Core | none | mgr, po, scope | Orchestrate across any domain |
| Domain | {domain}- | sys-eng, sys-qa, sys-uat, sys-sentinel, sys-challenger, sys-ux | Domain expertise in agent prompt |
| Specialist | {domain}- | sec-eng, fe-qa, fe-uat | Cross-cutting or domain-scoped |

**Domain registry:**

| Shortcode | RDF Profile | Domain |
|-----------|-------------|--------|
| sys | systems-engineering | Bash/shell, Linux, security tooling |
| sec | security | Offensive/defensive security assessment |
| fe | frontend | Vue/React, CSS, Playwright |
| php | php-backend | PHP, MySQL, cPanel/Plesk apps (future) |
| py | python-backend | Python/Perl, Postgres (future) |
| iaas | infrastructure | IaaS, API integrations, cloud (future) |
| fs | full-stack | Cross-stack coordination (future) |

**CC agent names:** `rfxn-{file-stem}` (e.g., `rfxn-sys-eng`, `rfxn-mgr`)
**Slash commands:** `/{file-stem}` (e.g., `/sys-eng`, `/mgr`)

### Market Assessment

No existing tool provides cross-project convention governance, typed agent
pipelines with quality gates, hierarchical convention inheritance, or
domain-specific agent personas.

| Tool | What it does | Why not |
|------|-------------|---------|
| Ruflo (claude-flow) | 60+ agents, swarm topologies | Unreliable; "almost nothing works" (GH #624) |
| GSD (get-shit-done) | Phase execution, state files | Subagents miss CLAUDE.md; governance regression |
| Cline Memory Bank | Structured project memory | Single-project only, no cross-project |
| CCPM | GitHub Issues + worktrees | Single-project task management |
| everything-claude-code | 12 agents, 24 commands | Generic; no domain depth |
| @mallardbay/cursor-rules | Cross-platform rule sync | File-copy level; no inheritance or drift detection |

Claude Code Native Agent Teams (experimental) is the one development to watch.
Phase 5 designs the dispatch abstraction layer so the pipeline can adopt Agent
Teams natively when stable, with zero regression to the current subagent model.

---

## Target Directory Structure

```
rdf/                                 # Repository root
|-- .claude-plugin/
|   +-- plugin.json                  # CC plugin manifest
|
|-- bin/
|   +-- rdf                          # Thin wrapper dispatcher (~50 lines)
|
|-- lib/
|   |-- rdf_common.sh                # Shared init, version, config, cleanup
|   |                                # Guard: _RDF_COMMON_LOADED
|   |                                # rdf_init(): idempotent
|   |                                # rdf_die(), rdf_log(), rdf_require_bin()
|   |
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
|   |-- agents/                      # Pure markdown, no tool frontmatter
|   |   |-- mgr.md                   # Core: Engineering Manager
|   |   |-- po.md                    # Core: Product Owner
|   |   |-- scope.md                 # Core: Scoping & Research
|   |   |-- sys-eng.md               # Systems: Senior Engineer (7-step)
|   |   |-- sys-qa.md                # Systems: QA Engineer (6-step)
|   |   |-- sys-uat.md               # Systems: UAT (Docker sysadmin)
|   |   |-- sys-sentinel.md          # Systems: Post-impl 4-pass review
|   |   |-- sys-challenger.md        # Systems: Pre-impl adversary
|   |   |-- sys-ux.md                # Systems: UX/output design review
|   |   |-- sec-eng.md               # Security: Security engineer
|   |   |-- fe-qa.md                 # Frontend: QA (API/DOM/CSS/JS)
|   |   +-- fe-uat.md                # Frontend: UAT (Playwright)
|   |
|   |-- commands/                    # Pure markdown (~64 commands)
|   |   |-- mgr.md                   # Engineering Manager orchestrator
|   |   |-- sys-eng.md ... sys-ux.md # Domain persona dispatchers
|   |   |-- po.md, scope.md          # Core persona dispatchers
|   |   |-- sec-eng.md               # Security dispatch
|   |   |-- fe-qa.md, fe-uat.md      # Frontend dispatchers
|   |   |-- audit*.md                # 24 audit commands
|   |   |-- rel-*.md                 # 7 release commands
|   |   |-- proj-*.md                # 6 project commands
|   |   |-- mem-*.md                 # 3 memory commands
|   |   |-- code-*.md                # 2 code quality commands
|   |   |-- test-*.md                # 3 test commands
|   |   |-- refresh.md               # State refresh (agent-driven)
|   |   +-- *.md                     # modernize, onboard, reload, status,
|   |                                # ci-setup, lib-release, doc-author
|   |
|   |-- scripts/                     # Hook scripts (bash, tool-agnostic)
|   |   |-- pre-commit-validate.sh
|   |   |-- post-edit-lint.sh
|   |   |-- subagent-stop.sh
|   |   |-- context-bar.sh
|   |   |-- clone-conversation.sh
|   |   |-- half-clone-conversation.sh
|   |   |-- check-context.sh
|   |   |-- setup.sh
|   |   |-- color-preview.sh
|   |   +-- test-half-clone.sh
|   |
|   +-- reference/                   # Framework-level docs (profile-independent)
|       |-- framework.md
|       |-- memory-standards.md
|       +-- session-safety.md
|
|-- profiles/
|   |-- registry.json                # Profile catalog + dependency graph
|   |
|   |-- core/
|   |   |-- profile.json             # Components: mgr, po, scope + core scripts
|   |   +-- governance.md            # Commit protocol, memory standards,
|   |                                # session safety, artifact taxonomy,
|   |                                # GitHub Issues conventions
|   |
|   |-- systems-engineering/
|   |   |-- profile.json             # Components: sys-* agents/commands + scripts
|   |   |-- governance.md            # Bash 4.1, shell standards, portability,
|   |   |                            # testing, verification before commit
|   |   |-- templates/
|   |   |   |-- claude-shell.md.tmpl
|   |   |   +-- claude-lib.md.tmpl
|   |   +-- reference/
|   |       |-- os-compat.md
|   |       |-- test-infra.md
|   |       |-- cross-project.md
|   |       +-- audit-pipeline.md
|   |
|   |-- security/
|   |   |-- profile.json             # Components: sec-eng
|   |   |-- governance.md            # Security assessment methodology
|   |   +-- templates/
|   |       +-- claude-security.md.tmpl
|   |
|   +-- frontend/
|       |-- profile.json             # Components: fe-qa, fe-uat
|       |-- governance.md            # Web conventions (generic, framework-agnostic)
|       +-- templates/
|           +-- claude-frontend.md.tmpl
|
|-- adapters/
|   |-- claude-code/
|   |   |-- adapter.sh               # CC-specific generation logic
|   |   |-- agent-meta.json          # YAML frontmatter values per agent
|   |   |-- command-meta.json        # YAML frontmatter values per command
|   |   |-- hooks/
|   |   |   +-- hooks.json           # CC hook event mapping
|   |   +-- output/                  # GENERATED by 'rdf generate claude-code'
|   |       |-- agents/              # Canonical + YAML frontmatter
|   |       |-- commands/            # Canonical + YAML frontmatter
|   |       +-- scripts/             # Copied from canonical
|   |-- gemini-cli/
|   |   +-- adapter.sh               # Gemini-specific generation
|   |-- codex/
|   |   +-- adapter.sh               # Codex-specific generation
|   +-- agents-md/
|       +-- adapter.sh               # AGENTS.md generation
|
|-- state/
|   +-- rdf-state.sh                 # Project state -> JSON (<1s, no LLM)
|
|-- docs/
|   +-- specs/                       # Architecture and design documents
|
|-- CLAUDE.md                        # RDF project's own instructions
|-- VERSION                          # "2.0.0"
|-- CHANGELOG
|-- CHANGELOG.RELEASE
|-- RDF.md                           # Architecture doc (this file)
|-- WORKFORCE.md                     # Org chart + pipelines
+-- README.md                        # Public-facing docs
```

---

## Scope

**In scope:**

- Canonical agent/command/script storage with tool-agnostic content
- Profile system for discipline-based convention bundles (core, systems-engineering,
  security, frontend) with dependency resolution
- Unified CLI (`rdf generate`, `rdf profile`, `rdf init`, `rdf doctor`, `rdf state`,
  `rdf refresh`, `rdf sync`, `rdf github`)
- Tool-specific adapters (Claude Code, Gemini CLI, Codex, AGENTS.md)
- GitHub Issues + Projects v2 integration: standardized label taxonomy,
  repo-level and org-level project boards, issue templates, workflow integration
- Project initialization (`rdf init`) with batch mode, type detection, GitHub
  scaffolding, and per-tool configuration
- Health checking (`rdf doctor`) with drift detection across artifacts, memory,
  plan, GitHub sync, and convention compliance
- Deterministic state helper (`rdf state`) returning project JSON in <1 second
- Agent-driven state refresh (`rdf refresh`) with scope-based updates
- Emergency reverse sync (`rdf sync`) to pull deployed edits back to canonical
- Agent Teams readiness: dispatch abstraction layer supporting both subagent and
  native Agent Teams modes behind a feature flag
- Friction fixes: self-verification gates (sys-qa, sys-sentinel), scope
  confirmation (mgr), evidence requirements (sys-eng), context anchoring (reload)
- {domain}-{role} naming convention applied across all agents, commands, and
  CC registrations

**Out of scope (deferred):**

- Plugin marketplace publishing
- Additional discipline profiles beyond core/systems-engineering/security/frontend
- SQLite state store (evaluate if flat files become unwieldy at 30+ projects)

---

## Risk Assessment

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| Canonical migration introduces naming regressions | Medium | High | Phase 1 verification pass: grep for all stale names, diff against live state |
| Adapter adds complexity without value | Medium | Medium | Phase 2 proves value by achieving zero behavioral difference vs current layout |
| Profile split loses conventions | Low | High | Verification: core + systems-engineering governance = full parent CLAUDE.md |
| Unified CLI scope creep delays delivery | Medium | Medium | CLI is lazy-sourced; each subcommand is independent and can ship incrementally |
| GitHub integration couples to API changes | Low | Medium | All GitHub operations use `gh` CLI; adapter is isolated from API versioning |
| Agent Teams API instability | High | Low | Feature-flagged; subagent mode is default, Agent Teams opt-in behind RDF_AGENT_TEAMS |
| Codex/Gemini adapter formats change | Medium | Low | Adapters are isolated; rebuild without affecting canonical or other adapters |
| Cross-reference breakage during rename | Medium | High | Automated stale-name grep across all canonical files before each phase commit |
| Framework maintenance tax | Medium | Medium | Single dispatcher + lazy-sourced modules; no daemon, no database |

---

## Success Metrics

- All 12 active projects pass `rdf doctor --all` with OK status
- `rdf generate claude-code` output is functionally identical to current setup
- `rdf generate all` produces valid output for all active adapters
- `rdf state` returns accurate JSON for any project in <1 second
- Zero convention drift between canonical source and deployed copies
- Zero stale names (old short-form agent/command names) in any file
- `rdf init --batch` onboards all existing projects in <1 hour
- `rdf github setup` scaffolds a complete repo project in one command
- Org-level Ecosystem Project provides cross-repo visibility for all rfxn repos
- Framework adds <5 minutes overhead per session vs current direct-edit workflow
- Agent Teams dispatch abstraction passes all pipeline scenarios in both modes

---

## Dependency Graph

```
Phase 1 (canonical + naming + friction)
  |-- Phase 2 (adapter + state + CLI + github)
  |     |-- Phase 3 (profiles)
  |     |     |-- Phase 4 (state refresh) -- needs profiles
  |     |     |-- Phase 7 (init + doctor) -- needs profiles for templates
  |     |     +-- Phase 6 (gemini/codex) -- needs adapter pattern
  |     +-- Phase 5 (agent teams) -- needs adapter, independent of profiles
  +-- Phase 8 (docs + cutover) -- depends on all above
```

Phase 2 starts after Phase 1. Phase 3 requires Phase 2.
Phases 4, 6, and 7 require Phase 3. Phase 5 requires Phase 2 (independent
of profiles). Phase 8 requires all phases stable.
