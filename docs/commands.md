---
title: Slash Commands
parent: Reference
nav_order: 1
description: "Every RDF slash command: session lifecycle, the spec-to-ship pipeline, review and audit, and utilities for Claude Code."
---

# Slash commands
{: .no_toc }

RDF ships 38 commands: 22 lifecycle and 16 utility. Run them inside your agent
session. On a plugin install, add the namespace: `/r-start` becomes `/rdf:r-start`.

*Dispatches* names the [agents](agents.md) a command hands work to.

1. TOC
{:toc}

## Session

| Command | Purpose |
|---------|---------|
| `/r-init` | Scan the project and generate its governance in `.rdf/governance/` |
| `/r-start` | Load project context and show a health dashboard |
| `/r-save` | End a session: sync plan progress, memory and the session log |
| `/r-status` | Show the project health dashboard without changing anything |
| `/r-tasks` | Show task list progress for long-running commands |
| `/r-mode` | Switch the [operational mode](profiles-modes.md#modes) for this session |
| `/r-env` | Assess this host and print exact fixes ([details](configuration.md#check-your-environment)) |
| `/r-refresh` | Re-derive governance from the codebase after it drifts |
| `/r-sync` | Pull emergency edits from the deployed location back to canonical |
| `/r-context-audit` | Measure context overhead, with a score and drift detection |

## Pipeline

| Command | Dispatches | Purpose |
|---------|-----------|---------|
| `/r-spec` | reviewer | Design: discover, brainstorm, write a spec, challenge review |
| `/r-plan` | reviewer | Plan: decompose a spec into phases, challenge review |
| `/r-build [N\|--parallel]` | dispatcher, qa | Execute plan phases with TDD and quality gates |
| `/r-ship` | qa, reviewer | Release: preflight, verify, prep, publish, report |
| `/r-vpe` | none | Run the whole pipeline from one outcome-oriented request |

## Review and audit

| Command | Dispatches | Purpose |
|---------|-----------|---------|
| `/r-verify` | qa | QA verification against a diff or scope |
| `/r-test` | uat | User acceptance testing from an end-user persona |
| `/r-review` | reviewer | Adversarial review in challenge or sentinel mode |
| `/r-review-answer` | none | Route review findings to fix, rebut or defer, with an audit trail |
| `/r-verify-claim` | none | Verify one falsifiable claim about the codebase (5 claim classes) |
| `/r-audit` | reviewer, qa | Full codebase audit across all domains |
| `/r-audit-slop` | engineer, reviewer | Find AI slop: dead code, orphan helpers, no-op functions |

## Utilities

| Command | Purpose |
|---------|---------|
| `/r-util-mem-compact` | Archive stale `MEMORY.md` entries |
| `/r-util-mem-audit` | Fact-check `MEMORY.md` against live state |
| `/r-util-claudemd-review` | Find `CLAUDE.md` improvements and prose drift from recent conversations |
| `/r-util-chg-gen` | Generate changelog entries from a diff or commit range |
| `/r-util-chg-dedup` | Deduplicate changelog entries |
| `/r-util-rel-squash` | Plan and execute a release branch squash |
| `/r-util-doc-gen` | Generate publication-ready documentation |
| `/r-util-ci-gen` | Generate a GitHub Actions CI workflow |
| `/r-util-lib-sync` | Detect drift in shared libraries across projects |
| `/r-util-lib-release` | Run a shared library release |
| `/r-util-proj-cross` | Analyze convention drift across projects |
| `/r-util-code-scan` | Find bugs by pattern class |
| `/r-util-code-map` | Print a structural map of a large source file |
| `/r-util-code-modernize` | Assess modernization maturity and plan remediation |
| `/r-util-test-dedup` | Find duplicate and overlapping tests |
| `/r-util-test-scope` | Recommend which tests to run for a diff |
