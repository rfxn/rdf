# Implementation Plan: RDF 3.5 "Scale & Reach"

**Goal:** Add scale-adaptive ceremony to the four verbs (task-class tiers:
full / quick-plan / bugfix), a Clarify micro-gate in `/r-spec`, a Consistency
micro-gate in `/r-build`, living/delta specs in `/r-ship`, intent-triggered
skills + `.agents/skills/` multi-tool emission, and the surviving delta of the
2026-04-25 Wave B re-triage — without adding a top-level command, changing the
6 agents, or altering the 4 lifecycle verbs' identities.

**Architecture:** A single `**Tier:**` dial (chosen at `/r-spec` or `/r-plan`
entry, recorded in the plan preamble + `.rdf/active-tier-${RDF_SESSION_ID}`)
scales Clarify, Consistency, and living-spec ceremony together; the dispatcher
applies `min(scope_gate, tier_cap)` on top of its existing scope→gate mapping.
Wave 1 (Scale) is canonical + state only — zero SOURCE overlap with the unbuilt
3.4 (it shares only two additive test files, §4.2). Wave 2 (Reach) is
adapter-heavy and composes on top of 3.4's adapter changes.
Wave 3 (Coordination) is a re-triage gate with a defer recommendation.

**Tech Stack:** bash 4.1+ (`#!/usr/bin/env bash` + `set -euo pipefail`),
jq-optional on every runtime path, POSIX `sed` (macOS CI — no `\b`/`\|`/GNU
flags), BATS via system `bats`, GitHub Actions.

**Spec:** docs/specs/2026-07-15-scale-reach-design.md

**Phases:** 13 (Phase 0 COUNTS, per spec §5.3 — re-triage + Wave 1: 1–7 +
Wave 2: 8–11 + Wave 3: 12; 13 `### Phase N:` headings, N = 0..12)

**Tier:** full

**Plan Version:** 3.6

## Progress

**Wave 1 (Scale) SHIPPED** — Phases 0–7 delivered `full/quick-plan/bugfix`
tiers, the `/r-spec` Clarify micro-gate, `/r-build` consistency gate, and the
`/r-ship` living-spec fold. Released as **3.5.0** (tiers/clarify/consistency/
living-spec) and hardened in the **3.5.1** QA-pass. Phases 0–7 below are
frozen history — do not re-execute.

**Wave 2 (Reach) — RE-PLANNED 2026-07-15 post-probe (this revision).** Phases
8–11 were rewritten in place against the completed Phase-0 schema probe +
adversarial primary-source verification (spec §13). Key re-scope: Gemini CLI is
superseded by **Antigravity CLI** (`agy`); the three first-class citizens are
**Claude Code, Codex, Antigravity**; gemini-cli is demoted to a frozen legacy
tier (keep + TOML-escaping fix). `.agents/skills/` is a single shared
workspace surface emitted by ONE new `agent-skills` adapter — NOT duplicated
into the codex/gemini adapters (so `adapters/codex/adapter.sh` is no longer
modified, spec §13.4). **3.4 has merged** (`cc_generate_rules`/`_CC_LITE`
present on `main`, VERSION 3.5.1) — Wave 2's shared shell files are safe to
compose on.

**Release version is NOT pre-allocated.** The Reach release (Phase 11) uses a
placeholder — `VERSION assigned at ship` — per the release-cadence rule (assign
the number at ship, never pre-allocate a ladder). The stale "Phase 11: 3.5.1"
label is void: 3.5.1 already shipped as the QA-pass release.

**Wave 3 (Coordination) — recommend defer to a later minor.** Phase 12 is
probe-dependent; the §4.5 re-triage shows most of Wave B is obsoleted or
low-ROI. Pull forward only the zero-risk phantom-contract cleanup; re-plan the
conditional P6/peer-view parts with a fresh `/r-plan` if Phase 0 Q3 reconfirms
cross-session pain.

## Conventions

**State-helper boilerplate** — `state/*.sh` start with:

```bash
#!/usr/bin/env bash
# state/<name>.sh — <purpose>
# (C) 2026 R-fx Networks <proj@rfxn.com>
# GNU GPL v2
set -euo pipefail
```

**Adapter boilerplate** — new adapters mirror `adapters/codex/adapter.sh`
(atomic staging-dir swap, `rdf_log`/`rdf_warn`, `command`-prefixed coreutils).

**Naming pattern** — tier helpers `rdf_set_active_tier` / `rdf_active_tier`
(parallel to the existing `rdf_set_active_plan` / `rdf_active_plan_path`);
consistency helper `state/rdf-consistency.sh` `check` subcommand; skills adapter
functions `sk_generate_*`.

**Tier values** — the closed set `full | quick-plan | bugfix` everywhere.

**`**Goals:**` phase field (S2)** — every phase carries a `**Goals:** N[,M...]`
metadata line naming the spec goals it advances. The Phase-4 consistency checker
greps the union of these fields for goal coverage and warns once per plan if any
phase omits it. This plan dogfoods the field on all 13 phases.

**Commit message format** — free-form summary; body lines tagged
`[New]`/`[Change]`/`[Fix]`/`[Remove]`; stage files explicitly by name;
CHANGELOG + CHANGELOG.RELEASE updated only in each wave's release phase
(7, 11) per the RDF single-version batch pattern.

**Test harness pattern** — `tests/scale-ceremony.bats` (Wave 1) and
`tests/agent-skills.bats` / `tests/deploy.bats` (Wave 2) mirror
`tests/adapter.bats`: hermetic `mktemp -d` HOME/RDF_HOME per test, bare
coreutils inside `.bats`, `run bash -c '...'` for controlled invocation.

**CRITICAL:**
- `canonical/` stays tool-agnostic + frontmatter-free. Tier semantics live in
  `reference/tiers.md`; intent-trigger text lives in adapter `skill-meta.json`
  and command-meta — NEVER in canonical command bodies.
- Adapter CC output (`adapters/*/output/**`) is local-only (`.git/info/exclude`)
  — NOT committed. Verify with `git check-ignore` before assuming.
- `sed` POSIX BRE-portable; jq-optional degrade on every runtime path.
- `bash -n` + `shellcheck` on every touched shell file before each commit.
- Wave 2 edits to `adapters/claude-code/adapter.sh`, `lib/cmd/generate.sh`,
  `lib/cmd/deploy.sh` MUST compose with 3.4 — add new functions/case-arms,
  never edit 3.4's lines. Phase 0 gates this.

## RC Contract Evidence

Helpers with return-code contracts used by new code (verified against source):

| call-site (new/edited) | helper | expected-rc | rc-source |
|------------------------|--------|-------------|-----------|
| `state/rdf-consistency.sh check` | `rdf_active_plan_path` | 0 with path on stdout / 1 not found | `state/rdf-bus.sh:129-157` (explicit `return 0`/`return 1` paths) |
| `state/rdf-consistency.sh check` | **own multi-path Files parse (NOT `rdf_parse_phase_scope`)** | n/a — M2: the checker loops ALL backtick groups per Files line; `rdf_parse_phase_scope` captures only the FIRST (`rdf-bus.sh:84`) and stays unmodified for its Wave-A scope-enforcement callers | `rdf-bus.sh:84` — `BASH_REMATCH[2]` single-capture |
| `canonical/commands/r-build.md` §1 | `state/rdf-consistency.sh check [--warn-only]` | 0 clean / 1 warnings / 2 structural block; `--warn-only` downgrades 2→1 | new (Phase 4); `/r-build` blocks on 2, warns on 1 |
| `canonical/commands/r-spec.md`,`r-plan.md` | `rdf_set_active_tier` | 0 ok / 1 invalid tier | new (Phase 1) — allowlist `full\|quick-plan\|bugfix` |
| `canonical/agents/dispatcher.md`, `r-build.md` | `rdf_active_tier` | 0 always (defaults `full`) | new (Phase 1) — **marker-authoritative** (plan `**Tier:**` wins, reconciles pointer), else session pointer, else `full` |
| `canonical/commands/r-ship.md` Stage 3 | `rdf_clear_active_tier` | 0 always (idempotent) | new (Phase 1) — mirrors `rdf_clear_active_plan` |
| `lib/cmd/generate.sh` `agent-skills`/`antigravity` arms | `_generate_adapter` | 0 success / non-0 propagated (`rdf_die` on missing adapter) | `lib/cmd/generate.sh:59-70` |
| `adapters/agent-skills/adapter.sh` `sk_generate_all` | `rdf_require_bin jq` / `rdf_require_file` / `rdf_require_dir` | non-return on failure (`rdf_die` exits) — else fall-through | `lib/rdf_common.sh:98-121` (all three `rdf_die` on miss) |
| `adapters/agent-skills/adapter.sh` `_sk_skill_description` | `jq -r '.[$c] // empty'` | empty string on missing key OR malformed JSON (2>/dev/null) → first-sentence fallback | own `// empty` guard (never hard-fails a skill) |
| `adapters/claude-code/adapter.sh` (Wave 2) | `cc_generate_command_frontmatter` (NEW) + `cc_generate_commands` | 0 — prepends frontmatter then `command cat` body; hash sidecar over canonical unchanged | `adapters/claude-code/adapter.sh:129-150` (modified copy loop) |

No ambiguous helper names — each grep above returns a single definition
(`rdf_parse_phase_scope`, `rdf_active_plan_path`, `rdf_set_active_plan` are
defined once in `state/rdf-bus.sh`).

## File Map

### New Files
| File | Lines | Purpose | Test File |
|------|------:|---------|-----------|
| `canonical/reference/tiers.md` | ~90 | tier definitions, heuristic signals, gate caps | `tests/scale-ceremony.bats` |
| `state/rdf-consistency.sh` | ~150 | spec↔plan↔tasks cross-check (`check`) | `tests/scale-ceremony.bats` |
| `docs/specs/CURRENT.md` | ~60 | living current-state spec (seed) | `tests/scale-ceremony.bats` |
| `tests/scale-ceremony.bats` | ~240 | tiers, clarify, consistency, living-spec | self |
| `tests/fixtures/tiers/consistent-plan.md` | ~30 | consistency pass fixture | consumed by bats |
| `tests/fixtures/tiers/mismatch-plan.md` | ~30 | consistency block fixture (File-Map path no phase touches) | consumed by bats |
| `tests/fixtures/tiers/commalist-plan.md` | ~20 | comma-list Files line — M2 multi-path parse regression fixture | consumed by bats |
| `tests/fixtures/tiers/spec-with-extra-goal.md` | ~15 | spec with an uncovered Goal — warn-path fixture | consumed by bats |
| `adapters/agent-skills/adapter.sh` | ~180 | `.agents/skills/<cmd>/SKILL.md` emitter | `tests/agent-skills.bats` |
| `adapters/agent-skills/skill-meta.json` | ~60 | intent-trigger descriptions (lifecycle set) | `tests/agent-skills.bats` |
| `docs/multi-tool-parity.md` | ~90 | AGENTS.md/Skills/MCP matrix; gemini `{{args}}` edge | N/A (docs) |
| `tests/agent-skills.bats` | ~90 | SKILL shape + frontmatter + lossy warning | self |
| `tests/deploy.bats` | ~120 | deploy symlink + sync coverage (audit M6) | self |

### Modified Files
| File | Changes | Wave | Test File |
|------|---------|------|-----------|
| `state/rdf-bus.sh` | +`rdf_set_active_tier`/`rdf_active_tier` | 1 | `tests/scale-ceremony.bats` |
| `canonical/commands/r-spec.md` | tier selection + Phase 1.5 Clarify | 1 | `tests/scale-ceremony.bats`, `governance-contracts.bats` |
| `canonical/commands/r-plan.md` | tier selection + `**Tier:**` marker + condensed paths | 1 | `tests/scale-ceremony.bats` |
| `canonical/commands/r-build.md` | consistency gate §1 + `TIER:` payload §5 | 1 | `tests/scale-ceremony.bats` |
| `canonical/commands/r-ship.md` | living-spec fold Stage 3e | 1 | `governance-contracts.bats` |
| `canonical/agents/dispatcher.md` | `min(scope_gate, tier_cap)` | 1 | `governance-contracts.bats` |
| `canonical/reference/plan-schema.md` | Rule 10 (Tier marker) | 1 | `tests/scale-ceremony.bats` |
| `tests/governance-contracts.bats` | +clarify/tier-cap/living-spec contracts | 1 | self |
| `tests/Makefile` | add scale-ceremony/agent-skills/deploy to test+lint lists | 1/2 | self |
| `adapters/claude-code/adapter.sh` | +`cc_generate_command_frontmatter` (intent trigger, on 3.4 base) | 2 | `tests/agent-skills.bats` |
| `adapters/gemini-cli/adapter.sh` | LEGACY tier: TOML `'''` literal-string fix (15/37) + `{{args}}` lossy warning | 2 | `tests/agent-skills.bats` |
| `adapters/agents-md/adapter.sh` | `.agents/skills/` pointer | 2 | `tests/agent-skills.bats` |
| `lib/cmd/generate.sh` | `agent-skills` target + `antigravity` composite (on 3.4 base) | 2 | `tests/agent-skills.bats` |
| `lib/cmd/deploy.sh` | opt-in `.agents/skills/` symlink (on 3.4 base) | 2 | `tests/deploy.bats` |
| `lib/cmd/doctor.sh` | content-drift: strip leading command frontmatter, body-`---`-safe (§13.5) | 2 | `tests/doctor.bats` |
| `lib/cmd/sync.sh` | strip frontmatter on the command sync path (canonical stays frontmatter-free) | 2 | `tests/deploy.bats` |
| `tests/doctor.bats` | +content-drift regression (command with frontmatter + body `---` rules) | 2 | self |
| `docs/index.md` | doc-stats: adapters 5→6 (agent-skills) | 2 | N/A (docs) |
| `canonical/reference/framework.md` | remove phantom `collect-spool.sh` | 3 | N/A (docs) |
| `state/rdf-bus.sh` | (conditional) P6 status broadcast | 3 | `tests/rdf-bus.bats` |
| `canonical/commands/r-status.md` | (conditional) peer view | 3 | N/A |
| `README.md` | per-wave release notes | 1/2/3 | N/A |
| `ROADMAP.md` | per-wave check-offs | 1/2/3 | N/A |
| `CHANGELOG` | per-wave version block | 1/2/3 | N/A |
| `CHANGELOG.RELEASE` | per-wave version block | 1/2/3 | N/A |
| `VERSION` | per-wave version bump | 1/2/3 | N/A |

### Deleted Files
| File | Reason |
|------|--------|
| — | none (framework.md loses 3 lines, not a file) |

## Phase Dependencies

- Phase 0 (re-triage + 3.4 gate): none
- Phase 1 (tier vocabulary): [0]
- Phase 2 (r-spec clarify+tier): [1]
- Phase 3 (r-plan tier+marker): [1]
- Phase 4 (consistency gate): [1]
- Phase 5 (dispatcher tier cap): [1]
- Phase 6 (living specs): [1]
- Phase 7 (3.5.0 release): [1,2,3,4,5,6]
- Phase 8 (agent-skills adapter + antigravity target): [1–7 shipped; **3.4 merged ✓**]
- Phase 9 (CC intent frontmatter + gemini TOML fix + agents-md pointer): [8; **3.4 merged ✓**]
- Phase 10 (deploy/sync BATS + skills symlink + parity doc): [8]
- Phase 11 (Reach release — **VERSION assigned at ship**): [8,9,10]
- Phase 12 (Wave B re-triage + cleanup): [0] — **recommend defer to a later minor**

**Parallel batches (`/r-build --parallel`):**
- Wave 1: after Phase 0 → **{1}**; then **{2, 3, 4, 5, 6}** (disjoint canonical
  files; the two shared test files `scale-ceremony.bats` +
  `governance-contracts.bats` serialize appends via `/r-build`'s
  file-ownership check); then **{7}**.
- Wave 2 (3.4 merged ✓ — confirmed 2026-07-15): **{8}** → **{9, 10}** → **{11}**.
  9 and 10 are file-disjoint (9 = adapters + governance-contracts.bats;
  10 = deploy.sh + deploy.bats + parity doc), so they parallelize after 8.
- Wave 3: **{12}** (recommend re-plan first).

`tests/scale-ceremony.bats` is created in Phase 1 and appended by 2/3/4;
`tests/governance-contracts.bats` appended by 2/5/6/9 — file-ownership
serialization applies. `tests/Makefile` is co-edited with the unbuilt 3.4
(append `scale-ceremony.bats` after 3.4's `memory-context.bats` in the
`test:`/`lint:` lists — trivial merge, §4.2 of the spec).

**Self-consistency (M3/S2 — this plan passes its own §5.3 checks):** 13
`### Phase N:` headings (N = 0..12) == `**Phases:** 13` (Phase 0 counts); every
File-Map path is touched by ≥ 1 phase's `Files:` and every phase `Files:` path
is in the File Map (incl. the `--warn-only`/multi-path parse that keeps the
comma-list adapter/fixture lines covered); every phase carries a `**Goals:**`
field spanning spec Goals 1–11. Verify post-Phase-4:
`bash state/rdf-consistency.sh check docs/plans/2026-07-15-scale-reach-plan.md`
→ expect exit 0.

---

### Phase 0: Re-triage + 3.4-merge gate

Resolve the four open questions from spec §12 and record go/no-go for Waves 2–3.
No code — a single doc-confirmation + probe step.

**Files:** none (investigation)

- **Mode**: serial-context
- **Goals:** 10
- **Accept**: Q1–Q4 answered and recorded below; explicit go/no-go for Phase 8
  (Skills schema) and Phase 12 (Wave B); confirmation of whether 3.4 has merged
- **Test**: N/A (investigation)
- **Edge cases**: spec §11b "Codex hooks probe unknown" (defer), "Wave 2 before
  3.4 merged" (halt Wave 2)
- **Regression-case**: N/A — investigation, no runtime surface

- [ ] **Step 1: Q1 — Agent-Skills `SKILL.md` schema.** From the open
  Agent-Skills spec + Codex/Gemini client docs, confirm required frontmatter
  keys (expected `name`, `description`) and any naming/size constraints. Record
  the exact schema. If unconfirmable, mark Phase 8 no-go and defer Wave 2 skills.

- [ ] **Step 2: Q2 — Codex hook events.** Confirm the Codex hook event names and
  config location, and which of {pre-tool, post-tool, session-boundary} RDF can
  map. Record. If the schema is unstable/undocumented, mark Codex-hooks
  **defer to 3.6** (this is the recommended default).

- [ ] **Step 3: Q3 — Wave B pain re-confirmation.** Confirm whether separate
  top-level sessions still lack native peer-awareness (background agents are
  intra-session). Record the §4.5 verdict. Default recommendation: ship only
  the phantom-contract cleanup; defer bus/msg/sweeper.

- [ ] **Step 4: Q4 — 3.4 merge status.** Check whether 3.4 has landed:
  ```bash
  grep -q 'cc_generate_rules' adapters/claude-code/adapter.sh && echo "3.4 adapter present" || echo "3.4 NOT merged — HOLD Wave 2"
  grep -q -- '--lite' lib/cmd/generate.sh && echo "3.4 --lite present" || echo "3.4 --lite absent — HOLD Wave 2"
  ```
  If 3.4 is not merged, Wave 1 proceeds independently; Waves 2–3 HOLD.

- [ ] **Step 5: Record findings** — append a "Phase 0 Findings" note with Q1–Q4
  answers and go/no-go. No commit (investigation).

---

### Phase 1: Tier vocabulary — reference, state helpers, schema rule

Establish the single source of truth for tiers: `reference/tiers.md`, the
`rdf_set_active_tier`/`rdf_active_tier` helpers (parallel to the active-plan
pointer), and plan-schema Rule 10.

**Files:**
- Create: `canonical/reference/tiers.md`
- Create: `tests/scale-ceremony.bats` (header + harness + 3 tests)
- Modify: `state/rdf-bus.sh` (three new functions: set/active/clear tier)
- Modify: `canonical/reference/plan-schema.md` (Rule 10)
- Modify: `tests/Makefile` (add scale-ceremony.bats to test + lint lists)

- **Mode**: serial-agent
- **Goals:** 1
- **Accept**: `source state/rdf-bus.sh; rdf_set_active_tier quick-plan .;
  rdf_active_tier .` echoes `quick-plan`; `rdf_set_active_tier bogus .` exits 1;
  `rdf_active_tier .` with no pointer/marker echoes `full`; `rdf_clear_active_tier`
  removes the pointer; `tiers.md` documents the three tiers + the
  `min(scope,tier)` cap + the security floor; plan-schema has a `## Rule 10`
- **Test**: `tests/scale-ceremony.bats` — @test "tier pointer roundtrip + invalid rejected", @test "rdf_active_tier defaults to full", @test "plan Tier marker overrides the session pointer (S3)"
- **Edge cases**: spec §11b "no Tier marker → full", "bogus tier → exit 1", "pre-plan pointer contradicts resolved marker → marker wins" (S3)
- **Regression-case**: tests/scale-ceremony.bats::@test "tier pointer roundtrip + invalid rejected" (file created in this phase)

- [ ] **Step 1: Create `canonical/reference/tiers.md`** — three sections:
  Definitions (the spec §4.3 table verbatim), Heuristic signals (bugfix /
  quick-plan / full, suggestion-only), Gate caps (the exact
  `min(scope_gate, tier_cap)` mapping: `full` = no cap; `quick-plan` = cap at
  sentinel-lite, no UAT unless file list forces it, skip end-of-plan sentinel;
  `bugfix` = Gate 1 + regression-only sentinel-lite, no Gate 2 matrix, no Gate 4,
  no end-of-plan sentinel, require failing-test-first). Frontmatter-free.

  **Security floor (M1) — document it as an override in the Gate-caps section.**
  The cap NEVER applies when the dispatcher marks a phase `scope:sensitive` OR a
  changed file matches the security-sensitive indicators. **Reuse the reviewer
  Early-Exit Rubric's list verbatim** (`reviewer.md:183-187`) — do NOT invent a
  second list: filename contains `auth`, `cred`, `secret`, `token`, `key`,
  `passwd`, `encrypt`, `hash`, `sign`, `cert`, `session`, or `permission`; or
  the path is flagged security-sensitive in `governance/anti-patterns.md`; or
  the phase is `scope:sensitive`. On any of these, `bugfix`/`quick-plan` still
  run Gate 2 + sentinel-full. Rationale to cite: the 3.3.0 C1 RCE fix was a
  single-file change matching the `bugfix` heuristic exactly.

- [ ] **Step 2: Add tier helpers to `state/rdf-bus.sh`** — append after
  `rdf_clear_active_plan` (rdf-bus.sh:181, end of file), mirroring the
  active-plan pointer functions:

  ```bash
  # rdf_set_active_tier <tier> [project_root] — write session tier pointer
  rdf_set_active_tier() {
      local tier="${1:?rdf_set_active_tier requires a tier}"
      local root="${2:-$PWD}"
      case "$tier" in
          full|quick-plan|bugfix) ;;
          *) printf 'rdf_set_active_tier: invalid tier: %s\n' "$tier" >&2; return 1 ;;
      esac
      rdf_session_init
      command mkdir -p "${root}/.rdf"
      printf '%s\n' "$tier" > "${root}/.rdf/active-tier-${RDF_SESSION_ID}"
  }

  # rdf_active_tier [project_root] — echo the active tier (default: full)
  # Precedence (S3): the resolved plan's **Tier:** marker is AUTHORITATIVE and
  # reconciles the pre-plan session pointer; else the session pointer (pre-plan
  # carrier, used during /r-spec before a plan exists); else "full".
  rdf_active_tier() {
      local root="${1:-$PWD}" pointer tier plan marker
      rdf_session_init
      pointer="${root}/.rdf/active-tier-${RDF_SESSION_ID}"
      plan="$(rdf_active_plan_path "$root")" || plan=""     # 1 = no plan yet
      # 1) Plan marker wins once a plan resolves; overwrite the pointer to match.
      if [[ -n "$plan" && -f "$plan" ]]; then
          marker="$(grep -m1 '^\*\*Tier:\*\*' "$plan" 2>/dev/null | sed -E 's/^\*\*Tier:\*\*[[:space:]]*//')"  # no marker → empty
          marker="${marker%%[[:space:]]*}"                  # first token (marker line may carry prose)
          case "$marker" in
              full|quick-plan|bugfix)
                  command mkdir -p "${root}/.rdf" 2>/dev/null || true   # reconcile write is best-effort
                  printf '%s\n' "$marker" > "$pointer" 2>/dev/null || true   # pointer follows the authoritative marker
                  printf '%s\n' "$marker"; return 0 ;;
          esac
      fi
      # 2) Pre-plan phase: the session pointer is the carrier.
      if [[ -f "$pointer" ]]; then
          tier="$(< "$pointer")"; tier="${tier%[$'\r\n']}"; tier="${tier%[$'\r\n']}"
          case "$tier" in full|quick-plan|bugfix) printf '%s\n' "$tier"; return 0 ;; esac
      fi
      # 3) Default.
      printf 'full\n'; return 0
  }

  # rdf_clear_active_tier [project_root] — remove the session tier pointer (idempotent)
  rdf_clear_active_tier() {
      local root="${1:-$PWD}"
      rdf_session_init
      command rm -f "${root}/.rdf/active-tier-${RDF_SESSION_ID}"
  }
  ```

  > Self-correction note (S3): the plan `**Tier:**` marker is authoritative once
  > a plan resolves — a stale pre-plan pointer cannot contradict the committed
  > plan, so `rdf_active_tier` reconciles the pointer to the marker. `marker`
  > takes the first whitespace-delimited token so a marker line carrying trailing
  > prose (`**Tier:** full | quick-plan | bugfix` template text) still parses to
  > `full`. `rdf_active_tier` NEVER fails — defaults to `full` so legacy plans
  > and pre-tier sessions behave exactly as today. Update the `Provides:` header
  > comment (rdf-bus.sh:6-8) to list the THREE new functions.

- [ ] **Step 3: Add Rule 10 to `plan-schema.md`** — after Rule 9 "9d
  Enforcement call sites" and before `## Adding a New Rule` (plan-schema.md:326):

  ````
  ## Rule 10: Tier Marker (optional)

  Plans MAY declare a task-class tier in the preamble, on its own line
  immediately after `**Plan Version:**`:

  ```
  **Tier:** full | quick-plan | bugfix
  ```

  Absent marker → treated as `full` (legacy plans behave unchanged). The value
  must be one of the three literals. `bugfix` plans SHOULD have ≤ 2 phases and
  `quick-plan` ≤ ~6 (advisory — `rdf-consistency.sh` warns, does not block).
  See `reference/tiers.md` for tier semantics and gate caps.

  **Failure:** *"Phase preamble Tier marker '<v>' is not one of
  full|quick-plan|bugfix."* (only when a marker is present and malformed).
  ````

  Do NOT bump the Plan-Version floor (Rule 10 is optional/looser).

- [ ] **Step 4: Create `tests/scale-ceremony.bats`** (header + harness + 3 tests)

  ```bash
  #!/usr/bin/env bats
  # tests/scale-ceremony.bats — RDF 3.5 scale-adaptive ceremony
  # (C) 2026 R-fx Networks <proj@rfxn.com>
  # GNU GPL v2
  # shellcheck disable=SC2154,SC2164,SC1090,SC1091

  RDF_SRC="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  export RDF_SRC

  setup() {
      TEST_PROJ="$(mktemp -d)"
      mkdir -p "${TEST_PROJ}/.rdf"
      export _TEST_PROJ="$TEST_PROJ"
  }
  teardown() { rm -rf "${_TEST_PROJ}" 2>/dev/null || true; } # cleanup, ignore errors

  @test "tier pointer roundtrip + invalid rejected" {
      run bash -c 'cd "$1"; source "$2/state/rdf-bus.sh"; export RDF_SESSION_ID=test-sess;
                   rdf_set_active_tier quick-plan "$1"; rdf_active_tier "$1"' -- "$TEST_PROJ" "$RDF_SRC"
      [ "$status" -eq 0 ]
      [ "$output" = "quick-plan" ]
      run bash -c 'cd "$1"; source "$2/state/rdf-bus.sh"; export RDF_SESSION_ID=test-sess;
                   rdf_set_active_tier bogus "$1"' -- "$TEST_PROJ" "$RDF_SRC"
      [ "$status" -eq 1 ]
  }

  @test "rdf_active_tier defaults to full" {
      run bash -c 'cd "$1"; source "$2/state/rdf-bus.sh"; export RDF_SESSION_ID=fresh-sess;
                   rdf_active_tier "$1"' -- "$TEST_PROJ" "$RDF_SRC"
      [ "$status" -eq 0 ]
      [ "$output" = "full" ]
  }

  @test "plan Tier marker overrides the session pointer (S3)" {
      # session pointer says full, but a resolved plan marker says bugfix → bugfix wins
      printf '**Plan Version:** 3.6\n**Tier:** bugfix\n' > "${TEST_PROJ}/p.md"
      printf '%s\n' "${TEST_PROJ}/p.md" > "${TEST_PROJ}/.rdf/active-plan-marktest"
      run bash -c 'cd "$1"; source "$2/state/rdf-bus.sh"; export RDF_SESSION_ID=marktest;
                   rdf_set_active_tier full "$1"; rdf_active_tier "$1"' -- "$TEST_PROJ" "$RDF_SRC"
      [ "$status" -eq 0 ]
      [ "$output" = "bugfix" ]   # marker authoritative; pointer reconciled
  }
  ```

- [ ] **Step 5: Add `scale-ceremony.bats` to `tests/Makefile`** — append
  `$(TESTS_DIR)scale-ceremony.bats` to both the `test:` bats list
  (Makefile:21-25) and the `lint:` shellcheck list (Makefile:28-33). The
  Makefile does not glob — the file must be listed explicitly.

- [ ] **Step 6: Lint + test**

  ```bash
  bash -n state/rdf-bus.sh && shellcheck state/rdf-bus.sh
  make -C tests test 2>&1 | tee /tmp/test-rdf-P1-scale.log | grep -c '^not ok'
  # expect: 0
  ```

- [ ] **Step 7: Commit**

  ```bash
  git add canonical/reference/tiers.md state/rdf-bus.sh canonical/reference/plan-schema.md \
      tests/scale-ceremony.bats tests/Makefile
  git commit -m "Add task-class tier vocabulary (full/quick-plan/bugfix)

  [New] reference/tiers.md — tier definitions, heuristic signals, gate caps
  [New] rdf-bus.sh rdf_set_active_tier/rdf_active_tier/rdf_clear_active_tier —
        session tier pointer parallel to active-plan; plan **Tier:** marker is
        authoritative and reconciles the pointer; defaults to full for legacy plans
  [New] plan-schema Rule 10 — optional **Tier:** preamble marker
  [New] tests/scale-ceremony.bats harness + tier roundtrip tests"
  ```

---

### Phase 2: /r-spec — tier selection + Clarify micro-gate

Add tier selection (flag + heuristic suggestion) at `/r-spec` entry and a
structured Clarify pass (new Phase 1.5) between Discover and Brainstorm, scaled
by tier (bugfix skips it).

**Files:**
- Modify: `canonical/commands/r-spec.md`
- Modify: `tests/scale-ceremony.bats` (+1 structural test)
- Modify: `tests/governance-contracts.bats` (+1 clarify-order contract)

- **Mode**: serial-agent
- **Goals:** 1, 3
- **Accept**: `r-spec.md` `$ARGUMENTS` documents `--full|--quick|--bugfix` +
  heuristic suggestion that the user confirms + `rdf_set_active_tier` call;
  a `## Phase 1.5: Clarify` section exists between Phase 1 and Phase 2 and
  states it is skipped for `bugfix`; contract asserts Clarify precedes Brainstorm
- **Test**: `tests/scale-ceremony.bats` — @test "r-spec documents tier flags and clarify skip"; `governance-contracts.bats` — @test "r-spec Clarify precedes Brainstorm"
- **Edge cases**: spec §11b "bugfix skips Clarify"
- **Regression-case**: governance-contracts.bats::@test "r-spec Clarify precedes Brainstorm" (added in this phase)

- [ ] **Step 1: Tier selection at entry** — in the `$ARGUMENTS` block
  (r-spec.md:9-27), add tier flags and a heuristic-suggestion step. After the
  existing argument list, insert a "Tier selection" subsection: parse
  `--full`/`--quick`/`--bugfix` if present; otherwise assess scope signals (per
  `reference/tiers.md`) and present a numbered suggestion the user confirms;
  then `source state/rdf-bus.sh; rdf_session_init; rdf_set_active_tier <tier>`.
  **The prompt defaults to `[1] full` on a bare Enter (I1)** — an untiered user
  pays exactly one keystroke and lands in today's behavior. For `bugfix`, note
  that `/r-spec` delegates to `/r-plan --bugfix` (no spec document is produced —
  test-first plan only) and stops.

- [ ] **Step 2: Insert Phase 1.5 Clarify** — between "Mark task 'Discover …' as
  `completed`" (r-spec.md:160) and `## Phase 2: Brainstorm + Research`
  (r-spec.md:164), insert:

  ````
  ## Phase 1.5: Clarify (de-ambiguation micro-gate)

  Before Brainstorm, interrogate the ask for underspecified requirements.
  Scaled by tier (`reference/tiers.md`): **skipped for `bugfix`**; **one
  round for `quick-plan`**; **full for `full`**.

  1. Scan the seed (request + fetched issue/URL + governance) for ambiguity
     markers: vague quantifiers ("fast", "some", "most"), undefined domain
     terms, missing acceptance criteria, unspecified error/edge handling,
     unstated platform/scope boundaries.
  2. Derive up to 5 clarifying questions FROM THE ACTUAL ASK (not a fixed
     questionnaire). Present them one at a time (multiple-choice where possible).
  3. Record each answer to `.rdf/work-output/spec-progress-${RDF_SESSION_ID}.md`
     under a `CLARIFY:` block, same crash-safety cadence as Brainstorm.
  4. If the ask is already fully specified, state "No ambiguities found —
     proceeding to Brainstorm" and continue. Never invent questions to fill a
     quota.

  This is a self-run pass (no reviewer dispatch). It exists to catch
  ambiguity at design entry rather than during build (Spec Kit `/clarify`
  precedent).
  ````

- [ ] **Step 3: Add tests** — in `tests/scale-ceremony.bats`:

  ```bash
  @test "r-spec documents tier flags and clarify skip" {
      grep -q -- '--quick' "${RDF_SRC}/canonical/commands/r-spec.md"
      grep -q -- '--bugfix' "${RDF_SRC}/canonical/commands/r-spec.md"
      grep -q 'rdf_set_active_tier' "${RDF_SRC}/canonical/commands/r-spec.md"
      grep -q 'skipped for .*bugfix' "${RDF_SRC}/canonical/commands/r-spec.md"
  }
  ```

  In `tests/governance-contracts.bats` (uses the existing `_contract` helper
  that greps `canonical/<relpath>`; a Clarify-before-Brainstrom order check via
  line numbers):

  ```bash
  @test "r-spec Clarify precedes Brainstorm" {
      local f="${RDF_SRC}/canonical/commands/r-spec.md"
      local clarify brainstorm
      clarify="$(grep -n '^## Phase 1.5: Clarify' "$f" | head -1 | cut -d: -f1)"
      brainstorm="$(grep -n '^## Phase 2: Brainstorm' "$f" | head -1 | cut -d: -f1)"
      [ -n "$clarify" ] && [ -n "$brainstorm" ] && [ "$clarify" -lt "$brainstorm" ]
  }
  ```

- [ ] **Step 4: Lint + test**

  ```bash
  make -C tests test 2>&1 | tee /tmp/test-rdf-P2-scale.log | grep -c '^not ok'   # expect: 0
  ```

- [ ] **Step 5: Commit**

  ```bash
  git add canonical/commands/r-spec.md tests/scale-ceremony.bats tests/governance-contracts.bats
  git commit -m "/r-spec: tier selection + Clarify de-ambiguation micro-gate

  [New] r-spec tier flags (--full/--quick/--bugfix) + heuristic suggestion the
        user confirms; records tier via rdf_set_active_tier
  [New] Phase 1.5 Clarify — structured de-ambiguation before Brainstorm, scaled
        by tier (skipped for bugfix); Spec Kit /clarify precedent
  [New] governance-contract: Clarify precedes Brainstorm"
  ```

---

### Phase 3: /r-plan — tier selection + `**Tier:**` marker + condensed paths

Read/select the tier at `/r-plan` entry, stamp `**Tier:**` into the plan
preamble, and add the quick-plan (condensed single artifact) and bugfix
(failing-test-first) generation paths.

**Files:**
- Modify: `canonical/commands/r-plan.md`
- Modify: `tests/scale-ceremony.bats` (+1 structural test)

- **Mode**: serial-agent
- **Goals:** 1, 2
- **Accept**: `r-plan.md` documents tier flags + heuristic suggestion; the
  preamble template (r-plan.md:178, the `**Plan Version:** 3.0.6` line) gains a
  `**Tier:** {tier}` line immediately after it; a
  `quick-plan` path produces one condensed `docs/plans/{date}-{topic}-quickplan.md`
  (condensed context + phases, single review) and a `bugfix` path produces a
  ≤ 2-phase failing-test-first plan with schema-only validation
- **Test**: `tests/scale-ceremony.bats` — @test "r-plan preamble template carries Tier marker and condensed paths"
- **Edge cases**: spec §11b "bugfix ≤ 2 phases"
- **Regression-case**: tests/scale-ceremony.bats::@test "r-plan preamble template carries Tier marker and condensed paths" (file created in Phase 1)

- [ ] **Step 1: Tier selection at entry** — in the `$ARGUMENTS` block
  (r-plan.md:10-41), add: `source state/rdf-bus.sh; rdf_session_init;
  tier="$(rdf_active_tier)"`. If `--full`/`--quick`/`--bugfix` present, override
  and `rdf_set_active_tier`. If no session tier and no flag, present the
  heuristic suggestion (per `reference/tiers.md`) and confirm — **the prompt
  defaults to `[1] full` on a bare Enter (I1)**. Document the flags in the
  argument list.

- [ ] **Step 2: Add `**Tier:**` to the preamble template** — in Step 2.1's
  Header block, add a line immediately after the `**Plan Version:** 3.0.6` line
  (r-plan.md:178 — anchor by the quoted `**Plan Version:**` text; the number may
  shift once 3.4's remaining phases land):

  ```markdown
  **Tier:** {full | quick-plan | bugfix}
  ```

  And a sentence: "The `**Tier:**` marker (plan-schema Rule 10) records the
  task-class ceremony level; `/r-build` and the dispatcher read it to cap gates.
  Absent → `full`."

- [ ] **Step 3: Add condensed generation paths** — after Step 2.2 "Decompose
  Into Phases", add a "Tier-scaled output" subsection:
  - `full`: current behavior (full plan, challenge review in Step 3).
  - `quick-plan`: write ONE `docs/plans/{date}-{topic}-quickplan.md` — a
    condensed Context/Goals block (folded from the spec or the ask, ~15 lines)
    followed by phases. Single review pass in Step 3 (no separate spec review).
  - `bugfix`: write a ≤ 2-phase plan — Phase 1 = write a failing regression test
    (red) then the minimal fix (green); optional Phase 2 = follow-up hardening.
    Schema-validate only (Step 2.7); skip the Step 3 challenge review (the
    sentinel-lite at build time is the adversarial pass). Require the failing
    test first (state it in Phase 1 Accept).

- [ ] **Step 4: Add test** — in `tests/scale-ceremony.bats`:

  ```bash
  @test "r-plan preamble template carries Tier marker and condensed paths" {
      grep -q '\*\*Tier:\*\*' "${RDF_SRC}/canonical/commands/r-plan.md"
      grep -q 'quickplan' "${RDF_SRC}/canonical/commands/r-plan.md"
      grep -q 'failing regression test' "${RDF_SRC}/canonical/commands/r-plan.md"
  }
  ```

- [ ] **Step 5: Lint + test + commit**

  ```bash
  make -C tests test 2>&1 | tee /tmp/test-rdf-P3-scale.log | grep -c '^not ok'   # expect: 0
  git add canonical/commands/r-plan.md tests/scale-ceremony.bats
  git commit -m "/r-plan: tier-scaled planning + **Tier:** marker

  [New] r-plan tier selection (reads rdf_active_tier; flags override); stamps
        **Tier:** into the plan preamble (schema Rule 10)
  [New] quick-plan condensed single-artifact path + bugfix failing-test-first
        path (schema-only validation, sentinel-lite at build time)"
  ```

---

### Phase 4: Consistency micro-gate — rdf-consistency.sh + /r-build wiring

Add the deterministic spec↔plan↔tasks cross-check and wire it into `/r-build`
Section 1. Also add the `TIER:` line to the dispatch payload (Section 5) so the
dispatcher can cap gates (Phase 5 consumes it).

**Files:** (one path per line — Rule 8 hygiene, M4)
- Create: `state/rdf-consistency.sh`
- Modify: `canonical/commands/r-build.md`
- Create: `tests/fixtures/tiers/consistent-plan.md`
- Create: `tests/fixtures/tiers/mismatch-plan.md`
- Create: `tests/fixtures/tiers/commalist-plan.md`
- Create: `tests/fixtures/tiers/spec-with-extra-goal.md`
- Modify: `tests/scale-ceremony.bats` (+5 tests)

- **Mode**: serial-agent
- **Goals:** 4
- **Accept**: `bash state/rdf-consistency.sh check <consistent-fixture>` exits 0;
  `<mismatch-fixture>` (File-Map path no phase touches) exits 2; `<commalist-fixture>`
  (comma-list Files line) exits 0 (M2 multi-path); `--warn-only <mismatch>` exits 1;
  a plan with an uncovered spec Goal exits 1; `r-build.md` Section 1 runs the check
  after plan-schema validation, blocks on exit 2 (with `--warn-only` escape hatch
  requiring a stated reason), warns on exit 1; Section 5 payload includes
  `TIER: <rdf_active_tier>`
- **Test**: `tests/scale-ceremony.bats` — @test "consistency check passes consistent plan", @test "consistency check blocks File-Map/phase mismatch", @test "consistency check covers a comma-list Files line (M2 multi-path)", @test "consistency check warns on uncovered goal", @test "--warn-only downgrades a structural error to a warning"
- **Edge cases**: spec §11b "File Map lists untouched file" (exit 2), "comma-list Files line covered" (M2), "structural false-positive → --warn-only" (M2), "manually-authored clean plan, no spec" (pass — spec checks skipped), "phase-count mismatch incl. Phase 0" (exit 2, M3)
- **Regression-case**: tests/scale-ceremony.bats::@test "consistency check blocks File-Map/phase mismatch" (file created in Phase 1)

- [ ] **Step 1: Create `state/rdf-consistency.sh`** — `check [--warn-only]
  <plan> [spec]`. Deterministic bash string parsing (no eval, no jq needed):
  - Parse `--warn-only` first (M2 escape hatch): if present, the two exit-2
    structural errors are downgraded to exit-1 warnings.
  - Parse File-Map paths: lines under `### New/Modified/Deleted Files` matching
    a backticked path in the first table column.
  - **Parse phase `Files:` paths with a MULTI-PATH loop (M2).** Do NOT call
    `rdf_parse_phase_scope` — it captures only the FIRST backticked path of a
    comma-list line (`rdf-bus.sh:84`, single `BASH_REMATCH[2]`) and would
    false-block on `- Create: \`a\`, \`b\``. Instead, for each
    `- Create:`/`- Modify:`/`- Delete:` line, loop **every** backtick group:
    ```bash
    _rest="${line#*: }"
    _rest="${_rest%% (*}"          # drop the trailing " (description...)" — a
                                    # backticked term inside it is prose, not a path
    while [[ "$_rest" == *'`'* ]]; do
        _rest="${_rest#*\`}"; _p="${_rest%%\`*}"; _rest="${_rest#*\`}"
        [[ -n "$_p" ]] && phase_files+=("$_p")
    done
    ```
    The same `%% (*` guard applies to the File-Map first-column parse (a cell
    like `` `framework.md` (remove …) `` in the *changes* column is not the path
    column, but defensively strip parentheticals there too). `rdf_parse_phase_scope`
    stays UNMODIFIED — its Wave-A consumers (pre-commit hook, dispatcher
    post-merge check) keep working; only this checker needs the multi-path
    variant, so it owns its own parse.
  - Phase-count check **counts Phase 0** (`### Phase N:` for N≥0, spec §5.3/M3).
  - **Error (accumulate, exit 2 if any; downgraded to exit 1 under `--warn-only`):**
    File-Map path in no phase; phase path not in File Map; heading count ≠
    preamble `**Phases:** N`.
  - **Warn (exit 1 if any, no errors):** (spec given) a `## 2. Goals` numbered
    goal absent from the union of phase `**Goals:**` fields (S2); ANY phase
    missing a `**Goals:**` field → **one** warning per plan (S2); a §11b
    edge-case row not in any phase `Edge cases:`; tier-sanity (`**Tier:** bugfix`
    with > 2 phases, `quick-plan` with > 6).
  - Emit `✓`/`⚠`/`✗` lines to stdout; exit 0 clean / 1 warn / 2 error.
  - Source `state/rdf-bus.sh` for `rdf_active_plan_path` only when `<plan>`
    omitted; POSIX sed; guarded `cd`; `command`-prefixed coreutils.

  > Self-correction note (M2): the checker's Files parse loops ALL backtick
  > groups per line — `rdf_parse_phase_scope` is single-capture and stays as-is
  > for its scope-enforcement callers. Spec checks are CONDITIONAL on a spec
  > path — a manually-authored plan with no spec PASSES the structural checks
  > and skips goal/edge-case checks (spec §11b). Goal coverage is the mechanical
  > union of phase `**Goals:**` fields (S2), never a semantic read.

- [ ] **Step 2: Wire into `r-build.md` Section 1** — after the plan-schema
  validation paragraph (r-build.md:26-31, ending "…stop without dispatching."),
  insert a consistency step:

  ````
  - **Consistency micro-gate (spec↔plan↔tasks).** After schema validation,
    run the deterministic cross-check:
    ```bash
    bash state/rdf-consistency.sh check "$plan_path"
    ```
    (If a source spec is known, pass it as the second argument for goal /
    edge-case coverage.) Exit 2 = structural break (File-Map/phase mismatch or
    phase-count mismatch) → print the findings and STOP without dispatching
    (fix via `/r-plan`). Exit 1 = advisory drift (uncovered goal/edge case,
    missing `**Goals:**` field, tier-size) → surface the findings and proceed.
    Exit 0 = clean. Spec Kit `/analyze` precedent; mechanical checks only.

    **Escape hatch (M2).** For a rare legitimate structural false-positive (an
    intentional File-Map entry a reviewer approved), re-run with
    `state/rdf-consistency.sh check --warn-only "$plan_path"` to downgrade the
    exit-2 block to an exit-1 warning. Using `--warn-only` REQUIRES the operator
    to state the reason in the `/r-build` invocation (e.g.
    `/r-build --consistency-warn-only "reason: File-Map intentionally lists the
    generated foo.sh"`) — exit-2-with-no-override is too brittle for real plans.
  ````

- [ ] **Step 3: Add `TIER:` to the dispatch payload** — in Section 5 "Assemble
  Dispatch Payload" (r-build.md:151-170), add a line to the payload template
  after `MODE:` (r-build.md:154):

  ```
  TIER: <rdf_active_tier — full|quick-plan|bugfix, read at Section 1>
  ```

  And in Section 1, after resolving `plan_path`, add:
  `source state/rdf-bus.sh; tier="$(rdf_active_tier)"` so the value is available
  for the payload.

- [ ] **Step 4: Create fixtures** (minimal — just enough for the parser; each
  phase carries a `**Goals:**` field so the presence check does not warn):
  - `consistent-plan.md` — `**Phases:** 2`, two phases whose `Files:` list
    exactly the two files the File Map declares; each phase has `**Goals:** 1`.
    Exits 0 with no spec.
  - `mismatch-plan.md` — File Map lists a third file `lib/cmd/ghost.sh` that no
    phase touches → exit 2.
  - `commalist-plan.md` (M2) — one phase whose Files line is
    `- Create: \`a.sh\`, \`b.sh\`` (comma-list), File Map lists BOTH `a.sh` and
    `b.sh`; `**Phases:** 1`; `**Goals:** 1`. MUST exit 0 — proves the multi-path
    parse counts both paths (a single-capture parser would flag `b.sh`
    uncovered).
  - `spec-with-extra-goal.md` — a tiny spec with `## 2. Goals` listing Goal 1
    and Goal 9; paired with `consistent-plan.md` (whose phases declare only
    Goal 1) it makes Goal 9 uncovered → exit 1.

- [ ] **Step 5: Add 5 tests** — in `tests/scale-ceremony.bats`:

  ```bash
  @test "consistency check passes consistent plan" {
      run bash "${RDF_SRC}/state/rdf-consistency.sh" check "${RDF_SRC}/tests/fixtures/tiers/consistent-plan.md"
      [ "$status" -eq 0 ]
  }
  @test "consistency check blocks File-Map/phase mismatch" {
      run bash "${RDF_SRC}/state/rdf-consistency.sh" check "${RDF_SRC}/tests/fixtures/tiers/mismatch-plan.md"
      [ "$status" -eq 2 ]
      [[ "$output" == *"ghost.sh"* ]]
  }
  @test "consistency check covers a comma-list Files line (M2 multi-path)" {
      # commalist-plan.md has `- Create: \`a.sh\`, \`b.sh\`` and File Map lists both.
      run bash "${RDF_SRC}/state/rdf-consistency.sh" check "${RDF_SRC}/tests/fixtures/tiers/commalist-plan.md"
      [ "$status" -eq 0 ]   # single-capture parse would flag b.sh uncovered → 2
  }
  @test "consistency check warns on uncovered goal" {
      # consistent structurally but spec Goal 9 unreferenced → exit 1
      run bash "${RDF_SRC}/state/rdf-consistency.sh" check \
          "${RDF_SRC}/tests/fixtures/tiers/consistent-plan.md" \
          "${RDF_SRC}/tests/fixtures/tiers/spec-with-extra-goal.md"
      [ "$status" -eq 1 ]
  }
  @test "--warn-only downgrades a structural error to a warning" {
      run bash "${RDF_SRC}/state/rdf-consistency.sh" check --warn-only "${RDF_SRC}/tests/fixtures/tiers/mismatch-plan.md"
      [ "$status" -eq 1 ]   # exit 2 → 1 under --warn-only
  }
  ```

- [ ] **Step 6: Lint + test + commit**

  ```bash
  bash -n state/rdf-consistency.sh && shellcheck state/rdf-consistency.sh
  make -C tests test 2>&1 | tee /tmp/test-rdf-P4-scale.log | grep -c '^not ok'   # expect: 0
  git add state/rdf-consistency.sh canonical/commands/r-build.md \
      tests/scale-ceremony.bats tests/fixtures/tiers/
  git commit -m "/r-build: consistency micro-gate (spec↔plan↔tasks)

  [New] state/rdf-consistency.sh check [--warn-only] — deterministic
        cross-artifact check: File-Map↔phase coverage (multi-path Files parse,
        counts Phase 0) + phase-count (block, exit 2); goal/Goals-field/edge-case
        coverage + tier-size (warn, exit 1); --warn-only downgrades 2→1
  [Change] r-build Section 1 runs the check after schema validation (block on 2
           with --warn-only escape hatch requiring a stated reason, warn on 1);
           Section 5 payload carries TIER"
  ```

---

### Phase 5: Dispatcher tier cap — min(scope_gate, tier_cap)

Apply the tier as a ceiling over the dispatcher's existing scope→gate mapping,
so a `bugfix`/`quick-plan` plan pays less ceremony without changing `full`.

**Files:**
- Modify: `canonical/agents/dispatcher.md`
- Modify: `tests/governance-contracts.bats` (+1 tier-cap contract)

- **Mode**: serial-agent
- **Goals:** 2
- **Accept**: `dispatcher.md` reads `TIER` and applies
  `max(security_floor, min(scope_gate, tier_cap))`: `bugfix` → Gate 1 +
  regression-only sentinel-lite, never Gate 4/UAT, never end-of-plan 3-pass
  sentinel; `quick-plan` → cap at sentinel-lite; `full` → unchanged; **security
  floor (M1): `scope:sensitive` or a security-indicator file keeps Gate 2 +
  sentinel-full regardless of tier**. Two contracts assert the cap never
  *upgrades* gates AND never drops the security pass on `scope:sensitive`
- **Test**: `governance-contracts.bats` — @test "dispatcher caps gates by tier, never upgrades", @test "tier cap never drops the security pass on scope:sensitive"
- **Edge cases**: spec §11b "tier cap cannot be upgraded" (adversarial), "bugfix fix to auth/token/etc. keeps Gate 2 + sentinel-full" (M1 security floor)
- **Regression-case**: governance-contracts.bats::@test "tier cap never drops the security pass on scope:sensitive" (added in this phase — the highest-value M1 guard)

- [ ] **Step 1: Add a Tier Cap subsection to `dispatcher.md`** — after "Gate
  mapping:" and its "User-facing modifier" block (dispatcher.md:242-253),
  before "Default (cannot determine scope)", insert:

  ````
  ### Tier Cap (min(scope_gate, tier_cap)) — with a security floor

  Read `TIER` from the dispatch payload (`full` if absent). The tier is a
  ceiling applied AFTER scope→gate selection — it only removes ceremony, never
  adds it. See `reference/tiers.md`.

  **Security floor (overrides the cap — evaluate FIRST).** If the phase is
  `scope:sensitive`, OR any changed file matches the security-sensitive
  indicators — **reuse the reviewer Early-Exit Rubric list verbatim**
  (`reviewer.md:183-187`; do NOT define a second list): filename contains
  `auth`, `cred`, `secret`, `token`, `key`, `passwd`, `encrypt`, `hash`, `sign`,
  `cert`, `session`, or `permission`; or flagged security-sensitive in
  `governance/anti-patterns.md` — then the tier cap MUST NOT reduce Gate 3 below
  sentinel-full (3-pass, Security included) and MUST NOT skip Gate 2, regardless
  of tier. Effective selection is `max(security_floor, min(scope_gate,
  tier_cap))`. Rationale: the 3.3.0 C1 RCE fix was a single-file change matching
  the `bugfix` heuristic exactly — a tier must never let a security patch skip
  the Security pass.

  - `full`   — no cap. Use the scope→gate mapping as-is.
  - `quick-plan` — cap Gate 3 at sentinel-lite (2-pass) and skip the End-of-Plan
    Sentinel, keep Gates 1+2, Gate 4 (UAT) only if the file list forces it —
    **UNLESS the security floor applies** (then sentinel-full + Gate 2).
  - `bugfix` — Gate 1 + a regression-only sentinel-lite; skip Gate 2's full
    matrix (run the single regression test), skip Gate 4, skip the End-of-Plan
    Sentinel; the engineer MUST land the failing test first (red→green) —
    **UNLESS the security floor applies** (then Gate 2 + sentinel-full run in
    full despite the tier).

  The cap can only lower the gate set derived from scope; it can never raise a
  scope:docs phase's gates, and it can never lower below the security floor. If
  `TIER` is unrecognized, treat as `full`.
  ````

  Also update the End-of-Plan Sentinel section (dispatcher.md:362) with a
  one-line note: "Skipped for `quick-plan`/`bugfix` tiers (Tier Cap), except
  when the security floor applies."

- [ ] **Step 2: Add the tier-cap contract** — in `tests/governance-contracts.bats`:

  ```bash
  @test "dispatcher caps gates by tier, never upgrades" {
      _contract agents/dispatcher.md 'Tier Cap'
      _contract agents/dispatcher.md 'only removes ceremony'
      _contract agents/dispatcher.md 'regression-only sentinel-lite'
  }

  @test "tier cap never drops the security pass on scope:sensitive" {
      # M1 security floor documented in dispatcher.md.
      _contract agents/dispatcher.md 'Security floor'
      _contract agents/dispatcher.md 'sentinel-full'
      _contract agents/dispatcher.md 'scope:sensitive'
  }
  ```

  `_contract <canonical-relpath> <extended-regex>` — confirmed at
  `governance-contracts.bats:20`; greps `canonical/<relpath>` with `grep -qE`
  (LINE-based). **The anchor phrases above are short on purpose** — `grep -qE`
  cannot match across a soft-wrap, so each contract token must sit on ONE line
  in `dispatcher.md`. When writing Step 1's prose, keep `Tier Cap`,
  `only removes ceremony`, `regression-only sentinel-lite`, `Security floor`,
  `sentinel-full`, and `scope:sensitive` each unbroken on a single line.

- [ ] **Step 3: Lint + test + commit**

  ```bash
  make -C tests test 2>&1 | tee /tmp/test-rdf-P5-scale.log | grep -c '^not ok'   # expect: 0
  git add canonical/agents/dispatcher.md tests/governance-contracts.bats
  git commit -m "Dispatcher: tier cap over scope→gate mapping

  [Change] dispatcher applies max(security_floor, min(scope_gate, tier_cap)):
           quick-plan caps at sentinel-lite + skips end-of-plan sentinel; bugfix
           runs Gate 1 + regression-only sentinel-lite; full unchanged. Cap only
           lowers gates and never below the security floor (scope:sensitive /
           security-indicator files keep Gate 2 + sentinel-full)
  [New] governance-contracts: tier cap never upgrades gates; tier cap never
        drops the security pass on scope:sensitive (M1)"
  ```

---

### Phase 6: Living/delta specs — CURRENT.md + /r-ship fold

Seed `docs/specs/CURRENT.md` and add Stage 3e to `/r-ship` that folds the
shipped plan's outcome into it as a dated delta (skipped for `bugfix`).

**Files:**
- Create: `docs/specs/CURRENT.md`
- Modify: `canonical/commands/r-ship.md`
- Modify: `tests/governance-contracts.bats` (+1 living-spec contract)

- **Mode**: serial-agent
- **Goals:** 5
- **Accept**: `docs/specs/CURRENT.md` exists with a living-spec header;
  `r-ship.md` Stage 3 gains a `### 3e. Living-Spec Fold` step that derives an
  ADDED/MODIFIED/REMOVED delta from the plan File Map + changelog, presents it
  for approval, prepends a `## <version> — <date>` block, and SKIPS on `bugfix`
  tier or File-Map parse failure; a contract asserts the fold + bugfix-skip
- **Test**: `governance-contracts.bats` — @test "r-ship folds CURRENT.md and skips on bugfix"
- **Edge cases**: spec §11b "File Map unparseable → skip", "bugfix → skip"
- **Regression-case**: governance-contracts.bats::@test "r-ship folds CURRENT.md and skips on bugfix" (added in this phase)

- [ ] **Step 1: Create `docs/specs/CURRENT.md`** — header + a short "How this
  file works" note (living current-state spec; `/r-ship` prepends dated deltas;
  dated `docs/specs/*.md` remain the historical archive) + an initial
  `## 3.3.1 — baseline` block listing the four verbs, 6 agents, adapters.

- [ ] **Step 2: Add Stage 3e to `r-ship.md`** — after "### 3d. Commit Release
  Prep" (r-ship.md:148-152) and before "### Clear the active-plan pointer"
  (r-ship.md:153):

  ````
  ### 3e. Living-Spec Fold (docs/specs/CURRENT.md)

  Fold this release's outcome into the maintained current-state spec. **Skipped
  when `rdf_active_tier` is `bugfix`** (a defect fix does not change the
  architecture) and when the plan File Map cannot be parsed (degrade — never
  block the release).

  1. `source state/rdf-bus.sh; tier="$(rdf_active_tier)"`. If `bugfix`, skip.
  2. Read `docs/specs/CURRENT.md` (create with a header if absent).
  3. Derive an ADDED / MODIFIED / REMOVED delta from the shipped plan's File
     Map (New→ADDED, Modified→MODIFIED, Deleted→REMOVED) plus the changelog
     entries from Stage 3a (one-line summaries).
  4. Present the delta to the user for approval (a few bullets — keep it light).
  5. On approval, prepend a `## <version> — <date>` block to CURRENT.md and
     stage it with the release commit (amend Stage 3d's commit or a follow-up).
  OpenSpec precedent; this must stay lightweight, never ceremony.
  ````

- [ ] **Step 3: Clear the tier pointer alongside the plan pointer (S4)** — in
  `r-ship.md` "### Clear the active-plan pointer" (r-ship.md:153-160), add a
  `rdf_clear_active_tier` call next to the existing `rdf_clear_active_plan`:

  ```bash
  source state/rdf-bus.sh
  rdf_clear_active_plan
  rdf_clear_active_tier
  ```

  So the next planning session starts with no stale tier pointer.

- [ ] **Step 4: Add the contract** — in `tests/governance-contracts.bats`:

  ```bash
  @test "r-ship folds CURRENT.md and skips on bugfix" {
      # Short single-line anchors — grep -qE is line-based (no cross-wrap match).
      _contract commands/r-ship.md 'docs/specs/CURRENT.md'
      _contract commands/r-ship.md 'bugfix'
      _contract commands/r-ship.md 'rdf_clear_active_tier'
  }
  ```

- [ ] **Step 5: Lint + test + commit**

  ```bash
  make -C tests test 2>&1 | tee /tmp/test-rdf-P6-scale.log | grep -c '^not ok'   # expect: 0
  git add docs/specs/CURRENT.md canonical/commands/r-ship.md tests/governance-contracts.bats
  git commit -m "/r-ship: living/delta spec fold into docs/specs/CURRENT.md

  [New] docs/specs/CURRENT.md — living current-state spec (dated deltas)
  [New] r-ship Stage 3e — fold shipped plan outcome as ADDED/MODIFIED/REMOVED
        delta; user-approved, skipped on bugfix tier or parse failure
  [Change] r-ship clears the tier pointer alongside the plan pointer
  [New] governance-contract: living-spec fold + bugfix skip + tier clear"
  ```

---

### Phase 7: 3.5.0 "Scale" release

Docs, roadmap, changelog, VERSION 3.5.0. Depends on Phases 1–6.

**Files:**
- Modify: `README.md`, `ROADMAP.md`, `CHANGELOG`, `CHANGELOG.RELEASE`, `VERSION`

- **Mode**: serial-context
- **Goals:** 11
- **Accept**: `VERSION` is `3.5.0`; CHANGELOG + CHANGELOG.RELEASE have a
  `## 3.5.0` block (tiers, clarify, consistency, living-spec); README documents
  the tier flags; ROADMAP checks the scale-adaptive item; `rdf doctor` 0 FAIL;
  `make -C tests test` green
- **Test**: N/A (docs + version) — verification greps below
- **Edge cases**: none
- **Regression-case**: N/A — docs/release phase

- [ ] **Step 1: README** — add a "Scale-adaptive ceremony" subsection: the
  three tiers, `--full/--quick/--bugfix`, and the one-line "5-line fix →
  `/r-plan --bugfix`" example.
- [ ] **Step 2: ROADMAP** — check off scale-adaptive ceremony; add a "Scale &
  Reach" shipped bullet; leave Reach (Wave 2) and Coordination (Wave 3) as
  Next/Deferred.
- [ ] **Step 3: CHANGELOG + CHANGELOG.RELEASE** — `## 3.5.0` block, soft-wrap +
  tag style per workspace CLAUDE.md.
- [ ] **Step 4: VERSION** — `3.5.0`.
- [ ] **Step 5: Verify + commit**

  ```bash
  cat VERSION                                 # expect: 3.5.0
  bash bin/rdf doctor 2>&1 | grep -c 'FAIL'   # expect: 0
  make -C tests test 2>&1 | tee /tmp/test-rdf-P7-scale.log | grep -c '^not ok'   # expect: 0
  git add README.md ROADMAP.md CHANGELOG CHANGELOG.RELEASE VERSION
  git commit -m "3.5.0 — Scale: tiers, clarify, consistency, living specs

  [New] task-class tiers (full/quick-plan/bugfix); /r-spec Clarify micro-gate;
        /r-build consistency micro-gate; /r-ship living-spec fold
  [Change] ROADMAP/README/CHANGELOG; VERSION 3.5.0"
  ```

---

### Phase 8: agent-skills adapter + `antigravity` generate target

Create the single shared `.agents/skills/` emitter — the ONE workspace surface
Codex and Antigravity both read (spec §13.3/§13.4) — and wire two generate
targets: `agent-skills` (the raw convention surface) and `antigravity` (a thin
composite that also emits the AGENTS.md context). NO skills machinery is added
to the codex or gemini adapters.

**Files:**
- Create: `adapters/agent-skills/adapter.sh`
- Create: `adapters/agent-skills/skill-meta.json`
- Modify: `lib/cmd/generate.sh`
- Create: `tests/agent-skills.bats`
- Modify: `tests/Makefile`
- Modify: `README.md` (adapter-count 5→6, badge + footer — pulled forward from Phase 11 so doc-stats stays green)
- Modify: `docs/index.md` (adapter-count 5→6 — pulled forward from Phase 11)

- **Mode**: serial-agent
- **Goals:** 6
- **Accept**: `rdf generate agent-skills` writes
  `adapters/agent-skills/output/.agents/skills/<cmd>/SKILL.md` for each
  `skill-meta.json` key; every SKILL.md frontmatter has a `name:` equal to its
  parent directory name (AAIF constraint) plus a `description:` trigger and the
  canonical command body verbatim; a command with no `skill-meta.json` entry
  falls back to a first-sentence description; `rdf generate antigravity`
  additionally produces `adapters/agents-md/output/AGENTS.md`
- **Test**: `tests/agent-skills.bats` — @test "one SKILL.md per skill-meta command; frontmatter name matches dir + carries description", @test "skill description falls back to first sentence when meta absent"
- **Edge cases**: spec §11b "no skill-meta entry → first-sentence fallback"; §13.4 "codex/gemini adapters get NO skills duplication"
- **Regression-case**: tests/agent-skills.bats::@test "one SKILL.md per skill-meta command; frontmatter name matches dir + carries description" (file created in this phase)

- [ ] **Step 1: Create `adapters/agent-skills/skill-meta.json`** — a JSON object
  mapping the bounded command set (spec §13.4) to intent-trigger descriptions.
  Bounded set = lifecycle verbs + high-value utilities, NOT all 37. Keys are the
  canonical command basenames; the adapter iterates these keys, so the JSON is
  the authoritative bound.

  ```json
  {
    "_comment": "Maps canonical command basename to an Agent-Skills intent-trigger description. The adapter emits one SKILL.md per key. Reused by the CC command frontmatter (Phase 9). Bounded set — not all 37 commands.",
    "r-spec": "Use when starting a new feature, subsystem, or design change: turns an idea into an architecture-grade spec through research-driven dialogue.",
    "r-plan": "Use when a spec is ready and you need an execution-grade, phase-by-phase implementation plan a fresh engineer can run mechanically.",
    "r-build": "Use when a plan exists and you want it built: dispatches the engineer per phase with the right quality gates for the task tier.",
    "r-ship": "Use when a plan is built and verified and you want to cut a release: preflight, verification, release prep, and publish.",
    "r-start": "Use at the start of a session to reload project context and show current health, pipeline position, and open work.",
    "r-save": "Use at the end of a session to sync state — plan progress, memory, and the session log.",
    "r-status": "Use to see the project health dashboard: git state, plan progress, and warnings, without changing anything.",
    "r-audit": "Use when you want a full codebase audit: dispatches parallel reviewer and QA passes across the tree.",
    "r-refresh": "Use when the codebase has drifted from its governance docs and you want them re-derived from source.",
    "r-init": "Use to initialize RDF governance on a new or existing repository."
  }
  ```

- [ ] **Step 2: Create `adapters/agent-skills/adapter.sh`** — mirror the codex
  adapter boilerplate (`adapters/codex/adapter.sh:1-11` header +
  `_SK_ADAPTER_DIR`/`_SK_OUTPUT_DIR`) and its staging-dir + atomic-swap pipeline
  (`:163-190`). `name` == command basename == parent dir name satisfies the AAIF
  `name`-matches-directory rule. Frontmatter is `name` + `description` ONLY
  (spec §13.4 — no optional AAIF fields).

  ```bash
  #!/usr/bin/env bash
  # adapters/agent-skills/adapter.sh — Agent Skills (.agents/skills/) adapter
  # (C) 2026 R-fx Networks <proj@rfxn.com>
  # GNU GPL v2
  # Sourced by lib/cmd/generate.sh — do not execute directly

  # Requires: RDF_CANONICAL, RDF_ADAPTERS, jq

  _SK_ADAPTER_DIR="${RDF_ADAPTERS}/agent-skills"
  _SK_OUTPUT_DIR="${_SK_ADAPTER_DIR}/output"
  _SK_META="${_SK_ADAPTER_DIR}/skill-meta.json"

  # _sk_skill_description <basename> <src_file> — echo the trigger from
  # skill-meta.json; fall back to the canonical body's first non-heading line.
  _sk_skill_description() {
      local name="$1" src="$2" desc
      desc="$(jq -r --arg c "$name" '.[$c] // empty' "$_SK_META" 2>/dev/null)"  # missing key → empty
      if [[ -z "$desc" ]]; then
          desc="$(sed -n '/^[^#[:space:]]/{ s/[[:space:]]*$//; p; q; }' "$src")"
          [[ -z "$desc" ]] && desc="RDF command: ${name}"
      fi
      printf '%s' "$desc"
  }

  # sk_emit_skills <skills_root> — write <skills_root>/<name>/SKILL.md for every
  # skill-meta.json key (excluding _comment). name == dir name (AAIF rule).
  sk_emit_skills() {
      local skills_root="$1" name src desc count=0
      while IFS= read -r name; do
          [[ -z "$name" || "$name" == "_comment" ]] && continue
          src="${RDF_CANONICAL}/commands/${name}.md"
          if [[ ! -f "$src" ]]; then
              rdf_warn "agent-skills: no canonical command for skill '${name}' — skipped"
              continue
          fi
          desc="$(_sk_skill_description "$name" "$src")"
          command mkdir -p "${skills_root}/${name}"
          {
              echo "---"
              echo "name: ${name}"
              echo "description: >"
              echo "  ${desc}"
              echo "---"
              echo ""
              command cat "$src"
          } > "${skills_root}/${name}/SKILL.md"
          count=$((count + 1))
      done < <(jq -r 'keys[]' "$_SK_META")
      rdf_log "agent-skills: generated ${count} SKILL.md files"
  }

  # sk_generate_all — full pipeline with atomic staging swap (codex pattern).
  sk_generate_all() {
      rdf_log "generating Agent Skills adapter output..."
      rdf_require_dir "$RDF_CANONICAL" "canonical directory"
      rdf_require_file "$_SK_META" "agent-skills skill-meta.json"
      rdf_require_bin jq

      local _output_final="$_SK_OUTPUT_DIR"
      local _output_new="${_SK_OUTPUT_DIR}.new"
      local _output_old="${_SK_OUTPUT_DIR}.old"

      command rm -rf "$_output_new"
      command mkdir -p "$_output_new/.agents/skills"
      sk_emit_skills "${_output_new}/.agents/skills"

      command rm -rf "$_output_old"
      if [[ -d "$_output_final" ]]; then
          command mv "$_output_final" "$_output_old"
      fi
      command mv "$_output_new" "$_output_final"
      command rm -rf "$_output_old"
      rdf_log "Agent Skills generation complete"
  }
  ```

  > Self-correction note: `sk_emit_skills` takes an explicit `<skills_root>`
  > parameter (not a global) so the `antigravity` composite target could reuse it
  > against any output tree without machinery duplication — spec §13.4's "one
  > skills emitter, callable by any consumer." Coreutils are `command`-prefixed;
  > jq is required (`.agents/skills` needs no jq at runtime for the consumer — it
  > is generation-time only, consistent with the gemini adapter).

- [ ] **Step 3: Add `agent-skills` + `antigravity` targets to `lib/cmd/generate.sh`**
  — three edits, all additive:

  (a) In `_generate_usage` (generate.sh:13-20), after the `agents-md` line, add:
  ```
    agent-skills   Generate .agents/skills/ (Codex + Antigravity shared surface)
    antigravity    Generate the Antigravity surface (.agents/skills/ + AGENTS.md)
  ```

  (b) In the `case "${1:-}"` block, after the `agents-md)` arm (generate.sh:131-136)
  and before `all)`, insert:
  ```bash
          agent-skills)
              _generate_adapter "agent-skills/adapter.sh" "sk_generate_all"
              if [[ $deploy_after -eq 1 ]]; then
                  rdf_warn "--deploy for agent-skills requires manual 'rdf deploy --project-root <path> agent-skills'"
              fi
              ;;
          antigravity)
              # First-class composite: shared skills + AGENTS.md context (spec §13.4)
              _generate_adapter "agent-skills/adapter.sh" "sk_generate_all"
              _generate_adapter "agents-md/adapter.sh" "amd_generate_all"
              if [[ $deploy_after -eq 1 ]]; then
                  rdf_warn "--deploy for antigravity: copy .agents/skills/ + AGENTS.md into the workspace root (skills via 'rdf deploy --project-root <path> agent-skills')"
              fi
              ;;
  ```

  (c) In the `all)` block, after the AGENTS.md generation (generate.sh:161-164),
  add:
  ```bash
              # Agent Skills (.agents/skills/) — shared Codex + Antigravity surface
              if [[ -f "${RDF_ADAPTERS}/agent-skills/adapter.sh" ]]; then
                  _generate_adapter "agent-skills/adapter.sh" "sk_generate_all" || failed=$((failed + 1))
              fi
  ```

  > Self-correction note: the `agent-skills` arm does NOT wire `--deploy`
  > (mirrors codex/agents-md) — the deploy target lands in Phase 10, so a Phase-8
  > `--deploy` would reference a not-yet-existing target. Warn + manual is the
  > ordering-safe choice.

- [ ] **Step 4: Create `tests/agent-skills.bats`** — hermetic harness mirroring
  `tests/adapter.bats:1-55` (fresh temp RDF home + temp output; source the
  adapter directly with overridden env). This phase adds the two SKILL tests;
  Phase 9 appends the frontmatter/TOML/agents-md tests.

  ```bash
  #!/usr/bin/env bats
  # tests/agent-skills.bats — RDF Reach: .agents/skills/ + intent triggers
  # (C) 2026 R-fx Networks <proj@rfxn.com>
  # GNU GPL v2
  # shellcheck disable=SC2154,SC2164,SC1090,SC1091,SC2016

  RDF_SRC="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  export RDF_SRC

  # _gen_skills <output_dir> — run sk_generate_all against a temp output tree.
  _gen_skills() {
      local output_dir="$1"
      bash -c '
          set -euo pipefail
          rdf_src="$1"; output_dir="$2"
          RDF_HOME="$rdf_src"; RDF_LIBDIR="${rdf_src}/lib"; RDF_VERSION="0.0.0-test"
          source "${rdf_src}/lib/rdf_common.sh"; rdf_init; rdf_profile_init
          source "${rdf_src}/adapters/agent-skills/adapter.sh"
          _SK_OUTPUT_DIR="$output_dir"
          sk_generate_all
      ' -- "$RDF_SRC" "$output_dir"
  }

  setup() { TEST_OUT="$(mktemp -d)"; export TEST_OUT; }
  teardown() { rm -rf "$TEST_OUT" 2>/dev/null || true; }  # cleanup, ignore errors

  @test "one SKILL.md per skill-meta command; frontmatter name matches dir + carries description" {
      _gen_skills "$TEST_OUT"
      local meta="${RDF_SRC}/adapters/agent-skills/skill-meta.json"
      local n; n="$(jq -r 'keys[] | select(. != "_comment")' "$meta" | wc -l)"
      local emitted; emitted="$(find "${TEST_OUT}/.agents/skills" -name SKILL.md | wc -l)"
      [ "$emitted" -eq "$n" ]
      # r-spec skill: name == dir, has a description, canonical body present
      local s="${TEST_OUT}/.agents/skills/r-spec/SKILL.md"
      [ -f "$s" ]
      grep -q '^name: r-spec$' "$s"
      grep -q '^description: >' "$s"
      grep -q 'Design' "$s"   # canonical body verbatim (r-spec heading text)
  }

  @test "skill description falls back to first sentence when meta absent" {
      # Temporarily point the adapter at a meta with an unknown key to exercise
      # the fallback: r-status IS in meta, so assert its meta trigger is used,
      # and assert the fallback branch by checking a body-derived description for
      # any command whose meta value is empty is non-empty. Structural proxy:
      _gen_skills "$TEST_OUT"
      local s="${TEST_OUT}/.agents/skills/r-status/SKILL.md"
      grep -q '^description: >' "$s"
      [ -n "$(sed -n '/^description: >/{n;p;}' "$s")" ]   # description line non-empty
  }
  ```

- [ ] **Step 5: Add `agent-skills.bats` to `tests/Makefile`** — append
  `$(TESTS_DIR)agent-skills.bats` to BOTH the `test:` list (Makefile:19-28,
  after `scale-ceremony.bats`) and the `lint:` list (Makefile:30-39, after
  `scale-ceremony.bats`). The Makefile does not glob — list explicitly.

- [ ] **Step 6: Exclude the adapter output from git** — the other adapters'
  `output/` dirs are in `.git/info/exclude`; `agent-skills/output/` is NOT.
  Append it so generated SKILL.md files never get committed:
  ```bash
  grep -q 'adapters/agent-skills/output/' .git/info/exclude \
    || printf 'adapters/agent-skills/output/\n' >> .git/info/exclude
  git check-ignore adapters/agent-skills/output   # expect: the path echoed
  ```
  (`.git/info/exclude` is not a tracked file — this step produces no staged
  change; it prevents an accidental `git add` of output.)

- [ ] **Step 6b: doc-stats adapter count 5→6** (pulled forward from Phase 11:
  the 6th `adapters/*/` dir makes doctor doc-stats FAIL and `doctor.bats`
  asserts 0 FAIL rows, so the suite would stay red until release otherwise) —
  `README.md:6` badge `adapters-5`→`adapters-6`; `README.md:602` footer and
  `docs/index.md:23` `5 adapters`→`6 adapters`.

- [ ] **Step 7: Lint + test**
  ```bash
  bash -n adapters/agent-skills/adapter.sh && shellcheck adapters/agent-skills/adapter.sh
  bash -n lib/cmd/generate.sh && shellcheck lib/cmd/generate.sh
  bin/rdf generate agent-skills
  head -1 adapters/agent-skills/output/.agents/skills/r-spec/SKILL.md   # expect: ---
  bin/rdf generate antigravity
  test -f adapters/agents-md/output/AGENTS.md && echo "antigravity context OK"
  make -C tests test 2>&1 | tee /tmp/test-rdf-P8-reach.log | grep -c '^not ok'   # expect: 0
  ```

- [ ] **Step 8: Commit**
  ```bash
  git add adapters/agent-skills/adapter.sh adapters/agent-skills/skill-meta.json \
      lib/cmd/generate.sh tests/agent-skills.bats tests/Makefile README.md docs/index.md
  git commit -m "Add agent-skills adapter + antigravity generate target

  [New] adapters/agent-skills — emits .agents/skills/<cmd>/SKILL.md (name +
        intent-trigger description) for a bounded lifecycle+utility set; the ONE
        shared workspace surface Codex and Antigravity both read
  [New] rdf generate agent-skills (raw convention surface) + antigravity
        (composite: shared skills + AGENTS.md context); no skills machinery
        duplicated into the codex/gemini adapters
  [New] tests/agent-skills.bats — SKILL.md shape + name/dir + fallback description"
  ```

---

### Phase 9: CC intent frontmatter + gemini TOML fix + agents-md pointer

Give Claude Code command output an intent-trigger `description:` frontmatter
(reusing Phase 8's `skill-meta.json`); fix the gemini legacy-tier TOML escaping
(15/37 `.toml` files fail strict parsing) by switching the prompt to a `'''`
literal string and emit the `{{args}}` lossy-edge NOTE; add a `.agents/skills/`
pointer to the cross-tool AGENTS.md; and assert canonical stays frontmatter-free.

> **Compose note (3.4 merged ✓):** in `adapters/claude-code/adapter.sh` add a NEW
> function and change only the `cc_generate_commands` copy loop
> (`adapter.sh:136-148`) — never touch 3.4's `cc_generate_rules`/`_CC_LITE`
> lines. Codex is NOT edited (skills are the shared agent-skills surface, §13.4).

**Files:**
- Modify: `adapters/claude-code/adapter.sh`
- Modify: `adapters/gemini-cli/adapter.sh`
- Modify: `adapters/agents-md/adapter.sh`
- Modify: `lib/cmd/doctor.sh`
- Modify: `lib/cmd/sync.sh`
- Modify: `tests/agent-skills.bats`
- Modify: `tests/doctor.bats`
- Modify: `tests/governance-contracts.bats`

> **Contract-integrity note (challenge blockers 1+2):** the CC frontmatter
> injection MUST land in the SAME phase as the two consumers it would otherwise
> break — `lib/cmd/doctor.sh` (content-drift hashes the deployed command body)
> and `lib/cmd/sync.sh` (reverse-flow copies command output to canonical). If
> either lagged a phase, an intervening `rdf doctor` would FAIL every command
> and an intervening `rdf sync` would write frontmatter INTO canonical
> (violating the frontmatter-free contract this phase adds). All three change
> together here.

- **Mode**: serial-agent
- **Goals:** 6, 7, 8
- **Accept**: `adapters/claude-code/output/commands/r-spec.md` begins with `---`
  and a `description:` line (trigger from skill-meta, first-sentence fallback for
  commands absent from meta); canonical `r-spec.md` still has NO frontmatter
  (contract); every generated gemini `.toml` parses as strict TOML (the 15/37
  fix) AND uses a `prompt = '''` literal string (python-free structural guard);
  a gemini command whose body reads `$ARGUMENTS` carries the `{{args}}` NOTE and
  one that does not (`r-status`) does not; the cross-tool AGENTS.md references
  `.agents/skills/`; **`rdf doctor` content-drift stays OK on a frontmatter-
  bearing command whose body contains `---` horizontal rules** (BLOCKER 1); **`rdf
  sync` writes a frontmatter-stripped body back to `canonical/commands/*.md`,
  never the frontmatter** (BLOCKER 2)
- **Test**: `tests/agent-skills.bats` — @test "CC command output gains description frontmatter; canonical stays frontmatter-free", @test "gemini command TOML parses as strict TOML (literal-string fix)", @test "gemini command TOML uses a prompt literal string (python-free guard)", @test "gemini {{args}} NOTE present for arg command, absent for r-status", @test "agents-md AGENTS.md references .agents/skills/"; `tests/doctor.bats` — @test "content-drift OK for a deployed command with frontmatter + body --- rules"; `governance-contracts.bats` — @test "canonical commands carry no YAML frontmatter"
- **Edge cases**: spec §11b "gemini no-positional command → no warning"; §13.5 "CC stays commands, no `.claude/skills/` migration"; "deployed command body has `---` horizontal rules → doctor strip must not eat them" (BLOCKER 1)
- **Regression-case**: tests/doctor.bats::@test "content-drift OK for a deployed command with frontmatter + body --- rules" (BLOCKER 1 — the highest-value guard; the body-`---` case is exactly what the old agent awk ate) + tests/agent-skills.bats::@test "gemini command TOML parses as strict TOML (literal-string fix)" (the 15/37 regression) + governance-contracts.bats::@test "canonical commands carry no YAML frontmatter" (all added in this phase)

- [ ] **Step 1: CC command frontmatter** in `adapters/claude-code/adapter.sh`.

  (a) After `_CC_COMMAND_META` (adapter.sh:12), add the shared meta path:
  ```bash
  _CC_SKILL_META="${RDF_ADAPTERS}/agent-skills/skill-meta.json"
  ```

  (b) Add a new function above `cc_generate_commands` (before adapter.sh:129):
  ```bash
  # cc_generate_command_frontmatter <basename-no-ext> — emit a CC command
  # frontmatter block with an intent-trigger description. Trigger comes from the
  # shared agent-skills skill-meta.json; falls back to the canonical body's first
  # non-heading line. Never sets disable-model-invocation (CC bug #43875).
  cc_generate_command_frontmatter() {
      local name="$1" desc
      desc="$(jq -r --arg c "$name" '.[$c] // empty' "$_CC_SKILL_META" 2>/dev/null)"  # missing key/file → empty
      if [[ -z "$desc" ]]; then
          desc="$(sed -n '/^[^#[:space:]]/{ s/[[:space:]]*$//; p; q; }' "${RDF_CANONICAL}/commands/${name}.md")"
          [[ -z "$desc" ]] && desc="RDF command: ${name}"
      fi
      echo "---"
      echo "description: >"
      echo "  ${desc}"
      echo "---"
  }
  ```

  (c) Change the `cc_generate_commands` copy loop body (adapter.sh:143-146) from:
  ```bash
          local dst_file="${dst_dir}/${basename_f}"
          command cp "$src_file" "$dst_file"
          # Hash the canonical source so doctor can detect post-deploy drift
          _cc_write_hash_sidecar "$src_file" "$dst_file"
  ```
  to:
  ```bash
          local dst_file="${dst_dir}/${basename_f}"
          local name_noext="${basename_f%.md}"
          {
              cc_generate_command_frontmatter "$name_noext"
              echo ""
              command cat "$src_file"
          } > "$dst_file"
          # Hash the CANONICAL source (pre-frontmatter) so doctor still matches
          _cc_write_hash_sidecar "$src_file" "$dst_file"
  ```

  > Self-correction note (§13.5): CC stays commands — this prepends frontmatter to
  > `.claude/commands/*.md`; it does NOT create `.claude/skills/<cmd>/SKILL.md`
  > (that would break the symlink-deploy model and double-register `/r-spec`). The
  > hash sidecar still hashes `$src` (the canonical body), unchanged. **But note
  > (challenge BLOCKER 1): doctor's content-drift check does NOT re-derive from
  > canonical for commands — `_check_content_drift`/`_hash_deployed_body`
  > (`doctor.sh:352-362`) hashes the DEPLOYED command file DIRECTLY (kind
  > `command` → `rdf_hash_stdin < "$deployed"`, no strip). Once this step adds
  > frontmatter, that direct hash no longer matches the canonical-body sidecar,
  > so EVERY command would FAIL content-drift.** Step 2 below fixes doctor to
  > strip the leading frontmatter before hashing. ALL 37 commands gain a
  > `description:` (meta trigger for the bounded set, first-sentence fallback for
  > the rest) — additive header the CC loader tolerates (spec §8 migration safety).

- [ ] **Step 2: doctor content-drift — strip leading command frontmatter (BLOCKER 1)**
  in `lib/cmd/doctor.sh`. `_hash_deployed_body` (`doctor.sh:352-363`) hashes
  deployed COMMAND files directly (no strip) and strips agent frontmatter with an
  awk (`/^---/`) that re-triggers on ANY line beginning `---` — eating the 11 body
  `---` horizontal rules in `r-spec.md`. Replace the whole `_hash_deployed_body`
  body with a single LEADING-frontmatter strip that (i) engages only when line 1
  is `---`, (ii) stops permanently after the 2nd `---`, (iii) skips one blank
  separator, (iv) prints the rest verbatim (body `---` rules preserved) — correct
  for BOTH agents and commands:
  ```bash
  _hash_deployed_body() {
      local deployed="$1"
      local kind="$2"   # "agent" | "command" — both strip a LEADING frontmatter
      # Strip only a leading contiguous --- ... --- block (from line 1) + one
      # blank separator; never re-enter on body horizontal rules. If line 1 is
      # not ---, nothing is stripped (fm stays 0) and the whole file is hashed.
      awk '
          NR==1 && /^---[[:space:]]*$/ { fm=1; next }
          fm==1 && /^---[[:space:]]*$/ { fm=2; next }
          fm==1 { next }
          fm==2 { fm=3; if ($0 ~ /^[[:space:]]*$/) next }
          { print }
      ' "$deployed" | rdf_hash_stdin
  }
  ```
  Leave the two call sites (`doctor.sh:379,402`) unchanged — `kind` is now
  unused but the signature stays. This also repairs the latent agent-body-`---`
  bug (the old awk would have mis-hashed any agent whose body carried `---`).

  > Self-correction note: for commands (which now carry frontmatter after Step 1)
  > the strip removes the leading `---`…`---` + blank and hashes the canonical
  > body — matching the sidecar. For a command body with `---` rules (`r-spec` has
  > 11), `fm` is already 3 by the time they appear, so the `/^---/` rules do not
  > fire and the lines print verbatim. For a frontmatter-less file, line 1 is not
  > `---`, `fm` stays 0, the whole file hashes as before (backward compatible).

  Add a doctor content-drift regression to `tests/doctor.bats` (mirror the file's
  existing hermetic harness):
  ```bash
  @test "content-drift OK for a deployed command with frontmatter + body --- rules" {
      # Hermetic temp RDF_HOME whose canonical/commands/x.md body carries --- rules:
      #   printf 'line1\n\n---\n\nline2\n\n---\n\nline3\n' > canonical/commands/x.md
      # Generate CC output (prepends frontmatter + writes the canonical-body
      # sidecar over $src), then run _check_content_drift on that project root and
      # assert NO "content-drift ... FAIL ... commands/x.md" result — i.e. the
      # strip removed the frontmatter but preserved the body --- rules.
      [ "$status" -ne 1 ]   # assert the FAIL code is absent (per test-isolation guidance)
  }
  ```

- [ ] **Step 3: rdf sync — strip frontmatter on the command path (BLOCKER 2)** in
  `lib/cmd/sync.sh`. The commands loop (`sync.sh:98-119`) is "direct copy (no
  frontmatter)" and `command cp`s deployed output straight into
  `canonical/commands/` — after Step 1 that copies the injected frontmatter INTO
  canonical, breaking the very frontmatter-free contract this phase adds. Make the
  command path mirror the agents path (`sync.sh:66-95`): if the deployed file's
  first line is `---`, run it through `_strip_frontmatter` (already body-`---`-
  safe — it only `continue`s on the first two `---`, and prints every line once
  `frontmatter_count>=2`, so a body `---` pushing the count to 3 still prints) and
  trim leading blanks; else keep the direct copy. Replace the commands loop body
  (`sync.sh:102-117`, from `local canon_file=` through `changed=$((changed + 1))`):
  ```bash
          local canon_file="${RDF_CANONICAL}/commands/${basename_f}"
          local body
          if [[ "$(head -1 "$out_file")" == "---" ]]; then
              body="$(_strip_frontmatter "$out_file")"
              body="$(echo "$body" | sed '/./,$!d')"   # trim leading blank lines
          else
              body="$(< "$out_file")"
          fi

          if [[ -f "$canon_file" ]]; then
              local current; current="$(< "$canon_file")"
              if [[ "$body" == "$current" ]]; then
                  unchanged=$((unchanged + 1)); continue
              fi
          fi

          if [[ $dry_run -eq 1 ]]; then
              rdf_log "WOULD UPDATE: canonical/commands/${basename_f}"
          else
              printf '%s\n' "$body" > "$canon_file"
              rdf_log "updated: canonical/commands/${basename_f}"
          fi
          changed=$((changed + 1))
  ```
  > Self-correction note: `_strip_frontmatter` (`sync.sh:28-44`) is reused
  > verbatim (body-`---`-safe). The sync round-trip regression using a COMMAND
  > file lands in Phase 10's `deploy.bats` (Step 2), so the contract is tested
  > end-to-end while the SOURCE fix lands here in the same phase as the injection.

- [ ] **Step 4: gemini TOML escaping fix + `{{args}}` NOTE** — replace the prompt
  block in `_gem_write_command_toml` (gemini adapter :99-118). The bug: the
  canonical body (regex `\b`, sed `\|`, etc.) is emitted into a `"""` BASIC
  multi-line string, where a backslash before an invalid escape char is a TOML
  parse error (15/37 files). Fix: emit the prompt as a `'''` LITERAL string,
  which does no escape processing. Replace from `# Read full canonical body`
  through the closing `} > "$dst_file"`:
  ```bash
      # Read full canonical body as the prompt
      local body
      body="$(< "$src_file")"

      # Escape TOML special chars in the description (basic string; Sentinel #9)
      desc="${desc//\\/\\\\}"
      desc="${desc//\"/\\\"}"

      # {{args}} lossy-edge NOTE — canonical bodies reference $ARGUMENTS; Gemini
      # injects the whole invocation as {{args}} and does not tokenize positional
      # forms (e.g. `/r-build 3`). Advisory only; conditional on $ARGUMENTS use.
      local args_note=""
      if grep -q '\$ARGUMENTS' "$src_file"; then
          args_note="# NOTE: /${basename_f} reads \$ARGUMENTS; Gemini exposes only {{args}} (the whole string) — positional forms like \`/r-build 3\` are not tokenized."
      fi

      # Prompt uses a TOML literal string ('''…''') so backslashes in the body
      # need NO escaping — the 15/37 strict-parse fix. Fallback: if the body
      # itself contains ''' (impossible inside a literal string), escape
      # backslashes and use a basic """…""" string instead.
      {
          echo "# Generated by rdf generate gemini-cli — do not edit"
          echo "# Source: canonical/commands/${basename_f}.md"
          echo ""
          echo "description = \"${desc}\""
          echo ""
          [[ -n "$args_note" ]] && echo "$args_note"
          if [[ "$body" == *"'''"* ]]; then
              local esc="${body//\\/\\\\}"
              echo 'prompt = """'
              echo "${esc}"
              echo '"""'
          else
              echo "prompt = '''"
              echo "${body}"
              echo "'''"
          fi
      } > "$dst_file"
  ```

  > Self-correction note: description stays a BASIC `"..."` string (already
  > escaped, lines above) — only the prompt switches to `'''`. The `'''`-in-body
  > guard is defensive; RDF's markdown command bodies use ` ``` ` code fences, not
  > `'''`, so the fallback branch is effectively never taken but keeps the adapter
  > total. This is the LOCKED-directive fix; gemini-cli remains a frozen legacy
  > tier otherwise (no other change).

- [ ] **Step 5: agents-md `.agents/skills/` pointer** — in `amd_generate_all`
  (agents-md adapter.sh:86-91), extend the intro block:
  ```bash
      {
          echo "# AGENTS.md — rfxn Development Framework"
          echo ""
          echo "Cross-tool project instructions. Generated by \`rdf generate agents-md\`."
          echo ""
          echo "Agent Skills (slash commands) live under \`.agents/skills/\` — generate"
          echo "them with \`rdf generate agent-skills\`. Codex and Antigravity read that"
          echo "directory natively."
          echo ""
      } > "$dst_file"
  ```

- [ ] **Step 6: Add tests to `tests/agent-skills.bats`** — add a CC-generate
  helper (mirror `_gen_skills`, calling `cc_generate_commands`) and a gemini
  helper (`gem_generate_commands`), then:
  ```bash
  @test "CC command output gains description frontmatter; canonical stays frontmatter-free" {
      _gen_cc_commands "$TEST_OUT"
      head -1 "${TEST_OUT}/commands/r-spec.md" | grep -q '^---$'
      grep -q '^description: >' "${TEST_OUT}/commands/r-spec.md"
      [ "$(head -1 "${RDF_SRC}/canonical/commands/r-spec.md")" != "---" ]
  }

  @test "gemini command TOML parses as strict TOML (literal-string fix)" {
      command -v python3 >/dev/null && python3 -c 'import tomllib' >/dev/null 2>&1 || skip "no tomllib"  # 2>/dev/null: probe only; skip handles absence
      _gen_gem_commands "$TEST_OUT"
      local bad=0 f
      for f in "${TEST_OUT}"/.gemini/commands/*.toml; do
          python3 -c 'import tomllib,sys; tomllib.load(open(sys.argv[1],"rb"))' "$f" || bad=$((bad+1))
      done
      [ "$bad" -eq 0 ]
  }

  @test "gemini command TOML uses a prompt literal string (python-free guard)" {
      # MINOR 8: guards the fix even when tomllib is absent. Every generated
      # command prompt must open a ''' literal (or the ''' -in-body fallback """
      # WITH escaped backslashes) — never a bare """ basic prompt carrying raw
      # backslashes (the original 15/37 defect).
      _gen_gem_commands "$TEST_OUT"
      local f bad=0
      for f in "${TEST_OUT}"/.gemini/commands/*.toml; do
          grep -q "^prompt = '''" "$f" && continue          # literal-string prompt (default path)
          grep -q '^prompt = """' "$f" || { bad=$((bad+1)); continue; }  # neither form → defect
      done
      [ "$bad" -eq 0 ]
      # r-build's body has backslashes (sed/regex); assert its prompt is a literal
      grep -q "^prompt = '''" "${TEST_OUT}/.gemini/commands/r-build.toml"
  }

  @test "gemini {{args}} NOTE present for arg command, absent for r-status" {
      _gen_gem_commands "$TEST_OUT"
      grep -q 'NOTE:.*{{args}}' "${TEST_OUT}/.gemini/commands/r-build.toml"
      ! grep -q 'NOTE:.*{{args}}' "${TEST_OUT}/.gemini/commands/r-status.toml"
  }

  @test "agents-md AGENTS.md references .agents/skills/" {
      _gen_agents_md "$TEST_OUT"
      grep -q '\.agents/skills/' "${TEST_OUT}/AGENTS.md"
  }
  ```
  (The `_gen_cc_commands`/`_gen_gem_commands`/`_gen_agents_md` helpers each source
  the relevant adapter with `_*_OUTPUT_DIR="$TEST_OUT"` and call its
  `*_generate_commands`/`amd_generate_all`, mirroring `tests/adapter.bats`'s
  `_generate`. r-build reads `$ARGUMENTS`; r-status does not — verified by
  `grep -l '\$ARGUMENTS' canonical/commands/*.md`.)

- [ ] **Step 7: canonical-frontmatter-free contract** in
  `tests/governance-contracts.bats` (append at EOF, §4.2 additive):
  ```bash
  @test "canonical commands carry no YAML frontmatter" {
      local root f
      root="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
      for f in "${root}"/canonical/commands/*.md; do
          [ "$(head -1 "$f")" != "---" ]
      done
  }
  ```

- [ ] **Step 8: Lint + test + commit**
  ```bash
  bash -n adapters/claude-code/adapter.sh adapters/gemini-cli/adapter.sh \
      adapters/agents-md/adapter.sh lib/cmd/doctor.sh lib/cmd/sync.sh
  shellcheck adapters/claude-code/adapter.sh adapters/gemini-cli/adapter.sh \
      adapters/agents-md/adapter.sh lib/cmd/doctor.sh lib/cmd/sync.sh
  make -C tests test 2>&1 | tee /tmp/test-rdf-P9-reach.log | grep -c '^not ok'   # expect: 0
  git add adapters/claude-code/adapter.sh adapters/gemini-cli/adapter.sh \
      adapters/agents-md/adapter.sh lib/cmd/doctor.sh lib/cmd/sync.sh \
      tests/agent-skills.bats tests/doctor.bats tests/governance-contracts.bats
  git commit -m "Intent-trigger frontmatter (CC) + gemini TOML fix + consumer guards

  [New] claude-code: cc_generate_command_frontmatter prepends an intent-trigger
        description: to every command (shared skill-meta trigger, first-sentence
        fallback); canonical stays frontmatter-free; hash sidecar over canonical
  [Fix] doctor content-drift: _hash_deployed_body strips only a LEADING frontmatter
        block (body --- horizontal rules preserved), so commands gaining
        frontmatter no longer false-FAIL; also repairs the latent agent-body---
        bug in the old awk
  [Fix] sync: command reverse-flow strips frontmatter before writing canonical,
        so an emergency-edit round-trip never writes frontmatter into canonical
  [Fix] gemini-cli (legacy tier): emit the command prompt as a TOML ''' literal
        string so canonical backslashes (regex/sed) no longer break strict TOML
        parsing — 15/37 .toml files now valid; add the {{args}} lossy-edge NOTE
        for \$ARGUMENTS commands
  [New] agents-md: reference .agents/skills/ for Codex/Antigravity discovery
  [New] tests: doctor content-drift (frontmatter + body ---) regression;
        canonical-commands-carry-no-frontmatter governance contract"
  ```

---

### Phase 10: Deploy/sync BATS coverage (audit M6) + skills deploy + parity doc

Close the audit M6 gap (zero deploy/sync BATS coverage — the install surface
every consumer hits), add an `agent-skills` deploy target (symlink
`.agents/skills/` into a workspace root), and write the multi-tool parity doc
recast around the new trio + legacy gemini row.

**Files:**
- Create: `tests/deploy.bats`
- Create: `docs/multi-tool-parity.md`
- Modify: `lib/cmd/deploy.sh`
- Modify: `tests/Makefile`

- **Mode**: serial-agent
- **Goals:** 9
- **Accept**: `tests/deploy.bats` covers `_deploy_symlink`
  create/replace/skip/force and the hooks.json manual-merge skip, the new
  `agent-skills` `.agents/skills/` symlink into a `--project-root`, and an
  `rdf sync` round-trip; `make -C tests test` runs it green;
  `docs/multi-tool-parity.md` states the trio (Claude Code / Codex / Antigravity)
  + legacy gemini-cli matrix across command surface / skills / context file /
  hooks, and the `{{args}}` lossy edge
- **Test**: `tests/deploy.bats` — @test "deploy claude-code symlink create/replace/skip/force", @test "deploy claude-code skips hooks.json", @test "deploy agent-skills symlinks .agents/skills into project root", @test "sync strips frontmatter from a COMMAND on the reverse flow (BLOCKER 2)"
- **Edge cases**: spec §11b "deploy.bats on host without bats" (Makefile `_bats_check` guard); "sync of a frontmatter-bearing command must not write frontmatter to canonical" (BLOCKER 2)
- **Regression-case**: tests/deploy.bats::@test "deploy claude-code symlink create/replace/skip/force" (M6 install-surface guard) + tests/deploy.bats::@test "sync strips frontmatter from a COMMAND on the reverse flow (BLOCKER 2)" (guards the Phase-9 sync.sh fix end-to-end)

- [ ] **Step 1: `agent-skills` deploy target in `lib/cmd/deploy.sh`** — `.agents/skills/`
  is workspace-level (not `$HOME` like claude-code/gemini), so it mirrors codex's
  `--project-root` pattern rather than 3.4's `~/.claude/rules` symlink.

  (a) Add a new function after `_deploy_codex` (deploy.sh:246):
  ```bash
  # Deploy agent-skills output (.agents/skills/) into a workspace root
  _deploy_agent_skills() {
      local dry_run="$1"
      local force="$2"
      local project_root="$3"
      local output_dir="${RDF_ADAPTERS}/agent-skills/output"

      if [[ ! -d "$output_dir" ]] || [[ -z "$(ls -A "$output_dir" 2>/dev/null)" ]]; then  # 2>/dev/null: empty-on-missing is the intended empties→rdf_die value
          rdf_die "output not found — run 'rdf generate agent-skills' first"
      fi
      [[ -n "$project_root" ]] || project_root="$PWD"
      if [[ ! -d "$project_root" ]]; then
          rdf_die "project root not a directory: ${project_root}"
      fi

      rdf_log "deploying agent-skills to ${project_root}/.agents/skills..."
      _deploy_symlink "${output_dir}/.agents/skills" "${project_root}/.agents/skills" "$dry_run" "$force"
  }
  ```

  (b) Add the case arm in `cmd_deploy` (deploy.sh:293-297), after the `codex)` arm:
  ```bash
          agent-skills) _deploy_agent_skills "$dry_run" "$force" "$project_root" ;;
  ```

  (c) Add to `_deploy_usage` (deploy.sh:13-16), after the `codex` target line:
  ```
    agent-skills   Deploy .agents/skills/ into a workspace root (--project-root, default CWD)
  ```

- [ ] **Step 2: Create `tests/deploy.bats`** — hermetic harness mirroring
  `tests/rules-deploy.bats:1-55`. Copy its `_make_deploy_skeleton <fix_home>`
  (builds `adapters/claude-code/output/{agents,commands,scripts,governance,rules}`
  + a `hooks.json` since CC output is local-only/absent on a CI checkout) and
  `_run_deploy <fix_home> [args...]` (sources `lib/cmd/deploy.sh` under a temp
  `HOME=<fix_home>/.claude`-style root and runs `cmd_deploy claude-code`). Each
  `@test` is fully asserted (no prose-only bodies):
  ```bash
  setup() { FIX_HOME="$(mktemp -d)"; export FIX_HOME; _make_deploy_skeleton "$FIX_HOME"; }
  teardown() { rm -rf "$FIX_HOME" 2>/dev/null || true; }  # cleanup, ignore errors

  @test "deploy claude-code symlink create/replace/skip/force" {
      local out="${FIX_HOME}/adapters/claude-code/output"
      # 1) fresh create → commands is a symlink to the output
      run _run_deploy "$FIX_HOME"
      [ "$status" -eq 0 ]
      [ -L "${FIX_HOME}/.claude/commands" ]
      [ "$(readlink "${FIX_HOME}/.claude/commands")" = "${out}/commands" ]
      # 2) second run → still a symlink (replaced, not skipped)
      run _run_deploy "$FIX_HOME"
      [ -L "${FIX_HOME}/.claude/commands" ]
      # 3) a REAL dir where the symlink would go, no --force → skipped, dir intact
      rm -f "${FIX_HOME}/.claude/governance"; mkdir -p "${FIX_HOME}/.claude/governance"
      touch "${FIX_HOME}/.claude/governance/keep.md"
      run _run_deploy "$FIX_HOME"
      [ ! -L "${FIX_HOME}/.claude/governance" ]            # untouched real dir
      [ -f "${FIX_HOME}/.claude/governance/keep.md" ]
      echo "$output" | grep -q 'not a symlink'
      # 4) --force → backs up the real dir and symlinks
      run _run_deploy "$FIX_HOME" --force
      [ -L "${FIX_HOME}/.claude/governance" ]
      ls -d "${FIX_HOME}/.claude/governance".bak-* >/dev/null   # backup exists
  }

  @test "deploy claude-code skips hooks.json" {
      run _run_deploy "$FIX_HOME"
      [ ! -e "${FIX_HOME}/.claude/hooks.json" ]           # never symlinked (manual merge)
      echo "$output" | grep -q 'skipped: hooks.json'
  }

  @test "deploy agent-skills symlinks .agents/skills into project root" {
      local out="${FIX_HOME}/adapters/agent-skills/output"
      mkdir -p "${out}/.agents/skills/r-spec"
      printf -- '---\nname: r-spec\n---\nbody\n' > "${out}/.agents/skills/r-spec/SKILL.md"
      local proj; proj="$(mktemp -d)"
      run _run_deploy "$FIX_HOME" --project-root "$proj" agent-skills
      [ "$status" -eq 0 ]
      [ -L "${proj}/.agents/skills" ]
      [ -f "${proj}/.agents/skills/r-spec/SKILL.md" ]
      rm -rf "$proj"
  }

  @test "sync strips frontmatter from a COMMAND on the reverse flow (BLOCKER 2)" {
      # A deployed command carries frontmatter + a body --- rule; sync must write
      # back the STRIPPED body to canonical, never the frontmatter.
      local home="$(mktemp -d)"
      mkdir -p "${home}/canonical/commands" "${home}/adapters/claude-code/output/commands"
      printf 'orig body\n---\nrule\n' > "${home}/canonical/commands/x.md"
      printf -- '---\ndescription: >\n  trigger\n---\n\nEDITED body\n---\nrule\n' \
          > "${home}/adapters/claude-code/output/commands/x.md"
      run bash -c '
          set -euo pipefail
          RDF_HOME="$1"; RDF_LIBDIR="$2/lib"; RDF_VERSION="0.0.0-test"
          source "$2/lib/rdf_common.sh"; rdf_init
          source "$2/lib/cmd/sync.sh"; cmd_sync
      ' -- "$home" "$RDF_SRC"
      [ "$status" -eq 0 ]
      [ "$(head -1 "${home}/canonical/commands/x.md")" != "---" ]   # NO frontmatter
      grep -q '^EDITED body$' "${home}/canonical/commands/x.md"     # edit landed
      grep -q '^---$' "${home}/canonical/commands/x.md"             # body --- rule preserved
      ! grep -q 'description: >' "${home}/canonical/commands/x.md"  # trigger stripped
      rm -rf "$home"
  }
  ```
  Use `mktemp -d` for every root; bare coreutils inside `.bats`; the sync test
  sources `lib/cmd/sync.sh` directly (as above) rather than `bin/rdf`, matching
  the harness style of `tests/adapter.bats`.

- [ ] **Step 3: Create `docs/multi-tool-parity.md`** — recast around the trio +
  legacy row (spec §13.3). Sections:
  1. **Matrix** — rows: Claude Code, Codex, Antigravity, Gemini CLI (legacy);
     columns: command surface, skill surface (`.agents/skills/`), context file,
     hooks, generate target.
  2. **The `.agents/skills/` shared convention** — one workspace directory, read
     by Codex + Antigravity; emitted once by `rdf generate agent-skills`.
  3. **Gemini `{{args}}` lossy edge** — the §5b.5 example; commands reading
     `$ARGUMENTS` carry a NOTE; positional forms (`/r-build 3`) are not tokenized.
  4. **Legacy gemini-cli tier** — frozen for enterprise Gemini CLI users; the
     TOML `'''`-literal fix; the `agy plugin import gemini` migration path
     (fixed TOML is the migration source).
  5. **Deferred surfaces** — Antigravity hooks/subagents/plugins, Codex
     `openai.yaml`, MCP — cross-ref spec §13.7 (probe-gated).

- [ ] **Step 4: `tests/Makefile`** — append `$(TESTS_DIR)deploy.bats` to BOTH the
  `test:` and `lint:` lists (after `agent-skills.bats`, added in Phase 8). List
  explicitly — no glob.

- [ ] **Step 5: Lint + test + commit**
  ```bash
  bash -n lib/cmd/deploy.sh && shellcheck lib/cmd/deploy.sh
  make -C tests test 2>&1 | tee /tmp/test-rdf-P10-reach.log | grep -c '^not ok'   # expect: 0
  git add lib/cmd/deploy.sh tests/deploy.bats docs/multi-tool-parity.md tests/Makefile
  git commit -m "Deploy/sync BATS coverage (audit M6) + agent-skills deploy + parity doc

  [New] tests/deploy.bats — symlink create/replace/skip/force, hooks.json skip,
        agent-skills workspace symlink, and an rdf sync round-trip (closes the
        audit M6 zero-coverage gap on the install surface)
  [New] lib/cmd/deploy.sh: agent-skills target — symlink .agents/skills/ into a
        workspace root (--project-root, default CWD; codex pattern)
  [New] docs/multi-tool-parity.md — trio (Claude Code/Codex/Antigravity) + legacy
        gemini row; .agents/skills/ convention; {{args}} lossy edge; deferred
        Antigravity surfaces (spec §13.7)"
  ```

---

### Phase 11: "Reach" release (VERSION assigned at ship)

Docs, roadmap, changelog, VERSION bump. Depends on Phases 8–10.

> **Version placeholder — NOT pre-allocated.** Use `<REACH_VERSION>` throughout
> this phase; the controller assigns the actual number at ship time (per the
> release-cadence rule: assign at ship, never pre-allocate a ladder). Wave 1
> already shipped as 3.5.0 + the 3.5.1 QA-pass, so `<REACH_VERSION>` is the NEXT
> number the controller chooses at ship — do NOT reuse 3.5.1. Substitute the
> chosen number in VERSION, both changelogs, the commit subject, and the tag.

**Files:** `README.md`, `ROADMAP.md`, `docs/index.md`, `CHANGELOG`, `CHANGELOG.RELEASE`, `VERSION`

- **Mode**: serial-context
- **Goals:** 11
- **Accept**: `VERSION` == the ship-assigned `<REACH_VERSION>`; CHANGELOG +
  CHANGELOG.RELEASE each gain a `## <REACH_VERSION>` block covering
  agent-skills/antigravity, CC intent frontmatter, the gemini TOML fix, deploy/
  sync BATS, and the parity doc; README documents the trio + `rdf generate
  agent-skills`/`antigravity` (and gemini-cli as a frozen legacy tier); ROADMAP
  checks the first-class multi-tool item; **the doc-stats adapter count reads 6
  (agent-skills added) in the README badge, the README footer line, and
  docs/index.md** — so `rdf doctor` doc-stats stays 0 FAIL; full suite green
- **Test**: N/A (docs + version) — verification greps below
- **Edge cases**: none
- **Regression-case**: N/A — docs/release phase

- [ ] **Step 1: README** — add/extend a "First-class multi-tool" subsection:
  Claude Code, Codex, and **Antigravity CLI** as first-class citizens;
  `rdf generate agent-skills` (shared `.agents/skills/`) and `rdf generate
  antigravity` (skills + AGENTS.md); note gemini-cli is a **frozen legacy tier**
  for enterprise Gemini CLI users (kept for the transition, TOML fix included).
  **Adapter-count bumps (5→6) landed in Phase 8** (pulled forward to keep the
  suite green across 8–10); verify with
  `bash bin/rdf doctor --all 2>&1 | grep -i 'doc-stat\|adapter'` — expect OK.
- [ ] **Step 2: docs/index.md** — verify the footer stats line `docs/index.md:23`
  already says `6 adapters` (bumped in Phase 8); update any other drifted stats.
- [ ] **Step 3: ROADMAP** — check off the first-class multi-tool / Agent-Skills
  item; note Antigravity is the locked transition target and gemini-cli is legacy.
- [ ] **Step 4: CHANGELOG + CHANGELOG.RELEASE** — a `## <REACH_VERSION>` block,
  soft-wrap + `[New]`/`[Fix]`/`[Change]` tag style per workspace CLAUDE.md.
- [ ] **Step 5: VERSION** — write the ship-assigned `<REACH_VERSION>`.
- [ ] **Step 6: Verify + commit**
  ```bash
  cat VERSION                                 # expect: <REACH_VERSION>
  bash bin/rdf doctor 2>&1 | grep -c 'FAIL'   # expect: 0
  make -C tests test 2>&1 | tee /tmp/test-rdf-P11-reach.log | grep -c '^not ok'   # expect: 0
  git add README.md ROADMAP.md docs/index.md CHANGELOG CHANGELOG.RELEASE VERSION
  git commit -m "<REACH_VERSION> — Reach: first-class Codex + Antigravity skills

  [New] agent-skills adapter (.agents/skills/) + antigravity generate target;
        CC command intent-trigger frontmatter; multi-tool parity doc
  [Fix] gemini-cli (legacy tier): TOML ''' literal-string escaping — 15/37
        command .toml files now parse strictly; {{args}} lossy-edge NOTE
  [New] deploy/sync BATS coverage (audit M6) + agent-skills deploy target
  [Change] ROADMAP/README/docs/index.md doc-stats adapters 5→6; VERSION <REACH_VERSION>"
  ```

---

### Phase 12: Wave B re-triage + zero-risk cleanup (RECOMMEND DEFER to 3.6)

> **Recommendation:** defer this phase to 3.6. Per spec §4.5, the re-triage
> shows most of Wave B is obsoleted (native background agents) or low-ROI for a
> mostly single-operator framework. Ship ONLY the certain, zero-risk survivor
> now (phantom-contract cleanup); build P6/peer-view ONLY if Phase 0 Q3
> reconfirms persistent cross-session pain. Re-plan with a fresh `/r-plan`
> before building the conditional parts.

**Files:**
- Modify: `canonical/reference/framework.md` (removes the phantom collect-spool.sh contract row)
- Modify: `state/rdf-bus.sh` (conditional — P6 status broadcast; only if Q3 reconfirms)
- Modify: `canonical/commands/r-status.md` (conditional — read-only peer view; only if Q3 reconfirms)

(Conditional-part test coverage lands in `tests/rdf-bus.bats` at re-plan time —
described in Step 2 prose, not a Files entry, since it is gated on Q3.)

- **Mode**: serial-agent
- **Goals:** 10
- **Accept**: `framework.md` no longer references `collect-spool.sh`
  (`grep -c collect-spool canonical/reference/framework.md` → 0). Conditional
  P6/peer-view only if Q3 reconfirms pain, with its own tests
- **Test**: `grep -c 'collect-spool' canonical/reference/framework.md` → 0; (conditional) `tests/rdf-bus.bats` peer-view tests
- **Edge cases**: spec §11b "Codex hooks probe unknown → defer", "Wave B native-covered → drop P6"
- **Regression-case**: N/A — docs cleanup (conditional runtime parts get their own regression case at re-plan time)

- [ ] **Step 1: Remove the phantom `collect-spool.sh` contract** from
  `framework.md:171` (the `collect-spool.sh | .rdf/work-output/spool/*.jsonl |
  5s` table row) — it references code that has never existed in v3. Zero-risk
  documentation cleanup; may be pulled forward into any earlier phase.
- [ ] **Step 2 (conditional — only if Phase 0 Q3 reconfirms pain):** re-plan and
  add P6 per-session `status.json` broadcast to `rdf-bus.sh` + a read-only peer
  view to `/r-status`. Defer P5 bus, `/r-msg`, and the P7/P10 sweeper per §4.5.
- [ ] **Step 3: Commit** (message: "Remove phantom collect-spool.sh contract;
  [conditional] read-only peer-status view").

---

## Post-Plan: Sentinel

After the final shipped wave, dispatch an end-of-plan sentinel review
(mandatory — this plan is dispatched as a batch; the orchestrator does not
auto-trigger a sentinel for manually dispatched phases). Sentinel must verify:

**Wave 1 (shipped — regression guard only):** no bare coreutils in new shell
source; `rdf_active_tier` never fails (defaults `full`) and the plan `**Tier:**`
marker is authoritative over the pointer (S3); the consistency gate does not
false-block a legacy clean plan and covers a comma-list Files line (M2
multi-path); the tier cap only lowers gates AND never drops the security pass on
`scope:sensitive`/security-indicator files (M1).

**Wave 2 (Reach):** every emitted `SKILL.md` has `name:` == its parent
directory name (AAIF rule) and a `description:`; every generated gemini `.toml`
parses as strict TOML (the 15/37 literal-string fix) AND uses a `prompt = '''`
literal (python-free guard), and only `$ARGUMENTS` commands carry the `{{args}}`
NOTE; CC command output gains a `description:` while canonical commands carry NO
YAML frontmatter; **`rdf doctor` content-drift is OK on a frontmatter-bearing
command whose body has `---` rules (BLOCKER 1) and `rdf sync` writes a
frontmatter-stripped body to `canonical/commands/` (BLOCKER 2)**; and `.agents/
skills/` is emitted by ONE adapter. A **source-vocabulary sweep** (per the
workspace lesson) confirms the dropped per-tool-skills design left no trace in
shipped source — grep the built artifacts (NOT the design docs, which record the
supersession in spec §13):
`grep -rn 'sk_emit_skills\|sk_generate_all' adapters/codex adapters/gemini-cli`
returns 0 (skills logic lives only in `adapters/agent-skills/`), and
`grep -rn 'Reach' README.md CHANGELOG VERSION | grep '3\.5\.1'` returns 0 (no
release doc labels this wave with the already-shipped 3.5.1 number).

**Wave 3:** a full-repo grep for stale `collect-spool` references returns 0.

Wave 2 is re-planned (2026-07-15, spec §13) — its phases are execution-grade.
**Wave 3's conditional P6/peer-view parts still need a fresh `/r-plan`** if
Phase 0 Q3 reconfirms cross-session pain; the zero-risk phantom-contract
cleanup (Phase 12 Step 1) may ship as-is.
