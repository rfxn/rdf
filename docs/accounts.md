---
title: Launchers and Accounts
parent: Guides
nav_order: 5
description: "Launch Claude Code and Codex with rdf run, choose permission and sandbox modes, run work and personal accounts against the same projects and memory, and let sessions on every account find each other."
---

# Launchers and accounts
{: .no_toc }

`rdf run` launches Claude Code or Codex in a named mode, for a chosen account.
`rdf account` lets several logins share one set of projects, auto memory and
`--resume` history. `rdf peers` shows the live Claude Code sessions on every
account.

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
| See every live Claude Code session | `rdf peers` |
| Message a session on another account | Ask Claude to `SendMessage` to its name |

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
| **Shared** | `projects`, `history.jsonl`, `paste-cache`, `file-history`, `tasks`, `todos`, `plans`, `CLAUDE.md`, `settings.json`, `keybindings.json`, `skills`, `agents`, `commands`, `rules`, `output-styles`, `sessions` (the live-session registry), and RDF's `scripts`, `governance`, `reference` | `config.toml`, `AGENTS.md`, `history.jsonl`, `prompts`, `rules`, `skills`, `sessions`, `archived_sessions` |

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
  never replaces a path that already exists in an account directory, except
  `sessions`, which it merges into `~/.claude/sessions` (see
  [Sessions on every account](#sessions-on-every-account-see-each-other)). It
  re-links an account's existing Codex home but never creates one, because a new
  home has no Codex login; `mkdir ~/.codex-<name>` and re-run `link` to add one.
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
It also refuses while `<name>` has its own `sessions` directory; run
`rdf account link <name>` to merge it. It moves Claude Code logins only, and it is
Linux only: macOS keeps each login in the keychain under its config directory path.

## Sessions on every account see each other

Claude Code sessions can message each other with the built-in `ListAgents` and
`SendMessage` tools. Each session finds peers in its config directory's
`sessions/`, Claude Code's registry of live sessions, so on its own it sees only
its own account. RDF shares that directory like the rest of the shared state.

- `rdf account add` links the new account's `sessions` to `~/.claude/sessions`,
  and creates `~/.claude/sessions` (mode 700) when it is missing.
- `rdf account link` moves the files in an account's own `sessions` directory into
  `~/.claude/sessions`, then replaces the directory with a link.
- If a file of the same name is already in the shared directory, or the account's
  directory holds a symlink, `link` names each one and leaves that account's
  directory as it is. Resolve them and re-run. A session that starts during the
  move also leaves the directory in place; re-run `rdf account link`.

A session that was already running lists the other accounts' sessions once
`rdf account link` has run, without a restart. If one does not, restart it.

### Message a session

In a Claude Code session, ask Claude to list the other sessions or to message one
by name. It uses `ListAgents` and `SendMessage`, and the reply comes back to the
sender. Get the names from `rdf peers`.

### See every session

`rdf peers` lists the live Claude Code sessions on this machine, on every account,
and what each one is working on. It only reads: each account's session registry
and `.claude.json` account ids, the transcripts under `projects/`, RDF progress
files and Claude Code's socket directory. Example output from a fixture with two
accounts:

```text
  NAME          ACCOUNT  STATE MODE        AGE PROJECT BRANCH            TITLE
  docs-pass     personal busy  acceptEdits 14m site    main              Rewrite the install guide
* release-check work     idle  default     41m api     release/2.4       Check release notes against the diff
  api-retries   work     busy  bypass      2h  api     fix/retry-backoff Fix flaky retry backoff test
```

`*` marks the session you ran it from. `rdf peers <name>` prints one session's
card, `--here` keeps sessions in this repository, and `--json` prints JSON. See
[Parallel sessions](concurrent-sessions.md#see-what-other-sessions-are-doing) for
the card, and the [CLI reference](cli.md#sessions) for flags.

`rdf peers` reads every account's registry directly, so it lists a session even
when that account is not linked yet. `ListAgents` does not. When an account's
`sessions` is not a link to `~/.claude/sessions`, `rdf peers` without `--json` or
a name also prints this line on stderr:

```text
peer messaging across accounts is off for: personal (run: rdf account link)
```

### Held messages

Claude Code decides whether a peer message reaches the receiving session. The
`crossSessionInbound` setting in `settings.json` takes `accept`, `hold` or
`refuse`. When it is unset, a message from a session in a different permission
mode class, such as a bypass session writing to one that prompts, is held for the
receiver's user to review. A headless session has no one to review it, so a held
message expires there.

The tradeoff: `accept` drops the review, so any of your sessions on this machine,
on any account and in any mode, can put text in front of the receiver, and a
bypass receiver acts on it without a prompt. `hold` keeps a person in the loop at
the cost of an approval per message. The shared `settings.json` applies to every
account. A repository's settings or your organization's managed settings can set
`hold`, and your own `accept` does not override them.

### Data across orgs

A message carries text from the sender's conversation into the receiver's. When
the two accounts belong to different orgs, that text leaves one org's account and
is processed under the other's. It is the same direction as resuming a work
transcript on a personal account.

### Scope and limits

- One machine and one OS user. Every account's message sockets live in one
  per-user directory, which is what lets an account reach another account's
  session.
- Claude Code only. Codex sessions are not covered, and `rdf peers` does not list
  them.
- The registry layout (`sessions/<pid>.json`, one socket per session) is an
  internal Claude Code detail and can change in any release. If it moves, sessions
  on different accounts stop finding each other.

`rdf peers` is the tripwire for that last case. When it finds live Claude Code
sockets that no registry entry claims, it prints this line on stderr, again only
without `--json` or a name:

```text
1 live Claude Code sockets have no registry entry; Claude Code may have changed its session layout
```
