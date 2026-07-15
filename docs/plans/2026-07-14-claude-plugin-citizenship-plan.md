# Implementation Plan: Claude Code Plugin Citizenship

**Goal:** Make RDF installable as a Claude Code plugin (`/plugin marketplace add rfxn/rdf` + `/plugin install rdf@rdf`) via a fifth adapter target, with namespace-rewritten commands, plugin-root hooks, manifest-based install-mode detection, and CI validation — while keeping symlink deploy byte-identical.

**Architecture:** New `adapters/claude-plugin/adapter.sh` (prefix `cpl_`) generating committed output; `plugin.json` component-path overrides point at it; repo declares itself a marketplace; `rdf generate` stamps the plugin version from `VERSION`.

**Tech Stack:** bash 4.1+ (`#!/usr/bin/env bash`, `set -euo pipefail` semantics via sourcing), jq (walk/1 defined inline for 1.5 compat), BATS via batsman, GitHub Actions.

**Spec:** docs/specs/2026-07-14-claude-plugin-citizenship-design.md

**Phases:** 7

**Plan Version:** 3.0.6

## Progress

All 7 phases complete (2026-07-14): P1 `b22dcdd` · P2 `6d275f4` ·
P3 `0636209` · P4 `ece8408` (validate --strict green) · P5 `1312b60` ·
P6 `b6f8453` (CI plugin job) · P7 `ef27860` · post-phase fixup
`df37308` (hermetic deploy test — CI-red at ef27860, remediated) ·
sentinel verdict: HEAD sound, 0 SHOULD-FIX.

## Conventions

**Adapter boilerplate** — `adapters/claude-plugin/adapter.sh` starts with:

```bash
#!/usr/bin/env bash
# adapters/claude-plugin/adapter.sh — Claude Code plugin adapter
# (C) 2026 R-fx Networks <proj@rfxn.com>
# GNU GPL v2
# Sourced by lib/cmd/generate.sh — do not execute directly

# Requires: RDF_HOME, RDF_CANONICAL, RDF_ADAPTERS, RDF_VERSION, jq
```

**Naming pattern** — functions `cpl_generate_<component>()`, private helpers `_cpl_<name>()`, dir vars `_CPL_ADAPTER_DIR` / `_CPL_OUTPUT_DIR` (mirrors `_CC_*`).

**Commit message format** — free-form summary line, body lines tagged `[New]` / `[Change]` / `[Fix]`; stage files explicitly by name; no CHANGELOG updates in these phases (batched at next version bump per repo pattern).

**Test harness pattern** — `tests/plugin-adapter.bats` follows `tests/adapter.bats`: hermetic temp `RDF_HOME`, generation run in a `bash -c` subprocess sourcing `lib/rdf_common.sh` then the adapter with `_CPL_OUTPUT_DIR` overridden after sourcing. Bare coreutils in `.bats` files (no `command` prefix — Docker containers, per workspace standards).

**CRITICAL:**
- Never `git add -A` — stage by name. Generated output is staged with `git add adapters/claude-plugin/output`. Note: unlike claude-code/gemini-cli/codex (outputs local-only via `.git/info/exclude`), plugin output MUST be tracked — consumers clone the repo and never run `rdf generate`. Verified: `git check-ignore adapters/claude-plugin/output/x` exits 1 (not ignored).
- `sed` expressions must stay POSIX BRE-portable (macOS CI runs the BATS suite) — no `\b`, no `\|` alternation outside bracket expressions.
- Every `2>/dev/null` / `|| true` needs a same-line justification comment.
- `bash -n` + `shellcheck` on every touched shell file before each commit.

## RC Contract Evidence

Helpers with return-code contracts used by new code (verified against source):

| Helper | File | Contract |
|--------|------|----------|
| `rdf_profile_includes(kind, name)` | lib/rdf_common.sh:175 | unconditional `return 0` stub (v3 dropped profile filtering; queued for removal in 2026-07-13 simplicity audit) — plugin adapter does NOT call it |
| `rdf_require_dir/file/bin` | lib/rdf_common.sh:98-121 | return 0 or `rdf_die` (exit) — never returns non-zero |
| `jq -e 'expr'` | external | exit 0 = truthy result, 1 = false/null, 2+ = parse/usage error; callers treat non-zero as "not detected" |
| `_add_result(cat, status, msg)` | lib/cmd/doctor.sh:47 | always returns 0; appends `"cat|status|msg"` to `_RESULTS` array |
| `rdf_hash_stdin` | lib/rdf_common.sh:77 | 0 on success; NOT used by plugin adapter (no sidecars) |

## File Map

### New Files
| File | Lines | Purpose | Test File |
|------|-------|---------|-----------|
| `adapters/claude-plugin/adapter.sh` | ~200 | `cpl_*` generation functions | `tests/plugin-adapter.bats` |
| `adapters/claude-plugin/output/**` | 56 files (generated) | committed plugin components | CI drift check (N/A BATS — generated) |
| `.claude-plugin/marketplace.json` | 14 | repo-as-marketplace | `tests/plugin-adapter.bats` |
| `tests/plugin-adapter.bats` | ~230 | adapter + detection + guard tests | self |
| `tests/fixtures/canonical/commands/r-example-extra.md` | 8 | prefix-collision rewrite fixture | consumed by plugin-adapter.bats |
| `tests/fixtures/canonical/commands/r-caller.md` | 14 | cross-ref rewrite fixture | consumed by plugin-adapter.bats |
| `tests/fixtures/canonical/agents/caller.md` | 8 | agent-body rewrite fixture | consumed by plugin-adapter.bats |

### Modified Files
| File | Changes | Test File |
|------|---------|-----------|
| `lib/cmd/generate.sh` | `claude-plugin` case + usage + `all` loop | `tests/plugin-adapter.bats` |
| `.claude-plugin/plugin.json` | component paths; version becomes stamped | `tests/plugin-adapter.bats` (version-sync guard) |
| `lib/cmd/doctor.sh` | `_check_install_mode()` + wiring | `tests/plugin-adapter.bats` |
| `lib/cmd/deploy.sh` | plugin-presence warning | `tests/plugin-adapter.bats` |
| `.github/workflows/ci.yml` | `plugin` job | N/A (CI config — validated by the job itself running) |
| `README.md` | plugin install path | N/A (docs) |
| `docs/quickstart.md` | plugin install option | N/A (docs) |
| `ROADMAP.md` | check off shipped items | N/A (docs) |

### Deleted Files
| File | Reason |
|------|--------|
| — | none |

## Phase Dependencies

- Phase 1: none
- Phase 2: [1]
- Phase 3: [2]
- Phase 4: [3]
- Phase 5: [1]
- Phase 6: [4]
- Phase 7: [4, 6]

(Phases 2 and 3 depend serially because they extend the same two files
as Phase 1: `adapters/claude-plugin/adapter.sh` and
`tests/plugin-adapter.bats`. Phase 5's lib changes are independent of
the adapter, but its BATS tests append to `tests/plugin-adapter.bats` —
created in Phase 1 — so it depends on [1]; it can still run in parallel
with Phases 2-4 only if the build resolves the shared-file conflict,
which /r-build's file-ownership check will serialize automatically.
Phase 7 depends on Phase 6 because it checks off the ROADMAP's
"validate --strict in CI" box — untrue until the CI job lands.)

---

### Phase 1: Plugin adapter core — commands generation with namespace rewrite

Creates the fifth adapter with the `/r-X` → `/rdf:r-X` rewrite engine and wires the `claude-plugin` target into `rdf generate`. Agents/scripts/hooks arrive in Phases 2-3; `cpl_generate_all` starts with commands only and grows.

**Files:**
- Create: `adapters/claude-plugin/adapter.sh` (test: `tests/plugin-adapter.bats`)
- Create: `tests/plugin-adapter.bats`
- Create: `tests/fixtures/canonical/commands/r-caller.md`, `tests/fixtures/canonical/commands/r-example-extra.md`
- Modify: `lib/cmd/generate.sh` (new target case, usage line, `all` loop)
- Modify: `tests/Makefile` (add plugin-adapter.bats to explicit test + lint file lists — discovered during execution: the Makefile does not glob)

- **Mode**: serial-agent
- **Accept**: `_generate_plugin` BATS harness produces `output/commands/` where (a) `r-caller.md` contains `/rdf:r-example` and `/rdf:r-example-extra`, (b) path-like `canonical/commands/r-example.md` is unrewritten, (c) `bin/rdf generate claude-plugin` on the real repo exits 0 and emits 37 files
- **Test**: `tests/plugin-adapter.bats` — @test "plugin generator writes commands under output dir", @test "plugin commands rewrite /r-X cross-refs to /rdf:r-X", @test "rewrite does not touch path-like r- strings", @test "rewrite handles prefix-colliding command names", @test "generate claude-plugin target is wired into cmd_generate"
- **Edge cases**: spec §11b "Cross-ref inside a path" (test c), "`/r-util-mem-compact` vs shorter prefix names" (test d), "Future 38th command" (counts derived from `ls`, never hardcoded)
- **Regression-case**: tests/plugin-adapter.bats::@test "plugin commands rewrite /r-X cross-refs to /rdf:r-X" (file created in this phase)

- [ ] **Step 1: Create fixture `tests/fixtures/canonical/commands/r-caller.md`**

  ```markdown
  You are running the /r-caller command. This is a test fixture.

  RDF_TEST_MARKER_r_caller

  Cross-references for rewrite tests:
  - Run `/r-example` to do the thing.
  - Then run /r-example-extra for the longer-named variant.
  - Pipeline: (/r-example) hands off via |/r-example| table syntax.
  - Path that must NOT rewrite: canonical/commands/r-example.md
  - Another path: tests/fixtures/canonical/commands/r-example.md
  /r-example at line start must rewrite too.
  ```

- [ ] **Step 2: Create fixture `tests/fixtures/canonical/commands/r-example-extra.md`**

  ```markdown
  You are running the /r-example-extra command. This is a test fixture.

  RDF_TEST_MARKER_r_example_extra

  Exists so the rewrite engine has a name that prefix-collides with
  r-example — longest-first ordering must rewrite /r-example-extra
  atomically, never as /rdf:r-example + "-extra".
  ```

- [ ] **Step 3: Create `adapters/claude-plugin/adapter.sh`**

  Complete file content:

  ```bash
  #!/usr/bin/env bash
  # adapters/claude-plugin/adapter.sh — Claude Code plugin adapter
  # (C) 2026 R-fx Networks <proj@rfxn.com>
  # GNU GPL v2
  # Sourced by lib/cmd/generate.sh — do not execute directly

  # Requires: RDF_HOME, RDF_CANONICAL, RDF_ADAPTERS, RDF_VERSION, jq

  _CPL_ADAPTER_DIR="${RDF_ADAPTERS}/claude-plugin"
  _CPL_OUTPUT_DIR="${_CPL_ADAPTER_DIR}/output"

  # Rewrite /r-NAME cross-references to /rdf:r-NAME in a command body.
  # Plugin commands are always namespaced by the loader; unrewritten
  # references would point at commands that do not exist in plugin installs.
  # Boundary rules: leading context is line start or one of space/tab,
  # backtick, (, |, ", ', *; trailing boundary is EOL or any char outside
  # [a-z-]. Names are applied longest-first so /r-example-extra rewrites
  # before /r-example can partially match. POSIX BRE only (macOS CI).
  # Args: $1 = src file, $2 = dst file
  _cpl_rewrite_namespace() {
      local src="$1"
      local dst="$2"
      local sed_args=()
      local name
      while IFS= read -r name; do
          [[ -z "$name" ]] && continue
          sed_args+=(-e "s#^/${name}\$#/rdf:${name}#")
          sed_args+=(-e "s#^/${name}\([^a-z-]\)#/rdf:${name}\1#")
          sed_args+=(-e "s#\([[:space:]\`(|\"'*]\)/${name}\$#\1/rdf:${name}#")
          sed_args+=(-e "s#\([[:space:]\`(|\"'*]\)/${name}\([^a-z-]\)#\1/rdf:${name}\2#g")
      done < <(_cpl_command_names_longest_first)
      sed "${sed_args[@]}" "$src" > "$dst"
  }

  # Emit canonical command basenames (no .md), longest name first.
  _cpl_command_names_longest_first() {
      local f b
      for f in "${RDF_CANONICAL}/commands"/*.md; do
          [[ -f "$f" ]] || continue
          b="$(basename "$f" .md)"
          printf '%d %s\n' "${#b}" "$b"
      done | sort -rn | cut -d' ' -f2-
  }

  # Generate plugin command files: canonical/commands/*.md -> output/commands/
  # with namespace rewrite. No .rdf-hash sidecars — strict plugin validation
  # rejects non-component files in the commands dir.
  cpl_generate_commands() {
      local src_dir="${RDF_CANONICAL}/commands"
      local dst_dir="${_CPL_OUTPUT_DIR}/commands"
      local count=0

      command mkdir -p "$dst_dir"

      for src_file in "${src_dir}"/*.md; do
          [[ -f "$src_file" ]] || continue
          local basename_f
          basename_f="$(basename "$src_file")"
          _cpl_rewrite_namespace "$src_file" "${dst_dir}/${basename_f}"
          count=$((count + 1))
      done
      rdf_log "generated ${count} command files (namespace-rewritten)"
  }

  # Full plugin generation pipeline (grows in later phases)
  cpl_generate_all() {
      rdf_log "generating Claude Plugin adapter output..."
      rdf_require_dir "$RDF_CANONICAL" "canonical directory"
      rdf_require_bin jq

      local _output_final="$_CPL_OUTPUT_DIR"
      local _output_new="${_CPL_OUTPUT_DIR}.new"
      local _output_old="${_CPL_OUTPUT_DIR}.old"

      # Build into staging directory, then atomic swap (cc adapter pattern)
      command rm -rf "$_output_new"
      command mkdir -p "$_output_new"
      _CPL_OUTPUT_DIR="$_output_new"

      cpl_generate_commands

      _CPL_OUTPUT_DIR="$_output_final"
      command rm -rf "$_output_old"
      if [[ -d "$_output_final" ]]; then
          command mv "$_output_final" "$_output_old"
      fi
      command mv "$_output_new" "$_output_final"
      command rm -rf "$_output_old"

      local command_count
      command_count="$(find "${_CPL_OUTPUT_DIR}/commands" -name '*.md' 2>/dev/null | wc -l)"  # dir may not exist on partial generation

      rdf_log "plugin generation complete: ${command_count} commands"
  }
  ```

  > Self-correction note: the sed delimiter is `#`, NOT `|` — the leading-
  > context bracket expression contains a literal `|` (table-cell refs),
  > which would terminate a `|`-delimited `s` expression mid-pattern.
  > Also note `\$` inside double quotes emits a literal `$` anchor, and
  > `\1`/`\2` backrefs pass through double quotes unmodified.

- [ ] **Step 4: Wire target into `lib/cmd/generate.sh`**

  4a. In `_generate_usage()` heredoc, after the line
  `  claude-code    Generate Claude Code adapter output`, insert:

  ```
    claude-plugin  Generate Claude Code plugin output (marketplace install)
  ```

  4b. In `cmd_generate()`, after the complete `claude-code)` case block
  (ends with the first `;;`), insert:

  ```bash
          claude-plugin)
              _generate_adapter "claude-plugin/adapter.sh" "cpl_generate_all"
              if [[ $deploy_after -eq 1 ]]; then
                  rdf_warn "--deploy not applicable to claude-plugin — install via /plugin marketplace add"
              fi
              ;;
  ```

  4c. In the `all)` case, after the Claude Code block
  (`_generate_adapter "claude-code/adapter.sh" ...` + its `fi`), insert:

  ```bash
              # Claude Plugin
              if [[ -f "${RDF_ADAPTERS}/claude-plugin/adapter.sh" ]]; then
                  _generate_adapter "claude-plugin/adapter.sh" "cpl_generate_all" || failed=$((failed + 1))
              fi
  ```

- [ ] **Step 5: Create `tests/plugin-adapter.bats`** with header, `_generate_plugin` helper, setup/teardown, and the 5 Phase-1 tests:

  ```bash
  #!/usr/bin/env bats
  # tests/plugin-adapter.bats — BATS tests for the RDF claude-plugin adapter
  # (C) 2026 R-fx Networks <proj@rfxn.com>
  # GNU GPL v2
  #
  # Hermetic: fresh temp RDF home + temp output dir per test. Harness
  # pattern mirrors tests/adapter.bats.
  #
  # shellcheck disable=SC2154,SC2164,SC1090,SC1091

  RDF_SRC="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  export RDF_SRC

  # Usage: _generate_plugin <test_home> <output_dir>
  _generate_plugin() {
      local test_home="$1"
      local output_dir="$2"
      bash -c '
          set -euo pipefail
          rdf_src="$1"
          test_home="$2"
          output_dir="$3"
          RDF_HOME="$test_home"
          RDF_LIBDIR="${rdf_src}/lib"
          RDF_VERSION="0.0.0-test"
          source "${rdf_src}/lib/rdf_common.sh"
          rdf_init
          rdf_profile_init
          _CPL_ADAPTER_DIR="${RDF_ADAPTERS}/claude-plugin"
          _CPL_OUTPUT_DIR="$output_dir"
          source "${rdf_src}/adapters/claude-plugin/adapter.sh"
          _CPL_OUTPUT_DIR="$output_dir"
          rdf_require_dir "$RDF_CANONICAL" "canonical directory"
          rdf_require_bin jq
          cpl_generate_commands
      ' -- "$RDF_SRC" "$test_home" "$output_dir"
  }

  setup() {
      TEST_HOME="$(mktemp -d)"
      TEST_OUT="$(mktemp -d)"

      mkdir -p \
          "${TEST_HOME}/canonical/commands" \
          "${TEST_HOME}/canonical/agents" \
          "${TEST_HOME}/canonical/scripts" \
          "${TEST_HOME}/adapters/claude-plugin" \
          "${TEST_HOME}/adapters/claude-code/hooks" \
          "${TEST_HOME}/.claude-plugin" \
          "${TEST_HOME}/profiles/core" \
          "${TEST_HOME}/state"

      cp "${RDF_SRC}/tests/fixtures/canonical/commands/r-example.md" \
          "${TEST_HOME}/canonical/commands/r-example.md"
      cp "${RDF_SRC}/tests/fixtures/canonical/commands/r-example-extra.md" \
          "${TEST_HOME}/canonical/commands/r-example-extra.md"
      cp "${RDF_SRC}/tests/fixtures/canonical/commands/r-caller.md" \
          "${TEST_HOME}/canonical/commands/r-caller.md"
      cp "${RDF_SRC}/tests/fixtures/canonical/agents/example.md" \
          "${TEST_HOME}/canonical/agents/example.md"

      echo "0.0.0-test" > "${TEST_HOME}/VERSION"
      touch "${TEST_HOME}/.rdf-profiles"

      export _TEST_HOME="$TEST_HOME"
      export _TEST_OUT="$TEST_OUT"
  }

  teardown() {
      rm -rf "${_TEST_HOME}" "${_TEST_OUT}" 2>/dev/null || true # ignore errors on cleanup
  }

  @test "plugin generator writes commands under output dir" {
      _generate_plugin "${_TEST_HOME}" "${_TEST_OUT}"
      [ -d "${_TEST_OUT}/commands" ]
      [ -f "${_TEST_OUT}/commands/r-caller.md" ]
      [ -f "${_TEST_OUT}/commands/r-example.md" ]
      [ -f "${_TEST_OUT}/commands/r-example-extra.md" ]
  }

  @test "plugin commands rewrite /r-X cross-refs to /rdf:r-X" {
      _generate_plugin "${_TEST_HOME}" "${_TEST_OUT}"
      grep -q '`/rdf:r-example`' "${_TEST_OUT}/commands/r-caller.md"
      grep -q '^/rdf:r-example at line start' "${_TEST_OUT}/commands/r-caller.md"
      grep -q '(/rdf:r-example)' "${_TEST_OUT}/commands/r-caller.md"
      grep -q '|/rdf:r-example|' "${_TEST_OUT}/commands/r-caller.md"
  }

  @test "rewrite does not touch path-like r- strings" {
      _generate_plugin "${_TEST_HOME}" "${_TEST_OUT}"
      grep -q 'canonical/commands/r-example\.md' "${_TEST_OUT}/commands/r-caller.md"
      run grep 'canonical/commands/rdf:' "${_TEST_OUT}/commands/r-caller.md"
      [ "$status" -ne 0 ]
  }

  @test "rewrite handles prefix-colliding command names" {
      _generate_plugin "${_TEST_HOME}" "${_TEST_OUT}"
      # longer name rewritten atomically
      grep -q 'run /rdf:r-example-extra for' "${_TEST_OUT}/commands/r-caller.md"
      # no leftover un-namespaced occurrence of the longer name
      run grep ' /r-example-extra' "${_TEST_OUT}/commands/r-caller.md"
      [ "$status" -ne 0 ]
  }

  @test "generate claude-plugin target is wired into cmd_generate" {
      grep -q 'claude-plugin)' "${RDF_SRC}/lib/cmd/generate.sh"
      grep -q 'cpl_generate_all' "${RDF_SRC}/lib/cmd/generate.sh"
      grep -q 'claude-plugin' <(bash "${RDF_SRC}/bin/rdf" generate help)
  }
  ```

- [ ] **Step 6: Lint + test**

  ```bash
  bash -n adapters/claude-plugin/adapter.sh lib/cmd/generate.sh
  # expect: exit 0, no output
  shellcheck adapters/claude-plugin/adapter.sh lib/cmd/generate.sh
  # expect: exit 0 (no new findings; SC2004/SC2001 pre-existing in other files only)
  make -C tests test 2>&1 | tee /tmp/test-rdf-P1-debian12.log | grep -c '^not ok'
  # expect: 0
  ```

- [ ] **Step 7: Real-repo smoke**

  ```bash
  bin/rdf generate claude-plugin && ls adapters/claude-plugin/output/commands/*.md | wc -l
  # expect: 37
  git checkout -- adapters/ 2>/dev/null; git clean -fd adapters/claude-plugin/ # discard smoke output — committed output lands in Phase 4
  ```

- [ ] **Step 8: Commit**

  ```bash
  git add adapters/claude-plugin/adapter.sh lib/cmd/generate.sh tests/plugin-adapter.bats \
      tests/fixtures/canonical/commands/r-caller.md tests/fixtures/canonical/commands/r-example-extra.md
  git commit -m "Add claude-plugin adapter core — namespace-rewritten command generation

  [New] adapters/claude-plugin/adapter.sh — cpl_generate_commands with
        boundary-guarded, longest-first /r-X -> /rdf:r-X rewrite (plugin
        commands are always loader-namespaced); staging + atomic swap
  [New] tests/plugin-adapter.bats — hermetic harness + 5 rewrite/wiring tests
  [Change] generate.sh: claude-plugin target case, usage entry, all-loop"
  ```

---

### Phase 2: Agents and scripts generation

Extends the adapter with sidecar-free agent generation (frontmatter from the cc `agent-meta.json`, bodies namespace-rewritten — 14 `/r-X` refs across 5 of 6 real personas would otherwise instruct plugin users to run nonexistent commands) and script copying.

**Files:**
- Create: `tests/fixtures/canonical/agents/caller.md` (agent-body rewrite fixture)
- Modify: `adapters/claude-plugin/adapter.sh` (two new functions + `cpl_generate_all` additions)
- Modify: `tests/plugin-adapter.bats` (harness gains agents/scripts, +4 tests)

- **Mode**: serial-agent
- **Accept**: temp-output run yields `agents/example.md` starting with `---` frontmatter and NO `.rdf-hash` files anywhere in output; `agents/caller.md` body contains `/rdf:r-example`; `scripts/` contains executable copies
- **Test**: `tests/plugin-adapter.bats` — @test "plugin agents carry frontmatter", @test "plugin agents rewrite /r-X cross-refs in bodies", @test "plugin output contains no .rdf-hash sidecars", @test "plugin scripts are copied executable"
- **Edge cases**: none from spec §11b (sidecar exclusion and agent-body rewrite are Goal-2 properties, tested here)
- **Regression-case**: tests/plugin-adapter.bats::@test "plugin output contains no .rdf-hash sidecars" (test added in this phase; file created in Phase 1 of this plan)

- [ ] **Step 1: Add `cpl_generate_agents()` to `adapters/claude-plugin/adapter.sh`** (after `cpl_generate_commands`)

  ```bash
  # Generate plugin agent files with CC YAML frontmatter, no hash sidecars.
  # Reuses the cc adapter's agent-meta.json as the single metadata source.
  cpl_generate_agents() {
      local src_dir="${RDF_CANONICAL}/agents"
      local dst_dir="${_CPL_OUTPUT_DIR}/agents"
      local meta="${RDF_ADAPTERS}/claude-code/agent-meta.json"
      local count=0

      rdf_require_file "$meta" "agent-meta.json"
      command mkdir -p "$dst_dir"

      for src_file in "${src_dir}"/*.md; do
          [[ -f "$src_file" ]] || continue
          local basename_f
          basename_f="$(basename "$src_file" .md)"
          local dst_file="${dst_dir}/${basename_f}.md"

          # Body gets the same /r-X -> /rdf:r-X rewrite as commands —
          # agent personas reference pipeline commands 14 times today.
          if _cpl_agent_frontmatter "$basename_f" "$meta" > "${dst_file}.tmp" 2>/dev/null; then  # agents without metadata fall through to plain copy
              echo "" >> "${dst_file}.tmp"
              _cpl_rewrite_namespace "$src_file" "${dst_file}.body"
              command cat "${dst_file}.body" >> "${dst_file}.tmp"
              command rm -f "${dst_file}.body"
              command mv "${dst_file}.tmp" "$dst_file"
          else
              _cpl_rewrite_namespace "$src_file" "$dst_file"
              command rm -f "${dst_file}.tmp"
          fi
          count=$((count + 1))
      done
      rdf_log "generated ${count} agent files"
  }

  # YAML frontmatter from agent-meta.json (cc-compatible schema).
  # Args: $1 = agent basename, $2 = agent-meta.json path
  _cpl_agent_frontmatter() {
      local agent="$1"
      local meta="$2"
      local name desc model tools_json disallowed_json

      if ! jq -e --arg a "$agent" '.[$a]' "$meta" >/dev/null 2>&1; then  # missing entry = signal caller to plain-copy
          rdf_warn "no metadata for agent: $agent — copying without frontmatter"
          return 1
      fi

      name="$(jq -r --arg a "$agent" '.[$a].name' "$meta")"
      desc="$(jq -r --arg a "$agent" '.[$a].description' "$meta")"
      model="$(jq -r --arg a "$agent" '.[$a].model' "$meta")"
      tools_json="$(jq -c --arg a "$agent" '.[$a].tools // []' "$meta")"
      disallowed_json="$(jq -c --arg a "$agent" '.[$a].disallowedTools // []' "$meta")"

      echo "---"
      echo "name: ${name}"
      echo "description: >"
      echo "  ${desc}"
      if [[ "$tools_json" != "[]" ]]; then
          echo "tools:"
          jq -r '.[]' <<< "$tools_json" | while IFS= read -r tool; do
              echo "  - ${tool}"
          done
      fi
      if [[ "$disallowed_json" != "[]" ]]; then
          echo "disallowedTools:"
          jq -r '.[]' <<< "$disallowed_json" | while IFS= read -r tool; do
              echo "  - ${tool}"
          done
      fi
      echo "model: ${model}"
      echo "---"
  }
  ```

  > Self-correction note: frontmatter logic is intentionally duplicated
  > from `_cc_agent_frontmatter` rather than cross-sourced — adapters
  > never source each other (spec §4 Dependency Rules). The meta file IS
  > shared (data, not code).

- [ ] **Step 2: Add `cpl_generate_scripts()`** (after the agent functions)

  ```bash
  # Copy canonical scripts (hook targets) — executable, unconditional.
  # No rdf_profile_includes call: it is a dead return-0 stub queued for
  # removal (2026-07-13 simplicity audit) — don't build new code on it.
  cpl_generate_scripts() {
      local src_dir="${RDF_CANONICAL}/scripts"
      local dst_dir="${_CPL_OUTPUT_DIR}/scripts"
      local count=0

      command mkdir -p "$dst_dir"

      for src_file in "${src_dir}"/*.sh; do
          [[ -f "$src_file" ]] || continue
          local basename_f
          basename_f="$(basename "$src_file")"
          command cp "$src_file" "${dst_dir}/${basename_f}"
          command chmod +x "${dst_dir}/${basename_f}"
          count=$((count + 1))
      done
      rdf_log "generated ${count} script files"
  }
  ```

- [ ] **Step 3: Extend `cpl_generate_all()`** — add after `cpl_generate_commands` line:

  ```bash
      cpl_generate_agents
      cpl_generate_scripts
  ```

  and extend the completion log to report agent/script counts (mirror cc lines 229-234, using `_CPL_OUTPUT_DIR`).

- [ ] **Step 4: Create fixture `tests/fixtures/canonical/agents/caller.md`**

  ```markdown
  You are a test fixture agent for plugin adapter BATS tests.

  RDF_TEST_MARKER_agent_caller

  When your work is done, hand off by running /r-example — this
  reference must be namespace-rewritten in plugin output.
  Path that must NOT rewrite: canonical/commands/r-example.md
  ```

- [ ] **Step 5: Extend BATS harness + 4 tests** — in `_generate_plugin`'s subprocess, after `cpl_generate_commands` add `cpl_generate_agents` and `cpl_generate_scripts`; in `setup()` copy the new agent fixture, write an agent-meta fixture covering BOTH agents, and add one fixture script:

  ```bash
      cp "${RDF_SRC}/tests/fixtures/canonical/agents/caller.md" \
          "${TEST_HOME}/canonical/agents/caller.md"
      cat > "${TEST_HOME}/adapters/claude-code/agent-meta.json" <<'META'
  {
    "example": {
      "name": "rdf-example",
      "description": "Test fixture agent for adapter BATS tests.",
      "tools": ["Bash", "Read"],
      "disallowedTools": [],
      "model": "sonnet"
    },
    "caller": {
      "name": "rdf-caller",
      "description": "Fixture agent with /r- cross-references.",
      "tools": ["Read"],
      "disallowedTools": [],
      "model": "sonnet"
    }
  }
  META
      printf '#!/usr/bin/env bash\necho fixture\n' > "${TEST_HOME}/canonical/scripts/fixture.sh"
  ```

  New tests:

  ```bash
  @test "plugin agents carry frontmatter" {
      _generate_plugin "${_TEST_HOME}" "${_TEST_OUT}"
      head -1 "${_TEST_OUT}/agents/example.md" | grep -q -- '---'
      grep -q '^name: rdf-example$' "${_TEST_OUT}/agents/example.md"
  }

  @test "plugin agents rewrite /r-X cross-refs in bodies" {
      _generate_plugin "${_TEST_HOME}" "${_TEST_OUT}"
      grep -q 'running /rdf:r-example — this' "${_TEST_OUT}/agents/caller.md"
      grep -q 'canonical/commands/r-example\.md' "${_TEST_OUT}/agents/caller.md"
  }

  @test "plugin output contains no .rdf-hash sidecars" {
      _generate_plugin "${_TEST_HOME}" "${_TEST_OUT}"
      run find "${_TEST_OUT}" -name '*.rdf-hash'
      [ -z "$output" ]
  }

  @test "plugin scripts are copied executable" {
      _generate_plugin "${_TEST_HOME}" "${_TEST_OUT}"
      [ -x "${_TEST_OUT}/scripts/fixture.sh" ]
  }
  ```

- [ ] **Step 6: Lint + test**

  ```bash
  bash -n adapters/claude-plugin/adapter.sh && shellcheck adapters/claude-plugin/adapter.sh
  # expect: exit 0
  make -C tests test 2>&1 | tee /tmp/test-rdf-P2-debian12.log | grep -c '^not ok'
  # expect: 0
  ```

- [ ] **Step 7: Commit**

  ```bash
  git add adapters/claude-plugin/adapter.sh tests/plugin-adapter.bats \
      tests/fixtures/canonical/agents/caller.md
  git commit -m "Plugin adapter: agents and scripts generation

  [New] cpl_generate_agents — cc frontmatter from shared agent-meta.json,
        bodies namespace-rewritten (14 /r-X refs across 5 personas),
        no .rdf-hash sidecars (strict plugin validation)
  [New] cpl_generate_scripts — executable, profile-filtered copies"
  ```

---

### Phase 3: Hooks transform and version stamping

Adds the `${CLAUDE_PLUGIN_ROOT}` hooks rewrite (all 4 command paths including top-level `statusLine`) and stamps `plugin.json` version from `VERSION`.

**Files:**
- Modify: `adapters/claude-plugin/adapter.sh` (two functions + `cpl_generate_all`)
- Modify: `tests/plugin-adapter.bats` (+3 tests, hooks + plugin.json fixtures)

- **Mode**: serial-agent
- **Accept**: generated `hooks.json` has 0 `~/.claude` occurrences and 4 `CLAUDE_PLUGIN_ROOT` occurrences; PreCompact prompt byte-identical; fixture `plugin.json` version becomes `0.0.0-test`
- **Test**: `tests/plugin-adapter.bats` — @test "plugin hooks.json uses CLAUDE_PLUGIN_ROOT for all 4 script refs", @test "plugin hooks.json preserves prompt-type hooks untouched", @test "generate stamps plugin.json version from VERSION"
- **Edge cases**: spec §11b "Top-level statusLine.command (sibling of hooks)" (jq `walk` covers whole document), "PreCompact prompt-type hook" (untouched assertion), "VERSION bumped, generate not run" (stamping is the mechanism; guard test lands Phase 4)
- **Regression-case**: tests/plugin-adapter.bats::@test "plugin hooks.json uses CLAUDE_PLUGIN_ROOT for all 4 script refs" (test added in this phase; file created in Phase 1 of this plan)

- [ ] **Step 1: Add `cpl_generate_hooks()`**

  ```bash
  # Transform hooks.json: every "command" value under ~/.claude/scripts/
  # (ANYWHERE in the document — includes top-level statusLine, a sibling
  # of "hooks") -> ${CLAUDE_PLUGIN_ROOT}-relative path. Prompt-type hooks
  # pass through untouched. walk/1 is defined inline for jq 1.5 compat
  # (builtin only since 1.6; local def harmlessly shadows it on 1.6+).
  cpl_generate_hooks() {
      local src="${RDF_ADAPTERS}/claude-code/hooks/hooks.json"
      local dst="${_CPL_OUTPUT_DIR}/hooks.json"
      local pfx='"${CLAUDE_PLUGIN_ROOT}"/adapters/claude-plugin/output/scripts'

      rdf_require_file "$src" "hooks.json template"
      jq --arg pfx "$pfx" '
          def walk(f):
              . as $in
              | if type == "object" then
                    reduce keys[] as $key ({}; . + {($key): ($in[$key] | walk(f))}) | f
                elif type == "array" then map(walk(f)) | f
                else f
                end;
          walk(
              if type == "object" and (.command? | type == "string")
                 and (.command | startswith("~/.claude/scripts/"))
              then .command = ($pfx + (.command | ltrimstr("~/.claude/scripts")))
              else .
              end
          )
      ' "$src" > "$dst"
      rdf_log "generated hooks.json (plugin-root paths)"
  }
  ```

- [ ] **Step 2: Add `cpl_stamp_plugin_version()`**

  ```bash
  # Stamp plugin.json version from VERSION. Plugin users only receive
  # updates when this field changes — stamping makes the bump automatic
  # on every generate after a version change.
  cpl_stamp_plugin_version() {
      local manifest="${RDF_HOME}/.claude-plugin/plugin.json"
      local tmp

      rdf_require_file "$manifest" "plugin.json"
      tmp="$(command mktemp)"
      jq --arg v "$RDF_VERSION" '.version = $v' "$manifest" > "$tmp"
      command mv "$tmp" "$manifest"
      rdf_log "stamped plugin.json version: ${RDF_VERSION}"
  }
  ```

- [ ] **Step 3: Extend `cpl_generate_all()`** — after `cpl_generate_scripts` add:

  ```bash
      cpl_generate_hooks
      cpl_stamp_plugin_version
  ```

  > Self-correction note: `cpl_generate_hooks` writes into the staging
  > dir (swapped atomically); `cpl_stamp_plugin_version` writes OUTSIDE
  > output/ to `.claude-plugin/plugin.json` — it must run inside
  > `cpl_generate_all` but its target is not part of the staging swap.
  > That is correct and intentional: the manifest lives at repo root.

- [ ] **Step 4: BATS fixtures + 3 tests** — `setup()` additions:

  ```bash
      cp "${RDF_SRC}/adapters/claude-code/hooks/hooks.json" \
          "${TEST_HOME}/adapters/claude-code/hooks/hooks.json"
      printf '{\n  "name": "rdf",\n  "version": "9.9.9"\n}\n' \
          > "${TEST_HOME}/.claude-plugin/plugin.json"
  ```

  `_generate_plugin` subprocess additions after `cpl_generate_scripts`:
  `cpl_generate_hooks` and `cpl_stamp_plugin_version`.

  New tests:

  ```bash
  @test "plugin hooks.json uses CLAUDE_PLUGIN_ROOT for all 4 script refs" {
      _generate_plugin "${_TEST_HOME}" "${_TEST_OUT}"
      run grep -c 'CLAUDE_PLUGIN_ROOT' "${_TEST_OUT}/hooks.json"
      [ "$output" -eq 4 ]
      run grep '~/.claude' "${_TEST_OUT}/hooks.json"
      [ "$status" -ne 0 ]
  }

  @test "plugin hooks.json preserves prompt-type hooks untouched" {
      _generate_plugin "${_TEST_HOME}" "${_TEST_OUT}"
      diff <(jq -S '.hooks.PreCompact' "${TEST_HOME}/adapters/claude-code/hooks/hooks.json") \
           <(jq -S '.hooks.PreCompact' "${_TEST_OUT}/hooks.json")
  }

  @test "generate stamps plugin.json version from VERSION" {
      _generate_plugin "${_TEST_HOME}" "${_TEST_OUT}"
      run jq -r .version "${_TEST_HOME}/.claude-plugin/plugin.json"
      [ "$output" = "0.0.0-test" ]
  }
  ```

  > The real repo's hooks template is the fixture on purpose: the test
  > then guards the actual 4-ref shape (3 in-hooks + statusLine). If a
  > 5th hook script is added later, the `-eq 4` assertion fails loudly —
  > update it together with the template.

- [ ] **Step 5: Lint + test**

  ```bash
  bash -n adapters/claude-plugin/adapter.sh && shellcheck adapters/claude-plugin/adapter.sh
  # expect: exit 0
  make -C tests test 2>&1 | tee /tmp/test-rdf-P3-debian12.log | grep -c '^not ok'
  # expect: 0
  ```

- [ ] **Step 6: Commit**

  ```bash
  git add adapters/claude-plugin/adapter.sh tests/plugin-adapter.bats
  git commit -m "Plugin adapter: hooks transform and version stamping

  [New] cpl_generate_hooks — jq walk rewrites all 4 ~/.claude/scripts
        command refs (incl. top-level statusLine) to CLAUDE_PLUGIN_ROOT
  [New] cpl_stamp_plugin_version — plugin.json version from VERSION so
        plugin users are never silently frozen on stale releases"
  ```

---

### Phase 4: Manifests and committed plugin output

Declares the repo a marketplace, points `plugin.json` at the generated components, generates and commits the real output, and adds real-repo guard tests.

**Files:**
- Create: `.claude-plugin/marketplace.json`
- Modify: `.claude-plugin/plugin.json` (component paths)
- Create: `adapters/claude-plugin/output/**` (generated, committed)
- Modify: `tests/plugin-adapter.bats` (+3 real-repo guard tests)

- **Mode**: serial-context
- **Accept**: `jq` parses both manifests; `plugin.json` `.commands/.agents/.hooks` point at `./adapters/claude-plugin/output/...`; committed output contains 37 commands / 6 agents / 12 scripts / hooks.json; `jq -r .version plugin.json` equals `cat VERSION`
- **Test**: `tests/plugin-adapter.bats` — @test "repo plugin.json version matches VERSION", @test "repo marketplace.json declares plugin rdf with source ./", @test "repo plugin.json component paths exist"
- **Edge cases**: spec §11b "VERSION bumped, generate not run" (version-sync guard test), "Marketplace added but plugin not installed" (docs, Phase 7), "Plugin user without jq" (Risk 6 — docs, Phase 7)
- **Regression-case**: tests/plugin-adapter.bats::@test "repo plugin.json version matches VERSION" — guards the release-freeze failure mode permanently (test added in this phase; file created in Phase 1 of this plan)

- [ ] **Step 1: Create `.claude-plugin/marketplace.json`**

  ```json
  {
    "name": "rdf",
    "owner": { "name": "R-fx Networks", "email": "proj@rfxn.com" },
    "metadata": { "description": "RDF — governance-driven AI development" },
    "plugins": [
      {
        "name": "rdf",
        "source": "./",
        "description": "Convention governance, quality gates, and typed agent personas"
      }
    ]
  }
  ```

- [ ] **Step 2: Add component paths to `.claude-plugin/plugin.json`** — insert after the `"license"` line (keep all existing fields):

  ```json
    "commands": "./adapters/claude-plugin/output/commands",
    "agents": "./adapters/claude-plugin/output/agents",
    "hooks": "./adapters/claude-plugin/output/hooks.json",
  ```

  (Exact placement: `"license": "GPL-2.0",` then these three lines, then `"keywords": [`.)

  > Execution discovery: `claude plugin validate --strict` REJECTS a
  > directory string for `agents` ("Invalid input") — it requires an
  > explicit array of `.md` file paths. Resolved by having
  > `cpl_stamp_plugin_version` stamp the agents array from generated
  > output at generate time (self-heals when agents are added/removed);
  > the repo guard test iterates the array. `commands` as a directory
  > string IS accepted.

- [ ] **Step 3: Generate and stage real output**

  ```bash
  bin/rdf generate claude-plugin
  # expect: rdf: plugin generation complete: 37 commands, 6 agents, 12 scripts (log line)
  jq . .claude-plugin/plugin.json > /dev/null && jq . .claude-plugin/marketplace.json > /dev/null && echo "manifests parse"
  # expect: manifests parse
  diff <(jq -r .version .claude-plugin/plugin.json) VERSION && echo SYNCED
  # expect: SYNCED
  ```

- [ ] **Step 4: Real-repo guard tests** (append to `tests/plugin-adapter.bats` — these read `RDF_SRC` directly, no generation):

  ```bash
  @test "repo plugin.json version matches VERSION" {
      run jq -r .version "${RDF_SRC}/.claude-plugin/plugin.json"
      [ "$output" = "$(cat "${RDF_SRC}/VERSION")" ]
  }

  @test "repo marketplace.json declares plugin rdf with source ./" {
      run jq -r '.plugins[0].name + " " + .plugins[0].source' "${RDF_SRC}/.claude-plugin/marketplace.json"
      [ "$output" = "rdf ./" ]
  }

  @test "repo plugin.json component paths exist" {
      local p
      for key in commands agents hooks; do
          p="$(jq -r ".${key}" "${RDF_SRC}/.claude-plugin/plugin.json")"
          [ "${p#./}" != "$p" ]           # must be ./-relative
          [ -e "${RDF_SRC}/${p#./}" ]     # must exist in repo
      done
  }
  ```

- [ ] **Step 5: Verify (full)**

  ```bash
  make -C tests test 2>&1 | tee /tmp/test-rdf-P4-debian12.log | grep -c '^not ok'
  # expect: 0
  diff <(cd canonical/commands && grep -l '/r-' ./*.md | sort) \
       <(cd adapters/claude-plugin/output/commands && grep -l '/rdf:r-' ./*.md | sort)
  # expect: no output (exit 0)
  grep -rn '~/.claude' adapters/claude-plugin/output/hooks.json | wc -l
  # expect: 0
  find adapters/claude-plugin/output -name '*.rdf-hash' | wc -l
  # expect: 0
  ```

- [ ] **Step 6: Commit**

  ```bash
  git add .claude-plugin/marketplace.json .claude-plugin/plugin.json \
      adapters/claude-plugin/output tests/plugin-adapter.bats
  git commit -m "Declare repo as plugin marketplace and commit generated plugin output

  [New] .claude-plugin/marketplace.json — repo is its own marketplace
        (install: /plugin marketplace add rfxn/rdf; /plugin install rdf@rdf)
  [New] adapters/claude-plugin/output — 37 commands (namespace-rewritten),
        6 agents, 12 scripts, plugin-root hooks.json
  [Change] plugin.json: component paths -> generated output; version now
           generate-stamped from VERSION
  [New] real-repo guard tests: version sync, marketplace shape, path existence"
  ```

---

### Phase 5: Install-mode detection in doctor and deploy

Manifest-based (`installed_plugins.json`, key `rdf@rdf`) detection; doctor OK/OK/WARN matrix; deploy dual-install warning. Lib changes are independent of the adapter, but the BATS additions append to the Phase-1-created test file — hence dependency [1].

**Files:**
- Modify: `lib/cmd/doctor.sh` (`_check_install_mode()` + `_doctor_one` wiring + scope die-string)
- Modify: `lib/cmd/deploy.sh` (warning in `_deploy_claude_code()`)
- Modify: `tests/plugin-adapter.bats` (+3 tests)

- **Mode**: serial-agent
- **Accept**: with fixture HOME containing BOTH a `~/.claude/commands` symlink and a manifest with `rdf@rdf`, doctor emits `install-mode|WARN|both symlink deploy and plugin install detected...`; plugin-only emits OK; deploy emits the dual-install warn line to stderr
- **Test**: `tests/plugin-adapter.bats` — @test "doctor warns on dual install mode", @test "doctor reports plugin-only install as OK", @test "deploy warns when plugin manifest lists rdf@rdf"
- **Edge cases**: spec §11b "Both symlink deploy and plugin installed" (WARN test); missing manifest = not plugin-installed (plugin-only test's inverse setup); absent/invalid manifest never errors (`jq -e ... 2>/dev/null` guard)
- **Regression-case**: tests/plugin-adapter.bats::@test "doctor reports plugin-only install as OK" — guards against the false-positive class the spec review flagged (test added in this phase; file created in Phase 1 of this plan)

- [ ] **Step 1: Add `_check_install_mode()` to `lib/cmd/doctor.sh`** — insert after `_check_readme()`'s closing brace (before `_resolve_version_for_doctor()`):

  ```bash
  # ── Check: install-mode ──
  # Detects how RDF is installed for this user: symlink deploy (~/.claude/
  # commands -> adapter output), plugin install (rdf@rdf in the plugin
  # manifest), both (WARN — duplicate commands), or neither.
  _check_install_mode() {
      local manifest="${HOME}/.claude/plugins/installed_plugins.json"
      local symlink_mode=0
      local plugin_mode=0

      [[ -L "${HOME}/.claude/commands" ]] && symlink_mode=1
      if [[ -f "$manifest" ]] \
          && jq -e '.plugins | has("rdf@rdf")' "$manifest" >/dev/null 2>&1; then  # absent or malformed manifest = not plugin-installed
          plugin_mode=1
      fi

      if [[ $symlink_mode -eq 1 && $plugin_mode -eq 1 ]]; then
          _add_result "install-mode" "$_WARN" "both symlink deploy and plugin install detected — /r-start and /rdf:r-start both active; remove one (rdf deploy help | /plugin uninstall rdf@rdf)"
      elif [[ $plugin_mode -eq 1 ]]; then
          _add_result "install-mode" "$_OK" "plugin install (rdf@rdf)"
      elif [[ $symlink_mode -eq 1 ]]; then
          _add_result "install-mode" "$_OK" "symlink deploy"
      else
          _add_result "install-mode" "$_OK" "no user-level RDF install (project-only usage)"
      fi
  }
  ```

- [ ] **Step 2: Wire into `_doctor_one()`** — in the `""|all)` branch add `_check_install_mode "$path"` after `_check_sync "$path"`; add scoped case `install-mode)  _check_install_mode "$path" ;;` after the `sync)` case; extend the die-string (currently doctor.sh:776):

  old:
  ```bash
          *)         rdf_die "unknown scope: $scope — valid: artifacts, drift, memory, plan, github, sync, content-drift, readme" ;;
  ```
  new:
  ```bash
          *)         rdf_die "unknown scope: $scope — valid: artifacts, drift, memory, plan, github, sync, install-mode, content-drift, readme" ;;
  ```

  (`_check_install_mode` ignores its `$path` argument — it inspects
  `$HOME`, not the project — but takes it for signature uniformity with
  every other `_check_*`.)

- [ ] **Step 3: Deploy warning** — in `_deploy_claude_code()` (lib/cmd/deploy.sh:164), insert after the pre-flight `fi` and before `rdf_log "deploying Claude Code adapter..."`:

  ```bash
      local plugin_manifest="${HOME}/.claude/plugins/installed_plugins.json"
      if command -v jq >/dev/null 2>&1 \
          && [[ -f "$plugin_manifest" ]] \
          && jq -e '.plugins | has("rdf@rdf")' "$plugin_manifest" >/dev/null 2>&1; then  # no jq / no manifest = skip advisory silently
          rdf_warn "plugin install detected (rdf@rdf) — symlink deploy will duplicate commands as /r-* and /rdf:r-*"
      fi
  ```

- [ ] **Step 4: 3 BATS tests** (append; they source doctor/deploy directly with a fixture HOME):

  ```bash
  # Helper: run _check_install_mode under a fixture HOME, print raw results.
  _run_install_mode_check() {
      local fixture_home="$1"
      HOME="$fixture_home" bash -c '
          set -euo pipefail
          rdf_src="$1"
          RDF_HOME="$rdf_src"
          RDF_LIBDIR="${rdf_src}/lib"
          source "${rdf_src}/lib/rdf_common.sh"
          rdf_init
          source "${rdf_src}/lib/cmd/doctor.sh"
          _reset_results
          _check_install_mode "."
          printf "%s\n" "${_RESULTS[@]}"
      ' -- "$RDF_SRC"
  }

  @test "doctor warns on dual install mode" {
      FIX_HOME="$(mktemp -d)"
      mkdir -p "${FIX_HOME}/.claude/plugins" "${FIX_HOME}/real-target"
      ln -s "${FIX_HOME}/real-target" "${FIX_HOME}/.claude/commands"
      printf '{"version":1,"plugins":{"rdf@rdf":[{"scope":"user"}]}}\n' \
          > "${FIX_HOME}/.claude/plugins/installed_plugins.json"
      run _run_install_mode_check "$FIX_HOME"
      [ "$status" -eq 0 ]
      [[ "$output" == *"install-mode|WARN|both symlink deploy and plugin install"* ]]
      rm -rf "$FIX_HOME"
  }

  @test "doctor reports plugin-only install as OK" {
      FIX_HOME="$(mktemp -d)"
      mkdir -p "${FIX_HOME}/.claude/plugins"
      printf '{"version":1,"plugins":{"rdf@rdf":[{"scope":"user"}]}}\n' \
          > "${FIX_HOME}/.claude/plugins/installed_plugins.json"
      run _run_install_mode_check "$FIX_HOME"
      [ "$status" -eq 0 ]
      [[ "$output" == *"install-mode|OK|plugin install (rdf@rdf)"* ]]
      rm -rf "$FIX_HOME"
  }

  @test "deploy warns when plugin manifest lists rdf@rdf" {
      FIX_HOME="$(mktemp -d)"
      mkdir -p "${FIX_HOME}/.claude/plugins"
      printf '{"version":1,"plugins":{"rdf@rdf":[{"scope":"user"}]}}\n' \
          > "${FIX_HOME}/.claude/plugins/installed_plugins.json"
      run bash -c '
          set -euo pipefail
          rdf_src="$1"
          fix_home="$2"
          HOME="$fix_home"
          RDF_HOME="$rdf_src"
          RDF_LIBDIR="${rdf_src}/lib"
          source "${rdf_src}/lib/rdf_common.sh"
          rdf_init
          source "${rdf_src}/lib/cmd/deploy.sh"
          _deploy_claude_code 1 0
      ' -- "$RDF_SRC" "$FIX_HOME"
      [[ "$output" == *"plugin install detected (rdf@rdf)"* ]]
      rm -rf "$FIX_HOME"
  }
  ```

  > Self-correction note (CORRECTED post-CI): the original deploy test
  > pointed RDF_HOME at the real repo, assuming `adapters/claude-code/
  > output` exists — true locally (untracked, .git/info/exclude) but
  > FALSE in CI checkouts, so the pre-flight died before the warning.
  > The test is hermetic now: fixture RDF_HOME with a minimal cc-output
  > skeleton. Lesson: never assert against untracked local state.

- [ ] **Step 5: Lint + test**

  ```bash
  bash -n lib/cmd/doctor.sh lib/cmd/deploy.sh && shellcheck lib/cmd/doctor.sh lib/cmd/deploy.sh
  # expect: exit 0
  make -C tests test 2>&1 | tee /tmp/test-rdf-P5-debian12.log | grep -c '^not ok'
  # expect: 0
  ```

- [ ] **Step 6: Commit**

  ```bash
  git add lib/cmd/doctor.sh lib/cmd/deploy.sh tests/plugin-adapter.bats
  git commit -m "Install-mode detection: doctor check and deploy dual-install warning

  [New] doctor.sh _check_install_mode — manifest-based (installed_plugins.json
        key rdf@rdf), never cache-dir scanning; WARN on dual install
  [Change] deploy.sh _deploy_claude_code warns when a plugin install exists"
  ```

---

### Phase 6: CI plugin job

Adds the fifth CI job: generate, drift-check, validate strict.

**Files:**
- Modify: `.github/workflows/ci.yml` (new job after `doctor`)

- **Mode**: serial-context
- **Accept**: pushed workflow runs 5 jobs; plugin job green: drift diff empty, `claude plugin validate . --strict` exit 0
- **Test**: N/A (CI config) — verification is the live run: `gh run list --limit 1` shows success incl. plugin job
- **Edge cases**: spec §11b "CI runner lacks network for npm install" (no `continue-on-error` — fails loudly); spec Risk 1 npm-name fallback documented in-step
- **Regression-case**: N/A — refactor — CI config only; the job itself is the permanent guard

- [ ] **Step 1: Append job to `.github/workflows/ci.yml`** after the `doctor` job (before `tests:`):

  ```yaml
    plugin:
      name: Plugin (drift + validate)
      runs-on: ubuntu-latest
      steps:
        - name: Checkout
          uses: actions/checkout@v4

        - name: Install dependencies (jq)
          run: sudo apt-get install -y jq

        - name: Generate claude-plugin output
          run: ./bin/rdf generate claude-plugin

        - name: Fail on uncommitted plugin drift
          # Stale committed output (or an unstamped plugin.json version)
          # makes the release un-mergeable — same guard as the doctor job.
          run: git diff --exit-code adapters/claude-plugin/output .claude-plugin/plugin.json

        - name: Install Claude Code CLI
          run: npm install -g @anthropic-ai/claude-code

        - name: Validate plugin + marketplace (strict)
          run: claude plugin validate . --strict
  ```

  > Verify-at-implementation (spec Risk 1): if `@anthropic-ai/claude-code`
  > is not the correct npm package name, check `npm search claude-code`
  > and the official install docs. If headless `claude plugin validate`
  > proves infeasible in CI (auth requirement), replace the last two steps
  > with a jq schema check of both manifests and note the downgrade in the
  > commit body; strict validate then runs locally pre-release instead.

- [ ] **Step 2: Verify locally then live**

  ```bash
  python3 -c "import yaml; yaml.safe_load(open('.github/workflows/ci.yml')); print('yaml OK')"
  # expect: yaml OK
  bin/rdf generate claude-plugin && git diff --exit-code adapters/claude-plugin/output .claude-plugin/plugin.json && echo "drift clean"
  # expect: drift clean
  ```

- [ ] **Step 3: Commit**

  ```bash
  git add .github/workflows/ci.yml
  git commit -m "CI: plugin job — generate, drift check, strict validation

  [New] ci.yml plugin job: rdf generate claude-plugin, git diff --exit-code
        on committed output + stamped manifest, claude plugin validate --strict"
  ```

  Post-push verification (after the phase batch pushes):

  ```bash
  gh run list --limit 1 --json conclusion --jq '.[0].conclusion'
  # expect: success
  ```

---

### Phase 7: Documentation — install paths, prerequisites, roadmap

Docs catch up with the new consumer install mode.

**Files:**
- Modify: `README.md` (Quick Start + badges row area)
- Modify: `docs/quickstart.md` (§1 gains plugin option; jq prerequisite note)
- Modify: `ROADMAP.md` (check off 3 of 4 "Soon" items)

- **Mode**: serial-agent
- **Accept**: README Quick Start shows both install modes with the namespacing difference stated; quickstart documents jq as hook prerequisite; ROADMAP "Soon" has 3 checked boxes
- **Test**: N/A (docs) — verification greps below
- **Edge cases**: spec §11b "Marketplace added but plugin not installed" (README instructs both commands), "Plugin user without jq" (prerequisite note — Risk 6 mitigation)
- **Regression-case**: N/A — docs — markdown-only phase, no runtime surface

- [ ] **Step 1: README Quick Start** — replace the current §2 code block's step 1-3 header comment area. Old (README.md §2, lines ~37-49):

  ```bash
  # 1. Clone
  git clone https://github.com/rfxn/rdf.git && cd rdf
  ```

  New — insert BEFORE `# 1. Clone` a plugin-mode block, making two labeled paths:

  ```bash
  # ── Option A: plugin install (consumer — commands namespaced /rdf:r-*) ──
  #   In Claude Code:
  #     /plugin marketplace add rfxn/rdf
  #     /plugin install rdf@rdf
  #   Note: hooks + status line require jq on PATH.

  # ── Option B: symlink deploy (contributor/power mode — bare /r-*) ──
  # 1. Clone
  git clone https://github.com/rfxn/rdf.git && cd rdf
  ```

- [ ] **Step 2: quickstart.md §1** — after the existing clone/generate/deploy code block, add:

  ```markdown
  **Prefer a one-command install?** RDF is also a Claude Code plugin:
  `/plugin marketplace add rfxn/rdf` then `/plugin install rdf@rdf`.
  Plugin commands are namespaced (`/rdf:r-start` instead of `/r-start`);
  everything else is identical. Hooks and the status line require `jq`
  on your PATH in both modes.
  ```

- [ ] **Step 3: ROADMAP.md "Soon" section** — flip three boxes to `[x]`
  (installable via marketplace; design pass on namespacing/dual modes;
  validate --strict in CI). Leave `[ ] Submission to the community plugin
  marketplace` unchecked — it is a manual post-merge action.

- [ ] **Step 4: Verify**

  ```bash
  grep -c 'plugin install rdf@rdf' README.md docs/quickstart.md
  # expect: README.md:1 and docs/quickstart.md:1 (one hit each)
  grep -c '^- \[x\]' ROADMAP.md
  # expect: 6 (3 pre-existing in "Now" + 3 newly checked in "Soon")
  ```

- [ ] **Step 5: Commit**

  ```bash
  git add README.md docs/quickstart.md ROADMAP.md
  git commit -m "Docs: plugin install path, jq prerequisite, roadmap progress

  [Change] README Quick Start: plugin install (Option A) vs symlink deploy
           (Option B) with namespacing difference stated
  [Change] quickstart: one-command plugin install + jq hook prerequisite
  [Change] ROADMAP: 3 of 4 plugin-citizenship items shipped"
  ```

---
