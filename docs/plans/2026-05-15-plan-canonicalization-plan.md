# Implementation Plan: Plan Canonicalization

**Goal:** Move the active-plan slot from root `PLAN.md` (gitignored, prone to inter-session clobbering) to `docs/plans/{YYYY-MM-DD}-{topic}-plan.md` (committed at creation). Route every consumer through a new `rdf_active_plan_path` resolver in `state/rdf-bus.sh` with a three-tier fallback (session pointer → un-suffixed pointer → root PLAN.md legacy).

**Architecture:** 7 phases. P1 lands the resolver helpers + `lib/cmd/generate.sh` deploy extension + BATS coverage. P2 rewrites `/r-plan` to write to `docs/plans/` and commit mandatorily. P3-P5 wire the resolver through 7 commands + 6 agent/reference files + 5 bash/lib/state files. P3, P4, P5 are independent and may run as a parallel-batch once P1 lands. P6 runs the local migration (`.gitignore`, `git rm --cached PLAN.md`) and the adapter regen. P7 ships 3.1.2.

**Tech Stack:** Bash 4.1+ (CentOS 6 floor), markdown (canonical content; frontmatter-free), BATS via existing batsman submodule.

**Spec:** docs/specs/2026-05-15-plan-canonicalization-design.md

**Phases:** 7

**Plan Version:** 3.0.6

**Predecessor PLAN.md note:** Overwrites a stale PLAN.md for the just-shipped 3.1.1 reviewer-ROI work. That plan's content is already preserved at `docs/plans/2026-04-26-reviewer-roi-3.1.1-plan.md` (commit `ff65b85`) — no migration needed.

**Bootstrap note:** This plan itself is committed to `docs/plans/` at creation, exercising the very flow being implemented. `PLAN.md` at root is updated as a working-slot copy for `/r-build` until P6 untracks it.

---

## Conventions

**Commit message format:** RDF — free-form descriptive (no version prefix). Tag body lines with `[New]` `[Change]` `[Fix]` `[Remove]`. One commit per phase. No `Co-Authored-By`.

**Canonical content:** All `canonical/**/*.md` edits are frontmatter-free. Adapter regen (`rdf generate claude-code`) happens in P6 only — P2-P5 do not regenerate.

**Staging:** `git add <path>` explicitly per file. `docs/plans/` and `docs/specs/` ARE committed. Other working files (`PLAN.md`, `MEMORY.md`, `.rdf/`) remain excluded — `.git/info/exclude` already lists them.

**CHANGELOG / CHANGELOG.RELEASE:** P7 batches all entries into a single 3.1.2 section.

**Shell standards:** `#!/usr/bin/env bash`, `set -euo pipefail`, `command cp/mv/rm/cat`, double-quote all variables, `command -v` for binary discovery.

**Version bump:** 3.1.1 → 3.1.2. Patch — additive resolver, back-compat fallback preserved.

**Resolver call pattern (every consumer):**

```bash
# At top of script (or near existing source state/rdf-bus.sh):
source state/rdf-bus.sh    # OR ${RDF_STATE_DIR}/rdf-bus.sh, OR $(dirname "$0")/rdf-bus.sh
                           # — exact form documented per phase

# Where the script formerly used PLAN.md directly:
plan_path="$(rdf_active_plan_path "$project_root")" || {
    echo "No active plan found." >&2
    exit 1
}
# use $plan_path henceforth
```

**CRITICAL — do NOT:**
- Refactor adjacent unrelated code "while in the file."
- Touch files in the No-Touch list (see spec §4.1).
- Commit `PLAN.md` content — root PLAN.md is a working slot; the canonical copy is in `docs/plans/`.
- Add new skill files. Resolver behavior lives in `state/rdf-bus.sh`; no separate skill.
- Edit `~/.claude/` directly — canonical only; regen in P6.
- Bump version in P1-P6 — version only changes in P7.

---

## File Map

### New Files

| File | Lines | Purpose | Test File |
|------|------:|---------|-----------|
| `tests/plan-canonicalization.bats` | ~140 | BATS coverage for resolver, set/clear lifecycle, fallback tiers, CRLF strip, session isolation | N/A (is the test file) |
| `tests/fixtures/plan-canon/canonical/docs/plans/2026-05-15-test-plan.md` | ~12 | Minimal canonical plan fixture | N/A (fixture) |
| `tests/fixtures/plan-canon/legacy/PLAN.md` | ~10 | Minimal legacy root-PLAN fixture | N/A (fixture) |

### Modified Files

| File | Changes | Test File |
|------|---------|-----------|
| `state/rdf-bus.sh` | Append three helper functions (`rdf_active_plan_path`, `rdf_set_active_plan`, `rdf_clear_active_plan`); update header function inventory. | `tests/plan-canonicalization.bats` |
| `lib/cmd/generate.sh` | Add `rdf-bus.sh` to `_generate_deploy_state_helpers` loop (line 41) so resolver helpers ship to `~/.rdf/state/`. | `tests/adapter.bats` |
| `canonical/commands/r-plan.md` | Step 2 writes `docs/plans/{date}-{topic}-plan.md`; Step 3.3 commit becomes mandatory; new Step 2.0 (choose filename) and Step 3.3.1 (set pointer); Resume Protocol reads via resolver; new `--resume <path>` flag. | `tests/adapter.bats` |
| `canonical/commands/r-build.md` | §1 reads via resolver; §2b worktree dispatch copies resolver result. | `tests/adapter.bats` |
| `canonical/commands/r-ship.md` | Reads via resolver; calls `rdf_clear_active_plan` after successful release. | `tests/adapter.bats` |
| `canonical/commands/r-save.md` | §2 reads via resolver. | `tests/adapter.bats` |
| `canonical/commands/r-status.md` | Reads via resolver; output shows named plan path, not `PLAN.md`. | `tests/adapter.bats` |
| `canonical/commands/r-vpe.md` | Output text shows named plan path. | `tests/adapter.bats` |
| `canonical/commands/r-start.md` | Reads via resolver. | `tests/adapter.bats` |
| `canonical/commands/r-refresh.md` | §5b reads via resolver. | `tests/adapter.bats` |
| `canonical/agents/dispatcher.md` | Load reads via resolver; worktree sync uses resolver+basename; post-merge scope check eval uses resolver. | `tests/adapter.bats` |
| `canonical/agents/engineer.md` | Scope-read prose mentions resolver. | `tests/adapter.bats` |
| `canonical/reference/framework.md` | Status-markers section: clarify status lives in work-output. Plan inventory updated. | `tests/adapter.bats` |
| `canonical/reference/session-safety.md` | Plan sync table: resolver-based reading. | `tests/adapter.bats` |
| `canonical/reference/progress-tracking.md` | One-line reference update. | `tests/adapter.bats` |
| `canonical/reference/plan-schema.md` | Three-call-site enforcement table: rewording "after PLAN.md write" → "after plan write". | `tests/adapter.bats` |
| `lib/cmd/refresh.sh` | Source rdf-bus from `${RDF_STATE_DIR}/rdf-bus.sh`; replace `${project_path}/PLAN.md` with `$(rdf_active_plan_path "$project_path")`. | `tests/plan-canonicalization.bats` |
| `lib/cmd/dispatch.sh` | Usage example strings reference named plan paths. | N/A (usage doc) |
| `state/rotate-work-output.sh` | Source rdf-bus from `$(command dirname "$0")/rdf-bus.sh`; replace `${_project_root}/PLAN.md` with `$(rdf_active_plan_path "$_project_root")`. | `tests/plan-canonicalization.bats` |
| `state/git-hooks/pre-commit` | Ancestor walk: search for `state/rdf-bus.sh` instead of `PLAN.md`; call resolver to get plan path; pass to `rdf_parse_phase_scope`. | `tests/rdf-bus.bats` (pre-existing) + `tests/plan-canonicalization.bats` |
| `.gitignore` | Add `PLAN.md`, `PLAN*.md`, `PLAN-*.md`, `.rdf/active-plan*`. | N/A (config) |
| `(git index)` | `git rm --cached PLAN.md` — untrack stale 3.0.3 snapshot. | N/A (git-tree op) |
| `(local)` `.git/info/exclude` | Remove line 18 (`docs/`) — local operator action, not committed. | N/A (local-only file) |
| `VERSION` | 3.1.1 → 3.1.2 | N/A (config) |
| `RDF.md` | Version reference 3.1.2 | N/A (docs) |
| `README.md` | Version badge 3.1.2 | N/A (docs) |
| `CHANGELOG` | New `## 3.1.2` section | N/A (docs) |
| `CHANGELOG.RELEASE` | New `## 3.1.2` release-notes section | N/A (docs) |

### Deleted Files

None. Root `PLAN.md` is untracked, not deleted — operators may retain it as a legacy working file until they re-plan.

---

## Phase Dependencies

- Phase 1: none
- Phase 2: [1]
- Phase 3: [1]
- Phase 4: [1]
- Phase 5: [1]
- Phase 6: [2, 3, 4, 5]
- Phase 7: [6]

Phases 3, 4, 5 are independent (no shared files) and eligible for an inter-phase parallel batch via `/r-build --parallel` once P1 completes.

---

### Phase 1: Resolver helpers + generate.sh deploy + BATS coverage

Add `rdf_active_plan_path`, `rdf_set_active_plan`, `rdf_clear_active_plan` to `state/rdf-bus.sh`. Extend `lib/cmd/generate.sh` to deploy `rdf-bus.sh` to `~/.rdf/state/`. Land BATS coverage for the new helpers including session-scoped pointer, un-suffixed fallback, legacy `PLAN.md` fallback, CRLF strip, missing-file handling, and pointer-validation in set.

**Files:**
- Modify: `state/rdf-bus.sh` (append helpers + header inventory update)
- Modify: `lib/cmd/generate.sh` (extend deploy loop)
- Create: `tests/plan-canonicalization.bats`
- Create: `tests/fixtures/plan-canon/canonical/docs/plans/2026-05-15-test-plan.md`
- Create: `tests/fixtures/plan-canon/legacy/PLAN.md`

- **Mode**: serial-agent
- **Accept**:
  - `bash -n state/rdf-bus.sh` exits 0
  - `shellcheck state/rdf-bus.sh` exits 0
  - `source state/rdf-bus.sh; declare -F rdf_active_plan_path rdf_set_active_plan rdf_clear_active_plan` lists 3 declarations
  - `grep -nE '^[[:space:]]+rdf-bus\.sh' lib/cmd/generate.sh` returns ≥ 1 hit inside `_generate_deploy_state_helpers`
  - `make -C tests test` exits 0
  - `grep -c '^\s*@test ' tests/plan-canonicalization.bats` returns 13
- **Test**: `tests/plan-canonicalization.bats` — 13 new `@test` blocks (see step 3 for full list).
- **Edge cases**: Pointer to missing file (resolver falls through); empty pointer file (resolver falls through); CRLF in pointer content (stripped); relative path passed to set (absolutized); double-call to set (overwrites); clear when no pointer (idempotent); session ID unset (un-suffixed pointer path).
- **Regression-case**: `tests/plan-canonicalization.bats::@test "rdf_active_plan_path resolves session-scoped pointer"`

- [ ] **Step 1: Append the three helpers to `state/rdf-bus.sh`**

  Current file ends at line 110 (verified via `wc -l`). Append after line 110 (after the closing `}` of `rdf_parse_phase_scope`):

  ```bash

  # rdf_active_plan_path [project_root] — resolve active plan path
  # Resolution order:
  #   1. .rdf/active-plan-${RDF_SESSION_ID}  (session-scoped)
  #   2. .rdf/active-plan                    (un-suffixed default)
  #   3. PLAN.md                             (legacy fallback)
  # Returns 0 with path on stdout if found; 1 with empty stdout otherwise.
  rdf_active_plan_path() {
      local root="${1:-$PWD}" pointer plan
      rdf_session_init
      pointer="${root}/.rdf/active-plan-${RDF_SESSION_ID}"
      if [[ -f "$pointer" ]]; then
          plan="$(< "$pointer")"
          plan="${plan%[$'\r\n']}"
          plan="${plan%[$'\r\n']}"
          if [[ -n "$plan" && -f "$plan" ]]; then
              printf '%s\n' "$plan"
              return 0
          fi
      fi
      pointer="${root}/.rdf/active-plan"
      if [[ -f "$pointer" ]]; then
          plan="$(< "$pointer")"
          plan="${plan%[$'\r\n']}"
          plan="${plan%[$'\r\n']}"
          if [[ -n "$plan" && -f "$plan" ]]; then
              printf '%s\n' "$plan"
              return 0
          fi
      fi
      if [[ -f "${root}/PLAN.md" ]]; then
          printf '%s\n' "${root}/PLAN.md"
          return 0
      fi
      return 1
  }

  # rdf_set_active_plan <plan_path> [project_root] — write pointer
  # plan_path may be relative or absolute; absolutized before write.
  rdf_set_active_plan() {
      local plan="${1:?rdf_set_active_plan requires plan path}"
      local root="${2:-$PWD}"
      rdf_session_init
      if [[ "$plan" != /* ]]; then
          plan="$(command pwd)/${plan}"
      fi
      if [[ ! -f "$plan" ]]; then
          printf 'rdf_set_active_plan: plan file does not exist: %s\n' "$plan" >&2
          return 1
      fi
      command mkdir -p "${root}/.rdf"
      printf '%s\n' "$plan" > "${root}/.rdf/active-plan-${RDF_SESSION_ID}"
  }

  # rdf_clear_active_plan [project_root] — remove session pointer (idempotent)
  rdf_clear_active_plan() {
      local root="${1:-$PWD}"
      rdf_session_init
      command rm -f "${root}/.rdf/active-plan-${RDF_SESSION_ID}"
  }
  ```

  Also update header (lines 6-7):

  ```bash
  # Provides: rdf_session_init, rdf_scoped_filename, rdf_session_short,
  #           rdf_parse_phase_scope, rdf_active_plan_path,
  #           rdf_set_active_plan, rdf_clear_active_plan.
  ```

- [ ] **Step 2: Extend `lib/cmd/generate.sh:_generate_deploy_state_helpers` deploy loop**

  Current loop (line 41):

  ```bash
  for _helper in rdf-state.sh context-audit.sh rotate-work-output.sh; do
  ```

  Change to:

  ```bash
  for _helper in rdf-state.sh context-audit.sh rotate-work-output.sh rdf-bus.sh; do
  ```

- [ ] **Step 3: Create `tests/plan-canonicalization.bats` with 13 test blocks**

  ```bash
  #!/usr/bin/env bats
  # tests/plan-canonicalization.bats — plan canonicalization resolver lifecycle
  # (C) 2026 R-fx Networks <proj@rfxn.com>
  # GNU GPL v2

  setup() {
      TEST_TMP="$(mktemp -d)"
      mkdir -p "$TEST_TMP/proj/.rdf" "$TEST_TMP/proj/docs/plans"
      # shellcheck source=/dev/null
      source "${BATS_TEST_DIRNAME}/../state/rdf-bus.sh"
      RDF_SESSION_ID="01900000-0000-7000-8000-000000000001"
      export RDF_SESSION_ID
  }

  teardown() {
      rm -rf "$TEST_TMP"
  }

  @test "rdf_active_plan_path resolves session-scoped pointer" {
      printf '%s\n' '# Plan' > "$TEST_TMP/proj/docs/plans/foo.md"
      printf '%s\n' "$TEST_TMP/proj/docs/plans/foo.md" > "$TEST_TMP/proj/.rdf/active-plan-${RDF_SESSION_ID}"
      run rdf_active_plan_path "$TEST_TMP/proj"
      [ "$status" -eq 0 ]
      [ "$output" = "$TEST_TMP/proj/docs/plans/foo.md" ]
  }

  @test "rdf_active_plan_path falls back to un-suffixed pointer" {
      printf '%s\n' '# Plan' > "$TEST_TMP/proj/docs/plans/bar.md"
      printf '%s\n' "$TEST_TMP/proj/docs/plans/bar.md" > "$TEST_TMP/proj/.rdf/active-plan"
      run rdf_active_plan_path "$TEST_TMP/proj"
      [ "$status" -eq 0 ]
      [ "$output" = "$TEST_TMP/proj/docs/plans/bar.md" ]
  }

  @test "rdf_active_plan_path returns PLAN.md as last resort" {
      printf '%s\n' '# Legacy Plan' > "$TEST_TMP/proj/PLAN.md"
      run rdf_active_plan_path "$TEST_TMP/proj"
      [ "$status" -eq 0 ]
      [ "$output" = "$TEST_TMP/proj/PLAN.md" ]
  }

  @test "rdf_active_plan_path returns 1 when nothing exists" {
      run rdf_active_plan_path "$TEST_TMP/proj"
      [ "$status" -eq 1 ]
      [ -z "$output" ]
  }

  @test "rdf_active_plan_path skips empty pointer and falls through" {
      : > "$TEST_TMP/proj/.rdf/active-plan-${RDF_SESSION_ID}"
      printf '%s\n' '# Legacy' > "$TEST_TMP/proj/PLAN.md"
      run rdf_active_plan_path "$TEST_TMP/proj"
      [ "$status" -eq 0 ]
      [ "$output" = "$TEST_TMP/proj/PLAN.md" ]
  }

  @test "rdf_active_plan_path skips pointer to nonexistent file" {
      printf '%s\n' "$TEST_TMP/proj/docs/plans/missing.md" > "$TEST_TMP/proj/.rdf/active-plan-${RDF_SESSION_ID}"
      printf '%s\n' '# Legacy' > "$TEST_TMP/proj/PLAN.md"
      run rdf_active_plan_path "$TEST_TMP/proj"
      [ "$status" -eq 0 ]
      [ "$output" = "$TEST_TMP/proj/PLAN.md" ]
  }

  @test "rdf_active_plan_path strips CRLF from pointer content" {
      printf '%s\n' '# Plan' > "$TEST_TMP/proj/docs/plans/baz.md"
      printf '%s\r\n' "$TEST_TMP/proj/docs/plans/baz.md" > "$TEST_TMP/proj/.rdf/active-plan-${RDF_SESSION_ID}"
      run rdf_active_plan_path "$TEST_TMP/proj"
      [ "$status" -eq 0 ]
      [ "$output" = "$TEST_TMP/proj/docs/plans/baz.md" ]
  }

  @test "rdf_set_active_plan writes session-scoped pointer" {
      printf '%s\n' '# Plan' > "$TEST_TMP/proj/docs/plans/qux.md"
      run rdf_set_active_plan "$TEST_TMP/proj/docs/plans/qux.md" "$TEST_TMP/proj"
      [ "$status" -eq 0 ]
      [ -f "$TEST_TMP/proj/.rdf/active-plan-${RDF_SESSION_ID}" ]
      pointer_content="$(< "$TEST_TMP/proj/.rdf/active-plan-${RDF_SESSION_ID}")"
      [ "$pointer_content" = "$TEST_TMP/proj/docs/plans/qux.md" ]
  }

  @test "rdf_set_active_plan absolutizes relative paths" {
      printf '%s\n' '# Plan' > "$TEST_TMP/proj/docs/plans/rel.md"
      cd "$TEST_TMP/proj"
      run rdf_set_active_plan "docs/plans/rel.md" "$TEST_TMP/proj"
      [ "$status" -eq 0 ]
      pointer_content="$(< "$TEST_TMP/proj/.rdf/active-plan-${RDF_SESSION_ID}")"
      [[ "$pointer_content" == /* ]]
  }

  @test "rdf_set_active_plan rejects nonexistent path" {
      run rdf_set_active_plan "/no/such/file.md" "$TEST_TMP/proj"
      [ "$status" -eq 1 ]
      [[ "$output" =~ "does not exist" ]]
  }

  @test "rdf_clear_active_plan removes session pointer" {
      printf '%s\n' '# Plan' > "$TEST_TMP/proj/docs/plans/clear.md"
      printf '%s\n' "$TEST_TMP/proj/docs/plans/clear.md" > "$TEST_TMP/proj/.rdf/active-plan-${RDF_SESSION_ID}"
      run rdf_clear_active_plan "$TEST_TMP/proj"
      [ "$status" -eq 0 ]
      [ ! -f "$TEST_TMP/proj/.rdf/active-plan-${RDF_SESSION_ID}" ]
  }

  @test "rdf_clear_active_plan is idempotent" {
      run rdf_clear_active_plan "$TEST_TMP/proj"
      [ "$status" -eq 0 ]
  }

  @test "two RDF_SESSION_IDs maintain independent pointers" {
      printf '%s\n' '# Plan A' > "$TEST_TMP/proj/docs/plans/a.md"
      printf '%s\n' '# Plan B' > "$TEST_TMP/proj/docs/plans/b.md"
      RDF_SESSION_ID="01900000-0000-7000-8000-000000000AAA" \
        rdf_set_active_plan "$TEST_TMP/proj/docs/plans/a.md" "$TEST_TMP/proj"
      RDF_SESSION_ID="01900000-0000-7000-8000-000000000BBB" \
        rdf_set_active_plan "$TEST_TMP/proj/docs/plans/b.md" "$TEST_TMP/proj"
      # Each pointer has independent content
      [ "$(< $TEST_TMP/proj/.rdf/active-plan-01900000-0000-7000-8000-000000000AAA)" = "$TEST_TMP/proj/docs/plans/a.md" ]
      [ "$(< $TEST_TMP/proj/.rdf/active-plan-01900000-0000-7000-8000-000000000BBB)" = "$TEST_TMP/proj/docs/plans/b.md" ]
  }
  ```

- [ ] **Step 4: Create test fixtures**

  Create `tests/fixtures/plan-canon/canonical/docs/plans/2026-05-15-test-plan.md`:

  ```markdown
  # Implementation Plan: Test Fixture

  **Plan Version:** 3.0.6
  **Phases:** 1

  ### Phase 1: Stub

  - **Mode**: serial-context
  ```

  Create `tests/fixtures/plan-canon/legacy/PLAN.md`:

  ```markdown
  # Legacy PLAN.md fixture

  ### Phase 1: Legacy
  ```

- [ ] **Step 5: Verify**

  ```bash
  bash -n state/rdf-bus.sh && shellcheck state/rdf-bus.sh
  # expect: no output, exit 0

  source state/rdf-bus.sh; declare -F rdf_active_plan_path rdf_set_active_plan rdf_clear_active_plan
  # expect: 3 lines, each starting with "declare -f"

  grep -nE 'rdf-bus\.sh' lib/cmd/generate.sh
  # expect: >= 1 hit in _generate_deploy_state_helpers

  grep -c '^[[:space:]]*@test ' tests/plan-canonicalization.bats
  # expect: 13

  make -C tests test 2>&1 | tee /tmp/test-rdf-P1-debian12.log | tail -10
  # expect: contains "ok" lines, no "not ok"
  ```

- [ ] **Step 6: Commit**

  ```bash
  git add state/rdf-bus.sh lib/cmd/generate.sh \
          tests/plan-canonicalization.bats tests/fixtures/plan-canon/
  git commit -m "Add rdf_active_plan_path resolver and BATS coverage

  [New] state/rdf-bus.sh — three helpers: rdf_active_plan_path (three-tier
        resolver: session pointer → un-suffixed pointer → root PLAN.md legacy),
        rdf_set_active_plan (absolutizes relative paths, validates target
        exists, writes session-scoped pointer), rdf_clear_active_plan
        (idempotent removal of session pointer)
  [Change] lib/cmd/generate.sh — _generate_deploy_state_helpers loop now
        ships rdf-bus.sh to ~/.rdf/state/ alongside the other state helpers
        so deployed consumers can resolve it
  [New] tests/plan-canonicalization.bats — 13 tests covering session-scoped
        pointer, un-suffixed fallback, PLAN.md legacy fallback, empty
        pointer skip, missing-file skip, CRLF strip, set/clear lifecycle,
        relative-path absolutization, nonexistent-path rejection,
        idempotent clear, two-session isolation
  [New] tests/fixtures/plan-canon/{canonical,legacy}/ — minimal plan
        fixtures referenced by the new tests"
  ```

---

### Phase 2: r-plan rewrite — write to docs/plans/, mandatory commit, --resume <path>

Rewrite `canonical/commands/r-plan.md` so plan creation writes the named plan to `docs/plans/{YYYY-MM-DD}-{topic}-plan.md`, calls `rdf_set_active_plan`, and commits the plan file mandatorily. Add `--resume <path>` flag for fresh-checkout takeover. Resume Protocol reads via resolver. Add three adapter-regen tests verifying the new canonical wording.

**Files:**
- Modify: `canonical/commands/r-plan.md`
- Modify: `tests/adapter.bats` (add 3 new `@test` blocks for the new canonical content)

- **Mode**: serial-agent
- **Accept**:
  - `grep -n 'docs/plans/{' canonical/commands/r-plan.md | wc -l` returns ≥ 3
  - `grep -n 'Commit the plan? \[Y/n\]' canonical/commands/r-plan.md` returns no hits (replaced with mandatory commit)
  - `grep -nE 'rdf_active_plan_path|rdf_set_active_plan' canonical/commands/r-plan.md` returns ≥ 3
  - `grep -n 'resume <path>' canonical/commands/r-plan.md` returns ≥ 1
- **Test**: `tests/adapter.bats` — existing canonical-regen tests still pass; new assertions verify docs/plans/ pattern present.
- **Edge cases**: Filename collision (append `-v2`); `docs/plans/` directory missing (mkdir -p); `--resume` with no pointer/no PLAN.md (graceful error); `--resume <path>` with nonexistent path (validation error before flow start).
- **Regression-case**: `tests/adapter.bats::@test "r-plan canonical references rdf_active_plan_path"`

- [ ] **Step 1: Rewrite argument detection block (lines 9-32)**

  Add the new `--resume <path>` form to the argument list. Insert into the code block at line 11-17:

  ```
  /r-plan                          — auto-detect most recent spec in docs/specs/
  /r-plan docs/specs/foo.md        — file path (contains / or ends with .md)
  /r-plan https://github.com/...   — GitHub URL (starts with http/https)
  /r-plan #42                      — issue shorthand (# + digits)
  /r-plan --resume                 — resume interrupted plan (resolved via rdf_active_plan_path)
  /r-plan --resume <path>          — set pointer to <path> and resume
  ```

  Add to argument detection logic block (after line 23 `--resume`):

  - `--resume <path>` (two tokens) → validate `<path>` exists; `rdf_set_active_plan "<path>"`; enter Resume Protocol

- [ ] **Step 2: Rewrite Resume Protocol (lines 67-89)**

  Replace the heading at line 67:

  ```
  If `--resume` is specified or PLAN.md exists with incomplete phases:
  ```

  with:

  ```
  If `--resume` (with or without `<path>`) is specified, OR if `rdf_active_plan_path` returns a plan with incomplete phases:
  ```

  Replace line 71 "Read existing PLAN.md" with:

  ```
  1. Source `state/rdf-bus.sh`; `rdf_session_init`. Read the active plan:
     `plan_path="$(rdf_active_plan_path)"`. If `--resume <path>` was given,
     call `rdf_set_active_plan "<path>"` first.
  ```

  Replace line 88 "delete PLAN.md" with "remove the pointer (`rdf_clear_active_plan`) and begin from Step 1."

- [ ] **Step 3: Insert new Step 2.0 (Determine Plan File Path) before line 132**

  Insert before `## Step 2: Write PLAN.md` (line 132):

  ```markdown
  ## Step 2.0: Determine Plan File Path

  Derive the plan filename:

  ```bash
  TODAY="$(command date +%Y-%m-%d)"
  TOPIC="{slugified topic from spec or user input}"
  PLAN_FILE="docs/plans/${TODAY}-${TOPIC}-plan.md"
  ```

  If `PLAN_FILE` already exists, append a disambiguating suffix (`-v2`,
  `-v3`, ...) — never overwrite a committed plan.

  Create `docs/plans/` if absent: `command mkdir -p docs/plans/`.

  ---
  ```

- [ ] **Step 4: Rename Step 2 heading (line 132)**

  Change `## Step 2: Write PLAN.md` to `## Step 2: Write Plan File`.

- [ ] **Step 5: Update Step 2.7 reviewer dispatch block (lines 374-399)**

  Replace `PLAN.md` references in the validator prose with "the plan file" / "$PLAN_FILE". The schema validator helper signature `rdf_parse_phase_scope <plan> <N>` (which appears in plan-schema.md) remains unchanged.

- [ ] **Step 6: Rewrite Step 3.1 review dispatch block (lines 455-456)**

  Change:
  ```
  File: PLAN.md
  Mode: challenge
  ```
  to:
  ```
  File: $PLAN_FILE  (the docs/plans/{date}-{topic}-plan.md path from Step 2.0)
  Mode: challenge
  ```

- [ ] **Step 7: Rewrite Step 3.2 summary text (line 467)**

  Change:
  ```
  Plan written to: PLAN.md
  ```
  to:
  ```
  Plan written to: $PLAN_FILE
  ```

- [ ] **Step 8: Rewrite Step 3.3 (lines 479-493) — mandatory commit + set pointer**

  Replace the entire Step 3.3 block:

  ```markdown
  ### 3.3 Commit Planning Artifacts (mandatory)

  Plans are committed at creation. Stage the plan file and commit:

  ```bash
  git add "$PLAN_FILE"
  # If the spec is not yet committed:
  git diff --cached --name-only | grep -q docs/specs/ || git add "$SPEC_PATH"
  git commit -m "Add {topic} implementation plan

  [New] $PLAN_FILE — {N}-phase implementation plan"
  ```

  The plan is now a tracked artifact and cannot be silently overwritten by a subsequent session. This is the central guarantee of the post-3.1.2 plan model.

  ### 3.3.1 Set the Active-Plan Pointer

  After committing:

  ```bash
  source state/rdf-bus.sh
  rdf_set_active_plan "$PLAN_FILE"
  ```

  This records the plan as active for the current session. The pointer file `.rdf/active-plan-${RDF_SESSION_ID}` is gitignored.
  ```

- [ ] **Step 9: Rewrite Completion Handoff (lines 502-505)**

  Change:
  ```
  > **Plan ready** — `PLAN.md` ({N} phases)
  ```
  to:
  ```
  > **Plan ready** — `$PLAN_FILE` ({N} phases)
  ```

- [ ] **Step 10: Add three adapter-regen tests to `tests/adapter.bats`**

  Append three `@test` blocks at end of file (before the final `}` if pattern matches, or after the last existing `@test`):

  ```bash
  @test "r-plan canonical names docs/plans path" {
      run grep -c 'docs/plans/{' "$RDF_SRC/canonical/commands/r-plan.md"
      [ "$status" -eq 0 ]
      [ "$output" -ge 3 ]
  }

  @test "r-plan Step 3.3 marks commit as mandatory" {
      # Should NOT contain the optional [Y/n] prompt — commit is mandatory
      run grep -c 'Commit the plan? \[Y/n\]' "$RDF_SRC/canonical/commands/r-plan.md"
      [ "$output" = "0" ]
  }

  @test "r-plan Resume Protocol calls rdf_active_plan_path" {
      run grep -c 'rdf_active_plan_path' "$RDF_SRC/canonical/commands/r-plan.md"
      [ "$status" -eq 0 ]
      [ "$output" -ge 1 ]
  }
  ```

- [ ] **Step 11: Verify**

  ```bash
  grep -c 'docs/plans/{' canonical/commands/r-plan.md
  # expect: >= 3

  grep -c 'Commit the plan? \[Y/n\]' canonical/commands/r-plan.md
  # expect: 0

  grep -cE 'rdf_active_plan_path|rdf_set_active_plan' canonical/commands/r-plan.md
  # expect: >= 3

  grep -c 'resume <path>' canonical/commands/r-plan.md
  # expect: >= 1

  grep -c '^@test "r-plan canonical names docs/plans path"\|^@test "r-plan Step 3.3 marks commit as mandatory"\|^@test "r-plan Resume Protocol calls rdf_active_plan_path"' tests/adapter.bats
  # expect: 3

  make -C tests test 2>&1 | tail -10
  # expect: no "not ok"; the three new adapter tests pass after canonical update
  ```

- [ ] **Step 12: Commit**

  ```bash
  git add canonical/commands/r-plan.md tests/adapter.bats
  git commit -m "Rewrite /r-plan to write plans to docs/plans/ with mandatory commit

  [Change] canonical/commands/r-plan.md — Step 2 writes plan to
        docs/plans/{YYYY-MM-DD}-{topic}-plan.md instead of root PLAN.md.
        Step 2.0 (new) derives filename with collision suffixes (-v2, -v3).
        Step 3.3 commit becomes mandatory (no longer [Y/n] prompt) — plans
        are tracked artifacts at creation. Step 3.3.1 (new) sets the
        active-plan pointer via rdf_set_active_plan. Resume Protocol reads
        active plan via rdf_active_plan_path. New --resume <path> form sets
        pointer to <path> for fresh-checkout takeover."
  ```

---

### Phase 3: Command consumers route through resolver

Wire `rdf_active_plan_path` through the seven non-r-plan commands (r-build, r-ship, r-save, r-status, r-vpe, r-start, r-refresh). All edits are wording changes: "PLAN.md" → "active plan" / "the plan file"; sourcing snippets reference `rdf_active_plan_path` where the command performs a read.

**Files:**
- Modify: `canonical/commands/r-build.md`
- Modify: `canonical/commands/r-ship.md`
- Modify: `canonical/commands/r-save.md`
- Modify: `canonical/commands/r-status.md`
- Modify: `canonical/commands/r-vpe.md`
- Modify: `canonical/commands/r-start.md`
- Modify: `canonical/commands/r-refresh.md`
- Modify: `tests/adapter.bats` (add 2 adapter-regen tests for consumer wiring + r-ship clear-pointer)

- **Mode**: serial-agent
- **Accept**:
  - `grep -lE 'rdf_active_plan_path' canonical/commands/r-{build,ship,save,status,start,refresh}.md | wc -l` returns 6 (r-vpe is output-text only — no resolver call)
  - `grep -n 'rdf_clear_active_plan' canonical/commands/r-ship.md` returns ≥ 1
  - All 7 files pass adapter regen: `tests/adapter.bats` exits 0
- **Test**: `tests/adapter.bats` — adapter regen of these files matches expected output.
- **Edge cases**: r-build with no active plan (resolver returns "", command errors with "No active plan; run /r-plan"); r-ship with phases incomplete (existing logic preserved); r-status with no plan (existing "No active plan." text preserved).
- **Regression-case**: `tests/adapter.bats::@test "consumers route through rdf_active_plan_path"`

- [ ] **Step 1: Update `canonical/commands/r-build.md` §1 (Locate and Validate PLAN.md)**

  Replace lines 18-46 (Section 1) with resolver-based read:

  ```markdown
  ### 1. Locate and Validate the Active Plan

  - Source `state/rdf-bus.sh` and call `rdf_session_init`.
  - `plan_path="$(rdf_active_plan_path)"` — resolves via three-tier
    fallback (session pointer → un-suffixed pointer → root PLAN.md).
  - If `$plan_path` is empty, report error and stop:
    "No active plan found. Create one with /r-plan or write it manually,
     then run /r-plan --resume <path> to set the pointer."
  - Read `$plan_path` as the plan input from here forward.
  ```

  Also update §2b worktree dispatch references (search for `PLAN.md` in that section) to use `$plan_path` or "the active plan".

- [ ] **Step 2: Update `canonical/commands/r-ship.md`**

  Replace lines 46-48 with:

  ```markdown
  - Source `state/rdf-bus.sh`; `rdf_session_init`. Resolve the active
    plan: `plan_path="$(rdf_active_plan_path)"`.
  - Read `$plan_path` — verify ALL phases are marked complete.
  - If no active plan resolves, skip this check (ad-hoc release).
  ```

  After the successful release commit step, append:

  ```markdown
  ### Clear the active-plan pointer

  After the release tag/commit lands, clear the pointer:

  ```bash
  source state/rdf-bus.sh
  rdf_clear_active_plan
  ```

  The plan file in `docs/plans/` is retained as historical record; only
  the session-scoped pointer is removed so the next planning session
  starts clean.
  ```

- [ ] **Step 3: Update `canonical/commands/r-save.md` §2 (Sync PLAN.md)**

  Replace line 93-95:

  ```markdown
  ### 2. Sync the Plan with Git

  Source `state/rdf-bus.sh`; `rdf_session_init`. Resolve the plan:
  `plan_path="$(rdf_active_plan_path)"`. If empty, skip.
  ```

  Replace remaining `PLAN.md` occurrences in §2 (around lines 95-125) with `$plan_path`.

- [ ] **Step 4: Update `canonical/commands/r-status.md`**

  Replace lines 17-25 with resolver-driven read:

  ```markdown
  Source `state/rdf-bus.sh`; `rdf_session_init`.
  `plan_path="$(rdf_active_plan_path)"`. If empty, display: "No active
  plan. Run /r-plan to create one."
  ```

  Update output text at line 85 to show `$plan_path`. Update line 96 table to show the resolved path. Update lines 113-117 (Build derivation) to read from `$plan_path`.

- [ ] **Step 5: Update `canonical/commands/r-vpe.md`**

  Lines 147-152 and 200: replace literal `PLAN.md` in output text examples with `$plan_path` (the named file). No resolver call needed — VPE invokes /r-plan which sets the pointer; VPE's display text just shows what /r-plan reported.

- [ ] **Step 6: Update `canonical/commands/r-start.md`**

  Replace lines 172-174 and 228 references to `PLAN.md` with resolver-driven reads. Specifically, at line 228:

  ```markdown
  - Do NOT read full plan prose — extract phase names and statuses
    from the resolver-returned path.
  ```

  Add a sourcing snippet at line ~142 (near other rdf-bus sourcing): `source state/rdf-bus.sh; rdf_session_init; plan_path="$(rdf_active_plan_path)"`.

- [ ] **Step 7: Update `canonical/commands/r-refresh.md`**

  Replace lines 10, 176, 185, 261 references to `PLAN.md`. The 5b section header at line 179 becomes "Refresh the Active Plan". Lines 222-265 (issue cross-ref) — note that this section's status parsing becomes a no-op for canonical plans (acknowledged in spec §9); add an INFO log: "issue cross-reference: phase-status parsing inert for canonical plans (status lives in .rdf/work-output/)".

- [ ] **Step 8: Add two adapter-regen tests to `tests/adapter.bats`**

  Append two `@test` blocks at end of file:

  ```bash
  @test "consumers route through rdf_active_plan_path" {
      # All 6 read-side consumers reference the resolver
      local count
      count=$(grep -lE 'rdf_active_plan_path' \
          "$RDF_SRC/canonical/commands/r-build.md" \
          "$RDF_SRC/canonical/commands/r-ship.md" \
          "$RDF_SRC/canonical/commands/r-save.md" \
          "$RDF_SRC/canonical/commands/r-status.md" \
          "$RDF_SRC/canonical/commands/r-start.md" \
          "$RDF_SRC/canonical/commands/r-refresh.md" 2>/dev/null | wc -l)
      [ "$count" -eq 6 ]
  }

  @test "r-ship calls rdf_clear_active_plan" {
      run grep -c 'rdf_clear_active_plan' "$RDF_SRC/canonical/commands/r-ship.md"
      [ "$status" -eq 0 ]
      [ "$output" -ge 1 ]
  }
  ```

- [ ] **Step 9: Verify**

  ```bash
  grep -lE 'rdf_active_plan_path' canonical/commands/r-{build,ship,save,status,start,refresh}.md | wc -l
  # expect: 6

  grep -n 'rdf_clear_active_plan' canonical/commands/r-ship.md
  # expect: >= 1 hit

  grep -rn '\bPLAN\.md\b' canonical/commands/r-{build,ship,save,status,vpe,start,refresh}.md | \
      grep -vE 'legacy|fallback|LEGACY' | wc -l
  # expect: <= 5  (remaining mentions are output-text or legacy-context)

  make -C tests test 2>&1 | tail -10
  # expect: 2 new adapter tests pass; no "not ok"
  ```

- [ ] **Step 10: Commit**

  ```bash
  git add canonical/commands/r-build.md canonical/commands/r-ship.md \
          canonical/commands/r-save.md canonical/commands/r-status.md \
          canonical/commands/r-vpe.md canonical/commands/r-start.md \
          canonical/commands/r-refresh.md tests/adapter.bats
  git commit -m "Route command consumers through rdf_active_plan_path

  [Change] canonical/commands/r-build.md — §1 resolves active plan via
        rdf_active_plan_path; error path references /r-plan --resume <path>
  [Change] canonical/commands/r-ship.md — phase-complete check reads
        resolver; adds rdf_clear_active_plan call after successful release
  [Change] canonical/commands/r-save.md — §2 syncs the resolver-returned
        plan path; skips when no plan resolved
  [Change] canonical/commands/r-status.md — plan-state derivation reads
        resolver; display shows named plan path
  [Change] canonical/commands/r-vpe.md — output text shows named plan path
  [Change] canonical/commands/r-start.md — plan preview reads resolver
  [Change] canonical/commands/r-refresh.md — §5b reads resolver; INFO log
        notes phase-status parsing is inert for canonical plans"
  ```

---

### Phase 4: Agent + reference content updates

Update agent and reference files to use resolver language. The substantive change is `canonical/agents/dispatcher.md` worktree-sync (line 70 `command cp` call). Other edits are wording changes.

**Files:**
- Modify: `canonical/agents/dispatcher.md`
- Modify: `canonical/agents/engineer.md`
- Modify: `canonical/reference/framework.md`
- Modify: `canonical/reference/session-safety.md`
- Modify: `canonical/reference/progress-tracking.md`
- Modify: `canonical/reference/plan-schema.md`
- Modify: `tests/adapter.bats` (add 1 adapter-regen test for dispatcher worktree sync)

- **Mode**: serial-agent
- **Accept**:
  - `grep -n 'rdf_active_plan_path' canonical/agents/dispatcher.md` returns ≥ 2 (Load + worktree sync)
  - `grep -c 'PLAN\.md' canonical/agents/dispatcher.md` returns ≤ 5 (down from 13 — remaining mentions explain legacy fallback)
  - `grep -n 'Status markers' canonical/reference/framework.md | wc -l` returns ≥ 1; section now references `.rdf/work-output/` as storage
- **Test**: `tests/adapter.bats` — adapter regen of these files matches expected output.
- **Edge cases**: Worktree gets pointer from main repo's `.rdf/active-plan-$SESSION` (dispatcher writes a new pointer inside worktree pointing to worktree-local plan copy); legacy projects with no active-plan pointer (dispatcher falls back to root PLAN.md copy).
- **Regression-case**: `tests/adapter.bats::@test "dispatcher worktree sync references rdf_active_plan_path"`

- [ ] **Step 1: Rewrite `canonical/agents/dispatcher.md` Load step (lines 12-13)**

  Replace:
  ```markdown
  ### Load
  - Read PLAN.md — identify target phase (argument or next pending)
  ```
  with:
  ```markdown
  ### Load
  - Source `state/rdf-bus.sh`; `rdf_session_init`.
  - Resolve plan: `plan_path="$(rdf_active_plan_path)"`. Error and stop
    if empty.
  - Read `$plan_path` — identify target phase (argument or next pending)
  ```

- [ ] **Step 2: Rewrite `canonical/agents/dispatcher.md` Worktree sync (lines 55-92)**

  Replace the entire "Worktree Pre-Commit Hook Installation (and PLAN.md sync)" block. Key changes:

  ```markdown
  ### Worktree Pre-Commit Hook Installation (and active-plan sync)

  When dispatched into a worktree (`PARALLEL_BATCH: true` with
  `PROJECT_ROOT` set to a worktree path), perform two installation steps
  before any engineer subagent is dispatched:

  **(a) Sync the active plan from main repo into worktree.**
  Worktrees check out the HEAD-committed working tree. The plan in
  `docs/plans/` is committed and thus appears in the worktree
  automatically. Older legacy projects may still have a root `PLAN.md`
  (gitignored) that does NOT propagate — copy it explicitly if the
  resolver returned a legacy path.

  ```bash
  source "${PROJECT_ROOT_MAIN}/state/rdf-bus.sh"
  rdf_session_init
  _main_plan="$(rdf_active_plan_path "$PROJECT_ROOT_MAIN")"
  if [[ -z "$_main_plan" ]]; then
      echo "dispatcher: main repo has no active plan; cannot proceed" >&2
      exit 1
  fi
  _rel_path="${_main_plan#$PROJECT_ROOT_MAIN/}"
  command mkdir -p "${PROJECT_ROOT}/$(command dirname "$_rel_path")"
  command cp "$_main_plan" "${PROJECT_ROOT}/${_rel_path}"
  # Set the worktree-local pointer to the worktree-local copy
  rdf_set_active_plan "${PROJECT_ROOT}/${_rel_path}" "$PROJECT_ROOT"
  ```

  This sync is one-shot at worktree creation; subsequent operator edits
  to the main-repo plan are not reflected in worktrees. If the operator
  changes the plan mid-build, dispatch must be re-invoked.

  **(b) Install the pre-commit hook.** (unchanged — see Wave A)
  ```

- [ ] **Step 3: Rewrite `canonical/agents/dispatcher.md` Post-merge scope eval (line 110)**

  Replace:
  ```bash
  eval "$(rdf_parse_phase_scope PLAN.md $N)"
  ```
  with:
  ```bash
  eval "$(rdf_parse_phase_scope "$(rdf_active_plan_path)" $N)"
  ```

- [ ] **Step 4: Update `canonical/agents/dispatcher.md` Red/Green Decision (line 325) and Commit Strategy (line 475)**

  Line 325: change "update PLAN.md" to "update the phase result file in `.rdf/work-output/`" (clarify status doesn't live in plan body).

  Line 475: change "from PLAN.md phase description" to "from the active-plan phase description".

- [ ] **Step 5: Update `canonical/agents/engineer.md` (line 30)**

  Replace "Compute scope by reading PLAN.md for your phase" with "Compute scope by reading the active plan (resolved via `rdf_active_plan_path` in `state/rdf-bus.sh`) for your phase".

- [ ] **Step 6: Update `canonical/reference/framework.md`**

  Lines 55-62 (Status markers): keep the marker list but prepend a clarifying paragraph:

  ```markdown
  **PLAN.md status markers** (semantic states):

  These are the canonical state names. They are NOT stored inline in the
  plan body — committed plans in `docs/plans/` carry no status markers.
  Status lives in `.rdf/work-output/phase-N-result-${SESSION}.md` (engineer
  STATUS lines) and is derived by `r-status`, `r-save`, `r-ship` via git
  log cross-reference and result-file inspection.
  ```

  Line 235 inventory table: replace "PLAN.md" with "active plan (resolver-driven)".

- [ ] **Step 7: Update `canonical/reference/session-safety.md`**

  Lines 15, 73: replace `PLAN.md` references with "the active plan". Add a line:

  ```markdown
  Active plan is resolved via `rdf_active_plan_path` (state/rdf-bus.sh) —
  three-tier fallback: session pointer → un-suffixed pointer → root
  PLAN.md legacy.
  ```

- [ ] **Step 8: Update `canonical/reference/progress-tracking.md` and `canonical/reference/plan-schema.md`**

  `progress-tracking.md`: single-line reference at the existing PLAN.md mention — change to "the plan file (resolved via `rdf_active_plan_path`)".

  `plan-schema.md` lines 185, 187, 317, 319: three-call-site enforcement table — change "After PLAN.md write" → "After plan write" and "After PLAN.md read" → "After plan read".

- [ ] **Step 9: Add one adapter-regen test to `tests/adapter.bats`**

  ```bash
  @test "dispatcher worktree sync references rdf_active_plan_path" {
      run grep -c 'rdf_active_plan_path' "$RDF_SRC/canonical/agents/dispatcher.md"
      [ "$status" -eq 0 ]
      [ "$output" -ge 2 ]
  }
  ```

- [ ] **Step 10: Verify**

  ```bash
  grep -c 'rdf_active_plan_path' canonical/agents/dispatcher.md
  # expect: >= 2

  grep -c 'PLAN\.md' canonical/agents/dispatcher.md
  # expect: <= 5

  grep -c 'PLAN\.md' canonical/reference/framework.md
  # expect: <= 2  (only the "Status markers" header references)

  make -C tests test 2>&1 | tail -10
  # expect: 1 new adapter test passes; no "not ok"
  ```

- [ ] **Step 11: Commit**

  ```bash
  git add canonical/agents/dispatcher.md canonical/agents/engineer.md \
          canonical/reference/framework.md canonical/reference/session-safety.md \
          canonical/reference/progress-tracking.md canonical/reference/plan-schema.md \
          tests/adapter.bats
  git commit -m "Route agent + reference content through rdf_active_plan_path

  [Change] canonical/agents/dispatcher.md — Load resolves plan via
        rdf_active_plan_path; Worktree sync sources rdf-bus.sh from main
        repo, copies resolver result, sets worktree-local pointer to
        worktree-local copy; post-merge scope eval pipes resolver to
        rdf_parse_phase_scope; clarifies status lives in .rdf/work-output/
        not in plan body
  [Change] canonical/agents/engineer.md — scope-read prose references
        resolver helper
  [Change] canonical/reference/framework.md — status-markers section
        clarifies storage in .rdf/work-output/, not in plan body;
        inventory references resolver
  [Change] canonical/reference/session-safety.md — plan sync table notes
        resolver-driven read with three-tier fallback
  [Change] canonical/reference/progress-tracking.md — single-line
        reference update
  [Change] canonical/reference/plan-schema.md — three-call-site
        enforcement table rewords PLAN.md → plan"
  ```

---

### Phase 5: lib + state consumers wired through resolver

Wire `rdf_active_plan_path` through `lib/cmd/refresh.sh`, `state/rotate-work-output.sh`, and `state/git-hooks/pre-commit`. Update `lib/cmd/dispatch.sh` usage examples. Add an additive line to `lib/cmd/doctor.sh:_check_plan` to also report pointer state.

**Files:**
- Modify: `lib/cmd/refresh.sh`
- Modify: `state/rotate-work-output.sh`
- Modify: `state/git-hooks/pre-commit`
- Modify: `lib/cmd/dispatch.sh`
- Modify: `lib/cmd/doctor.sh`
- Modify: `tests/plan-canonicalization.bats` (append 1 orphan-refs test — Goal 10 from spec)

- **Mode**: serial-agent
- **Accept**:
  - `grep -n 'RDF_STATE_DIR.*rdf-bus' lib/cmd/refresh.sh` returns 1 hit
  - `grep -nE 'dirname.*\"\$0\".*rdf-bus' state/rotate-work-output.sh` returns 1 hit
  - `grep -n 'rdf_active_plan_path' state/git-hooks/pre-commit` returns ≥ 1
  - `bash -n state/git-hooks/pre-commit lib/cmd/refresh.sh state/rotate-work-output.sh` exits 0
  - `shellcheck state/git-hooks/pre-commit lib/cmd/refresh.sh state/rotate-work-output.sh` exits 0 (with existing inline disables preserved)
  - `make -C tests test 2>&1 | tail -5` passes (no new "not ok"); existing `tests/rdf-bus.bats` pre-commit hook tests still pass against updated ancestor walk
- **Test**: `tests/rdf-bus.bats` (existing) — pre-commit hook tests pass against updated ancestor walk; `tests/plan-canonicalization.bats` — resolver integration via fixture rdf-bus invocations.
- **Edge cases**: `refresh.sh` invoked with project having no active plan (existing `if [[ -f PLAN.md ]]` guard preserves skip semantics — adapt to `[[ -z "$plan_path" ]]`); `rotate-work-output.sh` against a non-RDF project (resolver returns 1, no protect-list extracted, full prune proceeds); pre-commit hook in non-worktree branch (still exits 0 — no phase number derived).
- **Regression-case**: `tests/rdf-bus.bats::@test "pre-commit hook accepts in-scope commit"` — existing test; survives the P5 ancestor-walk change because the fixture (`_setup_fixture_repo` at tests/rdf-bus.bats:71-86) commits both `state/rdf-bus.sh` and `PLAN.md` into the fixture repo. P5's new ancestor walk finds `state/rdf-bus.sh` (line 79 places it there). The resolver then returns `PLAN.md` via legacy fallback (line 80 creates it). Both the old and new code paths produce the same fixture-observable behavior — the test is unchanged-but-revalidated.

- [ ] **Step 1: Update `lib/cmd/refresh.sh` source path and resolver calls**

  After the existing sourcing block near the top (line ~10), add:

  ```bash
  # shellcheck source=/dev/null
  source "${RDF_STATE_DIR}/rdf-bus.sh"
  ```

  Then replace the four `${project_path}/PLAN.md` occurrences (around lines 143, 158, 223, 225):

  ```bash
  # Before:
  if [[ ! -f "${project_path}/PLAN.md" ]]; then
      rdf_warn "no PLAN.md found — skipping plan refresh"
      return 0
  fi

  # After:
  local plan_path
  plan_path="$(rdf_active_plan_path "$project_path")" || true
  if [[ -z "$plan_path" ]]; then
      rdf_warn "no active plan found — skipping plan refresh"
      return 0
  fi
  ```

  Replace `${project_path}/PLAN.md` reads with `$plan_path` throughout the function.

- [ ] **Step 2: Update `state/rotate-work-output.sh` source path and resolver call**

  Insert near the top, after `set -euo pipefail`:

  ```bash
  # shellcheck source=/dev/null
  source "$(command dirname "$0")/rdf-bus.sh"
  rdf_session_init
  ```

  Replace lines 43-49:

  ```bash
  # Before:
  _plan_file="${_project_root}/PLAN.md"
  if [[ -f "$_plan_file" ]]; then
      _active_basenames="$(grep -oE '[a-zA-Z0-9_-]+\.md' "$_plan_file" 2>/dev/null || true)"
  fi

  # After:
  _plan_file="$(rdf_active_plan_path "$_project_root")" || _plan_file=""
  if [[ -n "$_plan_file" && -f "$_plan_file" ]]; then
      _active_basenames="$(grep -oE '[a-zA-Z0-9_-]+\.md' "$_plan_file" 2>/dev/null || true)" # grep exits 1 when no match; both outcomes are valid
  fi
  ```

- [ ] **Step 3: Update `state/git-hooks/pre-commit` ancestor walk and resolver call**

  Replace lines 14-24 (ancestor walk):

  ```bash
  # Before:
  # Locate project root (nearest ancestor with PLAN.md)
  _proj=""
  _dir="$(command pwd)"
  while [[ "$_dir" != "/" ]]; do
      [[ -f "$_dir/PLAN.md" ]] && { _proj="$_dir"; break; }
      _dir="$(command dirname "$_dir")"
  done
  if [[ -z "$_proj" ]]; then
      echo "rdf pre-commit: PLAN.md not found in any ancestor; skipping scope check" >&2
      exit 0
  fi

  # After:
  # Locate project root (nearest ancestor with state/rdf-bus.sh — the RDF anchor)
  _proj=""
  _dir="$(command pwd)"
  while [[ "$_dir" != "/" ]]; do
      [[ -f "$_dir/state/rdf-bus.sh" ]] && { _proj="$_dir"; break; }
      _dir="$(command dirname "$_dir")"
  done
  if [[ -z "$_proj" ]]; then
      echo "rdf pre-commit: state/rdf-bus.sh not found in any ancestor; skipping scope check" >&2
      exit 0
  fi
  ```

  Replace line 48 (parse phase scope):

  ```bash
  # Before:
  eval "$(rdf_parse_phase_scope "$_proj/PLAN.md" "$_phase_n")"

  # After:
  _plan="$(rdf_active_plan_path "$_proj")"
  if [[ -z "$_plan" ]]; then
      echo "rdf pre-commit: no active plan found; skipping scope check" >&2
      exit 0
  fi
  eval "$(rdf_parse_phase_scope "$_plan" "$_phase_n")"
  ```

  Update the error message at line 50 ("Phase $_phase_n not found in PLAN.md") to "Phase $_phase_n not found in $_plan".

- [ ] **Step 4: Update `lib/cmd/dispatch.sh` usage examples**

  Lines 50-53 — replace `PLAN.md` in the usage examples:

  ```
  # Before:
  rdf dispatch agent engineer se-implement 3 /path/to/project /path/to/PLAN.md

  # After:
  rdf dispatch agent engineer se-implement 3 /path/to/project /path/to/active-plan.md
  ```

  No code change — this is the usage docstring only.

- [ ] **Step 5: Add diagnostic line to `lib/cmd/doctor.sh:_check_plan`**

  Around line 213 (after the existing OK result emission), add:

  ```bash
  # Also surface pointer state for the active session
  if [[ -n "${RDF_SESSION_ID:-}" && -f "${path}/.rdf/active-plan-${RDF_SESSION_ID}" ]]; then
      _add_result "plan-pointer" "$_OK" "session pointer present"
  elif [[ -f "${path}/.rdf/active-plan" ]]; then
      _add_result "plan-pointer" "$_OK" "un-suffixed pointer present"
  else
      _add_result "plan-pointer" "$_OK" "no pointer (legacy fallback or no plan)"
  fi
  ```

  This is additive — no behavior change to the existing check.

- [ ] **Step 6: Append orphan-refs test to `tests/plan-canonicalization.bats` (Goal 10 from spec)**

  After all consumer rewrites have landed (P2-P5 complete), the only remaining `PLAN.md` references in canonical/lib/state should be in legacy/fallback/output-text context. Append:

  ```bash
  @test "canonical PLAN.md references are scoped to legacy/fallback context" {
      # After full migration, every PLAN.md mention in canonical/lib/state
      # must be in legacy-fallback or output-text context (not a hardcoded
      # read path). Use word-boundary grep to catch all forms.
      local hits
      hits=$(grep -rn '\bPLAN\.md\b' \
          "$RDF_SRC/canonical/" "$RDF_SRC/lib/" "$RDF_SRC/state/" 2>/dev/null | \
          grep -vE 'legacy|fallback|LEGACY|FALLBACK|output-text' | wc -l)
      # Allow up to 10 residual mentions for status-marker reference and
      # transitional banner text (output-text only — not read paths).
      [ "$hits" -le 10 ]
  }
  ```

  Also bump the P1 Accept count from 13 to 14 in the planner's notes (already accounted for in this step — the test is added *after* P1, so P1's grep -c =13 remains correct at P1 completion; P5 brings the file up to 14).

- [ ] **Step 7: Verify**

  ```bash
  bash -n state/git-hooks/pre-commit lib/cmd/refresh.sh state/rotate-work-output.sh lib/cmd/dispatch.sh lib/cmd/doctor.sh
  # expect: no output, exit 0

  shellcheck state/git-hooks/pre-commit lib/cmd/refresh.sh state/rotate-work-output.sh lib/cmd/dispatch.sh lib/cmd/doctor.sh
  # expect: no output beyond existing pre-existing warnings, exit 0

  grep -n 'RDF_STATE_DIR.*rdf-bus' lib/cmd/refresh.sh
  # expect: 1 hit

  grep -nE 'dirname[^|]*\$0[^|]*rdf-bus' state/rotate-work-output.sh
  # expect: 1 hit

  grep -n 'rdf_active_plan_path' state/git-hooks/pre-commit
  # expect: >= 1

  grep -c '^@test "canonical PLAN.md references are scoped to legacy/fallback context"' tests/plan-canonicalization.bats
  # expect: 1

  make -C tests test 2>&1 | tee /tmp/test-rdf-P5-debian12.log | tail -10
  # expect: no "not ok"; rdf-bus.bats pre-commit tests pass; new orphan-refs test passes
  ```

- [ ] **Step 8: Commit**

  ```bash
  git add lib/cmd/refresh.sh state/rotate-work-output.sh \
          state/git-hooks/pre-commit lib/cmd/dispatch.sh lib/cmd/doctor.sh \
          tests/plan-canonicalization.bats
  git commit -m "Route lib/state consumers through rdf_active_plan_path

  [Change] lib/cmd/refresh.sh — sources rdf-bus.sh via RDF_STATE_DIR;
        _refresh_scope_plan and _refresh_scope_github read plan via
        rdf_active_plan_path; skip semantics preserved when empty
  [Change] state/rotate-work-output.sh — sources rdf-bus.sh via sibling
        path (\$(dirname \"\$0\")/rdf-bus.sh); active-basename extraction
        uses resolver-returned plan
  [Change] state/git-hooks/pre-commit — ancestor walk searches for
        state/rdf-bus.sh as the RDF anchor; plan path resolved via
        rdf_active_plan_path; skip semantics preserved when empty
  [Change] lib/cmd/dispatch.sh — usage examples reference named plan
        paths instead of literal PLAN.md
  [Change] lib/cmd/doctor.sh:_check_plan — additive diagnostic for
        active-plan pointer state"
  ```

---

### Phase 6: Migration — .gitignore, untrack PLAN.md, adapter regen

Apply local-and-tree migration: add the four plan/pointer patterns to `.gitignore`, untrack the stale 3.0.3 `PLAN.md` snapshot, regenerate adapter output, verify drift-free deployment to `~/.claude/`.

**Files:**
- Modify: `.gitignore`
- Modify: `(git index)` — `git rm --cached PLAN.md`
- Modify: `adapters/claude-code/output/` — regen output (may be empty if P2-P5 captured everything)
- Modify: `tests/plan-canonicalization.bats` (append 1 gitignore test — Goal 6 from spec)

- **Mode**: serial-context
- **Accept**:
  - `git ls-files --error-unmatch PLAN.md 2>&1 | head -1` reports "did not match any file(s)"
  - `grep -cE '^PLAN(\*|-\*)?\.md$|^\.rdf/active-plan' .gitignore` returns 4
  - `rdf doctor --all 2>&1 | grep -c FAIL` returns 0
  - `git check-ignore docs/plans/2026-05-15-plan-canonicalization-plan.md; echo $?` returns exit 1 (plan IS committable)
  - `make -C tests test` passes — including the new gitignore test
  - Adapter regen runs cleanly. Either `git status --short adapters/claude-code/output/` is clean (P2-P5 captured all canonical edits) OR shows modified files (regen produced new content); both outcomes are acceptable so long as `rdf doctor --all` reports zero FAILs.
- **Test**: `rdf doctor --all` and `make -C tests test` both pass.
- **Edge cases**: `PLAN.md` already untracked on a fresh clone (git rm errors — guard with `git ls-files --error-unmatch ... 2>&1 && git rm`); `.gitignore` already contains a duplicate (idempotent append; verify with grep -c); adapter regen produces no diff (acceptable — means earlier phases captured everything).
- **Regression-case**: N/A — refactor — gitignore + untrack + adapter regen are git-tree and build-output operations with no behavioral surface; resolver behavior is covered by `tests/plan-canonicalization.bats` (P1).

- [ ] **Step 1: Append four lines to `.gitignore`**

  ```bash
  {
      printf '\n# Plans — root location is transitional; canonical is docs/plans/\n'
      printf 'PLAN.md\nPLAN*.md\nPLAN-*.md\n'
      printf '\n# Active-plan pointer (resolver state)\n'
      printf '.rdf/active-plan*\n'
  } >> .gitignore
  ```

  Verify:

  ```bash
  grep -cE '^PLAN(\*|-\*)?\.md$|^\.rdf/active-plan' .gitignore
  # expect: 4
  ```

- [ ] **Step 2: Untrack stale `PLAN.md`**

  ```bash
  git ls-files --error-unmatch PLAN.md >/dev/null 2>&1 && git rm --cached PLAN.md
  ```

  Verify:

  ```bash
  git ls-files --error-unmatch PLAN.md 2>&1 | head -1
  # expect: error: pathspec 'PLAN.md' did not match any file(s) known to git
  ```

  PLAN.md remains on disk as a legacy working file.

- [ ] **Step 3: Regenerate adapter output**

  ```bash
  rdf generate claude-code 2>&1 | tail -10
  # expect: deployment log lines for each modified canonical file
  ```

- [ ] **Step 4: Run doctor drift check**

  ```bash
  rdf doctor --all 2>&1 | tee /tmp/doctor-rdf-P6.log | tail -20
  # expect: zero FAILs
  ```

- [ ] **Step 5: Append gitignore test to `tests/plan-canonicalization.bats` (Goal 6 from spec)**

  ```bash
  @test ".gitignore includes plan + pointer patterns" {
      local count
      count=$(grep -cE '^PLAN(\*|-\*)?\.md$|^\.rdf/active-plan' "$RDF_SRC/.gitignore")
      [ "$count" -eq 4 ]
  }
  ```

  This brings `tests/plan-canonicalization.bats` to 15 `@test` blocks (13 from P1 + 1 from P5 + 1 from P6).

- [ ] **Step 6: Verify full test suite still passes**

  ```bash
  make -C tests test 2>&1 | tee /tmp/test-rdf-P6-debian12.log | tail -10
  # expect: contains "ok" lines, no "not ok"; new gitignore test passes

  grep -c '^[[:space:]]*@test ' tests/plan-canonicalization.bats
  # expect: 15
  ```

- [ ] **Step 7: Commit**

  ```bash
  git add .gitignore tests/plan-canonicalization.bats
  # PLAN.md removal is already staged from Step 2
  git add adapters/claude-code/output/  # may be a no-op if P2-P5 captured all edits
  git commit -m "Migrate plan storage — untrack PLAN.md, regen adapter

  [Change] .gitignore — add PLAN.md, PLAN*.md, PLAN-*.md, .rdf/active-plan*
        patterns. Existing .git/info/exclude already covers these for
        operators who already have it; adding to tracked .gitignore brings
        the protection to fresh clones
  [Remove] (git index) — untrack stale PLAN.md snapshot from commit
        6308d6d. File remains on disk as legacy fallback for transitional
        projects that haven't re-planned
  [Change] adapters/claude-code/output/ — regenerated from canonical
        edits in P2-P5 (rdf_active_plan_path wiring across commands,
        agents, references)

  Operator note: \`.git/info/exclude\` line 18 (docs/) is local-only and
  must be removed manually per existing clone; see release notes."
  ```

---

### Phase 7: Release — 3.1.2 version bump, CHANGELOG, README, push

Land version 3.1.2 with full changelog entries, version bump in VERSION/RDF.md/README.md, final adapter regen if needed, and push to origin/main. End-of-plan sentinel runs automatically per dispatcher protocol.

**Files:**
- Modify: `VERSION`
- Modify: `RDF.md`
- Modify: `README.md`
- Modify: `CHANGELOG`
- Modify: `CHANGELOG.RELEASE`

- **Mode**: serial-context
- **Accept**:
  - `cat VERSION` returns `3.1.2`
  - `grep -c '3\.1\.2' README.md RDF.md` returns ≥ 2 hits total
  - `head -5 CHANGELOG` contains `## 3.1.2`
  - `head -5 CHANGELOG.RELEASE` contains `## 3.1.2`
  - `rdf doctor --all` reports zero FAILs
  - `make -C tests test` exits 0
- **Test**: `rdf doctor --all` and `make -C tests test` both pass.
- **Edge cases**: Adapter regen needed again (run if `rdf doctor` reports drift); CHANGELOG entry length (>4 physical lines per entry triggers governance lint — keep concise per workspace CLAUDE.md commit-protocol guidance).
- **Regression-case**: N/A — docs — version/changelog updates have no behavioral surface; release tooling regression is covered by `rdf doctor` exit code.

- [ ] **Step 1: Bump VERSION**

  ```bash
  printf '%s\n' '3.1.2' > VERSION
  ```

- [ ] **Step 2: Update version references in `RDF.md` and `README.md`**

  Replace any `3.1.1` reference with `3.1.2`. Verify:

  ```bash
  grep -n '3\.1\.[12]' RDF.md README.md
  # expect: all hits show 3.1.2 (no remaining 3.1.1 references except in changelog history)
  ```

- [ ] **Step 3: Append `## 3.1.2` section to `CHANGELOG`**

  ```markdown
  ## 3.1.2

  -- New Features --

  [New] state/rdf-bus.sh — rdf_active_plan_path / rdf_set_active_plan /
        rdf_clear_active_plan resolver with three-tier fallback (session
        pointer → un-suffixed pointer → root PLAN.md legacy); all plan
        consumers route through the resolver

  -- Changes --

  [Change] /r-plan — plans now write to docs/plans/{date}-{topic}-plan.md
        and are committed mandatorily at creation; root PLAN.md no longer
        the active slot; new --resume <path> form for fresh-checkout
        takeover
  [Change] canonical/{commands,agents,reference}/* — 13 files updated to
        route through rdf_active_plan_path; dispatcher worktree sync
        copies resolver result to worktree-local path and sets a
        worktree-local pointer; status markers in framework.md clarified
        to live in .rdf/work-output/, not in plan body
  [Change] lib/cmd/generate.sh — deploys rdf-bus.sh to ~/.rdf/state/
        alongside other state helpers so consumers running outside this
        repo can resolve the helper
  [Change] lib/cmd/refresh.sh, state/rotate-work-output.sh,
        state/git-hooks/pre-commit — resolver wiring with context-appropriate
        source paths (RDF_STATE_DIR for refresh.sh, sibling path for the
        deployed rotate-work-output.sh, ancestor walk anchored on
        state/rdf-bus.sh for the worktree hook)

  -- Bug Fixes --

  [Fix] plan loss between sessions — root PLAN.md being gitignored and
        single-slot caused plans created in one session to be silently
        overwritten by the next session's /r-plan; canonical plans now
        committed at creation prevent this class of loss
  [Remove] stale tracked PLAN.md snapshot from commit 6308d6d (3.0.3 gate
        simplification plan, abandoned and never updated) — untracked
        via git rm --cached; file retained on disk as legacy fallback
  ```

- [ ] **Step 4: Append `## 3.1.2` section to `CHANGELOG.RELEASE`**

  Same content as Step 3.

- [ ] **Step 5: Regenerate adapter output (if drift)**

  ```bash
  rdf generate claude-code 2>&1 | tail -5
  rdf doctor --all 2>&1 | tail -5
  # expect: zero FAILs
  ```

- [ ] **Step 6: Commit release**

  ```bash
  git add VERSION RDF.md README.md CHANGELOG CHANGELOG.RELEASE adapters/claude-code/output/
  git commit -m "Version 3.1.2 — Plan Canonicalization release

  See CHANGELOG.RELEASE for the full 3.1.2 entry list."
  ```

- [ ] **Step 7: Push**

  ```bash
  git log --oneline origin/main..HEAD | head -10
  # expect: 7 commits (P1-P7)

  git push origin main
  # expect: success
  ```

- [ ] **Step 8: Verify post-push**

  ```bash
  git status
  # expect: nothing to commit, working tree clean (apart from PLAN.md which is now gitignored)

  git log --oneline -10
  # expect: HEAD is the 3.1.2 release commit
  ```

---
