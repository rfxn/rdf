---
title: Parallel Sessions
parent: Guides
nav_order: 6
description: "Run several Claude Code sessions against one repository without collisions: session-scoped state, a worktree scope guard, dirty-tree checks and rdf peers."
---

# Parallel sessions

Run different milestones in different terminals, or leave partial work in one
session while another ships unrelated changes. RDF keeps them apart.

## How sessions stay separate

Every session has its own `RDF_SESSION_ID`: the Claude Code session id, or a minted
UUIDv7 otherwise. All subagents inherit it, and pipeline progress and phase
handoff files carry it:

```text
.rdf/work-output/
  phase-3-result-<SESSION_ID>.md
  vpe-progress-<SESSION_ID>.md
  build-progress-<SESSION_ID>.md
  sentinel-N-<SESSION_ID>.md
```

{: .tip }
`claude --resume <id>` keeps the session id. To resume into a second concurrent
terminal, add `--fork-session` (or `--fs` with `rdf run`).

## Three layers of protection

| Layer | What it does | Where it lives |
|-------|--------------|----------------|
| Session-scoped state | Suffixes pipeline progress and phase handoff files with the session id | `state/rdf-bus.sh` |
| Worktree boundary | A pre-commit hook rejects out-of-scope commits on every `rdf/phase-*` branch | `state/git-hooks/pre-commit` |
| Pre-aggregation gate | The engineer checks for a dirty tree before build steps | `canonical/agents/engineer.md` |

The scope guard works in any project. It chains your own hooks, so they still run.

## See what other sessions are doing

`rdf peers --here` lists the live Claude Code sessions under this checkout's git
toplevel (from a linked worktree, that worktree only), on any
[account](accounts.md#sessions-on-every-account-see-each-other).
`rdf peers <name>` shows what one of them is doing: its last prompt and reply, the
files it edited most recently, and its RDF progress files. Example output from a
fixture:

```text
name:         api-retries
account:      work
pid:          1584525
session:      0b6f2c1e-4a3d-4e8b-9c71-2f5d8a9e3b10
state:        busy
mode:         bypass
started:      2h ago
cwd:          /home/me/src/api
branch:       fix/retry-backoff
title:        Fix flaky retry backoff test
last prompt:  make the retry backoff test deterministic
last reply:   The backoff test reads the wall clock. I injected a fake clock into the retry loop and the test now passes 200 runs in a row.
recent files:
  /home/me/src/api/retry/backoff_test.go
  /home/me/src/api/retry/backoff.go
rdf progress: -
message it: SendMessage to "api-retries"
```

Before you edit files another session may be working on, check here first. To
coordinate, ask Claude to `SendMessage` to that session's name.

## Allow small test drift

Plan authors can pre-authorize trivial test-infrastructure changes with a
`**Tests-may-touch:**` glob list (plan schema Rule 8). Changes within the list, up
to 30 lines per file in at most 3 files per phase, are not treated as out of scope:

```markdown
**Tests-may-touch:** tests/fixtures/*.json, tests/helpers/*.bash
```

## Build phases in parallel

`/r-build --parallel` runs independent phases at once. Batches at `scope:multi-file`
or below share the working tree, with file ownership checked first.
`scope:cross-cutting` and `scope:sensitive` batches, or any batch with `--worktree`,
get their own worktrees, where each phase commits and then merges linearly.

Design record: [concurrent sessions spec](https://github.com/rfxn/rdf/blob/main/docs/specs/2026-04-25-concurrent-sessions-design.md).
