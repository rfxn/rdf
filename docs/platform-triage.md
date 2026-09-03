# Platform Triage Ledger

Per-minor re-triage of native Claude Code capabilities against RDF's own
mechanisms — one dated block per minor release, newest first. `/r-ship`
Stage 1d greps the top block for the release's `MAJOR.MINOR`; a minor
release without a current block is blocked (patch releases skip the check).
Origin: `docs/specs/2026-09-02-platform-alignment-spike-design.md` §6 (D4).

---

## 3.7 — 2026-09-02

| Line | Decision rule | Verdict | Evidence | Re-check trigger |
|---|---|---|---|---|
| Workflows | absorb when GA on the user's plan and the RDF mechanism is a loop with no user input | absorb (gated spike, D1 — deferred to next minor) | `workflows.md` GA; spike §3 | D1's A/B evidence lands (see follow-ons below) |
| Agent Teams | absorb only when non-experimental, `-p` capable, worktree-isolated, nested | **keep dispatcher** (first case, below) | `agent-teams.md`; `agent-teams-research.md:118-126` | experimental flag drops, `-p` support lands, or per-teammate worktree isolation ships |
| Skills frontmatter | absorb `skills/<name>/SKILL.md` + `disable-model-invocation` on side-effect commands + `allowed-tools` when the CC adapter can emit them from `skill-meta.json` | absorbed this release (sibling spec `2026-09-02-skills-native-adapter-consolidation-design.md`, Phases 1-6) | `skills.md` "Custom commands have been merged into skills" | CC's skill-frontmatter schema changes |
| Plugin components | absorb a component only when an RDF mechanism maps 1:1 | keep (only Workflows is a 1:1 candidate, tracked as D1) | `plugins-reference` component table | a new plugin component ships with an RDF-equivalent mechanism (MCP/LSP/monitors/output-styles currently have none) |
| Auto-memory | retire `~/.rdf/lessons-learned.md` only when a native *cross-project* store exists | keep | no native cross-project store found (spike §6) | Anthropic ships a native cross-project memory store |
| `.claude/rules/` + `@import` | already absorbed (3.4.0 `--rules`) — verify each minor that `cc_generate_rules` output still loads | keep as-is | `adapters/claude-code/adapter.sh:276-277`, `tests/rules-deploy.bats` | any minor where `rules-deploy.bats` regresses or CC's `@import` behavior changes |
| Eval availability | switch the trigger-eval runner to `claude plugin eval` when the probe stops printing "early access" | local harness (D2 — deferred to next minor) | spike §2 probe | `claude plugin eval` output drops "early access" |
| Hazard `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS` | a named subagent launches as a teammate when the flag is set, forming a team even when not asked | document "unset with RDF" | `agent-teams.md` | RDF ships a named-subagent workflow that intentionally wants Agent Teams semantics (none today) |

### First case — Agent Teams vs dispatcher

**Verdict: keep the dispatcher; do not absorb.**

1. "Agent teams are experimental and disabled by default" (`agent-teams.md`
   Warning); not enabled in this environment (spike §2).
2. "Spawning teammates also requires an interactive session. In
   non-interactive mode with the `-p` flag ... Claude doesn't spawn
   teammates" — no headless/CI path; RDF's D2 harness and `/r-build` resume
   both need `-p`.
3. Shared working tree: "Two teammates editing the same file leads to
   overwrites" and worktrees are offered only as manual sessions "without
   automated team coordination"; RDF's parallel path is worktree-isolated
   with a pre-commit scope hook (`r-build.md:232-253,273`,
   `state/git-hooks/pre-commit`, `plan-schema.md` Rule 8).
4. Gate machinery is hook-only (`TeammateIdle`/`TaskCreated`/`TaskCompleted`
   exit 2) — no engineer→QA→reviewer chain, no evidence grammar, no
   finding-resolution routing (`dispatcher.md:457-536`).
5. "No nested teams" and "Lead is fixed" contradict `/r-build` → dispatcher
   → engineer nesting (`r-build.md:204-208`).
6. "Task status can lag" is the exact failure the dispatcher's status files
   exist to prevent.

Re-check triggers: the experimental flag drops, `-p` support lands, or
per-teammate worktree isolation ships.

### Product rulings

1. **No dual `/r-build` path this minor.** The Workflow prototype
   (`docs/specs/support/rdf-build-workflow.prototype.js`) stays an unwired
   artifact until A/B evidence exists — see D1 in the follow-ons below.
2. **No `disable-model-invocation` on lifecycle skills.** Measured usage
   shows the pipeline model-invokes `/r-build` 43×, `/r-plan` 75×, `/r-spec`
   53×, `/r-ship` 5×, `/r-save` 25×. Flagging them `disable-model-invocation`
   would remove them from Claude's own suggestions — accepted as an AST03
   risk (over-privileged skills, see spike §7) for now; revisit alongside
   `allowed-tools` scoping.
3. **D4 gate strength: minor-only blocking.** `/r-ship` Stage 1d blocks a
   `x.y.0` release without a current top block; patch releases (`x.y.z`,
   `z>0`) skip the check unconditionally.

## Next minor — platform alignment follow-ons

Deferred from the spike's Go/No-Go summary (spike §8):

- **D1 — Workflow-backed `/r-build` behind a flag.** Fix the
  `tiers.md` bugfix/`min()` contradiction, define a plan `Status:` form,
  add a `deploy.sh` workflows dir, a `/r-build --workflow` arg (with BATS
  coverage), an A/B run on one real plan, and an indicator-list contract.
- **D2 — local trigger-eval harness.** `state/rdf-trigger-eval.sh` reading
  `evals/*/case.yaml` (37 positive + ~10 negative cases), a `/r-ship` 1e
  line, and an optional CI job — then switch to `claude plugin eval` once
  it exits early access (see the Eval availability row above).

## How to add a block at the next minor

Before the next minor ships, re-run the eight checklist lines above against
current platform docs (skills.md, agent-teams.md, workflows.md,
plugins-reference, etc.), prepend a new `## <MAJOR.MINOR> — <date>` block
(newest first, this block becomes history below it), fill in the same five
columns, and update or carry forward the Product rulings. `/r-ship` Stage 1d
greps only the *top* block, so the new block must be prepended, not
appended.
