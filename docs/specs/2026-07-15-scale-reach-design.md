# RDF 3.5 "Scale & Reach" — Design Spec

Date: 2026-07-15
Status: draft
Pipeline: spec → plan → build → ship
Composes with: RDF 3.4 "Memory & Context" (designed, not yet built —
`docs/specs/2026-07-15-memory-context-design.md`). 3.5 lands **after** 3.4;
this spec pins every file where 3.4 and 3.5 both write (§4.2).

## 1. Problem Statement

RDF's four-verb pipeline (`/r-spec → /r-plan → /r-build → /r-ship`) applies
one ceremony level to every task. Verified against the current tree
(HEAD 8864309, VERSION 3.3.1):

1. **Enterprise ceremony for a 5-line fix.** A bug fix pays the same price as
   a greenfield subsystem: `/r-spec` runs a 3-phase research dialogue and a
   mandatory challenge review (`r-spec.md:489` — "Dispatch the reviewer agent
   in challenge mode"), `/r-plan` runs a second challenge review
   (`r-plan.md:432` — "### 3.1 Plan Review"), `/r-build` runs per-phase gates
   plus an end-of-plan 3-pass sentinel for any plan ≥ 3 phases
   (`dispatcher.md:362` — "### End-of-Plan Sentinel"). *(Line cites are anchored
   by the quoted text and may drift as 3.4's remaining phases land — grep the
   quoted anchor, not the number.)*
   There is no lighter path. The anti-framework critique ("too much process
   for small work") lands directly here. Kiro answers this with three
   task-class tiers (full-spec / Quick-Plan / Bugfix); RDF has one.

2. **Ambiguity is caught late.** `/r-spec` jumps from Discover
   (`r-spec.md:108`) straight to Brainstorm (`r-spec.md:164`) with no
   structured de-ambiguation of the ask. Underspecified requirements surface
   during design or, worse, during build. Spec Kit added `/clarify` as a
   dedicated de-ambiguation pass precisely for this.

3. **No cross-artifact consistency check.** `/r-build` Section 1
   (`r-build.md:18-46`) validates the plan against `plan-schema.md` in
   isolation — it never checks the plan against the spec that produced it, or
   the phase set against the File Map. A goal dropped between spec and plan, or
   a File-Map file no phase touches, ships silently. Spec Kit added `/analyze`
   for exactly this spec↔plan↔tasks cross-check.

4. **Commands are invisible until memorized.** CC commands are direct-copied
   with no frontmatter (`adapter.sh:118-136`), so they never self-surface on
   intent — a new user must know `/r-spec` exists to use it. Superpowers
   (255k stars) demonstrates that intent-triggered skills beat memorized names
   for adoption.

5. **Specs are write-once, never maintained.** Each release writes a new
   `docs/specs/YYYY-MM-DD-*.md` and abandons it. There is no living
   current-state spec; a newcomer cannot answer "what is the system now?"
   without reading 24 dated design docs. OpenSpec maintains one current-state
   spec and expresses changes as deltas.

6. **Multi-tool parity is partial and drifting.** The 2026 convergence stack —
   AGENTS.md (Linux Foundation, 60k+ repos), the Agent Skills open standard
   (~45 clients incl. Codex + Gemini reading `.agents/skills/`), and MCP — is
   only half-served. RDF emits AGENTS.md (`codex/adapter.sh`,
   `agents-md/adapter.sh`) but **no** `.agents/skills/`. Gemini command TOML
   carries only `{{args}}` with no positional support (`gemini-cli/adapter.sh:115`)
   — an undocumented lossy edge for `/r-build 3` and `/r-plan <path>`. Codex
   emits **no** hooks (`codex/adapter.sh` has no hook function) while CC wires
   several. And the deploy/sync code paths (`lib/cmd/deploy.sh`, `r-sync.md`)
   have **zero** BATS coverage (audit finding M6) despite being the install
   surface every consumer hits. *(Superseded post-probe — see §13.1: the
   Linux-Foundation/AAIF governance attribution is unverified and uncited going
   forward; Gemini CLI → Antigravity CLI is the Agent-Skills client.)*

7. **Cross-session coordination was designed but never shipped.** The
   2026-04-25 concurrent-sessions design specified Wave B (cross-session
   message bus + `/r-msg` + peer-status). Only Wave A landed —
   `state/rdf-bus.sh` (181 lines) ships identity/scoped-filenames/phase-scope
   only; it has **no** bus, status broadcast, or sweeper. `framework.md:171`
   still advertises a phantom `collect-spool.sh` contract that no code
   implements. The user asked for Wave B in April; Wave A's
   real-usage-feedback precondition is now met, so a re-triage is due.

## 2. Goals

Numbered, measurable, pass/fail verifiable. Grouped by the two product
themes and the deferral tail (§7 stages them into releases).

**Theme Scale (3.5.0):**

1. `/r-spec` and `/r-plan` accept an explicit tier flag (`--full` |
   `--quick` | `--bugfix`) AND emit a heuristic tier suggestion the user
   confirms before work begins. The tier is recorded durably as a
   `**Tier:** <value>` marker in the plan preamble and session-scoped in
   `.rdf/active-tier-${RDF_SESSION_ID}`. Measurable: `rdf_active_tier` echoes
   the selected tier; a generated `--quick` plan contains `**Tier:** quick-plan`.
2. Three tiers select ceremony **within** the four verbs — no new top-level
   command: `full` = current pipeline; `quick-plan` = one condensed
   spec+plan artifact, single review, gates capped at sentinel-lite;
   `bugfix` = failing-test-first + fix, Gate 1 + regression-only sentinel-lite,
   no separate spec, no full QA matrix. **Security floor (§4.3):** the cap
   never applies on `scope:sensitive` or security-indicator files — those keep
   Gate 2 + sentinel-full regardless of tier. Measurable: the dispatcher's gate
   selection is capped by tier (a `bugfix` plan never triggers Gate 4/UAT or a
   3-pass sentinel *except* on security-sensitive files); asserted by two
   `governance-contracts.bats` contracts (tier-cap-lowers-only, and
   never-drops-security-on-sensitive).
3. `/r-spec` runs a **Clarify** micro-gate (new Phase 1.5) that interrogates
   the ask for underspecified requirements before Brainstorm, deriving
   questions from the actual input (not a fixed questionnaire), recording
   answers to `spec-progress`. Scaled by tier: skipped for `bugfix`, one-round
   for `quick-plan`, full for `full`. Measurable: `r-spec.md` contains a
   `## Phase 1.5: Clarify` section; a contract asserts it precedes Brainstorm.
4. `/r-build` preflight runs a **Consistency** micro-gate: a deterministic
   `state/rdf-consistency.sh check` that cross-verifies spec↔plan↔tasks —
   every File-Map file is touched by ≥ 1 phase, every phase file is in the File
   Map, phase count matches `**Phases:** N`, and (when a spec exists) every
   spec Goal and every §11b edge case maps to a phase. Emits structured
   findings; structural breaks block, advisory drift warns. Measurable:
   `bash state/rdf-consistency.sh check <plan>` exits 0 on a consistent plan,
   2 on a File-Map/phase mismatch; wired into `r-build.md` Section 1.
5. `/r-ship` folds the shipped plan's outcome into a maintained
   `docs/specs/CURRENT.md` living spec as a dated delta block
   (ADDED / MODIFIED / REMOVED), lightweight and user-approved, skipped for
   `bugfix` tier. Measurable: `docs/specs/CURRENT.md` exists and gains a
   `## <version> — <date>` delta section after a `/r-ship`; a contract asserts
   the fold step is present in `r-ship.md` Stage 3.

**Theme Reach (Wave 2 — `3.6.0` assigned at ship; §13):**

6. `rdf generate` emits `.agents/skills/<command>/SKILL.md` for the lifecycle
   commands from canonical sources, carrying a natural-language `description:`
   trigger (Goal 7's data) so Codex and Antigravity (both Agent-Skills clients;
   Gemini CLI superseded — §13.1) self-surface RDF commands on intent.
   Measurable: a new `agent-skills` generate target produces `SKILL.md` files
   whose frontmatter validates against the Agent-Skills schema (name +
   description); BATS asserts one SKILL per lifecycle command.
7. CC command output gains YAML frontmatter with an intent-trigger
   `description` (authored in adapter metadata, never in canonical bodies).
   Measurable: `output/commands/r-spec.md` begins with `---` and a
   `description:` line; canonical `r-spec.md` still has no frontmatter (a
   contract asserts canonical stays frontmatter-free).
8. The Gemini `{{args}}`-only lossy edge is documented (parity matrix in
   `docs/multi-tool-parity.md`) and the Gemini adapter emits a one-line warning
   in any command TOML whose canonical body references a positional argument.
   Measurable: `docs/multi-tool-parity.md` states the `{{args}}` limitation; the
   adapter emits the warning comment for positional-arg commands.
9. Deploy and sync code paths gain BATS coverage (closes audit M6). Measurable:
   `tests/deploy.bats` covers symlink create/replace/skip/force and the
   hooks.json manual-merge skip; `make -C tests test` runs it green.

**Deferral tail (re-triaged in Phase 0; recommend 3.6 — §7):**

10. Codex hooks intersection (pre-tool/post-tool/session-boundary only),
    per-tool recommended-settings fragments, and the Wave B surviving delta
    are **re-triaged** in a Phase-0 probe; only zero-risk survivors ship in
    3.5 (phantom `collect-spool.sh` contract removed from `framework.md`;
    read-only peer-status line in `/r-status` **iff** the re-triage confirms
    persistent cross-session pain). The remainder is recommended for deferral
    with written rationale (§7, §11).

11. `rdf doctor` reports 0 FAIL after each shipped wave; `make -C tests test`
    green; the four lifecycle verbs, the 6 agents, and native memory behavior
    are unchanged.

## 3. Non-Goals (Simplicity Budget — per item, what we are NOT building)

Per RDF 3.2.0 T4 simplicity-budget doctrine, each scope item names its
explicit exclusions.

- **Item 1 (tiers):** NOT a new top-level command — tier is a flag/marker on
  the existing four verbs. NOT auto-selecting a tier — the heuristic only
  *suggests*; the user always confirms. NOT removing any gate from the `full`
  tier — tiers only *cap* ceremony downward, never invent new gates. NOT a
  per-phase tier — one tier per plan.
- **Item 2 (clarify):** NOT a fixed questionnaire — questions are derived from
  the actual ask. NOT a blocking interrogation for trivial work — `bugfix`
  skips it. NOT a new reviewer dispatch — it is a self-run structured pass
  inside `/r-spec`.
- **Item 3 (consistency):** NOT semantic correctness checking — mechanical
  structural cross-references only. NOT a re-run of the challenge reviewer. NOT
  a hard block on advisory drift — only structural breaks (File-Map/phase
  mismatch, phase-count mismatch) block; goal/edge-case gaps warn.
- **Item 4/6/7 (skills + intent triggers):** NOT converting commands *into*
  skills — commands stay commands; SKILL.md is an *additional* emitted surface
  (the plugin-citizenship spec already ruled "commands stay commands",
  `2026-07-14-...-design.md:65`). NOT MCP server work. NOT emitting skills for
  all 37 commands — lifecycle + high-value utilities only, to bound surface.
- **Item 5 (living specs):** NOT auto-generating the whole spec from source —
  it is a human-readable delta append, not a diff engine. NOT blocking `/r-ship`
  on the fold — it degrades to a skip with a notice. NOT retiring the dated
  design docs — `docs/specs/YYYY-MM-DD-*.md` remain the historical archive.
- **Item 6 (multi-tool parity):** NOT mapping the full Codex/Gemini hook event
  surface — only the intersection RDF actually uses (pre-tool, post-tool,
  session boundary). NOT inventing a settings framework — recommended-settings
  fragments are static, opt-in, and RECOMMENDED-DEFERRED (§7). NOT changing
  canonical command bodies to satisfy any tool — all tool mechanics stay in
  adapters.
- **Item 7 (Wave B):** NOT resurrecting the full 12-primitive design. NOT
  adding `/r-msg` unless the re-triage proves persistent, native-uncovered
  pain (a whole messaging command for a mostly single-operator framework is
  surface RDF should not add speculatively). NOT a background daemon/sweeper —
  recovery stays opportunistic if it ships at all. The default recommendation
  is: ship only the phantom-contract cleanup + an optional read-only peer view;
  defer the bus/msg/sweeper.
- **Item 6b (Antigravity surfaces, added post-probe — §13.7):** NOT building
  Antigravity hooks (`.agents/hooks.json`), subagents, or plugins
  (`~/.gemini/antigravity-cli/plugins/`) — schemas undocumented or churning.
  NOT the Codex `agents/openai.yaml` per-skill metadata (Codex-specific,
  optional, not required for skill consumption). NOT global/user-level
  `~/.agents/skills/` scanning (unverified). NOT the optional AAIF SKILL.md
  fields (`license`, `metadata`, `allowed-tools`). The `.agents/skills/` skills
  surface is emitted ONCE as a shared workspace convention, NEVER duplicated per
  tool. NOT a separate Antigravity generation engine — `rdf generate
  antigravity` is a thin composite over the shared skills + `agents-md` context.
- **Cross-cutting:** NOT touching the files 3.4 owns without composing (§4.2).
  NOT GNU-only flags anywhere (macOS CI). jq-optional on every runtime path.

## 4. Architecture

### 4.1 File Map (all waves)

| File | Action | Wave | Est. lines | Purpose |
|------|--------|------|-----------:|---------|
| `canonical/reference/tiers.md` | new | 1 | ~90 | tier definitions, heuristic signals, per-tier gate caps (single source of truth cited by all verbs) |
| `state/rdf-consistency.sh` | new | 1 | ~150 | deterministic spec↔plan↔tasks cross-check (`check` subcommand) |
| `docs/specs/CURRENT.md` | new | 1 | ~60 | living current-state spec (seed; `/r-ship` appends deltas) |
| `tests/scale-ceremony.bats` | new | 1 | ~240 | tiers, clarify, consistency, living-spec, tier-cap contract |
| `tests/fixtures/tiers/*` | new | 1 | ~40 | consistent, mismatched, comma-list, and extra-goal plan/spec fixtures |
| `tests/Makefile` | modified | 1/2 | +2 | add `scale-ceremony.bats` (+Wave 2 bats) to `test:`/`lint:` lists — **co-edit with 3.4, §4.2** |
| `tests/governance-contracts.bats` | modified | 1 | +~5 | tier-cap-lowers-only, security-floor, living-spec, canonical-frontmatter contracts — **co-edit with 3.4, §4.2** |
| `state/rdf-bus.sh` | modified | 1 | 181→~215 | add `rdf_set_active_tier` + `rdf_active_tier` (parallel to active-plan) |
| `canonical/commands/r-spec.md` | modified | 1 | +~55 | tier selection at entry; Phase 1.5 Clarify micro-gate |
| `canonical/commands/r-plan.md` | modified | 1 | +~50 | tier selection; `**Tier:**` preamble marker; quick/bugfix condensed paths |
| `canonical/commands/r-build.md` | modified | 1 | +~25 | consistency micro-gate in Section 1; `TIER:` in dispatch payload |
| `canonical/commands/r-ship.md` | modified | 1 | +~30 | living-spec fold step (Stage 3e) |
| `canonical/agents/dispatcher.md` | modified | 1 | +~30 | tier cap applied over scope→gate mapping |
| `canonical/reference/plan-schema.md` | modified | 1 | +~30 | Rule 10 (Tier marker, optional) |
| `adapters/agent-skills/adapter.sh` | new | 2 | ~180 | emit `.agents/skills/<cmd>/SKILL.md` from canonical + trigger meta |
| `adapters/agent-skills/skill-meta.json` | new | 2 | ~60 | per-command intent-trigger descriptions (lifecycle set) |
| `docs/multi-tool-parity.md` | new | 2 | ~90 | AGENTS.md + Skills + MCP matrix; Gemini `{{args}}` lossy edge |
| `tests/deploy.bats` | new | 2 | ~120 | deploy symlink + sync BATS coverage (audit M6) |
| `tests/agent-skills.bats` | new | 2 | ~90 | SKILL.md shape + trigger presence |
| `adapters/claude-code/adapter.sh` | modified | 2 | (3.4 base) +~30 | command frontmatter (intent trigger) — **composes on 3.4** |
| `adapters/gemini-cli/adapter.sh` | modified | 2 | +~25 | LEGACY tier: TOML `'''` literal-string fix (15/37) + positional-arg lossy warning — **no per-tool `.agents/skills/`** (shared surface, §13.4) |
| `lib/cmd/doctor.sh` | modified | 2 | +~8 | content-drift: strip leading command frontmatter (body-`---`-safe) — §13.5 injection |
| `lib/cmd/sync.sh` | modified | 2 | +~8 | strip frontmatter on the command sync path so canonical stays frontmatter-free |
| `adapters/agents-md/adapter.sh` | modified | 2 | +~10 | reference `.agents/skills/` in AGENTS.md |
| `lib/cmd/generate.sh` | modified | 2 | (3.4 base) +~15 | `agent-skills` target — **composes on 3.4 `--lite`** |
| `lib/cmd/deploy.sh` | modified | 2 | (3.4 base) +~15 | skills deploy — **composes on 3.4 rules symlink** |
| `canonical/reference/framework.md` | modified | 3 | −3 | remove phantom `collect-spool.sh` contract (zero-risk; may pull to Wave 1) |
| `state/rdf-bus.sh` | modified | 3 | +~40 | (conditional) P6 status broadcast — only if re-triage confirms |
| `canonical/commands/r-status.md` | modified | 3 | +~15 | (conditional) read-only peer view |
| `README.md`, `ROADMAP.md`, `CHANGELOG`, `CHANGELOG.RELEASE`, `VERSION` | modified | 1/2/3 | +entries | per-wave release |

### 4.2 Composition with 3.4 (files both releases write)

3.4 lands first. 3.5 must not clobber 3.4's edits. The overlap set (from the
3.4 plan File Map):

| File | 3.4 change | 3.5 change | Composition rule |
|------|-----------|-----------|------------------|
| `adapters/claude-code/adapter.sh` | `cc_generate_rules()`, `--lite` in `cc_generate_all` | command frontmatter emission (Wave 2) | 3.5 Wave 2 adds a NEW function `cc_generate_command_frontmatter` and one call inside `cc_generate_commands`; do not touch `cc_generate_rules`/`--lite`. Wave 2 is gated on 3.4 merged. |
| `lib/cmd/generate.sh` | `--lite` flag parse | new `agent-skills` case | disjoint: 3.4 edits the `--lite` parse block; 3.5 adds a `case` arm. Land 3.5 after 3.4. |
| `lib/cmd/deploy.sh` | opt-in `rules/` symlink; `--lite` | skills symlink (Wave 2) | disjoint symlink lines in `_deploy_claude_code`; append after 3.4's rules symlink. |
| `state/rdf-bus.sh` | **untouched by 3.4** | tier helpers (Wave 1), P6 (Wave 3) | no conflict — 3.4 does not edit rdf-bus.sh. |
| `canonical/commands/r-save.md`, `r-start.md`, `r-util-mem-compact.md`, `r-context-audit.md` | 3.4 edits | **untouched by 3.5** | no conflict — 3.5 touches r-spec/r-plan/r-build/r-ship only. |
| `README.md`, `ROADMAP.md`, `CHANGELOG*`, `VERSION` | 3.4 entries | 3.5 entries | additive; 3.5 appends its own version blocks after 3.4's. |
| `tests/governance-contracts.bats` | 3.4 +2 contracts | 3.5 +tier-cap/security-floor/frontmatter contracts | **additive `@test` blocks, appended at EOF** — no source-line overlap, but both releases touch this file (co-edit); land 3.5's blocks after 3.4's. |
| `tests/Makefile` | 3.4 adds `memory-context.bats` to test+lint lists | 3.5 adds `scale-ceremony.bats` (+Wave 2 bats) | **co-edit of the same two list variables** — append 3.5's filenames to the `test:`/`lint:` lists after 3.4's; a merge conflict here is trivial (adjacent list lines). |

**No SOURCE file is edited at the same lines by both releases.** Two *test*
files are co-edited additively — `tests/governance-contracts.bats` (append
`@test` blocks at EOF) and `tests/Makefile` (append filenames to the `test:`
and `lint:` bats lists). Both merges are trivial (append/adjacent-line). The
three shared *shell* files (`claude-code/adapter.sh`, `generate.sh`,
`deploy.sh`) are all in 3.5 **Wave 2**, gated on 3.4 having merged (§7) — the
plan Phase-0 confirms 3.4's functions are present before Wave 2 edits. So the
accurate claim is: **Wave 1 has zero SOURCE overlap with 3.4; it shares two
additive test files whose merge points are named above.**

### 4.3 The tier as the master ceremony dial

The central design idea: **one tier value scales items 2, 3, and 5 together.**
The tier is chosen once (at `/r-spec` or `/r-plan` entry) and every downstream
ceremony reads it.

```
Tier      Clarify(#2)   Spec artifact         Plan review     Build gates(#1/dispatcher)   Living spec(#5)
--------  -----------   -------------------   -------------   --------------------------   ---------------
full      full pass     docs/specs/*.md       challenge rev   scope→gate map (unchanged)   fold on ship
quick     1 round       condensed, folded     single review   cap at sentinel-lite         optional
bugfix    skipped       none (test-first)     schema-only     Gate1 + regression-lite      skipped
```

The dispatcher already derives gates from scope (`dispatcher.md:242-247`). The
tier is a **ceiling** applied on top: `min(scope_gate, tier_cap)`. `full`'s cap
is "no cap". `quick-plan`'s cap is sentinel-lite (never 3-pass, never UAT unless
the file list forces it). `bugfix`'s cap is Gate 1 + a regression-only
sentinel-lite; QA-matrix and end-of-plan sentinel are suppressed. This keeps
the memory-recorded invariant "dispatcher owns gate machinery; developer sees
TDD-shaped outcomes" intact — the tier is just a new input to the dispatcher's
existing selection.

**Security floor (overrides the cap — non-negotiable).** The 3.3.0 Critical
RCE fix (C1, `context-audit.sh`) was a *single-file* change with a reproducing
test and an issue ref — the exact shape the `bugfix` heuristic matches. A tier
cap that let a security patch skip the sentinel Security pass or the QA gate
would be a self-inflicted vulnerability. Therefore: **when the dispatcher
classifies a phase `scope:sensitive`, OR any changed file matches the
security-sensitive indicators, the tier cap MUST NOT reduce Gate 3 below
sentinel-full (3-pass, Security included) and MUST NOT skip Gate 2.** The
indicator list is **reused verbatim** from the reviewer's Early-Exit Rubric
(`reviewer.md:183-187`) — do NOT define a second list: filename contains
`auth`, `cred`, `secret`, `token`, `key`, `passwd`, `encrypt`, `hash`, `sign`,
`cert`, `session`, or `permission`; or the path is flagged security-sensitive
in `governance/anti-patterns.md`; or the phase is `scope:sensitive`. The floor
means `min(scope_gate, tier_cap)` becomes `max(security_floor, min(scope_gate,
tier_cap))`. A `governance-contracts.bats` contract asserts the tier cap never
drops the security pass on `scope:sensitive`.

### 4.4 Dependency Tree

```
Wave 1 (Scale — canonical + state, NO adapter.sh) ────────────────────────
  tiers.md (reference, single source)
    ├── r-spec.md  --full|--quick|--bugfix + heuristic suggest → rdf_set_active_tier
    │     └── Phase 1.5 Clarify (scaled by tier)
    ├── r-plan.md  reads active tier → writes **Tier:** marker
    │     └── quick/bugfix condensed-artifact paths
    ├── r-build.md Section 1
    │     ├── state/rdf-consistency.sh check  (spec↔plan↔tasks)
    │     └── TIER: → dispatch payload
    │           └── dispatcher.md: min(scope_gate, tier_cap)
    └── r-ship.md Stage 3e → docs/specs/CURRENT.md delta fold (skip if bugfix)
  state/rdf-bus.sh: rdf_set_active_tier / rdf_active_tier (parallel to active-plan)
  plan-schema.md: Rule 10 (Tier marker)

Wave 2 (Reach — adapters; 3.4 MERGED, confirmed 2026-07-15 — see §13) ─────
  adapters/agent-skills/adapter.sh  (canonical/commands + skill-meta.json)
    └── output/.agents/skills/<cmd>/SKILL.md  (name + intent-trigger description)
         — the ONE shared workspace surface read by Codex + Antigravity
  generate.sh: `agent-skills` target + `antigravity` composite (skills + AGENTS.md)
  claude-code/adapter.sh: cc_generate_command_frontmatter (intent trigger)  [on 3.4 base]
  gemini-cli/adapter.sh (LEGACY tier): TOML `'''` literal-string fix (15/37) + {{args}} lossy warning
  agents-md/adapter.sh: `.agents/skills/` pointer (Antigravity + AGENTS.md consumers)
  deploy.sh: opt-in `.agents/skills/` symlink (--project-root)   [on 3.4 base]
  tests/deploy.bats (audit M6), tests/agent-skills.bats
  docs/multi-tool-parity.md (trio + legacy gemini row)
  NOTE: codex/adapter.sh is NO LONGER modified — skills are the shared
        agent-skills surface, not per-tool output (§13.4).

Wave 3 (Coordination — RE-TRIAGE GATED; recommend 3.6) ───────────────────
  Phase 0 probe: Codex hooks schema · Agent-Skills SKILL.md schema ·
                 Wave B survival (native background-agent coverage)
  framework.md: delete phantom collect-spool.sh contract  (zero-risk survivor)
  [conditional] rdf-bus.sh P6 status.json + r-status.md peer view
  [recommend-defer] P5 bus, /r-msg, P7/P10 sweeper
```

### 4.5 Wave B re-triage (item 7) — survival table

Re-triaged against the current platform (background agents; native subagent
dispatch; Wave A shipped). Each 2026-04-25 Wave B primitive gets a verdict.

| Wave B primitive | 2026-04 rationale | 2026-07 verdict | Disposition |
|------------------|-------------------|-----------------|-------------|
| Phantom `collect-spool.sh` contract (`framework.md:171`) | v2 doc inheritance | never implemented; pure drift | **Remove now** (zero-risk, Wave 3 quick-win, may pull to Wave 1) |
| P6 per-session `status.json` broadcast | "what's everyone working on" | still uncovered for separate *top-level* sessions (native background agents are intra-session) | **Ship iff probe confirms pain** (read-only, ~40 lines) |
| P12 `/r-status` peer view | peer awareness | thin read over P6 | **Ship with P6** (extends existing command, no new command) |
| P5 append-only NDJSON bus | cross-session claims | heavier; overlaps emerging native messaging; single-operator ROI low | **Recommend defer** (adds a subsystem for speculative multi-session use) |
| P12 `/r-msg` command | send/tail/announce | new command surface | **Recommend defer** (violates simplicity budget for the common case) |
| P7 staleness / P10 worktree sweeper | crash recovery | preventive, not actively painful; Wave A worktree hooks already reduce leaks | **Recommend defer** |
| P2 two-tier XDG dirs, P3 atomic write, P4 OFD locks | durability | 3.4's SessionEnd O_APPEND + existing atomic-swap cover the live pain | **Recommend defer** (no observed incident since Wave A) |

Net Wave B survivor for 3.5: the phantom-contract cleanup (certain) plus, if
the probe reconfirms cross-session pain, a read-only P6+peer-view. Everything
else is recommended-deferred with the rationale above.

### 4.6 Dependency Rules

- `canonical/` stays tool-agnostic and frontmatter-free. Intent-trigger text,
  SKILL.md frontmatter, Gemini `{{args}}` mechanics, and Codex hook shapes live
  **only** in `adapters/` and adapter metadata JSON — never in canonical
  command bodies. A `governance-contracts.bats` contract asserts canonical
  commands carry no YAML frontmatter.
- `tiers.md` is the single source for tier semantics; `r-spec`/`r-plan`/
  `r-build`/`dispatcher` cite it, never restate the gate table.
- `state/*.sh` never source adapters. `rdf-consistency.sh` may source
  `state/rdf-bus.sh` for `rdf_active_plan_path` only.
- Every new shell path is bash 4.1-safe, jq-optional (degrade to a documented
  fallback, never hard-fail a hook or a generate), and POSIX-`sed` portable
  (macOS CI) — no `\b`, no `\|`, no GNU-only flags.

## 5. Key File Contents

### 5.1 `canonical/reference/tiers.md` (new, Wave 1)

Single source of truth. Three subsections:

- **Definitions** — the §4.3 table verbatim (tier × ceremony).
- **Heuristic signals** (suggestion only; user confirms): `bugfix` when the
  input is a bug/issue reference or describes a defect in existing behavior,
  scope looks single-file, and a reproducing test can be written first;
  `quick-plan` when the change is well-understood, ≤ ~3 files, no open
  architecture questions; `full` otherwise (default on any ambiguity or
  multi-component work).
- **Gate caps** — the exact `min(scope_gate, tier_cap)` mapping the dispatcher
  applies (Wave-1 dispatcher edit cites this), INCLUDING the security floor
  (§4.3): the cap is overridden to sentinel-full + Gate 2 on `scope:sensitive`
  or any file matching the reviewer Early-Exit indicator list (reused verbatim
  from `reviewer.md:183-187`, never re-defined here).

### 5.2 `state/rdf-bus.sh` — tier helpers (new functions, Wave 1)

Mirrors the active-plan pointer pattern already in the file (`:129-181`).

| Function | Signature | Behavior | RC |
|----------|-----------|----------|----|
| `rdf_set_active_tier` | `<tier> [root]` | validate `tier ∈ {full,quick-plan,bugfix}`; write `.rdf/active-tier-${RDF_SESSION_ID}` | 0 ok, 1 invalid tier |
| `rdf_active_tier` | `[root]` | resolve per precedence below; echo the tier | 0 always (default `full`) |
| `rdf_clear_active_tier` | `[root]` | remove the session tier pointer (idempotent) | 0 always |

**Precedence (S3) — the plan marker is authoritative once a plan resolves.**
The session pointer `.rdf/active-tier-${RDF_SESSION_ID}` is only the *pre-plan
carrier* (used during the `/r-spec` phase, before any plan exists).
`rdf_active_tier` resolves in this order:

1. If `rdf_active_plan_path` resolves a plan AND that plan has a valid
   `**Tier:**` marker → the **marker wins**, and the session pointer is
   *reconciled* (overwritten) to match it (so a stale pre-plan pointer cannot
   contradict the committed plan).
2. Else, the session pointer if present and valid.
3. Else, `full`.

`rdf_clear_active_tier` is called by `/r-ship` alongside `rdf_clear_active_plan`
(Stage 3, pointer clear) so the next session starts clean.

Frontmatter-free, `command`-prefixed coreutils, guarded `cd`. No jq needed.

### 5.3 `state/rdf-consistency.sh` (new, Wave 1)

Deterministic cross-artifact check. `check [--warn-only] <plan-path> [spec-path]`:

| Check | Method | Severity |
|-------|--------|----------|
| File-Map ↔ phases | every `### New/Modified/Deleted` File-Map path appears in ≥ 1 phase `Files:`; every phase `Files:` path is in the File Map | **error (exit 2)** |
| Phase count | count of `### Phase N:` headings **including Phase 0** == preamble `**Phases:** N` | **error (exit 2)** |
| Goal coverage | (spec given) every spec `## 2. Goals` numbered goal appears in the union of phase `**Goals:**` fields | warn (exit 1) |
| Goals-field presence | every phase carries a `**Goals:** N[,M...]` metadata field | warn **once per plan** (exit 1) |
| Edge-case coverage | (spec given) every §11b edge-case row maps to a phase `Edge cases:` | warn (exit 1) |
| Tier sanity | `bugfix` plans have ≤ 2 phases; `quick-plan` ≤ ~6 | warn (exit 1) |

**Multi-path parse (M2).** `rdf_parse_phase_scope` (`rdf-bus.sh:84`) captures
only the FIRST backticked path of a comma-list Files line
(`- Create: \`a\`, \`b\``) — using it for coverage would false-block on any
multi-path line. The checker therefore does its OWN Files parse that loops
**every** backtick group per line (a `while` over `\`([^\`]+)\`` matches), and
recommends plans keep one path per Files line for Rule 8 hygiene. Wave A
consumers of `rdf_parse_phase_scope` (pre-commit hook, dispatcher post-merge
check) are unaffected — the helper is not modified; a regression test asserts a
comma-list line is fully covered by the checker.

**Goals field convention (S2).** Coverage is mechanical, not semantic: each
phase declares which spec goals it advances via a `**Goals:** N,M` metadata
line; the checker greps the union and flags any spec goal absent from it. A
plan whose phases omit the field gets ONE warning (not one per goal) — the
convention is opt-in-visible, never a semantic judgment. This plan dogfoods the
field on every phase.

**Escape hatch (M2).** `--warn-only` downgrades the two exit-2 structural
errors to exit-1 warnings, for the rare legitimate structural false-positive
(e.g. an intentional File-Map entry a reviewer approved). `/r-build` §1
documents that using it requires a stated reason in the build invocation —
exit-2-with-no-override is too brittle.

Emits a findings block to stdout; exit 0 clean, 1 warnings, 2 structural
break. Read loops are `eval`-free, POSIX sed, jq-optional (pure bash string
parsing). `/r-build` blocks on exit 2, surfaces warnings on exit 1.

### 5.4 `adapters/agent-skills/adapter.sh` (new, Wave 2)

Emits `.agents/skills/<command>/SKILL.md` for the lifecycle + high-value
utility set (bounded, not all 37). Each SKILL.md:

```markdown
---
name: r-spec
description: >
  <intent-trigger from skill-meta.json — e.g. "Use when starting a new
  feature or design: turns an idea into an architecture-grade spec through
  research-driven dialogue.">
---
<canonical command body, verbatim>
```

`name` + `description` are the Agent-Skills required frontmatter (schema
confirmed in Phase 0 probe). Body is the canonical command verbatim — the same
source CC/Gemini/Codex already consume. Trigger descriptions live in
`skill-meta.json` (adapter-side), reused by Goal 7's CC command frontmatter so
one description drives all tools.

### 5.5 `docs/specs/CURRENT.md` fold (item 5, Wave 1) — r-ship Stage 3e

New Stage 3e in `r-ship.md`, after 3d (commit) and before the pointer clear:

- Read `docs/specs/CURRENT.md` (seed created in Wave 1; absence → create with
  a header).
- Derive an ADDED/MODIFIED/REMOVED delta from the shipped plan's File Map +
  the changelog entries just generated (Stage 3a).
- Present the delta to the user for approval (lightweight — a few bullets).
- On approval, prepend a `## <version> — <date>` block to CURRENT.md and stage
  it with the release commit. Skip entirely when `rdf_active_tier` is `bugfix`.
- Degrade: if the plan File Map cannot be parsed, emit a notice and skip (never
  block the release).

## 5b. Examples

### 5b.1 Tier selection with heuristic suggestion

```
$ /r-plan --bugfix
Tier: bugfix (you selected --bugfix)
  → No spec. Plan = failing-test-first + fix. Gates: engineer self-report
    + regression-only sentinel-lite. Confirm? [Y/n]

$ /r-spec
Assessing scope... this looks like a multi-component feature.
Suggested tier: full (research dialogue + challenge review).
  [1] full (suggested)  [2] quick-plan  [3] bugfix
Select tier [1]:
```

### 5b.2 Consistency micro-gate in /r-build

```
$ /r-build
Consistency check (spec↔plan↔tasks)...
  ✓ File Map ↔ phases: 8/8 files covered
  ✓ Phase count: 8 headings == **Phases:** 8
  ⚠ Goal coverage: spec Goal 6 not referenced by any phase Accept/Test
  ✓ Edge cases: 11/11 mapped
Exit 1 (warnings) — proceeding. Address Goal 6 or confirm it is intentional.
```

Structural break (blocks):

```
$ /r-build
Consistency check...
  ✗ File Map lists `lib/cmd/foo.sh` — no phase touches it
Exit 2 — plan/File-Map mismatch. Fix the plan (re-run /r-plan) before build.
```

### 5b.3 Emitted SKILL.md (intent trigger)

```
$ rdf generate agent-skills && cat adapters/agent-skills/output/.agents/skills/r-spec/SKILL.md
---
name: r-spec
description: >
  Use when starting a new feature, subsystem, or design change: turns an
  idea into an architecture-grade spec through research-driven dialogue.
---
# /r-spec — Design Command
...canonical body verbatim...
```

### 5b.4 Living-spec delta after /r-ship

```
$ head -12 docs/specs/CURRENT.md
# RDF — Current-State Spec (living)

## 3.5.0 — 2026-07-15
ADDED: task-class tiers (full/quick-plan/bugfix); /r-spec Clarify micro-gate;
       /r-build consistency micro-gate; living-spec fold.
MODIFIED: dispatcher gate selection now min(scope, tier).
REMOVED: none.
```

### 5b.5 Gemini `{{args}}` lossy-edge warning

```
$ grep -A1 'positional' adapters/gemini-cli/output/.gemini/commands/r-build.toml
# NOTE: canonical /r-build takes positional args (e.g. `/r-build 3`); Gemini
# TOML exposes only {{args}} — pass the whole string, positionals not parsed.
```

## 6. Conventions

- Hook/state scripts: `#!/usr/bin/env bash`, `set -euo pipefail`,
  `command`-prefixed coreutils, `command -v` discovery, guarded `cd`.
- Tier marker: `**Tier:** full|quick-plan|bugfix` on its own preamble line,
  immediately after `**Plan Version:**`.
- Skill IDs: `name` == canonical command basename (`r-spec`); `description` is
  a natural-language *trigger* ("Use when …"), never a restatement of the body.
- Consistency findings: `✓`/`⚠`/`✗` prefix, one line per check, machine-greppable.
- All tool mechanics adapter-side; canonical stays tool-agnostic + frontmatter-free.
- CHANGELOG soft-wrap + tag style per workspace CLAUDE.md; one version block per
  shipped wave.

## 7. Release Staging & Deferral Recommendation

3.5 is large (7 items). Planning splits it into three shippable waves; the
**recommendation** (carried into the plan preamble) is to ship Waves 1–2 as
3.5.0/3.5.1 and defer the heavy tail to 3.6.

| Wave | Release | Items | Ships | Gate |
|------|---------|-------|-------|------|
| 1 | **3.5.0 "Scale"** | 1,2,3,5 | tiers, clarify, consistency, living-spec | none — canonical + state only; **no 3.4 SOURCE conflict** (two additive shared test files, §4.2) |
| 2 | **`3.6.0` "Reach"** | 4,6(core),8,9 | `.agents/skills` + intent triggers, gemini TOML fix, deploy/sync BATS | **3.4 merged ✓** + Skills-schema probe done (§13) |
| 3 | **3.6 (recommend defer)** | 6(heavy),7 | Codex hooks, settings fragments, Wave B delta | Phase-0 re-triage; only zero-risk survivors pulled forward |

**Why this split:** Wave 1 is the highest adoption-per-effort work, is
tool-agnostic, and has zero SOURCE overlap with the unbuilt 3.4 (only two
additive shared test files, §4.2) — it can be built and shipped independently
and immediately. Wave 2 is adapter-heavy and shares
three shell files with 3.4, so it must follow 3.4 and is worth its own point
release. Wave 3 is probe-dependent (Codex hook schema, current native
messaging coverage) and, on re-triage (§4.5), largely obsoleted or
low-ROI — building it speculatively violates the simplicity budget. The
roadmap explicitly permits 3.5 to split.

## 8. Migration Safety

- **Tiers:** additive. Plans without a `**Tier:**` marker default to `full`
  (Rule 10 is optional; legacy plans behave exactly as today). `rdf_active_tier`
  returns `full` when no pointer/marker exists. The tier-selection prompt
  defaults to `[1] full` on a bare Enter — an untiered user pays exactly one
  keystroke and lands in today's behavior, so nobody is forced to learn tiers.
- **Consistency gate:** advisory-by-default; only structural breaks block, and
  those are already latent plan bugs. A legacy plan with a clean File Map
  passes. On parse failure it degrades to a warning (matches `/r-build` 2b.4).
- **Living spec:** `docs/specs/CURRENT.md` is created on first need; absence is
  handled. `/r-ship` skips the fold on parse failure or `bugfix` tier —
  releases never block on it.
- **Skills/intent triggers (Wave 2):** new emitted surface; existing CC/Gemini/
  Codex outputs are byte-identical except CC commands gain frontmatter (a
  strictly additive header the loader already tolerates). No deploy default
  changes — skills deploy is opt-in.
- **Wave B (Wave 3):** removing the phantom `collect-spool.sh` line is
  documentation-only. Any P6/peer-view is read-only and opt-in. No persistent
  state to unwind.
- **Rollback per wave:** revert the wave's commits; no cross-wave state
  coupling. Tier markers and CURRENT.md are inert if the tooling is removed.

## 9. Dead Code and Cleanup

- `framework.md:171` `collect-spool.sh` — phantom contract (no implementation).
  Removed in Wave 3 (or pulled to Wave 1 as a zero-risk quick-win).
- `rdf_profile_includes()` (`lib/rdf_common.sh`) — dead stub noted by 3.4; 3.5
  new code must not call it.
- No new dead code introduced. `rdf-consistency.sh` and the tier helpers are
  all reachable from the verbs.

## 10a. Test Strategy

| Goal | Test file | Test |
|------|-----------|------|
| 1 | scale-ceremony.bats | `rdf_set_active_tier/rdf_active_tier roundtrip + default full` |
| 1 | scale-ceremony.bats | `--quick plan preamble contains **Tier:** quick-plan` (structural) |
| 2 | governance-contracts.bats | `r-spec Clarify precedes Brainstorm` (`_contract` on r-spec.md) |
| 2 | scale-ceremony.bats | `bugfix tier skips Clarify` (structural doc grep) |
| 3 | scale-ceremony.bats | `rdf-consistency check exits 0 on consistent fixture` |
| 3 | scale-ceremony.bats | `rdf-consistency check exits 2 on File-Map/phase mismatch` |
| 3 | scale-ceremony.bats | `rdf-consistency check exits 1 on uncovered goal` |
| 3 | scale-ceremony.bats | `rdf-consistency covers a comma-list Files line (M2 multi-path)` |
| 3 | scale-ceremony.bats | `--warn-only downgrades exit 2 to exit 1` |
| 2 | governance-contracts.bats | `bugfix tier never triggers 3-pass sentinel/UAT` (dispatcher cap contract) |
| 2 | governance-contracts.bats | `tier cap never drops the security pass on scope:sensitive` (M1 security floor) |
| 5 | governance-contracts.bats | `r-ship folds CURRENT.md; skips on bugfix` (`_contract` on r-ship.md) |
| 6 | agent-skills.bats | `one SKILL.md per lifecycle command; frontmatter has name+description` |
| 7 | agent-skills.bats | `CC command output gains frontmatter; canonical stays frontmatter-free` |
| 8 | agent-skills.bats | `gemini positional-arg command TOML carries the lossy warning` |
| 9 | deploy.bats | `deploy symlink create/replace/skip/force; hooks.json skipped` |
| 9 | deploy.bats | `sync pulls emergency edit back to canonical` |
| 11 | doctor.bats (existing) | `0 FAIL after each wave` |

Adversarial cases baked in: tier cap cannot be *upgraded* by the dispatcher
(only capped down); **a `bugfix`-tier change to a security-indicator file keeps
Gate 2 + sentinel-full (security floor, M1)**; **a comma-list Files line is
fully covered by the consistency parse (M2)** — no false-block; consistency
gate false-positive on a legacy clean plan (must pass); `--warn-only` downgrades
a structural error; canonical-frontmatter-free contract (Wave 2); living-spec
skip on bugfix; deploy `--force` backup path; sync round-trip.

## 10b. Verification Commands

```bash
# Goal 1 — tier roundtrip
source state/rdf-bus.sh; rdf_set_active_tier quick-plan .; rdf_active_tier .   # expect: quick-plan
rdf_set_active_tier bogus . ; echo $?                                          # expect: 1

# Goal 3 — consistency gate
bash state/rdf-consistency.sh check tests/fixtures/tiers/consistent-plan.md; echo $?   # expect: 0
bash state/rdf-consistency.sh check tests/fixtures/tiers/mismatch-plan.md;  echo $?     # expect: 2

# Goal 5 — living spec fold present, bugfix-skipped
grep -c 'CURRENT.md' canonical/commands/r-ship.md          # expect: >=1
grep -c 'bugfix' canonical/commands/r-ship.md              # expect: >=1

# Goal 6/7 — skills emission + canonical frontmatter-free
bin/rdf generate agent-skills
head -1 adapters/agent-skills/output/.agents/skills/r-spec/SKILL.md   # expect: ---
head -1 canonical/commands/r-spec.md                                  # expect: NOT ---

# Goal 9 — deploy BATS runs
make -C tests test 2>&1 | grep -c '^not ok'                 # expect: 0

# Goal 11 — clean
bash bin/rdf doctor 2>&1 | grep -c 'FAIL'                   # expect: 0
```

## 11. Risks

1. **Tier scope creep into a fourth pipeline.** Mitigation: tier is a
   flag+marker on the four verbs; a contract asserts no new top-level command
   is added. The dispatcher only *caps* gates — enforced by the tier-cap
   contract.
2. **Consistency gate false positives blocking builds.** Mitigation: only
   two structural checks block (File-Map/phase, phase-count); everything else
   warns; parse failure degrades to a warning. Legacy-clean-plan test guards it.
3. **Living spec becomes ceremony.** Mitigation: bugfix skips it, it is
   user-approved and best-effort, and it never blocks a release. If it feels
   heavy in practice, it is a single Stage-3e step to disable.
4. **Wave 2 collides with unbuilt 3.4.** Mitigation: Wave 2 is gated on 3.4
   merged; Phase 0 confirms `cc_generate_rules`/`--lite` are present; 3.5 adds
   new functions/case-arms, never edits 3.4's lines (§4.2).
5. **Codex/Skills schema assumptions wrong.** Mitigation: Phase-0 probe
   confirms the Agent-Skills `SKILL.md` frontmatter schema and Codex hook
   events from live docs before Wave 2/3 code; anything unconfirmed is deferred,
   not guessed (audit lesson: runtime-observed facts get an engineer-validation
   pass before code).
6. **Wave B built speculatively.** Mitigation: §4.5 re-triage defaults to
   deferring the bus/msg/sweeper; only the zero-risk phantom-contract cleanup
   is certain to ship. `/r-msg` is explicitly recommended-out.
7. **Over-large single release.** Mitigation: §7 staging + the plan's Phase-0
   split point; each wave is independently shippable and independently
   revertible.

## 11b. Edge Cases

| Scenario | Expected | Handling |
|----------|----------|----------|
| Plan with no `**Tier:**` marker | treated as `full` | Rule 10 optional; `rdf_active_tier` default |
| `rdf_set_active_tier bogus` | reject, exit 1 | tier allowlist |
| `/r-plan --bugfix` on a 9-file change | warn (bugfix ≤ 2 phases) | consistency tier-sanity check (warn) |
| `bugfix`-tier fix to `auth.sh`/`token.py`/etc. or a `scope:sensitive` phase | Gate 2 + sentinel-full run despite the tier | security floor (M1) overrides the cap |
| Phase `Files:` line lists two backticked paths (`\`a\`, \`b\``) | both paths counted as covered | checker's own multi-path parse (M2) |
| Consistency structural false-positive a reviewer approved | `check --warn-only` downgrades exit 2→1 | documented escape hatch (M2); requires stated reason in `/r-build` |
| Consistency check, File Map lists a file no phase touches | block, exit 2 | structural error |
| Plan preamble `**Phases:** N` vs `### Phase 0..K` heading count | Phase 0 IS counted | deterministic phase-count convention (M3) |
| Plan phases omit the `**Goals:**` field | warn once per plan | Goals-field presence check (S2) |
| Pre-plan session tier pointer contradicts a resolved plan's `**Tier:**` | plan marker wins; pointer reconciled | precedence order (S3) |
| Consistency check on a manually-authored clean plan (no spec) | pass (spec checks skipped) | spec-optional path |
| `/r-ship` living-spec fold, File Map unparseable | skip with notice, release proceeds | degrade path |
| `/r-ship` on a `bugfix` plan | living-spec fold skipped | tier check |
| Wave 2 generate before 3.4 merged | Phase-0 halts Wave 2 | gate: confirm 3.4 functions present |
| `agent-skills` generate with no skill-meta entry for a command | emit SKILL.md with a first-sentence fallback description | fallback like gemini command-meta |
| Gemini command TOML for a no-positional command | no lossy warning emitted | conditional on positional-arg grep |
| Codex hooks probe returns unknown schema | defer Codex hooks to 3.6 | Phase-0 no-go recorded |
| `deploy.bats` on a host without `bats` | Makefile `_bats_check` errors clearly | existing guard |

## 12. Open Questions (resolved in Phase 0 re-triage)

- **Q1 — Agent-Skills `SKILL.md` frontmatter schema.** Confirm required keys
  (expected: `name`, `description`) and any size/naming constraints from the
  open Agent-Skills spec + Codex/Gemini client docs. Blocks Wave 2 skills
  emission; non-blocking for Wave 1.
- **Q2 — Codex hook event names + config location.** Confirm the ~11-event
  Codex hook surface and which of {pre-tool, post-tool, session-boundary} RDF
  can map. If the schema is unstable, defer Codex hooks to 3.6 (recommended).
- **Q3 — Wave B cross-session pain re-confirmation.** Confirm whether separate
  top-level sessions still lack native peer-awareness (background agents are
  intra-session). If native now covers it, drop P6/peer-view entirely; if not,
  ship read-only P6+peer-view as the sole Wave B survivor.
- **Q4 — 3.4 merge status at Wave 2 start.** Confirm `cc_generate_rules`,
  `--lite`, and the rules symlink are present before editing the three shared
  shell files. Hard gate for Wave 2.

None block Wave 1. Phase 0 records go/no-go for Waves 2–3.

**RESOLVED 2026-07-15 (full detail + primary sources in §13):**
- **Q1 — GO.** SKILL.md required frontmatter is `name` + `description` only; RDF
  emits exactly those. Optional AAIF fields NOT emitted (§13.4).
- **Q2 — DEFER.** Antigravity hook/subagent schemas undocumented/churning; Codex
  `openai.yaml` optional. No hook/subagent emission in Reach (§13.7 Non-Goals).
- **Q3 — unchanged.** Stays in the deferred Phase 12 (recommend 3.6).
- **Q4 — GO. 3.4 HAS MERGED** (`cc_generate_rules`/`_CC_LITE` present on `main`,
  VERSION 3.5.1). Wave 2 composes safely.
- **New:** Gemini CLI is superseded by **Antigravity CLI** (`agy`); Antigravity
  is a first-class citizen, gemini-cli is demoted to a frozen legacy tier (§13.3,
  §13.6).

## 13. Phase-0 Probe Results & Revised Wave-2 Architecture (2026-07-15)

The Phase-0 schema probe (§12 Q1–Q4) plus an adversarial primary-source
verification pass is complete. This section is the authoritative fact base and
supersedes the pre-probe Wave-2 sketch (§4.4, §5.4) where they conflict. Wave 1
(Scale) shipped as 3.5.0 plus a 3.5.1 QA-pass; this section re-scopes the
second (adapter) wave, whose version is assigned at ship.

### 13.1 Verified fact base (primary sources)

**Gemini CLI → Antigravity CLI.** Gemini CLI stopped serving free/Pro/Ultra
tiers on 2026-06-18 (announced at I/O 2026-05-19); enterprise/paid-API users are
unaffected and the OSS repo remains active (v0.50.0, 2026-07-08). The successor
is **Antigravity CLI** (`agy`), closed-source Go, retaining Agent Skills, Hooks,
Subagents, and Extensions. Antigravity is RDF's locked-in transition target and
a first-class adapter citizen.

**Antigravity CLI surface** (confidence noted):
- Project skills: `<workspace>/.agents/skills/<skill-name>/SKILL.md` — the
  cross-tool convention — with optional `scripts/`, `examples/`, `resources/`.
  Skills double as slash commands via fuzzy matching. HIGH.
- SKILL.md frontmatter: only `name` + `description` documented; unknown-field
  handling unverified.
- Commands: NO TOML surface — legacy `.gemini/commands/*.toml` are CONVERTED to
  skills by `agy plugin import gemini`; skills are the only command surface.
  MEDIUM-HIGH.
- Context files: parses BOTH workspace `GEMINI.md` and `AGENTS.md`, plus global
  `~/.gemini/GEMINI.md`; precedence undocumented. MEDIUM-HIGH.
- Hooks `<workspace>/.agents/hooks.json` (schema undocumented); subagents
  (markdown, schema churning); plugins `~/.gemini/antigravity-cli/plugins/<name>/`
  with `plugin.json`; state root remains `~/.gemini/`.
- UNVERIFIED: user-level `~/.agents/skills/` scanning (post-migration global
  skills appear to live at `~/.gemini/skills/`).

**AAIF SKILL.md standard** (agentskills.io/specification): required `name`
(1–64 chars, lowercase alphanumeric + hyphens, no leading/trailing/consecutive
hyphens, MUST match the parent directory name) and `description` (1–1024 chars,
states what + when-to-use); optional `license`, `compatibility` (≤500),
`metadata` (arbitrary map), `allowed-tools` (experimental, agent-specific).
`.agents/skills/` is a widely-adopted convention, not a spec mandate. Governance
attribution is unverified and is deliberately NOT cited.

**Codex CLI:** consumes SKILL.md skills (explicit `$skill-name`, `/skills`,
implicit description matching); an optional Codex-specific `agents/openai.yaml`
inside a skill dir carries UI metadata / MCP tool deps / `allow_implicit_invocation`.

**Claude Code:** commands merged into skills — `.claude/commands/deploy.md` and
`.claude/skills/deploy/SKILL.md` both create `/deploy` and behave identically.
Commands remain fully supported (never documented as deprecated; skills
"recommended" for extra features). CC does NOT natively read AGENTS.md (only via
`@AGENTS.md` import or a symlink). Known bug: `disable-model-invocation` hides
the skill entirely (anthropics/claude-code#43875) — RDF must not set it.

**Gemini TOML** (legacy adapter): `prompt` required; `description` optional
(auto-derived from filename). Escaping is TOML-spec-level — basic strings
(`"..."`, `"""..."""`) process backslash escapes; literal strings (`'''...'''`)
do not. 15/37 generated command `.toml` files currently fail strict TOML parsing
because the canonical body (regex `\b`, sed `\|`, etc.) is emitted into a `"""`
basic multi-line string unescaped (`gemini-cli/adapter.sh:115-117`).

### 13.2 Resolved open questions (§12)

- **Q1 (SKILL.md schema) — RESOLVED / Phase 8 GO.** Required frontmatter is
  `name` + `description` only. RDF emits exactly these two; `name` == command
  basename and MUST equal the skill's parent directory name (AAIF constraint).
  Optional AAIF fields NOT emitted (§13.4).
- **Q2 (Codex hooks / Antigravity surfaces) — DEFER.** Hook/subagent/plugin
  schemas are undocumented or churning; Codex `openai.yaml` is optional and
  Codex-specific. None ship in Reach (§13.7).
- **Q3 (Wave B pain) — unchanged.** Not a Wave-2 concern; stays in deferred
  Phase 12 (recommend 3.6).
- **Q4 (3.4 merge) — RESOLVED: 3.4 HAS MERGED.** `cc_generate_rules`, `_CC_LITE`
  / `--lite`, and the `--lite` parse block are present in
  `adapters/claude-code/adapter.sh` and `lib/cmd/generate.sh` on `main`
  (VERSION 3.5.1). Wave 2's shared shell files are safe to compose on. GO.

### 13.3 First-class trio + legacy tier

Reach targets THREE first-class adapter citizens and ONE frozen legacy tier:

| Tool | Command surface | Skill surface | Context file | Tier |
|------|-----------------|---------------|--------------|------|
| Claude Code | `.claude/commands/*.md` + intent `description:` frontmatter | commands ARE skills natively | `CLAUDE.md` (NOT AGENTS.md) | first-class |
| Codex CLI | `.agents/skills/<cmd>/SKILL.md` (native scan) | shared `.agents/skills/` | own `AGENTS.md` (codex adapter) | first-class |
| Antigravity CLI | skills (fuzzy-matched slash) | shared `.agents/skills/` | `AGENTS.md` + `GEMINI.md` | first-class |
| Gemini CLI (enterprise) | `.gemini/commands/*.toml` | via `agy plugin import` | `GEMINI.md` | **legacy / frozen** |

`.agents/skills/` is a **workspace-level shared convention** — one directory at
the repo root that Codex, Antigravity, and every AAIF client read. It is
therefore emitted ONCE by a dedicated `agent-skills` adapter, NOT duplicated into
per-tool output trees.

### 13.4 Adapter-shape decision (design Q1)

- **`.agents/skills/` is emitted by ONE new adapter** (`adapters/agent-skills/`)
  via `rdf generate agent-skills`. This single artifact serves Codex, Antigravity,
  and the convention — no duplicate skills machinery in the codex or gemini
  adapters (a change from the pre-probe §4.4 sketch, which bolted skills emission
  onto codex + gemini). **`adapters/codex/adapter.sh` is consequently NOT
  modified in Reach** (Codex auto-discovers the shared `.agents/skills/`).
- **`rdf generate antigravity` is a thin first-class composite target** — it runs
  the shared skills emitter (`sk_generate_all`) plus the existing `agents-md`
  context emitter (`amd_generate_all`), so one command produces Antigravity's full
  surface (`.agents/skills/` + `AGENTS.md`). It adds no new generation engine,
  only a case arm calling two existing functions — discoverability parity with
  `claude-code`/`codex` at near-zero cost. **Decision (accepted asymmetry):** there
  is deliberately NO `rdf deploy antigravity` target — `.agents/skills/` deploys
  via the workspace-level `rdf deploy agent-skills` (Phase 10) and `AGENTS.md`/
  `GEMINI.md` are workspace files the user places directly; a composite deploy
  would duplicate the codex `--project-root` path for no gain. Generate is a
  composite; deploy stays per-artifact.
- **Emitted frontmatter is `name` + `description` ONLY.** `license` is redundant
  (repo LICENSE governs), `metadata: version/author` drifts on every release and
  Antigravity's unknown-field handling is unverified, `allowed-tools` is
  experimental + agent-specific. Adding unverified fields risks parse noise for
  zero confirmed benefit — deferred, not guessed (audit lesson).
- **Bounded command set:** lifecycle verbs (`r-spec`, `r-plan`, `r-build`,
  `r-ship`, `r-start`, `r-save`) + high-value utilities (`r-status`, `r-audit`,
  `r-refresh`, `r-init`) — ~10 of 37, bounded by `skill-meta.json` keys, not all
  commands. Trigger text lives in `skill-meta.json` and is reused by CC command
  frontmatter (§13.5) so one description drives all tools.

### 13.5 Claude Code stays commands (design Q4)

CC output stays `.claude/commands/*.md` and GAINS an intent-trigger
`description:` frontmatter block (Goal 7 as designed). RDF does NOT migrate CC to
`.claude/skills/<cmd>/SKILL.md`. Rationale:
1. Commands are not deprecated; a command's `description:` frontmatter drives
   model-invoked triggering identically to a skill's — the intent-trigger goal is
   met without migration.
2. RDF's deploy model symlinks `output/commands` → `~/.claude/commands`. Migrating
   to per-command `skills/<cmd>/SKILL.md` subdirectories would break every
   existing symlink-deploy user for zero functional gain (both forms create
   `/r-spec`).
3. Emitting BOTH `.claude/commands/r-spec.md` and `.claude/skills/r-spec/SKILL.md`
   would create two surfaces that both register `/r-spec` (collision noise); the
   plugin-citizenship spec already ruled "commands stay commands."
4. RDF never sets `disable-model-invocation`, side-stepping bug #43875.

### 13.6 Context-file story + gemini-cli demotion (design Q6, Q2)

- **gemini-cli is demoted to a frozen legacy tier.** It keeps its `GEMINI.md`
  (`gem_generate_context`) and command TOML for enterprise Gemini CLI (paid-API)
  users, frozen except the TOML-escaping fix. That fix is also strategically
  correct for the transition: `agy plugin import gemini` converts
  `.gemini/commands/*.toml` INTO Antigravity skills, so a strictly-valid TOML
  output is the migration SOURCE — fixing it directly serves Antigravity adoption.
- **Trade-off recorded for the challenge review (keep vs drop gemini-cli).** DROP
  would delete one legacy adapter and its tests, but abandon enterprise Gemini CLI
  users mid-transition and discard the working migration source. KEEP-frozen (the
  planned default) costs ~one TOML-fix diff plus continued test coverage.
  Recommendation: KEEP frozen + fix; revisit removal once usage telemetry shows
  enterprise Gemini CLI has migrated.
- **Antigravity context** is already served by existing adapters: it reads both
  `AGENTS.md` (from the `agents-md` adapter) and `GEMINI.md` (from the gemini-cli
  adapter). No new context adapter is needed; the parity doc maps this.
- **CC-reads-AGENTS.md: confirmed absent.** A repo grep found no spec/plan text
  claiming Claude Code natively reads AGENTS.md — the AGENTS.md references are all
  emission-side (codex/agents-md) or the parity matrix. Nothing to purge.

### 13.7 Deferred Antigravity/Codex surfaces (Non-Goals, probe-gated)

Mirroring the §4.5 Wave-3 deferral style, Reach does NOT build (schemas
undocumented or churning; revisit behind a future live-docs probe):
- Antigravity hooks (`<workspace>/.agents/hooks.json`) — schema undocumented.
- Antigravity subagents (markdown) — schema actively churning.
- Antigravity plugins (`~/.gemini/antigravity-cli/plugins/<name>/plugin.json`).
- Codex `agents/openai.yaml` per-skill metadata — Codex-specific, optional, not
  required for skill consumption.
- Global/user-level `~/.agents/skills/` scanning — unverified (post-migration
  global skills appear at `~/.gemini/skills/`).
- SKILL.md optional AAIF fields (`license`, `metadata`, `allowed-tools`).
- MCP server work (already a §3 non-goal).

Each ships only after a live-docs probe confirms a stable schema, per the audit
lesson (runtime-observed facts get an engineer-validation pass before code).
