---
title: Agents
parent: Reference
nav_order: 4
description: "RDF's seven universal agents and two effort variants: roles, models, tool access and how work is routed between them."
---

# Agents
{: .no_toc }

RDF uses seven universal agents, plus two variants that differ only in effort. Their
behavior comes from each project's governance files, not from domain knowledge baked
into prompts. A QA agent reviewing a bash firewall and one reviewing a Python
pipeline follow different rules because their governance differs.

1. TOC
{:toc}

## Roster

| Agent | Model · effort | Role | Access |
|-------|----------------|------|--------|
| `rdf-planner` | fable · high | Design specs and implementation plans. `/r-spec` and `/r-plan` run this protocol inline; direct dispatch also works | Read and write |
| `rdf-dispatcher` | opus · high | Orchestrate plan phases and TDD cycles | Read and write |
| `rdf-engineer` | opus · xhigh | Implement through the governance protocol | Read and write |
| `rdf-engineer-focused` | opus · medium | Variant for `scope:docs` and `scope:focused` phases. Failures escalate to `rdf-engineer` | Read and write |
| `rdf-qa` | opus · medium | Verification gate | Read and execute |
| `rdf-reviewer` | opus · xhigh | Adversarial sentinel review | Read and execute |
| `rdf-reviewer-challenge` | opus · high | Variant for pre-implementation challenge review | Read and execute |
| `rdf-uat` | opus · medium | User acceptance from an end-user persona | Read and execute |
| `rdf-claims` | opus · high | Fresh-context check of text before it is posted: PR bodies, commit messages, changelogs, issue and chat drafts (direct dispatch) | Read and execute; Edit disallowed, and its prompt limits writes to its report, evidence and scratch |

## Why agents stay narrow

Agents are context buffers, not general-purpose helpers. A QA agent loaded with only
the diff, the test results and the verification protocol catches issues that an agent
carrying the whole session would miss.

## Routing

Routing lives in [`adapters/claude-code/agent-meta.json`](https://github.com/rfxn/rdf/blob/main/adapters/claude-code/agent-meta.json),
which sets `model`, `effort` and `variants`. Variants generate from the base agent's
canonical body. The Agent tool cannot pass effort per call, so each effort level is its
own agent.

| To change | Do this |
|-----------|---------|
| Effort for one session | Use `/effort`, which saves a level per model |
| Effort for every agent | Set `CLAUDE_CODE_EFFORT_LEVEL` |
| The planner's model | Set its `"model"` in `agent-meta.json` and regenerate |

Spec and plan sessions are tuned for `claude --model fable --effort high`, and builds
for `claude --model opus`. No Fable access? Set the planner's `"model"` to `"opus"` and
run `rdf generate claude-code`.

`/r-util-claudemd-review` deliberately fans out to Sonnet for bulk transcript reading.

## More detail

[WORKFORCE.md](https://github.com/rfxn/rdf/blob/main/WORKFORCE.md) has the organization
chart, per-agent notes and common workflows.
