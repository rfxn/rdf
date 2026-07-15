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
makes no network calls to R-fx Networks or any third party. There is no
data to sell, share, or breach on our side, because none leaves your
machine.

## Where your data lives

All state RDF creates stays local to your machine:

- `~/.rdf/` — session logs, insights, and lessons-learned you generate
- `.rdf/` inside your projects — governance files, work output, memory
- `~/.claude/` (or equivalent) — deployed adapter content

These files are yours. Deleting them removes everything RDF knows.

## Third-party AI runtimes

RDF is governance content executed *by* an AI runtime you choose (Claude
Code, Gemini CLI, Codex). Your prompts, code, and RDF's governance text
are processed by that runtime under its own privacy policy — for Claude
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
[the RDF repository](https://github.com/rfxn/rdf) — the git history is
the changelog.

## Contact

Questions: **proj@rfxn.com** · Security reports: see
[SECURITY.md](https://github.com/rfxn/rdf/blob/main/SECURITY.md)
