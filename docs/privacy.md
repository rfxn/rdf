---
title: Privacy Policy
nav_exclude: true
permalink: /privacy
---

# Privacy Policy

*Effective 2026-07-14*

RDF (rfxn Development Framework) is a local development tool. It is
designed to collect nothing.

## What RDF collects

**Nothing.** RDF has no telemetry, no analytics, no account system, and
makes no network calls to R-fx Networks. The only third-party requests are
the version and pricing lookups `/r-env` makes when you run it online
(below). There is no data to sell, share, or breach on our side, because
none leaves your machine.

`rdf tokens` (and the per-session summary `/r-save` records) reads the
Claude Code transcripts already stored on your machine under
`~/.claude/projects/` (with `--codex`, the Codex rollouts under
`~/.codex/sessions/`) and writes its summary to your local
`.rdf/work-output/session-log.jsonl`. It sends nothing anywhere.

`/r-env` (the environment assessment) is the one exception, and only when you
run it without `--offline`: it asks the public npm registry for the current
Claude Code and Codex version numbers (a plain GET with no identifiers), runs
`claude doctor` (which can fetch your organization's managed settings), and
downloads the Anthropic and OpenAI pricing pages when you pass `--pricing`
or when the embedded price table is over 45 days old or a promotional price
in it has ended. `/r-start` and `rdf doctor` run it offline.

## Where your data lives

All state RDF creates stays local to your machine:

- `~/.rdf/`: session logs, insights, and lessons-learned you generate
- `.rdf/` inside your projects: governance files, work output, memory
- `~/.claude/` (or equivalent): deployed adapter content

These files are yours. Deleting them removes everything RDF knows.

## Third-party AI runtimes

RDF is governance content executed *by* an AI runtime you choose (Claude
Code, Codex, Antigravity CLI, and Gemini CLI as a legacy tier). Your
prompts, code, and RDF's governance text
are processed by that runtime under its own privacy policy. For Claude
Code, see [Anthropic's privacy policy](https://www.anthropic.com/legal/privacy).
RDF does not add any data flow beyond what your chosen runtime already
does.

## Optional integrations

Some commands can talk to services **you** configure with **your**
credentials (e.g., GitHub via the `gh` CLI for issues and releases).
Those interactions are between you and that service, under its policy.
RDF never proxies, stores, or observes them remotely.

## Changes

Changes to this policy are made by commit to
[the RDF repository](https://github.com/rfxn/rdf); the git history is
the changelog.

## Contact

Questions: **proj@rfxn.com** · Security reports: see
[SECURITY.md](https://github.com/rfxn/rdf/blob/main/SECURITY.md)
