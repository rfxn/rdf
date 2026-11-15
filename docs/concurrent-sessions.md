---
title: Parallel Sessions
parent: Guides
nav_order: 6
description: "Run several Claude Code sessions against one repository without collisions: session-scoped state, a worktree scope guard and dirty-tree checks."
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
