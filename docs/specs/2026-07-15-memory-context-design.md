# RDF 3.4 "Memory & Context" — Design Spec

Date: 2026-07-15
Status: draft
Pipeline: spec → plan → build → ship

## 1. Problem Statement

RDF 3.3 ships zero-effort memory promises that are not actually zero-effort,
and a context-thrift story that is measured but never published. Six gaps,
verified against current platform docs (code.claude.com — hooks, memory,
compaction) and the current tree (HEAD 932ed6a):

1. **Memory capture is manual and slow.** `/r-save`
   (`canonical/commands/r-save.md`) is an 8-phase serial protocol that
   re-runs `rdf-state.sh --full`, walks git log, syncs the plan, syncs
   MEMORY.md, and generates an insight — all on the main thread, all only
   when the user remembers to invoke it. If the session ends without
   `/r-save`, the session-log journal and insight are lost. There is no
   hook capturing session-end state today: `hooks.json` has PreToolUse,
   PostToolUse, PreCompact (prompt), SubagentStop, and statusLine — **no
   SessionEnd, no SessionStart**.

2. **Thresholds warn but never act.** `/r-save` §8 and `/r-start` §Warnings
   emit `⚠ MEMORY.md at N/200` and `⚠ Context at ~N%` as passive text. The
   user must notice, then manually run `/r-util-mem-compact` or start a
   fresh session. The threshold logic already exists (≥180 lines, >60%
   context) but stops at rendering a warning.

3. **Lessons load whole or not at all.** `~/.rdf/lessons-learned.md`
   (36 entries, 50 cap) is referenced from CLAUDE.md and read in full when
   an agent decides it is relevant — an all-or-nothing load. There is no
   compact index that lets an agent see *what lessons exist* cheaply and
   fetch only the relevant body. `/r-start` injects the last 5 insights but
   not a lessons overview.

4. **No consolidation / contradiction-prune.** `lessons-learned.md` and
   `insights.jsonl` accumulate by append (insights capped at 30 by line
   trim; lessons capped at 50 by warning only). Duplicate and *contradictory*
   entries survive indefinitely — "error crystallization": a wrong lesson,
   once written, is reinforced every session. No dedup pass exists.
   `/r-util-mem-compact` only compacts project MEMORY.md, not the global
   `~/.rdf/` corpus.

5. **Governance is inert and unscoped.** `cc_generate_governance`
   (`adapters/claude-code/adapter.sh:177`) copies every active profile's
   `governance-template.md` to `output/governance/`, deployed to
   `~/.claude/governance/` — a location Claude Code does not auto-load.
   Agents read it on demand. There is no `.claude/rules/*.md` emission with
   `paths:` frontmatter, so a Python project pays nothing for auto-active
   Python governance, and a mixed repo cannot load only the slice that
   matches the file being edited.

6. **Context cost is measured but unpublished; no minimal profile.**
   `state/context-audit.sh` (446 lines) computes boot cost, but RDF's
   *own* per-session token overhead is never isolated or published in
   README/docs, so a prospective adopter cannot answer "what does RDF cost
   me per session?". And there is no minimal deployment: every install
   ships all 37 commands, 6 agents, 12 scripts, hooks, and full governance.
   The GSD precedent (12,000 → 700 always-loaded tokens) has no RDF analog.

**Platform-fact re-triage (native memory coexistence).** Native auto-memory
is ON by default and loads the first 200 lines / 25 KB of
`~/.claude/projects/<slug>/memory/MEMORY.md` on every session, re-injecting
from disk after compaction. RDF must build the **delta**, not a parallel
memory system. This spec draws the division of labor explicitly (§4.5) and
does NOT reimplement conversational memory.

## 2. Goals

Numbered, measurable, pass/fail verifiable.

1. A `SessionEnd` hook (`session-end-capture.sh`) **appends** a deterministic
   entry (`insight: null`) to `.rdf/work-output/session-log.jsonl` — the
   journal `rdf-state.sh`/`/r-start` already read (`rdf-state.sh:252`,
   `tail -1`) — via a single O_APPEND write, AND writes a
   `session-end-<id>.json` cache for `/r-save` enrichment, on session
   termination (`clear|logout|prompt_input_exit|other`). The journal is
   populated even when `/r-save` is never invoked (Goal 1 is met because
   `/r-start` reads the appended entry). Uses an inline git-only snapshot
   (branch, short HEAD, dirty count, ISO timestamp — no `rdf-state.sh`
   call), completes within the 5 s budget, always exits 0.
2. `/r-save` does measurably less work at save time — this is NOT framed as
   "near-instant": (a) on a cache hit it SKIPS the redundant
   `rdf-state.sh --full` re-run; (b) the deterministic diff classification
   and log-entry JSON are produced by `rdf-state.sh` (new `diff_categories`
   field), not the model. Measurable acceptance: `rdf-state.sh --full .`
   emits a `diff_categories` object (`jq -e .diff_categories` succeeds), and
   `/r-save` given a present `session-end-<id>.json` cache issues zero
   additional `rdf-state.sh` invocations.
3. Auto-acting thresholds: when MEMORY.md ≥ 180 lines, `/r-save` and
   `/r-start` **run** `/r-util-mem-compact` in preview mode and surface the
   proposed reduction (not just a warning); when estimated context > 60%,
   both surface a concrete next action (fresh session / `/half-clone`) as a
   directive line, not a passive `⚠`.
4. A lessons ID-index (`~/.rdf/lessons-index.md`, ≤ 100 tokens / ≤ 400 bytes)
   is injected at `SessionStart` via `hookSpecificOutput.additionalContext`
   on `startup|clear|compact` (skipped on `resume`); full bodies fetched on
   demand by ID. There is NO subagent guard — the SessionStart `source` enum
   is `startup|resume|clear|compact` (no `subagent` value; the hook fires for
   subagents with no reliable way to distinguish them), so injection is
   accepted in subagent contexts and the ≤ 400 B hard cap bounds the N× cost
   instead. The hook is READ-ONLY (Goal 4b): it never regenerates the index
   or writes `lessons-learned.md` — index build is the single-writer
   responsibility of `/r-save`.
5. `/r-util-mem-compact` gains a lessons/insights consolidation pass:
   deterministic duplicate + contradiction detection over
   `lessons-learned.md` and `insights.jsonl`, gated by the existing
   `y / n / auto` review control (write-quality gate; never silent).
6. `rdf generate claude-code` emits `output/rules/<profile>.md` for each
   **language** profile, carrying `paths:` frontmatter derived from the
   profile's `detect` globs in `registry.json`. Core governance carries no
   `paths:` (never scoped — §4.3 tradeoff). A BATS test asserts each
   language rule has non-empty `paths:` and core has none.
7. A measurement harness (`state/rdf-overhead.sh`) reports RDF's isolated
   always-loaded token overhead as pure JSON, EXCLUDING `hooks.json` bytes
   (runtime config — never enters model context). Because scoped rules are
   opt-in (deploy default-off), the DEFAULT-deploy figure and the `--rules`
   figure are published SEPARATELY in README, each guarded against drift by
   BATS.
8. An `rdf-lite` minimal deployment (`rdf generate claude-code --lite`)
   produces an always-loaded footprint of ≤ 1,000 tokens (target ~700):
   condensed core governance only, lifecycle commands only, no hooks/
   statusline, language governance scoped via Goal 6. Measured by Goal 7's
   harness.
9. `rdf doctor` reports 0 FAIL after this change on a fresh deploy;
   `make -C tests test` is green; native auto-memory behavior is unchanged
   (RDF writes no file into `~/.claude/projects/<slug>/memory/` that it did
   not already write).

## 3. Non-Goals (Simplicity Budget — per scope item, what we are NOT building)

Per RDF 3.2.0 T4 simplicity-budget doctrine, each scope item names its
explicit exclusions:

- **Item 1 (zero-effort memory):** NOT a per-turn `Stop` hook (loop hazard:
  `stop_hook_active`, 8-block cap). NOT a background daemon or watcher. NOT
  moving insight *generation* into the hook — insight punchlines are model
  work; the hook captures only deterministic state (git/diff/plan). NOT
  auto-running `/r-save` — it stays user-invoked; the hook is a safety net,
  not a replacement.
- **Item 2 (less-work /r-save):** NOT parallelizing the model reasoning.
  NOT removing any /r-save section — the report contract is unchanged. NOT
  auto-executing `mem-compact --apply` (only the preview auto-runs).
- **Item 3 (lessons index):** NOT a vector DB, embeddings, or semantic
  retrieval. NOT an MCP server (claude-mem is external; we emulate its
  ID-fetch *pattern* with a flat text index). NOT changing lessons-learned
  storage format beyond adding stable IDs.
- **Item 4 (consolidation):** NOT an ML dedup engine. NOT cross-project
  lesson federation. NOT silent pruning — every merge/prune passes the
  y/n/auto gate. NOT touching MEMORY.md compaction (already covered).
- **Item 5 (scoped governance / T3):** NOT scoping core/security/commit
  governance (must survive compaction — §4.3). NOT a custom glob engine
  (rely on platform `paths:` matching). NOT nested `CLAUDE.md` (lost on
  compaction, strictly worse than rules). NOT auto-deploying rules to
  `~/.claude/rules/` by default — emission is unconditional, deploy of
  rules is opt-in (via `--lite` or a deploy flag).
- **Item 6 (published cost + rdf-lite):** NOT continuous telemetry, no
  per-user reporting, no dashboard — one measured number + a regeneration
  harness. NOT a new agent set or pipeline for rdf-lite — the 6 agents and
  4 lifecycle verbs are unchanged; lite is a generation/deploy variant that
  strips always-loaded weight, nothing else.
- **Native memory:** NOT reimplementing conversational memory. NOT moving
  RDF's project MEMORY.md out of the native directory (native already loads
  it). NOT writing new files into the native memory dir.

## 4. Architecture

### 4.1 File Map

| File | Action | Est. lines | Purpose |
|------|--------|-----------:|---------|
| `canonical/scripts/session-end-capture.sh` | new | ~70 | SessionEnd hook — deterministic session snapshot to `.rdf/work-output/` |
| `canonical/scripts/session-start-inject.sh` | new | ~55 | SessionStart hook — inject lessons ID-index via additionalContext (guarded) |
| `state/rdf-lessons.sh` | new | ~180 | `index` (build ID-index) + `scan` (dedup/contradiction candidates) subcommands |
| `state/rdf-overhead.sh` | new | ~130 | isolate RDF's per-session always-loaded token overhead → JSON |
| `profiles/lite/governance-lite.md` | new | ~90 | condensed core governance (~700 tokens) for rdf-lite |
| `state/rdf-state.sh` | modified | 341→~375 | add deterministic `diff_categories` field (F6 — model no longer classifies) |
| `tests/governance-contracts.bats` | modified | +~10 | never-scope-core + no-auto-resolve-contradiction contracts (F9) |
| `adapters/claude-code/hooks/hooks.json` | modified | 50→~78 | add matcher-less SessionStart + SessionEnd (on top of 3.3.x) |
| `adapters/claude-code/adapter.sh` | modified | 235→~300 | `cc_generate_rules()`; `--lite` mode in `cc_generate_all` |
| `lib/cmd/generate.sh` | modified | ~150→~165 | `--lite` flag parse + pass-through |
| `lib/cmd/deploy.sh` | modified | ~295→~310 | opt-in `rules/` symlink; `--lite` deploy skips hooks |
| `canonical/commands/r-save.md` | modified | 389→~430 | consume snapshot; background deterministic phases; auto-act thresholds |
| `canonical/commands/r-start.md` | modified | 234→~250 | auto-act thresholds; lessons-index awareness |
| `canonical/commands/r-util-mem-compact.md` | modified | 108→~170 | lessons/insights consolidation pass with y/n/auto gate |
| `canonical/commands/r-context-audit.md` | modified | 174→~185 | surface `rdf_overhead` field + rdf-lite delta |
| `README.md` | modified | ~+18 | published per-session cost; rdf-lite install |
| `docs/memory-context.md` | new | ~120 | native-memory coexistence + division of labor (user-facing) |
| `ROADMAP.md` | modified | ±0 | check off delivered items |
| `tests/memory-context.bats` | new | ~230 | hooks, index, consolidation, rules, overhead, lite |
| `CHANGELOG` / `CHANGELOG.RELEASE` | modified | +entries | 3.4.0 |
| `VERSION` | modified | 1 | 3.4.0 |

Regenerated (committed if the source adapter commits its output — CC output
is local-only via `.git/info/exclude`, so `adapters/claude-code/output/**`
is NOT committed; only regenerated locally): `output/rules/*.md`,
`output/hooks.json`.

### 4.2 Size Comparison

| Surface | Before | After |
|---------|-------:|------:|
| Hook events wired | 4 (+statusLine) | 6 (+SessionStart, +SessionEnd) |
| Hook scripts | 12 | 14 |
| State helpers (`state/*.sh`) | 3 | 5 |
| Adapter output component dirs | agents/commands/scripts/governance | + rules/ |
| Deploy modes | full | full + lite |
| Global `~/.rdf` artifacts | insights, lessons | + lessons-index |
| Commands (top-level) | 37 | 37 (no new command — item 2/4 fold into existing) |

No new top-level command. Item 4 folds into `/r-util-mem-compact`; item 1's
capture is a hook; items 3/6/7 are hooks + state helpers + adapter modes.

### 4.3 Compaction-survival tradeoff (T3, explicit per scope mandate)

Platform fact: after compaction, root `CLAUDE.md` + **unscoped** rules +
native auto-memory re-inject from disk; `paths:`-scoped rules and nested
`CLAUDE.md` are **lost until a matching file is read**. Therefore:

| Governance class | Emission | Rationale |
|------------------|----------|-----------|
| Core (commit protocol, coreutils prefix, security hygiene, `cd` guards) | **unscoped** — no `paths:` | Applies to every file/edit; losing it mid-session risks a convention violation on the very next write. Must survive compaction. |
| Language profiles (python, shell, go, rust, …) | **`paths:`-scoped** from `registry.json` `detect` globs | Re-triggered the instant a source file of that language is read; loss window is self-closing. Safe to scope; saves weight when the language isn't in play. |

Never scope core. This is the single most important T3 invariant and is
enforced by a BATS assertion (Goal 6).

### 4.4 Dependency Tree

```
SessionEnd (platform)   [3.4 adds a matcher-less array entry, on top of 3.3.x]
└── canonical/scripts/session-end-capture.sh
    ├── reads stdin: session_id, trigger, cwd
    ├── inline git-only snapshot (branch, short HEAD, dirty count, ISO ts) — NO rdf-state.sh
    ├── APPENDS one line (insight:null) to .rdf/work-output/session-log.jsonl  (single O_APPEND — read by /r-start)
    └── writes: .rdf/work-output/session-end-<id>.json  (cache consumed by /r-save)

SessionStart (platform)  [3.4 adds a DISTINCT matcher-less entry; 3.3.x owns the matcher:"compact" entry]
└── canonical/scripts/session-start-inject.sh   (READ-ONLY — never writes)
    ├── skip on source=resume; inject on startup|clear|compact (compact re-inject is intended — §5.2)
    ├── reads cached ~/.rdf/lessons-index.md   (NO regeneration — single-writer is /r-save)
    └── emits: {"hookSpecificOutput":{"additionalContext": "<index, <=400B>"}}  (stdout JSON)

/r-save (canonical command)   [single writer of lessons-learned.md + lessons-index.md]
    ├── reads: .rdf/work-output/session-end-<id>.json  (prefer $RDF_SESSION_ID match, else newest unconsumed; skip rdf-state re-run on hit)
    ├── reads rdf-state.sh .diff_categories (deterministic classification — model no longer classifies)
    ├── threshold: MEMORY.md >=180 → invoke /r-util-mem-compact (preview)
    └── on lessons write: state/rdf-lessons.sh index  (rebuild index + backfill IDs, flock-guarded)

/r-util-mem-compact (canonical command)
    ├── existing: project MEMORY.md compaction (unchanged)
    └── NEW: state/rdf-lessons.sh scan → dedup/contradiction candidates
             → y/n/auto gate (reuse /r-save §8 approve control) → apply

rdf generate claude-code [--lite]
└── adapters/claude-code/adapter.sh
    ├── cc_generate_rules      reads registry.json detect globs + profile governance
    │                          → output/rules/<profile>.md (paths: for language, none for core)
    └── --lite: governance = profiles/lite/governance-lite.md; skip hooks; lifecycle commands only

state/rdf-overhead.sh   → JSON {default_boot_tokens, rules_boot_tokens, lite_boot_tokens, breakdown, excluded}
    ├── consumed by: /r-context-audit (default/rules/lite figures; hooks.json under `excluded`)
    ├── consumed by: README publish target (default + --rules separately)
    └── guarded by: tests/memory-context.bats (published default == measured)
```

### 4.5 Native-memory coexistence — division of labor

Verified platform behavior: native auto-memory owns
`~/.claude/projects/<slug>/memory/MEMORY.md` (first 200 lines / 25 KB loaded
every session, topic files on demand, re-injected after compaction).

| Concern | Owner | Location | RDF's role |
|---------|-------|----------|------------|
| Conversational memory (what we discussed) | **Native** | `~/.claude/projects/<slug>/memory/` | none — do not touch |
| Project-state index (version, HEAD, pipeline, phase status) | **RDF content, native loading** | RDF's MEMORY.md already lives where native loads it | RDF owns hygiene (mem-compact, staleness); native owns the free re-inject |
| Cross-session/cross-project lessons | **RDF** | `~/.rdf/lessons-learned.md` (+ `lessons-index.md`) | native memory is per-project — cannot hold cross-project wisdom; RDF owns it |
| Rolling session insights | **RDF** | `~/.rdf/insights.jsonl` | append + cap + consolidate |
| Governance / conventions | **RDF** | `.claude/rules/` (scoped) + project `.rdf/governance/` | RDF emits; platform loads scoped rules |
| Session journal | **RDF** | `.rdf/work-output/session-log.jsonl` | hook + /r-save append |

RDF builds the **delta** — lessons, insights, governance, project-state
hygiene, and the session journal. It delegates conversational memory and
MEMORY.md *loading* to native. This spec adds no file to the native memory
directory.

### 4.6 Dependency Rules

- `canonical/` stays tool-agnostic and frontmatter-free. All Claude-specific
  mechanics (`paths:` frontmatter, `hookSpecificOutput` JSON shape, SessionEnd
  matcher list) live in `adapters/claude-code/` and the hook scripts, never
  in canonical command bodies.
- Hook scripts degrade gracefully without `jq` (parse guarded; on absence,
  emit nothing and exit 0 — never block startup/shutdown).
- State helpers (`state/*.sh`) never source adapters. `rdf-lessons.sh` and
  `rdf-overhead.sh` may source `state/rdf-bus.sh` for session helpers only.
- No hook may exceed its timeout: SessionStart/SessionEnd set an explicit
  short `timeout` (5 s) in `hooks.json` — never rely on the 600 s default.

## 5. File Contents

### 5.1 `canonical/scripts/session-end-capture.sh` (new)

SessionEnd hook. Reads the platform event JSON on stdin (`session_id`,
`trigger`, `cwd`). Takes an **inline git-only snapshot** (branch, short HEAD,
dirty count, ISO timestamp — NO `rdf-state.sh` call, so capture always
finishes inside the 5 s budget, F11). It then does two writes:

1. **APPENDS** one deterministic JSON line (`insight: null`,
   `source: "session-end-hook"`) to `.rdf/work-output/session-log.jsonl` via
   a single `>>` (O_APPEND) — this is the journal `rdf-state.sh:252`
   (`tail -1`) and `/r-start` already read, so the no-`/r-save` case is now
   actually captured (F5). A single short-line append is concurrency-safe.
2. **WRITES** `.rdf/work-output/session-end-<id>.json` — a richer cache
   `/r-save` consumes to enrich (diff summary, plan sync) on the next run.

Contract: exit 0 always; no stdout that could block; jq-optional (parses
stdin with jq when present, else falls back to `cwd=$(pwd)`, `trigger=other`,
and a `date+pid` id); a non-git tree is a clean no-op.

| Behavior | Detail |
|----------|--------|
| Trigger scope | fires on `clear`, `logout`, `prompt_input_exit`, `other` |
| Timeout | 5 s (set in hooks.json); inline git snapshot is well inside budget |
| id fallback | `session_id` absent (Phase-0 Q2) → `$(date +%s)-$$` for the cache filename |
| Failure | any probe error → fall through to exit 0 (`set -uo pipefail`, NOT `-e`) |
| No model work | insight field is null; `/r-save` fills it later |

### 5.2 `canonical/scripts/session-start-inject.sh` (new)

SessionStart hook. Emits the lessons ID-index as
`hookSpecificOutput.additionalContext` on stdout (appended after the prompt
prefix — does not invalidate prompt caching). **READ-ONLY** — it never writes
`lessons-learned.md` or `lessons-index.md` (single-writer is `/r-save`, F7).
Behavior:

- **No subagent guard (F1):** the SessionStart `source` enum is
  `startup|resume|clear|compact` — there is no `subagent` value and the hook
  fires for subagents indistinguishably. Injection is therefore accepted in
  subagent contexts; the ≤ 400 B hard cap bounds the per-spawn cost.
- **Resume skip:** `source=resume` → emit nothing (context is already
  present on resume).
- **Compact re-inject is intended (F12):** on `source=compact` the hook DOES
  inject — compaction drops in-context lessons and re-injecting the tiny
  index restores them (this composes with the 3.3.x `matcher:"compact"`
  context re-injection; the two are distinct array entries — §5.6).
- **Read cached only:** read `~/.rdf/lessons-index.md`; if absent, emit
  nothing (do NOT regenerate — that is `/r-save`'s job).
- **Degrade:** no `jq` / no index → emit nothing, exit 0.

Injected block shape (≤ 100 tokens):

```
RDF lessons available (fetch full text by ID from ~/.rdf/lessons-learned.md):
[W1] worktree agents: designate one owner per shared file before dispatch
[T1] source-refactor: update tests in the same phase or false-green
[R1] treat subagent findings as hypotheses; reproduce before fixing
... (top N by recency/tag, one line each, ID in brackets)
```

### 5.3 `state/rdf-lessons.sh` (new)

Two subcommands, pure deterministic shell (no model calls):

| Subcommand | Output | Logic |
|------------|--------|-------|
| `index` | writes `~/.rdf/lessons-index.md` | assign/read stable `[<Cat><n>]` IDs per lesson (category initial + ordinal), emit `[ID] first-clause` one line per lesson, cap N (default 12), size-cap 400 B. Called ONLY by `/r-save` (single writer, F7) — flock-guarded around the `lessons-learned.md` mutation |
| `scan` | JSON candidates to stdout | token-Jaccard duplicate detection + order-independent polarity-contradiction heuristic — flags only, never mutates |

**Tokenizer + thresholds (computed against `tests/fixtures/lessons/lessons-sample.md`,
not asserted — every number below was run through the actual tokenizer):**
lowercase → split on non-alpha → drop a stopword set
(`the a an to of for and or in on per before at is be`) → sort-unique. Then:

- **Duplicate:** Jaccard = `|A∩B| / |A∪B|` (integer %). Threshold **≥ 50**.
  Fixture dup pair (the two paraphrased worktree bullets) computes to
  **50%** (`6/12`) → flagged. All eight cross-pairs that are NOT the dup
  compute to **0%** → not flagged.
- **Contradiction:** overlap in **[25, 50)** AND **opposing polarity**.
  Polarity is order-independent: bullet has `max` if it matches
  `always|every|full|all|must`, `min` if it matches
  `never|no|not|minimum|only|none`; a pair is opposing when
  `(A.max ∧ B.min) ∨ (A.min ∧ B.max)`. Fixture contradiction pair
  (`always run the full test matrix before every commit` vs
  `never run the full matrix before commit; Debian12 and Rocky9 is the
  minimum`) computes to **36%** overlap (`4/11`) with A.max ∧ B.min → flagged.
  The dup pair (50%) is caught by the duplicate branch first, so it never
  reaches the contradiction branch; the 0%-overlap negatives never enter it.

IDs are stable: category heading initial + insertion ordinal, persisted as an
HTML-comment marker (`<!-- id:W1 -->`) on the bullet at index-build time
(idempotent — re-runs skip already-tagged bullets). `scan` never mutates
files — it only proposes; the gate in `/r-util-mem-compact` decides.

### 5.4 `state/rdf-overhead.sh` (new)

Isolates RDF-owned always-loaded weight from total context weight (context-
audit.sh measures everything; this measures the RDF *delta*). Reuses
context-audit.sh's byte→token heuristic (bytes / 4). **`hooks.json` bytes are
EXCLUDED** (runtime config — never enters model context, F8). Output JSON:

```json
{
  "default_boot_tokens": 0,
  "rules_boot_tokens": 0,
  "lite_boot_tokens": 0,
  "breakdown": {
    "lessons_index": 0,
    "core_governance_rule": 0,
    "scoped_rules_dormant": 0,
    "lite_core_governance": 0
  },
  "excluded": { "hooks_json_runtime_config": 0 },
  "measured_at": "<ISO8601>",
  "commit": "<short-hash>"
}
```

Three figures, because rules deploy is opt-in (default-off, §3):

- `default_boot_tokens` — a DEFAULT deploy loads no rules (governance is
  symlinked to the non-auto-loaded `~/.claude/governance/`); the only RDF
  always-loaded model context is the lessons-index injection. This is the
  headline "full deploy default" number.
- `rules_boot_tokens` — the `--rules` (opt-in) figure: lessons-index +
  unscoped `rules/core.md`. Scoped language rules are counted separately as
  `scoped_rules_dormant` (they load only when a matching file is read).
- `lite_boot_tokens` — lessons-index + condensed `governance-lite.md`.

README publishes `default_boot_tokens` and `rules_boot_tokens` separately
(F8); the BATS drift guard checks the published default against measurement.

### 5.5 `adapters/claude-code/adapter.sh` — `cc_generate_rules()` (new)

Emits `output/rules/<profile>.md` for each active profile.

| Behavior | Detail |
|----------|--------|
| Source | `profiles/<profile>/governance-template.md` (same source as governance) |
| Core | copied to `rules/core.md` with **no** `paths:` frontmatter (always-loaded) |
| Language | copied to `rules/<profile>.md` with `paths:` built from `registry.json` `.profiles.<profile>.detect` (globs joined, `**/` prefixed as needed) |
| Frontmatter | YAML `---\npaths:\n  - "**/*.py"\n  - ...\n---` prepended; canonical body appended verbatim |
| `--lite` | `cc_generate_all` in lite mode: governance replaced by `profiles/lite/governance-lite.md` → `rules/core.md`; language rules still emitted (scoped, dormant); hooks skipped; only lifecycle commands emitted |

Frontmatter is adapter-only — canonical governance templates stay frontmatter-
free (Dependency Rule §4.6).

### 5.6 `adapters/claude-code/hooks/hooks.json` — additions (on top of 3.3.x)

**Composition (F4 — Q1 resolved).** 3.3.x lands TODAY, adding to `hooks.json`:
a PreCompact **command** hook (`precompact-snapshot.sh` →
`~/.rdf/state/handoff/<session_id>.md`, timeout 10) ALONGSIDE the existing
PreCompact **prompt** hook (so PreCompact has two entries, both preserved),
plus a SessionStart `matcher:"compact"` entry (`session-start-context.sh`,
timeout 10). 3.4 edits `hooks.json` **on top of** that version — it must NOT
touch the 3.3.x entries.

3.4 adds:

- A **distinct, matcher-less** SessionStart array entry for
  `session-start-inject.sh` (fires on all sources; lessons-index inject).
  It is a SEPARATE object in the `SessionStart` array — never appended into
  the 3.3.x `matcher:"compact"` entry.
- A matcher-less `SessionEnd` array entry for `session-end-capture.sh`.

```json
"SessionStart": [
  { "matcher": "compact", "hooks": [ { "type": "command", "command": "~/.claude/scripts/session-start-context.sh", "timeout": 10 } ] },   // 3.3.x — untouched
  { "hooks": [ { "type": "command", "command": "~/.claude/scripts/session-start-inject.sh", "timeout": 5 } ] }                             // 3.4 — new, matcher-less
],
"SessionEnd": [
  { "hooks": [ { "type": "command", "command": "~/.claude/scripts/session-end-capture.sh", "timeout": 5 } ] }
]
```

PreCompact (prompt + command, both from 3.3.x) is left byte-identical.

### 5.7 `canonical/commands/r-save.md` + `state/rdf-state.sh` — modifications

- **`rdf-state.sh` gains a `diff_categories` field (F6):** in `--full` mode,
  deterministically classify dirty + recently-changed files by path prefix
  (`canonical/commands`, `canonical/agents`, `lib/cmd`|`bin`, `adapters`,
  `docs/specs`, `*.md`, other) and emit a JSON object of counts. The MODEL no
  longer performs this classification in `/r-save` §1 — it reads
  `.diff_categories` and formats the top-3 summary. This is the substantive
  "less work at save time" change (measurable: `jq -e .diff_categories`).
- **§1 Compute Session Diff — cache selection rule (F5):** prefer the
  SessionEnd cache. Selection is explicit: if `$RDF_SESSION_ID` is set, look
  for `.rdf/work-output/session-end-${RDF_SESSION_ID}.json`; else glob
  `session-end-*.json` and take the newest un-consumed one. On a hit, parse
  it and SKIP the `rdf-state.sh --full` re-run; after consuming, rename it to
  `*.consumed` (mark consumed). Cache absent → run `rdf-state.sh` as today.
- **§3 Sync MEMORY.md — auto-act:** replace the passive "record a warning"
  at ≥180 lines with: "If ≥180 lines, invoke `/r-util-mem-compact` in
  preview mode and include its proposed reduction in the report (§8)."
- **§8 Output Report — thresholds become directives:** the `⚠ MEMORY.md at
  N/200` warning line becomes an action line showing the previewed
  reduction and a one-keystroke apply offer; the `⚠ Context at ~N%` line
  becomes a directive ("Context ~N% — start a fresh session or `/half-clone`
  now") when > 60%.
- **§7 Lessons Learned (single writer, F7):** after appending to
  `lessons-learned.md` (y or auto), run `state/rdf-lessons.sh index` to
  rebuild the ID-index AND backfill any missing `<!-- id -->` markers. This
  is the ONLY place lessons-learned.md / lessons-index.md are written
  programmatically; the SessionStart hook is read-only. `rdf-lessons.sh`
  takes an flock on `lessons-learned.md` so a concurrent
  `/r-util-mem-compact` consolidation cannot interleave.

### 5.8 `canonical/commands/r-start.md` — modifications

- **§Warnings — auto-act:** MEMORY.md ≥180 → run `/r-util-mem-compact`
  preview and show the proposed reduction inline instead of only warning;
  context > 60% → directive line.
- **Note:** the lessons ID-index is injected by the SessionStart hook, not
  by `/r-start` — `/r-start` continues to render insights and adds a single
  line noting "N lessons indexed (fetch by ID)".

### 5.9 `canonical/commands/r-util-mem-compact.md` — consolidation pass (new §)

New scope: `--lessons` (and auto-detected when run with no target and
`~/.rdf/lessons-learned.md` is near cap). Steps:

1. Run `state/rdf-lessons.sh scan` → duplicate + contradiction candidates.
2. Present each candidate under the **existing y/n/auto gate** (reuse the
   exact approve/reject/auto control documented in `/r-save` §8): for each
   proposed merge (dedup) or prune (contradiction), show both entries and
   the proposed resolution; `y` applies, `n` skips, `auto` applies all
   remaining safe merges (contradictions ALWAYS require explicit `y` — never
   auto-resolved, to avoid crystallizing the wrong side).
3. Same for `insights.jsonl` duplicates.
4. NEVER delete without gate approval; NEVER auto-resolve a contradiction.

### 5.10 `profiles/lite/governance-lite.md` (new)

Condensed core governance, ~700 tokens: commit protocol (one line), coreutils
`command` prefix, `cd` guards, security hygiene, the 3-4 highest-value
anti-patterns. A curated distillation of `profiles/core/governance-template.md`
— not a transform; hand-authored to fit the budget. Frontmatter-free
(adapter adds none for core).

## 5b. Examples

### 5b.1 SessionEnd capture (no /r-save run)

```
$ # user closes session via /clear — hook appends to the journal AND writes a cache
$ tail -1 .rdf/work-output/session-log.jsonl
{"timestamp":"2026-07-15T18:20:00Z","head_after":"932ed6a","branch":"main",
 "dirty_files":2,"trigger":"clear","source":"session-end-hook","insight":null}
$ cat .rdf/work-output/session-end-01J....json      # richer cache for /r-save
{"timestamp":"2026-07-15T18:20:00Z","head_after":"932ed6a","branch":"main",
 "dirty_files":2,"trigger":"clear","source":"session-end-hook","insight":null}
```

### 5b.2 SessionStart injection

```
$ echo '{"source":"startup"}' | ~/.claude/scripts/session-start-inject.sh
{"hookSpecificOutput":{"additionalContext":"RDF lessons available (fetch by ID from ~/.rdf/lessons-learned.md):\n[W1] worktree: one owner per shared file before dispatch\n[T1] source-refactor: update tests same phase\n..."}}

$ echo '{"source":"resume"}' | ~/.claude/scripts/session-start-inject.sh
$   # (no output — resume already has context)

$ echo '{"source":"compact"}' | ~/.claude/scripts/session-start-inject.sh
{"hookSpecificOutput":{"additionalContext":"RDF lessons available ..."}}   # re-inject after compaction (intended)
```

There is no subagent example — the `source` enum has no `subagent` value
(F1); subagent spawns receive the same ≤ 400 B injection, which is why the
cap, not a guard, bounds the cost.

### 5b.3 Consolidation gate (numbers computed against the fixture — F2)

```
Duplicate candidate (Jaccard 50%, threshold >=50):
  [W1] designate one owner per shared file before launching parallel agents
  [W2] fanning out parallel agents: pick one owner per shared file at dispatch
Proposed: merge into [W1], drop [W2].
Merge as lesson? y / n / auto

Contradiction candidate (36% overlap in [25,50) + opposing polarity):
  [T2] always run the full test matrix before every commit          (max)
  [T3] never run the full matrix before commit; Debian12 and Rocky9  (min)
       is the minimum
Proposed: keep [T3] (more specific), flag [T2] for review.
Resolve? y / n   (contradictions never auto-resolve — `auto` is ignored here)
```

### 5b.4 Scoped rule output (T3)

`output/rules/python.md`:

```markdown
---
paths:
  - "**/pyproject.toml"
  - "**/requirements.txt"
  - "**/*.py"
---
# Python Governance
...canonical body verbatim...
```

`output/rules/core.md` (no `paths:` — always loaded):

```markdown
# Core Governance
...
```

### 5b.5 Published overhead

```
$ bash rdf/state/rdf-overhead.sh | jq '{default_boot_tokens, rules_boot_tokens, lite_boot_tokens}'
{ "default_boot_tokens": 120, "rules_boot_tokens": 2100, "lite_boot_tokens": 810 }
```

(Illustrative shape, not a committed figure — the build fills real numbers.)
README publishes the DEFAULT figure and the opt-in `--rules` figure
separately: "RDF's default deploy adds ~{X} always-loaded tokens per session
(lessons-index only — governance is read on demand); the opt-in `--rules`
scoped-governance deploy adds ~{Y}; rdf-lite ~{Z}. `hooks.json` is runtime
config and not counted. Measured by `rdf/state/rdf-overhead.sh`, guarded in
CI."

## 6. Conventions

- Hook scripts: `#!/bin/bash`, `set -uo pipefail` (match existing hook
  scripts — NOT `-e`, so a probe failure never aborts the hook), always
  exit 0, guard every `jq`/`command -v` with a same-line comment.
- State helpers: `#!/usr/bin/env bash`, `set -euo pipefail`, `command`-prefixed
  coreutils, `command -v` discovery.
- Lessons ID format: `[<CategoryInitial><ordinal>]` — `W1`, `T2`, `R1`.
  Persisted as `<!-- id:W1 -->` HTML comment on the bullet.
- `paths:` frontmatter: double-quoted glob strings, `**/` prefix for
  extension globs; directory globs (`migrations/`) become `**/migrations/**`.
- All hook/rule mechanics are adapter-side; canonical stays tool-agnostic.

## 7. Interface Contracts

- New hooks: SessionStart (`session-start-inject.sh`), SessionEnd
  (`session-end-capture.sh`) — additive to `hooks.json`; existing hooks
  byte-identical.
- New CLI surface: `rdf generate claude-code --lite` (additive flag);
  `rdf deploy claude-code --lite` (additive); `state/rdf-lessons.sh
  {index,scan}`; `state/rdf-overhead.sh`.
- `/r-util-mem-compact` gains `--lessons` scope (additive; default behavior
  when a target MEMORY.md is specified is unchanged).
- `~/.rdf/lessons-index.md` — new artifact; `~/.rdf/lessons-learned.md`
  gains stable `<!-- id:X -->` markers (backward-compatible; markers are
  comments).
- `rdf-state.sh --full` output gains a `diff_categories` object (ADDITIVE —
  existing fields unchanged; consumers ignore unknown fields).
- No change to: the 6 agents, the 4 lifecycle verbs, existing hook scripts,
  the 3.3.x PreCompact/SessionStart-compact entries, native memory directory
  contents.

## 8. Migration Safety

- **Fresh install:** gains all six items on first `rdf generate claude-code`
  + deploy. rdf-lite via `--lite`.
- **Existing symlink users:** `rdf generate claude-code` adds `output/rules/`
  and the two hook entries; `rdf deploy claude-code` symlinks `rules/` only
  when opted in (default deploy leaves rules un-symlinked → zero behavior
  change until the user chooses scoped governance). Hook additions require
  the user to merge `hooks.json` (deploy already skips hooks.json with a
  manual-merge notice — §deploy L189).
- **lessons-learned.md ID backfill:** first `state/rdf-lessons.sh index`
  run appends `<!-- id:X -->` markers idempotently; a file with no markers
  is upgraded in place; re-runs are no-ops.
- **No native-memory migration:** RDF writes nothing new into the native
  memory directory. Division of labor (§4.5) is documentation + behavior,
  not a file move.
- **Rollback:** remove the two hook entries, delete `rules/`, drop the new
  scripts, revert command edits. `lessons-index.md` and `<!-- id:X -->`
  markers are inert if the tooling is gone. No persistent state to unwind.

## 9. Dead Code and Cleanup

- `rdf_profile_includes()` (`lib/rdf_common.sh:175`) is a dead `return 0`
  stub (v3 dropped profile filtering). New code MUST NOT call it. Not
  removed here (tracked under 3.2 T5 debt) — but `cc_generate_rules` must
  not reintroduce a call to it.
- `canonical/scripts/check-context.sh` is a documented-but-unwired `Stop`
  hook. This spec does NOT wire it (Stop loop hazard). Left as-is (advisory
  install snippet in its header).

## 10a. Test Strategy

New file `tests/memory-context.bats` (harness pattern from
`tests/adapter.bats`, hermetic temp HOME/RDF_HOME):

| Goal | Test file | Test |
|------|-----------|------|
| 1 | memory-context.bats | `@test "session-end-capture appends journal entry + writes cache, exits 0"` (git-repo fixture; assert `tail -1 session-log.jsonl` + `session-end-<id>.json` + exit 0) |
| 1 | memory-context.bats | `@test "session-end-capture is a no-op outside a git repo"` (run in a masked non-git tmp dir; assert exit 0 + no journal write) |
| 2 | memory-context.bats | `@test "rdf-state --full emits diff_categories object"` (real measurement, not prose) |
| 2 | memory-context.bats | `@test "r-save selects session-end cache and skips state re-run"` (structural: doc references `$RDF_SESSION_ID` cache selection) |
| 3 | memory-context.bats | `@test "rdf-lessons index emits <=400 byte ID-index"` |
| 3 | memory-context.bats | `@test "rdf-lessons index assigns stable IDs across two runs"` |
| 3 | memory-context.bats | `@test "session-start-inject injects on startup, skips resume"` (real source enum; no subagent payload) |
| 3 | memory-context.bats | `@test "session-start-inject is read-only (does not write lessons-index.md)"` (F7) |
| 4 | memory-context.bats | `@test "rdf-lessons scan flags the 50% duplicate pair"` |
| 4 | memory-context.bats | `@test "rdf-lessons scan flags the 36% opposing-polarity contradiction"` |
| 5 | memory-context.bats | `@test "core rule has no paths frontmatter; python rule has paths from detect globs"` |
| 5 | memory-context.bats | `@test "generate emits one rule per active profile"` |
| 6 | memory-context.bats | `@test "rdf-overhead emits default/rules/lite figures and excludes hooks.json"` |
| 6 | memory-context.bats | `@test "lite footprint is <=1000 tokens"` |
| 6 | memory-context.bats | `@test "published README default number is within tolerance of measurement"` (drift guard) |
| 4/5 | **governance-contracts.bats** | `@test "consolidation never auto-resolves a contradiction"` (via `_contract` on `commands/r-util-mem-compact.md`) — F9 |
| 5 | **governance-contracts.bats** | `@test "adapter never scopes core governance"` (direct grep on adapter.sh — `_contract` is canonical-only; noted) — F9 |
| 9 | adapter.bats (existing) | green = CC output unchanged for non-rules paths |

Adversarial cases baked into tests: injection accepted-but-capped in subagent
contexts (no fictional guard); contradiction auto-resolve prohibition
(governance-contract); scoped-core prohibition (governance-contract);
degrade-without-jq; read-only SessionStart; non-git-repo capture no-op.

## 10b. Verification Commands

```bash
# Goal 1 — capture hook appends journal + writes cache, exits 0 (in a git repo)
echo '{"session_id":"t","trigger":"clear","cwd":"'"$PWD"'"}' \
  | bash canonical/scripts/session-end-capture.sh; echo "exit=$?"   # expect exit=0
tail -1 .rdf/work-output/session-log.jsonl | jq -e '.insight == null'  # expect true

# Goal 2 — deterministic classification lives in rdf-state.sh
bash state/rdf-state.sh --full . | jq -e '.diff_categories'   # expect an object

# Goal 3 — index size + stability
bash state/rdf-lessons.sh index && wc -c < ~/.rdf/lessons-index.md   # expect <=400
bash state/rdf-lessons.sh index && bash state/rdf-lessons.sh index   # idempotent (no new markers)

# Goal 5 — core unscoped, language scoped
bin/rdf generate claude-code
head -1 adapters/claude-code/output/rules/core.md          # expect NOT '---'
grep -c '^paths:' adapters/claude-code/output/rules/python.md   # expect 1

# Goal 6/7 — overhead (default vs rules vs lite), hooks excluded
bash rdf/state/rdf-overhead.sh | jq '.default_boot_tokens, .rules_boot_tokens, .lite_boot_tokens'
bin/rdf generate claude-code --lite && bash rdf/state/rdf-overhead.sh | jq '.lite_boot_tokens'  # expect <=1000

# Goal 9 — clean
bash bin/rdf doctor 2>&1 | grep -c 'FAIL'      # expect 0
make -C tests test 2>&1 | grep -c '^not ok'    # expect 0
```

## 11. Risks

1. **SessionEnd ordering** — the hook fires on *termination*, after any
   manual `/r-save`. So `/r-save` in the same session cannot consume that
   session's SessionEnd cache. Resolution: the cache is a safety net for the
   *next* session's `/r-start` and for sessions that never run `/r-save`;
   `/r-save` consumes a cache only if one already exists (e.g., from a prior
   `/clear` mid-session). Spec §5.7 states this explicitly. Not a defect —
   the value is capturing sessions that would otherwise be lost.
2. **Scoped-rule compaction loss** — §4.3. Mitigated by never scoping core;
   BATS asserts it. Residual: a language rule is briefly absent post-compact
   until the next matching-file read — acceptable (self-closing window).
3. **SessionStart injection multiplication** — fires for subagents too, and
   the `source` enum has NO `subagent` value, so there is no reliable guard
   (F1). Mitigated instead by the ≤ 400 B hard cap: N subagents × ≤400 B is a
   bounded, small cost. Adversarial test asserts the cap holds and that the
   hook is read-only.
4. **Contradiction auto-resolve = crystallizing the wrong side** — the whole
   point of the gate. Mitigated: contradictions NEVER auto-resolve; only
   safe dedup merges honor `auto`. Enforced by test.
5. **`jq` absent at runtime** — all hooks + state helpers degrade to no-op
   and exit 0. Never block startup/shutdown. (jq is a hard `rdf` CLI dep but
   not guaranteed on every consumer's PATH for hooks.)
6. **rdf-lite drift** — a lite deploy that silently diverges from the
   published token number. Mitigated by Goal 6/7 drift guard test.
7. **Published overhead staleness** — README number rots. Mitigated by the
   BATS drift guard + a `make overhead-doc` regeneration target; optionally
   a CI step.

## 11b. Edge Cases

| Scenario | Expected | Handling |
|----------|----------|----------|
| `/r-save` runs, no prior SessionEnd cache | re-run `rdf-state.sh` as today | §5.7 cache-absent fallback |
| SessionEnd fires with `trigger: logout`, no git repo | no journal write; exit 0 | inline git-check guard (no rdf-state dependency) |
| SessionStart in subagent | same ≤ 400 B injection (no guard — enum has no `subagent`) | 400 B cap bounds cost (F1) |
| SessionStart `source=resume` | no injection | resume skip |
| SessionStart `source=compact` | RE-inject the index (intended) | compaction drops in-context lessons (F12); distinct from 3.3.x compact entry |
| `lessons-learned.md` has zero entries | index empty; injection emits nothing | size guard |
| Two lessons with identical text | scan flags dedup; gate merges on `y`/`auto` | Jaccard=1.0 |
| Contradiction pair | flagged; `auto` does NOT resolve; requires explicit `y` | §5.9 rule |
| Project with only core profile active | `rules/core.md` only, no scoped rules | cc_generate_rules loops active profiles |
| Mixed repo (python+shell) | `rules/core.md` (unscoped) + `rules/python.md` + `rules/shell.md` (scoped) | detect globs per profile |
| `--lite` on a project with language profiles | condensed core (unscoped) + language rules scoped/dormant; hooks skipped | lite mode |
| `hooks.json` already user-merged | deploy skips hooks.json (existing manual-merge notice) | no change |
| No `~/.rdf/` dir | hooks create it or no-op; never error | mkdir -p guard |
| MEMORY.md exactly 180 lines | auto-preview fires (>= threshold) | §5.7 |

## 12. Open Questions (Phase-0 re-triage — one probe)

- **Q1 (SessionStart collision) — RESOLVED by coordinator (F4).** 3.3.x lands
  TODAY: a PreCompact **command** hook (`precompact-snapshot.sh`) alongside
  the existing PreCompact prompt hook, plus a SessionStart `matcher:"compact"`
  entry (`session-start-context.sh`). 3.4 therefore edits `hooks.json` on top
  of that version and adds its lessons-inject as a DISTINCT, matcher-less
  SessionStart array entry — never appended into the 3.3.x compact entry
  (§5.6). No git-probe needed; the composition is fixed.
- **Q2 (SessionEnd matcher/stdin) — remains a cheap platform confirmation.**
  Confirm from code.claude.com hooks docs that (a) SessionEnd fires on the
  `clear` trigger (not only `logout`) — required for the mid-session `/clear`
  capture value — and (b) whether stdin includes `session_id` on all four
  triggers. The hook already falls back to `$(date +%s)-$$` when `session_id`
  is absent, so (b) is non-blocking; (a) determines how often the safety net
  fires. Probe: re-read the SessionEnd reference; record the matcher + stdin
  schema in the plan preamble.

Q2 is not a design blocker (the hook degrades either way). Phase 0 is a single
doc-confirmation step.
