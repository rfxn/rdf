---
title: Multi-Tool Parity
parent: Reference
nav_order: 5
description: "What RDF supports in Claude Code, Codex and Antigravity CLI: commands, skills, context files, hooks, plus the legacy Gemini CLI tier."
---

# Multi-tool parity
{: .no_toc }

RDF generates governance, commands and skills for several AI coding tools from one
canonical source. Claude Code, Codex CLI and Antigravity CLI are first-class. Gemini CLI
is a frozen legacy tier for enterprise users.

1. TOC
{:toc}

## Compare the tools

| | Claude Code | Codex CLI | Antigravity CLI | Gemini CLI |
|---|-------------|-----------|-----------------|------------|
| **Tier** | First-class | First-class | First-class | Legacy, frozen |
| **Commands** | All 38, as `.claude/skills/<cmd>/SKILL.md` with intent descriptions | 11 lifecycle, as `.agents/skills/<cmd>/SKILL.md` (native scan) | 11 lifecycle, as skills (fuzzy-matched slash) | `.gemini/commands/*.toml` |
| **Skills** | Its own `skills/` tree | Shared `.agents/skills/` | Shared `.agents/skills/` | Through `agy plugin import gemini` |
| **Context file** | `CLAUDE.md`, not `AGENTS.md` | `AGENTS.md` | `AGENTS.md` and `GEMINI.md` | `GEMINI.md` |
| **Hooks** | `hooks.json` | [Deferred](#deferred-surfaces) | [Deferred](#deferred-surfaces) | None |
| **Generate target** | `claude-code` | `codex` | `antigravity` | `gemini-cli` |

### Claude Code: plugin or symlink deploy

| | Symlink deploy | Plugin install |
|---|----------------|----------------|
| **Install** | `rdf deploy claude-code` | `/plugin install rdf@rdf` |
| **Command names** | `/r-start` | `/rdf:r-start` |
| **`rdf` CLI** | Yes | No |
| **Hooks** | Manual merge into `settings.json` | Register automatically |
| **`~/.rdf/state/` helpers** | Symlinked by deploy | Copied by a SessionStart hook |

On a plugin install, the helpers arrive at the first session start after install. Until
that restart, 11 state-backed commands run in a degraded mode: `r-spec`, `r-plan`,
`r-build`, `r-ship`, `r-status`, `r-env`, `r-save`, `r-refresh`, `r-context-audit`,
`r-vpe` and `r-util-mem-compact`. `r-start` falls back gracefully. The others need the
helpers for full session-scoped state.

## The shared skills directory

`.agents/skills/` is one workspace-level tree that Codex, Antigravity CLI and every
[Agent Skills](https://agentskills.io/) client read. It is emitted once, by a dedicated
adapter, and is not duplicated into per-tool output:

```bash
rdf generate agent-skills                                  # emit the tree
rdf deploy --project-root /path/to/workspace agent-skills  # symlink it into a workspace
```

Because the deploy is a symlink, regenerating updates deployed skills in place. Of the
project-scoped deploy targets, only `agent-skills` defaults `--project-root` to the
current directory; `agents-md`, `codex` and `antigravity` require it.

Each `SKILL.md` carries only `name` (equal to the command basename and parent directory)
and `description` frontmatter. Optional fields such as `license`, `metadata` and
`allowed-tools` are deliberately not emitted.

**The tree is bounded** to the 11 lifecycle commands: `/r-spec`, `/r-plan`, `/r-build`,
`/r-ship`, `/r-start`, `/r-save`, `/r-status`, `/r-env`, `/r-audit`, `/r-refresh` and
`/r-init`. Utility commands stay Claude Code only for now. The source of truth is
`adapters/agent-skills/skill-meta.json`.

## Composites and AGENTS.md

`codex` and `antigravity` are the same composite on both verbs: the `.agents/skills/`
symlink plus `AGENTS.md`. An existing `AGENTS.md` is left alone unless you pass `--force`.

```bash
rdf generate --project-root /path/to/proj antigravity   # optional here
rdf deploy   --project-root /path/to/proj antigravity   # required here
```

The quickest route is at init time, which does both steps:

```bash
rdf init ~/projects/my-app --tools codex
```

`agents-md` is also a standalone target. With `--project-root`, generate composes
`<root>/AGENTS.md` from that repository's own `CLAUDE.md`, falling back to its
`.rdf/governance/index.md` and then a stub, and it refuses a root that is not a git
repository. Without `--project-root`, generate refreshes this checkout's tracked
`adapters/agents-md/output/AGENTS.md`, which `rdf deploy agents-md` copies into a project
root. `rdf generate` accepts its flags and target in any order.

## Model and effort routing

This applies to Claude Code only. `adapters/claude-code/agent-meta.json` pins `model` and
`effort` per agent, and emits effort variants because the Agent tool cannot pass effort
per call. See [Agents](agents.md).

Codex and Antigravity CLI emit no agents today, so routing there stays with your session
settings.

## Gemini CLI legacy tier

Gemini CLI stopped serving free, Pro and Ultra tiers on 2026-06-18. Enterprise and
paid-API users are unaffected, and the open source repository stays active. RDF keeps the
adapter frozen for those users, with one exception: command TOML now uses `'''`-literal
strings, so backslashes in command bodies parse strictly. That also serves migration,
because `agy plugin import gemini` converts `.gemini/commands/*.toml` into Antigravity
skills.

<details markdown="block">
<summary>The {% raw %}{{args}}{% endraw %} limitation</summary>

Gemini CLI command TOML substitutes {% raw %}`{{args}}`{% endraw %}, the whole invocation string, and does not
tokenize positional arguments. RDF emits canonical command bodies verbatim, so a body that
reads `$ARGUMENTS` keeps that literal token. A command invoked as `/r-build 3` receives the
raw `3`, unbound to any placeholder.

RDF adds a NOTE comment to affected commands so a Gemini CLI user knows to pass the argument
through the {% raw %}`{{args}}`{% endraw %} form. This is an accepted limitation of the frozen tier.

</details>

## Deferred surfaces

These ship only after a live probe confirms a stable schema:

- Antigravity hooks (`<workspace>/.agents/hooks.json`): the schema is undocumented
- Antigravity subagents (markdown): the schema is actively changing
- Antigravity plugins (`~/.gemini/antigravity-cli/plugins/<name>/plugin.json`)
- Codex `agents/openai.yaml` per-skill metadata
- User-level `~/.agents/skills/` scanning: unverified
- Optional `SKILL.md` fields (`license`, `metadata`, `allowed-tools`)
- Per-agent effort for Codex and Antigravity CLI, since neither adapter emits agents yet

MCP server work is a standing non-goal. Design record:
[scale and reach spec](https://github.com/rfxn/rdf/blob/main/docs/specs/2026-07-15-scale-reach-design.md).
