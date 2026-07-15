# Implementation Plan: RDF 3.5 "Scale & Reach"

**Goal:** Add scale-adaptive ceremony to the four verbs (task-class tiers:
full / quick-plan / bugfix), a Clarify micro-gate in `/r-spec`, a Consistency
micro-gate in `/r-build`, living/delta specs in `/r-ship`, intent-triggered
skills + `.agents/skills/` tri-tool emission, and the surviving delta of the
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

Not started. Phase 0 (re-triage + 3.4-merge gate) first, then Wave 1.

**RECOMMENDED SPLIT (binding guidance for the controller):** ship **Wave 1 as
3.5.0** immediately — it is tool-agnostic and has zero SOURCE overlap with the
unbuilt 3.4 (only two additive shared TEST files: `governance-contracts.bats`,
appended at EOF, and `tests/Makefile`, appended to the `test:`/`lint:` lists —
both trivial append-merges; see §4.2 of the spec). Ship **Wave 2 as 3.5.1**
only after 3.4 has merged (it shares three shell files with 3.4). **Recommend deferring Wave 3 to 3.6** — it is
probe-dependent and the §4.5 re-triage shows most of Wave B is obsoleted or
low-ROI; pull forward only the zero-risk phantom-contract cleanup. Waves 2–3
SHOULD be re-planned with a fresh `/r-plan` once Phase 0 resolves Q1–Q4 — their
phases below are execution-grade only to the extent the probe allows and are
marked accordingly.

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
| `lib/cmd/generate.sh` `agent-skills` arm | `_generate_adapter` | 0 success / non-0 propagated | `lib/cmd/generate.sh:56-67` |
| `adapters/agent-skills/adapter.sh` | `rdf_get_active_profiles` | 0 always (echoes list) | `lib/rdf_common.sh:159` (echo + read loop, no non-zero path) |
| `adapters/claude-code/adapter.sh` (Wave 2) | `cc_generate_commands` | 0 (3.4/3.3 base — direct-copy loop) | `adapters/claude-code/adapter.sh:118-136` |

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
| `docs/tri-tool-parity.md` | ~90 | AGENTS.md/Skills/MCP matrix; gemini `{{args}}` edge | N/A (docs) |
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
| `adapters/claude-code/adapter.sh` | +`cc_generate_command_frontmatter` (on 3.4 base) | 2 | `tests/agent-skills.bats` |
| `adapters/gemini-cli/adapter.sh` | skills emission + `{{args}}` lossy warning | 2 | `tests/agent-skills.bats` |
| `adapters/codex/adapter.sh` | skills emission | 2 | `tests/agent-skills.bats` |
| `adapters/agents-md/adapter.sh` | reference `.agents/skills/` | 2 | `tests/agent-skills.bats` |
| `lib/cmd/generate.sh` | `agent-skills` target (on 3.4 base) | 2 | `tests/agent-skills.bats` |
| `lib/cmd/deploy.sh` | skills symlink (on 3.4 base) | 2 | `tests/deploy.bats` |
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
- Phase 8 (agent-skills adapter): [0, **3.4 merged**]
- Phase 9 (intent triggers + gemini/codex skills): [8, **3.4 merged**]
- Phase 10 (deploy/sync BATS + parity doc): [8]
- Phase 11 (3.5.1 release): [8,9,10]
- Phase 12 (Wave B re-triage + cleanup): [0] — **recommend defer to 3.6**

**Parallel batches (`/r-build --parallel`):**
- Wave 1: after Phase 0 → **{1}**; then **{2, 3, 4, 5, 6}** (disjoint canonical
  files; the two shared test files `scale-ceremony.bats` +
  `governance-contracts.bats` serialize appends via `/r-build`'s
  file-ownership check); then **{7}**.
- Wave 2 (after 3.4 merged): **{8}** → **{9, 10}** → **{11}**.
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

### Phase 8: agent-skills adapter (Reach — GATED on 3.4 merged + Phase-0 Q1)

> **Gating note:** Do NOT start until Phase 0 Step 4 confirms 3.4 has merged and
> Step 1 confirms the Agent-Skills `SKILL.md` schema. RECOMMEND re-planning
> Waves 2–3 with a fresh `/r-plan` after Phase 0 — the steps below are
> execution-grade only to the extent the probe allows.

Emit `.agents/skills/<command>/SKILL.md` from canonical commands + trigger
descriptions, and wire an `agent-skills` generate target.

**Files:**
- Create: `adapters/agent-skills/adapter.sh`
- Create: `adapters/agent-skills/skill-meta.json`
- Modify: `lib/cmd/generate.sh` (compose on 3.4)
- Create: `tests/agent-skills.bats`
- Modify: `tests/Makefile`

- **Mode**: serial-agent
- **Goals:** 6
- **Accept**: `rdf generate agent-skills` writes
  `.agents/skills/r-spec/SKILL.md` (and the lifecycle set) with `name` +
  `description` frontmatter validating against the Phase-0 schema; a command
  with no `skill-meta.json` entry falls back to a first-sentence description
- **Test**: `tests/agent-skills.bats` — @test "one SKILL.md per lifecycle command with name+description frontmatter"
- **Edge cases**: spec §11b "no skill-meta entry → first-sentence fallback"
- **Regression-case**: tests/agent-skills.bats::@test "one SKILL.md per lifecycle command with name+description frontmatter" (file created in this phase)

- [ ] **Step 1: `skill-meta.json`** — map lifecycle + high-value utility command
  basenames to intent-trigger descriptions ("Use when …"). Bounded set (verbs +
  r-start/r-save/r-audit/r-refresh — not all 37).
- [ ] **Step 2: `adapters/agent-skills/adapter.sh`** — `sk_generate_all`:
  staging-dir + atomic swap (codex adapter pattern); for each command in the
  meta set, write `.agents/skills/<name>/SKILL.md` = frontmatter (name +
  description from meta, or first-sentence fallback) + canonical body verbatim.
  `rdf_require_bin jq`; `command`-prefixed coreutils.
- [ ] **Step 3: `agent-skills` target in `generate.sh`** — add a `case` arm
  (compose after 3.4's `--lite` block) calling
  `_generate_adapter "agent-skills/adapter.sh" "sk_generate_all"`; add to `all`;
  update `_generate_usage`.
- [ ] **Step 4: `tests/agent-skills.bats`** + Makefile entry — assert one
  SKILL.md per meta command, frontmatter has `name:` + `description:`, canonical
  body present.
- [ ] **Step 5: Lint + test + commit** (message: "Add agent-skills adapter —
  `.agents/skills/` intent-triggered commands").

---

### Phase 9: Intent triggers (CC frontmatter) + gemini/codex skills + lossy warning

> **Gating note:** on 3.4-merged `adapters/claude-code/adapter.sh`. Add a NEW
> function + one call; never edit 3.4's `cc_generate_rules`/`--lite` lines.

**Files:**
- Modify: `adapters/claude-code/adapter.sh` (compose on 3.4)
- Modify: `adapters/gemini-cli/adapter.sh`
- Modify: `adapters/codex/adapter.sh`
- Modify: `adapters/agents-md/adapter.sh`
- Modify: `tests/agent-skills.bats`
- Modify: `tests/governance-contracts.bats` (+canonical-frontmatter-free contract)

- **Mode**: serial-agent
- **Goals:** 6, 7, 8
- **Accept**: `output/commands/r-spec.md` begins with `---` + a `description:`
  line (trigger from skill-meta); canonical `r-spec.md` still has no
  frontmatter (contract); gemini positional-arg command TOML carries the
  `{{args}}` lossy warning comment; codex + gemini emit `.agents/skills/`
- **Test**: `tests/agent-skills.bats` — @test "CC command output gains frontmatter; canonical stays frontmatter-free", @test "gemini positional-arg TOML carries lossy warning"
- **Edge cases**: spec §11b "gemini no-positional command → no warning"
- **Regression-case**: governance-contracts.bats::@test "canonical commands carry no YAML frontmatter" (added in this phase)

- [ ] **Step 1: `cc_generate_command_frontmatter`** in `adapters/claude-code/adapter.sh`
  — new function reading `adapters/agent-skills/skill-meta.json`; call it inside
  `cc_generate_commands` (adapter.sh:118-136) to prepend `---\ndescription: >\n
  <trigger>\n---\n` before the canonical body (fallback: first-sentence). Keep
  the `.rdf-hash` sidecar over the CANONICAL body (unchanged).
- [ ] **Step 2: gemini/codex skills emission** — call the shared skills logic (or
  replicate `sk_generate_*`) in `gem_generate_all`/`cdx_generate_all`; both write
  `.agents/skills/` alongside their existing output.
- [ ] **Step 3: gemini `{{args}}` lossy warning** — in `_gem_write_command_toml`
  (gemini adapter :79-118), if the canonical body references a positional arg
  (grep for `$ARGUMENTS`-with-positional patterns), emit a `# NOTE:` comment
  documenting that only `{{args}}` is exposed.
- [ ] **Step 4: agents-md reference** — add a `.agents/skills/` mention to the
  AGENTS.md generation (`amd_generate_all`).
- [ ] **Step 5: canonical-frontmatter-free contract** — in
  `governance-contracts.bats`, assert no `canonical/commands/*.md` starts with
  `---`.
- [ ] **Step 6: Lint + test + commit** (message: "Intent triggers + tri-tool
  skills emission").

---

### Phase 10: Deploy/sync BATS coverage (audit M6) + parity doc

Close the audit M6 gap (zero deploy/sync test coverage) and document the
tri-tool parity matrix incl. the Gemini `{{args}}` lossy edge.

**Files:**
- Create: `tests/deploy.bats`
- Create: `docs/tri-tool-parity.md`
- Modify: `lib/cmd/deploy.sh`
- Modify: `tests/Makefile`

- **Mode**: serial-agent
- **Goals:** 9
- **Accept**: `tests/deploy.bats` covers `_deploy_symlink` create/replace/skip/
  force and the hooks.json manual-merge skip, plus an `rdf sync` round-trip;
  `make -C tests test` runs it green; `docs/tri-tool-parity.md` states the
  AGENTS.md/Skills/MCP matrix and the `{{args}}` limitation
- **Test**: `tests/deploy.bats` — @test "deploy symlink create/replace/skip/force", @test "deploy skips hooks.json", @test "sync pulls emergency edit back to canonical"
- **Edge cases**: spec §11b "deploy.bats on host without bats" (Makefile guard)
- **Regression-case**: tests/deploy.bats::@test "deploy symlink create/replace/skip/force" (file created in this phase)

- [ ] **Step 1: Skills symlink in `lib/cmd/deploy.sh`** (compose on 3.4 base —
  append after 3.4's opt-in `rules/` symlink in `_deploy_claude_code`, never
  editing 3.4's lines): opt-in `.agents/skills/` symlink for the agent-skills
  output. Default off, mirroring 3.4's `--rules` pattern.
- [ ] **Step 2: `tests/deploy.bats`** — hermetic HOME; generate to a temp
  output, then exercise `cmd_deploy claude-code` paths: fresh symlink, replace
  existing symlink, skip real file without `--force`, back-up + replace with
  `--force`, hooks.json skipped, and the new skills symlink. Add an `rdf sync`
  round-trip (edit a deployed file, sync, assert canonical updated).
- [ ] **Step 3: `docs/tri-tool-parity.md`** — matrix of AGENTS.md / Agent-Skills
  / MCP / hooks across CC/Gemini/Codex; the Gemini `{{args}}`-only lossy edge;
  the Codex hooks intersection (recommend-deferred, cross-ref Phase 12).
- [ ] **Step 4: Makefile** — add `deploy.bats` + `agent-skills.bats` to test +
  lint lists.
- [ ] **Step 5: Lint + test + commit** — `git add lib/cmd/deploy.sh
  tests/deploy.bats docs/tri-tool-parity.md tests/Makefile` (message: "Add
  deploy/sync BATS coverage (audit M6) + skills symlink + tri-tool parity doc").

---

### Phase 11: 3.5.1 "Reach" release

VERSION 3.5.1, changelog, README, ROADMAP. Depends on Phases 8–10.

**Files:** `README.md`, `ROADMAP.md`, `CHANGELOG`, `CHANGELOG.RELEASE`, `VERSION`

- **Mode**: serial-context
- **Goals:** 11
- **Accept**: `VERSION` 3.5.1; CHANGELOG block covers skills/intent-triggers/
  parity/deploy-coverage; ROADMAP checks the tri-tool item; `rdf doctor` 0 FAIL;
  full suite green
- **Test**: N/A (docs) — greps below
- **Edge cases**: none
- **Regression-case**: N/A — docs/release phase

- [ ] **Step 1–4:** README (intent-triggered install), ROADMAP (Reach shipped),
  CHANGELOG/CHANGELOG.RELEASE (`## 3.5.1`), VERSION `3.5.1`.
- [ ] **Step 5: Verify + commit**
  ```bash
  cat VERSION                                 # expect: 3.5.1
  bash bin/rdf doctor 2>&1 | grep -c 'FAIL'   # expect: 0
  make -C tests test 2>&1 | grep -c '^not ok' # expect: 0
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
no bare coreutils in new shell source; `rdf_active_tier` never fails (defaults
`full`) and the plan `**Tier:**` marker is authoritative over the pointer (S3);
the consistency gate does not false-block a legacy clean plan and covers a
comma-list Files line (M2 multi-path); the tier cap only lowers gates AND never
drops the security pass on `scope:sensitive`/security-indicator files (M1 — the
highest-value guard); canonical commands carry no YAML frontmatter (Wave 2);
and a full-repo grep for stale `collect-spool` references returns 0.

Per the workspace lesson — **run a fresh `/r-plan` for Waves 2–3 after Phase 0
resolves Q1–Q4**; do not build their phases from this plan's outlines without
the probe-confirmed schemas.
