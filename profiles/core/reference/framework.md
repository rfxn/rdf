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

**Gate selection** is managed by the dispatcher based on planner-assigned
phase tags. The developer does not interact with gate selection directly.

Summary:
- Trivial changes (risk:low) → deterministic checks only (engineer + QA)
- Standard changes → deterministic + adversarial review (+ sentinel)
- User-facing changes → add UAT acceptance testing

The dispatcher auto-scales sentinel depth (2-pass or 4-pass) based on
risk level and change type. See dispatcher.md for the full matrix.
