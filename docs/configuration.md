---
title: Configuration
parent: Reference
nav_order: 3
description: "Configure RDF: the files it creates in your project, how convention inheritance works, environment variables and the /r-env host assessment."
---

# Configuration
{: .no_toc }

Most projects need no configuration beyond `rdf init` and `/r-init`. Your rules
live in plain files you can edit.

1. TOC
{:toc}

## Project files

| Path | Written by | Purpose |
|------|-----------|---------|
| `CLAUDE.md` | `rdf init` | Project working instructions, merged from your stack's profiles. Excluded from commits by default |
| `MEMORY.md` | `rdf init` | Placeholder for session-persistent project facts |
| `.rdf/governance/reference/` | `rdf init` | Reference docs from matching profiles |
| `.rdf/governance/index.md` | `/r-init` | Project identity, loaded first by agents |
| `.rdf/governance/architecture.md` | `/r-init` | How the project is laid out |
| `.rdf/governance/conventions.md` | `/r-init` | How code is written here |
| `.rdf/governance/verification.md` | `/r-init` | Lint and test commands that QA runs |
| `.rdf/governance/constraints.md` | `/r-init` | Hard limits, which also raise a phase's gate scope |
| `.rdf/governance/anti-patterns.md` | `/r-init` | Patterns to reject, which can mark paths security-sensitive |
| `.rdf/governance/ignore.md` | `/r-init` | Paths agents should skip |
| `.rdf/work-output/` | Agents | Session state and agent results |
| `.git/info/exclude` | `rdf init` | Keeps working files out of commits |

After the code changes, run `/r-refresh` to update governance. It preserves your
edits. `/r-init --force` deletes `.rdf/governance/`, including the reference docs
`rdf init` copied there, and starts over.

## Convention inheritance

The most specific rule wins:

```text
project CLAUDE.md  >  workspace CLAUDE.md  >  profile defaults  >  core defaults
```

Agents read the chain at session start and apply it in that order.

## Use other AI tools

`rdf init` targets Claude Code by default. Pass `--tools LIST` (comma-separated) to
wire up other surfaces in the target project. An existing `AGENTS.md` is left
untouched, and AGENTS.md composition requires a git repository.

| Value | Adds |
|-------|------|
| `claude-code` | The default; a no-op when combined with others |
| `agent-skills` | Symlinks `.agents/skills` |
| `agents-md` | Composes `AGENTS.md` from the project's own `CLAUDE.md` |
| `codex`, `antigravity` | Both of the above |

See [Multi-tool parity](multi-tool-parity.md).

## Environment variables

Most setups need none of these.

| Variable | Default | Purpose |
|----------|---------|---------|
| `RDF_TARGET` | `~/.claude` | Deploy target for the claude-code adapter |
| `RDF_ACCOUNT` | Unset | Account for `rdf run` and `rdf review` when no `@name` is given. Set by `rdf use`, and overrides `rdf account default`. `RDF_CLAUDE_ACCOUNT` is still read as a fallback |
| `RDF_WORKSPACE` | Parent of the RDF checkout | Workspace root for `rdf doctor --all`. Set it when the checkout sits directly in `$HOME`, because `--all` refuses to scan a home directory |
| `RDF_CLAUDE_PROJECTS` | `$CLAUDE_CONFIG_DIR/projects`, else `~/.claude/projects` | Transcript root for `rdf tokens` |
| `CODEX_HOME` | `~/.codex` | Codex home read by `rdf tokens` |
| `RDF_TOKENS_CACHE` | `~/.rdf/cache/tokens` | `rdf tokens` row cache |
| `RDF_TOKENS_JOBS` | CPU count | Parallel extraction workers |

## Keep deployed files in sync

Generated output is symlinked, so regenerating updates deployed files in place. A
new command also needs `rdf deploy`, because each skill has its own symlink.

```text
canonical edits  -->  rdf generate  -->  deployed (~/.claude/, ~/.gemini/, ...)
deployed edits   <--  rdf sync      <--  emergency path
```

Emergency edits to `~/.claude/` are allowed, but pull them back with `rdf sync`.
`rdf doctor --scope content-drift` detects divergence using per-file `.rdf-hash`
sidecars.

## Check your environment

`/r-env` compares this host with what the project needs and prints exact fixes for
your package manager. It changes nothing on its own, and offers to run the fixes you
pick. It checks:

- A code intelligence plugin and language server for each primary language
  (detected from manifests, ignoring samples, docs and vendored code)
- The tools RDF relies on, the hard fd limit and sandbox dependencies
- Claude Code currency on your update channel
- `.claude` settings and memory files
- The age of the `rdf tokens` price table

`/r-start` shows a one-line brief, and `rdf doctor` runs it offline as its `env`
scope. To silence a finding, add its id to `~/.rdf/env-ignore`.
