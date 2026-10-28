---
name: r-env
description: >
  Use to assess the environment against an optimal Claude Code + RDF setup: code intelligence plugins and language servers, tools, limits, sandbox, Claude Code currency, .claude files and the price table, with exact fix commands.
---

# /rdf:r-env — Environment Assessment

Assess this host against an optimal Claude Code + RDF setup for the current
project: code intelligence plugins and their language servers, the tools RDF
relies on, fd and process limits, sandbox dependencies, Claude Code and Codex
currency, `.claude` settings and memory files, and the age of the `rdf tokens`
price table. Read-only: it reports exact fixes and offers to apply them.

`/rdf:r-start` shows a one-line brief of the same assessment; `rdf doctor` runs it
offline as its `env` scope. This command is the full report.

## Arguments

`$ARGUMENTS` (optional, any order):
- `--pricing`: also compare the `rdf tokens` price table with the vendors'
  live pricing pages (automatic when the table is over 45 days old or a
  pricing finding fires)
- `--offline`: no network: skip the latest-version lookups, `claude doctor`
  and the pricing comparison
- a project path (default: the current directory)

## Protocol

### 1. Run the assessment

Resolve `rdf-env.sh` (first path that exists):
1. `~/.rdf/state/rdf-env.sh`
2. `<rdf-checkout>/state/rdf-env.sh` (dev installs only)

If neither exists, say the helpers are not delivered yet (plugin: restart the
session; checkout: `rdf deploy claude-code`) and stop.

Run it once and parse the JSON. Do NOT re-run individual checks yourself:

```bash
bash ~/.rdf/state/rdf-env.sh --json [--offline] <project>
```

Without `--offline` the helper asks registry.npmjs.org for the current
`@anthropic-ai/claude-code` and `@openai/codex` dist-tags (no identifiers are
sent) and runs `claude doctor`, which can fetch managed settings. The JSON
carries settings knob values, env variable names (never their values) and MCP
server counts only.

### 2. Compare prices (only with `--pricing`, an age over 45 days, or a pricing finding)

1. `bash ~/.rdf/state/rdf-tokens.sh --pricing --json` gives the table, its
   `as_of`, `expires` and `sources`.
2. Fetch the markdown variant of each source page (append `.md`; plain tables,
   about 50 KB and 22 KB): `curl -fsSL "<sources.anthropic>.md"` and
   `curl -fsSL "<sources.openai>.md"`.
3. For every model in both, compare input, output, cache writes (5m and 1h
   for Anthropic, 30m for OpenAI), cache reads, the long-context and fast
   tiers, and promotional end dates. Report each difference as a row: model,
   field, table value, page value. List page models missing from the table
   that this host uses (check `rdf tokens --claude --json` and `--codex --json`
   `unpriced_models`).
4. Never edit the table here. The fix is a change to `_tok_prices` in
   `state/rdf-tokens.sh` with a new `as_of`; offer to make it.

### 3. Render the report

ONE block, under about 60 lines:

```
## Environment — {project} · {tool} · gap {N} · warn {N} · info {N}

| Area | Status | Detail |
|------|--------|--------|
| Code intelligence | {✔ or ✘} | {languages: server + plugin state} |
| Tools | ... | ... |
| Limits | ... | nofile {soft}/{hard} |
| Sandbox | ... | ... |
| Claude Code | ... | {version} ({channel} {latest}) |
| Config & memory | ... | ... |
| Pricing | ... | as of {as_of}{, promo ends {expires}} |
```

Then the findings, gaps first, then warnings, then info. Give each its title,
one line of why, and its fix commands in a `bash` block ready to paste. When
several fixes use this host's package manager, also give one combined command
(for example `sudo dnf install ShellCheck bats`). Mark commands that need
`sudo`.

Then **Optimal setup for this project**, a checklist from the facts: each
primary language with its language server and plugin, the project's tools,
limits, sandbox readiness, Claude Code currency, and accounts that lack a
plugin. Checked means present.

Footer: OS, package manager, Codex version, RAM and free disk, the count of
ignored findings and where the ignore files live (`~/.rdf/env-ignore` for every
project, `<project>/.rdf/env-ignore` for this one; one finding id per line).

When `tool` is not `claude` (Codex, Gemini CLI), code intelligence findings are
skipped by design; say so in the table.

### 4. Offer, never apply

Close by offering the fixes the user picks. Rules:
- Never run `sudo`, a package install or `claude plugin install` without the
  user's explicit go-ahead for that command
- Plugin installs are per account: use the `CLAUDE_CONFIG_DIR=` form the
  finding gives
- Never edit settings files unless asked
- To silence a finding, add its id to an ignore file (offer this; do not do it
  unasked)

## Rules
- One helper call; no extra probes unless the user asks about a specific item
- Never paste raw settings or `.claude.json` content into the report
- Do NOT run tests, builds or installs as part of the assessment
