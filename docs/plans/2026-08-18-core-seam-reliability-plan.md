# Implementation Plan: core-seam-reliability

**Goal:** Close the three seams that shipped defects in every 3.6.x release: sync
truncation of canonical sources, drift-prone state-helper delivery (and the
plugin-tier gap that hard-stops the pipeline), and unenforced metadata catalogs.

**Architecture:** One shared frontmatter-strip + one shared agent-meta preflight
in `lib/rdf_common.sh`; delivery ownership inverted (deploy-owned per-file
symlinks on checkout installs, SessionStart bootstrap copies on plugin
installs, generate never touches `$HOME`); doctor grows `catalogs` and
`state-helpers` scopes as belt-and-braces.

**Tech Stack:** bash (3.2 floor — macOS CI — intersected with 4.1 CentOS 6),
BATS via `tests/infra`, jq, shellcheck.

**Spec:** docs/specs/2026-08-18-core-seam-reliability-design.md

**Phases:** 7

**Plan Version:** 3.0.6

**Tier:** full

## Conventions

**Coreutils** — `command cp` / `command rm` / `command mkdir` etc. in all
project source; bare coreutils in `.bats` files; `/usr/bin/*` only in agent
tool calls.

**Suppressions** — every new `2>/dev/null` / `|| true` carries a same-line
justification comment.

**Hook contract** — deployed hook scripts use `set -euo pipefail` +
`trap 'exit 0' EXIT`, silent on success, jq-free unless guarded.

**Commit message format** — RDF free-form descriptive subject; body lines
tagged `[New]` `[Change]` `[Fix]`; no AI attribution; stage files explicitly.

**CHANGELOG batching (explicit plan-level deviation):** phases 1–6 commit code
only; Phase 7 lands the consolidated `CHANGELOG` + `CHANGELOG.RELEASE` entries
for the whole wave. This deviates from workspace rule 8's per-commit
requirement (this wave is serial commits on main, not a squash-merged branch);
the deviation is deliberate, declared here, and approved under the operator's
delegated unattended-run authority — one coherent wave entry beats six
fragments of the same feature.

**Regeneration rule** — any phase touching `canonical/` or
`adapters/claude-code/hooks/` must run `./bin/rdf generate claude-code` and
`./bin/rdf generate claude-plugin` before its commit and stage the changed
committed outputs (`adapters/claude-plugin/output/**`). `adapters/claude-code/output/`
is untracked (local-only) — never stage it.

**Verification before commit (every phase touching shell):**
```bash
bash -n <changed .sh files> && shellcheck <changed .sh files>
# expect: exit 0, no output
```

## RC Contract Evidence

| Caller | Helper | Contract relied on |
|--------|--------|--------------------|
| `cmd_sync`, `_hash_deployed_body` | `rdf_strip_frontmatter` | always exits 0; empty stdout for unclosed-frontmatter input (callers empty-guard) |
| `cc_generate_all`, `cpl_generate_all` | `rdf_require_agent_meta` | exits the process via `rdf_die` on missing keys; returns 0 otherwise — callers need no rc check |
| `_deploy_state_helpers` | `_deploy_symlink` | returns 1 + increments `_DEPLOY_SKIPPED` on missing source; caller ignores rc (counters report) |
| `_deploy_state_helpers`, `state-bootstrap.sh` | `diff -q` | 0 = identical, 1 = differs, 2 = error; only 0 triggers the migration remove |
| `_check_state_helpers` | `rdf_hash_stdin` | returns 1 when no SHA tool; check degrades to WARN |

## File Map

### New Files
| File | Lines | Purpose | Test File |
|------|-------|---------|-----------|
| `canonical/scripts/state-bootstrap.sh` | ~55 | plugin-tier SessionStart helper delivery | `tests/bootstrap.bats` |
| `tests/strip.bats` | ~110 | shared strip + preflight unit tests | (is a test) |
| `tests/sync.bats` | ~100 | sync agents-path guards | (is a test) |
| `tests/bootstrap.bats` | ~120 | bootstrap behavior | (is a test) |

### Modified Files
| File | Changes | Test File |
|------|---------|-----------|
| `lib/rdf_common.sh` | +`rdf_strip_frontmatter`, +`rdf_require_agent_meta` | `tests/strip.bats` |
| `lib/cmd/sync.sh` | delete `_strip_frontmatter`; guards on agents loop; shared fn | `tests/sync.bats` |
| `lib/cmd/doctor.sh` | `_hash_deployed_body` via shared fn; +2 checks; scope lists/usage | `tests/doctor.bats` |
| `lib/cmd/generate.sh` | delete `_generate_deploy_state_helpers` + call | `tests/deploy.bats` |
| `lib/cmd/deploy.sh` | +`_deploy_state_helpers`; call + usage text | `tests/deploy.bats` |
| `adapters/claude-code/adapter.sh` | preflight call in `cc_generate_all` | `tests/deploy.bats` |
| `adapters/claude-plugin/adapter.sh` | preflight call in `cpl_generate_all` | `tests/deploy.bats` |
| `adapters/claude-code/hooks/hooks.json` | SessionStart bootstrap entry | `tests/bootstrap.bats` |
| `state/rdf-overhead.sh` | `.rdf-source` fallback | `tests/overhead.bats` |
| `.github/workflows/ci.yml` | bash-3.2 smoke for state-bootstrap.sh | N/A (config) |
| `canonical/commands/{r-status,r-build,r-vpe,r-refresh,r-ship,r-plan,r-save,r-spec,r-util-mem-compact}.md` | absence-guard rewording | N/A (docs) |
| `README.md`, `docs/quickstart.md`, `docs/multi-tool-parity.md` | plugin parity + 13-check count | N/A (docs) |
| `adapters/claude-plugin/output/**` | regenerated (committed output) | N/A (derived) |
| `tests/deploy.bats` | rewrite helper test + 5 new | (is a test) |
| `tests/doctor.bats` | +2 tests | (is a test) |
| `tests/overhead.bats` | adjust deployed-copy cases if broken by symlink delivery | (is a test) |
| `CHANGELOG`, `CHANGELOG.RELEASE` | consolidated wave entries (Phase 7) | N/A (docs) |

### Deleted Files
| File | Reason |
|------|--------|
| (none) | deletions are function-level, listed above |

## Phase Dependencies

- Phase 1: none
- Phase 2: [1]
- Phase 3: [1]
- Phase 4: [3]
- Phase 5: [4]
- Phase 6: [4, 5]
- Phase 7: [2, 5, 6]

(3 and 4 both touch `tests/deploy.bats`; 2 and 3 are parallel-safe but the
whole plan is executed serially — no worktree parallelism is requested.)

---

### Phase 1: Shared strip + agent-meta preflight in lib/rdf_common.sh

Foundation phase: the two shared helpers everything else consumes, with unit
tests.

**Files:**
- Modify: `lib/rdf_common.sh` (add two functions after `rdf_hash_stdin`, i.e. after line 83)
- Create: `tests/strip.bats` (test: itself)

- **Mode**: serial-agent
- **Accept**: `bash -n lib/rdf_common.sh` exits 0; `grep -c '^rdf_strip_frontmatter()' lib/rdf_common.sh` → 1; `grep -c '^rdf_require_agent_meta()' lib/rdf_common.sh` → 1; strip.bats 6 tests pass.
- **Test**: `tests/strip.bats` — 6 tests listed in Step 2.
- **Edge cases**: body `---` horizontal rules preserved; unclosed frontmatter → empty output; frontmatter-less file → verbatim.
- **Regression-case**: tests/strip.bats::@test "strip: frontmatter-less file passes through verbatim"

- [ ] **Step 1: Add the two helpers to `lib/rdf_common.sh`**

  Insert after the `rdf_hash_stdin` function (currently ends line 83), before
  `rdf_die`:

  ```bash
  # rdf_strip_frontmatter FILE — emit FILE's body, stripping ONLY a leading
  # --- ... --- frontmatter block plus one following blank separator; files not
  # starting with --- pass through verbatim. Single strip implementation for
  # sync (reverse flow) and doctor (drift hashing). Unclosed frontmatter emits
  # nothing — callers must empty-guard.
  rdf_strip_frontmatter() {
      command awk '
          NR==1 && /^---[[:space:]]*$/ { fm=1; next }
          fm==1 && /^---[[:space:]]*$/ { fm=2; next }
          fm==1 { next }
          fm==2 { fm=3; if ($0 ~ /^[[:space:]]*$/) next }
          { print }
      ' "$1"
  }

  # rdf_require_agent_meta META_FILE AGENTS_DIR — die listing canonical agents
  # absent from the catalog: a plain-copied agent deploys broken and arms the
  # sync truncation path, so generation must fail instead.
  rdf_require_agent_meta() {
      local meta="$1" agents_dir="$2" missing="" f b
      for f in "${agents_dir}"/*.md; do
          [[ -f "$f" ]] || continue
          b="$(command basename "$f" .md)"
          if ! jq -e --arg a "$b" 'has($a)' "$meta" >/dev/null 2>&1; then  # missing key → collect for the die message
              missing="${missing:+${missing}, }${b}"
          fi
      done
      [[ -z "$missing" ]] || rdf_die "agents missing from agent-meta.json: ${missing} — add entries before generating"
  }
  ```

- [ ] **Step 2: Create `tests/strip.bats`**

  Header mirrors `tests/deploy.bats:1-15` (RDF_SRC resolution, shellcheck
  disables). 6 tests; helper sources `lib/rdf_common.sh` only:

  ```bash
  _strip() {  # run rdf_strip_frontmatter against a fixture file
      bash -c 'source "$1/lib/rdf_common.sh"; rdf_strip_frontmatter "$2"' -- "$RDF_SRC" "$1"
  }

  @test "strip: leading frontmatter block + one blank separator removed" {
      f="$(mktemp)"; printf -- '---\ndescription: x\n---\n\nbody line\n' > "$f"
      run _strip "$f"
      [ "$output" = "body line" ]
      rm -f "$f"
  }

  @test "strip: frontmatter-less file passes through verbatim" {
      f="$(mktemp)"; printf 'plain body\nsecond line\n' > "$f"
      run _strip "$f"
      [ "${lines[0]}" = "plain body" ]
      [ "${lines[1]}" = "second line" ]
      rm -f "$f"
  }

  @test "strip: body --- horizontal rules preserved" {
      f="$(mktemp)"; printf -- '---\nx: y\n---\n\nbody\n---\nafter rule\n' > "$f"
      run _strip "$f"
      echo "$output" | grep -q '^---$'
      echo "$output" | grep -q '^after rule$'
      rm -f "$f"
  }

  @test "strip: unclosed frontmatter yields empty output" {
      f="$(mktemp)"; printf -- '---\nnever closed\n' > "$f"
      run _strip "$f"
      [ -z "$output" ]
      rm -f "$f"
  }

  @test "require_agent_meta: dies listing every missing agent" {
      d="$(mktemp -d)"; printf '{}\n' > "$d/meta.json"
      touch "$d/alpha.md" "$d/beta.md"
      run bash -c 'source "$1/lib/rdf_common.sh"; rdf_require_agent_meta "$2/meta.json" "$2"' -- "$RDF_SRC" "$d"
      [ "$status" -eq 1 ]
      echo "$output" | grep -q 'alpha, beta'
      rm -rf "$d"
  }

  @test "require_agent_meta: complete catalog passes silently" {
      d="$(mktemp -d)"; printf '{"alpha":{"name":"a"}}\n' > "$d/meta.json"
      touch "$d/alpha.md"
      run bash -c 'source "$1/lib/rdf_common.sh"; rdf_require_agent_meta "$2/meta.json" "$2"' -- "$RDF_SRC" "$d"
      [ "$status" -eq 0 ]
      [ -z "$output" ]
      rm -rf "$d"
  }
  ```

- [ ] **Step 3: Verify**

  ```bash
  bash -n lib/rdf_common.sh && shellcheck lib/rdf_common.sh
  # expect: exit 0
  make -C tests test 2>&1 | tee /tmp/test-rdf-P1-debian12.log | tail -5
  # expect: exit 0; strip.bats adds 6 passing tests (222 → 228)
  ```

- [ ] **Step 4: Commit**

  ```bash
  git add lib/rdf_common.sh tests/strip.bats
  git commit -m "Add shared frontmatter-strip and agent-meta preflight helpers

  [New] rdf_strip_frontmatter in lib/rdf_common.sh — leading-anchored strip
        (doctor's verified semantics), single implementation for sync + doctor
  [New] rdf_require_agent_meta in lib/rdf_common.sh — generation preflight that
        dies listing agents absent from agent-meta.json
  [New] tests/strip.bats — 6 unit tests incl. body-hr preservation and
        unclosed-frontmatter empty-output contract"
  ```

---

### Phase 2: Converge sync + doctor on the shared strip; guard the agents path

Fixes the P1 data-loss path: sync's agents loop gains the commands loop's
guards, both loops use the shared function, doctor's hasher consumes it too.

**Files:**
- Modify: `lib/cmd/sync.sh` (delete `_strip_frontmatter` lines 26–44; rewrite agents loop 66–96; commands loop call site 107)
- Modify: `lib/cmd/doctor.sh` (`_hash_deployed_body` lines 348–360)
- Create: `tests/sync.bats` (test: itself)
- Modify: `tests/strip.bats` (add single-implementation grep guard)

- **Mode**: serial-agent
- **Accept**: `grep -c '^_strip_frontmatter()' lib/cmd/sync.sh` → 0; sync of a frontmatter-less agent output leaves canonical byte-identical; `rdf doctor --scope content-drift` behavior unchanged on a clean tree.
- **Test**: 4 tests — the 3 `tests/sync.bats` tests in Step 3 plus the 1 `tests/strip.bats` guard in Step 4.
- **Edge cases**: no-frontmatter agent (verbatim, no truncation); unclosed frontmatter (skip + warn); body `---` rules preserved through sync.
- **Regression-case**: tests/sync.bats::@test "sync agents: frontmatter-less output syncs verbatim (no truncation)"

- [ ] **Step 1: Rewrite the agents loop in `lib/cmd/sync.sh`**

  Delete lines 26–44 (`# Strip YAML frontmatter…` comment block + the whole
  `_strip_frontmatter()` function). Replace the agents loop body (the block
  currently at lines 66–96 beginning `# Sync agents — strip frontmatter`)
  with (mirrors the commands loop exactly):

  ```bash
      # Sync agents — strip frontmatter if present (canonical stays frontmatter-free)
      if [[ -d "${output_dir}/agents" ]]; then
          for out_file in "${output_dir}/agents"/*.md; do
              [[ -f "$out_file" ]] || continue
              local basename_f
              basename_f="$(basename "$out_file")"
              local canon_file="${RDF_CANONICAL}/agents/${basename_f}"
              local body
              if [[ "$(head -1 "$out_file")" == "---" ]]; then
                  body="$(rdf_strip_frontmatter "$out_file")"
                  body="$(echo "$body" | sed '/./,$!d')"   # trim leading blank lines
                  if [[ -z "$body" ]]; then
                      rdf_warn "skipping agents/${basename_f}: unclosed frontmatter (empty body after strip)"
                      continue
                  fi
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
                  rdf_log "WOULD UPDATE: canonical/agents/${basename_f}"
              else
                  printf '%s\n' "$body" > "$canon_file"
                  rdf_log "updated: canonical/agents/${basename_f}"
              fi
              changed=$((changed + 1))
          done
      fi
  ```

  In the commands loop, change line 107 `body="$(_strip_frontmatter "$out_file")"`
  → `body="$(rdf_strip_frontmatter "$out_file")"`.

- [ ] **Step 2: Converge doctor's hasher**

  In `lib/cmd/doctor.sh`, replace the `_hash_deployed_body` definition
  (currently the comment at 347-349 + awk body, lines ~350–360) with:

  ```bash
      # _hash_deployed_body <deployed-file> — hash the frontmatter-stripped body
      # (single strip implementation: rdf_strip_frontmatter in rdf_common.sh).
      _hash_deployed_body() {
          rdf_strip_frontmatter "$1" | rdf_hash_stdin
      }
  ```

- [ ] **Step 3: Create `tests/sync.bats`**

  Same harness as `tests/deploy.bats:123-144` (source sync.sh directly against
  a temp RDF_HOME). 3 tests:

  ```bash
  _run_sync() {  # $1 = temp RDF_HOME
      bash -c '
          set -euo pipefail
          RDF_HOME="$1"; RDF_LIBDIR="$2/lib"; RDF_VERSION="0.0.0-test"
          source "$2/lib/rdf_common.sh"; rdf_init
          source "$2/lib/cmd/sync.sh"; cmd_sync
      ' -- "$1" "$RDF_SRC"
  }

  @test "sync agents: frontmatter-less output syncs verbatim (no truncation)" {
      home="$(mktemp -d)"
      mkdir -p "${home}/canonical/agents" "${home}/adapters/claude-code/output/agents"
      printf 'agent body\nline two\n' > "${home}/canonical/agents/a.md"
      printf 'agent body\nline two\n' > "${home}/adapters/claude-code/output/agents/a.md"
      run _run_sync "$home"
      [ "$status" -eq 0 ]
      [ -s "${home}/canonical/agents/a.md" ]                       # NOT truncated to empty
      grep -q '^agent body$' "${home}/canonical/agents/a.md"
      echo "$output" | grep -q '0 updated'                          # verbatim == unchanged
      rm -rf "$home"
  }

  @test "sync agents: unclosed frontmatter skipped with warning, canonical untouched" {
      home="$(mktemp -d)"
      mkdir -p "${home}/canonical/agents" "${home}/adapters/claude-code/output/agents"
      printf 'precious canonical\n' > "${home}/canonical/agents/a.md"
      printf -- '---\nnever closed\n' > "${home}/adapters/claude-code/output/agents/a.md"
      run _run_sync "$home"
      [ "$status" -eq 0 ]
      echo "$output" | grep -q 'unclosed frontmatter'
      grep -q '^precious canonical$' "${home}/canonical/agents/a.md"
      rm -rf "$home"
  }

  @test "sync agents: frontmatter stripped, body --- rules preserved, edit lands" {
      home="$(mktemp -d)"
      mkdir -p "${home}/canonical/agents" "${home}/adapters/claude-code/output/agents"
      printf 'old body\n' > "${home}/canonical/agents/a.md"
      printf -- '---\nname: a\n---\n\nEDITED body\n---\nrule\n' \
          > "${home}/adapters/claude-code/output/agents/a.md"
      run _run_sync "$home"
      [ "$status" -eq 0 ]
      [ "$(head -1 "${home}/canonical/agents/a.md")" = "EDITED body" ]
      grep -q '^---$' "${home}/canonical/agents/a.md"
      rm -rf "$home"
  }
  ```

- [ ] **Step 4: Add the single-implementation guard to `tests/strip.bats`**

  ```bash
  @test "strip: sync.sh defines no local strip implementation" {
      run grep -c '^_strip_frontmatter()' "$RDF_SRC/lib/cmd/sync.sh"
      [ "$output" = "0" ]
  }
  ```

- [ ] **Step 5: Verify**

  ```bash
  bash -n lib/cmd/sync.sh lib/cmd/doctor.sh && shellcheck lib/cmd/sync.sh lib/cmd/doctor.sh
  # expect: exit 0
  ./bin/rdf generate claude-code >/dev/null 2>&1 && ./bin/rdf doctor --scope content-drift . | tail -3
  # expect: content-drift OKs, 0 FAIL (hasher refactor is behavior-preserving)
  make -C tests test 2>&1 | tee /tmp/test-rdf-P2-debian12.log | tail -5
  # expect: exit 0 (228 → 232 tests)
  ```

- [ ] **Step 6: Commit**

  ```bash
  git add lib/cmd/sync.sh lib/cmd/doctor.sh tests/sync.bats tests/strip.bats
  git commit -m "Fix sync agents-path truncation; converge on one strip implementation

  [Fix] rdf sync agents loop could overwrite a canonical agent with an empty
        body when the deployed file had no frontmatter (missing agent-meta
        plain-copy) — head-1 + empty-body guards now mirror the commands loop
  [Change] sync + doctor _hash_deployed_body consume rdf_strip_frontmatter;
           sync's count-based _strip_frontmatter deleted
  [New] tests/sync.bats — truncation regression, unclosed-frontmatter skip,
        round-trip strip cases"
  ```

---

### Phase 3: Generate preflight — missing agent-meta is a hard failure

**Files:**
- Modify: `adapters/claude-code/adapter.sh` (one call in `cc_generate_all`, after line 285 `rdf_require_file "$_CC_AGENT_META" "agent-meta.json"`)
- Modify: `adapters/claude-plugin/adapter.sh` (one call in `cpl_generate_all`, after line 247 `rdf_require_bin jq`)
- Modify: `tests/deploy.bats` (2 new tests)

- **Mode**: serial-agent
- **Accept**: generating with a canonical agent absent from agent-meta.json exits 1 naming the agent, for both targets; a normal `./bin/rdf generate claude-code` still succeeds.
- **Test**: tests/deploy.bats — the 2 tests in Step 2.
- **Edge cases**: canonical agent added without meta entry → generate exits 1 naming it.
- **Regression-case**: tests/deploy.bats::@test "generate claude-code fails listing agents missing from agent-meta"

- [ ] **Step 1: Add the preflight calls**

  `adapters/claude-code/adapter.sh` — in `cc_generate_all`, directly after
  `rdf_require_file "$_CC_AGENT_META" "agent-meta.json"`:

  ```bash
      rdf_require_agent_meta "$_CC_AGENT_META" "${RDF_CANONICAL}/agents"
  ```

  `adapters/claude-plugin/adapter.sh` — in `cpl_generate_all`, directly after
  `rdf_require_bin jq`:

  ```bash
      rdf_require_agent_meta "${RDF_ADAPTERS}/claude-code/agent-meta.json" "${RDF_CANONICAL}/agents"
  ```

- [ ] **Step 2: Add 2 tests to `tests/deploy.bats`**

  Harness: build a scratch RDF_HOME with a minimal canonical tree + a meta
  file missing one agent, source the adapter, call the generate entry point:

  ```bash
  @test "generate claude-code fails listing agents missing from agent-meta" {
      home="$(mktemp -d)"
      mkdir -p "${home}/canonical/agents" "${home}/canonical/commands" \
               "${home}/canonical/scripts" "${home}/adapters/claude-code/hooks" \
               "${home}/adapters/agent-skills" "${home}/profiles"
      printf 'body\n' > "${home}/canonical/agents/ghost.md"
      printf '{}\n' > "${home}/adapters/claude-code/agent-meta.json"
      printf '{}\n' > "${home}/adapters/claude-code/command-meta-v3.json"
      printf '{}\n' > "${home}/adapters/agent-skills/skill-meta.json"
      printf '{"hooks":{}}\n' > "${home}/adapters/claude-code/hooks/hooks.json"
      run bash -c '
          set -euo pipefail
          RDF_HOME="$1"; RDF_LIBDIR="$2/lib"; RDF_VERSION="0.0.0-test"
          source "$2/lib/rdf_common.sh"; rdf_init
          source "$2/adapters/claude-code/adapter.sh"
          cc_generate_all
      ' -- "$home" "$RDF_SRC"
      [ "$status" -eq 1 ]
      echo "$output" | grep -q 'agents missing from agent-meta.json: ghost'
      rm -rf "$home"
  }

  @test "generate claude-plugin fails on same missing agent-meta" {
      home="$(mktemp -d)"
      mkdir -p "${home}/canonical/agents" "${home}/canonical/commands" \
               "${home}/canonical/scripts" "${home}/adapters/claude-code/hooks" \
               "${home}/adapters/claude-plugin" "${home}/adapters/agent-skills" \
               "${home}/.claude-plugin"
      printf 'body\n' > "${home}/canonical/agents/ghost.md"
      printf '{}\n' > "${home}/adapters/claude-code/agent-meta.json"
      printf '{}\n' > "${home}/adapters/agent-skills/skill-meta.json"
      printf '{"hooks":{}}\n' > "${home}/adapters/claude-code/hooks/hooks.json"
      printf '{"name":"rdf"}\n' > "${home}/.claude-plugin/plugin.json"
      run bash -c '
          set -euo pipefail
          RDF_HOME="$1"; RDF_LIBDIR="$2/lib"; RDF_VERSION="0.0.0-test"
          source "$2/lib/rdf_common.sh"; rdf_init
          source "$2/adapters/claude-plugin/adapter.sh"
          RDF_ADAPTERS="$1/adapters" _CPL_OUTPUT_DIR="$1/adapters/claude-plugin/output" cpl_generate_all
      ' -- "$home" "$RDF_SRC"
      [ "$status" -eq 1 ]
      echo "$output" | grep -q 'agents missing from agent-meta.json: ghost'
      rm -rf "$home"
  }
  ```

  > Self-correction note: the adapter scripts read `RDF_ADAPTERS`/`RDF_CANONICAL`
  > at source time into `_CC_*`/`_CPL_*` vars — the engineer must export
  > `RDF_HOME` to the scratch tree BEFORE `rdf_init` (as shown) so those
  > resolve into the fixture, and may need to source the REAL adapter file
  > with the scratch env rather than copying it. Adjust the harness to
  > whichever sourcing order makes the preflight fire against the fixture —
  > the assertions (exit 1 + message naming `ghost`) are the contract.

- [ ] **Step 3: Verify**

  ```bash
  bash -n adapters/claude-code/adapter.sh adapters/claude-plugin/adapter.sh && \
    shellcheck adapters/claude-code/adapter.sh adapters/claude-plugin/adapter.sh
  # expect: exit 0
  ./bin/rdf generate claude-code | tail -2
  # expect: "CC generation complete: 6 agents, ..." (all 6 agents have meta — no die)
  make -C tests test 2>&1 | tee /tmp/test-rdf-P3-debian12.log | tail -5
  # expect: exit 0 (232 → 234 tests)
  ```

- [ ] **Step 4: Commit**

  ```bash
  git add adapters/claude-code/adapter.sh adapters/claude-plugin/adapter.sh tests/deploy.bats
  git commit -m "Fail generation when a canonical agent lacks an agent-meta entry

  [Change] cc_generate_all + cpl_generate_all preflight rdf_require_agent_meta:
           the warn-and-plain-copy path deployed a frontmatter-less agent and
           armed the sync truncation chain — now a hard failure naming the
           missing agents"
  ```

---

### Phase 4: Invert state-helper delivery — deploy-owned symlinks, generate HOME-clean

**Files:**
- Modify: `lib/cmd/generate.sh` (delete lines 41–68 `_generate_deploy_state_helpers` and the call at line 111)
- Modify: `lib/cmd/deploy.sh` (add `_deploy_state_helpers` before `_deploy_claude_code`; call it at the end of `_deploy_claude_code` before the hooks-skip log; usage text line 14)
- Modify: `state/rdf-overhead.sh` (`.rdf-source` fallback in the recovery chain, lines 25–31)
- Modify: `tests/deploy.bats` (rewrite the test at line 146; add 3)
- Modify: `tests/overhead.bats` (only if the 2 deployed-copy tests break — see Step 5)

- **Mode**: serial-agent
- **Accept**: `HOME=$(mktemp -d) ./bin/rdf generate claude-code` writes nothing under that HOME; after `deploy claude-code` (in the BATS fixture HOME), `find $HOME/.rdf/state -maxdepth 1 -type l | wc -l` = 7 and `git-hooks/pre-commit` is a symlink; a pre-existing identical real copy is upgraded to a symlink without `--force`; a differing copy is skipped with warning.
- **Test**: tests/deploy.bats — 4 tests in Step 4 (1 rewritten + 3 added, net +3 to the suite).
- **Edge cases**: stale real copies migration; `--dry-run` helpers logged not written; `RDF_TARGET` set → helpers still under `$HOME/.rdf/state`; `generate all`/`claude-plugin` write nothing under `$HOME`.
- **Regression-case**: tests/deploy.bats::@test "deploy claude-code symlinks state helpers per-file (glob)"

- [ ] **Step 1: Delete generate-side delivery**

  In `lib/cmd/generate.sh`: remove lines 41–68 (comment block + entire
  `_generate_deploy_state_helpers()` function) and line 111
  (`            _generate_deploy_state_helpers`). Nothing replaces them.

- [ ] **Step 2: Add `_deploy_state_helpers` to `lib/cmd/deploy.sh`**

  Insert before `_deploy_claude_code` (currently line 166):

  ```bash
  # Deploy state helpers as per-file symlinks into ~/.rdf/state/ (glob-driven —
  # no hard-coded list). The dir itself stays real: handoff/ inside it is a
  # runtime write target. Helpers are per-user, so the destination is always
  # $HOME-scoped and does not follow RDF_TARGET.
  _deploy_state_helpers() {
      local dry_run="$1"
      local force="$2"
      local state_dst="${HOME}/.rdf/state"
      local src dst
      for src in "${RDF_HOME}/state/"*.sh; do
          [[ -f "$src" ]] || continue
          dst="${state_dst}/$(basename "$src")"
          # Migration pre-step (NEW, not _deploy_symlink semantics): a real file
          # byte-identical to source is our own old copy-deploy artifact —
          # remove it so the symlink lands without --force. Differing files
          # fall through to _deploy_symlink's skip-with-warn.
          if [[ -f "$dst" && ! -L "$dst" ]] && diff -q "$src" "$dst" >/dev/null 2>&1; then  # identical = machine-managed copy, safe to replace
              [[ $dry_run -eq 1 ]] || command rm -f "$dst"
          fi
          _deploy_symlink "$src" "$dst" "$dry_run" "$force"
      done
      src="${RDF_HOME}/state/git-hooks/pre-commit"
      if [[ -f "$src" ]]; then
          dst="${state_dst}/git-hooks/pre-commit"
          if [[ -f "$dst" && ! -L "$dst" ]] && diff -q "$src" "$dst" >/dev/null 2>&1; then  # same migration rule
              [[ $dry_run -eq 1 ]] || command rm -f "$dst"
          fi
          _deploy_symlink "$src" "$dst" "$dry_run" "$force"
      fi
  }
  ```

  In `_deploy_claude_code`, insert before the
  `# Skip hooks.json — requires manual merge` comment (line 198):

  ```bash
      _deploy_state_helpers "$dry_run" "$force"
  ```

  In `_deploy_usage`, change line 14
  `  claude-code    Deploy to ~/.claude/ (agents, commands, scripts, governance)` →
  `  claude-code    Deploy to ~/.claude/ (agents, commands, scripts, governance) + ~/.rdf/state helpers`

- [ ] **Step 3: `.rdf-source` fallback in `state/rdf-overhead.sh`**

  Replace lines 27–31 (the inner `if [[ -n "$_link" …` / `else` warn block)
  with:

  ```bash
          if [[ -n "$_link" && -d "${_link%/adapters/*}/adapters/claude-code/output" ]]; then
              _rdf_home="${_link%/adapters/*}"
          elif [[ -f "${HOME}/.rdf/state/.rdf-source" ]] \
              && _src="$(command cat "${HOME}/.rdf/state/.rdf-source")" \
              && [[ -d "${_src}/adapters/claude-code" ]]; then
              _rdf_home="$_src"   # plugin install: bootstrap stamps the source root
          else
              echo "rdf-overhead: deploy symlink absent — rules/lite figures may be inaccurate" >&2
          fi
  ```

- [ ] **Step 4: Rewrite/add `tests/deploy.bats` coverage**

  REWRITE the test at line 146 ("generate deploys state helpers + pre-commit
  hook to ~/.rdf/state") into (uses the existing `_run_deploy` helper; the
  fixture home carries BOTH the cc output skeleton and a copy of the real
  `state/` tree so the glob and the deploy stay hermetic):

  ```bash
  @test "deploy claude-code symlinks state helpers per-file (glob)" {
      local home; home="$(mktemp -d)"
      _make_deploy_skeleton "$home"
      cp -R "$RDF_SRC/state" "$home/state"
      run _run_deploy "$home"
      [ "$status" -eq 0 ]
      [ -L "${home}/.rdf/state/rdf-bus.sh" ]
      [ -L "${home}/.rdf/state/rdf-overhead.sh" ]
      [ -L "${home}/.rdf/state/git-hooks/pre-commit" ]
      [ "$(find "${home}/.rdf/state" -maxdepth 1 -type l | wc -l | tr -d ' ')" = "7" ]
      rm -rf "$home"
  }
  ```

  > Note: `_run_deploy` sets `RDF_HOME="$fix_home"`, so the helper glob reads
  > `$home/state/` (the copied tree) and symlink targets resolve inside the
  > fixture — hermetic by construction. RDF_TARGET isolation is already
  > covered by the existing "honors RDF_TARGET override" test; helpers are
  > HOME-scoped by design (see `_deploy_state_helpers` comment).

  ADD:

  ```bash
  @test "deploy migrates byte-identical helper copies to symlinks; differing copy skipped" {
      local home; home="$(mktemp -d)"
      _make_deploy_skeleton "$home"; cp -R "$RDF_SRC/state" "$home/state"
      mkdir -p "${home}/.rdf/state"
      cp "$home/state/rdf-bus.sh" "${home}/.rdf/state/rdf-bus.sh"          # identical → migrate
      printf 'locally modified\n' > "${home}/.rdf/state/rdf-state.sh"      # differs → skip
      run _run_deploy "$home"
      [ -L "${home}/.rdf/state/rdf-bus.sh" ]
      [ ! -L "${home}/.rdf/state/rdf-state.sh" ]
      grep -q '^locally modified$' "${home}/.rdf/state/rdf-state.sh"
      echo "$output" | grep -q 'not a symlink'
      rm -rf "$home"
  }

  @test "generate claude-code writes nothing under HOME" {
      local home; home="$(mktemp -d)"
      run bash -c '
          set -euo pipefail
          rdf_src="$1"; fix_home="$2"
          HOME="$fix_home"; RDF_HOME="$rdf_src"; RDF_LIBDIR="${rdf_src}/lib"
          source "${rdf_src}/lib/rdf_common.sh"; rdf_init
          source "${rdf_src}/lib/cmd/generate.sh"
          type _generate_deploy_state_helpers 2>/dev/null && exit 99
          exit 0
      ' -- "$RDF_SRC" "$home"
      [ "$status" -eq 0 ]                                    # function fully removed
      [ -z "$(find "$home" -mindepth 1 2>/dev/null)" ]       # HOME untouched
      rm -rf "$home"
  }

  @test "deploy --dry-run logs helper symlinks without writing" {
      local home; home="$(mktemp -d)"
      _make_deploy_skeleton "$home"; cp -R "$RDF_SRC/state" "$home/state"
      run _run_deploy "$home" --dry-run
      [ "$status" -eq 0 ]
      echo "$output" | grep -q 'would symlink.*rdf-bus.sh'
      [ ! -e "${home}/.rdf/state/rdf-bus.sh" ]
      rm -rf "$home"
  }
  ```

- [ ] **Step 5: Verify (incl. overhead suite)**

  ```bash
  bash -n lib/cmd/generate.sh lib/cmd/deploy.sh state/rdf-overhead.sh && \
    shellcheck lib/cmd/generate.sh lib/cmd/deploy.sh state/rdf-overhead.sh
  # expect: exit 0
  make -C tests test 2>&1 | tee /tmp/test-rdf-P4-debian12.log | tail -5
  # expect: exit 0 (234 → 237 tests; overhead.bats deployed-copy cases still
  # green — they exercise the deploy-symlink recovery path which is unchanged;
  # if either fails, adjust ONLY its fixture setup to symlink helpers instead
  # of copying, never its assertions)
  ```

- [ ] **Step 6: Commit**

  ```bash
  git add lib/cmd/generate.sh lib/cmd/deploy.sh state/rdf-overhead.sh tests/deploy.bats
  # plus tests/overhead.bats IF touched in Step 5
  git commit -m "Move state-helper delivery to deploy as per-file symlinks

  [Change] rdf deploy claude-code now owns ~/.rdf/state: glob-driven per-file
           symlinks (drift-impossible on checkout installs) with automatic
           migration of byte-identical legacy copies; rdf generate no longer
           writes under \$HOME
  [Fix] the copy-deploy seam behind the 3.6.1/3.6.2/3.6.3 stale-helper class
        is removed at the root instead of re-patched
  [Change] rdf-overhead.sh resolves the checkout via ~/.rdf/state/.rdf-source
           when no deploy symlink exists (plugin installs)"
  ```

---

### Phase 5: Plugin-tier SessionStart bootstrap

**Files:**
- Create: `canonical/scripts/state-bootstrap.sh` (test: `tests/bootstrap.bats`)
- Modify: `adapters/claude-code/hooks/hooks.json` (SessionStart entry)
- Create: `tests/bootstrap.bats`
- Modify: `.github/workflows/ci.yml` (bash-3.2 smoke)
- Modify: `adapters/claude-plugin/output/**` (regenerated — committed output)

- **Mode**: serial-agent
- **Accept**: bootstrap run with a plugin-root-shaped `$0` copies 7 helpers + hook + stamps `.rdf-version`/`.rdf-source`; re-run exits 0 with no copies (stamp current); symlinked `~/.rdf/state` → no-op; unwritable HOME → exit 0; regenerated plugin hooks.json contains the `${CLAUDE_PLUGIN_ROOT}` bootstrap path first in the unmatched SessionStart group.
- **Test**: tests/bootstrap.bats — 5 tests in Step 3.
- **Edge cases**: plugin+checkout coexist (symlink no-op); read-only HOME (exit 0); missing VERSION at root (exit 0, no copy).
- **Regression-case**: tests/bootstrap.bats::@test "bootstrap copies helpers + stamps version from plugin-root layout"

- [ ] **Step 1: Create `canonical/scripts/state-bootstrap.sh`**

  ```bash
  #!/usr/bin/env bash
  # canonical/scripts/state-bootstrap.sh — SessionStart hook: deliver
  # ~/.rdf/state helpers on plugin installs. Checkout deploys symlink helpers
  # via rdf deploy and are detected + skipped. Copies only when the plugin
  # VERSION differs from the last bootstrap stamp. Startup must never fail.

  set -euo pipefail
  trap 'exit 0' EXIT   # SessionStart errors must not disrupt startup — force exit 0 on any failure

  root="${0%/adapters/*}"
  [[ -d "${root}/state" && -f "${root}/VERSION" ]] || exit 0

  state_dst="${HOME:-/tmp}/.rdf/state"

  # A symlinked helper means a checkout deploy owns this dir — never overwrite.
  [[ -L "${state_dst}/rdf-bus.sh" ]] && exit 0

  version="$(command cat "${root}/VERSION")"
  if [[ -f "${state_dst}/.rdf-version" ]] \
      && [[ "$(command cat "${state_dst}/.rdf-version")" == "$version" ]]; then
      exit 0
  fi

  command mkdir -p "${state_dst}/git-hooks"
  for src in "${root}/state/"*.sh; do
      [[ -f "$src" ]] || continue
      dst="${state_dst}/$(command basename "$src")"
      [[ -L "$dst" ]] && continue   # never replace a checkout symlink
      command cp "$src" "$dst"
      command chmod +x "$dst"
  done
  if [[ -f "${root}/state/git-hooks/pre-commit" && ! -L "${state_dst}/git-hooks/pre-commit" ]]; then
      command cp "${root}/state/git-hooks/pre-commit" "${state_dst}/git-hooks/pre-commit"
      command chmod +x "${state_dst}/git-hooks/pre-commit"
  fi
  printf '%s\n' "$version" > "${state_dst}/.rdf-version"
  printf '%s\n' "$root" > "${state_dst}/.rdf-source"
  exit 0
  ```

  `chmod +x canonical/scripts/state-bootstrap.sh`.

  > Self-correction note: on a checkout deploy this same script runs from
  > `~/.claude/scripts/state-bootstrap.sh` (post hooks merge): `$0` contains
  > no `/adapters/`, so `root` = `$0` (a file path), the `-d "${root}/state"`
  > sanity fails, and it exits 0 before touching anything — the symlink
  > check is a second, independent guard.

- [ ] **Step 2: Wire into `adapters/claude-code/hooks/hooks.json`**

  In the SessionStart array, the second (matcher-less) group currently holds
  one hook (`session-start-inject.sh`). Prepend the bootstrap so its hooks
  array becomes:

  ```json
  {
    "hooks": [
      {
        "type": "command",
        "command": "~/.claude/scripts/state-bootstrap.sh",
        "timeout": 10
      },
      {
        "type": "command",
        "command": "~/.claude/scripts/session-start-inject.sh",
        "timeout": 5
      }
    ]
  }
  ```

- [ ] **Step 3: Create `tests/bootstrap.bats`** (5 tests)

  Fixture builder creates a plugin-root-shaped tree so `$0` derivation works:

  ```bash
  _make_plugin_root() {   # $1 = dir; returns script path in $BOOT
      mkdir -p "$1/state/git-hooks" "$1/adapters/claude-plugin/output/scripts"
      printf '#!/usr/bin/env bash\necho helper\n' > "$1/state/rdf-bus.sh"
      printf '#!/usr/bin/env bash\necho hook\n' > "$1/state/git-hooks/pre-commit"
      printf '9.9.9-test\n' > "$1/VERSION"
      cp "$RDF_SRC/canonical/scripts/state-bootstrap.sh" \
         "$1/adapters/claude-plugin/output/scripts/state-bootstrap.sh"
      BOOT="$1/adapters/claude-plugin/output/scripts/state-bootstrap.sh"
  }

  @test "bootstrap copies helpers + stamps version from plugin-root layout" {
      root="$(mktemp -d)"; home="$(mktemp -d)"; _make_plugin_root "$root"
      run env HOME="$home" bash "$BOOT"
      [ "$status" -eq 0 ]; [ -z "$output" ]                      # silent success
      [ -x "${home}/.rdf/state/rdf-bus.sh" ]
      [ -x "${home}/.rdf/state/git-hooks/pre-commit" ]
      [ "$(cat "${home}/.rdf/state/.rdf-version")" = "9.9.9-test" ]
      [ "$(cat "${home}/.rdf/state/.rdf-source")" = "$root" ]
      rm -rf "$root" "$home"
  }

  @test "bootstrap no-ops when stamp is current" {
      root="$(mktemp -d)"; home="$(mktemp -d)"; _make_plugin_root "$root"
      env HOME="$home" bash "$BOOT"
      printf 'sentinel\n' > "${home}/.rdf/state/rdf-bus.sh"     # local mutation
      run env HOME="$home" bash "$BOOT"                          # stamp matches → no copy
      [ "$status" -eq 0 ]
      grep -q '^sentinel$' "${home}/.rdf/state/rdf-bus.sh"
      rm -rf "$root" "$home"
  }

  @test "bootstrap no-ops when helpers are checkout symlinks" {
      root="$(mktemp -d)"; home="$(mktemp -d)"; _make_plugin_root "$root"
      mkdir -p "${home}/.rdf/state"
      ln -s "$root/state/rdf-bus.sh" "${home}/.rdf/state/rdf-bus.sh"
      run env HOME="$home" bash "$BOOT"
      [ "$status" -eq 0 ]
      [ -L "${home}/.rdf/state/rdf-bus.sh" ]                     # untouched
      [ ! -f "${home}/.rdf/state/.rdf-version" ]                 # no stamp written
      rm -rf "$root" "$home"
  }

  @test "bootstrap exits 0 without VERSION at root and copies nothing" {
      root="$(mktemp -d)"; home="$(mktemp -d)"; _make_plugin_root "$root"
      rm -f "$root/VERSION"
      run env HOME="$home" bash "$BOOT"
      [ "$status" -eq 0 ]
      [ ! -e "${home}/.rdf/state/rdf-bus.sh" ]
      rm -rf "$root" "$home"
  }

  @test "bootstrap exits 0 on unwritable HOME" {
      root="$(mktemp -d)"; home="$(mktemp -d)"; _make_plugin_root "$root"
      chmod 555 "$home"
      run env HOME="$home" bash "$BOOT"
      [ "$status" -eq 0 ]
      chmod 755 "$home"; rm -rf "$root" "$home"
  }
  ```

  > Self-correction note: the unwritable-HOME test is skipped when running as
  > root (root ignores mode bits) — guard with
  > `[ "$(id -u)" -eq 0 ] && skip "mode bits ignored as root"`. Docker test
  > containers run as root; macOS CI does not.

- [ ] **Step 4: CI smoke + regenerate**

  In `.github/workflows/ci.yml`, directly after the "Smoke rdf-bus under
  system bash 3.2 (macOS)" step (lines ~132–140), add a functional smoke in
  the same shape (syntax check + a real no-op run from a plugin-root-shaped
  path against a scratch HOME):

  ```yaml
      - name: Smoke state-bootstrap under system bash 3.2 (macOS)
        if: runner.os == 'macOS'
        run: |
          /bin/bash -n canonical/scripts/state-bootstrap.sh
          root="$(mktemp -d)"; mkdir -p "$root/adapters/x"
          cp canonical/scripts/state-bootstrap.sh "$root/adapters/x/boot.sh"
          HOME="$(mktemp -d)" /bin/bash "$root/adapters/x/boot.sh"
          echo "bash 3.2 bootstrap smoke: OK"
  ```

  (The scratch root has no `state/`/`VERSION`, so the run exercises the
  sanity-exit path — asserting the script parses and exits 0 under bash 3.2.)
  Then regenerate:

  ```bash
  ./bin/rdf generate claude-code && ./bin/rdf generate claude-plugin
  git status --porcelain adapters/claude-plugin/output | head
  # expect: modified hooks.json + new scripts/state-bootstrap.sh under output/
  jq -r '.hooks.SessionStart[1].hooks[0].command' adapters/claude-plugin/output/hooks.json
  # expect: "${CLAUDE_PLUGIN_ROOT}"/adapters/claude-plugin/output/scripts/state-bootstrap.sh
  ```

- [ ] **Step 5: Verify**

  ```bash
  bash -n canonical/scripts/state-bootstrap.sh && shellcheck canonical/scripts/state-bootstrap.sh
  # expect: exit 0
  jq . adapters/claude-code/hooks/hooks.json >/dev/null && echo OK
  # expect: OK
  make -C tests test 2>&1 | tee /tmp/test-rdf-P5-debian12.log | tail -5
  # expect: exit 0 (237 → 242 tests)
  ```

- [ ] **Step 6: Commit**

  ```bash
  git add canonical/scripts/state-bootstrap.sh adapters/claude-code/hooks/hooks.json \
          tests/bootstrap.bats .github/workflows/ci.yml adapters/claude-plugin/output
  git commit -m "Add SessionStart state bootstrap: plugin installs get ~/.rdf/state

  [New] canonical/scripts/state-bootstrap.sh — copies state helpers + pre-commit
        hook from the plugin root on session start, version-stamped, no-op on
        checkout (symlink) installs; closes the plugin-tier gap that hard-stopped
        /r-build and degraded 10 commands
  [Change] hooks.json SessionStart runs the bootstrap before lessons inject
  [New] tests/bootstrap.bats — copy/stamp/no-op/unwritable-HOME coverage
  [Change] CI: bash-3.2 smoke for state-bootstrap.sh"
  ```

---

### Phase 6: Doctor catalogs + state-helpers checks (11 → 13)

**Files:**
- Modify: `lib/cmd/doctor.sh` (2 new checks after `_check_deps`; scope wiring in `_doctor_one`; `_doctor_usage` scope list; unknown-scope die message)
- Modify: `tests/doctor.bats` (2 new tests)
- Modify: `README.md` (line 232 "11 checks: …" → 13 + new scope names)

- **Mode**: serial-agent
- **Accept**: `./bin/rdf doctor --scope catalogs .` and `--scope state-helpers .` run; a fixture with a missing agent-meta key FAILs catalogs; a stale helper copy FAILs state-helpers; symlinked helpers OK; `grep -n '11 checks' README.md RDF.md WORKFORCE.md docs/index.md docs/quickstart.md docs/multi-tool-parity.md` → no output (specs/plans are point-in-time snapshots and intentionally keep their historical "11 checks" prose).
- **Test**: tests/doctor.bats — 2 tests in Step 3.
- **Edge cases**: orphan meta entry → WARN; missing meta entry → FAIL; absent helpers → WARN; no jq → WARN-and-skip.
- **Regression-case**: tests/doctor.bats::@test "doctor state-helpers: stale copy FAILs, symlink OKs, absent WARNs"

- [ ] **Step 1: Add `_check_catalogs` after `_check_deps` (line 674)**

  ```bash
  # ── Check: catalogs — adapter metadata catalogs vs canonical globs ──
  # Missing agent-meta key = FAIL (generate refuses; sync-truncation armer);
  # orphan entries = WARN. skill-meta is a curated subset — orphans only.
  _check_catalogs() {
      local agents_dir="${RDF_CANONICAL}/agents"
      local agent_meta="${RDF_ADAPTERS}/claude-code/agent-meta.json"
      local skill_meta="${RDF_ADAPTERS}/agent-skills/skill-meta.json"
      if ! command -v jq >/dev/null 2>&1; then
          _add_result "catalogs" "$_WARN" "jq not found — catalog checks skipped"
          return 0
      fi
      local f b missing="" orphans=""
      if [[ -f "$agent_meta" ]]; then
          for f in "${agents_dir}"/*.md; do
              [[ -f "$f" ]] || continue
              b="$(command basename "$f" .md)"
              jq -e --arg a "$b" 'has($a)' "$agent_meta" >/dev/null 2>&1 \
                  || missing="${missing:+${missing}, }${b}"   # jq -e false/parse-fail both count as missing
          done
          while IFS= read -r b; do
              [[ -f "${agents_dir}/${b}.md" ]] || orphans="${orphans:+${orphans}, }${b}"
          done < <(jq -r 'keys[]' "$agent_meta" 2>/dev/null)  # unparseable meta → empty list (missing loop already flagged)
          if [[ -n "$missing" ]]; then
              _add_result "catalogs" "$_FAIL" "agent-meta.json missing agents: ${missing} — rdf generate will refuse"
          else
              _add_result "catalogs" "$_OK" "agent-meta.json covers all canonical agents"
          fi
          [[ -n "$orphans" ]] && _add_result "catalogs" "$_WARN" "agent-meta.json orphan entries (no canonical agent): ${orphans}"
      else
          _add_result "catalogs" "$_FAIL" "agent-meta.json not found: ${agent_meta}"
      fi
      if [[ -f "$skill_meta" ]]; then
          orphans=""
          while IFS= read -r b; do
              [[ -f "${RDF_CANONICAL}/commands/${b}.md" ]] || orphans="${orphans:+${orphans}, }${b}"
          done < <(jq -r 'keys[]' "$skill_meta" 2>/dev/null)  # unparseable meta → empty list, WARN below not triggered
          if [[ -n "$orphans" ]]; then
              _add_result "catalogs" "$_WARN" "skill-meta.json orphan entries (no canonical command): ${orphans}"
          else
              _add_result "catalogs" "$_OK" "skill-meta.json keys all resolve to canonical commands"
          fi
      fi
      return 0
  }
  ```

- [ ] **Step 2: Add `_check_state_helpers` directly after it**

  ```bash
  # ── Check: state-helpers — ~/.rdf/state delivery integrity ──
  # Symlink → OK (or WARN if it points outside this checkout); real file →
  # hash-compare against source (stale = FAIL, the 3.6.x silent-degradation
  # class); absent → WARN with remediation.
  _check_state_helpers() {
      local state_dst="${HOME}/.rdf/state"
      local src dst b stale="" absent="" foreign=""
      for src in "${RDF_HOME}/state/"*.sh; do
          [[ -f "$src" ]] || continue
          b="$(command basename "$src")"
          dst="${state_dst}/${b}"
          if [[ -L "$dst" ]]; then
              [[ "$(rdf_canonical_path "$dst")" == "$(rdf_canonical_path "$src")" ]] \
                  || foreign="${foreign:+${foreign}, }${b}"
          elif [[ -f "$dst" ]]; then
              [[ "$(rdf_hash_stdin < "$dst")" == "$(rdf_hash_stdin < "$src")" ]] \
                  || stale="${stale:+${stale}, }${b}"
          else
              absent="${absent:+${absent}, }${b}"
          fi
      done
      if [[ -n "$stale" ]]; then
          _add_result "state-helpers" "$_FAIL" "stale deployed copies: ${stale} — re-run 'rdf deploy claude-code' (checkout) or restart your session (plugin)"
      fi
      [[ -n "$foreign" ]] && _add_result "state-helpers" "$_WARN" "symlinks point outside this checkout: ${foreign}"
      [[ -n "$absent" ]] && _add_result "state-helpers" "$_WARN" "helpers not deployed: ${absent} — run 'rdf deploy claude-code'"
      if [[ -z "$stale" && -z "$foreign" && -z "$absent" ]]; then
          _add_result "state-helpers" "$_OK" "all state helpers current"
      fi
      if [[ -f "${state_dst}/.rdf-version" ]] \
          && [[ "$(command cat "${state_dst}/.rdf-version")" != "$RDF_VERSION" ]]; then
          _add_result "state-helpers" "$_WARN" "bootstrap stamp $(command cat "${state_dst}/.rdf-version") != checkout ${RDF_VERSION}"
      fi
      return 0
  }
  ```

  > Self-correction note: `rdf_hash_stdin` returns 1 with no SHA tool; under
  > `set -` semantics inside doctor this surfaces as an empty capture on both
  > sides → equal → no false FAIL. Acceptable degradation; no extra guard.

- [ ] **Step 3: Wire scopes + update README**

  In `_doctor_one` (line ~935): add to the `""|all)` block after
  `_check_deps`:

  ```bash
              _check_catalogs
              _check_state_helpers
  ```

  Add case arms after `deps)`:

  ```bash
          catalogs)       _check_catalogs ;;
          state-helpers)  _check_state_helpers ;;
  ```

  Extend the `unknown scope` die message and `_doctor_usage` scope list with
  `catalogs, state-helpers`.

  `README.md` line 232: change
  `| 11 checks: artifacts, drift, memory, plan, github, sync, install-mode, deps, content-drift, doc-stats, readme |` →
  `| 13 checks: artifacts, drift, memory, plan, github, sync, install-mode, deps, catalogs, state-helpers, content-drift, doc-stats, readme |`

  Add 2 tests to `tests/doctor.bats`, using its existing `_RESULTS`-printing
  harness pattern (`_run_doc_stats`, lines 15–33 — rows print as
  `scope|LEVEL|message`):

  ```bash
  # Usage: _run_check <check_fn> <fix_rdf_home> <fix_home> — prints _RESULTS rows
  _run_check() {
      bash -c '
          set -euo pipefail
          rdf_src="$1"; check_fn="$2"; fix_rdf="$3"; fix_home="$4"
          HOME="$fix_home"
          RDF_HOME="$fix_rdf"
          RDF_LIBDIR="${rdf_src}/lib"
          RDF_VERSION="0.0.0-test"
          source "${rdf_src}/lib/rdf_common.sh"
          rdf_init
          source "${rdf_src}/lib/cmd/doctor.sh"
          _reset_results
          "$check_fn"
          if [ "${#_RESULTS[@]}" -gt 0 ]; then
              printf "%s\n" "${_RESULTS[@]}"
          fi
      ' -- "$RDF_SRC" "$@"
  }

  @test "doctor catalogs: missing agent-meta entry FAILs, orphan WARNs" {
      fix="$(mktemp -d)"
      mkdir -p "$fix/canonical/agents" "$fix/canonical/commands" \
               "$fix/adapters/claude-code" "$fix/adapters/agent-skills"
      touch "$fix/canonical/agents/a.md" "$fix/canonical/agents/b.md"
      printf '{"a":{"name":"a"},"ghost":{"name":"g"}}\n' > "$fix/adapters/claude-code/agent-meta.json"
      printf '{"r-a":"desc"}\n' > "$fix/adapters/agent-skills/skill-meta.json"
      touch "$fix/canonical/commands/r-a.md"
      run _run_check _check_catalogs "$fix" "$fix"
      [ "$status" -eq 0 ]
      [[ "$output" == *"catalogs|FAIL|agent-meta.json missing agents: b"* ]]
      [[ "$output" == *"catalogs|WARN|agent-meta.json orphan entries (no canonical agent): ghost"* ]]
      [[ "$output" == *"catalogs|OK|skill-meta.json keys all resolve to canonical commands"* ]]
      rm -rf "$fix"
  }

  @test "doctor state-helpers: stale copy FAILs, symlink OKs, absent WARNs" {
      fix="$(mktemp -d)"; home="$(mktemp -d)"
      mkdir -p "$fix/state" "$home/.rdf/state"
      printf 'one\n' > "$fix/state/linked.sh"
      printf 'two\n' > "$fix/state/stale.sh"
      printf 'three\n' > "$fix/state/missing.sh"
      ln -s "$fix/state/linked.sh" "$home/.rdf/state/linked.sh"
      printf 'MUTATED\n' > "$home/.rdf/state/stale.sh"
      run _run_check _check_state_helpers "$fix" "$home"
      [ "$status" -eq 0 ]
      [[ "$output" == *"state-helpers|FAIL|stale deployed copies: stale.sh"* ]]
      [[ "$output" == *"state-helpers|WARN|helpers not deployed: missing.sh"* ]]
      [[ "$output" != *"linked.sh"* ]]                       # symlink to source = clean
      rm -rf "$fix" "$home"
  }
  ```

- [ ] **Step 4: Verify**

  ```bash
  bash -n lib/cmd/doctor.sh && shellcheck lib/cmd/doctor.sh
  # expect: exit 0
  ./bin/rdf doctor --scope catalogs . 2>&1 | tail -3
  # expect: OK lines (live catalogs are complete), 0 FAIL
  ./bin/rdf doctor --scope state-helpers . 2>&1 | tail -3
  # expect: on this dev box: OK or WARN (pre-migration copies), no crash
  grep -n '11 checks' README.md RDF.md WORKFORCE.md docs/index.md docs/quickstart.md docs/multi-tool-parity.md
  # expect: no output (specs/plans keep their historical prose)
  make -C tests test 2>&1 | tee /tmp/test-rdf-P6-debian12.log | tail -5
  # expect: exit 0 (242 → 244 tests)
  ```

- [ ] **Step 5: Commit**

  ```bash
  git add lib/cmd/doctor.sh tests/doctor.bats README.md
  git commit -m "Add doctor catalogs and state-helpers scopes (11 -> 13 checks)

  [New] _check_catalogs — agent-meta completeness (FAIL) + orphan entries (WARN)
        + skill-meta orphan detection; the catalog class shipped bugs in 3.6.1
  [New] _check_state_helpers — stale ~/.rdf/state copies FAIL with remediation,
        foreign symlinks and absent helpers WARN, bootstrap stamp drift WARN
  [Change] README doctor row: 13 checks"
  ```

---

### Phase 7: Plugin-parity wording, docs, regeneration, consolidated changelog

**Files:**
- Modify: `canonical/commands/{r-status,r-build,r-vpe,r-refresh,r-ship,r-plan,r-save,r-spec,r-util-mem-compact}.md` (absence-guard rewording)
- Modify: `README.md`, `docs/quickstart.md`, `docs/multi-tool-parity.md` (plugin-tier state claims)
- Modify: `adapters/claude-plugin/output/**` (regenerated)
- Modify: `CHANGELOG`, `CHANGELOG.RELEASE` (consolidated wave entries)

- **Mode**: serial-agent
- **Accept**: `grep -rln 'plugin-only install' canonical/commands/ | wc -l` → 0; the 9 commands + r-build hard-stop describe the bootstrap reality; README/quickstart/parity no longer claim plugin installs lack state helpers; plugin output regenerated and staged; CHANGELOG + CHANGELOG.RELEASE carry the wave's entries.
- **Test**: verification commands below (docs phase — no new BATS).
- **Edge cases**: none
- **Regression-case**: N/A — docs — wording, doc-claim, and regenerated-output updates only; behavior changes were landed and tested in phases 1–6

- [ ] **Step 1: Reword the 9 command guards**

  For each of the 9 files, locate the sentence matching
  `grep -n 'plugin-only install' canonical/commands/<f>.md` (e.g.
  `r-spec.md:47-49`, `r-build.md:22-24`, `r-plan.md:59-62`) and rewrite the
  parenthetical from the shape
  `*If ~/.rdf/state/rdf-bus.sh is absent (plugin-only install), …*` to:

  `*If ~/.rdf/state/rdf-bus.sh is absent (helpers not yet bootstrapped —
  fresh plugin install before its first session restart), <same degraded
  behavior clause>; restart the session (plugin) or run 'rdf deploy
  claude-code' (checkout) to deliver them.*`

  Keep each command's existing degraded-behavior clause (skip session init /
  default tier full / read committed plan) — only the cause + remediation
  text changes. For `r-build.md`'s hard-stop (lines 22–24), the stop remains
  but the message it instructs sends becomes: "`/r-build` needs the
  `~/.rdf/state` helpers — restart your session so the RDF plugin can
  bootstrap them, or run `rdf deploy claude-code` from a checkout."

- [ ] **Step 2: Update the three docs**

  Run `grep -n 'state helper\|degraded\|symlink deploy' README.md docs/quickstart.md docs/multi-tool-parity.md`
  and update every claim that plugin installs never receive state helpers /
  10 commands run degraded, to: plugin installs bootstrap `~/.rdf/state` at
  session start (SessionStart hook); degraded mode now only applies before
  the first session restart after install. Keep the checkout-deploy
  description unchanged apart from noting deploy now also delivers the
  helpers (matches Phase 4's usage text).

- [ ] **Step 3: Regenerate + changelog**

  ```bash
  ./bin/rdf generate claude-code && ./bin/rdf generate claude-plugin
  ```

  Add to `CHANGELOG` (top, under a new unreleased header if none) and mirror
  in `CHANGELOG.RELEASE`, one entry per wave item (wrap per workspace
  changelog style, 6-space `[New]`/`[Fix]` and 9-space `[Change]`
  continuation indent):

  ```
  [Fix] rdf sync could truncate canonical agents to empty when the deployed
        copy had no frontmatter — agents loop now guards like the commands loop
  [Change] one shared frontmatter-strip (rdf_strip_frontmatter) for sync +
           doctor; generation fails when agent-meta.json misses an agent
  [Change] state-helper delivery moved from generate (copy) to deploy
           (per-file symlinks, auto-migrating identical legacy copies);
           generate no longer writes under $HOME
  [New] SessionStart state-bootstrap delivers ~/.rdf/state on plugin installs
        (version-stamped) — the full pipeline now runs on the plugin tier
  [New] doctor scopes: catalogs (agent/skill-meta integrity), state-helpers
        (stale-copy FAIL) — 13 checks
  [New] tests: strip/sync/bootstrap suites + deploy/doctor coverage (222 -> ~244)
  ```

- [ ] **Step 4: Verify**

  ```bash
  grep -rln 'plugin-only install' canonical/commands/ | wc -l
  # expect: 0
  grep -n '11 checks' README.md RDF.md WORKFORCE.md docs/index.md docs/quickstart.md docs/multi-tool-parity.md
  # expect: no output (specs/plans keep their historical prose)
  ./bin/rdf doctor . 2>&1 | tail -3
  # expect: 0 FAIL
  make -C tests test 2>&1 | tee /tmp/test-rdf-P7-debian12.log | tail -5
  # expect: exit 0
  ```

- [ ] **Step 5: Commit**

  ```bash
  git add canonical/commands/r-status.md canonical/commands/r-build.md \
          canonical/commands/r-vpe.md canonical/commands/r-refresh.md \
          canonical/commands/r-ship.md canonical/commands/r-plan.md \
          canonical/commands/r-save.md canonical/commands/r-spec.md \
          canonical/commands/r-util-mem-compact.md \
          README.md docs/quickstart.md docs/multi-tool-parity.md \
          adapters/claude-plugin/output CHANGELOG CHANGELOG.RELEASE
  git commit -m "Update plugin-tier wording for state bootstrap; consolidated changelog

  [Change] 9 command absence-guards + /r-build hard-stop now describe the
           bootstrap reality (restart session / rdf deploy) instead of a
           permanent plugin-tier limitation
  [Change] README/quickstart/multi-tool-parity: plugin installs bootstrap
           ~/.rdf/state at session start
  [Change] CHANGELOG + CHANGELOG.RELEASE: consolidated core-seam wave entries"
  ```

---
