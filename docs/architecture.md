---
title: Architecture
parent: Project
nav_order: 1
description: "How RDF is built: canonical markdown, per-tool adapters, governance-driven agents, data flow and the repository layout."
---

# Architecture
{: .no_toc }

RDF is a governance layer, not a runtime. Claude Code, Codex and Antigravity CLI do
the work. RDF tells them how to behave.

1. TOC
{:toc}

## Design principles

| Principle | What it means |
|-----------|---------------|
| Canonical-first, adapter-delivered | Content lives as tool-agnostic markdown in `canonical/`. Adapters generate tool-specific output |
| Governance-driven agents | Universal agents are shaped by per-project governance, not baked-in domain knowledge. Same agent, different governance, different behavior |
| Profiles are expertise, modes are methodology | Profiles define what the code is. Modes define how you work. They compose independently |
| Convention over configuration | The most specific rule always wins |

## Philosophy

**Governance overhead is proportional to blast radius.** Security tools running on
350,000 servers need more gates than a weekend project, so RDF scales governance to
risk with [tiers and scopes](pipeline.md).

**Agents are context buffers, not general-purpose.** Narrow context produces deep
review. See [Agents](agents.md).

**Convention inheritance beats documentation.** Projects inherit conventions from
profiles and parent governance files, and the AI reads them automatically. Nobody has
to remember to brief the model.

**Trust is earned with evidence, not claims.** Every gate requires specifics: grep
output, test results, commit hashes. "I checked and it's fine" is not acceptable.

## Data flow

```text
canonical/          Adapter            Tool deployment
  agents/*.md  -->  adapter.sh   -->   output/agents/*.md     -->  ~/.claude/agents/
  commands/*.md     (frontmatter       output/skills/<n>/          ~/.claude/skills/<n>/
                    injection)           SKILL.md                  (per-skill symlinks)
  scripts/*.sh                         output/scripts/*.sh         ~/.claude/scripts/
```

| Path | Steps |
|------|-------|
| Normal | Edit `canonical/`, run `rdf generate`, and symlinks pick up the change. New commands also need `rdf deploy` |
| Emergency | Edit `~/.claude/`, then `rdf sync` pulls it back to canonical |
| Drift check | `rdf doctor --scope content-drift` compares `.rdf-hash` sidecars |

## Adapters

Write content once in tool-agnostic markdown and generate for each runtime:

| Adapter | Output | Deploy target |
|---------|--------|---------------|
| Claude Code | YAML-frontmattered agents plus `skills/<cmd>/SKILL.md` with intent descriptions | `~/.claude/` |
| Claude Plugin | The same skills layout, with `/r-X` rewritten to `/rdf:r-X` and output committed | Plugin install, which clones the repo |
| Agent Skills | `.agents/skills/<cmd>/SKILL.md`, shared by Codex and Antigravity CLI | Workspace root |
| AGENTS.md | Cross-tool documentation, composed per project | Project root |
| Gemini CLI (legacy) | TOML commands, YAML agents and `GEMINI.md` | `~/.gemini/` |

Codex and Antigravity CLI are served by the Agent Skills and AGENTS.md composite, not a
bespoke adapter. `rdf generate all` builds all five adapters in one pass. See
[Multi-tool parity](multi-tool-parity.md).

## Repository layout

```text
rdf/
|-- bin/rdf                             # CLI dispatcher
|-- lib/
|   |-- rdf_common.sh                   # Shared helpers, profile system
|   +-- cmd/                            # One file per rdf subcommand
|-- canonical/
|   |-- agents/                         # 7 universal agents (pure markdown)
|   |-- commands/                       # 38 commands (/r- namespace)
|   |-- scripts/                        # 16 hook and helper scripts (bash)
|   +-- reference/                      # Framework docs
|-- profiles/
|   |-- registry.json                   # Machine-readable profile catalog
|   |-- registry.md                     # Human-readable profile catalog
|   |-- detection-rules.md              # Auto-detection signals per profile
|   |-- core/                           # Always active
|   +-- lite/                           # rdf-lite deploy source, not a registered profile
|-- modes/                              # 7 session-scoped overlays
|-- adapters/
|   |-- claude-code/                    # CC adapter, metadata and hooks
|   |-- claude-plugin/                  # Plugin adapter (namespaced, committed output)
|   |-- agent-skills/                   # Shared .agents/skills (Codex, Antigravity)
|   |-- gemini-cli/                     # Gemini CLI adapter (legacy tier)
|   +-- agents-md/                      # Cross-tool AGENTS.md composer
|-- state/
|   |-- rdf-state.sh                    # Project state as JSON
|   |-- rdf-tokens.sh                   # Local token usage report
|   |-- rdf-env.sh                      # Environment assessment
|   |-- context-audit.sh                # Context weight audit
|   +-- rotate-work-output.sh           # Age and size based rotation
+-- reference/                          # Diagrams and architecture docs
```

[RDF.md](https://github.com/rfxn/rdf/blob/main/RDF.md) has the file-level tree, the
scope and the risk assessment.

## Scripts

Sixteen scripts deploy to `~/.claude/scripts/`.

| Script | Purpose |
|--------|---------|
| `context-bar.sh` | [Status line](context-bar.md): project, branch, phase, model |
| `session-start-inject.sh` | SessionStart hook: inject the lessons ID-index |
| `session-start-context.sh` | SessionStart hook after compaction: re-inject the handoff |
| `session-end-capture.sh` | SessionEnd hook: git snapshot to the session journal |
| `precompact-snapshot.sh` | PreCompact hook: snapshot session state |
| `state-bootstrap.sh` | SessionStart hook: deliver `~/.rdf/state` helpers on plugin installs |
| `subagent-stop.sh` | SubagentStop hook: capture agent completion events |
| `pre-commit-validate.sh` | PreToolUse hook: pre-commit lint and anti-pattern greps |
| `post-edit-lint.sh` | PostToolUse hook: `bash -n` syntax check on edited shell files |
| `comment-metrics.sh` | Per-file comment cruft metrics for shell source |
| `check-context.sh` | Context window utilization check |
| `clone-conversation.sh` | Fork the current conversation to a new session |
| `half-clone-conversation.sh` | Fork the recent half of a conversation |
| `test-half-clone.sh` | Test harness for half-clone |
| `setup.sh` | First-run environment setup |
| `color-preview.sh` | Terminal color palette preview |

## Diagrams

[reference/diagrams.md](https://github.com/rfxn/rdf/blob/main/reference/diagrams.md) has
Mermaid diagrams of the pipeline, architecture and ecosystem.
