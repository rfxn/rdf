# Platform Triage Ledger

Per-minor re-triage of native Claude Code capabilities against RDF's own
mechanisms: one dated block per minor release, newest first below the
Conventions section. `/r-ship` Stage 1d greps the first dated block for the
target release's `MAJOR.MINOR`; a minor release without a current block is
blocked (patch releases skip the check).
Origin: `docs/specs/2026-09-02-platform-alignment-spike-design.md` §6 (D4).

---

## Conventions

### How to add a block at the next minor

Before the next minor ships, re-run every checklist line of the newest
block against current platform docs (skills.md, agent-teams.md, workflows.md,
plugins-reference, etc.), then insert a new `## <MAJOR.MINOR> (<date>)` block
immediately after this Conventions section, ahead of every dated block, which
becomes history below it. Fill in the same five columns and update or carry
forward the Product rulings. `/r-ship` Stage 1d greps only the *first* dated
block, so the new block must be prepended, not appended.

### Next minor: platform alignment follow-ons

Deferred from the spike's Go/No-Go summary (spike §8):

- **D1: Workflow-backed `/r-build` behind a flag.** Fix the
  `tiers.md` bugfix/`min()` contradiction, define a plan `Status:` form,
  add a `deploy.sh` workflows dir, a `/r-build --workflow` arg (with BATS
  coverage), an A/B run on one real plan, and an indicator-list contract.
- **D2: trigger-eval suite on `claude plugin eval`.** The 3.8 re-triage
  found `claude plugin eval` GA (v2.1.269+), so D2 skips the local harness:
  an `evals/*/case.yaml` suite (37 positive + ~10 negative cases) run by
  `claude plugin eval`, a `/r-ship` 1e line, and an optional CI job.

Rows to add to the next block:

- **`subagentPromptCacheTtl`**: detect and report; never write user settings,
  and recommend 1h only from measurement. Doctor `harness` reports the effective
  TTL and its source as OK, the unset case included (automatic 5m, with a
  pointer to compare `rdf tokens` rebuild cost against cache-write spend).
  Evidence: `prompt-caching.md` "Choose the TTL yourself" gives the order
  (`FORCE_PROMPT_CACHING_5M=1`, the bucket's env var, the bucket's setting,
  subagent `experimental.cacheTtl`, `ENABLE_PROMPT_CACHING_1H=1`, the default)
  and requires v2.1.242+; it says the one-hour TTL "costs more on short bursts
  of work that never idle past five minutes". Probe 2026-10-24: with the
  setting at `"1h"`, a fresh subagent wrote 37,791 tokens at `ephemeral_1h` and
  0 at 5m. RDF's own 30 days would have cost about $25 more at 1h (31.6M
  subagent write tokens at the 1h premium vs ~9M rebuild tokens avoided).
  Trigger: the docs change the order or a bucket's default.

---

## 3.9 (2026-10-22)

Re-run against Claude Code 2.1.308 docs (`workflows.md`, `agent-teams.md`, `skills.md`,
`plugins/components.md` (the former `plugins-reference` slug), `memory.md`,
`plugin-evals.md`, `sub-agents.md`, `model-config.md`, `env-vars.md`, `authentication.md`,
`claude-directory.md`). One row is new: 3.9 ships `rdf account` / `rdf shell init`, which
depend on `CLAUDE_CONFIG_DIR` semantics. Two triggers fired (per-call subagent `effort`;
`CLAUDE_CODE_SESSION_ID` scope); neither changes a 3.9 deliverable.

| Line | Decision rule | Verdict | Evidence | Re-check trigger |
|---|---|---|---|---|
| Workflows | absorb when GA on the user's plan and the RDF mechanism is a loop with no user input | absorb (gated spike, D1, still deferred) | `workflows.md`: "Dynamic workflows are available on all paid plans, with Anthropic API access, and on Amazon Bedrock, Google Cloud's Agent Platform, and Microsoft Foundry. On Pro, turn them on from the Dynamic workflows row in `/config`." | D1's A/B evidence lands |
| Agent Teams | absorb only when non-experimental, `-p` capable, worktree-isolated, nested | **keep dispatcher** (unchanged) | `agent-teams.md`: "Agent teams are experimental and disabled by default."; "In non-interactive mode with the `-p` flag, including Agent SDK sessions, Claude doesn't spawn teammates"; "No nested teams: teammates cannot spawn their own teammates." | experimental flag drops, `-p` support lands, or per-teammate worktree isolation ships |
| Skills frontmatter | absorb keys the CC adapter can emit from `skill-meta.json` | keep; emitted keys still documented (`disable-model-invocation`, `allowed-tools` present); newer keys (`when_to_use`, `disallowed-tools`, `background`, `shell`, `metadata`, `license`, `compatibility`) not adopted | `skills.md` frontmatter reference (20 fields); "Custom commands have been merged into skills." Whether the field list grew since 2.1.280 is unverified (changelog gap 2.1.281–2.1.295) | CC's skill-frontmatter schema changes |
| Plugin components | absorb a component only when an RDF mechanism maps 1:1 | keep; `channels` is new and maps to Relay (separate project), not RDF core | `plugins/components.md`: "A Claude Code plugin is built from components, such as skills, agents, hooks, and MCP servers"; `channels` "lets an outside system such as a chat app send messages into a session"; `workflows/` is the tracked D1 candidate | Relay's next release plans Slack/Telegram steering (evaluate `channels` there) |
| Auto-memory | retire `~/.rdf/lessons-learned.md` only when a native *cross-project* store exists | keep | `memory.md`: "Auto memory is machine-local. All worktrees and subdirectories within the same git repository share one auto memory directory"; path under `CLAUDE_CONFIG_DIR` when set | Anthropic ships a native cross-project memory store |
| `.claude/rules/` + `@import` | verify each minor that `cc_generate_rules` output still loads | keep as-is | `memory.md`: "The `.claude/rules/` directory supports symlinks"; `tests/rules-deploy.bats` green in the 3.9.0 suite (477/477) | `rules-deploy.bats` regresses or CC's `@import` behavior changes |
| Eval availability | switch the trigger-eval runner to `claude plugin eval` when the probe stops printing "early access" | switch still due (3.8 trigger stands); D2 unbuilt. D2's `evals/*/case.yaml` plan must follow the current layout | `plugin-evals.md`: "Claude Code v2.1.269 or later"; "Git 2.31 or later, if git is installed"; `prompt.md` + `graders/*.md` primary, `case.yaml` optional with `schema_version: "1.1"`; local probe on 2.1.308: "No eval cases found" | D2 lands, or the command reports "currently unavailable" |
| Hazard `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS` | a named subagent launches as a teammate when the flag is set | document "unset with RDF" (hazard stated more strongly) | `agent-teams.md`: "while agent teams are enabled, a subagent that Claude names launches as a teammate, so teams can form even when you didn't ask for one"; skipped when the Agent call "passes `isolation` on the call itself" | RDF intentionally wants Agent Teams semantics for a named subagent |
| Subagent `model` / `effort` | absorb per-agent routing when the adapter can emit it from `agent-meta.json` | absorbed (3.8). **Trigger fired**: the Agent tool takes a per-call `effort` (v2.1.292+); variants kept this minor (ruling 4) | `sub-agents.md`: "it can also pass an `effort` parameter for that invocation ... requires Claude Code v2.1.292 or later"; the 2.1.308 Agent tool schema says to set it "ONLY when the user, or instructions such as CLAUDE.md or a skill, explicitly ask" | spec B evaluates skill-instructed per-call `effort` as a replacement for variants |
| Opus 5.5 effort default | detect and advise; never write user settings | doctor `harness` scope WARNs | `model-config.md`: "a top-level `effortLevel` in your user settings file doesn't count for Opus 5.5"; new: "A top-level `effortLevel` in project, local, or managed settings, or one passed with `--settings`, applies to every model." | the default or the precedence changes; doctor coverage of the project/local/`--settings` forms unverified |
| `omitClaudeMd` | absorb for agents that take everything from the dispatch payload, once measured | defer to context-economy spec B | `sub-agents.md`: "Set to `true` to start this subagent without the user, project, and local CLAUDE.md files"; "Requires Claude Code v2.1.271 or later" | spec B lands |
| `CLAUDE_CODE_SESSION_ID` | key session-scoped state on the harness session id; mint only outside Claude Code | absorbed (3.8). **Trigger fired** (scope widened); no RDF impact: RDF ships no MCP servers | `env-vars.md`: "Set automatically to the current session ID in Bash and PowerShell tool subprocesses, hook command subprocesses, and stdio MCP server subprocesses." | RDF ships an MCP server, or the variable's semantics change |
| Multi-account via `CLAUDE_CONFIG_DIR` (new) | absorb a native account switcher if one exists; else keep `rdf account` within the documented mechanism | **keep `rdf account`** (absorbed this release): no native claude.ai switcher; per-account config dirs are the documented pattern | `authentication.md`: "give each account its own configuration directory"; "Separate directories don't keep two Claude Console sign-ins without an API key apart"; `env-vars.md` `CLAUDE_CONFIG_DIR`: "Useful for running multiple accounts side by side"; `claude-directory.md`: "every `~/.claude` path on this page lives under that directory instead"; precedence: `ANTHROPIC_AUTH_TOKEN`, `ANTHROPIC_API_KEY`, `apiKeyHelper`, `CLAUDE_CODE_OAUTH_TOKEN`, `ANTHROPIC_PROFILE` all outrank `/login` (launchers drop the env forms; README keeps `apiKeyHelper` out of shared settings). `.claude.json` placement is undocumented; probe on 2.1.308: `<dir>/.claude.json` with the variable set | Claude Code ships native account switching, documents `.claude.json` placement differently, or changes snapshot/credential precedence |

### Product rulings

1. **No dual `/r-build` path this minor**. Carried from 3.7 (D1 still unbuilt).
2. **No `disable-model-invocation` on lifecycle skills**. Carried from 3.7.
3. **D4 gate strength: minor-only blocking**. Carried from 3.7.
4. **Routing lives in `agent-meta.json`, not in dispatch calls**. Carried from 3.8. The
   per-call `effort` parameter is set only on explicit instruction, so effort that differs
   by mode stays a variant agent until spec B measures skill-instructed per-call effort.
5. **Multiple accounts use documented `CLAUDE_CONFIG_DIR` dirs, never token injection
   into one dir**. This keeps Remote Control and connectors per account and org-managed
   settings out of other accounts (3.9).

---

## 3.8 (2026-09-24)

Re-run against Claude Code 2.1.280 docs (`workflows.md`, `agent-teams.md`,
`skills.md`, `plugins-reference`, `memory.md`, `plugin-evals.md`, `sub-agents.md`,
`model-config.md`, `env-vars.md`). Four rows are new this minor because 3.8
routes model/effort per agent and keys session state on the harness session id.

| Line | Decision rule | Verdict | Evidence | Re-check trigger |
|---|---|---|---|---|
| Workflows | absorb when GA on the user's plan and the RDF mechanism is a loop with no user input | absorb (gated spike, D1, still deferred) | `workflows.md`: "available on all paid plans, with Anthropic API access, and on Amazon Bedrock, Google Cloud's Agent Platform, and Microsoft Foundry" (unchanged) | D1's A/B evidence lands |
| Agent Teams | absorb only when non-experimental, `-p` capable, worktree-isolated, nested | **keep dispatcher** (3.7 first case stands) | `agent-teams.md`: still experimental and off by default; "In non-interactive mode with the `-p` flag ... Claude doesn't spawn teammates"; "teammates cannot spawn their own teammates" | experimental flag drops, `-p` support lands, or per-teammate worktree isolation ships |
| Skills frontmatter | absorb keys the CC adapter can emit from `skill-meta.json` | keep (absorbed in 3.7; no new keys since 2026-09-02). Skill `model`/`effort` last one turn, so Fable for `/r-spec`/`/r-plan` is a session-start advisory, not skill frontmatter | `skills.md` frontmatter reference | CC's skill-frontmatter schema changes |
| Plugin components | absorb a component only when an RDF mechanism maps 1:1 | keep | `plugins-reference`: "Plugin components include skills, agents, hooks, MCP servers, LSP servers, and monitors" (unchanged) | a new plugin component ships with an RDF-equivalent mechanism |
| Auto-memory | retire `~/.rdf/lessons-learned.md` only when a native *cross-project* store exists | keep | `memory.md`: "Auto memory is machine-local. All worktrees and subdirectories within the same git repository share one auto memory directory" | Anthropic ships a native cross-project memory store |
| `.claude/rules/` + `@import` | verify each minor that `cc_generate_rules` output still loads | keep as-is | `memory.md` (no behavior change); `tests/rules-deploy.bats` green | `rules-deploy.bats` regresses or CC's `@import` behavior changes |
| Eval availability | switch the trigger-eval runner to `claude plugin eval` when the probe stops printing "early access" | **trigger fired**: `claude plugin eval` is GA (v2.1.269+); D2 is re-scoped to a `claude plugin eval` suite, no local harness (not built this release) | `plugin-evals.md`: requires "v2.1.269 or later"; the early-access message means "Your build predates general availability"; `claude plugin eval --help` on 2.1.280 has no early-access wording | D2 lands, or the command reports "currently unavailable" (switched off server-side) |
| Hazard `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS` | a named subagent launches as a teammate when the flag is set | document "unset with RDF" | `agent-teams.md` (unchanged) | RDF intentionally wants Agent Teams semantics for a named subagent |
| Subagent `model` / `effort` (new) | absorb per-agent routing when the adapter can emit it from `agent-meta.json` | **absorbed this release**: `model`/`effort` per agent plus effort variants (`rdf-engineer-focused`, `rdf-reviewer-challenge`), since the Agent tool takes a per-call `model` but no `effort` | `sub-agents.md`: `effort` "Overrides the session effort level. Default: inherits from session"; `model-config.md`: frontmatter effort overrides "the session level but not the environment variable" | the Agent tool gains a per-call `effort` (variants become unnecessary) |
| Opus 5.5 effort default (new) | detect and advise; never write user settings | doctor `harness` scope WARNs | `model-config.md`: Opus 5.5 defaults to `medium`; "a top-level `effortLevel` in your user settings file doesn't count for Opus 5.5" | the default or the precedence changes |
| `omitClaudeMd` (new) | absorb for agents that take everything from the dispatch payload, once measured | defer to context-economy spec B | `sub-agents.md`: skips user, project, and local CLAUDE.md; managed policy still loads; v2.1.271+ | spec B lands |
| `CLAUDE_CODE_SESSION_ID` (new) | key session-scoped state on the harness session id; mint only outside Claude Code | **absorbed this release** (`rdf_session_init`) | `env-vars.md`: "Set automatically to the current session ID in Bash and PowerShell tool subprocesses, hook command subprocesses"; matches the hook `session_id`; updated on `/clear`; `--resume <id>` keeps it, `--continue` may get the startup ID | the variable's scope or semantics change |

### Product rulings

1. **No dual `/r-build` path this minor**. Carried from 3.7 (D1 still unbuilt).
2. **No `disable-model-invocation` on lifecycle skills**. Carried from 3.7.
3. **D4 gate strength: minor-only blocking**. Carried from 3.7.
4. **Routing lives in `agent-meta.json`, not in dispatch calls.** Canonical text
   dispatches by agent name; no per-call `model:` override (3.8). Effort that
   differs by mode is a variant agent, not a parameter.

---

## 3.7 (2026-09-02)

| Line | Decision rule | Verdict | Evidence | Re-check trigger |
|---|---|---|---|---|
| Workflows | absorb when GA on the user's plan and the RDF mechanism is a loop with no user input | absorb (gated spike, D1, deferred to next minor) | `workflows.md` GA; spike §3 | D1's A/B evidence lands (see follow-ons below) |
| Agent Teams | absorb only when non-experimental, `-p` capable, worktree-isolated, nested | **keep dispatcher** (first case, below) | `agent-teams.md`; `agent-teams-research.md:118-126` | experimental flag drops, `-p` support lands, or per-teammate worktree isolation ships |
| Skills frontmatter | absorb `skills/<name>/SKILL.md` + `disable-model-invocation` on side-effect commands + `allowed-tools` when the CC adapter can emit them from `skill-meta.json` | absorbed this release (sibling spec `2026-09-02-skills-native-adapter-consolidation-design.md`, Phases 1-6) | `skills.md` "Custom commands have been merged into skills" | CC's skill-frontmatter schema changes |
| Plugin components | absorb a component only when an RDF mechanism maps 1:1 | keep (only Workflows is a 1:1 candidate, tracked as D1) | `plugins-reference` component table | a new plugin component ships with an RDF-equivalent mechanism (MCP/LSP/monitors/output-styles currently have none) |
| Auto-memory | retire `~/.rdf/lessons-learned.md` only when a native *cross-project* store exists | keep | no native cross-project store found (spike §6) | Anthropic ships a native cross-project memory store |
| `.claude/rules/` + `@import` | already absorbed (3.4.0 `--rules`); verify each minor that `cc_generate_rules` output still loads | keep as-is | `adapters/claude-code/adapter.sh:96,140`, `tests/rules-deploy.bats` | any minor where `rules-deploy.bats` regresses or CC's `@import` behavior changes |
| Eval availability | switch the trigger-eval runner to `claude plugin eval` when the probe stops printing "early access" | local harness (D2, deferred to next minor) | spike §2 probe | `claude plugin eval` output drops "early access" |
| Hazard `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS` | a named subagent launches as a teammate when the flag is set, forming a team even when not asked | document "unset with RDF" | `agent-teams.md` | RDF ships a named-subagent workflow that intentionally wants Agent Teams semantics (none today) |

### First case: Agent Teams vs dispatcher

**Verdict: keep the dispatcher; do not absorb.**

1. "Agent teams are experimental and disabled by default" (`agent-teams.md`
   Warning); not enabled in this environment (spike §2).
2. "Spawning teammates also requires an interactive session. In
   non-interactive mode with the `-p` flag ... Claude doesn't spawn
   teammates": no headless/CI path; RDF's D2 harness and `/r-build` resume
   both need `-p`.
3. Shared working tree: "Two teammates editing the same file leads to
   overwrites" and worktrees are offered only as manual sessions "without
   automated team coordination"; RDF's parallel path is worktree-isolated
   with a pre-commit scope hook (`r-build.md:232-253,273`,
   `state/git-hooks/pre-commit`, `plan-schema.md` Rule 8).
4. Gate machinery is hook-only (`TeammateIdle`/`TaskCreated`/`TaskCompleted`
   exit 2), with no engineer→QA→reviewer chain, no evidence grammar, no
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
   artifact until A/B evidence exists; see D1 in the follow-ons below.
2. **No `disable-model-invocation` on lifecycle skills.** Measured usage
   shows the pipeline model-invokes `/r-build` 43×, `/r-plan` 75×, `/r-spec`
   53×, `/r-ship` 5×, `/r-save` 25× (controller usage mining 2026-09-02:
   Skill-tool invocations across 10,453 Claude Code transcripts on the
   maintainer's machine, not in the repo). Flagging them `disable-model-invocation`
   would remove them from Claude's own suggestions, which is accepted as an AST03
   risk (over-privileged skills, see spike §7) for now; revisit alongside
   `allowed-tools` scoping.
3. **D4 gate strength: minor-only blocking.** `/r-ship` Stage 1d blocks a
   `x.y.0` release without a current top block; patch releases (`x.y.z`,
   `z>0`) skip the check unconditionally.
