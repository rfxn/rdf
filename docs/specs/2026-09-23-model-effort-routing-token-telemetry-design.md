# Model & Effort Routing + Token Usage Report — Design Spec

**Date:** 2026-09-23 · **Tier:** full · **Mode:** unattended (decisions and review responses in §12)
**Input:** `docs/specs/2026-09-23-context-economy-model-routing-research.md` (Options 1, 2, 7)
**Baseline:** RDF 3.7.0 @ 55e8473 · Claude Code 2.1.280 · jq 1.7.1 locally (1.5 floor) · 364 BATS tests
**Revision:** r4 — challenge cycles 1–3 addressed (§12); effort precedence probed empirically

## 1. Problem Statement

1. **Routing is split across eight places and has no effort dimension.**
   - `adapters/claude-code/agent-meta.json` sets a model per agent and never
     sets `effort`: planner, engineer, reviewer → `opus`; dispatcher, qa, uat →
     `sonnet`.
   - Canonical prose overrides models at these sites:
     - `canonical/agents/dispatcher.md:264-265`: docs/focused engineer → `sonnet`
     - `dispatcher.md:279-282`: challenge-mode note
     - `canonical/commands/r-spec.md:558`, `r-plan.md:502`, `r-review.md:103`:
       challenge reviewer → `sonnet`
     - `r-sync.md:128`: illustrative only
2. **Opus 5.5 effort trap.**
   - Opus 5.5 (the `opus` alias since CC 2.1.280) defaults to `medium`.
   - A top-level `effortLevel` in *user* settings does not apply to it
     (code.claude.com/docs/en/model-config § Adjust effort level, line 540).
   - Subagents with no `effort:` inherit the session's effort (sub-agents
     frontmatter table).
   - On an install that set effort before 2026-09-22, every RDF agent therefore
     silently runs at `medium`, and nothing in RDF detects it.
3. **No per-call effort.**
   - The Agent tool's per-invocation override carries only `model`
     (`sonnet|opus|haiku|fable`). Effort is definition-level.
   - **Probed 2026-09-23** (headless `claude -p`, `--agents` probe agent with
     `effort: high`):
     - a session at `--effort medium` ran the subagent at `high`: frontmatter
       beats session effort
     - with `CLAUDE_CODE_EFFORT_LEVEL=low`, the same subagent ran at `low`: the
       env var overrides agent frontmatter
4. **No trustworthy token instrument.**
   - `state/rdf-overhead.sh` estimates boot bytes/4. It never reads transcripts.
   - The 2026-09-10 research brief did not dedup and overstated totals ~2.4×.
     Claude Code writes one JSONL entry per content block, each repeating
     `message.id` and `usage`.
   - 60-day measured shape: cache reads 60% / cache writes 25% / output 15% of
     spend. Nothing records per-session cost.
5. **Context-cost setting unmanaged.** This install runs
   `BASH_MAX_OUTPUT_LENGTH=128000` (platform default 30,000). RDF neither sets
   nor inspects it.

## 2. Goals

1. **Routing source.** `agent-meta.json` is the single routing source.
   - All 6 agents declare `model` and `effort` per §4.4.
   - The engineer declares variant `focused`; the reviewer declares variant
     `challenge`.
2. **Emission.** `rdf generate claude-code` and `rdf generate claude-plugin`
   emit an `effort:` line for every agent, plus two variant files carrying the
   base body:
   - `engineer-focused.md` (`name: rdf-engineer-focused`)
   - `reviewer-challenge.md` (`name: rdf-reviewer-challenge`)
3. **Backward compatibility.** Metadata without `effort`/`variants` emits
   byte-identical agent files to 3.7.0. This is proven against a frozen 3.7.0
   metadata fixture.
4. **Validation.** Invalid routing values abort `rdf generate` (exit 1) and make
   `rdf doctor --scope catalogs` report FAIL. Invalid means:
   - an unknown model or effort
   - a malformed variant
   - a variant stem colliding with a canonical agent
5. **Canonical routing text.**
   - Zero `model: "sonnet"` routing directives remain in canonical
     agents/commands.
   - The dispatcher routes docs/focused phases to `rdf-engineer-focused` and
     escalates a failed focused phase to `rdf-engineer`.
   - Challenge reviews dispatch `rdf-reviewer-challenge`.
6. **Fable advisory and handoffs.**
   - `/r-spec` and `/r-plan` carry a non-blocking Claude Code model advisory
     (Fable at `high`).
   - The `/r-spec` handoff says `/r-plan` stays on that session. The `/r-plan`
     handoff names the Opus build session.
   - `/r-plan` remains main-context.
7. **Sync safety.** `rdf sync` never creates a canonical agent (so never a
   variant). The doctor `sync` agent-count check accounts for variants.
8. **`rdf tokens`.** It reports, from a project's Claude Code transcripts using
   bash + jq only:
   - deduplicated usage and list-price cost
   - share by cost class
   - breakdowns by model and by agent type
   - main-thread context median / p90 / >200 K share
   - subagent boot cost
   - effort distribution

   Output is human text or `--json`. On the pinned fixture it reproduces the
   hand-computed figures in §10a exactly.
9. **Session cost.** `/r-save` records a `tokens` summary object (or `null`) in
   its session-log entry. `rdf-state.sh` preserves it in `session_last`.
   `/r-start` shows the session cost on its "Last:" line when present.
10. **`rdf doctor --scope harness` (15th scope).** It WARNs when:
    - the main thread would run Opus 5.5 without a pinned effort
    - `CLAUDE_CODE_EFFORT_LEVEL` is set (it flattens per-agent effort)
    - `BASH_MAX_OUTPUT_LENGTH` > 30000

    Otherwise it reports OK. It never writes settings. `rdf doctor --json` stays
    valid JSON for any message text.
11. **Doc truth.** README, RDF.md, WORKFORCE.md, docs/demo-walkthrough.md,
    docs/multi-tool-parity.md, docs/privacy.md, CHANGELOG and CHANGELOG.RELEASE
    state the new routing and surfaces truthfully. `rdf doctor` reports 0 FAIL.
    The full suite passes.

## 3. Non-Goals

- **Codex and Antigravity effort emission** (`.codex/agents/*.toml`,
  `.agents/agents/*.md`). Neither adapter emits agents today. Documented as
  deferred in multi-tool-parity.
- **Writing any user or project `settings.json`.** Detection and printed fixes
  only.
- **Spec B:** onboarding diet (`omitClaudeMd`, dispatch-by-value) and bounded
  sessions.
- **Effort ladders** beyond the single focused → base escalation.
- **Lean-plan doctrine.**
- **Per-phase cost attribution.**
- **A `/r-ship` token regression line.**
- **Changes to `state/rdf-overhead.sh`** or its published figures.
- **The gemini-cli adapter and its own `agent-meta.json`:** frozen legacy.
- **A `/r-plan` delegation flag.** `/r-plan` stays inline (user decision).
- **`canonical/commands/r-util-claudemd-review.md:64-66` "Parallel Sonnet
  Subagents":** a deliberate exception for bulk read-only transcript analysis
  across general-purpose subagents, not a role in the routing table. Left
  unchanged and noted in README's routing section.
- **Excluding copied history from `--session` on resumed or forked sessions.**
  Copied entries keep `message.id`/`timestamp`/`uuid` but take the new
  `sessionId` (probed), so they are indistinguishable. Documented as a known
  limitation. Window mode dedups across files and is unaffected.

## 4. Architecture

### 4.1 File Map

| File | Status | Est. lines Δ | Purpose |
|------|--------|--------------|---------|
| `adapters/claude-code/agent-meta.json` | modify | +12 | `effort` per agent; `variants` on engineer, reviewer; planner → `fable`; dispatcher/qa/uat → `opus` |
| `lib/rdf_common.sh` | modify | +55 | `rdf_agent_routing_errors`, `rdf_agent_variant_stems`; `rdf_require_agent_meta` runs validation |
| `lib/adapter_common.sh` | modify | +35 | `adp_agent_frontmatter` variant arg + `effort:` line; `adp_emit_agents` emits variants |
| `adapters/claude-code/adapter.sh` | modify | 2 moved | `rdf_require_bin jq` before `rdf_require_agent_meta` (validation needs jq) |
| `lib/cmd/sync.sh` | modify | +6 | agents loop never creates a canonical agent |
| `lib/cmd/doctor.sh` | modify | +110 | `_check_harness`; routing errors in `_check_catalogs`; variant-aware `_check_sync`; JSON escaping in `_results_to_json`; usage/scope lists |
| `state/rdf-tokens.sh` | **new** | ~280 | transcript reader: discovery, window, jq extract/dedup/price/aggregate/render |
| `state/rdf-state.sh` | modify | ~12 | `session_last` keep-list adds `tokens`; prefers the `/r-save` entry over a same-state trailing SessionEnd-hook entry |
| `lib/cmd/tokens.sh` | **new** | ~20 | `rdf tokens` wrapper → `${RDF_STATE_DIR}/rdf-tokens.sh` (help passes through) |
| `bin/rdf` | modify | +2 | `tokens` case + usage line |
| `canonical/agents/dispatcher.md` | modify | ~15 | agent routing replaces model routing; focused-failure escalation |
| `canonical/commands/r-spec.md` | modify | ~12 | `## Model` advisory; challenge → `rdf-reviewer-challenge`; handoff line |
| `canonical/commands/r-plan.md` | modify | ~10 | `## Model` advisory; challenge → `rdf-reviewer-challenge`; handoff line |
| `canonical/commands/r-review.md` | modify | ~6 | challenge → `rdf-reviewer-challenge`, sentinel → `rdf-reviewer` |
| `canonical/commands/r-sync.md` | modify | ~6 | illustrative frontmatter shows `effort:`; variant stems are generated copies — never offered for import |
| `canonical/commands/r-save.md` | modify | ~12 | step 5 `tokens` field + capture snippet |
| `canonical/commands/r-start.md` | modify | 2 | "Last:" line cost segment |
| `adapters/claude-plugin/output/**` | regenerate | +2 files | variants + regenerated bodies (committed; CI drift gate) |
| `.claude-plugin/plugin.json` | regenerate | +2 entries | agents array stamped from the output glob |
| `tests/fixtures/adapter-common/agent-meta-3.7.0.json` | **new** | ~70 | frozen copy of today's `agent-meta.json` (no effort/variants) |
| `tests/adapter-common.bats` | modify | +40 | byte-identity test (and its line-31 regenerate recipe comment) reads the frozen fixture; new live-meta routing test |
| `tests/tokens.bats` | **new** | ~240 | `rdf tokens` behavior + `rdf-state.sh` tokens pass-through and save-then-hook selection |
| `tests/fixtures/tokens/proj/**` | **new** | 6 files | synthetic transcript tree (§10a) |
| `tests/strip.bats` | modify | +40 | routing validation |
| `tests/sync.bats` | modify | +20 | sync never creates canonical agents |
| `tests/doctor.bats` | modify | +90 | harness matrix, catalogs routing, sync count, JSON escaping |
| `tests/deploy.bats` | modify | 1 | state-helper link count derived from `state/*.sh`, not literal 7 |
| `tests/plugin-adapter.bats` | modify | +15 | variants in plugin.json agents array |
| `tests/governance-contracts.bats` | modify | +45 | routing, advisory, handoff, r-save/r-start contracts |
| `tests/Makefile` | modify | +2 | register `tokens.bats` in `test` and `lint` |
| `README.md` | modify | ~30 | roster table + routing note; CLI table (`rdf tokens`, doctor 15 checks incl. doc-truth); "Add an Agent" schema (`effort`, `variants`); token usage section; tree |
| `RDF.md` | modify | ~10 | agent table; tree (`rdf-tokens.sh`, `tokens.sh`) |
| `WORKFORCE.md` | modify | ~20 | diagram model labels; Model Summary |
| `docs/demo-walkthrough.md` | modify | 6 | roster table models |
| `docs/multi-tool-parity.md` | modify | ~8 | routing row / deferred note |
| `docs/privacy.md` | modify | ~4 | `rdf tokens` reads local transcripts only; sends nothing |
| `CHANGELOG`, `CHANGELOG.RELEASE` | modify | ~12 each | Unreleased entries |

**No-touch files:**
- `adapters/gemini-cli/**`
- `state/rdf-overhead.sh`, `tests/overhead.bats`
- `canonical/scripts/session-end-capture.sh` (5 s SessionEnd budget)
- `lib/cmd/deploy.sh`: agents deploy as a directory symlink, and the state
  helpers are globbed
- `canonical/scripts/state-bootstrap.sh`: globs `state/*.sh`
- `adapters/agents-md/adapter.sh`: its roster iterates canonical agents only
- `canonical/agents/*.md` other than `dispatcher.md`
- `canonical/commands/r-util-claudemd-review.md`
- `canonical/commands/r-vpe.md`

### 4.2 Size Comparison

| Metric | Before | After |
|--------|--------|-------|
| Canonical agents | 6 | 6 |
| Emitted CC agent files | 6 | 8 (6 + 2 variants) |
| Agents with explicit `effort` | 0 | 8 |
| `model: "sonnet"` routing directive lines in canonical agents/commands | 6 | 0 |
| `rdf` subcommands | 10 | 11 (`tokens`) |
| Doctor scopes | 14 | 15 (`harness`) |
| State helpers (`state/*.sh`) | 7 | 8 |
| BATS suites / tests | 24 / 364 | 25 / ≥400 |

### 4.3 Dependency Tree

```
bin/rdf
├── lib/rdf_common.sh ── rdf_agent_routing_errors(meta, agents_dir)   [new, jq]
│                     ── rdf_agent_variant_stems(meta)               [new, jq]
│                     └─ rdf_require_agent_meta(meta, dir) ──► rdf_agent_routing_errors
├── lib/cmd/generate.sh
│   ├── adapters/claude-code/adapter.sh   cc_generate_all: rdf_require_bin jq → rdf_require_agent_meta (reordered)
│   │       └─ cc_generate_agents ──► lib/adapter_common.sh adp_emit_agents
│   │                                      └─ adp_agent_frontmatter(meta, agent[, variant])
│   └── adapters/claude-plugin/adapter.sh cpl_generate_all: rdf_require_bin jq → rdf_require_agent_meta (already ordered)
│           ├─ cpl_generate_agents ──► adp_emit_agents
│           └─ cpl_stamp_plugin_version (globs output/agents/*.md — variants included)
├── lib/cmd/sync.sh        (no metadata needed: skips output agents without a canonical file)
├── lib/cmd/doctor.sh
│   ├── _check_catalogs ──► rdf_agent_routing_errors
│   ├── _check_sync     ──► rdf_agent_variant_stems
│   ├── _check_harness  (jq over settings files + env)
│   └── _results_to_json (escapes all string fields)
└── lib/cmd/tokens.sh ──► ${RDF_STATE_DIR}/rdf-tokens.sh (standalone bash + jq)

state/rdf-state.sh  ── session_last keep-list includes "tokens"
~/.rdf/state/rdf-tokens.sh  ◄── existing state/*.sh delivery (deploy symlink loop / state-bootstrap copy)
    ▲
    └── /r-save step 5: bash ~/.rdf/state/rdf-tokens.sh --session "$CLAUDE_CODE_SESSION_ID" --summary
```

### 4.4 Routing Table (the contract)

| Emitted agent | Source | model | effort | Dispatched for |
|---|---|---|---|---|
| `rdf-planner` | planner | `fable` | `high` | direct dispatch only (no canonical command dispatches it; `/r-spec`, `/r-plan` run inline) |
| `rdf-dispatcher` | dispatcher | `opus` | `high` | `/r-build` |
| `rdf-engineer` | engineer | `opus` | `xhigh` | multi-file / cross-cutting / sensitive phases; escalation target |
| `rdf-engineer-focused` | engineer · variant `focused` | `opus` | `medium` | `scope:docs`, `scope:focused` phases |
| `rdf-qa` | qa | `opus` | `medium` | Gate 1 verification, `/r-verify` |
| `rdf-uat` | uat | `opus` | `medium` | Gate 4, `/r-test` |
| `rdf-reviewer` | reviewer | `opus` | `xhigh` | sentinel (Gate 3, end-of-plan), `/r-review sentinel`, `/r-audit`, `/r-audit-slop` |
| `rdf-reviewer-challenge` | reviewer · variant `challenge` | `opus` | `high` | challenge mode from `/r-spec`, `/r-plan`, `/r-review challenge` |
| main thread | user session | `opus` (user) | `xhigh` (user) | doctor `harness` advises; RDF never writes it |
| `/r-spec`, `/r-plan` sessions | user session | `fable` | `high` | advisory + handoff launch line (`claude --model fable --effort high`) |

- **Precedence (probed):** agent `effort:` beats session effort (`--effort`,
  `/effort`, saved `modelSettings`); `CLAUDE_CODE_EFFORT_LEVEL` beats agent
  `effort:`.
- **Why aliases, not IDs:** `opus` → Opus 5.5, `fable` → Fable 5.1
  (model-config § fable alias resolution). A family alias resolves to the main
  conversation's exact model when the main model is in that family (sub-agents
  § Choose a model).

### 4.5 Key Changes

1. **Variant emission.** One canonical body yields N agent files that differ
   only in frontmatter (name, description, model, effort). Since effort is
   definition-level and not settable per call, this is the least machinery that
   gives per-mode effort. The alternatives:
   - one effort per agent: loses two approved table rows
   - omitting `effort`: re-exposes the Opus 5.5 trap
   - a Sonnet model override: the cascade the vendor guidance argues against

   Cost of the choice:
   - agents at different efforts do not share a prompt-cache prefix (cache keys
     include effort)
   - dispatches of custom agents already start cold (5 m TTL), so the loss is
     limited to same-type siblings
   - the two variant descriptions add ~70 tokens to the agent listing
2. **Dispatch by agent name replaces dispatch by model override.** Canonical
   names `rdf-engineer-focused` / `rdf-reviewer-challenge`. No canonical
   routing site passes a per-invocation `model`.
3. **Escalation.** A focused phase whose gate fails re-dispatches its fix cycle
   to `rdf-engineer` (xhigh) within the existing 3-retry loop.
4. **Session-boundary Fable routing.** Skill `model:` lasts one turn (skills §
   frontmatter), and a mid-session model switch rewrites the model-scoped cache.
5. **Token report as a state helper.** `rdf-tokens.sh` mirrors `rdf-state.sh`:
   an executable helper delivered to `~/.rdf/state/`, wrapped by `rdf <cmd>`.
   The wording is "token usage report", never "telemetry" (privacy.md promises
   no telemetry, and nothing is transmitted).

### 4.6 Dependency Rules

- `state/rdf-tokens.sh` is standalone: it sources nothing (plugin installs have
  no checkout). It needs bash ≥ 3.2, jq ≥ 1.5, and POSIX `find`, `xargs`,
  `touch -t`, `mktemp` and `sed`.
- The `lib/rdf_common.sh` routing helpers require jq. Callers guarantee it:
  - generate calls `rdf_require_bin jq` first (claude-code adapter reorder; the plugin adapter already orders jq first at lines 136-137)
  - doctor has an existing jq guard in `_check_catalogs`, and `_check_sync`
    guards with `command -v jq` and WARNs `jq not found — agent count skipped` without it
- `adp_agent_frontmatter` called with 2 args keeps today's exact output when
  the meta entry has no `effort`.
- Canonical stays frontmatter-free. Routing lives only in `agent-meta.json`.
- **Ordering constraints for the plan:**
  - variant emission lands no later than canonical text naming the variants
  - plugin output is regenerated in the same commit as any canonical/meta change
  - the frozen fixture lands with (or before) the `agent-meta.json` change
  - README/RDF.md trees are updated in the same commit as new files (doc-truth
    tree scan)

## 5. File Contents

### 5.1 `adapters/claude-code/agent-meta.json` (modified)

| Key | Current | New |
|---|---|---|
| `planner.model` / `.effort` | `opus` / — | `fable` / `high` |
| `dispatcher.model` / `.effort` | `sonnet` / — | `opus` / `high` |
| `engineer.effort` | — | `xhigh` |
| `engineer.variants` | — | `{"focused": {"effort": "medium", "description": "Implementation engineer for docs/focused-scope plan phases (medium effort). Failures escalate to rdf-engineer."}}` |
| `qa.model` / `.effort` | `sonnet` / — | `opus` / `medium` |
| `uat.model` / `.effort` | `sonnet` / — | `opus` / `medium` |
| `reviewer.effort` | — | `xhigh` |
| `reviewer.variants` | — | `{"challenge": {"effort": "high", "description": "Adversarial reviewer, challenge mode: pre-implementation spec/plan review (high effort). Read-only."}}` |
| `commands` | unchanged | unchanged |

**Variant schema:**
- `variants.<key>` requires `effort`; `model` and `description` are optional
  and inherit from the base.
- Emitted `name`: `<base name>-<key>`. Emitted file: `<agent stem>-<key>.md`.
- `tools` and `disallowedTools` are always inherited.

### 5.2 `lib/rdf_common.sh` (modified)

| Function | Signature | Purpose | Dependencies |
|---|---|---|---|
| `rdf_agent_routing_errors` | `(meta, agents_dir)` | Print one line per violation as `<agent>[.<variant>]: <problem>` (checks below). A missing `model` or `effort` is valid (skipped). rc 0 always; empty stdout means valid | jq |
| `rdf_agent_variant_stems` | `(meta)` | Print `<agentkey>-<variantkey>` per declared variant; empty on none or unparseable | jq |

Checks run on agent-shaped entries only (objects with `.name`):
- `model` present but not in `opus|sonnet|haiku|fable|inherit` and not a
  `claude-` id; a `claude-` id is rejected when it matches
  `*[!a-z0-9.-]*` (so no newline or YAML-breaking char reaches `model:`); bash
  `case`, no jq regex
- `effort` present but not in `low|medium|high|xhigh|max`
- `variants` present but not an object
- a variant key rejected by `case "$k" in ""|[!a-z]*|*[!a-z0-9-]*) error;;`
  (non-empty, starts with a letter, only `[a-z0-9-]`)
- a variant with no `effort`, or with an invalid `effort` or `model`
- a variant whose `<stem>-<key>.md` exists in `agents_dir` (collision)

| Function | Current behavior | New behavior | Lines affected |
|---|---|---|---|
| `rdf_require_agent_meta` | dies listing canonical agents missing from meta | after the missing check, dies with `invalid agent routing in agent-meta.json: <errors joined by '; '>` when `rdf_agent_routing_errors` prints anything | 104-114 |

### 5.3 `lib/adapter_common.sh` (modified)

| Function | Current behavior | New behavior | Lines affected |
|---|---|---|---|
| `adp_agent_frontmatter` | `(meta, agent)` → name, description, tools, disallowedTools, model | `(meta, agent[, variant])`: variant sets name `<name>-<variant>` and overrides description / model / effort when given; emits `effort: X` after `model:` only when the effective effort is non-null | 31-66 |
| `adp_emit_agents` | one file per canonical agent + optional sidecar | after each base file, emits `<stem>-<key>.md` per variant key: variant frontmatter, the same filtered body, and a sidecar hashing the canonical source. Logs `generated N agent files (M variants)` (the M clause only when M > 0) | 73-107 |

### 5.4 `lib/cmd/sync.sh` (modified)

| Function | Current behavior | New behavior | Lines affected |
|---|---|---|---|
| `cmd_sync` agents loop | syncs every `output/agents/*.md` to `canonical/agents/<name>`, creating files that do not exist | when `canonical/agents/<name>` does not exist: `rdf_log "skipping agents/<name>: no canonical agent (generated variant or stray output)"`, count it as skipped (a new `skipped` counter included in the summary line), and `continue`. Needs no jq or metadata | 61-89 |

### 5.5 `lib/cmd/doctor.sh` (modified)

| Function | Current behavior | New behavior | Lines affected |
|---|---|---|---|
| `_doctor_usage` | 14 scopes | adds `harness` | 18-21 |
| `_check_catalogs` | missing/orphan checks | adds one FAIL per `rdf_agent_routing_errors` line (`agent routing: <line>`); else OK `agent routing valid (N agents, M variants)` | 769-815 |
| `_check_sync` | counts canonical vs output agents | with jq: output count excludes stems from `rdf_agent_variant_stems`; OK text `agent count matches (6 + 2 variants)`. Without jq: WARN `jq not found — agent count skipped` | 490-504 |
| `_results_to_json` | prints fields raw — `"`, `\` or control chars in any field yield invalid JSON | escapes each whole result entry once before splitting on `|` (escaping never introduces `|`), and name/path once per project, via `_json_esc`: one `sed 's/[[:cntrl:]]//g; s/\\/\\\\/g; s/"/\\"/g'` fork per string (≈1 fork per check; category/status are code-fixed tokens) | 1458-1477 |
| `_doctor_one` | 14 scopes | `harness) _check_harness "$path"`; included in `""/all`; the `*)` message lists 15 scopes | 1488-1525 |

New functions:

| Function | Signature | Purpose | Dependencies |
|---|---|---|---|
| `_json_esc` | `(string)` | stdout: JSON-safe string body (no quotes added); single `sed` with `[[:cntrl:]]` deletion (POSIX class, GNU+BSD) | sed |
| `_check_harness` | `(path)` | effort-pin, env-flattening and output-limit checks | jq, `_add_result` |

`_check_harness` algorithm:
1. **No jq** → `WARN harness checks skipped (jq not found)`; return.
2. **Settings files**, in precedence order: managed
   (`/etc/claude-code/managed-settings.json`, then
   `/Library/Application Support/ClaudeCode/managed-settings.json`),
   `<path>/.claude/settings.local.json`, `<path>/.claude/settings.json`,
   `${HOME}/.claude/settings.json`. Skip each file that is missing or fails
   `jq -e .`.
3. **Env flattening.** `CLAUDE_CODE_EFFORT_LEVEL` is taken from the process env,
   else from the first file with `.env.CLAUDE_CODE_EFFORT_LEVEL`. Empty and
   `auto` ("use the model default", env-vars doc) count as unset. If set →
   `WARN CLAUDE_CODE_EFFORT_LEVEL=<v> overrides every agent's effort — RDF's
   per-role routing (xhigh/high/medium) is flattened to <v>; unset it and use
   /effort <level>, which saves per model and leaves agent effort intact`.
4. **Main model** is the first non-empty of env `ANTHROPIC_MODEL`, then each
   file's `.model`. It is Opus-5.5-bound when it is empty, `default`, `opus`,
   `opus[1m]`, or matches `claude-opus-5-5*` (bash `case`). `best` is not
   Opus-bound, because it resolves to Fable where available.
5. **Not Opus-5.5-bound** → `OK main model <m> — Opus 5.5 effort check not
   applicable`. The model string is sanitized to `[A-Za-z0-9.[]_-]` before
   display.
6. **Pinned** when any holds:
   - step 3 found the env var
   - a managed, project or local file has a top-level `.effortLevel`
   - any file has a `.modelSettings` key starting with `claude-opus-5-5` that
     carries `.effortLevel`

   A top-level `.effortLevel` in a managed/project/local file pins because, per
   model-config line 540, such a key "applies to every model"; the user-file
   top-level key does not. Pinned → `OK Opus 5.5 main-thread effort pinned
   (<source>)`.
7. **Not pinned** → `WARN Opus 5.5 main thread runs at its 'medium' default —
   run '/effort xhigh' in a session (saves per model) or add modelSettings
   claude-opus-5-5 effortLevel xhigh to ~/.claude/settings.json; RDF agents pin
   their own effort`. The message never recommends the env var. It appends
   `(a top-level effortLevel in ~/.claude/settings.json does not apply to Opus
   5.5)` when that key exists.
8. **Output limit.** The effective limit is the first file's
   `.bashOutputMaxChars` (a setting that makes Claude Code ignore the env var,
   env-vars doc line 186; clamped 4000–128000). If no file sets it, the limit is
   `BASH_MAX_OUTPUT_LENGTH` from env, else the first
   `.env.BASH_MAX_OUTPUT_LENGTH`.
   - Integer > 30000 → `WARN <source>=<n> exceeds the 30000 default — large
     Bash results stay in context for the rest of the session; overflow already
     spills to a file`.
   - Otherwise → `OK Bash output limit at or below platform default`.

### 5.6 `state/rdf-tokens.sh` (new, executable, `set -euo pipefail`)

| Function | Signature | Purpose | Dependencies |
|---|---|---|---|
| `_tok_usage` | `()` | heredoc usage (§7.1); the only copy of the usage text | — |
| `_tok_die` | `(msg[, rc])` | `rdf-tokens: error: msg` to stderr; exit rc (default 1) | — |
| `_tok_slug` | `(dir)` | `printf '%s' "$dir" \| sed 's/[^A-Za-z0-9-]/-/g'` | sed |
| `_tok_resolve_dir` | `(project)` | transcripts dir: `$RDF_CLAUDE_PROJECTS/<slug of logical path>`, falling back to `<slug of cd -P path>`; neither exists → die rc 1 naming both | `_tok_slug` |
| `_tok_window` | `(days, since)` | sets `_TOK_SINCE` (see below) and `_TOK_REF`, a `mktemp` file touched `-t` to since − 1 day (tz margin) for the mtime prefilter | jq, touch, mktemp |
| `_tok_files` | `(tdir, sid)` | NUL-terminated paths (see below) | find |
| `_tok_agent_map` | `(outfile)` | stdin = NUL list of jsonl paths; writes one merged JSON object `{path: agentType}` to `outfile` (`xargs -0 jq -c '{(input_filename): .agentType}'` over existing sibling `*.meta.json`, then `jq -s add`); consumed via `--slurpfile` (never `--argjson` — a 659-file map is ~98 KB and single args cap at 128 KB). Keys are the `.meta.json` paths; a row resolves its label with `$agents[0][(.file | rtrimstr(".jsonl")) + ".meta.json"] // "unknown"` | xargs, jq |
| `_tok_rows` | `()` | stdin = NUL list of jsonl paths; `xargs -0 jq -cR --arg since "$_TOK_SINCE" 'fromjson? \| select(…)'` (row definition below) | xargs, jq |
| `_tok_report` | `(mode)` | `jq -s` over rows with `--slurpfile agents` and `--argjson prices` (small, fixed): dedup (§6.3), price (§6.4), aggregate, render `text`/`json`/`summary` | jq |
| `_tok_prices` | `()` | echo the embedded price JSON (§6.4) | — |
| `main` | `("$@")` | parse and validate args, resolve inputs, run the pipeline. One `mktemp -d` work dir holds `_TOK_REF`, the NUL path list (read twice) and the agent map; a single `trap 'command rm -rf "${_TOK_WORK:-}"' EXIT` cleans it (safe under `set -u` in session mode) | all above |

`_TOK_SINCE` is `YYYY-MM-DDT00:00:00Z` with `--since`. Otherwise it is
`now − days·86400` formatted by `jq -n --argjson e "$e" '$e|todate'`.

`_tok_files` modes:
- **Session:** globs `$RDF_CLAUDE_PROJECTS/*/<sid>.jsonl`, taking the first
  match, then `<dir>/<sid>/subagents/agent-*.jsonl` and
  `<dir>/<sid>/subagents/workflows/*/agent-*.jsonl`.
- **Window:** `find <tdir> -name '*.jsonl' -newer "$_TOK_REF" -print0`,
  restricted to main files and subagent files by path shape.

`_tok_rows` keeps an entry when all of these hold:
- `.type == "assistant"`
- `.message.id` is non-empty and `.message.usage` is an object
- `.message.model != "<synthetic>"`
- `(.timestamp // "") >= $since` (plain string comparison; empty `$since` in
  session mode)

Each kept entry becomes one compact row with these sources:
- `id` ← `.message.id`; `ts` ← `.timestamp`; `file` ← `input_filename`;
  `sid` ← `.sessionId`; `model` ← `.message.model`
- `eff` ← `.effort // .perTurnEffort // "unset"`
- `in` ← `.usage.input_tokens`; `cr` ← `.usage.cache_read_input_tokens`;
  `out` ← `.usage.output_tokens`; `th` ←
  `.usage.output_tokens_details.thinking_tokens` (all under `.message`,
  default 0)
- `cw5`/`cw1h` ← `.usage.cache_creation.ephemeral_5m_input_tokens` /
  `ephemeral_1h_input_tokens`; when `.usage.cache_creation` is absent,
  `cw5` ← `.usage.cache_creation_input_tokens` and `cw1h` ← 0

### 5.7 `lib/cmd/tokens.sh` (new)

| Function | Signature | Purpose | Dependencies |
|---|---|---|---|
| `cmd_tokens` | `("$@")` | `rdf_require_file "${RDF_STATE_DIR}/rdf-tokens.sh" "rdf-tokens.sh"`; `bash "$script" "$@"`. `help`/`--help`/`-h` are forwarded (the helper prints usage), and the exit code passes through | rdf_common |

### 5.8 `state/rdf-state.sh` (modified)

| Function | Current behavior | New behavior | Lines affected |
|---|---|---|---|
| session_last block | `tail -1` of `session-log.jsonl`; python keep-list `('timestamp','head_before','head_after','commits','diff_summary','pipeline','insight')` | (1) line selection: when the last line contains `"source":"session-end-hook"` and the line before it does not, and both carry a non-empty `head_after` (extracted with `sed -n 's/.*"head_after"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p'` — `/r-save` entries are often pretty-spaced) that match by prefix (`[[ $a == "$b"* || $b == "$a"* ]]`, absorbing short-hash length drift), select the previous line — the `/r-save` entry for the same session state; otherwise the last line. Pure bash + sed, both paths. (2) keep-list adds `'tokens'` | 270-287 |

### 5.9 Canonical text changes

| File | Location | Current | New |
|---|---|---|---|
| `agents/dispatcher.md` | 263-282 "Model routing" | docs/focused → pass `model: "sonnet"`; challenge note mentions sonnet | "Agent routing": docs/focused → dispatch `rdf-engineer-focused`; multi-file/cross-cutting/sensitive → `rdf-engineer`; never pass a per-invocation `model` for routing. Reviewer: the dispatcher dispatches only sentinel reviews → `rdf-reviewer`; challenge reviews come from commands via `rdf-reviewer-challenge` |
| `agents/dispatcher.md` | 399-401 Red/Green | fail → feedback to engineer, retry ≤ 3 | adds: a phase dispatched to `rdf-engineer-focused` sends every fix-cycle re-dispatch to `rdf-engineer` (escalation; same 3-retry cap) |
| `commands/r-spec.md` | after line 7 | — | `## Model` — "In Claude Code this stage is tuned for Fable at high effort. If the active model is not Fable, mention once: 'Tip: launch spec sessions with `claude --model fable --effort high`' — then continue on the current model. Never block, never switch models mid-session." |
| `commands/r-spec.md` | 558-560 | challenge with `model: "sonnet"` | dispatch `rdf-reviewer-challenge` (challenge mode) |
| `commands/r-spec.md` | 643 handoff | "Run `/r-plan`…" | "… Run `/r-plan` in this same session." |
| `commands/r-plan.md` | after line 8 | — | same `## Model` section, naming plan sessions |
| `commands/r-plan.md` | 501-503 | challenge with `model: "sonnet"` | dispatch `rdf-reviewer-challenge` |
| `commands/r-plan.md` | 605 handoff | "Run `/r-build`…" | adds "— in Claude Code, start the build in an Opus session: `claude --model opus`" |
| `commands/r-review.md` | 103-107 | challenge → `model: "sonnet"`; sentinel → default | challenge → dispatch `rdf-reviewer-challenge`; sentinel → `rdf-reviewer` |
| `commands/r-sync.md` | 128 | `model: opus` illustration | adds `effort: xhigh` beneath it |
| `commands/r-sync.md` | 98-103, 138-140 (unmatched deployed files → offer import) | every deployed agent with no canonical match is offered for import | adds: deployed agents whose stem is `<agent>-<variant>` per `agent-meta.json` `variants` are generated copies — never offer them for import; edits belong in `canonical/agents/<agent>.md` |
| `commands/r-save.md` | step 5 | JSON without tokens; template reads `"head_after": "{current HEAD hash}"` | adds `"tokens": {…}` (summary object, or null) + the §7.3 snippet; states the entry is appended as ONE compact JSON line and `head_after` is the short hash (`git rev-parse --short HEAD`) |
| `commands/r-start.md` | 182 | `Last: {N} commits · {diff_summary} · {pipeline} *({age})*` | `Last: {N} commits · {diff_summary} · {pipeline} · ${cost} *({age})*`, with a rule line: cost segment only when `session_last.tokens.cost_usd` exists |

## 5b. Examples

### `rdf tokens` (human)

```
$ rdf tokens --days 30
rdf tokens — rdf · since 2026-08-24T21:05:21Z · list-price estimate
sessions 12 · api turns 1204 (main 412 · subagents 792 in 38 runs)

spend  $142.18
  cache read    61.0%   $86.73
  cache write   24.0%   $34.12
  output        15.0%   $21.30
  input          0.0%    $0.03

by model            turns       cost
  claude-opus-5-5     980    $101.22
  claude-fable-5-1    224     $40.96

by agent             runs   turns       cost
  main                 12     412     $70.01
  rdf-engineer          9     310     $38.40
  rdf-reviewer          6     140     $17.55
  Explore              11      70      $4.10

main context/turn  median 212K · p90 431K · >200K 54.1%
subagent boot      median 22.9K cache-write tokens (38 runs)
effort             xhigh 1120 · high 84
```

(Illustrative figures. Exact fixture figures are in §10a.)

### `rdf tokens --session <id> --summary`

```json
{"session":"e231d9a1-b9ad-493c-8d68-e66f3c9b3891","cost_usd":4.1203,"api_turns":212,"cache_read_share":0.6201,"main_ctx_median":163000,"subagent_runs":3,"by_model":{"claude-opus-5-5":4.1203}}
```

### Errors

```
$ rdf tokens --days abc
rdf-tokens: error: --days expects a positive integer
$ echo $?
2
$ rdf tokens --project /tmp/nowhere
rdf-tokens: error: no transcripts for /tmp/nowhere (looked in ~/.claude/projects/-tmp-nowhere and ~/.claude/projects/-private-tmp-nowhere)
$ echo $?
1
```

### `rdf doctor --scope harness`

```
=== rdf ===
  [harness]   [WARN]  Opus 5.5 main thread runs at its 'medium' default — run '/effort xhigh' in a session (saves per model) or add modelSettings claude-opus-5-5 effortLevel xhigh to ~/.claude/settings.json; RDF agents pin their own effort (a top-level effortLevel in ~/.claude/settings.json does not apply to Opus 5.5)
  [harness]   [WARN]  BASH_MAX_OUTPUT_LENGTH=128000 exceeds the 30000 default — large Bash results stay in context for the rest of the session; overflow already spills to a file
```

### Generated variant frontmatter

```
---
name: rdf-engineer-focused
description: >
  Implementation engineer for docs/focused-scope plan phases (medium effort). Failures escalate to rdf-engineer.
tools:
  - Bash
  - Read
  - Write
  - Edit
  - Glob
  - Grep
model: opus
effort: medium
---
```

### Generate failure

```
$ rdf generate claude-code     # agent-meta has "effort": "ultra" on qa
rdf: error: invalid agent routing in agent-meta.json: qa: effort 'ultra' not in low|medium|high|xhigh|max
$ echo $?
1
```

### Output tree

```
before: adapters/claude-code/output/agents/{dispatcher,engineer,planner,qa,reviewer,uat}.md
after:  adapters/claude-code/output/agents/{dispatcher,engineer,engineer-focused,planner,qa,reviewer,reviewer-challenge,uat}.md
```

## 6. Conventions

### 6.1 Shell

- **Headers.** The new executable uses `#!/usr/bin/env bash`,
  `set -euo pipefail`, and the header `# state/rdf-tokens.sh — <purpose>`,
  `# (C) 2026 R-fx Networks <proj@rfxn.com>`, `# GNU GPL v2`.
- **Strict mode.** Sourced `lib/**` files carry no `set` line.
- **Coreutils.** First-party source prefixes coreutils with `command`. The
  helper is an executable, so it follows the same rule as `state/*.sh`.
- **Bash floor.** No bash-4 features: no `mapfile`, `local -A`, `${v,,}`,
  `declare -n`, `&>>` or `|&`. Empty arrays expand as `"${a[@]+"${a[@]}"}"`.
  Pattern substitution is never used for escaping.
- **Suppressions and locals.**
  - Every new `2>/dev/null` / `|| true` carries a same-line justification.
  - A function-local var is declared separately from its `$(…)` assignment.
- **Wrapper shape.** `lib/cmd/tokens.sh` follows `lib/cmd/state.sh`, minus the
  usage heredoc, which is forwarded to the helper.

### 6.2 jq portability (1.5 floor)

- **Forbidden** (1.6+ or Oniguruma-dependent):
  - `round`, `ceil`, `abs`, `trim`/`ltrim`/`rtrim`, `pick`, `IN`, `INDEX`,
    `$ENV`, `env.`, `walk` (unless defined inline), `halt_error`, `splits`
    (jq 1.5 libm exposes `floor`/`sqrt`/`pow` only)
  - `test`/`match`/`capture`/`sub`/`gsub`
  - CLI flags `--args`, `--jsonargs`, `--rawfile`
  - `fromdateiso8601`/`strptime` on transcript timestamps: they carry
    milliseconds, and the probe failed with rc 5
- **Allowed:** `group_by`, `sort_by`, `min_by`, `max_by`, `startswith`,
  `ltrimstr`, `rtrimstr`, `todate` on integer epochs, `input_filename`,
  `fromjson?`, `tostring`, `floor`, `length`, `add`, `keys`, `to_entries`,
  `from_entries`.
- **Rounding** is written `(. * 10000 + 0.5 | floor) / 10000` for JSON money
  and shares (4 dp), `(. * 10 + 0.5 | floor) / 10` for every `*_pct` field
  (1 dp), and `(. * 100 + 0.5 | floor) / 100` for text dollars (2 dp).
- **Programs** are single-quoted. Values enter via `--arg`, `--argjson` (small, fixed values only) or `--slurpfile` (large maps); never by string interpolation.

### 6.3 Dedup and metric contract

- Rows are grouped by `id` across every file in scope.
- For numeric fields (`in, cw5, cw1h, cr, out, th`) take the max; for the other
  fields take the row with the smallest `ts`.
- If `usage.cache_creation` is absent, all of `cache_creation_input_tokens` is
  `cw5`.
- Context per turn = `in + cw5 + cw1h + cr`.
- Percentiles use nearest rank: index `(-((-(p*n)) | floor)) - 1` (a `ceil`
  without `ceil`), median p = 0.5, p90 p = 0.9.
- A turn is **main** when its file is a top-level `<sid>.jsonl`, and
  **subagent** otherwise.
- `subagent_runs` = distinct subagent files with ≥ 1 row.
- `sessions` = distinct `sid` over main rows.
- Boot = the `cw5 + cw1h` of the earliest-`ts` row in each subagent file.

### 6.4 Pricing (embedded; USD per MTok; list-price estimate as of 2026-09-23)

| Key (prefix match, longest first) | input | output | cache read |
|---|---|---|---|
| `claude-opus-5-5` | 4 | 20 | 0.20 |
| `claude-opus-5` | 5 | 25 | 0.50 |
| `claude-opus-4-8` | 5 | 25 | 0.50 |
| `claude-fable-5-1` | 10 | 50 | 0.25 |
| `claude-fable-5` | 10 | 50 | 1.00 |
| `claude-sonnet-5` | 2 | 10 | 0.20 |
| `claude-haiku-4-5` | 1 | 5 | 0.10 |

- Cache write costs 1.25× input for `cw5` and 2× input for `cw1h`.
- A trailing `[1m]` is stripped before matching. Matching uses `startswith`
  over keys sorted by length, descending.
- An unmatched model contributes tokens and turns but no cost, and is listed in
  `unpriced_models`.
- Shares are computed over priced cost only.

### 6.5 Agent labels

- A main file's rows are labelled `main`.
- A subagent file's rows take `agentType` from `<file minus .jsonl>.meta.json`,
  or `unknown` when absent.

## 7. Interface Contracts

### 7.1 `rdf tokens` / `rdf-tokens.sh`

```
Usage: rdf tokens [options]
  --project DIR      project directory (default: current directory)
  --transcripts DIR  transcript directory (overrides --project resolution)
  --session ID       one session and its subagents, found under any project (ignores the window)
  --days N           window: last N days (default 30)
  --since YYYY-MM-DD window start (overrides --days)
  --json             full JSON report
  --summary          compact JSON object for session logs
  help               this text
Environment:
  RDF_CLAUDE_PROJECTS  transcript root (default: ~/.claude/projects)
Prices are embedded list prices as of 2026-09-23 (estimate). Transcripts are read
locally; nothing is sent anywhere.
Known limitation: --session on a resumed or forked session includes the history
it copied from its parent.
```

**Exit codes:**
- `0`: report printed, including an empty window (`no usage in window` /
  zero-valued JSON).
- `1`: transcripts not found, or jq absent.
- `2`: usage error — unknown flag, bad `--days`/`--since`, a missing value, or a
  `--session` value outside `[A-Za-z0-9-]`.

**`--json` keys:**
- `scope`: `{project, transcripts, since, session}`
- counts: `sessions`, `api_turns`, `main_turns`, `subagent_turns`,
  `subagent_runs`
- `tokens`: `{input, cache_write_5m, cache_write_1h, cache_read, output, thinking}`
- `cost_usd` (4 dp)
- `share`: `{input, cache_write, cache_read, output}` (4 dp)
- `by_model`: `[{model, turns, cost_usd|null}]`, cost descending
- `by_agent`: `[{agent, runs, turns, cost_usd}]`, cost descending
- `main_context`: `{median, p90, over_200k_pct}`
- `subagent_boot`: `{median_cache_write, runs}`
- `effort`: `{<level>: turns}`
- `unpriced_models`: `[…]`

**`--summary` keys:** `session` (or null), `cost_usd`, `api_turns`,
`cache_read_share`, `main_ctx_median`, `subagent_runs`, `by_model`
(`{model: cost}`).

### 7.2 `rdf doctor --scope harness`

- Category `harness`, `category|status|message` results.
- WARN or OK only, so exit-code semantics are unchanged.
- `--json` output is valid for all message text (§5.5 `_json_esc`).

### 7.3 `/r-save` capture

```bash
tok="$(bash ~/.rdf/state/rdf-tokens.sh --session "${CLAUDE_CODE_SESSION_ID:-}" --summary 2>/dev/null)" || tok=""   # helper absent / no id / no transcript → record null
[ -n "$tok" ] || tok=null
```

The entry's `tokens` value is `$tok`, inlined as JSON. `rdf-state.sh` keeps it
in `session_last`, and `/r-start` renders `tokens.cost_usd`.

### 7.4 `agent-meta.json`

- Additive keys `effort` (string) and `variants` (object).
- The gemini adapter reads its own `adapters/gemini-cli/agent-meta.json` and is
  unaffected.

## 8. Migration Safety

- **Upgrade, checkout:**
  - `rdf generate claude-code` rebuilds `output/agents/` atomically
    (`adp_stage_begin/commit`).
  - `~/.claude/agents` is a directory symlink, so the variants appear without a
    deploy change.
  - Sessions pick up new agents on restart.
- **Upgrade, plugin:**
  - `plugin.json` gains 2 agent paths via `cpl_stamp_plugin_version`.
  - Committed output is regenerated in the same commit, which satisfies the CI
    drift gate (`git diff --exit-code adapters/claude-plugin/output
    .claude-plugin/plugin.json`).
- **Helper delivery:**
  - `rdf-tokens.sh` is delivered by the `state/*.sh` globs (`deploy.sh:207`,
    `state-bootstrap.sh:27`).
  - `rdf doctor --scope state-helpers` covers it.
  - `tests/deploy.bats:353` stops hard-coding 7.
  - Checkout installs link helpers per file, so users must re-run
    `rdf deploy claude-code` once to link `rdf-tokens.sh`. Until then `/r-save`
    records `null` and `doctor --scope state-helpers` WARNs `helpers not
    deployed`. The CHANGELOG states this.
- **Fable availability:**
  - Only `rdf-planner` uses `fable`, and no canonical command dispatches it.
  - Where an allowlist excludes the newest Fable, CC substitutes the newest
    permitted version (model-config § availableModels).
  - Where Fable is absent entirely, a direct planner dispatch fails. The README
    documents the one-line override (`"model": "opus"`).
- **Rollback:**
  - Revert and regenerate.
  - The only persistent write is the additive `tokens` key in
    `session-log.jsonl`; old readers ignore it (python keep-list) or pass it
    through (no-python path).
- **Uninstall:** the new files are removed by the existing paths (the
  `~/.rdf/state` links and copies; the output agents dir).
- **Test-suite impact:**
  - The byte-identity test switches to the frozen fixture. That is its intended
    contract: emitter mechanics, not live values.
  - `deploy.bats:353` derives its count from source.
  - The `sync.bats` / `doctor.bats` additions are new tests. No existing
    assertion changes except the two named above.
- **Doc-truth:**
  - The WORKFORCE dispatch check matches `rdf-reviewer` inside
    `rdf-reviewer-challenge` (verified by the reviewer probe).
  - The canonical-agent iteration is unaffected.
  - `rdf doctor --scope doc-truth` and `doc-stats` run in the doc phase's
    verification.

## 9. Dead Code and Cleanup

| Finding | Location | Action |
|---|---|---|
| README doctor row says "13 checks" and omits `doc-truth` | `README.md:246` | fix to 15, listing `doc-truth`, `harness` |
| README footnote on dynamic sonnet routing | `README.md:408` | replace with variant routing note |
| README "Add an Agent" shows `"model": "sonnet"`, no `effort` | `README.md:590-600` | document `model`/`effort`/`variants` |
| `dispatcher.md` challenge-mode sonnet note | `dispatcher.md:279-282` | rewritten (§5.9) |
| WORKFORCE "Model Summary" sonnet rows | `WORKFORCE.md:48-56` | rewritten |
| `_results_to_json` unescaped strings (latent invalid JSON) | `doctor.sh:1458-1477` | fixed (§5.5) |

No dead functions found in the files read.

## 10a. Test Strategy

| Goal | Test file | `@test` |
|---|---|---|
| 1 | `governance-contracts.bats` | "agent-meta pins model and effort for every agent per the routing table" |
| 2 | `adapter-common.bats` | "live agent-meta emits effort lines and the two variant files with overridden name/effort" |
| 2 | `plugin-adapter.bats` | "plugin.json agents array includes generated variant files" |
| 3 | `adapter-common.bats` | existing "adp_emit_agents output is byte-identical to the 3.6.5 emitter fixture", now reading `tests/fixtures/adapter-common/agent-meta-3.7.0.json` |
| 4 | `strip.bats` | "rdf_require_agent_meta dies on invalid effort, bad variant key, missing variant effort, and variant collision"; "missing model/effort is valid" |
| 4 | `doctor.bats` | "doctor catalogs: invalid agent routing FAILs; valid routing reports OK" |
| 5 | `governance-contracts.bats` | "no canonical routing directive passes model: sonnet"; "dispatcher routes focused phases to rdf-engineer-focused and escalates failures to rdf-engineer"; "challenge reviews dispatch rdf-reviewer-challenge" |
| 6 | `governance-contracts.bats` | "r-spec and r-plan carry the non-blocking Fable advisory"; "r-spec handoff keeps /r-plan in the same session"; "r-plan handoff names the Opus build session" |
| 7 | `sync.bats` | "sync never creates a canonical agent from a variant or stray output file" |
| 7 | `governance-contracts.bats` | "r-sync never offers generated variant agents for import" |
| 7 | `doctor.bats` | "doctor sync: agent count excludes declared variants" |
| 8 | `tokens.bats` | "--json on the fixture reproduces the hand-computed report" (all §10a figures); "dedups repeated message.id entries"; "labels subagents by meta agentType including workflow subagents"; "skips synthetic, id-less and malformed entries"; "--since excludes older entries"; "--session includes out-of-window rows and only that session"; "unknown model is reported unpriced and excluded from shares"; "text output shows spend and by-agent rows"; "bad --days and bad --session exit 2; missing transcripts exit 1"; "rdf tokens wrapper forwards help and exit codes" |
| 9 | `tokens.bats` | "--summary emits the compact session object"; "rdf-state.sh session_last preserves a tokens object"; "session_last prefers the /r-save entry over a trailing same-state SessionEnd-hook entry"; "session_last keeps a hook entry whose head_after differs"; "session_last selects a pretty-spaced /r-save entry" |
| 9 | `governance-contracts.bats` | "r-save session-log entry records a tokens summary or null"; "r-start Last line renders session cost when present" |
| 10 | `doctor.bats` | "doctor --json stays valid when a message contains quotes and backslashes"; "harness: unpinned Opus 5.5 WARNs"; "harness: modelSettings pin is OK"; "harness: CLAUDE_CODE_EFFORT_LEVEL WARNs as flattening"; "harness: project top-level effortLevel pins, user top-level does not"; "harness: non-opus model is not applicable"; "harness: BASH_MAX_OUTPUT_LENGTH above 30000 WARNs"; "harness: bashOutputMaxChars setting takes precedence over the env var"; "harness: CLAUDE_CODE_EFFORT_LEVEL=auto counts as unset" |
| 11 | existing `doc-truth.bats`, full suite, `rdf doctor` | verification G11 |

### Token fixture (`tests/fixtures/tokens/proj/`)

Timestamps use the real millisecond format.

| File | Entries |
|---|---|
| `s1.jsonl` (sessionId `s1`) | **A** `msg_A` opus-5-5, `2026-09-20T10:00:00.123Z`, xhigh, usage in 10 / cc 1000 (`cache_creation` 5m 0, 1h 1000) / cr 100000 / out 2000 / thinking 500. Written as **3** entries (content blocks). **B** `msg_B` opus-5-5, `2026-09-20T10:05:00.456Z`, xhigh, in 5 / cc 0 (5m 0, 1h 0) / cr 300000 / out 1000. **OLD** `msg_OLD` opus-5-5, `2026-08-01T00:00:00.000Z`, xhigh, in 1 / cr 0 / out 100 / cc 0. One `<synthetic>` entry `msg_S`. One assistant entry with usage but no `message.id`. One truncated line `{"type":"assistant","message":{` |
| `s1/subagents/agent-a1.jsonl` + `agent-a1.meta.json` `{"agentType":"rdf-engineer"}` | **C** `msg_C` opus-5-5, `2026-09-20T10:01:00.000Z`, medium, in 3 / cc 20000 (**no** `cache_creation` object) / cr 0 / out 500. **D** `msg_D` opus-5-5, `2026-09-20T10:02:00.000Z`, medium, in 2 / cc 0 / cr 20000 / out 300 |
| `s1/subagents/workflows/wf_x/agent-w1.jsonl` + meta `{"agentType":"general-purpose"}` | **E** `msg_E` fable-5-1, `2026-09-20T10:03:00.000Z`, high, in 1 / cc 10000 (5m 10000, 1h 0) / cr 0 / out 100 |
| `s2.jsonl` (sessionId `s2`) | **F** `msg_F` `claude-mystery-9`, `2026-09-21T00:00:00.000Z`, no effort field, in 100 / cc 0 / cr 0 / out 100 |

**Expected: `--transcripts tests/fixtures/tokens/proj --since 2026-09-01 --json`**

Counts and turns:

| Field | Value |
|---|---|
| `sessions` | 2 |
| `api_turns` | 6 |
| `main_turns` | 3 |
| `subagent_turns` | 3 |
| `subagent_runs` | 2 |

Tokens:

| `input` | `cache_write_5m` | `cache_write_1h` | `cache_read` | `output` | `thinking` |
|---|---|---|---|---|---|
| 121 | 30000 | 1000 | 420000 | 4000 | 500 |

Cost and shares:

| Field | Value |
|---|---|
| `cost_usd` | 0.3981 |
| `share.cache_read` | 0.211 |
| `share.cache_write` | 0.5853 |
| `share.output` | 0.2035 |
| `share.input` | 0.0002 |

By model:

| Model | Turns | `cost_usd` |
|---|---|---|
| `claude-opus-5-5` | 4 | 0.2681 |
| `claude-fable-5-1` | 1 | 0.13 |
| `claude-mystery-9` | 1 | null |

By agent:

| Agent | Runs | Turns | `cost_usd` |
|---|---|---|---|
| `main` | 2 | 3 | 0.1481 |
| `general-purpose` | 1 | 1 | 0.13 |
| `rdf-engineer` | 1 | 2 | 0.12 |

Remaining fields:

| Field | Value |
|---|---|
| `main_context` | `{median: 101010, p90: 300005, over_200k_pct: 33.3}` |
| `subagent_boot` | `{median_cache_write: 10000, runs: 2}` |
| `effort` | `{xhigh: 2, medium: 2, high: 1, unset: 1}` |
| `unpriced_models` | `["claude-mystery-9"]` |

Per-message derivation:
- A = 0.00004 + 0.008 + 0.02 + 0.04 = 0.06804
- B = 0.00002 + 0.06 + 0.02 = 0.08002
- C = 0.000012 + 0.1 + 0.01 = 0.110012
- D = 0.000008 + 0.004 + 0.006 = 0.010008
- E = 0.00001 + 0.125 + 0.005 = 0.13001
- Sum = 0.39809

**Expected: `--transcripts …/proj --session s1 --summary` (OLD included, F excluded):**
- `api_turns`: 6
- `cost_usd`: 0.4001 (0.39809 + OLD 0.002004)
- `subagent_runs`: 2
- `session`: `"s1"`

(In the fixture, `--session` resolves via `RDF_CLAUDE_PROJECTS=tests/fixtures/tokens`
so `*/s1.jsonl` matches `proj/s1.jsonl`.)

## 10b. Verification Commands

```bash
# G1
jq -r 'to_entries[]|select(.value|type=="object" and has("name"))|"\(.key) \(.value.model) \(.value.effort)"' adapters/claude-code/agent-meta.json
# expect:
# planner fable high
# dispatcher opus high
# engineer opus xhigh
# qa opus medium
# uat opus medium
# reviewer opus xhigh

# G2
bin/rdf generate claude-code >/dev/null && grep -h '^\(name\|model\|effort\):' adapters/claude-code/output/agents/engineer-focused.md adapters/claude-code/output/agents/reviewer-challenge.md
# expect:
# name: rdf-engineer-focused
# model: opus
# effort: medium
# name: rdf-reviewer-challenge
# model: opus
# effort: high
ls adapters/claude-code/output/agents/*.md | wc -l
# expect: 8

# G3
bats tests/adapter-common.bats -f 'byte-identical'
# expect: ok 1 adp_emit_agents output is byte-identical to the 3.6.5 emitter fixture

# G4
bats tests/strip.bats -f 'invalid'
# expect: all selected tests ok (0 failures)

# G5
grep -rnE 'model: ?"sonnet"' canonical/agents canonical/commands | wc -l
# expect: 0
grep -c 'rdf-engineer-focused' canonical/agents/dispatcher.md
# expect: 2 or more
grep -l 'rdf-reviewer-challenge' canonical/commands/r-spec.md canonical/commands/r-plan.md canonical/commands/r-review.md | wc -l
# expect: 3

# G6
grep -l 'claude --model fable --effort high' canonical/commands/r-spec.md canonical/commands/r-plan.md | wc -l
# expect: 2

# G7
bats tests/sync.bats -f 'never creates'
# expect: 1 test ok

# G8
bin/rdf tokens --transcripts tests/fixtures/tokens/proj --since 2026-09-01 --json | jq -c '[.api_turns, .cost_usd, .unpriced_models]'
# expect: [6,0.3981,["claude-mystery-9"]]

# G9
RDF_CLAUDE_PROJECTS=tests/fixtures/tokens bash state/rdf-tokens.sh --session s1 --summary | jq -c '[.api_turns, .cost_usd]'
# expect: [6,0.4001]

# G10
bin/rdf doctor --scope harness --json | jq -r '.checks[].category' | sort -u
# expect: harness
bin/rdf doctor --scope bogus 2>&1 | grep -c 'harness'
# expect: 1

# G11
bin/rdf doctor >/dev/null; echo "rc=$?"
# expect: rc=0
make -C tests test 2>&1 | grep -c '^not ok'
# expect: 0
shellcheck -S error --exclude=SC1090,SC1091 state/rdf-tokens.sh lib/cmd/tokens.sh lib/cmd/doctor.sh lib/cmd/sync.sh lib/rdf_common.sh lib/adapter_common.sh state/rdf-state.sh; echo "rc=$?"
# expect: rc=0
```

## 11. Risks

1. **Variant files confuse sync or drift tooling.**
   Mitigation:
   - sync never creates canonical agents (no jq dependency)
   - `_check_sync` excludes variant stems
   - content-drift works unchanged, since variant sidecars hash the canonical
     body
   - tests cover each
2. **Cost moves versus the old Sonnet mix.** Mitigation:
   - the measured S3 delta is −0.2% to −6.5% vs all-Opus-5.5, and scoped roles
     run at `medium`
   - `rdf tokens` measures the actual effect
   - effort is a one-line metadata edit
3. **`fable` unavailable on some accounts.** Mitigation:
   - only the rarely-dispatched `rdf-planner` uses it, and `/r-spec`/`/r-plan`
     run inline and never require it
   - README documents the override
4. **Transcript schema drift across CC versions.** Mitigation:
   - defensive jq (`fromjson?`, `//` defaults, rows need id + usage)
   - the fixture pins today's shape
   - output is labelled an estimate
5. **jq 1.5 incompatibility.** CI's apt (1.7.1) and brew jq don't exercise 1.5.
   Mitigation:
   - the §6.2 forbidden list is enforced by a grep assertion in `tokens.bats`
     (`@test "rdf-tokens.sh uses no jq 1.6+ builtins"`)
   - string-compared timestamps
   - no regex builtins
6. **Doc-truth / doc-stats FAIL from count changes.** Mitigation: count-bearing
   docs are updated in the same phase as the code, and that phase's
   verification runs `rdf doctor --scope doc-truth` and `--scope doc-stats`.
7. **`CLAUDE_CODE_SESSION_ID` absent** (other harnesses, older CC).
   Mitigation: `/r-save` records `null`, and the helper exits 2 on an empty id.
8. **Users rely on `CLAUDE_CODE_EFFORT_LEVEL`,** which silently flattens the
   routing (probed). Mitigation: doctor `harness` WARNs with the `/effort`
   alternative, and the README routing section states the precedence.

## 11b. Edge Cases

| Scenario | Expected behavior | Handling |
|---|---|---|
| Same `message.id` in 3 content-block entries and again in a resumed session file | counted once in window mode | dedup §6.3 across all files |
| Line truncated mid-write (active session) | line skipped, rest parsed | `jq -R 'fromjson?'` |
| `usage.cache_creation` absent (older CC) | all creation tokens priced as 5 m | §6.3 |
| Model `claude-opus-5-5[1m]` or date-suffixed haiku | priced by prefix | strip `[1m]`, `startswith` longest-first |
| Model not in price table | tokens counted; cost null; excluded from shares | §6.4 |
| Subagent `.meta.json` missing | label `unknown` | §6.5 |
| Window with zero rows | exit 0, `no usage in window` / zero JSON | `_tok_report` guard |
| `--session ../x` or `a/b` | exit 2 | `case` on `*[!A-Za-z0-9-]*` |
| Project path with `.`/`_` or a symlinked path (`/tmp` → `/private/tmp`) | resolves via logical then `cd -P` slug | `_tok_resolve_dir` |
| Many transcript files (long windows) | no ARG_MAX failure | `find -print0 \| xargs -0 jq` batches |
| Variant stem collides with a canonical agent | generate dies; doctor FAIL | `rdf_agent_routing_errors` |
| Emergency edit to a deployed variant | sync skips it (message); content-drift FAILs on it | §5.4 + existing drift loop |
| Settings file unparseable | skipped by harness | `jq -e .` guard |
| `BASH_MAX_OUTPUT_LENGTH` non-numeric | treated as unset (OK) | integer `case` guard |
| Main model `sonnet`/`fable`/`best` | effort check reports not applicable | §5.5 step 5 |
| Doctor message containing `"`, `\`, a tab or ESC | valid JSON | `_json_esc` |
| `/r-save` entry followed by the SessionEnd-hook entry for the same state | `/r-start` shows the `/r-save` entry (with tokens) | §5.8 line selection |
| Spaced `/r-save` entry (`"head_after": "…"`) before the hook entry | still selected | `[[:space:]]*` pattern |
| Session A `/r-save`, then session B's hook with no commits (A's hook never fired) | A's entry shown (its own timestamp) — acceptable | §5.8 same-state rule |
| `CLAUDE_CODE_EFFORT_LEVEL=auto` | treated as unset (no flattening WARN; Opus pin still evaluated) | §5.5 step 3 |
| `bashOutputMaxChars` set in a settings file | env var ignored; setting value checked | §5.5 step 8 |
| Glasswell-scale window (659 subagent files) | agent map passed by file | `--slurpfile` |
| `--session` on a resumed session | includes copied parent history | documented limitation (§3, usage text) |

## 12. Open Questions

None. Decisions were made unattended (user-authorized 2026-09-23). Rationale is
in `.rdf/work-output/spec-progress-01a0d009-e5d2-751f-b48e-f76641568c15.md`
(Q1–Q9).

### Challenge review r1 — responses

| Finding | Response |
|---|---|
| M1 byte-identity test reads live meta | **Fixed:** frozen `agent-meta-3.7.0.json` fixture + a separate live-meta test (§4.1, §10a) |
| M2 `rdf-state.sh` keep-list drops `tokens` | **Fixed:** keep-list adds `tokens` (§5.8), with a test |
| M3 `deploy.bats:353` hard-codes 7 | **Fixed:** count derived from `state/*.sh` |
| S1 project top-level `effortLevel` as pin | **Rebutted with evidence:** model-config line 540: "A top-level `effortLevel` in project, local, or managed settings… applies to every model." Kept, and cited in §5.5 |
| S2 cache-sharing claim | **Fixed:** §4.5.1 now states variants do not share cache with the base, and justifies them as the least machinery for the user-approved per-role effort |
| S3 planner → `inherit` | **Rebutted:** the user approved `fable/high` for `rdf-planner`. The risk is scoped (no canonical dispatch) and the override is documented. "(VPE, users)" corrected |
| S4 sync without jq | **Fixed:** sync never creates canonical agents (no metadata needed) |
| S5 missing model | **Fixed:** specified as valid/skipped |
| S6 session transcript resolution | **Fixed:** session mode globs `*/<sid>.jsonl`; project mode tries the logical, then the physical slug |
| S7 jq 1.5 floor | **Fixed:** expanded forbidden list, string timestamp compare, grep-enforced test, ms fixture timestamps |
| S8 privacy "no telemetry" | **Fixed:** "token usage report" wording; `docs/privacy.md` updated |
| S9 claudemd-review sonnet, README Add-an-Agent | **Fixed:** the former is an explicit non-goal, the latter added to the file map |
| S10 weak verification | **Fixed:** concrete fixture figures; host-dependent check removed; handoff and `/r-start` contracts tested |
| S11 new scope vs `deps`; duplicated usage | Scope **kept**: parity with `deps`/`state-helpers`, which also run per project under `--all`, and "harness settings" is a distinct category. Usage **fixed**: forwarded to the helper |
| I1 precedence | **Resolved empirically:** env overrides agent effort; `--effort` does not. Doctor WARNs on the env var and never recommends it |
| I2 jq ordering | **Fixed:** both adapters reorder |
| I3 escaping | **Fixed** — superseded in r3 by a single `sed` per entry (§5.5) |
| I4 session regex, resume double count, `best`, ARG_MAX, example time | **Fixed** / documented (§11b) |
| I5 ordering, description size, "In Claude Code" phrasing | **Adopted** (§4.6, §5.1, §5.9) |
| I6 factual nits | **Fixed** (364 tests; lines 104-114; §6.2; skipped counter) |

### Challenge review r2 — responses

| Finding | Response |
|---|---|
| MUST-FIX: SessionEnd-hook entry shadows the `/r-save` entry in `session_last` (`rdf-state.sh:272` `tail -1`; `session-end-capture.sh:64`) | **Fixed:** same-`head_after` save-then-hook selection (§5.8) + two fixture tests; it also restores `commits`/`diff_summary` on today's Last line |
| S1 `/r-sync` offers variants for import | **Fixed:** r-sync text (§5.9) + contract test |
| S2 `CLAUDE_CODE_EFFORT_LEVEL=auto` | **Fixed:** empty/`auto` = unset |
| S3 `bashOutputMaxChars` precedence | **Fixed:** setting first, env fallback |
| S4 agent map exceeds single-arg limit | **Fixed:** merged file + `--slurpfile` |
| S5 `over_200k_pct` rounding | **Fixed:** `*_pct` at 1 dp; fixture 33.3 stands |
| S6 no `ceil` in jq 1.5 | **Fixed:** floor-based index; forbidden list extended |
| S7 variant-key and model-id patterns | **Fixed:** explicit reject patterns |
| S8 `_json_esc` fork cost | **Fixed:** one `sed` per entry; category/status not escaped separately |
| I: plugin adapter already ordered; recipe comment; row sources; directive count 6; `_check_sync` without jq; managed settings; upgrade note | **Fixed** (§4.1, §4.6, §5.5, §5.6, §8) |
| I: existing pattern-substitution escapes | Noted. The r3 design uses `sed`, so the claim about pattern substitution is moot and was removed |

### Challenge review r3 — responses

| Finding | Response |
|---|---|
| MUST-FIX: the `head_after` sed pattern misses pretty-spaced `/r-save` entries (71 of 851 journal entries; 9 of 35 current last lines) | **Fixed:** `[[:space:]]*` pattern; non-empty + prefix match; spaced-entry test; r-save step 5 now asks for one compact line with the short hash |
| Short vs long hash | **Fixed:** prefix comparison, plus r-save wording pins `--short` |
| §6.2 vs `--slurpfile` | **Fixed:** §6.2 allows `--slurpfile` |
| I: temp cleanup, map key, cross-session row, stale I3 text, line range | **Fixed** (§5.6 `main`, `_tok_agent_map`, §11b, §12, §5.8) |

**Final verdict:** cycle 3 reported one MUST-FIX that it classed as applicable without another cycle (a one-line pattern plus a test). It is applied here, so all MUST-FIX findings are resolved.

