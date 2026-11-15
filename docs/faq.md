---
title: FAQ
nav_order: 5
description: "Common questions about RDF: how it compares with CLAUDE.md and spec-driven tools, context cost, privacy, what gets committed, troubleshooting and uninstall."
---

# FAQ and troubleshooting
{: .no_toc }

1. TOC
{:toc}

## About RDF

### What is RDF?

RDF (rfxn Development Framework) is a governance layer for AI coding agents. It keeps
your project's conventions in files the agent reads, adds a spec-to-ship pipeline, and
has separate agents review the work. It is unrelated to the W3C Resource Description
Framework.

### Who is it for?

Anyone whose code matters enough to review, whether that is a solo maintainer or a team
shipping to production. It came from maintaining security tooling, but
[profiles](profiles-modes.md) cover Python, Go, Rust, TypeScript, Node, PHP, Perl,
frontend, databases and infrastructure.

### How is this different from a CLAUDE.md?

A `CLAUDE.md` is one file you write and maintain. RDF generates one from your stack's
profiles, then adds what a single file cannot do: governance derived from your actual
code, a reviewer that challenges plans before implementation, gates that demand evidence,
and a doctor that detects drift.

### How does it compare with Spec Kit, BMAD or Superpowers?

They share the spec-first idea. RDF's focus is governance generated per repository,
adversarial gates sized to each change's scope and risk, a CLI for project health and
token spend, and one source deployed to several AI tools. If you want only a spec
template and a task list, a lighter tool may suit you better.

### Which AI tools does it support?

Claude Code, Codex and Antigravity CLI are first-class. Any tool that reads `AGENTS.md`
gets the documentation surface, and Gemini CLI is a frozen legacy tier. Claude Code has
all 38 commands, while Codex and Antigravity get the 11 lifecycle commands. See
[Multi-tool parity](multi-tool-parity.md).

### Is it worth it on a small project?

Often, yes, because the ceremony scales. `/r-plan --bugfix` writes a short failing-test-first
plan and keeps gates minimal, and you can skip the pipeline and run `/r-verify` or `/r-review`
on any diff. See [Pick a tier](pipeline.md#pick-a-tier).

### Will it bloat my context?

The default deploy adds ~0.1K always-loaded tokens per session. Your scaffolded `CLAUDE.md`
costs more (about 3K tokens on the Quickstart's Flask app), and skill and agent descriptions
add about 1.6K by the same estimate. Governance files load on demand. See
[Token usage](token-usage.md#what-rdf-adds-to-every-session).

### Does RDF send my code anywhere?

RDF has no telemetry and no RDF-hosted accounts, and it makes no network calls to R-fx Networks. Your
code goes only to the AI tool you already use, under that tool's terms. See the
[privacy policy](privacy.md) for the version and pricing lookups `/r-env` can make.

### What gets committed to my repository?

`rdf init` adds `CLAUDE.md`, `PLAN*.md`, `AUDIT.md`, `MEMORY.md`, `.rdf/` and `.agents/`
to `.git/info/exclude`, so they stay local. Specs in `docs/specs/` and plans in
`docs/plans/` are normal files meant to be committed, and `SECURITY.md` and
`CONTRIBUTING.md` are yours to keep or delete.

### What is the difference between `rdf init` and `/r-init`?

`rdf init` runs in your shell with no model calls. It writes `CLAUDE.md`, reference docs
and the `.rdf/` layout. `/r-init` runs in your agent session, scans your code and writes
the project governance. Use both, in that order. Plugin installs have no CLI, so they use
`/rdf:r-init` alone.

## Troubleshooting

### `rdf: command not found`

The checkout is not on your `PATH`. Link it:

```bash
mkdir -p ~/.local/bin && ln -s ~/rdf/bin/rdf ~/.local/bin/rdf
```

Make sure `~/.local/bin` is on your `PATH`, or use `bin/rdf` from the checkout.

### `manual merge required: hooks.json`

This is expected on a symlink deploy and does not affect the exit status. RDF does not
edit your `settings.json`. Follow [the merge step](quickstart.md#option-a-from-source-recommended)
to turn on hooks and the status line.

### `/r-start` shows no governance

Run `/r-init` in the project. `rdf init` only scaffolds; `/r-init` writes the governance
files.

### `/r-init` says governance already exists

Run `/r-refresh` to update it, which preserves your edits. `/r-init --force` deletes
`.rdf/governance/` and regenerates from scratch, which also removes the reference docs
`rdf init` copied there.

### A plugin command reports missing helpers

A SessionStart hook installs the `~/.rdf/state/` helpers. Restart Claude Code once after
installing or updating the plugin.

### The status line is blank

Hooks and the status line need `jq` on your `PATH`, and the symlink deploy needs the hooks
merge. See the [status line reference](context-bar.md).

### `rdf doctor` shows WARNs

WARNs are advisory, and a fresh install usually has a few. Only FAIL findings set a
non-zero exit. Run `rdf doctor --quiet` to see just WARN and FAIL rows.

### `rdf doctor --all` refuses to run

Your checkout sits directly in `$HOME`, and `--all` will not scan a home directory. Point
it at your projects with `RDF_WORKSPACE=~/projects rdf doctor --all`.

## Update and uninstall

### How do I update?

**From source:**

```bash
cd ~/rdf && git pull && bin/rdf generate claude-code && bin/rdf deploy claude-code
```

**Plugin:** update it from `/plugin`, then restart Claude Code.

### How do I uninstall?

**Plugin:**

```text
/plugin uninstall rdf@rdf
```

**From source**, remove the symlinks and RDF's state:

```bash
rm ~/.claude/skills/r-* ~/.claude/skills/reference
rm ~/.claude/agents ~/.claude/scripts ~/.claude/reference ~/.claude/governance
rm -rf ~/.rdf
```

If you merged hooks, remove the `hooks` entries and `statusLine` that point at
`~/.claude/scripts/` from `~/.claude/settings.json`.

**From a project**, delete `.rdf/`, `CLAUDE.md` and `MEMORY.md`, then remove the
`RDF working files` block from `.git/info/exclude`.

## Still stuck?

Search [discussions](https://github.com/rfxn/rdf/discussions) or
[open an issue](https://github.com/rfxn/rdf/issues/new/choose). Support is best-effort and
community-driven.
