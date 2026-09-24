# Implementation Plan: Model & Effort Routing + Token Usage Report

**Goal:** Pin model and effort per agent role from one metadata source (Opus 5.5 at xhigh/high/medium by role, Fable 5.1 at high for planning), add `rdf tokens` for measured per-session cost, and add a doctor `harness` scope that catches the Opus 5.5 effort trap.

**Architecture:** `agent-meta.json` gains `effort` and `variants`. The shared emitter writes an `effort:` line and one extra agent file per variant from the same canonical body. The canonical text then routes by agent name instead of a per-call `model`. `rdf-tokens.sh` is a standalone bash + jq state helper, wrapped by `rdf tokens`. `/r-save` records its summary, and `rdf-state.sh` surfaces it to `/r-start`.

**Tech Stack:** bash 3.2/4.1 floor, jq 1.5 floor, BATS (system bats), shellcheck; Claude Code 2.1.280 agent frontmatter (`model`, `effort`)

**Spec:** docs/specs/2026-09-23-model-effort-routing-token-telemetry-design.md

**Phases:** 8

**Plan Version:** 3.0.6

**Tier:** full

## How this plan delivers code

Every line of code in this plan was implemented and validated before the plan was written:
- in a scratch copy of the repo at `a388935`
- full suite 409 ok / 0 failed (364 existing + 45 new)
- `rdf doctor` 0 FAIL
- `claude plugin validate --strict` passed
- `rdf-tokens.sh` and `tests/tokens.bats` also pass under the official jq 1.5 binary

The exact changes are committed next to this plan as sequential patches, one tests patch and one code patch per phase:

```
docs/plans/2026-09-23-model-effort-routing-token-report-patches/
  p1-tests.patch p1-code.patch … p7-tests.patch p7-code.patch p8-code.patch
```

Each phase follows the same order:
1. Apply its **tests** patch.
2. Watch the named tests fail (red).
3. Apply its **code** patch.
4. Watch them pass (green).
5. Lint and commit.

Patches apply in phase order: each patch's context assumes every prior phase landed. They were verified to apply in sequence from `a388935` with `git apply --check`, and the final tree is byte-identical to the validated scratch tree.

> Self-correction notes carried from validation (do not re-discover):
> - jq 1.5 treats `label` as a keyword, so `$label` breaks the whole program. The helper uses `$plabel`, and a test greps for reserved-word variables.
> - Timestamp windows compare the fixed-width `YYYY-MM-DDTHH:MM:SS` prefix. Full-string comparison fails at exact-second boundaries: `…00.000Z` sorts before `…00Z`.
> - jq 1.5 has no `ceil`/`round`. Percentile and rounding math uses `floor` only.
> - `cp` is aliased to `cp -i` on the dev host. Use `/usr/bin/cp` in Bash tool calls; the patches handle all file writes anyway.

## Conventions

**Boilerplate:** new shell files carry `# <path> — <purpose>` / `# (C) 2026 R-fx Networks <proj@rfxn.com>` / `# GNU GPL v2`. Executables set `set -euo pipefail`; sourced `lib/**` files carry no `set` line.

**Naming:** `rdf_*` public helpers (`lib/rdf_common.sh`), `adp_*` (`lib/adapter_common.sh`), `_tok_*` private to `state/rdf-tokens.sh`, `_check_*` doctor checks, `cmd_<name>` subcommand entry.

**Commit message format:** free-form subject; every body line tagged `[New]` `[Change]` `[Fix]` `[Remove]`; no Co-Authored-By or AI attribution. Stage files explicitly by name — never `git add -A` / `git add .`.

**CRITICAL:**
- **Canonical changes regenerate output.** Phases touching `canonical/` or `agent-meta.json` must run `bin/rdf generate claude-code` and `bin/rdf generate claude-plugin`. The same commit must include the regenerated `adapters/claude-plugin/output/**` files and `.claude-plugin/plugin.json` (CI drift gate: `git diff --exit-code adapters/claude-plugin/output .claude-plugin/plugin.json`).
- **Changelog lands once.** CHANGELOG and CHANGELOG.RELEASE are consolidated in Phase 8 under `## Unreleased`, following the 3.7.0 precedent (commit `42ad580`); the version is assigned at ship. Phases 1-7 do not edit either changelog.
- **Shell floor and suppressions.** Bash 3.2/4.1 floor: no `mapfile`, `local -A`, `${v,,}`, `declare -n`, `&>>`. Every new `2>/dev/null` / `|| true` carries a same-line justification (already true in the patches).
- **Tests are hermetic.** `tests/doctor.bats` harness tests clear `BASH_MAX_OUTPUT_LENGTH`, `CLAUDE_CODE_EFFORT_LEVEL` and `ANTHROPIC_MODEL` with `env -u`, and override `_HARNESS_MANAGED_PATHS` (empty unless a test passes `RDF_TEST_MANAGED_PATHS`).

## File Map

### New Files
| File | Lines | Purpose | Test File |
|------|-------|---------|-----------|
| `state/rdf-tokens.sh` | 346 | Local token usage report from Claude Code transcripts (bash + jq) | `tests/tokens.bats` |
| `lib/cmd/tokens.sh` | 12 | `rdf tokens` wrapper → `${RDF_STATE_DIR}/rdf-tokens.sh` | `tests/tokens.bats` |
| `tests/tokens.bats` | 187 | rdf tokens behavior + session_last tokens pass-through | N/A (test) |
| `tests/fixtures/tokens/proj/s1.jsonl` | 9 | fixture main transcript (dup ids, synthetic, id-less, truncated, old) | N/A (fixture) |
| `tests/fixtures/tokens/proj/s1/subagents/agent-a1.jsonl` | 2 | fixture subagent (no cache_creation object) | N/A (fixture) |
| `tests/fixtures/tokens/proj/s1/subagents/agent-a1.meta.json` | 1 | fixture meta (rdf-engineer) | N/A (fixture) |
| `tests/fixtures/tokens/proj/s1/subagents/workflows/wf_x/agent-w1.jsonl` | 1 | fixture workflow subagent (Fable 5.1) | N/A (fixture) |
| `tests/fixtures/tokens/proj/s1/subagents/workflows/wf_x/agent-w1.meta.json` | 1 | fixture meta (general-purpose) | N/A (fixture) |
| `tests/fixtures/tokens/proj/s2.jsonl` | 1 | fixture second session, unpriced model | N/A (fixture) |
| `tests/fixtures/adapter-common/agent-meta-3.7.0.json` | 71 | frozen 3.7.0 agent catalog for the byte-identity emitter test | N/A (fixture) |
| `adapters/claude-plugin/output/agents/engineer-focused.md` | 197 | generated variant (committed plugin output) | `tests/plugin-adapter.bats` |
| `adapters/claude-plugin/output/agents/reviewer-challenge.md` | 322 | generated variant (committed plugin output) | `tests/plugin-adapter.bats` |

### Modified Files
| File | Changes | Test File |
|------|---------|-----------|
| `lib/rdf_common.sh` | `rdf_agent_routing_errors`, `rdf_agent_variant_stems`; `rdf_require_agent_meta` validates routing | `tests/strip.bats` |
| `lib/adapter_common.sh` | `adp_agent_frontmatter` variant arg + `effort:` line; `adp_emit_agents` emits variants | `tests/adapter-common.bats` |
| `adapters/claude-code/adapter.sh` | `rdf_require_bin jq` before `rdf_require_agent_meta` | `tests/adapter-common.bats` |
| `tests/strip.bats` | routing-validation tests | N/A (test) |
| `tests/adapter-common.bats` | byte-identity test reads frozen meta; variant emission test; live routing tests | N/A (test) |
| `lib/cmd/sync.sh` | agents loop never creates a canonical agent; skipped counter | `tests/sync.bats` |
| `tests/sync.bats` | variant/stray skip test | N/A (test) |
| `lib/cmd/doctor.sh` | `_check_harness`, `_json_esc`, routing in `_check_catalogs`, variant-aware `_check_sync`, scope wiring | `tests/doctor.bats` |
| `tests/doctor.bats` | JSON escaping, catalogs routing, sync count, harness matrix | N/A (test) |
| `bin/rdf` | `tokens` case + usage line | `tests/tokens.bats` |
| `tests/Makefile` | register `tokens.bats` in `test` and `lint` | N/A (test infra) |
| `tests/deploy.bats` | state-helper link count derived from `state/*.sh` | N/A (test) |
| `state/rdf-state.sh` | `_session_pick` (save-then-hook selection) + keep-list `tokens` | `tests/tokens.bats` |
| `adapters/claude-code/agent-meta.json` | model/effort per agent; variants on engineer, reviewer | `tests/adapter-common.bats` |
| `tests/plugin-adapter.bats` | plugin.json lists variant files | N/A (test) |
| `.claude-plugin/plugin.json` | regenerated agents array (+2 variant paths) | `tests/plugin-adapter.bats` |
| `adapters/claude-plugin/output/agents/dispatcher.md` | regenerated (Phases 6, 7) | `tests/plugin-adapter.bats` |
| `adapters/claude-plugin/output/agents/engineer.md` | regenerated | `tests/plugin-adapter.bats` |
| `adapters/claude-plugin/output/agents/planner.md` | regenerated | `tests/plugin-adapter.bats` |
| `adapters/claude-plugin/output/agents/qa.md` | regenerated | `tests/plugin-adapter.bats` |
| `adapters/claude-plugin/output/agents/reviewer.md` | regenerated | `tests/plugin-adapter.bats` |
| `adapters/claude-plugin/output/agents/uat.md` | regenerated | `tests/plugin-adapter.bats` |
| `canonical/agents/dispatcher.md` | agent routing + focused→base escalation | `tests/governance-contracts.bats` |
| `canonical/commands/r-spec.md` | `## Model` advisory; `rdf-reviewer-challenge`; handoff | `tests/governance-contracts.bats` |
| `canonical/commands/r-plan.md` | `## Model` advisory; `rdf-reviewer-challenge`; handoff | `tests/governance-contracts.bats` |
| `canonical/commands/r-review.md` | challenge/sentinel agent routing | `tests/governance-contracts.bats` |
| `canonical/commands/r-sync.md` | `effort:` illustration; variants never imported | `tests/governance-contracts.bats` |
| `canonical/commands/r-save.md` | `tokens` field + capture snippet; one compact line | `tests/governance-contracts.bats` |
| `canonical/commands/r-start.md` | Last line cost segment | `tests/governance-contracts.bats` |
| `tests/governance-contracts.bats` | routing / advisory / handoff / tokens contracts | N/A (test) |
| `adapters/claude-plugin/output/skills/r-spec/SKILL.md` | regenerated | `tests/plugin-adapter.bats` |
| `adapters/claude-plugin/output/skills/r-plan/SKILL.md` | regenerated | `tests/plugin-adapter.bats` |
| `adapters/claude-plugin/output/skills/r-review/SKILL.md` | regenerated | `tests/plugin-adapter.bats` |
| `adapters/claude-plugin/output/skills/r-sync/SKILL.md` | regenerated | `tests/plugin-adapter.bats` |
| `adapters/claude-plugin/output/skills/r-save/SKILL.md` | regenerated | `tests/plugin-adapter.bats` |
| `adapters/claude-plugin/output/skills/r-start/SKILL.md` | regenerated | `tests/plugin-adapter.bats` |
| `README.md` | roster (model · effort), CLI table (`rdf tokens`, doctor 15), token usage paragraph, Add-an-Agent schema, trees | N/A (docs) |
| `RDF.md` | agent table, trees | N/A (docs) |
| `WORKFORCE.md` | diagram labels, agent headings, Model Summary | N/A (docs) |
| `docs/demo-walkthrough.md` | roster table | N/A (docs) |
| `docs/multi-tool-parity.md` | §4b routing, deferred bullet | N/A (docs) |
| `docs/privacy.md` | `rdf tokens` reads local transcripts only | N/A (docs) |
| `CHANGELOG` | `## Unreleased` entries | N/A (docs) |
| `CHANGELOG.RELEASE` | Unreleased release notes | N/A (docs) |

### Deleted Files
| File | Reason |
|------|--------|

## RC Contract Evidence

| Caller | Helper | Contract (verified by running the validated code) |
|---|---|---|
| `rdf_require_agent_meta` | `rdf_agent_routing_errors` | rc 0 always; stdout = one error line per violation; empty = valid |
| `_check_catalogs`, `_check_sync` | `rdf_agent_variant_stems` | rc 0 always (`\|\| true` on unparseable meta); stdout = `<agent>-<variant>` lines |
| `adp_emit_agents` | `adp_agent_frontmatter` | rc 1 + warn when agent absent from meta (existing); rc 0 otherwise, including with a variant arg |
| `cmd_tokens` | `state/rdf-tokens.sh` | exit 0 report (including an empty window), 1 transcripts not found / jq absent, 2 usage error; passed through unchanged |
| `/r-save` step 5 | `rdf-tokens.sh --session … --summary` | non-zero on any failure → caller records `null` |
| `_doctor_one` | `_check_harness` | rc 0 always; WARN/OK results only (never FAIL) |
| rdf-state main | `_session_pick` | rc 0 always; stdout = selected line (possibly empty) |

## Phase Dependencies

- Phase 1: none
- Phase 2: [1]
- Phase 3: [2]
- Phase 4: [3]
- Phase 5: [4]
- Phase 6: [5]
- Phase 7: [6]
- Phase 8: [7]

Strictly sequential by design. Each patch's context and each phase's verification assume every earlier phase landed. For example, Phase 6 Step 5 greps doctor output that only Phase 3 adds, `tests/adapter-common.bats` is patched in 1 then 6, and `tests/tokens.bats` in 4 then 5. Patch context alone does not force the order, because most patches also apply cleanly out of order, so this list is what `/r-build` enforces.

**Deviation from spec, resolved at the source:** spec §4.6 and Risk 6 originally put tree and count doc updates in each code phase. They are consolidated in Phase 8, and the spec is amended to match. The plan review measured 0 `not ok` and 0 doctor FAIL at every intermediate commit, because the doc-truth tree scan only checks that listed paths exist. The Goal 1 routing-table test lives in `tests/adapter-common.bats`, next to the other live-meta tests; spec §10a is amended to match.

---

### Phase 1: Routing validation and variant emission

Adds `rdf_agent_routing_errors` / `rdf_agent_variant_stems`, which `rdf generate` enforces, and teaches the shared emitter to write `effort:` lines and variant files. The live `agent-meta.json` is not changed here, so generated output stays identical.

**Files:**
- Modify: `lib/rdf_common.sh` (routing validation helpers)
- Modify: `lib/adapter_common.sh` (effort line + variant emission)
- Modify: `adapters/claude-code/adapter.sh` (jq check before meta validation)
- Modify: `tests/strip.bats` (validation tests)
- Modify: `tests/adapter-common.bats` (frozen-meta repoint + variant test)
- Create: `tests/fixtures/adapter-common/agent-meta-3.7.0.json` (frozen catalog)

- **Mode**: serial-agent
- **Goals:** 2, 3, 4
- **Accept**: `bats tests/strip.bats tests/adapter-common.bats` reports 0 `not ok`; `bin/rdf generate claude-code` still prints `6 agents`; shellcheck `-S error` clean on the 3 shell files
- **Test**: `tests/strip.bats::@test "require_agent_meta: dies on invalid effort, model, variant key, missing variant effort, and variant collision"`, `tests/strip.bats::@test "require_agent_meta: missing model and effort are valid"` (guard: passes before and after the code patch), `tests/adapter-common.bats::@test "adp_emit_agents emits an effort line and a variant file per declared variant"`, `tests/adapter-common.bats::@test "adp_emit_agents output is byte-identical to the 3.6.5 emitter fixture"`
- **Edge cases**: variant stem collides with a canonical agent (generate dies); missing model/effort valid; metadata without effort emits byte-identical frontmatter
- **Regression-case**: tests/adapter-common.bats::@test "adp_emit_agents output is byte-identical to the 3.6.5 emitter fixture"

- [ ] **Step 1: Apply the tests patch**

  ```bash
  P=docs/plans/2026-09-23-model-effort-routing-token-report-patches
  git hash-object "$P/p1-tests.patch"
  # expect: 569e2230d764fcab12099adf02d04ed8cbed21ff
  git apply --check "$P/p1-tests.patch" && git apply "$P/p1-tests.patch" && echo applied
  # expect: applied
  ```

- [ ] **Step 2: Red — the new tests fail before the code exists**

  ```bash
  bats tests/strip.bats tests/adapter-common.bats 2>&1 | grep '^not ok' | sed 's/^not ok [0-9]* //'
  # expect:
  # require_agent_meta: dies on invalid effort, model, variant key, missing variant effort, and variant collision
  # adp_emit_agents emits an effort line and a variant file per declared variant
  ```

- [ ] **Step 3: Apply the code patch**

  The patch:
  - adds `rdf_agent_routing_errors`, which reads jq `@tsv` rows `label field value` and validates them with bash `case` (no jq regex), plus `rdf_agent_variant_stems`
  - appends the routing check to `rdf_require_agent_meta`, dying with `invalid agent routing in agent-meta.json: <errors joined by '; '>`
  - extends `adp_agent_frontmatter meta agent [variant]` and emits `effort: X` only when set
  - loops variants in `adp_emit_agents`, with the same body and the same sidecar source
  - swaps the jq check before `rdf_require_agent_meta` in `cc_generate_all`

  ```bash
  git hash-object "$P/p1-code.patch"
  # expect: 66e0ba108d65c632559a24e187081726e51ec98f
  git apply --check "$P/p1-code.patch" && git apply "$P/p1-code.patch" && echo applied
  # expect: applied
  ```

- [ ] **Step 4: Green + lint**

  ```bash
  bats tests/strip.bats tests/adapter-common.bats 2>&1 | grep -c '^not ok'
  # expect: 0
  bash -n lib/rdf_common.sh lib/adapter_common.sh adapters/claude-code/adapter.sh && shellcheck lib/rdf_common.sh lib/adapter_common.sh tests/strip.bats tests/adapter-common.bats && shellcheck -S error --exclude=SC1090,SC1091 adapters/claude-code/adapter.sh && echo lint-ok
  # expect: lint-ok
  bin/rdf generate claude-code 2>&1 | grep -o 'complete: [0-9]* agents'
  # expect: complete: 6 agents
  ```

- [ ] **Step 5: Commit**

  ```bash
  git add lib/rdf_common.sh lib/adapter_common.sh adapters/claude-code/adapter.sh tests/strip.bats tests/adapter-common.bats tests/fixtures/adapter-common/agent-meta-3.7.0.json
  git commit -F - <<'EOF'
  Routing: agent-meta effort + variants — validation and emission

  [New] rdf_agent_routing_errors / rdf_agent_variant_stems: validate model, effort, and variants in agent-meta.json; rdf generate dies on invalid routing
  [New] adp_agent_frontmatter/adp_emit_agents: emit an effort: line when set and one agent file per declared variant from the same canonical body
  [Change] claude-code adapter checks for jq before validating agent-meta
  [Change] byte-identity emitter test reads a frozen 3.7.0 catalog (tests/fixtures/adapter-common/agent-meta-3.7.0.json)
  EOF
  git log --oneline -1
  # expect: <hash> Routing: agent-meta effort + variants — validation and emission
  ```

---

### Phase 2: sync never creates a canonical agent

Generated variants (and any stray output agent) have no canonical source. `rdf sync` now skips them instead of creating `canonical/agents/<variant>.md`, which would then fail `rdf generate` on the collision check.

**Files:**
- Modify: `lib/cmd/sync.sh` (skip agents without a canonical file)
- Modify: `tests/sync.bats` (skip test)

- **Mode**: serial-agent
- **Goals:** 7
- **Accept**: `bats tests/sync.bats` reports 0 `not ok`; the new test asserts `canonical/agents/a-lite.md` is not created and the output contains `1 skipped`
- **Test**: `tests/sync.bats::@test "sync never creates a canonical agent from a variant or stray output file"`
- **Edge cases**: emergency edit to a deployed variant (sync skips with a message; content-drift still flags it)
- **Regression-case**: tests/sync.bats::@test "sync agents: frontmatter-less output syncs verbatim (no truncation)"

- [ ] **Step 1: Apply the tests patch**

  ```bash
  P=docs/plans/2026-09-23-model-effort-routing-token-report-patches
  git hash-object "$P/p2-tests.patch"
  # expect: ec1c154773833d63c776e8432c1c8f85e2f746d6
  git apply --check "$P/p2-tests.patch" && git apply "$P/p2-tests.patch" && echo applied
  # expect: applied
  ```

- [ ] **Step 2: Red**

  ```bash
  bats tests/sync.bats 2>&1 | grep '^not ok' | sed 's/^not ok [0-9]* //'
  # expect:
  # sync never creates a canonical agent from a variant or stray output file
  ```

- [ ] **Step 3: Apply the code patch** — adds `local skipped=0`. Before `_sync_body`, a guard `if [[ ! -f "$canon_file" ]]` logs `skipping agents/<f>: no canonical agent (generated variant or stray output)`, counts it and continues. The summary appends `, N skipped` only when N > 0, so existing output is unchanged.

  ```bash
  git hash-object "$P/p2-code.patch"
  # expect: 221b045d310ae616c5b2c97b6185d7695f4bfa25
  git apply --check "$P/p2-code.patch" && git apply "$P/p2-code.patch" && echo applied
  # expect: applied
  ```

- [ ] **Step 4: Green + lint**

  ```bash
  bats tests/sync.bats tests/deploy.bats 2>&1 | grep -c '^not ok'
  # expect: 0
  bash -n lib/cmd/sync.sh && shellcheck lib/cmd/sync.sh tests/sync.bats && echo lint-ok
  # expect: lint-ok
  ```

- [ ] **Step 5: Commit**

  ```bash
  git add lib/cmd/sync.sh tests/sync.bats
  git commit -F - <<'EOF'
  sync: never create a canonical agent from generated output

  [Change] rdf sync skips output agents with no canonical counterpart (generated variants, stray files) and reports them as skipped instead of creating canonical/agents/<name>.md
  EOF
  git log --oneline -1
  # expect: <hash> sync: never create a canonical agent from generated output
  ```

---

### Phase 3: doctor — harness scope, routing catalog, variant-aware sync count, JSON escaping

Adds the 15th doctor scope `harness`. Its checks:
- the Opus 5.5 effort pin
- `CLAUDE_CODE_EFFORT_LEVEL` flattening agent effort (probe-verified 2026-09-23)
- `bashOutputMaxChars` / `BASH_MAX_OUTPUT_LENGTH` above 30000

The phase also adds routing validation to `catalogs` and teaches the `sync` agent count to exclude variants. It fixes the latent invalid-JSON bug in `--json` output as well.

**Files:**
- Modify: `lib/cmd/doctor.sh` (harness check, JSON escaping, catalogs, sync count, scope wiring)
- Modify: `tests/doctor.bats` (new tests)

- **Mode**: serial-agent
- **Goals:** 4, 7, 10
- **Accept**:
  - `bats tests/doctor.bats` reports 0 `not ok`
  - `bin/rdf doctor --scope harness --json | jq -r '.checks[].category' | sort -u` prints `harness`
  - `bin/rdf doctor --scope bogus` error text lists `harness`
- **Test**: all eleven RED tests listed in Step 2 (named `tests/doctor.bats` tests)
- **Edge cases**: unparseable settings file skipped; non-numeric `BASH_MAX_OUTPUT_LENGTH` = unset; main model sonnet/fable/best not applicable; message with quotes/backslash/tab → valid JSON; `CLAUDE_CODE_EFFORT_LEVEL=auto` = unset; `bashOutputMaxChars` beats the env var; managed-settings top-level `effortLevel` pins
- **Regression-case**: tests/doctor.bats::@test "doctor catalogs: missing agent-meta entry FAILs, orphan WARNs"

- [ ] **Step 1: Apply the tests patch**

  ```bash
  P=docs/plans/2026-09-23-model-effort-routing-token-report-patches
  git hash-object "$P/p3-tests.patch"
  # expect: 61788593ec6334a299d6b4cfc8461591d60ad992
  git apply --check "$P/p3-tests.patch" && git apply "$P/p3-tests.patch" && echo applied
  # expect: applied
  ```

- [ ] **Step 2: Red**

  ```bash
  bats tests/doctor.bats 2>&1 | grep '^not ok' | sed 's/^not ok [0-9]* //'
  # expect:
  # doctor --json stays valid when a message contains quotes and backslashes
  # doctor catalogs: invalid agent routing FAILs; valid routing reports OK
  # doctor sync: agent count excludes declared variants
  # doctor harness: unpinned Opus 5.5 WARNs; legacy user effortLevel is named
  # doctor harness: modelSettings pin is OK
  # doctor harness: CLAUDE_CODE_EFFORT_LEVEL WARNs as flattening; auto counts as unset
  # doctor harness: project top-level effortLevel pins, user top-level does not
  # doctor harness: managed-settings top-level effortLevel pins
  # doctor harness: unparseable settings file is skipped and the next file is read
  # doctor harness: non-opus model is not applicable
  # doctor harness: BASH_MAX_OUTPUT_LENGTH above 30000 WARNs; bashOutputMaxChars takes precedence
  ```

- [ ] **Step 3: Apply the code patch** — the patch makes these changes to `lib/cmd/doctor.sh`:
  - `_HARNESS_MANAGED_PATHS` global (colon list; tests override it)
  - `_check_harness path`, with its full algorithm in spec §5.5
  - `_json_esc`: one `sed` per entry, applied to the whole entry before the `|` split, and to name/path
  - `_check_catalogs` routing FAIL/OK lines
  - `_check_sync`: excludes variant stems; without jq it WARNs `jq not found — agent count skipped`
  - `harness` wired into the usage text, the `""|all` scope, the `harness)` case and the unknown-scope message

  ```bash
  git hash-object "$P/p3-code.patch"
  # expect: 330a5c6760595f147c4d31ed1a1226c108156a5e
  git apply --check "$P/p3-code.patch" && git apply "$P/p3-code.patch" && echo applied
  # expect: applied
  ```

- [ ] **Step 4: Green + lint + live smoke**

  ```bash
  bats tests/doctor.bats 2>&1 | grep -c '^not ok'
  # expect: 0
  bash -n lib/cmd/doctor.sh && shellcheck -S error --exclude=SC1090,SC1091 lib/cmd/doctor.sh && shellcheck tests/doctor.bats && echo lint-ok
  # expect: lint-ok
  bin/rdf doctor --scope harness --json | jq -r '.checks[].category' | sort -u
  # expect: harness
  bin/rdf doctor --scope bogus 2>&1 | grep -c 'doc-truth, harness'
  # expect: 1
  ```

- [ ] **Step 5: Commit**

  ```bash
  git add lib/cmd/doctor.sh tests/doctor.bats
  git commit -F - <<'EOF'
  doctor: harness scope, routing catalog check, variant-aware sync count, JSON escaping

  [New] rdf doctor --scope harness: WARNs when Opus 5.5 would run at its medium default, when CLAUDE_CODE_EFFORT_LEVEL flattens per-agent effort, and when the Bash output limit exceeds 30000; never writes settings
  [New] doctor catalogs reports invalid agent routing (model, effort, variants) as FAIL
  [Change] doctor sync agent count excludes declared variants; WARNs when jq is absent
  [Fix] doctor --json escapes quotes, backslashes, and control characters (a quote in any message produced invalid JSON)
  EOF
  git log --oneline -1
  # expect: <hash> doctor: harness scope, routing catalog check, variant-aware sync count, JSON escaping
  ```

---

### Phase 4: `rdf tokens` — local token usage report

A standalone state helper, delivered by the existing `state/*.sh` globs. It reads Claude Code transcripts (main plus `subagents/` and `subagents/workflows/*/`). It dedups by `message.id` (max per usage field) and prices by longest model-prefix match. It renders text, `--json` or `--summary`. A committed fixture pins hand-computed figures (spec §10a).

**Files:**
- Create: `state/rdf-tokens.sh` (helper)
- Create: `lib/cmd/tokens.sh` (wrapper)
- Modify: `bin/rdf` (tokens case + usage line)
- Create: `tests/tokens.bats` (behavior tests)
- Create: `tests/fixtures/tokens/proj/s1.jsonl` (fixture)
- Create: `tests/fixtures/tokens/proj/s1/subagents/agent-a1.jsonl` (fixture)
- Create: `tests/fixtures/tokens/proj/s1/subagents/agent-a1.meta.json` (fixture)
- Create: `tests/fixtures/tokens/proj/s1/subagents/workflows/wf_x/agent-w1.jsonl` (fixture)
- Create: `tests/fixtures/tokens/proj/s1/subagents/workflows/wf_x/agent-w1.meta.json` (fixture)
- Create: `tests/fixtures/tokens/proj/s2.jsonl` (fixture)
- Modify: `tests/Makefile` (register tokens.bats)
- Modify: `tests/deploy.bats` (derived helper count)

- **Mode**: serial-agent
- **Goals:** 8
- **Accept**:
  - `bats tests/tokens.bats tests/deploy.bats` reports 0 `not ok`
  - `bin/rdf tokens --transcripts tests/fixtures/tokens/proj --since 2026-09-01 --json | jq -c '[.api_turns, .cost_usd, .unpriced_models]'` prints `[6,0.3981,["claude-mystery-9"]]`
  - `bin/rdf doctor --scope doc-truth` shows 0 FAIL
- **Test**: all RED tests listed in Step 2 (named `tests/tokens.bats` tests); `tests/deploy.bats::@test "deploy claude-code symlinks state helpers per-file (glob)"`
- **Edge cases**:
  - dedup of repeated ids
  - a truncated line is skipped
  - absent `cache_creation` → 5 m
  - `[1m]` / date-suffixed model priced by prefix
  - an unpriced model is excluded from shares
  - missing subagent meta → `unknown`
  - an empty window → exit 0 `no usage in window`
  - `--session` with path characters → exit 2
  - logical vs physical slug
  - large file lists: xargs batching, and the agent map passed with `--slurpfile`
  - `--session` on a resumed session includes copied history (documented in usage)
- **Regression-case**: tests/tokens.bats::@test "--json on the fixture reproduces the hand-computed report"

- [ ] **Step 1: Apply the tests patch** (creates `tests/tokens.bats`, the fixture tree, the Makefile registration and the derived count in `deploy.bats`)

  ```bash
  P=docs/plans/2026-09-23-model-effort-routing-token-report-patches
  git hash-object "$P/p4-tests.patch"
  # expect: 817e2da9fdcfa6555c408a818e14d04acb6dc31e
  git apply --check "$P/p4-tests.patch" && git apply "$P/p4-tests.patch" && echo applied
  # expect: applied
  ```

- [ ] **Step 2: Red**

  ```bash
  bats tests/tokens.bats 2>&1 | grep '^not ok' | sed 's/^not ok [0-9]* //'
  # expect:
  # --json on the fixture reproduces the hand-computed report
  # dedups repeated message.id entries (usage counted once)
  # labels subagents by meta agentType including workflow subagents
  # skips synthetic, id-less and malformed entries
  # --since excludes older entries
  # --session includes out-of-window rows and only that session
  # --summary emits the compact session object
  # unknown model is reported unpriced and excluded from shares
  # text output shows spend and by-agent rows
  # empty window prints no usage and exits 0
  # bad --days and bad --session exit 2; missing transcripts exit 1
  # rdf tokens wrapper forwards help and exit codes
  # prices [1m] and dated model ids, labels a meta-less subagent unknown, dedups across files, falls back to the physical slug
  # rdf-tokens.sh uses no jq 1.6+ builtins or reserved-word variables
  ```

- [ ] **Step 3: Apply the code patch**

  The patch creates:
  - `state/rdf-tokens.sh` (346 lines, mode 100755), with functions `_tok_usage _tok_die _tok_slug _tok_resolve_dir _tok_prices _tok_window _tok_files _tok_agent_map _tok_rows _tok_report _tok_render main`
  - `lib/cmd/tokens.sh` (`cmd_tokens`, which forwards all args including `help`)
  - in the helper, an EXIT trap that removes the work dir only when one was created, and a "no transcripts" error that names the resolved project path
  - the `bin/rdf` `tokens)` case and usage line

  ```bash
  git hash-object "$P/p4-code.patch"
  # expect: 6e6dc9674d647970c560d5d62178bc29e7f00cfa
  git apply --check "$P/p4-code.patch" && git apply "$P/p4-code.patch" && echo applied
  # expect: applied
  test -x state/rdf-tokens.sh && echo executable
  # expect: executable
  ```

- [ ] **Step 4: Green + lint + real-data smoke**

  ```bash
  bats tests/tokens.bats tests/deploy.bats 2>&1 | grep -c '^not ok'
  # expect: 0
  bash -n state/rdf-tokens.sh lib/cmd/tokens.sh bin/rdf && shellcheck state/rdf-tokens.sh lib/cmd/tokens.sh tests/tokens.bats && shellcheck -S error --exclude=SC1090,SC1091 bin/rdf && echo lint-ok
  # expect: lint-ok
  bin/rdf tokens --transcripts tests/fixtures/tokens/proj --since 2026-09-01 --json | jq -c '[.api_turns, .cost_usd, .unpriced_models]'
  # expect: [6,0.3981,["claude-mystery-9"]]
  d="$(mktemp -d)"; bin/rdf tokens --transcripts "$d" --days 30; echo "rc=$?"; rm -rf "$d"
  # expect:
  # no usage in window
  # rc=0
  bin/rdf doctor --scope doc-truth 2>&1 | grep -c '\[FAIL\]'
  # expect: 0
  ```

- [ ] **Step 5: Commit**

  ```bash
  git add state/rdf-tokens.sh lib/cmd/tokens.sh bin/rdf tests/tokens.bats tests/Makefile tests/deploy.bats tests/fixtures/tokens/proj/s1.jsonl tests/fixtures/tokens/proj/s1/subagents/agent-a1.jsonl tests/fixtures/tokens/proj/s1/subagents/agent-a1.meta.json tests/fixtures/tokens/proj/s1/subagents/workflows/wf_x/agent-w1.jsonl tests/fixtures/tokens/proj/s1/subagents/workflows/wf_x/agent-w1.meta.json tests/fixtures/tokens/proj/s2.jsonl
  git commit -F - <<'EOF'
  rdf tokens: local token usage report from Claude Code transcripts

  [New] state/rdf-tokens.sh (bash + jq, jq 1.5 floor): usage deduplicated by message.id, list-price cost by cost class, model, agent, context depth, subagent boot, and effort; text, --json, and --summary; transcripts are read locally only
  [New] rdf tokens subcommand (lib/cmd/tokens.sh) forwarding to the state helper
  [New] tests/tokens.bats with a hand-computed fixture transcript tree
  [Change] deploy.bats derives the expected state-helper link count from state/*.sh
  EOF
  git log --oneline -1
  # expect: <hash> rdf tokens: local token usage report from Claude Code transcripts
  ```

---

### Phase 5: session_last keeps the `/r-save` entry and its tokens summary

The SessionEnd hook appends an entry after `/r-save`, and `rdf-state.sh` read only the last line, so the richer `/r-save` entry (commits, diff summary, now tokens) was shadowed. `_session_pick` prefers the previous line when:
- the last line is a hook entry
- the previous line is not
- both carry a non-empty `head_after`, compared by prefix and tolerant of spaced JSON

The python keep-list gains `tokens`.

**Files:**
- Modify: `state/rdf-state.sh` (`_session_pick` + keep-list)
- Modify: `tests/tokens.bats` (session_last tests)

- **Mode**: serial-agent
- **Goals:** 9
- **Accept**: `bats tests/tokens.bats` reports 0 `not ok`; the same with python3 hidden (`PATH` shim to `/bin/false`) also reports 0 `not ok` for `-f session_last`
- **Test**: all RED tests listed in Step 2; `tests/tokens.bats::@test "session_last keeps a hook entry whose head_after differs"` (guard; passes before and after)
- **Edge cases**: save-then-hook same state → save entry; spaced save entry selected; hook with different `head_after` kept; one-line log unchanged; cross-session save followed by a no-commit hook → save entry (acceptable)
- **Regression-case**: tests/tokens.bats::@test "session_last keeps a hook entry whose head_after differs"

- [ ] **Step 1: Apply the tests patch**

  ```bash
  P=docs/plans/2026-09-23-model-effort-routing-token-report-patches
  git hash-object "$P/p5-tests.patch"
  # expect: 489e4088806ced551a073167fae9eb308f471697
  git apply --check "$P/p5-tests.patch" && git apply "$P/p5-tests.patch" && echo applied
  # expect: applied
  ```

- [ ] **Step 2: Red**

  ```bash
  bats tests/tokens.bats 2>&1 | grep '^not ok' | sed 's/^not ok [0-9]* //'
  # expect:
  # rdf-state.sh session_last preserves a tokens object
  # session_last prefers the /r-save entry over a trailing same-state SessionEnd-hook entry
  # session_last selects a pretty-spaced /r-save entry
  ```

- [ ] **Step 3: Apply the code patch** — adds `_session_pick` after `_json_str`, replaces `tail -1 "$_session_file"` with `_session_pick "$_session_file"`, and appends `'tokens'` to the keep-list

  ```bash
  git hash-object "$P/p5-code.patch"
  # expect: 7f242c01c3ac404159ddd07f2100fde497fc466f
  git apply --check "$P/p5-code.patch" && git apply "$P/p5-code.patch" && echo applied
  # expect: applied
  ```

- [ ] **Step 4: Green (python and no-python paths) + lint**

  ```bash
  bats tests/tokens.bats 2>&1 | grep -c '^not ok'
  # expect: 0
  d="$(mktemp -d)"; ln -s /bin/false "$d/python3"; PATH="$d:$PATH" bats tests/tokens.bats -f session_last 2>&1 | grep -c '^not ok'; rm -rf "$d"
  # expect: 0
  bash -n state/rdf-state.sh && shellcheck -S error --exclude=SC1090,SC1091 state/rdf-state.sh && echo lint-ok
  # expect: lint-ok
  bash state/rdf-state.sh --full . | jq -e . >/dev/null && echo state-json-ok
  # expect: state-json-ok
  ```

- [ ] **Step 5: Commit**

  ```bash
  git add state/rdf-state.sh tests/tokens.bats
  git commit -F - <<'EOF'
  rdf-state: session_last keeps the /r-save entry and its tokens summary

  [Fix] session_last prefers the /r-save entry over the trailing same-state SessionEnd-hook entry, restoring commits and diff_summary on the /r-start Last line
  [New] session_last keep-list includes tokens
  EOF
  git log --oneline -1
  # expect: <hash> rdf-state: session_last keeps the /r-save entry and its tokens summary
  ```

---

### Phase 6: live routing values + regenerate

Sets the routing table in `agent-meta.json`:

| Agent | Model | Effort | Variant |
|---|---|---|---|
| planner | fable | high | — |
| dispatcher | opus | high | — |
| engineer | opus | xhigh | `focused` at medium |
| qa | opus | medium | — |
| uat | opus | medium | — |
| reviewer | opus | xhigh | `challenge` at high |

It then regenerates both Claude Code targets. The live `~/.claude/agents` symlink points at `adapters/claude-code/output/agents`, so new sessions pick up the variants immediately.

**Files:**
- Modify: `adapters/claude-code/agent-meta.json` (routing values)
- Modify: `tests/adapter-common.bats` (live routing tests)
- Modify: `tests/plugin-adapter.bats` (plugin variant test)
- Modify: `.claude-plugin/plugin.json` (regenerated)
- Modify: `adapters/claude-plugin/output/agents/dispatcher.md` (regenerated)
- Modify: `adapters/claude-plugin/output/agents/engineer.md` (regenerated)
- Modify: `adapters/claude-plugin/output/agents/planner.md` (regenerated)
- Modify: `adapters/claude-plugin/output/agents/qa.md` (regenerated)
- Modify: `adapters/claude-plugin/output/agents/reviewer.md` (regenerated)
- Modify: `adapters/claude-plugin/output/agents/uat.md` (regenerated)
- Create: `adapters/claude-plugin/output/agents/engineer-focused.md` (regenerated variant)
- Create: `adapters/claude-plugin/output/agents/reviewer-challenge.md` (regenerated variant)

- **Mode**: serial-agent
- **Goals:** 1, 2
- **Accept**:
  - `bats tests/adapter-common.bats tests/plugin-adapter.bats` reports 0 `not ok`
  - `ls adapters/claude-code/output/agents/*.md | wc -l` = 8
  - `jq '.agents | length' .claude-plugin/plugin.json` = 8
  - `claude plugin validate . --strict` passes (when the `claude` CLI is present)
- **Test**: `tests/adapter-common.bats::@test "agent-meta pins model and effort for every agent per the routing table"`, `tests/adapter-common.bats::@test "live agent-meta emits effort lines and the two variant files with overridden name/effort"`, `tests/plugin-adapter.bats::@test "plugin.json agents array includes generated variant files"` (guard; already green after Phase 1)
- **Edge cases**: none new; the variant-collision guard from Phase 1 runs on the live metadata during generate
- **Regression-case**: tests/adapter-common.bats::@test "agent-meta pins model and effort for every agent per the routing table"

- [ ] **Step 1: Apply the tests patch**

  ```bash
  P=docs/plans/2026-09-23-model-effort-routing-token-report-patches
  git hash-object "$P/p6-tests.patch"
  # expect: a88ec4544bfd9480f0eca52c56041fbbbe9895a0
  git apply --check "$P/p6-tests.patch" && git apply "$P/p6-tests.patch" && echo applied
  # expect: applied
  ```

- [ ] **Step 2: Red**

  ```bash
  bats tests/adapter-common.bats tests/plugin-adapter.bats 2>&1 | grep '^not ok' | sed 's/^not ok [0-9]* //'
  # expect:
  # agent-meta pins model and effort for every agent per the routing table
  # live agent-meta emits effort lines and the two variant files with overridden name/effort
  ```

- [ ] **Step 3: Apply the code patch** — makes text edits to `agent-meta.json`, preserving the existing inline-array formatting:
  - adds `effort` after each `model`
  - adds the `variants` object on engineer and reviewer
  - planner `opus` → `fable`
  - dispatcher, qa and uat `sonnet` → `opus`

  ```bash
  git hash-object "$P/p6-code.patch"
  # expect: ed50d481441213d433ee365fca2cc655c0582cf2
  git apply --check "$P/p6-code.patch" && git apply "$P/p6-code.patch" && echo applied
  # expect: applied
  jq -r 'to_entries[] | select(.value | type == "object" and has("name")) | "\(.key) \(.value.model) \(.value.effort)"' adapters/claude-code/agent-meta.json
  # expect:
  # planner fable high
  # dispatcher opus high
  # engineer opus xhigh
  # qa opus medium
  # uat opus medium
  # reviewer opus xhigh
  ```

- [ ] **Step 4: Regenerate both Claude Code targets**

  ```bash
  bin/rdf generate claude-code 2>&1 | grep -o 'generated 8 agent files (2 variants)'
  # expect: generated 8 agent files (2 variants)
  bin/rdf generate claude-plugin 2>&1 | grep -o 'plugin.json version: [0-9.]* (8 agents)'
  # expect: plugin.json version: 3.7.0 (8 agents)
  grep -h '^\(name\|model\|effort\):' adapters/claude-code/output/agents/engineer-focused.md adapters/claude-code/output/agents/reviewer-challenge.md
  # expect:
  # name: rdf-engineer-focused
  # model: opus
  # effort: medium
  # name: rdf-reviewer-challenge
  # model: opus
  # effort: high
  git status --porcelain adapters/claude-plugin/output .claude-plugin/plugin.json | wc -l
  # expect: 9
  ```

- [ ] **Step 5: Green + validation**

  ```bash
  bats tests/adapter-common.bats tests/plugin-adapter.bats tests/deploy.bats 2>&1 | grep -c '^not ok'
  # expect: 0
  bin/rdf doctor --scope catalogs 2>&1 | grep -o 'agent routing valid (6 agents, 2 variants)'
  # expect: agent routing valid (6 agents, 2 variants)
  bin/rdf doctor --scope sync 2>&1 | grep -o 'agent count matches (6 + 2 variants)'
  # expect: agent count matches (6 + 2 variants)
  command -v claude >/dev/null && claude plugin validate . --strict 2>&1 | tail -1
  # expect: ✔ Validation passed   (prints nothing when the claude CLI is absent)
  ```

- [ ] **Step 6: Commit**

  ```bash
  git add adapters/claude-code/agent-meta.json tests/adapter-common.bats tests/plugin-adapter.bats .claude-plugin/plugin.json adapters/claude-plugin/output/agents/dispatcher.md adapters/claude-plugin/output/agents/engineer.md adapters/claude-plugin/output/agents/planner.md adapters/claude-plugin/output/agents/qa.md adapters/claude-plugin/output/agents/reviewer.md adapters/claude-plugin/output/agents/uat.md adapters/claude-plugin/output/agents/engineer-focused.md adapters/claude-plugin/output/agents/reviewer-challenge.md
  git commit -F - <<'EOF'
  Routing: opus/fable model + effort per role; engineer-focused and reviewer-challenge variants

  [Change] agent-meta.json: planner fable/high; dispatcher opus/high; engineer and reviewer opus/xhigh; qa and uat opus/medium (dispatcher, qa, uat were sonnet)
  [New] variants rdf-engineer-focused (medium) and rdf-reviewer-challenge (high) emitted from the base canonical bodies
  [Change] regenerated claude-plugin output and plugin.json (8 agents)
  EOF
  git log --oneline -1
  # expect: <hash> Routing: opus/fable model + effort per role; engineer-focused and reviewer-challenge variants
  ```

---

### Phase 7: canonical routing text — dispatch by agent name, Fable advisory, tokens in `/r-save`

Replaces every `model: "sonnet"` routing directive with agent-name routing, adds the focused→base escalation and the non-blocking Fable advisory, and updates handoffs. It also teaches `/r-save` to record the tokens summary and `/r-start` to show the cost. Regenerates both targets.

**Files:**
- Modify: `canonical/agents/dispatcher.md` (agent routing + escalation)
- Modify: `canonical/commands/r-spec.md` (Model section, challenge agent, handoff)
- Modify: `canonical/commands/r-plan.md` (Model section, challenge agent, handoff)
- Modify: `canonical/commands/r-review.md` (agent routing)
- Modify: `canonical/commands/r-sync.md` (effort illustration, variants never imported)
- Modify: `canonical/commands/r-save.md` (tokens field + capture snippet)
- Modify: `canonical/commands/r-start.md` (cost segment)
- Modify: `tests/governance-contracts.bats` (routing contracts)
- Modify: `adapters/claude-plugin/output/agents/dispatcher.md` (regenerated)
- Modify: `adapters/claude-plugin/output/skills/r-spec/SKILL.md` (regenerated)
- Modify: `adapters/claude-plugin/output/skills/r-plan/SKILL.md` (regenerated)
- Modify: `adapters/claude-plugin/output/skills/r-review/SKILL.md` (regenerated)
- Modify: `adapters/claude-plugin/output/skills/r-sync/SKILL.md` (regenerated)
- Modify: `adapters/claude-plugin/output/skills/r-save/SKILL.md` (regenerated)
- Modify: `adapters/claude-plugin/output/skills/r-start/SKILL.md` (regenerated)

- **Mode**: serial-agent
- **Goals:** 5, 6, 9
- **Accept**:
  - `grep -rnE 'model: ?"sonnet"' canonical/agents canonical/commands | wc -l` = 0
  - `bats tests/governance-contracts.bats` reports 0 `not ok`
  - `bin/rdf doctor --scope doc-truth` shows 0 FAIL
  - `bin/rdf doctor --scope content-drift` shows 0 FAIL after regeneration
- **Test**: all RED tests listed in Step 2 (named `tests/governance-contracts.bats` tests)
- **Edge cases**: emergency edit to a variant (r-sync text: never import, edit the base agent); `CLAUDE_CODE_SESSION_ID` unset → `/r-save` records `null`
- **Regression-case**: tests/governance-contracts.bats::@test "no canonical routing directive passes model: sonnet"

- [ ] **Step 1: Apply the tests patch**

  ```bash
  P=docs/plans/2026-09-23-model-effort-routing-token-report-patches
  git hash-object "$P/p7-tests.patch"
  # expect: f75d40e453f1ee3dc8df0466582a940e22b56ba9
  git apply --check "$P/p7-tests.patch" && git apply "$P/p7-tests.patch" && echo applied
  # expect: applied
  ```

- [ ] **Step 2: Red**

  ```bash
  bats tests/governance-contracts.bats 2>&1 | grep '^not ok' | sed 's/^not ok [0-9]* //'
  # expect:
  # no canonical routing directive passes model: sonnet
  # dispatcher routes focused phases to rdf-engineer-focused and escalates failures to rdf-engineer
  # challenge reviews dispatch rdf-reviewer-challenge
  # r-spec and r-plan carry the non-blocking Fable advisory
  # r-spec handoff keeps /r-plan in the same session
  # r-plan handoff names the Opus build session
  # r-sync never offers generated variant agents for import
  # r-save session-log entry records a tokens summary or null
  # r-start Last line renders session cost when present
  ```

- [ ] **Step 3: Apply the code patch** (exact text replacements per spec §5.9)

  ```bash
  git hash-object "$P/p7-code.patch"
  # expect: e0c4d924c45d8fde63c32a2aefc2982c9affe03c
  git apply --check "$P/p7-code.patch" && git apply "$P/p7-code.patch" && echo applied
  # expect: applied
  grep -rnE 'model: ?"sonnet"' canonical/agents canonical/commands | wc -l
  # expect: 0
  ```

- [ ] **Step 4: Regenerate both targets and verify**

  ```bash
  bin/rdf generate claude-code >/dev/null 2>&1 && bin/rdf generate claude-plugin >/dev/null 2>&1 && echo regenerated
  # expect: regenerated
  git status --porcelain adapters/claude-plugin/output .claude-plugin/plugin.json | wc -l
  # expect: 7
  bats tests/governance-contracts.bats tests/plugin-adapter.bats tests/agent-skills.bats 2>&1 | grep -c '^not ok'
  # expect: 0
  bin/rdf doctor --scope doc-truth 2>&1 | grep -c '\[FAIL\]'
  # expect: 0
  bin/rdf doctor --scope content-drift 2>&1 | grep -c '\[FAIL\]'
  # expect: 0
  command -v claude >/dev/null && claude plugin validate adapters/claude-plugin/output/skills --strict 2>&1 | tail -1
  # expect: ✔ Validation passed   (prints nothing when the claude CLI is absent)
  ```

- [ ] **Step 5: Commit**

  ```bash
  git add canonical/agents/dispatcher.md canonical/commands/r-spec.md canonical/commands/r-plan.md canonical/commands/r-review.md canonical/commands/r-sync.md canonical/commands/r-save.md canonical/commands/r-start.md tests/governance-contracts.bats adapters/claude-plugin/output/agents/dispatcher.md adapters/claude-plugin/output/skills/r-spec/SKILL.md adapters/claude-plugin/output/skills/r-plan/SKILL.md adapters/claude-plugin/output/skills/r-review/SKILL.md adapters/claude-plugin/output/skills/r-sync/SKILL.md adapters/claude-plugin/output/skills/r-save/SKILL.md adapters/claude-plugin/output/skills/r-start/SKILL.md
  git commit -F - <<'EOF'
  Canonical routing: dispatch by agent name, Fable advisory for spec/plan, tokens in /r-save

  [Change] dispatcher routes scope:docs/focused to rdf-engineer-focused and escalates a failed focused phase to rdf-engineer; no per-invocation model for routing
  [Change] /r-spec, /r-plan, /r-review challenge reviews dispatch rdf-reviewer-challenge
  [New] /r-spec and /r-plan carry a non-blocking Claude Code advisory (claude --model fable --effort high); /r-plan hands off to an Opus build session
  [New] /r-save records a tokens summary (rdf-tokens.sh --session) as one compact session-log line; /r-start renders the session cost
  [Change] /r-sync never offers generated variant agents for import
  [Change] regenerated claude-plugin output
  EOF
  git log --oneline -1
  # expect: <hash> Canonical routing: dispatch by agent name, Fable advisory for spec/plan, tokens in /r-save
  ```

---

### Phase 8: docs, changelog, and end-to-end verification

Updates every document that states agent models, CLI commands or doctor scopes, adds the privacy note for `rdf tokens`, and consolidates the changelog under `## Unreleased`. Then it runs the spec §10b verification against HEAD and links the new helper into `~/.rdf/state/`.

**Files:**
- Modify: `README.md` (roster, CLI table, token usage, Add an Agent, trees)
- Modify: `RDF.md` (agent table, trees)
- Modify: `WORKFORCE.md` (diagram, headings, Model Summary)
- Modify: `docs/demo-walkthrough.md` (roster)
- Modify: `docs/multi-tool-parity.md` (§4b routing, deferred bullet)
- Modify: `docs/privacy.md` (local-only transcript read)
- Modify: `CHANGELOG` (Unreleased)
- Modify: `CHANGELOG.RELEASE` (Unreleased notes)

- **Mode**: serial-agent
- **Goals:** 11
- **Accept**:
  - `bin/rdf doctor` exits 0 (0 FAIL)
  - `make -C tests test` reports 0 `not ok`
  - `bin/rdf doctor --scope doc-truth` and `--scope doc-stats` show 0 FAIL
  - `grep -rniE '\bsonnet\b' README.md RDF.md WORKFORCE.md docs/demo-walkthrough.md | grep -v 'fans out to Sonnet\|`sonnet`'` is empty
- **Test**: full suite `make -C tests test`; `tests/doc-truth.bats::@test` suite unchanged and green; spec §10b commands (Step 3)
- **Edge cases**: checkout install needs `rdf deploy claude-code` once to link `rdf-tokens.sh` (Step 4, and stated in the CHANGELOG)
- **Regression-case**: N/A — docs — documentation and changelog only; code behavior is covered by the Phase 1-7 regression cases

- [ ] **Step 1: Apply the docs + changelog patch**

  ```bash
  P=docs/plans/2026-09-23-model-effort-routing-token-report-patches
  git hash-object "$P/p8-code.patch"
  # expect: 84d182bd08e359552f2d20c24889bee25c5d8127
  git apply --check "$P/p8-code.patch" && git apply "$P/p8-code.patch" && echo applied
  # expect: applied
  head -3 CHANGELOG
  # expect:
  # # RDF Changelog
  #
  # ## Unreleased
  ```

- [ ] **Step 2: Doc-truth and stale-wording sweep**

  ```bash
  bin/rdf doctor --scope doc-truth 2>&1 | grep -c '\[FAIL\]'
  # expect: 0
  bin/rdf doctor --scope doc-stats 2>&1 | grep -c '\[FAIL\]'
  # expect: 0
  bin/rdf doctor --scope readme 2>&1 | grep -c '\[FAIL\]'
  # expect: 0
  grep -rniE '\bsonnet\b' README.md RDF.md WORKFORCE.md docs/demo-walkthrough.md | grep -v 'fans out to Sonnet' | grep -vc '`sonnet`'
  # expect: 0
  ```

- [ ] **Step 3: Spec §10b end-to-end verification against HEAD**

  ```bash
  jq -r 'to_entries[]|select(.value|type=="object" and has("name"))|"\(.key) \(.value.model) \(.value.effort)"' adapters/claude-code/agent-meta.json | paste -sd' ' -
  # expect: planner fable high dispatcher opus high engineer opus xhigh qa opus medium uat opus medium reviewer opus xhigh
  ls adapters/claude-code/output/agents/*.md | wc -l
  # expect: 8
  grep -rnE 'model: ?"sonnet"' canonical/agents canonical/commands | wc -l
  # expect: 0
  grep -l 'claude --model fable --effort high' canonical/commands/r-spec.md canonical/commands/r-plan.md | wc -l
  # expect: 2
  bin/rdf tokens --transcripts tests/fixtures/tokens/proj --since 2026-09-01 --json | jq -c '[.api_turns, .cost_usd, .unpriced_models]'
  # expect: [6,0.3981,["claude-mystery-9"]]
  RDF_CLAUDE_PROJECTS=tests/fixtures/tokens bash state/rdf-tokens.sh --session s1 --summary | jq -c '[.api_turns, .cost_usd]'
  # expect: [6,0.4001]
  bin/rdf doctor --scope harness --json | jq -r '.checks[].category' | sort -u
  # expect: harness
  make -C tests test 2>&1 | tee /tmp/test-rdf-context-economy.log | grep -c '^not ok'
  # expect: 0
  shellcheck -S error --exclude=SC1090,SC1091 bin/rdf lib/*.sh lib/cmd/*.sh state/*.sh adapters/*/adapter.sh && echo sc-ok
  # expect: sc-ok
  bin/rdf doctor >/dev/null; echo "rc=$?"
  # expect: rc=0
  ```

- [ ] **Step 4: Link the new helper for this checkout and confirm**

  `rdf deploy claude-code` symlinks `state/*.sh` per file into `~/.rdf/state/`, and it re-points every existing deployed link (`~/.claude/**`, `~/.rdf/state/*`) at the checkout that runs it. From the main checkout that changes nothing but the new link. From a worktree it would point the operator's live links at a temporary path that is deleted after merge. So the step runs only in the main checkout; in a worktree it prints a deferral, and the controller runs it from the main checkout after merge.

  ```bash
  if [ "$(git rev-parse --git-dir)" = "$(git rev-parse --git-common-dir)" ]; then bin/rdf deploy claude-code >/dev/null 2>&1; test -L ~/.rdf/state/rdf-tokens.sh && echo linked; else echo "worktree: deploy deferred to the main checkout"; fi
  # expect: linked   (a worktree prints "worktree: deploy deferred to the main checkout")
  bin/rdf doctor --scope state-helpers 2>&1 | grep -o 'all state helpers current'
  # expect: all state helpers current
  ```

- [ ] **Step 5: Commit**

  ```bash
  git add README.md RDF.md WORKFORCE.md docs/demo-walkthrough.md docs/multi-tool-parity.md docs/privacy.md CHANGELOG CHANGELOG.RELEASE
  git commit -F - <<'EOF'
  Docs + changelog: model/effort routing, rdf tokens, harness scope

  [Change] README, RDF.md, WORKFORCE.md, demo walkthrough: agent roster shows model + effort per role and the two variants; README CLI table adds rdf tokens and lists all 15 doctor checks
  [New] README token-usage paragraph and Add-an-Agent effort/variants schema; multi-tool-parity §4b routing note; privacy note that rdf tokens reads local transcripts only
  [Change] CHANGELOG and CHANGELOG.RELEASE consolidated under Unreleased (version assigned at ship)
  EOF
  git log --oneline -9
  # expect: 8 phase commits on top of the plan commit (plan + patches + spec amendment), newest first
  ```

---
