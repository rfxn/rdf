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

| Phase Tags | Gates |
|-----------|-------|
| risk:low, type:config | Gate 1 (self-report) |
| risk:medium, type:feature | Gates 1 + 2 (+ QA) |
| risk:high, type:security | Gates 1 + 2 + 3 (+ reviewer) |
| type:user-facing | Gates 1 + 2 + 4 (+ UAT) |
| risk:high, type:user-facing | All 4 gates |
