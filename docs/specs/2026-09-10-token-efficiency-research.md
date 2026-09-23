# Token Efficiency — Research and Product Options

**Date:** 2026-09-10 · **Status:** research (input to `/r-spec`) · **Baseline:** RDF 3.7.0 @ 55e8473, Claude Code 2.1.267

## 1. Question

What does RDF do today for token and context efficiency, what do peer
frameworks and the Claude Code platform do, and which product options would
materially cut token spend without eroding outcome quality?

## 2. Method

1. Internal inventory of every RDF mechanism that touches context (Explore
   pass over `canonical/`, `state/`, `adapters/`, `profiles/`, tests).
2. Transcript mining of real sessions in `~/.claude/projects/` (last 60 days):
   14 main RDF sessions, 155 RDF subagent transcripts, plus the heaviest
   pipeline consumer (glasswell) as a cross-check. Usage fields
   (`input`, `cache_creation`, `cache_read`, `output`) per assistant turn;
   tool-result bytes attributed to tool name and file path.
3. A live probe subagent (haiku, no tools) to confirm what custom subagents
   inherit.
4. Two external research passes: Claude Code platform mechanics (primary
   Anthropic sources) and peer frameworks / published measurements.

Token counts from transcripts are exact API figures. File sizes use the
bytes/4 heuristic that `rdf-overhead.sh` already uses.

## 3. Findings — measured on this install

### 3.1 Context depth is the dominant cost

| RDF main sessions, 60 days (n=14, 3,988 turns) | Value |
|---|---|
| Total input tokens (all classes) | 1.07 B |
| Cache-read share | 97% |
| Median context per turn | 262 K |
| p90 / p99 / max context per turn | 446 K / 631 K / 675 K |
| Turns over 200 K / over 400 K | 63% / 19% |
| Compaction events observed | 1 |
| First-turn cache write (boot system prompt) | median 27.8 K, avg 26 K |

The account runs `opus[1m]`. Native-1M models auto-compact at about 967 K
by default, so compaction never fires and nothing bounds context growth.
Every turn re-reads the whole prefix at cache price; a 400 K turn costs four
times a 100 K turn. The PreCompact snapshot hook is wired but has effectively
never run. `check-context.sh` (Stop-hook governor) exists in canonical but is
not wired, and hardcodes a 200 K window.

### 3.2 Subagents cost as much as the main thread, and far more in pipelines

| Scope, 60 days | Turns | Input tokens | Avg ctx/turn |
|---|---|---|---|
| RDF main | 3,988 | 1.07 B | 269 K |
| RDF subagents (155) | 8,496 | 1.02 B | 120 K |
| glasswell main | 1,724 | 0.48 B | 278 K |
| glasswell subagents | 108,905 | 22.6 B | 207 K |

RDF subagent spend by type (mapped from `Agent` calls): dispatcher 508 M
(23 runs, 154 turns avg), reviewer 410 M (46 runs), engineer 398 M (33 runs),
planner 168 M (3 runs at 258 K ctx/turn), qa 79 M. In glasswell, engineers
averaged 344 turns at 256 K context each.

### 3.3 Every custom subagent boots with ~25 K tokens it did not ask for

First-turn cache write per dispatch: rdf-* agents 20–24 K; built-in Explore
10.8 K. A no-tool haiku probe consumed 25.3 K tokens total and confirmed it
inherited the global, workspace and project CLAUDE.md, MEMORY.md and the full
skill listing (about 50 entries), but not the lessons index (SessionStart
hooks do not run for subagents). Platform docs confirm: custom subagents load
"every level of the CLAUDE.md hierarchy"; only Explore/Plan skip it. The
three CLAUDE.md layers plus MEMORY.md are 46.6 KB (~10.4 K tokens).

Agents are then instructed to read governance again
(`engineer.md:14-16`, `qa.md:13-15`, `reviewer.md:300`): CLAUDE.md was
re-read 63 times and `canonical/agents/*` 135 times by subagents.

### 3.4 Onboarding, not work, is where subagents read

| RDF subagent transcripts, 60 days | Value |
|---|---|
| Tool-result bytes in first 10 turns | 9.6 MB (43% of 22.4 MB) |
| Reads of plan / spec / governance / agent / reference / work-output | 889 (6.6 MB, 33% of all tool-result bytes) |
| Plan reads | 299 × avg 11.6 KB = 3.5 MB |
| Spec reads | 223 × avg 10 KB = 2.2 MB |
| First plan read occurs at turn | ~6 of ~54 |
| Turns the plan is then carried | ~48 |

Plan files are 45–109 KB; design specs 55–60 KB. The dispatcher already
extracts phase scope (`rdf_parse_phase_scope`) but hands the engineer the plan
path, and the engineer reads the whole plan and often the whole spec.

### 3.5 Read discipline

1,050 Read calls in RDF (main + sub) totalled 12.7 MB; 549 (52%) were full
reads with no offset/limit. `adapters/claude-code/adapter.sh` was read 56×,
`lib/cmd/doctor.sh` 52×. Two image assets (`demo.gif`, `social-preview.png`)
contributed 2.5 MB. Of 6,985 Bash results, 212 exceeded 8 KB and summed to
2.8 MB. `BASH_MAX_OUTPUT_LENGTH` is set to 128,000 (platform default 30,000;
overflow is saved to file either way).

### 3.6 Command surface vs. usage

| 60 days, all projects | Invocations |
|---|---|
| `/r-start` + `/r-save` | 120 |
| All other 35 commands combined | ~50 |
| `/r-spec` `/r-plan` `/r-build` `/r-ship` `/r-vpe` | 4–9 each |

37 canonical commands, 292 KB of body (r-init 28 KB, r-plan 25 KB, r-spec
25 KB; dispatcher agent 24 KB). Skill listing ≈ 1.1 K tokens always loaded,
agents ≈ 0.3 K — neither counted by `rdf-overhead.sh`, whose published
"~0.1 K default" is the lessons index only. No skill uses
`disable-model-invocation`; none uses `context: fork`. Invoked skill bodies
stay in context for the rest of the session (start+save ≈ 6 K tokens carried
~285 turns per session).

### 3.7 What RDF already does well (keep)

- Dispatch payload is paths + metadata, results go to `.rdf/work-output/`
  files, not inline (`r-build.md:180-202`, `dispatcher.md:527-530`).
- `reference/` files are linked, never eagerly read; tiers remove whole gate
  passes; simplicity-budget doctrine names surface as cost.
- Lessons ID-index at 400 B; MEMORY.md 200-line cap with auto-compact
  preview; session-end capture is a zero-token file write.
- `/r-util-code-map` (70–85% cheaper than full reads) exists but is wired
  only into `/r-audit`, `/r-refresh`, `/r-util-code-modernize` — not into
  the engineer/reviewer/qa agents that do the reading.
- `rotate-work-output.sh` exists but nothing invokes it.
- 97% cache-hit rate: prefix layout is already sound. Cache writes are 3% of
  input; the lever is bytes carried, not cache misses.

## 4. Findings — external, validated

### 4.1 Platform (Anthropic primary sources)

- Custom subagents inherit the full CLAUDE.md hierarchy; Explore/Plan do
  not. Only the subagent's final text returns to the parent. A `fork`
  subagent reads the parent's cache; a custom one starts cold.
- Skills: listing = name + description for every skill, budget 1% of the
  context window (8,000-char fallback), 1,536-char per-entry cap, least-used
  descriptions dropped first when over budget. `disable-model-invocation:
  true` removes the description from context entirely. After compaction the
  most recent invocation of each skill is re-attached, first 5,000 tokens
  each, 25,000 shared. `/skill-doctor` (2.1.261+) reports per-skill cost and
  usage.
- CLAUDE.md: "target under 200 lines"; `@import` does not reduce context;
  HTML comments are stripped before injection; delivered as a user message
  after the system prompt.
- Compaction: `/autocompact 500k` or `CLAUDE_CODE_AUTO_COMPACT_WINDOW`
  (100 K–1 M) sets the ceiling; `CLAUDE_AUTOCOMPACT_PCT_OVERRIDE` applies to
  subagents too. Tool outputs are cleared first, then summarized. A
  `SessionStart` hook matched to source `compact` can re-inject state; other
  hook output is summarized away. A "Compact instructions" section in
  CLAUDE.md steers the summary.
- `model:` or `effort:` on a main-conversation skill invalidates the cache
  for that turn; put them on the subagent instead. Subagent cache TTL is 5 m
  unless `subagentPromptCacheTtl: 1h`.
- Workflow tool: intermediate results stay in script variables; same-prefix
  siblings are staggered 5 s so they share cache.
- Anthropic's multi-agent post: agents ≈ 4× chat tokens, multi-agent ≈ 15×;
  token usage explains 80% of performance variance. Their Claude-5 system
  prompt cut of >80% reported no measurable coding-eval loss (internal,
  unpublished).
- Contested: the claim that long CLAUDE.md reduces adherence. Anthropic docs
  assert it; a 1,650-session factorial study (arXiv 2605.10039) found no
  effect of size 25–500 lines but a 5.6%/step compliance decay with session
  length. Both agree the cost of length is context, and the cost of session
  length is adherence.

### 4.2 Peer frameworks and published measurements

| Technique | Evidence | Verdict for RDF |
|---|---|---|
| Mask/elide old tool observations (SWE-agent, OpenHands, OpenCode, Goose) | Measured, 3 independent: ~2× cost cut at equal or better solve rate (JetBrains NeurIPS'25) | Platform does tool-result clearing at compaction only; RDF can force the boundary via budget + handoff |
| Cache-stable prefix, volatile content last | Measured in production (7%→84% hit, −59% cost) | Already at 97%; low marginal value here |
| Skill/rule body pruning with real routing descriptions (SkillReducer, 600 skills) | Measured: −39% body, −48% description, +2.8% quality | Directly applicable to 37 SKILL.md + 6 agents |
| Tool-schema tiering (Task Master 36 tools ≈ 21 K; serena-slim −50%) | Measured token counts | No MCP here; agent `tools:` allowlists are the analogue |
| Subtask in isolated context, summary-only return (Roo, Amp, Devin) | Consistent, unmeasured | Already RDF's model; enforce a return-size contract |
| Handoff over recursive compaction (Amp `/handoff`, Cline `/newtask`) | Vendor + OpenAI internal report via Amp | Fits `/r-save` + session-start re-inject |
| Head/tail truncation + recovery coaching (mini-SWE-agent 10 K chars) | Measured ablation | PostToolUse hook, low risk |
| Terse output styles (caveman) | Measured A/B: −8.5% output, cost ≈ −10% | Not worth a product |
| Bash-output filter proxy (RTK) | Measured A/B: +7.6% cost | Do not adopt |
| SuperClaude `--uc`, claude-flow "30–80%" | No methodology; audit found net overhead | Do not adopt |
| LLMLingua-style lossy compression | Mixed; dangerous for code | Do not adopt |
| Doc sharding (BMAD) | Deprecated by authors | Superseded by subagents |
| Context rot (Chroma, 18 models; Liu et al.) | Measured: focused ~300 tokens beats full 113 K on every model | Motivates bounding context, not just cost |

## 5. Product options

Each is spec-able on its own. Impact ranges are derived from §3 and are
estimates until Option E measures them.

### E. Token telemetry and budget gate — the enabler
Replace the bytes/4 "0.1 K" story with actuals from transcripts:
`state/rdf-tokens.sh` (boot cost, p50/p90 context, per-dispatch cost by agent
type, onboarding share, full-read %, top re-read files, cache-hit %) fed into
the `/r-save` session log and a `/r-ship` regression line; README publishes
honest always-on (listing + agents + lessons ≈ 1.4 K) and per-dispatch
(~25 K) figures; `tests/overhead.bats` extended. Prerequisite for claiming any
saving from A–D. Effort: small. Risk: none.

### A. Bounded sessions — context budget governor
Declare a working-context budget (e.g., 150–200 K) independent of the 1 M
window. Enforce with: (1) `CLAUDE_CODE_AUTO_COMPACT_WINDOW` set by deploy as
the hard ceiling; (2) the existing `check-context.sh` recalibrated to the
budget and wired as a Stop/UserPromptSubmit hook that at ~60% emits a
handoff directive (`/r-save` handoff → fresh session), preferring handoff
over recursive compaction; (3) a generated "Compact instructions" block naming
what must survive (plan position, modified files, test command, open
findings); (4) apply the same budget to long-running subagents
(`CLAUDE_AUTOCOMPACT_PCT_OVERRIDE` reaches them). Expected: main-thread input
tokens −35–45% (p50 262 K → ≤150 K working set, minus handoff re-read cost);
quality expected to rise per context-rot evidence. Effort: medium. Risk:
medium (handoff fidelity; one A/B on a real plan before default-on).

### B. Dispatch by value — subagent onboarding diet
The dispatcher passes the phase excerpt (already parsed), acceptance
criteria, file list and the spec sections the phase cites, and forbids
full-plan/full-spec reads; engineer/qa/reviewer prompts drop "read governance
index + conventions + constraints + anti-patterns" because the CLAUDE.md
hierarchy is already in their system prompt (verified §3.3); `code-map` becomes
mandatory before reading any file over 500 lines in all three agents; result
files get a size ceiling (e.g., ≤8 KB) and a ≤2 K-token return summary;
`rotate-work-output.sh` is wired into `/r-save`. Expected: subagent input
tokens −20–30% (plan+spec reads are 28% of subagent tool-result bytes, carried
~48 turns; redundant governance reads another few %). Effort: medium. Risk:
low (the excerpt is already computed; add a "request more context" escape
hatch).

### C. Right-size the skill surface (roadmap item 3, now evidenced)
`disable-model-invocation: true` on user-only lifecycle and utility skills
(start, save, status, init, mode, tasks, sync, most `r-util-*`) so their
descriptions leave the listing; fold start/save bookkeeping into hooks; retire
commands with zero invocations in 60 days; prune bodies to <5 K tokens with
critical instructions in the first 5 K (compaction re-attach keeps the head)
and move the rest to `reference/`; dedupe the 32 `rdf-bus` prose blocks and
9 crash-safety sections; write routing descriptions per SkillReducer. Target
~20 commands. Expected: always-on 1.1 K → ~0.3 K per session and per
subagent boot; invoked bodies 20–28 KB → ~10 KB; token effect modest
(1–3%), quality and maintainability effect larger. Effort: medium. Risk: low.

### F. Tool-output discipline
Revert `BASH_MAX_OUTPUT_LENGTH` toward the 30 K default (overflow goes to
file); PostToolUse hook that on outputs >8 KB appends recovery coaching
(head/tail/grep, redirect to file) — mini-SWE-agent's measured-safe pattern;
PreToolUse deny on Read of binary assets (`*.gif`, `*.png`, `*.jpg`) unless
explicitly requested; advisory on full reads of files >5 K tokens without
offset/limit. Expected: −5–10% of tool-result bytes. Effort: small. Risk:
low. Explicitly not RTK-style rewriting (measured negative).

### D. Cache-aware dispatch (small, fold into B)
Read-only discovery via Explore (skips CLAUDE.md, 10.8 K boot vs 24 K);
`model: haiku` where quality allows (qa-lite, uat); `subagentPromptCacheTtl:
1h` only if measured inter-dispatch gaps exceed 5 min; keep same-type
siblings identical in model/tools so they share prefix; volatile fields
(session IDs, timestamps) last in payloads. Cache writes are 3% of input
today, so the ceiling is low; the Explore/haiku swap is the real saving.

### G. Workflow-backed `/r-build` (roadmap D1) — token lens
Already a gated spike. The token evidence strengthens it: intermediate
results stay out of context, same-prefix siblings share cache, summary-only
returns. Keep as its own track; B's payload contract is a prerequisite it can
reuse.

### Not recommended
Symbol/terse compression modes, Bash-output rewriting proxies, lossy prompt
compression, doc sharding, blanket 1 h subagent TTL, raising
`BASH_MAX_OUTPUT_LENGTH` further.

## 6. Recommended bundle

One minor ("Context Economy"): **E → B → A → F**, with **C** folded in as
the roadmap item it already is, **D** absorbed into B, **G** unchanged on its
track. E first so every later phase reports a measured before/after on the
same transcripts. A carries the only medium risk and gets one A/B on a real
plan before default-on.

## 7. Open questions for `/r-spec`

1. Budget value for A: fixed (150 K) or fraction of window with a floor?
2. Handoff-first vs compaction-first at the budget boundary: pilot both on
   the same plan and compare tokens and sentinel findings.
3. Which lifecycle skills stay model-invocable (spec/plan/build/ship/review
   likely yes; everything else likely no)?
4. Does B's phase-excerpt payload need a spec-section resolver, or is
   "sections the phase cites" sufficient?
5. Should E write per-session token facts into the session log JSONL or a
   separate `tokens.jsonl`?

## 8. Sources

Internal: transcript mining scripts run 2026-09-10 (`/tmp/tok-usage.sh`,
`/tmp/agent-attrib.sh`); `state/rdf-overhead.sh` live run; Explore inventory.
Platform: code.claude.com/docs (context-window, skills, memory, sub-agents,
prompt-caching, hooks, env-vars, workflows, costs); anthropic.com/engineering
(effective-context-engineering, writing-tools-for-agents,
multi-agent-research-system, advanced-tool-use); claude.com/blog (prompt
caching is everything; new rules of context engineering; steering).
External: arXiv 2508.21433 (JetBrains observation masking), 2603.29919
(SkillReducer), 2605.10039 (CLAUDE.md factorial), 2507.11538, 2405.15793
(SWE-agent); Chroma context-rot report; JetBrains caveman and RTK A/Bs;
OpenHands condenser blog; github.com/anthropics/claude-code#74318 (subagent
cold start); Amp handoff; Manus context engineering; SuperClaude #286;
claude-flow audit gist.
