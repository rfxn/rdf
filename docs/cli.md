---
title: CLI
parent: Reference
nav_order: 2
description: "Reference for the rdf command line: generate, deploy, init, doctor, tokens, run, account and more, with options and exit codes."
---

# CLI reference
{: .no_toc }

Run `rdf <command> help` for full options on any command. If `rdf` is not on your
`PATH`, use `bin/rdf` from your checkout or see the
[Quickstart](quickstart.md#option-a-from-source-recommended).

1. TOC
{:toc}

## Set up

| Command | What it does |
|---------|--------------|
| `rdf generate <target>` | Build tool-specific files from canonical sources |
| `rdf deploy <target>` | Deploy generated output to its destination |
| `rdf init <path>` | Scaffold a project: `CLAUDE.md`, `.rdf/`, profile reference docs |
| `rdf profile list\|install\|remove\|status` | Manage active profiles, resolving dependencies |
| `rdf migrate [path]` | Move a project from `.claude/` and `work-output/` to `.rdf/` |

**Targets** for `generate`: `claude-code`, `claude-plugin`, `codex`, `antigravity`,
`agent-skills`, `agents-md`, `gemini-cli` (legacy), `all`.

**Targets** for `deploy`: `claude-code`, `gemini-cli`, `codex`, `antigravity`,
`agent-skills`, `agents-md`. All but the first two take `--project-root`.

| `rdf deploy` option | Effect |
|---------------------|--------|
| `--dry-run` | Show what would happen |
| `--force` | Back up real directories and files, then replace them with symlinks |
| `--rules` | Also symlink scoped governance rules (claude-code) |
| `--lite` | Symlink rules as governance. For the six-command [`rdf-lite`](token-usage.md#what-rdf-adds-to-every-session) set, run `rdf generate --lite --deploy claude-code` instead |
| `--project-root DIR` | Target project for `codex`, `antigravity`, `agent-skills`, `agents-md` |

| `rdf init` option | Effect |
|-------------------|--------|
| `--type PROFILES` | Force profiles (comma-separated) instead of auto-detecting |
| `--tools LIST` | Wire up [other tools](configuration.md#use-other-ai-tools) |
| `--version X.Y.Z` | Initial version (default: the `VERSION` file, then a `VERSION=` line in `files/<name>`, or 0.1.0) |
| `--no-memory` | Skip the `MEMORY.md` placeholder |
| `--github` | Create labels and a project board with `gh` |
| `--batch` | Process each non-hidden directory directly under the path |
| `--dry-run` | Show what would be created |

## Check health

| Command | What it does |
|---------|--------------|
| `rdf doctor [path]` | Check project health and convention drift |
| `rdf state [path]` | Print a JSON project snapshot in under a second, with no model calls |
| `rdf refresh [path]` | Update `MEMORY.md`, plans and GitHub state from git (`--scope memory\|plan\|github\|all`) |
| `rdf sync` | Pull emergency edits in `~/.claude/` back to canonical (`--dry-run`) |

`rdf doctor` takes `--all`, `--json`, `--quiet` and `--scope SCOPE`. The 16 scopes:

```text
artifacts  drift  memory  plan  github  sync  install-mode  deps  catalogs
state-helpers  content-drift  doc-stats  readme  doc-truth  harness  env
```

## Launch and accounts

| Command | What it does |
|---------|--------------|
| `rdf run claude\|codex [@account] [mode]` | Launch a tool for an account |
| `rdf c`, `rdf x` | Short for `rdf run claude` and `rdf run codex` |
| `rdf review [@account] PROMPT` | Run a read-only `codex exec` review |
| `rdf use <name>\|-` | Set the account for this shell (needs `rdf shell init`) |
| `rdf account add\|list\|link\|remove\|default\|primary\|dir` | Manage accounts that share projects, memory and config |
| `rdf shell init` | Print the `rdf` shell function and bash and zsh completion |

See [Launchers and accounts](accounts.md).

## Sessions

| Command | What it does |
|---------|--------------|
| `rdf peers [<name>] [--here] [--json]` | Live Claude Code sessions on every account and what each is doing |

| `rdf peers` option | Effect |
|--------------------|--------|
| `<name>` | Card for one session (exact name, else a unique prefix): pid, cwd, last prompt and reply, recent files, RDF progress files |
| `--here` | Only sessions under this checkout's git toplevel (else the current directory); from a linked worktree, that worktree only |
| `--json` | JSON array, or one object with `<name>` |

Table columns: `NAME` (`*` marks this session), `ACCOUNT`, `STATE`, `MODE` (the
session's permission mode, `bypass` for `bypassPermissions`), `AGE`, `PROJECT`,
`BRANCH`, `TITLE`. JSON keys: `name`, `account`, `pid`, `session_id`,
`status`, `mode`, `started_at`, `cwd`, `branch`, `title`, `last_prompt`, `self`;
a card adds `last_reply`, `recent_files` and `rdf_progress`. `rdf peers` only
reads. It exits 1 when `<name>` matches no live session, or more than one, and
lists the candidates.

See [Sessions on every account](accounts.md#sessions-on-every-account-see-each-other).

## Measure

| Command | What it does |
|---------|--------------|
| `rdf tokens` | Report token usage from local Claude Code and Codex data |

See [Token usage](token-usage.md) for recipes.

## GitHub

| Command | What it does |
|---------|--------------|
| `rdf github setup [--repo owner/repo]` | Create labels and a repo project |
| `rdf github sync-labels [--org org]` | Sync the label taxonomy across repos |
| `rdf github ecosystem-init [--org org]` | Create an org-level ecosystem project |
| `rdf github ecosystem-add <owner/repo>` | Add a repo to the ecosystem project |
| `rdf github ecosystem-sync [--org org]` | Sync open issues into the ecosystem project |

## Exit codes

| Code | Meaning |
|------|---------|
| 0 | Success |
| 1 | Failure: unknown command, missing dependency or file, a skipped deploy item, a FAIL from `rdf doctor`, or an `rdf peers <name>` that matches no single live session |
| 2 | Invalid usage from `rdf run`, `rdf c`, `rdf x`, `rdf tokens` or `rdf peers`, or an unknown account name |

`rdf migrate` has its own set: 0 migrated, 1 failed, 2 nothing to migrate, 3 conflict
(both `.claude/governance/` and `.rdf/governance/` exist).
