---
title: Token Usage and Context Cost
parent: Guides
nav_order: 3
description: "Measure Claude Code and Codex token spend from local transcripts with rdf tokens, and see exactly what RDF adds to every session."
---

# Token usage and context cost
{: .no_toc }

Two questions, answered from data on your machine: what does RDF add to a
session, and what are your sessions costing you?

1. TOC
{:toc}

## What RDF adds to every session

The default deploy adds ~0.1K always-loaded tokens per session: the lessons
index injected at session start, capped at 400 bytes. Governance is read on
demand, so it costs nothing until an agent needs it, and `hooks.json` is runtime
config that never enters model context.

| Deploy | Always-loaded overhead | Install |
|--------|------------------------|---------|
| Default | ~0.1K tokens (lessons index only) | `rdf deploy claude-code` |
| Scoped rules | ~2.2K tokens (adds the unscoped core rule) | `rdf deploy --rules claude-code` |
| `rdf-lite` | ~0.6K tokens (condensed core governance), ~0.7K if hooks are merged | `rdf generate --lite --deploy claude-code` |

These figures count only the lessons index and rules. They exclude your project's
`CLAUDE.md`, which
`rdf init` scaffolds (about 3K tokens on the Quickstart's Flask app), and the skill and
agent descriptions (about 1.6K tokens by the same estimate).

`rdf-lite` ships six lifecycle commands (`/r-spec`, `/r-plan`, `/r-build`, `/r-ship`,
`/r-start`, `/r-save`) and no hooks, so you can ignore the `hooks.json` merge notice its
deploy prints. Scoped language rules load only when a matching file is read, so they add
nothing to these figures.

Figures are a `bytes/4` estimate from `state/rdf-overhead.sh`, and a test fails CI if the
published default drifts too far from the measurement.

To audit your own setup, including skills and memory, run `/r-context-audit`.
It scores the overhead and tracks drift from a baseline.

## See what your sessions cost

`rdf tokens` reads the Claude Code transcripts and Codex rollouts already on
your machine. With no options, it reports the current project for the last 30
days, across both tools.

| Question | Command |
|----------|---------|
| What did this project spend lately? | `rdf tokens` |
| What about the last week? | `rdf tokens --days 7` |
| Since a given date? | `rdf tokens --since 2026-10-01` |
| Across all my projects? | `rdf tokens --all` |
| How does spend trend? | `rdf tokens --by week` (or `day`, `month`) |
| Which sessions cost the most? | `rdf tokens --by session --top 20` |
| Which projects cost the most? | `rdf tokens --by project` |
| What did one session cost? | `rdf tokens --session <id>` |
| One tool only? | `rdf tokens --claude` or `--codex` |
| Which prices are you using? | `rdf tokens --pricing` |
| Can I script this? | `rdf tokens --json` |

`/r-save` records a per-session summary, and `/r-start` shows it.

The Claude Code report breaks spend down by cost class, model, agent, context
depth, subagent boot cost, cache rebuilds and effort. The Codex report adds model
and Fast or Standard tier, review versus write, subagent runs and the account's
plan quota peak per reset window.

## How the numbers are counted

<details markdown="block">
<summary>Deduplication and scope</summary>

- Claude Code logs one API turn once per content block, so usage is deduplicated
  by message id.
- Claude Code counts sessions started in the project directory.
- Codex counts rollouts whose working directory is the project, below it, or one
  of the project's Claude Code scratchpads. Its plan quota peak is account-wide.
- A turn copied into a fork or resumed transcript counts once toward cache
  rebuilds. `--session` on a resumed or forked session still includes the
  history it copied from its parent.

</details>

<details markdown="block">
<summary>What a cache rebuild is</summary>

A cache rebuild is a turn that came after the prompt cache expired and rewrote at
least half of a context of 50K+ tokens. "Expired" means an idle gap over 5
minutes, or over 1 hour when the turn's 1h-TTL writes exceed its 5m writes.

Its cost is the write price minus what reading those tokens would have cost. Main
and subagent transcripts are reported separately, and a transcript's first turn
never counts.

</details>

<details markdown="block">
<summary>Prices and caching</summary>

Prices are list prices copied from the Anthropic and OpenAI pricing pages, applied
as API-equivalent estimates. Subscription plans bill differently. `--pricing`
prints the table with its date and sources.

Rows are cached per transcript and rollout under `~/.rdf/cache/tokens/`, and a
file is re-extracted when its modification time changes. The cache holds usage
metadata, never message content, and is safe to delete. `--no-cache` skips it.

</details>

Nothing is sent anywhere. See the [privacy policy](privacy.md).
