---
title: Quickstart
nav_order: 1
description: "Add RDF to any repo in five minutes: install, scaffold your project, generate governance and start your first Claude Code session."
---

# Quickstart: add RDF to your repo in 5 minutes
{: .no_toc }

By the end, your AI coding agent has governance written for your project and
the commands to take a change from spec to release. No rfxn context required.
The examples use Claude Code. [Codex and Antigravity CLI](#using-codex-or-antigravity-cli)
differ in one flag.

1. TOC
{:toc}

## Before you start

| You need | Notes |
|----------|-------|
| `git` | Your project should be a git repository |
| `bash` 3.2+ | macOS system bash works and is tested in CI |
| `jq` | Hooks and the status line need it (`apt install jq`, `brew install jq`) |
| An AI coding tool | Claude Code, Codex or Antigravity CLI |

## Step 1: Install RDF

Do this once per machine. Pick one option.

### Option A: from source (recommended)

This gives you the full toolset, including the `rdf` CLI, and bare `/r-*`
commands.

```bash
git clone https://github.com/rfxn/rdf.git ~/rdf && cd ~/rdf
bin/rdf generate claude-code    # build the adapter output
bin/rdf deploy claude-code      # symlink it into ~/.claude/
```

Put `rdf` on your `PATH`. The rest of this page assumes you did:

```bash
mkdir -p ~/.local/bin && ln -s ~/rdf/bin/rdf ~/.local/bin/rdf
```

Deploy prints `manual merge required: hooks.json` just before its summary line.
That step is yours because hooks change what your agent executes, so RDF leaves
`settings.json` alone. Merge them once to turn on pre-commit checks, post-edit
lint, compaction snapshots, the session journal and the status line. Run this
from `~/rdf`:

```bash
s=~/.claude/settings.json; [ -f "$s" ] || { command mkdir -p ~/.claude && echo '{}' > "$s"; }
t=$(mktemp) && jq -s '.[0] * .[1]' "$s" adapters/claude-code/hooks/hooks.json > "$t" && command cp "$t" "$s" && command rm -f "$t"
```

{: .warning }
The merge replaces arrays. If you already define hooks for the same events,
merge those by hand.

Verify the install:

```bash
rdf doctor    # expect 0 FAIL; WARNs are normal on a fresh install
```

### Option B: Claude Code plugin

In Claude Code:

```text
/plugin marketplace add rfxn/rdf
/plugin install rdf@rdf
```

Restart Claude Code once. Hooks register themselves, and a SessionStart hook
installs the `~/.rdf/state/` helpers; 11 state-backed commands run degraded
until that first restart ([details](multi-tool-parity.md#claude-code-plugin-or-symlink-deploy)).

Plugin commands are namespaced, so `/r-start` becomes `/rdf:r-start`. This
path has no `rdf` CLI, so skip Step 2 and start at Step 3 with `/rdf:r-init`.

## Step 2: Scaffold your project

Point `rdf init` at an existing project directory (it stops with `directory not
found` otherwise). It detects your stack and writes the starting files, with no
model calls:

```bash
rdf init ~/projects/my-app
```

Real output from a two-file Flask app:

```text
rdf: auto-detected profiles: python
rdf: initializing: my-app (profiles=python, version=0.1.0)
rdf:   created CLAUDE.md (profiles=python, sections=18)
rdf:   added 6 entries to .git/info/exclude
rdf:   created .rdf/{governance,work-output,memory,scopes}
rdf:   created .rdf/docs-level (floor)
rdf:   copied reference docs from 2 profile(s)
rdf:   created SECURITY.md
rdf:   created CONTRIBUTING.md
rdf:   created MEMORY.md placeholder
rdf: init complete: my-app
```

| Created | Purpose | Committed? |
|---------|---------|------------|
| `CLAUDE.md` | Conventions the agent follows, merged from your stack's profiles | No, excluded by default |
| `.rdf/governance/reference/` | Domain reference docs from matching profiles | No |
| `.rdf/memory/`, `.rdf/work-output/` | Session state and agent output | No |
| `MEMORY.md` | Placeholder for session-persistent project facts | No |
| `SECURITY.md`, `CONTRIBUTING.md` | Community-health starters to edit | Your choice |

Force a stack with `--type rust,infrastructure`, or preview everything with
`--dry-run`.

## Step 3: Generate governance

Open your project in Claude Code and run:

```text
/r-init
```

The agent reads your existing conventions, scans the code and tooling, and
writes project-specific governance. Without this step, agents have the
`CLAUDE.md` conventions but no project index to read. Trimmed output from the
same Flask app:

```text
Python 100%, 2 tracked files | 4 files ingested, 7 generated | 9 HIGH / 0 MED / 3 LOW

Governance (7 files in .rdf/governance/):
  index.md  architecture.md  conventions.md  verification.md
  constraints.md  anti-patterns.md  ignore.md

Review: 3 low-confidence items
Ready: /r-start to begin | /r-spec to design | /r-plan to plan
```

Read the low-confidence items it lists. Those are the guesses worth correcting.

## Step 4: Start working

```text
/r-start
```

You get a dashboard of version, branch, plan progress, in-flight work and
warnings. From there, four commands carry a change to release:

```text
/r-spec     design: research and brainstorm, then a spec with adversarial review
/r-plan     decompose the spec into a phased plan
/r-build    execute phases with TDD and quality gates
/r-ship     preflight, verify, release
```

Small change? `/r-plan --bugfix` writes a short plan whose first phase lands a
failing test, and keeps the ceremony minimal. You can also skip the pipeline: run `/r-verify` for a QA
pass or `/r-review` for an adversarial review of any diff.

## Step 5: Keep it healthy

```bash
rdf doctor ~/projects/my-app    # convention drift, stale state, sync health
```

To update RDF later:

```bash
cd ~/rdf && git pull && bin/rdf generate claude-code && bin/rdf deploy claude-code
```

## Using Codex or Antigravity CLI

Pass `--tools` at Step 2, then use the tool as usual:

```bash
rdf init ~/projects/my-app --tools codex        # or: --tools antigravity
```

This adds `.agents/skills/` with the 11 lifecycle commands and composes
`AGENTS.md` from your project's `CLAUDE.md`. See
[Multi-Tool Parity](multi-tool-parity.md) for what each tool supports.

## Where next

| Goal | Read |
|------|------|
| See a real change go from spec to ship | [Demo walkthrough](demo-walkthrough.md) |
| Understand gates and pick a tier | [Pipeline and quality gates](pipeline.md) |
| Look up a command | [Slash commands](commands.md) · [CLI](cli.md) |
| See what your sessions cost | [Token usage](token-usage.md) |
| Run work and personal accounts | [Launchers and accounts](accounts.md) |
| Fix something | [FAQ and troubleshooting](faq.md) |

Something broke in the first five minutes? That's a bug:
[open an issue](https://github.com/rfxn/rdf/issues/new/choose).
