# RDF — rfxn Development Framework

## Overview

Tool-agnostic convention governance with profile-based discipline selection,
delivered through tool-specific adapters, with deterministic state checking
and repeatable project intake at scale.

**Version target:** 1.0.0
**License:** GNU GPL v2

---

## Architecture

### Core Principles

- **Canonical-first, adapter-delivered:** All convention content, agent prompts,
  and governance docs live as tool-agnostic markdown. Tool-specific adapters
  (Claude Code plugin, Gemini CLI config, AGENTS.md) are generated from the
  canonical source.
- **Profile system for discipline selection:** Core framework primitives are
  always active. Domain profiles (systems-engineering, frontend, future
  disciplines) bundle relevant agents, commands, conventions, and reference
  docs. Multiple profiles can be active simultaneously.
- **Not a runtime:** Claude Code / Gemini CLI IS the runtime. RDF is the
  governance layer that tells the runtime how to behave.
- **Plugin is an adapter, not the architecture:** Claude Code plugin structure
  is one delivery mechanism. The canonical source works regardless of tool.

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
When stable, it would complement our pipeline with native shared task lists
and inter-agent messaging. No adoption needed — it arrives as a platform update.

---

## Target Directory Structure

```
rdf/
├── .claude-plugin/
│   └── plugin.json               # Claude Code plugin manifest
│
├── canonical/                    # Tool-agnostic framework content
│   ├── agents/                   # Agent prompts (pure markdown, no tool frontmatter)
│   │   ├── se.md                 # 7-step execution protocol
│   │   ├── qa.md                 # 6-step gate protocol
│   │   ├── uat.md                # Sysadmin persona, Docker scenarios
│   │   ├── challenger.md         # Pre-impl adversary
│   │   ├── sentinel.md           # Post-impl 4-pass review
│   │   ├── scope.md              # Scoping & research
│   │   ├── po.md                 # Product owner intake
│   │   ├── frontend-qa.md
│   │   ├── frontend-uat.md
│   │   └── ux-review.md
│   │
│   ├── commands/                 # Command prompts (pure markdown)
│   │   ├── em.md                 # Engineering Manager orchestrator
│   │   ├── se.md, qa.md, uat.md  # Agent dispatch commands
│   │   ├── audit-*.md            # 15 domain agents + orchestrators
│   │   ├── rel-*.md              # Release workflow (7 commands)
│   │   ├── proj-*.md             # Project coordination (7 commands)
│   │   ├── mem-*.md              # Memory management (3 commands)
│   │   ├── code-*.md             # Code quality (4 commands)
│   │   ├── test-*.md             # Test utilities (2 commands)
│   │   └── *.md                  # Standalone (reload, onboard, etc.)
│   │
│   ├── scripts/                  # Hook scripts (bash, tool-agnostic logic)
│   │   ├── pre-commit-validate.sh
│   │   ├── post-edit-lint.sh
│   │   ├── subagent-stop.sh
│   │   ├── overwatch-hook.sh
│   │   ├── context-bar.sh
│   │   ├── clone-conversation.sh
│   │   ├── half-clone-conversation.sh
│   │   └── ...
│   │
│   └── reference/                # Framework-level docs (profile-independent)
│       ├── framework.md          # RDF artifact taxonomy
│       ├── memory-standards.md
│       └── session-safety.md
│
├── profiles/                     # Domain-specific convention bundles
│   ├── registry.json             # Profile catalog
│   │
│   ├── core/                     # Always active — framework primitives
│   │   ├── profile.json          # Component lists, no dependencies
│   │   └── governance.md         # Commit protocol, memory standards,
│   │                               session safety, artifact taxonomy
│   │
│   ├── systems-engineering/      # Bash/shell/systems profile
│   │   ├── profile.json          # Component lists, requires: [core]
│   │   ├── governance.md         # Bash 4.1 floor, shell standards,
│   │   │                           portability, error handling, testing
│   │   ├── templates/
│   │   │   ├── claude-shell.md.tmpl
│   │   │   └── claude-lib.md.tmpl
│   │   └── reference/
│   │       ├── os-compat.md
│   │       ├── test-infra.md
│   │       ├── cross-project.md
│   │       └── audit-pipeline.md
│   │
│   └── frontend/                 # Frontend/web profile
│       ├── profile.json          # requires: [core]
│       ├── governance.md
│       ├── templates/
│       │   └── claude-frontend.md.tmpl
│       └── reference/
│
├── adapters/                     # Tool-specific delivery mechanisms
│   ├── claude-code/              # Claude Code plugin adapter
│   │   ├── generate.sh           # Builds plugin from canonical + profiles
│   │   └── hooks/
│   │       └── hooks.json        # Claude Code hook event mapping
│   ├── gemini-cli/               # Gemini CLI adapter
│   │   └── generate.sh           # Generates GEMINI.md + .gemini/ config
│   └── agents-md/                # Cross-tool standard adapter
│       └── generate.sh           # Generates AGENTS.md per project
│
├── state/                        # Deterministic state helpers
│   └── rdf-state.sh              # Project state → JSON (no LLM tokens)
│
├── bin/                          # Framework CLI tools
│   ├── rdf-init                  # Project initializer
│   ├── rdf-doctor                # Health checker / drift detection
│   ├── rdf-profile               # Profile manager
│   └── rdf-generate              # Generate tool-specific files from canonical
│
├── CLAUDE.md                     # Framework project's own instructions
├── VERSION                       # "1.0.0"
├── CHANGELOG
├── CHANGELOG.RELEASE
└── README.md
```

---

## Scope

**In scope:**
- Canonical agent/command/script storage with tool-agnostic content
- Profile system for discipline-based convention bundles
- Tool-specific adapters (Claude Code, Gemini CLI, AGENTS.md)
- Project initialization (rdf-init) with batch mode for onboarding
- Health checking (rdf-doctor) with drift detection
- Deterministic state helper (rdf-state.sh)
- Agent-driven state refresh (/refresh)
- Pipeline optimization: test result registry, agent test lock protocol,
  Challenger two-dispatch gate, library integration Sentinel, UX Reviewer
  expanded triggers, pipeline metrics (JSONL + rolling averages),
  EM context delegation via Scope work order assembly

**Out of scope (deferred):**
- Overwatch integration (separate project, separate plan)
- Plugin marketplace publishing
- Additional discipline profiles beyond core/systems-engineering/frontend
- Claude Code Agent Teams integration (waiting for stable release)
- SQLite state store (evaluate if flat files become unwieldy at 30+ projects)

---

## Risk Assessment

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| Adapter adds complexity without value | Medium | Medium | Phase 2 proves value by achieving zero behavioral difference |
| Profile split loses conventions | Low | High | Verification: core + SE governance = full parent CLAUDE.md |
| Gemini CLI format changes | Medium | Low | Adapter is isolated; rebuild without affecting canonical |
| Batch onboarding overwhelms framework | Low | Medium | Batch mode + `--no-memory` for quick structural init |
| Framework maintenance tax | Medium | Medium | Keep tooling minimal: 4 bash scripts + 1 JSON schema |
| Tool-agnostic abstraction is premature | Low | Medium | Already using Gemini CLI; multi-tool is current reality |

---

## Success Metrics

- All 10 active projects pass `rdf-doctor` with OK status
- Batch project initialization via `rdf-init --batch` completes in <1 hour
- `rdf-generate claude-code` output is functionally identical to current setup
- `rdf-state.sh` returns accurate JSON for any project in <1 second
- Zero convention drift between canonical source and installed copies
- Framework adds <5 minutes overhead per session vs current direct-edit workflow

---

## Dependency Graph

```
Phase 1 (canonical migration)
  ├─→ Phase 2 (claude adapter) ─── symlinks work immediately
  ├─→ Phase 3 (profiles) ─────── can define without adapter
  │     ├─→ Phase 4 (rdf-init) ── needs profiles for templates
  │     └─→ Phase 5 (rdf-doctor)─ needs profiles for drift detection
  ├─→ Phase 6 (state helper) ──── independent, pure bash + JSON
  ├─→ Phase 7 (gemini adapter) ── needs Phase 2 pattern as reference
  └─→ Phase 8 (docs + archive) ── depends on all above being stable
```

Phases 2, 3, and 6 can start in parallel after Phase 1.
Phase 4 requires Phase 3. Phase 5 requires Phase 3.
Phase 7 requires Phase 2. Phase 8 requires all phases stable.
