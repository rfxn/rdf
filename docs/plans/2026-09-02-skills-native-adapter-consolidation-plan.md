# Implementation Plan: Skills-Native Adapter Consolidation (+ doc truth, + platform-triage gate)

**Goal:** Emit `skills/<name>/SKILL.md` through one shared emitter for the Claude Code, Claude plugin, and agent-skills surfaces; retire the bespoke Codex adapter in favour of the composite; make AGENTS.md project-scoped and `rdf init --tools` real; delete dead catalogs; add a `doc-truth` doctor scope and fix the current doc drift; land the spike's contract-hardening and per-minor platform-triage gate.

**Architecture:** `lib/adapter_common.sh` holds parameterised `adp_*` emitters (no adapter globals); adapters shrink to orchestration plus their genuinely different parts. Consumers (deploy/doctor/sync/overhead/context-audit) first gain skills support alongside commands (Phase 2), then the emitters cut over and the commands branches are removed fail-closed (Phase 3). Codex/Antigravity are served by the agent-skills + agents-md composite (Phase 4). See spec §4.

**Tech Stack:** Bash 3.2+ floor (macOS CI leg), BATS (`make -C tests test`), jq, shellcheck, `claude plugin validate`.

**Spec:** docs/specs/2026-09-02-skills-native-adapter-consolidation-design.md (companion research: docs/specs/2026-09-02-platform-alignment-spike-design.md, D3/D4 consumed by Phase 7)

**Phases:** 8

**Plan Version:** 3.0.6

**Tier:** full

## RC Contract Evidence

| Caller | Helper | Contract | Evidence |
|--------|--------|----------|----------|
| `_deploy_claude_code` | `_deploy_symlink` | returns 1 + `_DEPLOY_SKIPPED++` only when the source is missing; a real non-symlink dest warns and `_DEPLOY_SKIPPED++` but still returns **0** (the branch ends in an assignment), so callers must not infer "linked" from rc — count the `_DEPLOY_OK` delta; replaces existing symlinks with `ln -snf`; `--force` backs up real dests | verified `lib/cmd/deploy.sh:58-117` |
| `cmd_deploy` | summary | exit 1 when `_DEPLOY_SKIPPED>0` (3.6.5) — a missing `output/skills` after Phase 3 therefore fails deploy loudly, which Phase 3 Step 1 relies on | verified `deploy.sh` summary block |
| `cc_generate_all`/`cpl_generate_all` | `rdf_require_agent_meta` | dies when an agent lacks meta (3.6.4) — `adp_emit_agents` must keep the warn-and-plain-copy branch only for the *library* contract test; adapters still call the preflight first | verified `adapters/claude-code/adapter.sh:305`, `claude-plugin/adapter.sh:265` |
| `_check_content_drift` | `rdf_strip_frontmatter` + `rdf_hash_stdin` | hash is over the canonical body; deployed file is stripped before hashing — unchanged for SKILL.md (frontmatter is leading `---` block) | verified `doctor.sh` `_hash_deployed_body` |
| `rdf sync` | `rdf_strip_frontmatter` | emits nothing for unclosed frontmatter → empty-body guard skips (3.6.4) — Phase 3 keeps the guard for SKILL.md | verified `lib/cmd/sync.sh:90-96` |
| `cpl_stamp_plugin_version` | jq | rewrites `.version` and `.agents`; Phase 3 extends with `.skills` and `del(.commands)` — CI diffs `.claude-plugin/plugin.json`, so the stamped file is committed in the same phase | verified `adapters/claude-plugin/adapter.sh:240-258`, `.github/workflows/ci.yml:104` |
| `_has_files` | `git ls-files` | sees tracked files only — untracked sources make `rdf init` detect `minimal` (found by the 5069a4c engineer); Phase 5 adds `--others --exclude-standard` | verified `lib/cmd/init.sh:44-52` |

## Conventions

**Shell:** bash 3.2-safe (no `${var,,}`, `mapfile -d`, `declare -A` globals); `command` prefix on coreutils in project source; `2>/dev/null` / `|| true` get a same-line justification on touched lines; `#!/usr/bin/env bash`; one-line function headers (`# name args — purpose`).

**Library boilerplate (`lib/adapter_common.sh`):**
```bash
#!/usr/bin/env bash
# lib/adapter_common.sh — shared adapter emitters (agents, skills, scripts, reference, staging)
# (C) 2026 R-fx Networks <proj@rfxn.com>
# GNU GPL v2
# Sourced by lib/cmd/generate.sh before any adapter — do not execute directly
```

**Filter convention:** every emitter takes `filter_fn` (a function name or `-`); bodies stream through `if [[ "$filter_fn" == "-" ]]; then command cat "$src"; else "$filter_fn" < "$src"; fi`. Never rewrite canonical on disk.

**Skill frontmatter (exact):** `---` / `name: <name>` / `description: >` / `  <trigger>` / `---` / empty line / body.

**Commit format (RDF):** free-form subject; body lines tagged `[New]`/`[Change]`/`[Fix]`/`[Remove]`; stage by name; no AI attribution.

**CHANGELOG:** Phases 1-7 do NOT touch `CHANGELOG`/`CHANGELOG.RELEASE`; Phase 8 consolidates both under the existing `## Unreleased` section (declared plan exception). Version stays 3.6.5 until `/r-ship` assigns the release number.

**Regeneration rule:** any phase touching `canonical/` runs `bin/rdf generate all` before commit and stages the tracked output trees (`adapters/claude-plugin/output/**`, `adapters/agents-md/output/AGENTS.md`, `.claude-plugin/plugin.json`). Untracked outputs (claude-code, gemini-cli, agent-skills) regenerate locally and are never staged. CI diffs the tracked trees after its own generate.

**Verification baseline per shell-touching phase:** `bash -n` + `shellcheck -S error --exclude=SC1090,SC1091` on every changed shell file; `make -C tests test 2>&1 | tee /tmp/test-rdf-P<N>.log | tail -3` → `not ok: 0`.

**CRITICAL:** never `git add -A`; never touch `adapters/gemini-cli/**`; never edit vendored `canonical/scripts/` (context-bar.sh, setup.sh, clone-conversation.sh, half-clone-conversation.sh, test-half-clone.sh, color-preview.sh, check-context.sh); never edit `canonical/scripts/state-bootstrap.sh`; keep `adapters/claude-code/hooks/hooks.json`, `agent-meta.json`, and `skill-meta.json` content unchanged.

## File Map

### New Files
| File | Lines | Purpose | Test File |
|------|-------|---------|-----------|
| `lib/adapter_common.sh` | ~230 | shared `adp_*` emitters | `tests/adapter-common.bats` |
| `tests/adapter-common.bats` | ~150 | library contracts + byte-identity fixtures | (self) |
| `tests/fixtures/adapter-common/agents-expected.tar` | 1 archive | 3.6.5 agents/scripts/reference emitter output captured in Phase 1 | `tests/adapter-common.bats` |
| `tests/doc-truth.bats` | ~120 | doc-truth scope | (self) |
| `docs/platform-triage.md` | ~60 | per-minor platform re-triage ledger (D4) | `tests/governance-contracts.bats` |
| `docs/context-bar.md` | moved from root | orphan doc relocated | `tests/doc-truth.bats` |

### Modified Files
| File | Changes | Test File |
|------|---------|-----------|
| `lib/rdf_common.sh` | `rdf_lite_commands`, `rdf_cc_dir_surfaces` | `tests/adapter-common.bats` |
| `lib/cmd/generate.sh` | source the lib; `codex` → composite; `agents-md --project-root`; usage | `tests/adapter.bats` |
| `adapters/claude-code/adapter.sh` | lib calls; skills emission; drop dead meta | `tests/adapter.bats`, `tests/rdf-lite.bats` |
| `adapters/claude-plugin/adapter.sh` | lib calls; skills emission; stamp `.skills` | `tests/plugin-adapter.bats` |
| `adapters/agent-skills/adapter.sh` | lib calls | `tests/agent-skills.bats` |
| `adapters/agents-md/adapter.sh` | project composer | `tests/agent-skills.bats` |
| `lib/cmd/deploy.sh` | skills links + prune + legacy removal; codex composite; `agents-md` target; usage | `tests/deploy.bats` |
| `lib/cmd/doctor.sh` | skills in content-drift/sync/install-mode; `doc-truth` scope | `tests/doctor.bats`, `tests/doc-truth.bats` |
| `lib/cmd/sync.sh` | skills reverse flow, fail-closed WARN | `tests/sync.bats` |
| `lib/cmd/init.sh` | `--tools` real; `_has_files` untracked fix | `tests/cmd-migrate-init.bats` |
| `state/rdf-overhead.sh` | resolver via `agents` symlink | `tests/overhead.bats` |
| `state/context-audit.sh` | skills inventory | `tests/state-injection.bats` |
| `.claude-plugin/plugin.json` | `skills` key, no `commands` (stamped) | `tests/plugin-adapter.bats` |
| `.gitignore` | drop `adapters/codex/output` | N/A (config) |
| `.github/workflows/ci.yml` | validate skills dir | N/A (CI) |
| `tests/Makefile` | register new bats files | `tests/governance-contracts.bats` (wiring contract) |
| `tests/adapter.bats` | skills paths; codex catalog test removed | (self) |
| `tests/plugin-adapter.bats` | skills paths, `skills` key | (self) |
| `tests/deploy.bats` | skills links, prune, legacy, codex composite | (self) |
| `tests/doctor.bats` | skills fixtures | (self) |
| `tests/sync.bats` | skills reverse flow | (self) |
| `tests/rdf-lite.bats` | lite by skill dir | (self) |
| `tests/overhead.bats` | agents-symlink resolver | (self) |
| `tests/agent-skills.bats` | shared emitter; composer | (self) |
| `tests/cmd-migrate-init.bats` | `--tools` matrix; untracked detection | (self) |
| `tests/state-injection.bats` | context-audit skills count | (self) |
| `tests/derfxn.bats` | `--tools` assertion flipped; consumer AGENTS.md no-rfxn | (self) |
| `tests/governance-contracts.bats` | D3 negation guards + structural contracts; D4 preflight contract | (self) |
| `canonical/commands/r-sync.md` | skills wording | `tests/derfxn.bats` (grep) |
| `canonical/commands/r-ship.md` | preflight 1d platform triage | `tests/governance-contracts.bats` |
| `canonical/reference/tiers.md` | line 41 full formula | `tests/governance-contracts.bats` |
| `README.md` | skills wording, adapter table, `--tools`, badges, docs table | `tests/doc-truth.bats`, `tests/derfxn.bats` |
| `RDF.md` | profile tree, adapter tree, skills wording, model table | `tests/doc-truth.bats` |
| `WORKFORCE.md` | dispatch-table truth (planner, r-start) | `tests/doc-truth.bats` |
| `CONTRIBUTING.md` | CI paragraph truthful | `tests/doc-truth.bats` |
| `ROADMAP.md` | item 4/5 status, D1/D2 follow-ons, "built-in 11" wording | N/A (docs) |
| `docs/index.md` | skills wording, counts | `tests/doc-truth.bats` |
| `docs/quickstart.md` | skills wording | N/A (docs) |
| `docs/multi-tool-parity.md` | parity matrix rows | N/A (docs) |
| `adapters/claude-plugin/output/**` | regenerated + committed (Phases 3, 7) | `tests/plugin-adapter.bats` |
| `adapters/agents-md/output/AGENTS.md` | regenerated + committed (Phase 4) | `tests/agent-skills.bats` |
| `CHANGELOG` | consolidated entries (Phase 8) | N/A (docs) |
| `CHANGELOG.RELEASE` | consolidated entries (Phase 8) | N/A (docs) |

### Deleted Files
| File | Reason |
|------|--------|
| `adapters/claude-code/command-meta-v3.json` | never read |
| `adapters/claude-code/command-map-v3.md` | 3.0 plan artifact |
| `adapters/codex/adapter.sh` | served by composite |
| `adapters/agents-md/sections.json` | replaced by composer |
| `context-bar.md` | moved to `docs/context-bar.md` |

## Phase Dependencies

- Phase 1: none
- Phase 2: [1]
- Phase 3: [2]
- Phase 4: [3]
- Phase 5: [4]
- Phase 6: [5]
- Phase 7: [6]
- Phase 8: [7]

(Strictly sequential: `deploy.sh`, `doctor.sh`, and several BATS files are touched by multiple phases; sequential ownership removes every shared-file conflict.)

---

### Phase 1: Shared adapter library (byte-identical extraction)

Create `lib/adapter_common.sh` and move the agent-frontmatter, agents loop, scripts loop, reference loop, sidecar, description, and staging code out of the three Claude-family adapters. Command emission stays local to each adapter in this phase so the output trees are byte-identical to 3.6.5.

**Files:**
- Create: `lib/adapter_common.sh`
- Create: `tests/adapter-common.bats`
- Create: `tests/fixtures/adapter-common/agents-expected.tar`
- Modify: `lib/rdf_common.sh`
- Modify: `lib/cmd/generate.sh`
- Modify: `adapters/claude-code/adapter.sh`
- Modify: `adapters/claude-plugin/adapter.sh`
- Modify: `adapters/agent-skills/adapter.sh`
- Modify: `tests/Makefile`

- **Goals:** 1
- **Mode**: serial-agent
- **Accept**: `bin/rdf generate claude-code && bin/rdf generate claude-plugin && bin/rdf generate agent-skills` produce trees whose `agents/`, `scripts/`, `reference/` (and `.agents/skills/`) contents are byte-identical to the pre-phase capture (`diff -r` empty); `grep -c '_cc_agent_frontmatter\|_cpl_agent_frontmatter\|cc_generate_scripts\|cpl_generate_scripts\|_sk_skill_description' adapters/*/adapter.sh` → 0 in the three adapters; `bash -n` + shellcheck clean; `make -C tests test` green.
- **Test**: `tests/adapter-common.bats::@test "adp_emit_agents output is byte-identical to the 3.6.5 emitter fixture"`, `::@test "adp_emit_agents plain-copies and warns when meta lacks the agent"`, `::@test "adp_stage_commit rotates .old and leaves no staging dirs"`, `::@test "adp_skill_description falls back meta → first line → RDF command:"`, `::@test "adp_copy_reference writes sidecars only when asked"`, `::@test "adp_emit_skills applies the filter to body and description"`, `::@test "no adapter except gemini defines output_old"`; existing `tests/adapter.bats`, `plugin-adapter.bats`, `agent-skills.bats` unchanged and green.
- **Edge cases**: spec 11b "skill-meta key without canonical file" (description helper returns fallback; caller decides) — covered by the description test.
- **Regression-case**: `tests/adapter-common.bats::@test "adp_emit_agents output is byte-identical to the 3.6.5 emitter fixture"` (created this phase)

- [x] **Step 1: Capture the baseline**

  Before any edit: `bin/rdf generate claude-code && bin/rdf generate claude-plugin && bin/rdf generate agent-skills`, then `tar -cf tests/fixtures/adapter-common/agents-expected.tar -C adapters/claude-code/output agents scripts reference -C ../../claude-plugin/output agents` (one archive, four dirs; keep it small — ~60 KB). This fixture is what the byte-identity test unpacks and diffs against.

- [x] **Step 2: Add the two lists to `lib/rdf_common.sh`**

  ```bash
  # rdf_lite_commands — lifecycle command basenames shipped by rdf-lite
  rdf_lite_commands() { printf '%s\n' r-spec r-plan r-build r-ship r-start r-save; }
  # rdf_cc_dir_surfaces — ~/.claude directory symlinks owned by rdf deploy (skills are per-entry)
  rdf_cc_dir_surfaces() { printf '%s\n' agents scripts governance reference; }
  ```

- [x] **Step 3: Write `lib/adapter_common.sh`**

  Functions per spec §5 (signatures verbatim): `adp_require_hash_tool`, `adp_write_hash_sidecar canonical_src dst`, `adp_agent_frontmatter meta agent` (rc 1 + warn when absent — same text as today), `adp_emit_agents src_dir dst_dir meta filter_fn sidecar`, `adp_skill_description name src meta`, `adp_emit_skills src_dir skills_root meta filter_fn sidecar names_fn ref_src` (written now, used by Phase 3; unit-tested here), `adp_names_all src_dir [meta]`, `adp_names_lite src_dir [meta]`, `adp_names_from_meta src_dir meta`, `adp_copy_scripts src dst`, `adp_copy_reference src dst sidecar`, `adp_stage_begin final_dir` (echoes `<final>.new`), `adp_stage_commit final_dir staging_dir`, `adp_count dir glob`. The plugin filter is applied to the *description* too: `adp_emit_skills` pipes the description through `filter_fn` when it is not `-`. Reference copy inside `adp_emit_skills` targets `<skills_root>/reference/` and its source is the `ref_src` parameter (`-` skips the copy).

- [x] **Step 4: Source the lib from `_generate_adapter`**

  In `lib/cmd/generate.sh` `_generate_adapter`, before sourcing the adapter: `# shellcheck disable=SC1090,SC1091` / `source "${RDF_LIBDIR}/adapter_common.sh"`.

- [x] **Step 5: Refactor the three adapters onto the lib (agents/scripts/reference/staging only)**

  claude-code: `cc_generate_agents` → `adp_emit_agents "${RDF_CANONICAL}/agents" "${_CC_OUTPUT_DIR}/agents" "$_CC_AGENT_META" - 1`; scripts/reference → `adp_copy_scripts` / `adp_copy_reference … 1`; `_cc_resolve_hash_cmd` → `adp_require_hash_tool`; `_cc_write_hash_sidecar` callers → `adp_write_hash_sidecar`; `cc_generate_all` uses `adp_stage_begin`/`adp_stage_commit`. Keep `cc_generate_commands` + `cc_generate_command_frontmatter` local for now but make the frontmatter call `adp_skill_description`. Delete `_CC_COMMAND_META`. claude-plugin: agents via `adp_emit_agents … "$meta" _cpl_rewrite_namespace_text 0`; scripts/reference via lib (sidecar 0); staging via lib; `cpl_generate_command_frontmatter` calls `adp_skill_description` then filters. agent-skills: `_sk_skill_description` → `adp_skill_description`; keep `sk_emit_skills` local this phase; staging via lib.

- [x] **Step 6: Tests + Makefile**

  Write `tests/adapter-common.bats` (seven tests above; the byte-identity test regenerates into a temp `RDF_ADAPTERS` copy, untars the fixture, `diff -r`). Register in `tests/Makefile`.

- [x] **Step 7: Verify**

  ```bash
  bash -n lib/adapter_common.sh adapters/claude-code/adapter.sh adapters/claude-plugin/adapter.sh adapters/agent-skills/adapter.sh lib/cmd/generate.sh lib/rdf_common.sh && shellcheck -S error --exclude=SC1090,SC1091 lib/adapter_common.sh adapters/*/adapter.sh lib/cmd/generate.sh lib/rdf_common.sh && echo LINT-OK
  # expect: LINT-OK
  bin/rdf generate all >/dev/null 2>&1; git status --porcelain adapters/claude-plugin/output adapters/agents-md/output .claude-plugin/plugin.json | wc -l
  # expect: 0   (tracked outputs byte-identical)
  make -C tests test 2>&1 | tee /tmp/test-rdf-P1.log | tail -3
  # expect: not ok: 0
  ```

- [x] **Step 8: Commit**

  `git add lib/adapter_common.sh lib/rdf_common.sh lib/cmd/generate.sh adapters/claude-code/adapter.sh adapters/claude-plugin/adapter.sh adapters/agent-skills/adapter.sh tests/adapter-common.bats tests/fixtures/adapter-common/agents-expected.tar tests/Makefile`
  Message: `Shared adapter library: one emitter for agents, scripts, reference, staging` / `[New] lib/adapter_common.sh — adp_* emitters; byte-identical to 3.6.5 output (fixture-tested)` / `[Change] claude-code, claude-plugin, agent-skills adapters call the library; dead _CC_COMMAND_META removed` / `[New] tests/adapter-common.bats (7 tests)`

---

### Phase 2: Consumers learn the skills layout (dual support, no emitter change)

Deploy, doctor, sync, the overhead resolver, and context-audit gain skills support while still handling the current `commands/` layout, so Phase 3's cut-over cannot leave a consumer silently no-oping.

**Files:**
- Modify: `lib/cmd/deploy.sh`
- Modify: `lib/cmd/doctor.sh`
- Modify: `lib/cmd/sync.sh`
- Modify: `state/rdf-overhead.sh`
- Modify: `state/context-audit.sh`
- Modify: `tests/deploy.bats`
- Modify: `tests/doctor.bats`
- Modify: `tests/sync.bats`
- Modify: `tests/overhead.bats`
- Modify: `tests/state-injection.bats`

- **Goals:** 3, 4
- **Mode**: serial-agent
- **Accept**: with a fixture output tree containing `skills/<n>/SKILL.md`, `bin/rdf deploy claude-code` creates `~/.claude/skills/<n>` symlinks and prunes RDF-owned stale ones; with a tree containing only `commands/`, behaviour is unchanged (existing tests green); `rdf doctor --scope content-drift` checks `skills/*/SKILL.md` + sidecars when present; `rdf sync` pulls `skills/*/SKILL.md` back to `canonical/commands/<n>.md`; `state/rdf-overhead.sh` resolves the checkout via `readlink ~/.claude/agents`; `context-audit.sh` emits `.skills.deployed.count` counting both layouts (existing JSON shape `state/context-audit.sh:411-412`).
- **Test**: `tests/deploy.bats::@test "deploy links each skill as its own symlink"`, `::@test "deploy prunes an RDF-owned skill symlink whose target vanished"`, `::@test "deploy skips a user-owned real skill dir and exits 1"`, `::@test "deploy creates ~/.claude/skills as a real directory, never a symlink"`, `::@test "RDF_TARGET applies to skills"`; `tests/doctor.bats::@test "content-drift FAILs on a corrupted SKILL.md"`, `::@test "sync-health checks per-skill links"`, `::@test "install-mode detects symlink deploy via skills"`; `tests/sync.bats::@test "sync pulls an edited SKILL.md back to canonical/commands"`; `tests/overhead.bats::@test "deployed copy resolves the real checkout via the agents symlink"`; `tests/state-injection.bats::@test "context-audit counts skills"`.
- **Edge cases**: 11b "user-owned real skill dir" (skip + exit 1), "RDF_TARGET set", "two symlink levels" (`rdf_canonical_path` compare), "canonical command removed after deploy" (prune).
- **Regression-case**: `tests/deploy.bats::@test "deploy links each skill as its own symlink"` (created this phase)

- [x] **Step 1: deploy.sh — `_deploy_skill_links` + wire-in**

  ```bash
  # _deploy_skill_links output_dir dest_base dry_run force — per-skill symlinks + prune of RDF-owned stale links
  _deploy_skill_links() {
      local output_dir="$1" dest_base="$2" dry_run="$3" force="$4" d n linked=0 pruned=0 target
      [[ -d "${output_dir}/skills" ]] || return 0          # Phase 2: skills tree optional; Phase 3 makes it required
      if [[ -L "${dest_base}/skills" ]]; then rdf_warn "${dest_base}/skills is a symlink — refusing to manage per-skill links inside it"; _DEPLOY_SKIPPED=$((_DEPLOY_SKIPPED + 1)); return 1; fi
      [[ $dry_run -eq 1 ]] || command mkdir -p "${dest_base}/skills"
      for d in "${output_dir}/skills"/*/; do
          [[ -d "$d" ]] || continue; n="$(command basename "$d")"
          _deploy_symlink "${output_dir}/skills/${n}" "${dest_base}/skills/${n}" "$dry_run" "$force" && linked=$((linked + 1))
      done
      for d in "${dest_base}/skills"/*; do            # prune: RDF-owned link whose target is gone
          [[ -L "$d" ]] || continue; target="$(readlink "$d")"
          case "$target" in "${output_dir}/skills/"*) [[ -e "$target" ]] || { [[ $dry_run -eq 1 ]] || command rm -f "$d"; pruned=$((pruned + 1)); } ;; esac
      done
      rdf_log "skills: ${linked} linked, ${pruned} pruned (${dest_base}/skills/<name> -> ${output_dir}/skills/<name>)"
  }
  ```
  `_deploy_claude_code`: replace the five explicit `_deploy_symlink` lines with a loop over `rdf_cc_dir_surfaces` **plus** (this phase only) `[[ -d "${output_dir}/commands" ]] && _deploy_symlink "${output_dir}/commands" "${dest_base}/commands" …`, then `_deploy_skill_links "$output_dir" "$dest_base" "$dry_run" "$force"`. Note: `_deploy_symlink`'s return value already counts OK/skipped — do not double count.

- [x] **Step 2: doctor.sh — content-drift, sync, install-mode**

  `_check_content_drift`: after the agents loop, add a skills loop: `for skill_file in "${output_dir}/skills"/*/SKILL.md` with sidecar `${skill_file}.rdf-hash`, message key `skills/<dir>`; keep the commands loop this phase (guard both loops with `[[ -d … ]]`). `_check_sync`: count `canonical/commands/*.md` against `skills/*/SKILL.md` when `output/skills` exists, else against `commands/*.md`; symlink-health loop iterates `rdf_cc_dir_surfaces` (+ `commands` when the output has it), then per-skill: every `output/skills/<n>` must have `~/.claude/skills/<n>` resolving to it (WARN per missing/wrong). `_check_install_mode`: `symlink_mode=1` if `-L "${base}/commands"` OR `-L "${base}/skills/r-start"` (any RDF-owned skill link).

- [x] **Step 3: sync.sh — skills loop**

  Add before the scripts loop: `if [[ -d "${output_dir}/skills" ]]; then for out_file in "${output_dir}/skills"/*/SKILL.md; do … n="$(command basename "$(command dirname "$out_file")")"; [[ "$n" == "reference" ]] && continue; canon_file="${RDF_CANONICAL}/commands/${n}.md"; (same strip / empty-body guard / compare / write as the commands loop) …; done; fi`. Extract the shared body-derivation into `_sync_body <file>` so the three loops call one helper (removes the duplicated strip block at `sync.sh:47-116`).

- [x] **Step 4: rdf-overhead.sh — resolver**

  Replace `readlink "${RDF_TARGET:-${HOME}/.claude}/commands"` with `…/agents`; keep `${_link%/adapters/*}`; the existing warning `rdf-overhead: deploy symlink absent — rules/lite figures may be inaccurate` becomes `rdf-overhead: no ~/.claude/agents deploy symlink — rules/lite figures may be inaccurate` (the overhead test greps for `agents`). (`agents` is a directory symlink today and after Phase 3.)

- [x] **Step 5: context-audit.sh — inventory**

  In the skills inventory section: count `find "$dir/skills" -mindepth 2 -maxdepth 2 -name SKILL.md` for the global and project dirs and add it to the existing `commands/*.md` count (both layouts). Keep the canonical count as is.

- [x] **Step 6: Tests**

  Extend `_make_deploy_skeleton` in `tests/deploy.bats` to also create `skills/x/SKILL.md` (keep `commands/x.md` this phase). Add the deploy/doctor/sync/overhead/state-injection tests listed above.

- [x] **Step 7: Verify**

  ```bash
  bash -n lib/cmd/deploy.sh lib/cmd/doctor.sh lib/cmd/sync.sh state/rdf-overhead.sh state/context-audit.sh && shellcheck -S error --exclude=SC1090,SC1091 lib/cmd/deploy.sh lib/cmd/doctor.sh lib/cmd/sync.sh state/rdf-overhead.sh state/context-audit.sh && echo LINT-OK
  # expect: LINT-OK
  make -C tests test 2>&1 | tee /tmp/test-rdf-P2.log | tail -3
  # expect: not ok: 0
  bin/rdf doctor | tail -1
  # expect: ... 0 FAIL
  ```

- [x] **Step 8: Commit**

  `git add lib/cmd/deploy.sh lib/cmd/doctor.sh lib/cmd/sync.sh state/rdf-overhead.sh state/context-audit.sh tests/deploy.bats tests/doctor.bats tests/sync.bats tests/overhead.bats tests/state-injection.bats`
  Message: `Consumers learn the skills layout: per-skill deploy links, doctor, sync, overhead, context-audit` / `[New] rdf deploy owns ~/.claude/skills/<name> symlinks with stale-link pruning` / `[Change] doctor content-drift/sync/install-mode and rdf sync handle skills/*/SKILL.md alongside commands/` / `[Change] overhead resolver follows the agents symlink; context-audit counts skills`

---

### Phase 3: Cut over to skills output (emitters, plugin manifest, legacy removal, docs)

Emit `skills/<name>/SKILL.md` from all three Claude-family adapters, stamp the plugin manifest, remove the `commands/` branches from consumers (fail-closed), prune the legacy `~/.claude/commands` symlink on deploy, delete the dead catalogs, and update the user-facing docs.

**Files:**
- Modify: `adapters/claude-code/adapter.sh`
- Modify: `adapters/claude-plugin/adapter.sh`
- Modify: `adapters/agent-skills/adapter.sh`
- Modify: `lib/cmd/deploy.sh`
- Modify: `lib/cmd/doctor.sh`
- Modify: `lib/cmd/sync.sh`
- Modify: `state/context-audit.sh`
- Modify: `.github/workflows/ci.yml`
- Modify: `.claude-plugin/plugin.json`
- Modify: `adapters/claude-plugin/output/**`
- Delete: `adapters/claude-code/command-meta-v3.json`
- Delete: `adapters/claude-code/command-map-v3.md`
- Modify: `canonical/commands/r-sync.md`
- Modify: `tests/adapter.bats`
- Modify: `tests/plugin-adapter.bats`
- Modify: `tests/agent-skills.bats`
- Modify: `tests/rdf-lite.bats`
- Modify: `tests/deploy.bats`
- Modify: `tests/doctor.bats`
- Modify: `tests/sync.bats`
- Modify: `tests/state-injection.bats`
- Modify: `tests/derfxn.bats`

- **Goals:** 2, 3, 4, 5
- **Mode**: serial-agent
- **Accept**: `bin/rdf generate claude-code` → `output/skills/` has 37 skill dirs + `reference/`, no `output/commands`; each `SKILL.md` stripped of frontmatter equals its canonical body; plugin output identical in shape without sidecars; `jq -r '.skills, (.commands // "absent")' .claude-plugin/plugin.json` → path, absent; `claude plugin validate . --strict` and `claude plugin validate adapters/claude-plugin/output/skills --strict` pass; `rdf deploy claude-code` on a fixture HOME whose `~/.claude/commands` symlinks into RDF output removes it and links 37 skills; `rdf sync --dry-run` with `output/skills` moved away prints `no skills tree`; lite generation emits exactly six skill dirs + reference. (The headless runtime probe is an advisory Step 6 line, not an Accept item — CI's two `claude plugin validate --strict` runs are the deterministic gate.)
- **Test**: `tests/adapter.bats::@test "generator writes skills/<n>/SKILL.md for every canonical command and no commands/"`, `::@test "SKILL.md body equals canonical body after frontmatter strip"`, `::@test "sidecar hash matches canonical for a skill"`; `tests/plugin-adapter.bats::@test "plugin skills carry /rdf: rewrite in body and description"`, `::@test "plugin.json has skills path, no commands key, and the path exists"`, `::@test "plugin tree has no .rdf-hash"`; `tests/rdf-lite.bats::@test "lite emits exactly the six lifecycle skills"`; `tests/agent-skills.bats::@test "agent-skills still emits only skill-meta keys"`; `tests/deploy.bats::@test "deploy removes a legacy commands symlink into RDF output"`, `::@test "deploy leaves a foreign ~/.claude/commands symlink alone"`, `::@test "deploy dies when output/skills is missing"`; `tests/sync.bats::@test "sync warns when output/skills is missing"`; `tests/doctor.bats::@test "content-drift WARNs when skills/ is absent"`, `::@test "sync-health WARNs on a lingering commands symlink into RDF output"`.
- **Edge cases**: 11b "commands is a real directory of user commands" (untouched + notice), "commands symlink points to a foreign tree" (untouched), "output/skills absent" (deploy dies; sync/doctor WARN), "--lite", "plugin install + symlink deploy on one machine" (advisory text updated to say skills), "macOS bash 3.2" (CI leg).
- **Regression-case**: `tests/adapter.bats::@test "generator writes skills/<n>/SKILL.md for every canonical command and no commands/"` (created this phase)

- [x] **Step 1: Emitters**

  claude-code: delete `cc_generate_commands`/`cc_generate_command_frontmatter`/`_cc_is_lite_command`; add `cc_generate_skills() { local names_fn=adp_names_all; [[ "$_CC_LITE" -eq 1 ]] && names_fn=adp_names_lite; adp_emit_skills "${RDF_CANONICAL}/commands" "${_CC_OUTPUT_DIR}/skills" "$_CC_SKILL_META" - 1 "$names_fn" "${RDF_CANONICAL}/reference"; }`; summary counts `skills` via `adp_count "${_CC_OUTPUT_DIR}/skills" SKILL.md` and logs "N skills". claude-plugin: delete `cpl_generate_commands`/`cpl_generate_command_frontmatter`; `cpl_generate_skills` = `adp_emit_skills … "$_CPL_SKILL_META" _cpl_rewrite_namespace_text 0 adp_names_all "${RDF_CANONICAL}/reference"`; `cpl_stamp_plugin_version` jq becomes `.version = $v | .agents = $agents | .skills = "./adapters/claude-plugin/output/skills" | del(.commands)`. agent-skills: delete `sk_emit_skills`; `sk_generate_all` calls `adp_emit_skills "${RDF_CANONICAL}/commands" "${stage}/.agents/skills" "$_SK_META" - 0 adp_names_from_meta "${RDF_CANONICAL}/reference"` (reference copy now inside the lib). Delete `command-meta-v3.json` and `command-map-v3.md` (`git rm`).

- [x] **Step 2: Consumers drop the commands branches (fail-closed)**

  deploy: remove the `commands` symlink line; `_deploy_skill_links` now dies `rdf_die "output/skills not found — run 'rdf generate claude-code' first"` when the tree is absent; add `_deploy_prune_legacy_commands dest_base output_dir dry_run` — if `-L "${dest_base}/commands"` and `"$(rdf_canonical_path "${dest_base}/commands")"` starts with `"$(rdf_canonical_path "${RDF_HOME}/adapters/claude-code/output")"` → `command rm -f` + `rdf_log "removed legacy commands symlink: … (skills supersede it)"`; real dir or foreign symlink → one `rdf_log` notice, no change. Update the plugin-install advisory to "duplicate skills as /r-* and /rdf:r-*". Usage: add "remove skills: `rm ~/.claude/skills/r-*`" line. doctor: remove commands loops; `content-drift` WARNs `no skills tree — run 'rdf generate claude-code'` when absent; `sync` count uses skills only, health loop = `rdf_cc_dir_surfaces` + per-skill, plus WARN when a `~/.claude/commands` symlink still resolves into RDF output; `install-mode` probes skills only. sync: remove the commands loop; WARN `no skills tree in <output_dir> — nothing to sync for commands` when absent. context-audit: skills only (keep the legacy count as a separate `legacy_commands` field so the number stays honest during transition).

- [x] **Step 3: CI + manifest + regen**

  `.github/workflows/ci.yml` plugin job: after `claude plugin validate . --strict` add `claude plugin validate adapters/claude-plugin/output/skills --strict`. Run `bin/rdf generate all`; `git rm -r adapters/claude-plugin/output/commands`; stage the new `adapters/claude-plugin/output/skills/**` and the stamped `.claude-plugin/plugin.json`.

- [x] **Step 4: Canonical doc**

  `canonical/commands/r-sync.md`: `~/.claude/commands/r-*.md` → `~/.claude/skills/r-*/SKILL.md`; "commands have no frontmatter" → "canonical stays frontmatter-free; SKILL.md carries name/description". (README/RDF.md/docs/CONTRIBUTING skills wording moves to Phase 6 with the other doc-truth edits — reviewer-suggested split.)

- [x] **Step 5: Tests**

  Rewrite the assertions listed in the seam map from `commands/x.md` to `skills/x/SKILL.md` across `adapter.bats`, `plugin-adapter.bats` (incl. the `for key in commands hooks` loop → `skills hooks` and a path-exists check), `agent-skills.bats:95-99` (CC frontmatter test now targets `skills/r-spec/SKILL.md`), `rdf-lite.bats`, `deploy.bats` (skeleton drops `commands/x.md`), `doctor.bats:93-105` fixture, `derfxn.bats` output-dir enumerations, and `state-injection.bats::"context-audit counts skills"` (Phase 2 asserted the combined count; now assert `.skills.deployed.count` = skills only and `.skills.legacy_commands` = 0 for a skills-only tree). Add the new tests listed in **Test**.

- [x] **Step 6: Verify**

  ```bash
  bin/rdf generate claude-code >/dev/null && ls adapters/claude-code/output/skills | wc -l && test ! -d adapters/claude-code/output/commands && echo no-commands
  # expect: 38 / no-commands
  source lib/rdf_common.sh; for d in adapters/claude-code/output/skills/r-*/; do n=$(basename "$d"); diff <(rdf_strip_frontmatter "$d/SKILL.md") canonical/commands/"$n".md >/dev/null || echo "DRIFT $n"; done
  # expect: (no output)
  jq -r '.skills, (.commands // "absent")' .claude-plugin/plugin.json
  # expect: ./adapters/claude-plugin/output/skills / absent
  claude plugin validate . --strict | tail -1 && claude plugin validate adapters/claude-plugin/output/skills --strict | tail -1
  # expect: ✔ Validation passed (twice)
  git status --porcelain adapters/claude-plugin/output .claude-plugin/plugin.json | grep -vc '^[AMDR]'
  # expect: 0   (everything staged; nothing untracked)
  make -C tests test 2>&1 | tee /tmp/test-rdf-P3.log | tail -3
  # expect: not ok: 0
  bin/rdf deploy claude-code | grep -E 'skills: 37 linked|removed legacy commands symlink'
  # expect: both lines (this machine has the 3.6.5 commands symlink)
  bin/rdf doctor | tail -1
  # expect: ... 0 FAIL
  # ADVISORY (does not gate Accept): headless runtime listing — skip when unauthenticated
  t=$(mktemp -d) && git -C "$t" init -q && mkdir -p "$t/.claude/skills" && for d in adapters/claude-code/output/skills/*/; do ln -s "$PWD/$d" "$t/.claude/skills/$(basename "$d")"; done; (cd "$t" && timeout 150 claude -p 'List the names of every custom skill available to you in this session as a JSON array of strings, nothing else.' --max-turns 1 --model claude-haiku-4-5-20251001 --output-format json 2>"$t/err" | jq -r '.result' | grep -cE '"r-start"'; grep -ciE 'not logged in|authenticat|api key' "$t/err" && echo SKIP-unauthenticated); rm -rf "$t"
  # expect: 1 (r-start listed; `reference` must not appear) — or SKIP-unauthenticated
  ```

- [x] **Step 7: Commit**

  `git add adapters/claude-code/adapter.sh adapters/claude-plugin/adapter.sh adapters/agent-skills/adapter.sh lib/cmd/deploy.sh lib/cmd/doctor.sh lib/cmd/sync.sh state/context-audit.sh .github/workflows/ci.yml .claude-plugin/plugin.json adapters/claude-plugin/output canonical/commands/r-sync.md tests/adapter.bats tests/plugin-adapter.bats tests/agent-skills.bats tests/rdf-lite.bats tests/deploy.bats tests/doctor.bats tests/sync.bats tests/state-injection.bats tests/derfxn.bats` (+ the two `git rm`s)
  Message: `Skills-native output: claude-code and plugin emit skills/<name>/SKILL.md` / `[Change] commands/ output retired; one shared skills emitter for cc, plugin, agent-skills` / `[Change] plugin.json declares skills; deploy removes the legacy ~/.claude/commands symlink it owns` / `[Change] doctor, sync, context-audit fail closed when the skills tree is absent` / `[Remove] command-meta-v3.json, command-map-v3.md (never read)`

---

### Phase 4: Codex via the composite; project-scoped AGENTS.md composer

Delete the bespoke Codex adapter, route `codex` to agent-skills + agents-md, and rewrite the agents-md adapter as a composer that builds AGENTS.md from the target repo's own CLAUDE.md.

**Files:**
- Delete: `adapters/codex/adapter.sh`
- Delete: `adapters/agents-md/sections.json`
- Modify: `adapters/agents-md/adapter.sh`
- Modify: `lib/cmd/generate.sh`
- Modify: `lib/cmd/deploy.sh`
- Modify: `.gitignore`
- Modify: `adapters/agents-md/output/AGENTS.md`
- Modify: `tests/adapter.bats`
- Modify: `tests/agent-skills.bats`
- Modify: `tests/deploy.bats`
- Modify: `tests/derfxn.bats`

- **Goals:** 6, 7
- **Mode**: serial-agent
- **Accept**: `test ! -e adapters/codex`; `bin/rdf generate codex` produces `adapters/agent-skills/output/.agents/skills/` and `adapters/agents-md/output/AGENTS.md`; `bin/rdf generate agents-md --project-root <tmp repo with CLAUDE.md>` writes an AGENTS.md whose body contains that CLAUDE.md verbatim, an `## Agent Skills` pointer, and the roster; `grep -c 'rfxn ecosystem\|CentOS 6' adapters/agents-md/output/AGENTS.md` → 0; `bin/rdf deploy codex --project-root P` symlinks `P/.agents/skills` and copy-skips `P/AGENTS.md`; `rdf generate all` exits 0 without codex.
- **Test**: `tests/adapter.bats::@test "generate codex emits .agents/skills and AGENTS.md via the composite"`, `::@test "adapters/codex does not exist"`; `tests/agent-skills.bats::@test "agents-md composes from a project CLAUDE.md"`, `::@test "agents-md falls back to governance index then stub"`, `::@test "self AGENTS.md regenerates byte-identical (tracked output)"`; `tests/deploy.bats::@test "deploy codex symlinks skills and copy-skips AGENTS.md"`, `::@test "deploy agents-md requires --project-root"`; `tests/derfxn.bats::@test "consumer AGENTS.md contains no rfxn identifiers"`.
- **Edge cases**: 11b "project has no CLAUDE.md and no governance index" (stub + WARN), "rdf generate all" (codex removed, exit 0), "AGENTS.md exists" (copy-skip on deploy).
- **Regression-case**: `tests/agent-skills.bats::@test "agents-md composes from a project CLAUDE.md"` (created this phase)

- [ ] **Step 1: Composer**

  Rewrite `adapters/agents-md/adapter.sh` per spec §5: `_amd_context_source root` (CLAUDE.md → `.rdf/governance/index.md` → empty), `amd_compose root dst` (header `# AGENTS.md — <basename root>` + generated-by line + context body + `## Agent Skills` paragraph + `## Agent Roster` via the retained `_amd_agent_roster` + 32 KiB warn), `amd_generate_all [root]` defaulting to `RDF_HOME` and writing `output/AGENTS.md` through `adp_stage_begin/commit`. `git rm adapters/agents-md/sections.json`.

- [ ] **Step 2: generate.sh / deploy.sh / .gitignore**

  generate: `codex)` and `antigravity)` both run `sk_generate_all` then `amd_generate_all`; `agents-md)` accepts `--project-root P` (parse before the target like `--deploy`) and passes it; `all)` drops the codex block; usage text lists `codex` as "composite (agent-skills + AGENTS.md)". deploy: `_deploy_codex` → `_deploy_agent_skills … "$project_root"` + `_deploy_agents_md` (copy-skip `adapters/agents-md/output/AGENTS.md` → `P/AGENTS.md`, die without `--project-root`); add `agents-md)` and `antigravity)` targets; usage updated. `.gitignore`: drop the `adapters/codex/output` line. `git rm adapters/codex/adapter.sh`; `command rm -rf adapters/codex`.

- [ ] **Step 3: Regenerate + tests**

  `bin/rdf generate all` and stage `adapters/agents-md/output/AGENTS.md`. Remove `tests/adapter.bats:558-609` (section comment, the `_generate_codex` helper that sources the deleted adapter, and the codex catalog test — single use, verified by grep) and add the tests listed above; `tests/derfxn.bats` gets the consumer-AGENTS.md no-rfxn test using a temp repo with a plain CLAUDE.md.

- [ ] **Step 4: Verify**

  ```bash
  test ! -e adapters/codex && echo codex-gone; bin/rdf generate all 2>&1 | tail -1
  # expect: codex-gone / all adapters generated successfully
  grep -c 'rfxn ecosystem\|CentOS 6' adapters/agents-md/output/AGENTS.md
  # expect: 0
  make -C tests test 2>&1 | tee /tmp/test-rdf-P4.log | tail -3
  # expect: not ok: 0
  ```

- [ ] **Step 5: Commit**

  `git add adapters/agents-md/adapter.sh adapters/agents-md/output/AGENTS.md lib/cmd/generate.sh lib/cmd/deploy.sh .gitignore tests/adapter.bats tests/agent-skills.bats tests/deploy.bats tests/derfxn.bats` (+ `git rm` of the two deleted files)
  Message: `Codex served by the composite; AGENTS.md composed from the project's own CLAUDE.md` / `[Remove] adapters/codex (empty governance section since 2026-03; stale o4-mini config)` / `[Change] rdf generate|deploy codex = agent-skills + agents-md; new agents-md/antigravity deploy targets` / `[New] agents-md composer (--project-root); sections.json retired; self AGENTS.md carries no rfxn/CentOS text`

---

### Phase 5: `rdf init --tools` made real; untracked-file profile detection

Implement the `--tools` value set on top of the Phase 4 targets and fix the first-run wart where `_has_files` ignores untracked sources.

**Files:**
- Modify: `lib/cmd/init.sh`
- Modify: `README.md`
- Modify: `tests/cmd-migrate-init.bats`
- Modify: `tests/derfxn.bats`

- **Goals:** 8
- **Mode**: serial-agent
- **Accept**: `bin/rdf init --tools cursor <repo>` exits 1 with `unknown --tools value: cursor (allowed: claude-code, agent-skills, agents-md, codex, antigravity)`; `--tools agent-skills,agents-md` writes `<repo>/.agents/skills` (symlink) and `<repo>/AGENTS.md`; `--tools codex` produces the same two; `--tools claude-code` is a no-op; `--dry-run --tools agents-md` prints a `would write AGENTS.md` line and writes nothing; a git repo whose only sources are untracked `app.py` + `requirements.txt` detects `python`.
- **Test**: `tests/cmd-migrate-init.bats::@test "init --tools unknown exits 1 with the allowed list"`, `::@test "init --tools agent-skills,agents-md writes both artifacts"`, `::@test "init --tools codex expands to the composite"`, `::@test "init --dry-run --tools prints would-write lines"`, `::@test "init detects profiles from untracked sources in a fresh git repo"`; `tests/derfxn.bats` assertion at `:145-146` flipped to `README documents the --tools value set`.
- **Edge cases**: 11b "rdf init --tools agents-md on a repo with AGENTS.md" (copy-skip + log), "rdf init --tools ''" (error).
- **Regression-case**: `tests/cmd-migrate-init.bats::@test "init --tools unknown exits 1 with the allowed list"` (created this phase)

- [ ] **Step 1: init.sh**

  `_init_validate_tools list` → splits on `,`, dies on empty token or token ∉ set, echoes the expanded newline list (codex/antigravity → agent-skills + agents-md, deduped). `_init_apply_tools path tools dry_run` runs after `_generate_companion_files`: for `agent-skills` source `lib/cmd/deploy.sh` and call `_deploy_agent_skills "$dry_run" 0 "$path"` (generate `agent-skills` first if `adapters/agent-skills/output` is missing); for `agents-md` source `lib/adapter_common.sh` + `adapters/agents-md/adapter.sh` and call `amd_compose "$path" "$path/AGENTS.md"` unless it exists (log skip). Usage line: `--tools LIST  claude-code (default), agent-skills, agents-md, codex, antigravity (comma-separated)`. `_has_files`: `git -C "$path" ls-files --cached --others --exclude-standard -- "$pattern"`.

- [ ] **Step 2: README + tests**

  README "rdf init" section documents `--tools`. Tests as listed; flip the derfxn assertion.

- [ ] **Step 3: Verify**

  ```bash
  t=$(mktemp -d) && git -C "$t" init -q && bin/rdf init --tools cursor "$t" 2>&1 | tail -1; echo "rc=$?"
  # expect: rdf: error: unknown --tools value: cursor (allowed: ...) / rc=1
  make -C tests test 2>&1 | tee /tmp/test-rdf-P5.log | tail -3
  # expect: not ok: 0
  ```

- [ ] **Step 4: Commit**

  `git add lib/cmd/init.sh README.md tests/cmd-migrate-init.bats tests/derfxn.bats`
  Message: `rdf init --tools is real; profile detection sees untracked sources` / `[New] --tools claude-code|agent-skills|agents-md|codex|antigravity (comma list); unknown values exit 1` / `[Fix] _has_files includes untracked, non-ignored files — a repo initialised before its first commit no longer detects as minimal`

---

### Phase 6: `doc-truth` doctor scope + live doc-truth fixes

Add the 14th doctor scope that mechanically checks profile/adapter counts, test wiring, WORKFORCE dispatch claims, and CONTRIBUTING CI claims; fix every current drift so the live repo passes.

**Files:**
- Modify: `lib/cmd/doctor.sh`
- Create: `tests/doc-truth.bats`
- Modify: `tests/Makefile`
- Modify: `README.md`
- Modify: `RDF.md`
- Modify: `WORKFORCE.md`
- Modify: `CONTRIBUTING.md`
- Modify: `ROADMAP.md`
- Modify: `docs/index.md`
- Modify: `docs/quickstart.md`
- Modify: `docs/multi-tool-parity.md`
- Modify: `canonical/reference/tiers.md`
- Create: `docs/context-bar.md`
- Delete: `context-bar.md`
- Modify: `adapters/claude-plugin/output/**`

- **Goals:** 9, 10
- **Mode**: serial-agent
- **Accept**: `bin/rdf doctor --scope doc-truth` → 0 FAIL on the live repo; each of the five claim classes has a fixture-driven FAIL test; README badge, `RDF.md` profile tree, `docs/index.md` agree with `profiles/` (14 dirs incl. lite; registry 13 + lite documented as unregistered) — pick one canonical definition: **profile count = registry entries** (13) and the doc-truth check also asserts every `profiles/*/governance-template.md` dir except `lite` is in the registry; `WORKFORCE.md` has no row claiming `r-start` dispatches anything and describes `planner` as inline/direct-dispatch; `CONTRIBUTING.md` CI paragraph lists exactly what `ci.yml` runs per OS; `tiers.md:41` reads `max(security_floor, min(scope_gate, tier_cap))`; `docs/context-bar.md` exists, root copy gone, README docs table links it; scope count in doctor usage 13 → 14.
- **Test**: `tests/doc-truth.bats::@test "FAILs when README badge profile count drifts"`, `::@test "FAILs when a profile dir is missing from registry.json"`, `::@test "FAILs when a tests/*.bats file is missing from the Makefile"`, `::@test "FAILs when WORKFORCE claims a dispatch the command body lacks"`, `::@test "WARNs when a command dispatches an agent WORKFORCE omits"`, `::@test "FAILs when CONTRIBUTING claims a CI step ci.yml lacks"`, `::@test "passes on the live repo"`, `::@test "context-bar.md lives under docs/ and is linked from README"`.
- **Edge cases**: none (doc checks).
- **Regression-case**: `tests/doc-truth.bats::@test "passes on the live repo"` (created this phase)

- [ ] **Step 1: `_check_doc_truth`**

  Implement per spec §13 table: WORKFORCE rows are read only between `^### Lifecycle Commands` and the next `^###`, must match the 4-column shape `^\| (r-[a-z-]+) \| /r-[a-z-]+ \| ([^|]*) \| [^|]+\|$`; a third cell of `--`, `—`, `none`, or empty claims nothing; token match `\brdf-${a}\b|\b${a}[[:space:]]+agent\b`; profile count from `jq '.profiles | length' profiles/registry.json` vs README `profiles-([0-9]+)` badge, `RDF.md` tree entries, `docs/index.md` `([0-9]+) profiles`; adapter count = `ls adapters/*/adapter.sh | wc -l` vs README `adapters-([0-9]+)` badge; test wiring = every `tests/*.bats` basename in `tests/Makefile`; CI claims = every backticked token in CONTRIBUTING's "CI runs" bullets present in `ci.yml`. Register the scope in the dispatch table and usage (14 scopes).

- [ ] **Step 2: Fix the live drift (and the skills wording deferred from Phase 3)**

  Skills wording: `README.md` data-flow diagram (`skills/<name>/SKILL.md`; the canonical `commands/ # 37 commands` note stays), adapter tree (5 adapters), plugin note; `RDF.md` adapter tree + `~/.claude/` wording; `docs/index.md`, `docs/quickstart.md`: "symlink deploy (skills)"; `docs/multi-tool-parity.md:18` Claude Code row → `.claude/skills/<name>/SKILL.md` (shared emitter with `.agents/skills/`); `CONTRIBUTING.md:20` wording. Then: README badges (`profiles-13`, `adapters-5`); `RDF.md` profile tree (+node, +rfxn-workspace, lite noted), adapter tree (5), model table (planner: inline in /r-spec and /r-plan, direct dispatch available); `WORKFORCE.md` dispatch table + prose (`/r-start` dispatches nothing; planner not dispatched by any command); `CONTRIBUTING.md` CI paragraph; `ROADMAP.md` "built-in 11" → "built-in profiles (see `profiles/registry.json`)"; `tiers.md:41`; `git mv context-bar.md docs/context-bar.md` + README docs-table row; `docs/index.md` counts. Regenerate outputs (canonical touched) and stage the tracked plugin tree.

- [ ] **Step 3: Verify**

  ```bash
  bin/rdf doctor --scope doc-truth | grep -c FAIL
  # expect: 0
  bin/rdf doctor --scope doc-stats | grep -c FAIL
  # expect: 0
  test -f docs/context-bar.md && ! test -f context-bar.md && grep -c 'docs/context-bar.md' README.md
  # expect: 1
  make -C tests test 2>&1 | tee /tmp/test-rdf-P6.log | tail -3
  # expect: not ok: 0
  ```

- [ ] **Step 4: Commit**

  `git add lib/cmd/doctor.sh tests/doc-truth.bats tests/Makefile README.md RDF.md WORKFORCE.md CONTRIBUTING.md ROADMAP.md docs/index.md docs/quickstart.md docs/multi-tool-parity.md canonical/reference/tiers.md docs/context-bar.md adapters/claude-plugin/output` (+ `git mv` already staged)
  Message: `doctor doc-truth scope: counts, test wiring, dispatch and CI claims checked from source` / `[New] rdf doctor --scope doc-truth (14th scope) + tests/doc-truth.bats` / `[Fix] README badges, RDF.md profile/adapter trees, WORKFORCE planner and r-start claims, CONTRIBUTING CI paragraph, tiers.md gate formula` / `[Change] docs describe the skills layout; context-bar.md relocated to docs/ and linked`

---

### Phase 7: Contract hardening (D3) and the per-minor platform-triage gate (D4)

Land the spike's two Go-now items: negation guards + structural assertions in the contract harness, and the `docs/platform-triage.md` ledger with a `/r-ship` preflight line that blocks a minor release without a current triage block.

**Files:**
- Modify: `tests/governance-contracts.bats`
- Create: `docs/platform-triage.md`
- Modify: `canonical/commands/r-ship.md`
- Modify: `README.md`
- Modify: `ROADMAP.md`
- Modify: `adapters/claude-plugin/output/**`

- **Goals:** 9
- **Mode**: serial-agent
- **Accept**: `tests/governance-contracts.bats` contains the two rewritten contracts from the spike (security-floor structural + r-review-answer negation guard) and every presence contract whose subject has a natural negation carries an absence regex (≥ 10 guards); a deliberate `Security floor no longer applies` line inserted into a temp copy of `dispatcher.md` makes the suite fail (demonstrated in the phase log, then reverted); `docs/platform-triage.md` has a dated `## 3.7 — 2026-09-02` block with the seven checklist rows and the Agent Teams first-case verdict (keep dispatcher) plus the two PO rulings from the spike's open questions (no dual `/r-build` path this minor; no `disable-model-invocation` on lifecycle skills — usage shows the pipeline model-invokes them); `canonical/commands/r-ship.md` Stage 1 gains `1d. Platform triage` (minor-only; `[x]` when the ledger's top block matches `MAJOR.MINOR`, `*(skipped)*` on patches, `> **Blocked**` otherwise); a contract asserts 1d exists; ROADMAP marks item 4 shipped-pending-release, item 5 first case done, and lists D1 (Workflow-backed build behind a flag) and D2 (local trigger-eval harness) as the next-minor candidates; README docs table links the ledger.
- **Test**: `tests/governance-contracts.bats::@test "tier cap never drops the security pass on scope:sensitive"`, `::@test "r-review-answer is advisory — does not block build/ship/merge"`, `::@test "r-ship preflight carries the platform-triage line (1d)"`, `::@test "platform-triage ledger top block names the current MAJOR.MINOR or the next minor"`.
- **Edge cases**: none.
- **Regression-case**: `tests/governance-contracts.bats::@test "tier cap never drops the security pass on scope:sensitive"` (created this phase)

- [ ] **Step 1: Contracts** — rewrite per spike §5 (copy the two tests verbatim; the indicator-list equality across reviewer/tiers/dispatcher; negation guards on the presence contracts for: NEEDS_CONTEXT gate, TDD_EVIDENCE, security floor, end-of-plan sentinel, consistency gate, r-review-answer advisory, canonical frontmatter-free, plan status writes, Clarify gate, tier caps).
- [ ] **Step 2: Ledger + preflight** — write `docs/platform-triage.md` (format per spike §6 option b; top block version `3.7`); add `### 1d. Platform Triage` to `r-ship.md` after 1c with the display rule; regenerate (canonical touched) and stage the plugin tree; README docs table + ROADMAP edits.
- [ ] **Step 3: Verify**

  ```bash
  cp canonical/agents/dispatcher.md /tmp/d.bak && printf '\nSecurity floor no longer applies.\n' >> canonical/agents/dispatcher.md && bats tests/governance-contracts.bats 2>&1 | grep -c '^not ok'; cp /tmp/d.bak canonical/agents/dispatcher.md
  # expect: ≥ 1   (harness now fails on the negation)
  make -C tests test 2>&1 | tee /tmp/test-rdf-P7.log | tail -3
  # expect: not ok: 0
  ```
- [ ] **Step 4: Commit** — `git add tests/governance-contracts.bats docs/platform-triage.md canonical/commands/r-ship.md README.md ROADMAP.md adapters/claude-plugin/output`; message `Contract harness hardening and per-minor platform-triage gate` / `[Change] governance contracts gain negation guards and structural assertions (formula, order, cross-file list equality)` / `[New] docs/platform-triage.md ledger; /r-ship preflight 1d blocks a minor without a current triage block` / `[Change] ROADMAP: item 4 built, item 5 first case ruled (keep dispatcher), D1/D2 queued`

---

### Phase 8: Changelog consolidation and end-to-end verification

Consolidate the release notes for Phases 1-7 under `## Unreleased`, regenerate and deploy locally, and run the full verification matrix.

**Files:**
- Modify: `CHANGELOG`
- Modify: `CHANGELOG.RELEASE`

- **Goals:** 1, 2, 3, 4, 5, 6, 7, 8, 9, 10
- **Mode**: serial-context
- **Accept**: both changelogs carry the consolidated entries in house style (no blank lines within a section, 6/9-space continuation, ≤ ~210-char lines); `bin/rdf generate all && bin/rdf deploy claude-code` on this machine exits 0 with `skills: 37 linked`; `bin/rdf doctor` → 0 FAIL (all 14 scopes); `make -C tests test` green; `git status --porcelain` empty after commit; every §10b command in the spec produces its expected output (run them all, paste results in the phase log).
- **Test**: spec §10b command list (all), `make -C tests test`, `bin/rdf doctor`.
- **Edge cases**: none.
- **Regression-case**: N/A — docs — changelog-only commit; behavior pinned by Phases 1-7 named tests.

- [x] **Step 1: Write entries** under `## Unreleased` in `CHANGELOG` (`-- New Features --`, `-- Bug Fixes --`, `-- Changes --`, `-- Removed --` as the file uses) and mirror into `CHANGELOG.RELEASE` under a matching heading (the ship stage renames `Unreleased` to the version).
- [x] **Step 2: Run the spec §10b block verbatim** and record output.
- [x] **Step 3: Commit** — `git add CHANGELOG CHANGELOG.RELEASE`; message `Changelog: skills-native adapters, doc-truth scope, platform-triage gate` / `[Change] CHANGELOG + CHANGELOG.RELEASE consolidated for the pending release`.

---
