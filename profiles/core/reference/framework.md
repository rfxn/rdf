# RDF Framework Reference

> Reference doc for core profile. Copied to
> .claude/governance/reference/ during /r:init.

## Governance File Taxonomy

| File | Purpose | Budget |
|------|---------|--------|
| index.md | Always-loaded pointer to all governance files | ~50 lines |
| architecture.md | Component map, data flow, key boundaries | varies |
| conventions.md | Coding patterns, naming, style | varies |
| verification.md | Which checks to run, how to run them | varies |
| constraints.md | Platform targets, compat, version floors | varies |
| anti-patterns.md | Project-specific pitfalls to avoid | varies |

## Agent Primitives

| Agent | Role | Context |
|-------|------|---------|
| Planner | Spec + plan via research-driven dialogue | Main context (interactive) |
| Dispatcher | Plan execution, TDD cycles, quality gates | Subagent (foreground) |
| Engineer | TDD implementation in any domain | Subagent (dispatched) |
| QA | Read-only verification against governance | Subagent (dispatched) |
| UAT | End-user acceptance testing | Subagent (dispatched) |
| Reviewer | Adversarial review (challenge + sentinel) | Subagent (dispatched) |

## Quality Gate Progression

**Verification depth** is managed by the dispatcher. It classifies each
phase by change scope, derived automatically from the file list,
description, and governance context:

  docs          -- changelog, README, comments
  focused       -- single file, config, one function
  multi-file    -- 2+ files, standard feature/refactor work
  cross-cutting -- install, CLI, cross-OS, breaking changes
  sensitive     -- security, shared libs, data migration

Higher scope = more verification. The dispatcher manages this
automatically. See dispatcher.md for the full derivation logic.
