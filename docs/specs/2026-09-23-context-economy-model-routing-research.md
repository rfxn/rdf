# Context Economy and Model Routing — Research and Product Options

**Date:** 2026-09-23 · **Status:** research (input to `/r-spec`) · **Baseline:** RDF 3.7.0 @ 55e8473, Claude Code 2.1.280, codex-cli 0.150.1
**Supersedes:** `2026-09-10-token-efficiency-research.md` (its token totals are ~2.4× inflated — see §2.1; its shape findings and options E/A/B/C/F carry forward here)

## 1. Question

How do we materially cut token spend without eroding outcome quality, and what
model/effort defaults should RDF ship now that Claude Opus 5.5 (2026-09-22) and
Claude Fable 5.1 are current — target: Opus 5.5 for default work, Fable 5.1 for
spec/plan?

## 2. Measured on this install (transcripts, deduped by `message.id`)

### 2.1 Correction to the 09-10 brief
Claude Code writes one JSONL entry per content block, each repeating the same
`message.id` and `usage`. The 09-10 brief counted entries, not API turns, so its
totals (1.07 B tokens, 3,988 turns, per-agent spend) are ~2.4× high. Medians,
percentiles and shares are unaffected. Any telemetry RDF ships must dedup by
`message.id` (and across resumed/fork transcripts: 164 repeated IDs observed).

### 2.2 Where the money goes (60 days, list prices)

| Measure | All projects | RDF |
|---|---|---|
| Spend | $19,245 | $497 |
| Cache reads / cache writes / output share of spend | 60% / 25% / 15% | — |
| Subagent share of spend | 80% | 54% |
| Main median / p90 context per turn | — | 295 K / 512 K |
| Turns > 200 K / > 400 K | 51% / 20% (since 09-10) | 64% / 28% |
| Compactions | 5 | 0 |
| rdf-* first-turn cache write (boot) | — | 23.1 K (Explore ~10 K) |
| Onboarding reads share of subagent tool-result bytes | — | 29% |
| Turns at `xhigh` effort | 95.2% | — |

Inherited per rdf-* boot: global CLAUDE.md 1.3 K + workspace 6.3 K + project
0.9 K + MEMORY.md 2.0 K ≈ 10.5 K tokens; engineer/qa/uat/dispatcher then re-read
governance derived from the same sources (`engineer.md:14-16`, `qa.md:13`,
`uat.md:14`, `dispatcher.md:17`).

Since 09-10, file access moved from Read to Bash (81 `cat`/`sed`/`grep` reads vs
2 Read calls) — read discipline must cover Bash, not just Read.

### 2.3 Model-cost scenarios (token volumes held fixed)

| Scenario | All projects | RDF |
|---|---|---|
| Actual (83% Opus 5) | $19,245 | $497 |
| S1 everything on Opus 5.5 | −47% | −40% |
| S2 S1 + spec/plan + planner on Fable 5.1 | +2.5% vs S1 (+4.0% with Fable's 2× output/turn) | +4.9% (+9.2%) |
| S3 current agent-meta mix (dispatcher/qa/uat on Sonnet 5) | −0.2% vs S1 | −6.5% vs S1 |

S1's saving is almost entirely cache-read price ($0.50 → $0.20/MTok) and arrives
automatically: the `opus` alias resolves to Opus 5.5 in CC 2.1.280. Output is
21–27% of cost under S1; ±25% output moves total ±5–7%. Effort also changes turn
count and context growth, which volumes cannot capture, and with 95% of turns at
`xhigh` there is no local effort-sensitivity data yet.

## 3. Platform facts (verified against primary docs 2026-09-23)

Claude Code (code.claude.com/docs: model-config, sub-agents, skills, settings-reference, workflows):
- `opus` → Opus 5.5; `fable` → Fable 5.1; `best` → Fable where available, else
  Opus (session-level only; not valid in agent frontmatter). `[1m]` is
  unnecessary on current models.
- **Opus 5.5 effort trap:** Opus 5.5 defaults to `medium`, and a top-level
  `effortLevel` in *user* settings does not apply to it. Only
  `modelSettings["claude-opus-5-5"].effortLevel`, `CLAUDE_CODE_EFFORT_LEVEL`,
  `--effort`, or `/effort` set it. Users who configured xhigh before 2026-09-22
  silently run at `medium`.
- Subagent frontmatter: `model:` (`sonnet|opus|haiku|fable|<id>|inherit`) and
  `effort:` (`low…max`); omitted effort inherits the session's. Resolution:
  per-invocation `model` → frontmatter → `CLAUDE_CODE_SUBAGENT_MODEL` → session.
- `omitClaudeMd: true` (v2.1.271+) boots a custom or plugin subagent without
  user/project/local CLAUDE.md; managed policy still loads. `skills:` preloads
  named skills into a subagent.
- Skill `model:` lasts only the current turn; the session model resumes on the
  next prompt — unusable for multi-turn `/r-spec` dialogue. Prompt caches are
  model-scoped, so a mid-session model switch rewrites the whole prefix.
- Workflow scripts may name a model per stage; agents with identical model,
  effort, type, tools, schema and cwd share cache.
- `/usage` reports cache hit rate and miss causes (v2.1.251+).

Anthropic model guidance (platform.claude.com effort + prompting guides):
- **Opus 5.5:** "Start at `medium`… set it explicitly… Reserve `xhigh` and `max`
  for work where you've measured a quality gain." At `medium` it matched or beat
  Opus 5 at `high` on multistep repository coding in fewer steps and tokens; at a
  given level it thinks more per turn than Opus 5, especially at `xhigh`.
- **Effort table:** `xhigh` = "Long-running agentic and coding tasks (over 30
  minutes) with token budgets in the millions"; `low` = "simpler tasks… such as
  subagents". Changing top-level effort between requests invalidates the cache.
- **Fable 5.1:** start at `high` (default); `xhigh` only for the most
  capability-sensitive work. At `xhigh`/`max` it may draft a long deliverable in
  thinking and write it again — run long documents at `high`.
- **Cost guide:** re-running failures at higher effort held the coding pass rate
  at about half the cost; when work is "one dependent chain, or fits in a single
  context… the coordinator's model alone at lower effort came out ahead."

Codex CLI (third-party-sourced where marked): custom agents in
`.codex/agents/*.toml` accept `model` and `model_reasoning_effort`; `[agents]`
has `default_subagent_reasoning_effort`; `plan_mode_reasoning_effort`,
`tool_output_token_limit`, `project_doc_max_bytes` (AGENTS.md cap, 32 KiB
default). Spawn-time overrides reportedly ignored in multi_agent_v2 — pin in
TOML. Local model cache (2026-08-29): gpt-5.6-sol/terra/luna, all default
`medium`. A reported GPT-6 Sol/Luna release (2026-09-22) is unverified locally —
RDF must not hardcode vendor model names.

Antigravity: `.agents/agents/<name>.md` takes `model: inherit|flash|pro`;
effort is session-level only (`--effort`, `/effort`).

## 4. External evidence (delta since 09-10)

| Finding | Evidence | Use |
|---|---|---|
| Token cuts ≠ cost cuts: 38% tool-output reduction raised cost 6.8%; r=0.15 token vs cost savings (arXiv 2607.12161) | Measured, third-party | Optimize bytes *carried*, measure cost per completed task |
| Rule-based trimming before LLM summarization most efficient; agent recovery of trimmed content gave no gain (arXiv 2609.20804, 176 configs) | Measured | Supports truncate-to-file (F) and bounded sessions (A) |
| Superpowers 6: −60% tokens; terse reviewer format −41% reviewer output; "implementation bodies in plans are marginal" | Vendor-measured | Result contracts; lean plans |
| Anthropic long-running harness: planner $0.46 vs build $113.85 | Measured, single case | Planning on the strongest model is cheap |
| CodeRabbit: Fable 5.1 review recall 61% at low vs 57% at high; Opus 5.5 max raises hard-case recall, lowers precision | Measured, vendor | Review effort is not monotonic — tune per mode |
| Aider architect/editor: strong planner + editor beats either alone | Measured (2024) | Supports Fable-plan / Opus-build split |
| Opus 5.5 beats Fable 5.1 on FrontierCode and GDPval-AA | Vendor | Fable-for-spec is plausible, not proven — A/B it |

## 5. Recommended routing defaults

Principle: **one model family for execution, vary effort by role; reserve the
most capable model for the stages whose output everything downstream inherits.**
Same-model siblings share cache; cascades to smaller models fragment it and the
vendor's own measurements favor "capable model, lower effort" over cascades.

| Role / stage | Model | Effort | Rationale |
|---|---|---|---|
| Main thread — build, ship, review, general | `opus` (5.5) | `xhigh` | Long-horizon (>30 min) agentic coding — matches effort-table definition; current baseline |
| `/r-spec`, `/r-plan` sessions; `rdf-planner` | `fable` (5.1) | `high` | Long deliverables; Fable guidance: `high` over `xhigh` for documents; +2.5–9% cost |
| `rdf-engineer` | `opus` | `xhigh` | Implementation quality is the product |
| `rdf-reviewer` sentinel | `opus` | `xhigh` | Post-impl defect finding |
| `rdf-reviewer` challenge | `opus` (was sonnet) | `high` | Removes the model switch; review effort is non-monotonic |
| `rdf-dispatcher` | `opus` (was sonnet) | `high` | Gate decisions; orchestration, not authoring |
| `rdf-qa`, `rdf-uat` | `opus` (qa/uat were sonnet) | `medium` | Scoped mechanical verification — "such as subagents" |
| Docs/focused engineer phases | `opus` (was sonnet) | `medium` → escalate on failure | Replaces model downgrade with effort downgrade |

Every non-default effort is explicit in frontmatter so behavior no longer
depends on the user's session effort (and the Opus 5.5 trap). The `xhigh`
settings are the no-regression starting point; Option 2 measures them and Option
5 steps roles down only where contracts hold.

## 6. Product options

### 1. Role-based model & effort profile (new; small–medium; risk low)
`agent-meta.json` gains per-role `effort` and a capability class
(`execution|planning`) instead of vendor names in canonical; the CC adapter emits
`model:` + `effort:`; the seven hardcoded `model: "sonnet"` sites (`dispatcher.md`
264/265/281, `r-spec.md` 558, `r-plan.md` 502, `r-review.md` 103; `r-sync.md` 128
is illustrative) become role policy. Spec/plan on Fable is delivered at the
*session* boundary (skill `model:` is one-turn only): `/r-start`, `/r-save`
handoff and `/r-spec`/`/r-plan` preambles name the stage's launch command
(`claude --model fable`), and `/r-plan` may dispatch plan authoring to
`rdf-planner`. New `rdf doctor` check: warn when Opus 5.5 would run without an
explicit effort (legacy top-level `effortLevel` only) and print the
`modelSettings` fix — never write user settings. Codex: emit role effort into
`.codex/agents/rdf-*.toml` without pinning a model; Antigravity: document
session-level effort. Contract tests pin the emitted frontmatter.

### 2. Token & cost telemetry — `rdf tokens` (the 09-10 "E", corrected; small; risk none)
Transcript reader with `message.id` dedup; cost by model / agent type / effort
(`effort`, `perTurnEffort`, `thinking_tokens` are already recorded); cache-hit
and cache-write share; boot cost per dispatch; **cost per completed phase** as
the headline metric (not tokens). Feeds `/r-save` session log and a `/r-ship`
regression line. Prototype exists (`/tmp/tokval.*`, Python) — port to bash+jq or
accept a Python dependency (decision). Prerequisite for claiming any saving.

### 3. Subagent onboarding diet (09-10 "B", now platform-backed; medium; risk low–medium)
`omitClaudeMd: true` on rdf-* agents (~10.5 K fewer boot tokens per dispatch,
and cache writes are 25% of spend); governance and conventions passed by value
in the dispatch payload (phase excerpt, cited spec sections, conventions digest);
`skills:` preload instead of "read reference X"; forbid full plan/spec reads;
code-map before reading large files; ≤2 K-token return contract. Probe first:
whether `omitClaudeMd` also drops auto-memory, and whether governance covers
every workspace rule the engineer needs. Expected subagent spend −20–30%.

### 4. Stage-bounded sessions (09-10 "A" + Fable routing; medium; risk medium)
One pipeline stage per session with handoff: spec/plan session on Fable,
build/ship on Opus — the same boundary that delivers Option 1's routing bounds
context. Budget governor: `CLAUDE_CODE_AUTO_COMPACT_WINDOW` plus
`check-context.sh` recalibrated and wired to emit a handoff directive at ~60%
of budget; "Compact instructions" naming what must survive. 64% of RDF turns
exceed 200 K and cache reads are 60% of spend; expected main-thread −30–45%.
Counter-evidence to weigh: Fable 5.1 guide says compacting early for cost "may
no longer be the right tradeoff" — pilot on one real plan before default-on.

### 5. Effort ladder in `/r-build` (new; medium; risk medium)
Focused/docs phases start at `medium`; a failed gate re-dispatches the phase one
effort level higher (vendor-measured: same pass rate at about half cost); for
small dependent chains, collapse gates the tier system does not already remove.
Needs Option 2 to verify; contract tests pin the escalation.

### 6. Lean plans (new; medium; risk medium — doctrine change)
Plans carry interfaces, tests and acceptance, not implementation bodies. Plans
are 45–109 KB and were re-read up to 16× each; current guidance says
over-prescriptive prompts degrade Fable/Opus 5.5 output. Conflicts with
`/r-plan` quality criterion 1 ("steps have exact code blocks") — A/B on one plan
before changing doctrine.

### 7. Tool-output discipline (09-10 "F"; small; risk low)
`BASH_MAX_OUTPUT_LENGTH` back toward the 30 K default (overflow goes to file);
PostToolUse coaching on outputs > 8 KB; deny binary-asset reads; extend
full-read advisories to Bash `cat`/`sed` of large files. Truncate-to-file only —
no output rewriting (measured negative).

### 8. Skill surface + prompt audit (09-10 "C" / roadmap item 3; medium; risk low)
`disable-model-invocation` on user-only skills; prune bodies; plus a
`/claude-api prompt-audit` pass over `canonical/` for instructions written for
older models ("think carefully", "show your reasoning" — the latter can trigger
`reasoning_extraction` refusals on Fable). Token effect modest; quality effect is
the point.

### Not recommended
Blanket `xhigh` on every subagent; Sonnet/Haiku cascades for cost (fragment cache,
vendor data favors capable-model-lower-effort); the advisor tool (API-level, Opus
5.5 not yet listed); terse/compression proxies; early compaction purely for cost;
hardcoding vendor model names in canonical.

## 7. Recommended sequencing

1. **Spec A — Routing + Telemetry:** Options 1 + 2 (+ 7's env default). Timely
   (Opus 5.5 launched 2026-09-22; the effort trap hits users now), small, high
   confidence, and it builds the instrument everything else is measured with.
2. **Spec B — Context Economy:** Options 3 + 4 (+ 8), measured by Option 2.
3. **Experiments gated on Spec A data:** Options 5 and 6, each with an A/B on a
   real plan before any default changes.

## 8. Open questions for `/r-spec`

1. Effort policy: role table in §5 vs blanket `xhigh`?
2. Fable effort for spec/plan: `high` (vendor guidance) or `xhigh`?
3. `/r-plan` authoring: stay inline in a Fable session, or dispatch to `rdf-planner`?
4. Telemetry implementation: bash+jq port or Python dependency?
5. `omitClaudeMd` rollout: all rdf-* agents, or read-only agents first?
6. Codex parity: emit `.codex/agents/*.toml` now or defer?

## 9. Sources

Internal: dedup re-measurement 2026-09-23 (`/tmp/tokval.LAjMpd/`), agent-meta
and canonical greps, `~/.claude/settings.json`, `~/.codex/models_cache.json`.
Platform (fetched 2026-09-23): code.claude.com/docs/en/{model-config,
sub-agents, skills, settings-reference, workflows, changelog};
platform.claude.com/docs/en/build-with-claude/{effort,
prompt-engineering/prompting-claude-opus-5-5,
prompt-engineering/prompting-claude-fable-5-1};
platform.claude.com/docs/en/about-claude/models/optimizing-for-cost-and-intelligence.
External (reported by research pass, not re-fetched): arXiv 2607.12161,
2609.20804, 2607.02436; blog.fsck.com Superpowers 6; coderabbit.ai Fable 5.1 and
Opus 5.5 reviews; anthropic.com/engineering/harness-design-long-running-apps;
aider.chat architect; ampcode.com/models; cursor.com/blog/router;
learn.chatgpt.com Codex config/subagents/skills; antigravity.google/docs/subagents.
