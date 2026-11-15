---
title: Launchers and Accounts
parent: Guides
nav_order: 5
description: "Launch Claude Code and Codex with rdf run, choose permission and sandbox modes, and run work and personal accounts against the same projects and memory."
---

# Launchers and accounts
{: .no_toc }

`rdf run` launches Claude Code or Codex in a named mode, for a chosen account.
`rdf account` lets several logins share one set of projects, auto memory and
`--resume` history.

1. TOC
{:toc}

## Common tasks

| I want to | Run |
|-----------|-----|
| Launch Claude Code | `rdf c` (short for `rdf run claude`) |
| Launch Codex | `rdf x` (short for `rdf run codex`) |
| Skip permission prompts | `rdf c -y` |
| Keep prompts but run in the tool's sandbox | `rdf c --sandbox` |
| Resume on another account | `rdf c @personal -y --resume` |
| Fork a session | `rdf c --fs --resume` |
| Run a read-only Codex review | `rdf review --effort high "Review HEAD~1..HEAD for regressions"` |

Every argument RDF does not recognize goes straight to the tool.

## Launch modes

| Mode | Claude Code | Codex |
|------|-------------|-------|
| `-y`, `--yolo` | `--dangerously-skip-permissions` (refused as root) | `--dangerously-bypass-approvals-and-sandbox` |
| `--root` | `--yolo` plus `IS_SANDBOX=1` | Not accepted |
| `--sandbox` | The tool's sandbox, permission checks kept | `--sandbox workspace-write --ask-for-approval on-request` |

{: .warning }
`--root` tells Claude Code it is already sandboxed so it will skip permissions as
root. It isolates nothing, so use it only on a host you can afford to lose.
`--yolo` on Codex also removes Codex's sandbox.

`--sandbox` on Claude Code runs shell commands without prompts, but they can write
only the working directory and temp, reach only hosts you allow, and cannot ask to
leave the sandbox. File edits in the working directory are auto-accepted, and
anything else asks. Linux needs `bubblewrap` and `socat`.

`--sandbox` does not combine with `--yolo` or `--root`, and it refuses tool flags
that would undo it (`--settings`, `--permission-mode`, `-s`, `-a` and the bypass
flags).

## Codex reviews

`rdf review` runs `codex exec` with a read-only sandbox and closes stdin for a text
prompt, so a backgrounded run never waits on it.

```bash
rdf review --effort high -o /tmp/r.md "Review HEAD~1..HEAD for regressions"
rdf review -f prompt.md -C ~/src/app     # long prompts go through stdin
```

| Option | Effect |
|--------|--------|
| `--effort LEVEL` | Reasoning effort (`low`, `medium`, `high`, `xhigh`) |
| `-m MODEL` | Model, defaulting to your Codex config |
| `-o FILE` | Write the final message to a file |
| `-C DIR` | Working directory for the run |
| `-f FILE`, `-` | Read the prompt from a file or stdin |
| `--write` | Use a workspace-write sandbox instead |

## Shell integration

Add this as the last line of `~/.bashrc` or `~/.zshrc`:

```bash
eval "$(rdf shell init)"
```

You get `rdf use` for per-shell accounts, plus tab completion for subcommands,
options and `@accounts` (zsh needs `compinit`).

## Set up several accounts

`rdf account` runs several Claude Code accounts against one set of projects, auto
memory, `--resume` history and config. The account logged in to `~/.claude` is the
primary.

```bash
rdf account add work --primary   # name the login ~/.claude already holds
rdf account add personal         # create ~/.claude-personal (and ~/.codex-personal if ~/.codex exists)
rdf run claude @personal         # first launch asks you to log in
rdf run codex @personal          # with ~/.codex-personal, Codex asks for its login too
rdf account list                 # logins and link health; * = active
```

### Choose an account

RDF takes the first of these that is set:

| Order | Source | Scope |
|-------|--------|-------|
| 1 | `@name` on the command line | One run |
| 2 | `rdf use <name>` (sets `RDF_ACCOUNT`) | This shell. `rdf use -` clears it, and `rdf use` alone lists accounts |
| 3 | `rdf account default <name>` | Every launch. `rdf account default -` clears it |
| 4 | None | The environment stays as it is |

These `@` names pass through to the tool: `@agent-…`, names with uppercase or other
characters an account cannot use, and paths that exist in the current directory
(unless registered as an account). Any other unregistered `@name` stops with an error.

### What is shared

| | Claude Code | Codex |
|---|-------------|-------|
| **Per account** | Login, `.claude.json` (project trust, user MCP servers, onboarding), plugins, org-managed settings | `auth.json`, state databases |
| **Shared** | `projects`, `history.jsonl`, `paste-cache`, `file-history`, `tasks`, `todos`, `plans`, `CLAUDE.md`, `settings.json`, `keybindings.json`, `skills`, `agents`, `commands`, `rules`, `output-styles`, and RDF's `scripts`, `governance`, `reference` | `config.toml`, `AGENTS.md`, `history.jsonl`, `prompts`, `rules`, `skills`, `sessions`, `archived_sessions` |

Shared Claude Code state is symlinked back to `~/.claude`, and shared Codex state to
`~/.codex`. Because Codex sessions live in one place, `rdf tokens` reads every
account's rollouts.

### What picking an account does

- **Claude Code:** sets `CLAUDE_CONFIG_DIR` and drops inherited credential and
  provider variables (such as `ANTHROPIC_API_KEY`, `ANTHROPIC_BASE_URL` and
  `CLAUDE_CODE_USE_BEDROCK`), so that account's login is used against Anthropic.
  `rdf run help` lists them all.
- **Codex:** sets `CODEX_HOME` to `~/.codex-<name>` when it exists, otherwise unsets
  it to use `~/.codex`, and drops `CODEX_API_KEY` and `CODEX_ACCESS_TOKEN`.

### Things to know

- Every account can resume any transcript and loads the auto memory of the project
  it opens, so work from one account's org reaches the other account's provider
  terms when you open it there.
- The shared `settings.json` applies to every account, including
  `remote.defaultEnvironmentId` and `enabledPlugins`. Keep `forceLoginOrgUUID`,
  `apiKeyHelper` and credential environment variables out of it.
- `rdf account link` adds links for entries that appear in `~/.claude` later. It
  never replaces a path that already exists in an account directory.
- `rdf run claude @<name> --chrome` picks the CLI account. The Chrome extension
  uses whichever claude.ai account the browser is signed in to.

### Change the primary

`rdf account primary <name>` makes `<name>` the login in `~/.claude`, which is what
plain `claude`, IDE extensions and scripts use. The current primary's login,
`.claude.json`, plugins and org-managed settings move to `~/.claude-<old>`. Shared
state stays where it is, and account names keep working.

```bash
rdf account primary personal --dry-run   # preview the moves
rdf account primary personal
```

Quit every Claude Code session first, because the command refuses while one runs.
It moves Claude Code logins only, and it is Linux only: macOS keeps each login in
the keychain under its config directory path.
