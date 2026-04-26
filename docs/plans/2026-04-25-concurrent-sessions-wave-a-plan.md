# Implementation Plan: Concurrent Sessions — Wave A (Stop the Bleeding)

**Goal:** Ship five primitives that make blacklight's observed concurrent-session failures stop happening — session identity (P1), scoped phase-result/progress filenames (P11), worktree boundary enforcement via pre-commit hook + dispatcher backstop (P8), pre-aggregation dirty check (P9), and the Tests-may-touch scope-flex zone that makes the enforcement livable (P13).

**Architecture:** 10 phases. New shell helper library (`state/rdf-bus.sh`) provides `rdf_session_init` (UUIDv7 generation), `rdf_scoped_filename` (suffix derivation), and `rdf_parse_phase_scope` (used by the pre-commit hook to compute scope from PLAN.md). New pre-commit hook script (`state/git-hooks/pre-commit`) is installed into worktrees on creation by `r-build.md` Section 6b — physically rejects out-of-scope commits before they happen. `framework.md` schema gains scoped state filenames; `plan-schema.md` gains Rule 8 (Tests-may-touch field). Dispatcher gains a backstop post-merge `git diff-tree` scope check. Engineer protocol gains a pre-aggregation `git status --porcelain` check. Existing commands (`r-build`, `r-vpe`, `r-spec`, `r-ship`, `qa`) update their state-file paths to use the scoped form. Phases 1 and 3 are independent; 2/4/6 depend on 1 or 3; 5/7/8/9 fan out from there; phase 10 is the release. Eligible parallel batches: [1,3] then [2,4,6] then [5,7,8,9] then [10].

**Tech Stack:** Bash 4.1+ (CentOS 6 floor), markdown (canonical content; frontmatter-free), BATS (`tests/rdf-bus.bats` new + `tests/adapter.bats` extended), pure-bash UUIDv7 generation (no external `uuidgen` dependency), git pre-commit hooks. All shell follows `#!/usr/bin/env bash`, `set -euo pipefail`, double-quoting, `command <util>` coreutils, and one-line function headers per RDF CLAUDE.md.

**Spec:** `docs/specs/2026-04-25-concurrent-sessions-design.md`

**Phases:** 10

**Plan Version:** 3.0.6

---

## Conventions

**Commit message format:** Free-form descriptive (RDF convention — no version prefix). Tag body lines with `[New]` `[Change]` `[Fix]`. One commit per phase. Example:
```
Add rdf-bus.sh helper library with session identity and scoped filename helpers

[New] state/rdf-bus.sh — rdf_session_init (UUIDv7) + rdf_scoped_filename + rdf_parse_phase_scope
[New] tests/rdf-bus.bats — unit tests for the three helpers
```

**Canonical content:** Every edit to `canonical/**/*.md` is frontmatter-free. Deployment via `rdf generate claude-code` happens in Phase 10 only.

**Staging:** `git add <path>` explicitly per file. Never `git add -A` or `git add .`. `.git/info/exclude` blocks `CLAUDE.md`, `PLAN.md`, `AUDIT.md`, `MEMORY.md`, `.claude/`, `.rdf/`, `docs/` — nothing in those paths will be committed in this plan.

**CHANGELOG / CHANGELOG.RELEASE:** RDF has its own CHANGELOG. Phase 10 batches changelog entries for all 9 prior phases into a single 3.1.0 section — feature-branch-batched per the workspace CLAUDE.md exception.

**Shell standards:** `#!/usr/bin/env bash`, `set -euo pipefail`, `command cp/mv/rm/cat/etc.` in source, double-quote all variables, one-line function headers (`# name args — purpose`). No prose catalogues. No `declare -A` for global state.

**Scoped filename convention** — defined in Phase 1, used by Phases 2, 5, 7, 8, 9:
```
.rdf/work-output/<basename>-<RDF_SESSION_ID>.<ext>
```
Example: `.rdf/work-output/vpe-progress-01951c8a-7b30-7c2f-8e1d-a4b3f9c2e105.md`.

**SESSION_ID env var contract** — defined in Phase 1, used by Phases 2, 5, 7, 8, 9:
- `RDF_SESSION_ID` is a UUIDv7 string set by `rdf_session_init`
- If already set in the environment when called, it is preserved (subagents inherit from parent)
- If unset, a fresh UUIDv7 is generated and exported

**Tests-may-touch scope-flex contract** — defined in Phase 3 (plan-schema.md Rule 8), enforced in Phase 4 (hook), Phase 5 (dispatcher), Phase 6 (engineer):
- Optional phase metadata field listing glob/prefix paths that may drift
- Per-file ceiling: ≤30 lines changed
- Global ceiling: ≤3 files touched in the flex zone per phase
- Default: empty (no flex zone — strict Files enforcement)

**Version bump:** 3.0.7 → 3.1.0. Wave A is the foundation of a multi-wave concurrent-sessions migration; minor-version bump signals new public env-var contract (`RDF_SESSION_ID`), new helper library, new plan-schema Rule 8.

**CRITICAL — do NOT:**
- Touch any Wave B or Wave C primitives in this plan: no `bus.jsonl`, no `status.json` heartbeat broadcast, no OFD locks, no atomic-rename helper, no worktree liveness sweeper, no `/r-msg` slash command. Out of scope.
- Modify `lib/cmd/`, `bin/rdf`, or `adapters/*/adapter.sh` shell wiring. Wave A is canonical content + new helper library + new pre-commit hook + tests only.
- Edit `~/.claude/` directly — all canonical edits go through `canonical/`, deployed via `rdf generate claude-code` in Phase 10.

---

## File Map

### New Files
| File | Lines | Purpose | Test File |
|------|-------|---------|-----------|
| `state/rdf-bus.sh` | ~120 | Helpers: `rdf_session_init` (UUIDv7), `rdf_scoped_filename` (suffix), `rdf_session_short` (last-12 display), `rdf_parse_phase_scope` (PLAN.md → allowed paths regex + ceilings) | `tests/rdf-bus.bats` |
| `tests/rdf-bus.bats` | ~120 | BATS unit tests covering all four helpers + edge cases | N/A (is the test file) |
| `state/git-hooks/pre-commit` | ~60 | Worktree pre-commit hook: parses phase scope + Tests-may-touch + ceilings, rejects out-of-scope commits before they land. Installed by dispatcher in Phase 5. | `tests/rdf-bus.bats` (integration test simulates hook execution) |

### Modified Files
| File | Changes | Test File |
|------|---------|-----------|
| `canonical/reference/framework.md` | Category 2 + Category 3 transient-state tables: file basenames change to session-suffixed form. New "Session Identity" subsection documenting `RDF_SESSION_ID`. | `tests/adapter.bats` |
| `canonical/reference/plan-schema.md` | Add Rule 8 (Tests-may-touch field): optional phase metadata, glob paths, per-file + global ceilings. | `tests/adapter.bats` |
| `canonical/agents/dispatcher.md` | Load section: source `state/rdf-bus.sh`, derive scoped phase-result filename via `rdf_scoped_filename`. New "Worktree Pre-Commit Hook Installation" step (copy hook into worktree's `.git/worktrees/<name>/hooks/`). New "Post-Merge Scope Check (defense-in-depth)" section: `git diff-tree --name-only` against phase scope + Tests-may-touch. | `tests/adapter.bats` |
| `canonical/agents/engineer.md` | Setup: new "Pre-aggregation Precondition" — `git status --porcelain` before any aggregation/build, honors Tests-may-touch flex zone. | `tests/adapter.bats` |
| `canonical/agents/qa.md` | EVIDENCE re-validation: derive `phase-<N>-result-<RDF_SESSION_ID>.md` from dispatch payload. Backwards-compat fallback to un-suffixed form. | `tests/adapter.bats` |
| `canonical/commands/r-build.md` | §6b: replace `8-char random hex` with `${RDF_SESSION_ID}` (UUIDv7); add hook-copy step after `git worktree add`; add explicit step requiring the controller to `cd` into the worktree before each `Task` dispatch (the actual mechanism per workspace CLAUDE.md "Worktree CWD" — the `Task` tool does not accept a `cwd` parameter); update `r-build.md:217,284` `build-progress.md` writes to scoped form. | `tests/adapter.bats` |
| `canonical/commands/r-vpe.md` | All `vpe-progress.md` → `vpe-progress-${RDF_SESSION_ID}.md`. Resume protocol: glob for current-session file; legacy un-suffixed file gets one-shot import prompt. | `tests/adapter.bats` |
| `canonical/commands/r-spec.md` | All `spec-progress.md` → scoped form. Resume protocol updated. | `tests/adapter.bats` |
| `canonical/commands/r-ship.md` | All `ship-progress.md` → scoped form. Resume protocol updated. | `tests/adapter.bats` |
| `canonical/commands/r-start.md` | Lines 143-146: 4 progress-file existence checks switched to source `state/rdf-bus.sh`, glob scoped form first, legacy fallback. | `tests/adapter.bats` |
| `canonical/commands/r-status.md` | Line 30: phase-N-status pattern documented as scoped form. Lines 101-118: 4 progress-file checks switched to scoped/glob form. | `tests/adapter.bats` |
| `canonical/commands/r-save.md` | Line 107: spec-progress consumer switched to scoped/glob form with legacy fallback. | `tests/adapter.bats` |
| `canonical/commands/r-refresh.md` | Lines 262-263, 269: artifact column entries and prose reference updated to scoped form. | `tests/adapter.bats` |
| `canonical/reference/session-safety.md` | Lines 53-59: 4 progress-file references in stale-session checklist updated to scoped form; one-line note added explaining `RDF_SESSION_ID` suffixing. | `tests/adapter.bats` |
| `VERSION` | 3.0.7 → 3.1.0 | N/A (release metadata) |
| `RDF.md` | Version reference bumped to 3.1.0 | N/A (release metadata) |
| `CHANGELOG` | New `## 3.1.0` section with batched [New]/[Change] entries for all 9 prior phases | N/A (release metadata) |
| `CHANGELOG.RELEASE` | New `## 3.1.0` release-notes-style section | N/A (release metadata) |
| `tests/adapter.bats` | Add cases verifying canonical edits regenerate correctly into `~/.claude/` adapter output | N/A (extended test file) |

### Deleted Files
None.

---

## Phase Dependencies

- Phase 1: none
- Phase 2: [1]
- Phase 3: none
- Phase 4: [1]
- Phase 5: [2, 4]
- Phase 6: [3]
- Phase 7: [2]
- Phase 8: [1, 4]
- Phase 9: [1, 2]
- Phase 10: [1, 2, 3, 4, 5, 6, 7, 8, 9]

Visual aid (not machine-read):
```
       P1 ──────┬── P2 ─┬── P5 (also needs P4)
                │       ├── P7
                │       └── P9
                ├── P4 ──┴── P5
                │            └── P8 (also needs P1)
                └── P8

       P3 ───── P6
                            ↓
                          P10 (release)
```

Eligible parallel batches:
- Batch 1: [P1, P3] (both independent)
- Batch 2: [P2, P4, P6] (P2 and P4 need P1; P6 needs P3)
- Batch 3: [P5, P7, P8, P9] (all dependencies satisfied)
- Batch 4: [P10]

---

### Phase 1: Helper library — `state/rdf-bus.sh` and unit tests

Create the foundation: a small shell library with `rdf_session_init` (generates a UUIDv7 and exports `RDF_SESSION_ID` if unset), `rdf_scoped_filename` (suffixes a base path with the session ID), `rdf_session_short` (last 12 chars for display), and `rdf_parse_phase_scope` (extracts allowed-path regex + ceilings from a PLAN.md phase, used by the Phase 4 pre-commit hook). Pure-bash UUIDv7 generation using `/dev/urandom` and `date +%s%N` — no external `uuidgen` dependency. BATS test file verifies the contracts.

**Files:**
- Create: `state/rdf-bus.sh` (test: `tests/rdf-bus.bats`)
- Create: `tests/rdf-bus.bats` (test: N/A — is the test file)

- **Mode**: serial-agent
- **Accept**: `state/rdf-bus.sh` exists and passes `bash -n` and `shellcheck`. Sourcing with `RDF_SESSION_ID` unset and calling `rdf_session_init` exports a UUIDv7 matching `^[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$`. `rdf_parse_phase_scope` against a fixture PLAN.md returns the expected regex and ceilings. All BATS tests in `tests/rdf-bus.bats` pass.
- **Test**: `tests/rdf-bus.bats::@test "rdf_session_init generates valid UUIDv7"`, `::@test "rdf_session_init preserves pre-set RDF_SESSION_ID"`, `::@test "rdf_scoped_filename appends session ID before extension"`, `::@test "rdf_session_short returns last 12 chars"`, `::@test "rdf_parse_phase_scope extracts Files paths from fixture PLAN"`, `::@test "rdf_parse_phase_scope extracts Tests-may-touch when present"`, `::@test "rdf_parse_phase_scope escapes regex metacharacters in paths"`. Run with `bats tests/rdf-bus.bats` — expect: 7 tests pass.
- **Edge cases**: `RDF_SESSION_ID` already set (must preserve, not regenerate); base path with no extension (must append suffix to end); base path with multiple dots (must split on last dot only); phase with no `Tests-may-touch` field (must return empty flex zone); phase with malformed Files block (must error gracefully); paths with regex metachars `[`, `]`, `(`, `)`, `+`, `?` (must escape, not let them leak into the scope regex). **SessionStart hook deferred to Wave B:** Wave A uses lazy per-command init (`rdf_session_init` called by each `/r-*` command on entry) instead of a SessionStart hook. Consequence: every state-writing AND state-reading command must source `state/rdf-bus.sh` and call `rdf_session_init` before any path derivation. Phase 1 Accept does not enforce this — Phases 5/8/9 must each source the helper.
- **Regression-case**: `tests/rdf-bus.bats::@test "rdf_session_init preserves pre-set RDF_SESSION_ID"`

- [ ] **Step 1: Create `state/rdf-bus.sh`**

  ```bash
  #!/usr/bin/env bash
  # state/rdf-bus.sh — Concurrent-session coordination primitives (Wave A)
  # (C) 2026 R-fx Networks <proj@rfxn.com>
  # GNU GPL v2
  #
  # Provides: rdf_session_init, rdf_scoped_filename, rdf_session_short,
  #           rdf_parse_phase_scope.
  # Sourced by /r-* commands and the pre-commit hook. Idempotent.

  # rdf_uuidv7 — emit a UUIDv7 string to stdout
  rdf_uuidv7() {
      local ts_ms hex_ts hex_rand variant_byte
      ts_ms=$(($(command date +%s%N) / 1000000))
      printf -v hex_ts '%012x' "$ts_ms"
      hex_rand=$(command od -An -N10 -tx1 /dev/urandom | command tr -d ' \n')
      variant_byte=$(printf '%x' $((0x8 | (0x${hex_rand:3:1} & 0x3))))
      printf '%s-%s-7%s-%s%s-%s\n' \
          "${hex_ts:0:8}" \
          "${hex_ts:8:4}" \
          "${hex_rand:0:3}" \
          "$variant_byte" "${hex_rand:4:3}" \
          "${hex_rand:7:12}"
  }

  # rdf_session_init — set RDF_SESSION_ID if unset; export
  rdf_session_init() {
      if [[ -z "${RDF_SESSION_ID:-}" ]]; then
          RDF_SESSION_ID="$(rdf_uuidv7)"
          export RDF_SESSION_ID
      fi
  }

  # rdf_scoped_filename path — emit session-suffixed form
  rdf_scoped_filename() {
      local path="$1" dir base ext
      rdf_session_init
      dir="$(command dirname "$path")"
      base="$(command basename "$path")"
      if [[ "$base" == *.* ]]; then
          ext=".${base##*.}"
          base="${base%.*}"
      else
          ext=""
      fi
      printf '%s/%s-%s%s\n' "$dir" "$base" "$RDF_SESSION_ID" "$ext"
  }

  # rdf_session_short — last 12 hex chars of RDF_SESSION_ID
  rdf_session_short() {
      rdf_session_init
      printf '%s\n' "${RDF_SESSION_ID##*-}"
  }

  # rdf_parse_phase_scope plan_path phase_n — emit shell vars to stdout
  # Outputs three lines:
  #   ALLOWED_REGEX=<pipe-separated path regex>
  #   FLEX_REGEX=<pipe-separated Tests-may-touch glob expansion or empty>
  #   FLEX_FILE_CEILING=3
  #   FLEX_LINE_CEILING=30
  # Caller evals to import.
  rdf_parse_phase_scope() {
      local plan="$1" n="$2"
      local in_phase=0 next_phase=0 files="" flex=""
      while IFS= read -r line; do
          if [[ "$line" =~ ^"### Phase ${n}:" ]]; then
              in_phase=1; continue
          fi
          if [[ "$in_phase" -eq 1 && "$line" =~ ^"### Phase " ]]; then
              break   # next phase reached
          fi
          if [[ "$in_phase" -eq 1 ]]; then
              # Match Files entries: - Create: `path`  /  - Modify: `path`  /  - Delete: `path`
              if [[ "$line" =~ ^-\ (Create|Modify|Delete):\ \`([^\`]+)\` ]]; then
                  files="${files:+$files|}${BASH_REMATCH[2]}"
              fi
              # Match Tests-may-touch field: **Tests-may-touch:** path1, path2
              if [[ "$line" =~ ^\*\*Tests-may-touch:\*\*[[:space:]]*(.+)$ ]]; then
                  flex="${BASH_REMATCH[1]}"
                  flex="${flex// /}"           # strip spaces
                  flex="${flex//,/|}"          # commas to pipes
              fi
          fi
      done < "$plan"
      # Escape ALL regex metacharacters except glob *, which we handle next.
      # Order matters: backslash must be first.
      _esc() {
          local s="$1"
          s="${s//\\/\\\\}"
          s="${s//./\\.}"
          s="${s//+/\\+}"
          s="${s//\?/\\?}"
          s="${s//(/\\(}"
          s="${s//)/\\)}"
          s="${s//[/\\[}"
          s="${s//]/\\]}"
          s="${s//\{/\\\{}"
          s="${s//\}/\\\}}"
          s="${s//^/\\^}"
          s="${s//\$/\\\$}"
          # Pipe is meaningful — preserved as alternation when joining
          printf '%s' "$s"
      }
      files="$(_esc "$files")"
      flex="$(_esc "$flex")"
      flex="${flex//\\*/[^/]*}"   # glob * (now \*) → regex [^/]*
      printf 'ALLOWED_REGEX=%s\n' "$files"
      printf 'FLEX_REGEX=%s\n' "$flex"
      printf 'FLEX_FILE_CEILING=3\n'
      printf 'FLEX_LINE_CEILING=30\n'
  }
  ```

- [ ] **Step 2: Create `tests/rdf-bus.bats`**

  ```bash
  #!/usr/bin/env bats
  # tests/rdf-bus.bats — Unit tests for state/rdf-bus.sh
  # (C) 2026 R-fx Networks <proj@rfxn.com>
  # GNU GPL v2

  RDF_SRC="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"

  setup() {
      unset RDF_SESSION_ID
      # shellcheck disable=SC1091
      source "$RDF_SRC/state/rdf-bus.sh"
      TEST_TMP="$(mktemp -d)"
  }

  teardown() {
      command rm -rf "$TEST_TMP"
  }

  @test "rdf_session_init generates valid UUIDv7" {
      rdf_session_init
      [[ "$RDF_SESSION_ID" =~ ^[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$ ]]
  }

  @test "rdf_session_init preserves pre-set RDF_SESSION_ID" {
      RDF_SESSION_ID="01951c8a-7b30-7c2f-8e1d-a4b3f9c2e105"
      export RDF_SESSION_ID
      rdf_session_init
      [ "$RDF_SESSION_ID" = "01951c8a-7b30-7c2f-8e1d-a4b3f9c2e105" ]
  }

  @test "rdf_scoped_filename appends session ID before extension" {
      RDF_SESSION_ID="01951c8a-7b30-7c2f-8e1d-a4b3f9c2e105"
      export RDF_SESSION_ID
      result="$(rdf_scoped_filename ".rdf/work-output/vpe-progress.md")"
      [ "$result" = ".rdf/work-output/vpe-progress-01951c8a-7b30-7c2f-8e1d-a4b3f9c2e105.md" ]
  }

  @test "rdf_session_short returns last 12 chars" {
      RDF_SESSION_ID="01951c8a-7b30-7c2f-8e1d-a4b3f9c2e105"
      export RDF_SESSION_ID
      [ "$(rdf_session_short)" = "a4b3f9c2e105" ]
  }

  @test "rdf_parse_phase_scope extracts Files paths from fixture PLAN" {
      printf '%s\n' \
          '### Phase 5: Example' \
          '- Create: `state/foo.sh`' \
          '- Modify: `canonical/agents/qa.md`' \
          '' \
          '### Phase 6: Other' \
          > "$TEST_TMP/PLAN.md"
      output="$(rdf_parse_phase_scope "$TEST_TMP/PLAN.md" 5)"
      [[ "$output" == *"ALLOWED_REGEX=state/foo\\.sh|canonical/agents/qa\\.md"* ]]
  }

  @test "rdf_parse_phase_scope extracts Tests-may-touch when present" {
      printf '%s\n' \
          '### Phase 7: Example' \
          '- Modify: `canonical/x.md`' \
          '**Tests-may-touch:** tests/fixtures/*.json, tests/helpers/*.bash' \
          '' \
          '### Phase 8: Other' \
          > "$TEST_TMP/PLAN.md"
      output="$(rdf_parse_phase_scope "$TEST_TMP/PLAN.md" 7)"
      [[ "$output" == *"FLEX_REGEX=tests/fixtures/[^/]*\\.json|tests/helpers/[^/]*\\.bash"* ]]
      [[ "$output" == *"FLEX_FILE_CEILING=3"* ]]
      [[ "$output" == *"FLEX_LINE_CEILING=30"* ]]
  }

  @test "rdf_parse_phase_scope escapes regex metacharacters in paths" {
      printf '%s\n' \
          '### Phase 9: Localization' \
          '- Modify: `docs/i18n/[en]/index.md`' \
          '- Create: `lib/util(plus).sh`' \
          '' \
          '### Phase 10: Other' \
          > "$TEST_TMP/PLAN.md"
      output="$(rdf_parse_phase_scope "$TEST_TMP/PLAN.md" 9)"
      # Verify [en] escaped, () escaped, +/? escaped — not parsed as regex char class/group/quantifier
      [[ "$output" == *"docs/i18n/\\[en\\]/index\\.md"* ]]
      [[ "$output" == *"lib/util\\(plus\\)\\.sh"* ]]
  }
  ```

  Also extend the metachar test fixture to cover `+` and `?` (the helper escapes them but the cycle 1 test only asserted `[`, `]`, `(`, `)`). Add to the fixture above (in the `Phase 9: Localization` block):

  ```
          '- Create: `lib/v1+util.sh`' \
          '- Create: `lib/util?.sh`' \
  ```

  And add two assertions:
  ```bash
      [[ "$output" == *"lib/v1\\+util\\.sh"* ]]
      [[ "$output" == *"lib/util\\?\\.sh"* ]]
  ```

- [ ] **Step 3: Verify lint and tests**

  ```bash
  bash -n state/rdf-bus.sh
  # expect: (no output, exit 0)
  shellcheck state/rdf-bus.sh
  # expect: (no output, exit 0)
  bats tests/rdf-bus.bats
  # expect: 7 tests pass
  ```

- [ ] **Step 4: Commit**

  ```bash
  git add state/rdf-bus.sh tests/rdf-bus.bats
  git commit -m "Add rdf-bus.sh helper library with session identity, scoped filenames, phase-scope parser

  [New] state/rdf-bus.sh — rdf_session_init (UUIDv7), rdf_scoped_filename, rdf_session_short, rdf_parse_phase_scope (with full regex metacharacter escaping)
  [New] tests/rdf-bus.bats — 7 unit tests covering generation, preservation, suffix derivation, short form, scope extraction, Tests-may-touch parsing, regex metachar escaping"
  ```

---

### Phase 2: `framework.md` schema — scoped state filenames + session identity contract

Update `canonical/reference/framework.md` to document the new `RDF_SESSION_ID` env var contract and update the Category 2 + Category 3 state tables to use session-suffixed filenames.

**Files:**
- Modify: `canonical/reference/framework.md` (test: `tests/adapter.bats`)

- **Mode**: serial-context
- **Accept**: `framework.md` Category 2 and Category 3 tables list session-scoped artifacts with the `-<SESSION_ID>` suffix. New "Session Identity" subsection exists with the `RDF_SESSION_ID` contract and helper signatures.
- **Test**: `grep -c '<SESSION_ID>' canonical/reference/framework.md` — expect: at least 10. `grep -c 'RDF_SESSION_ID' canonical/reference/framework.md` — expect: at least 3.
- **Edge cases**: none (pure schema documentation).
- **Regression-case**: N/A — docs — schema documentation update; no production behavior change

- [ ] **Step 1: Update Category 3 transient-state table**

  Locate the Category 3 table (lines ~66-74) and replace the artifact column entries:

  Old:
  ```
  | `phase-N-status.md` | engineer | dispatcher |
  | `phase-N-result.md` | engineer | dispatcher |
  | `qa-phase-N-verdict.md` | qa | dispatcher |
  | `sentinel-N.md` | reviewer | dispatcher |
  | `sentinel-plan-final.md` | reviewer (via dispatcher) | dispatcher |
  | `uat-phase-N-verdict.md` | uat | dispatcher |
  ```

  New:
  ```
  | `phase-N-status-<SESSION_ID>.md` | engineer | dispatcher |
  | `phase-N-result-<SESSION_ID>.md` | engineer | dispatcher |
  | `qa-phase-N-verdict-<SESSION_ID>.md` | qa | dispatcher |
  | `sentinel-N-<SESSION_ID>.md` | reviewer | dispatcher |
  | `sentinel-plan-final-<SESSION_ID>.md` | reviewer (via dispatcher) | dispatcher |
  | `uat-phase-N-verdict-<SESSION_ID>.md` | uat | dispatcher |
  ```

- [ ] **Step 2: Update Category 2 (persistent project state) — session-scoped progress files**

  In the Category 2 table (lines ~40-50), update:

  Old:
  ```
  | spec-progress.md | `.rdf/work-output/` | `/r-spec` | During design |
  | ship-progress.md | `.rdf/work-output/` | `/r-ship` | During release |
  | vpe-progress.md | `.rdf/work-output/` | `/r-vpe` | During VPE pipeline |
  | build-progress.md | `.rdf/work-output/` | `/r-build` | During parallel build |
  ```

  New:
  ```
  | spec-progress-<SESSION_ID>.md | `.rdf/work-output/` | `/r-spec` | During design |
  | ship-progress-<SESSION_ID>.md | `.rdf/work-output/` | `/r-ship` | During release |
  | vpe-progress-<SESSION_ID>.md | `.rdf/work-output/` | `/r-vpe` | During VPE pipeline |
  | build-progress-<SESSION_ID>.md | `.rdf/work-output/` | `/r-build` | During parallel build |
  ```

  Leave `session-log.jsonl` un-suffixed.

- [ ] **Step 3: Add "Session Identity" subsection**

  After the Category 3 table and before the "Engineer result schema:" heading, insert:

  ```markdown
  **Session Identity (`RDF_SESSION_ID`):** Set by the `rdf_session_init`
  helper in `state/rdf-bus.sh`. UUIDv7 string. Subagents inherit from
  parent (env passthrough). Used as filename suffix for transient state
  files to prevent collisions between concurrent sessions on the same
  repository. Helper functions:
  - `rdf_session_init` — generate UUIDv7 if unset; export
  - `rdf_scoped_filename <basepath>` — derive `<basepath>-<UUID>.<ext>`
  - `rdf_session_short` — last 12 chars for log display
  - `rdf_parse_phase_scope <plan> <N>` — extract phase Files + Tests-may-touch
    for the pre-commit hook (see Phase 4 below and `plan-schema.md` Rule 8)

  Concurrent-session coordination design: `docs/specs/2026-04-25-concurrent-sessions-design.md`.
  ```

- [ ] **Step 4: Verify**

  ```bash
  grep -c '<SESSION_ID>' canonical/reference/framework.md
  # expect: at least 10
  grep -c 'RDF_SESSION_ID' canonical/reference/framework.md
  # expect: at least 3
  grep -c 'rdf_session_init\|rdf_parse_phase_scope' canonical/reference/framework.md
  # expect: at least 2
  ```

- [ ] **Step 5: Commit**

  ```bash
  git add canonical/reference/framework.md
  git commit -m "Add session-suffixed transient state filenames and Session Identity subsection to framework.md

  [Change] framework.md: Category 2 + Category 3 tables — all session-scoped state
    files use '-<SESSION_ID>' suffix to prevent collisions across concurrent sessions
  [New] framework.md: Session Identity subsection documenting RDF_SESSION_ID env var
    and the four helper function contracts (init, scoped_filename, session_short, parse_phase_scope)"
  ```

---

### Phase 3: `plan-schema.md` Rule 8 — Tests-may-touch field

Add a new schema rule documenting the optional `**Tests-may-touch:**` phase metadata field, its glob syntax, and the per-file + global ceilings. Independent of all other Wave A phases — this just adds the rule that downstream phases (4, 5, 6) honor.

**Files:**
- Modify: `canonical/reference/plan-schema.md` (test: `tests/adapter.bats`)

- **Mode**: serial-context
- **Accept**: `plan-schema.md` has a new `## Rule 8: Tests-may-touch (optional)` section after Rule 7. The rule documents glob syntax, two ceilings (3 files, 30 lines), default behavior (empty flex zone), and the call-sites that enforce it (pre-commit hook, dispatcher post-merge, engineer dirty check).
- **Test**: `grep -c '## Rule 8: Tests-may-touch' canonical/reference/plan-schema.md` — expect: 1. `grep -c 'FLEX_FILE_CEILING\|FLEX_LINE_CEILING\|≤30 lines\|≤3 files' canonical/reference/plan-schema.md` — expect: at least 2.
- **Edge cases**: phase declares Tests-may-touch but no test file is added (no enforcement consequence — flex zone is empty drift target). Phase declares overlapping Files and Tests-may-touch (Files takes precedence; flex zone is the difference set).
- **Regression-case**: N/A — docs — schema rule documentation; the enforcement code lives in Phases 4, 5, 6 and is tested there

- [ ] **Step 1: Append Rule 8 to plan-schema.md**

  Read `canonical/reference/plan-schema.md` to confirm it ends with the "Adding a New Rule" section. Insert the new rule between Rule 7 and "Adding a New Rule":

  ```markdown
  ---

  ## Rule 8: Tests-may-touch (optional)

  Phases that add or extend tests MAY declare a scope-flex zone of paths
  that the engineer is pre-authorized to touch without surfacing as an
  out-of-scope finding:

  ```
  **Tests-may-touch:** tests/fixtures/*.json, tests/helpers/*.bash
  ```

  ### 8a. Syntax

  Comma-separated list of glob expressions or directory prefixes. Globs
  use shell-style `*` (matches a single path component, no `/`). Examples:
  - `tests/fixtures/*.json` — any JSON file directly in `tests/fixtures/`
  - `tests/helpers/` — any file under `tests/helpers/` (recursive)
  - `tests/**` — rejected (recursive `**` is too permissive; use a
    specific subdirectory)

  ### 8b. Ceilings

  Drift inside the flex zone is bounded:

  - **Per-file ceiling:** ≤30 lines added/changed (counted via
    `git diff --cached --numstat | awk '{print $1+$2}'`)
  - **Global ceiling:** ≤3 files touched per phase in the flex zone

  Drift exceeding either ceiling is rejected — same handling as
  out-of-scope drift. The intent is to legitimize *trivial* test-infra
  additions (a fixture, a helper); substantive test rewrites still
  require explicit `**Files:**` declaration.

  ### 8c. Default

  Empty (no flex zone). Phases without the `**Tests-may-touch:**` field
  get strict `**Files:**`-only enforcement.

  ### 8d. Enforcement

  Three call sites consume this rule:

  - **Pre-commit hook** (`state/git-hooks/pre-commit`, installed in
    worktrees by dispatcher): primary gate; rejects `git commit` if
    staged files violate the union of `**Files:**` and `**Tests-may-touch:**`,
    or if either ceiling is exceeded.
  - **Dispatcher post-merge check** (defense-in-depth): runs
    `git diff-tree --name-only` after engineer returns; same union check.
  - **Engineer dirty check** (`canonical/agents/engineer.md` Setup):
    runs `git status --porcelain` before any aggregation/build step;
    same union check.

  All three derive scope via `rdf_parse_phase_scope` from
  `state/rdf-bus.sh`.

  **Failure (out of scope):** *"Phase N: file <path> not in **Files:**
  list and not matched by **Tests-may-touch:** glob."*

  **Failure (per-file ceiling):** *"Phase N: file <path> in flex zone
  changed <K> lines (ceiling 30)."*

  **Failure (global ceiling):** *"Phase N: <K> files in flex zone
  (ceiling 3)."*
  ```

- [ ] **Step 2: Verify**

  ```bash
  grep -c '## Rule 8: Tests-may-touch' canonical/reference/plan-schema.md
  # expect: 1
  grep -c 'FLEX_FILE_CEILING\|≤30 lines\|≤3 files' canonical/reference/plan-schema.md
  # expect: at least 2
  grep -c 'rdf_parse_phase_scope' canonical/reference/plan-schema.md
  # expect: 1
  ```

- [ ] **Step 3: Commit**

  ```bash
  git add canonical/reference/plan-schema.md
  git commit -m "Add plan-schema Rule 8 — Tests-may-touch scope-flex zone

  [New] plan-schema.md Rule 8: optional **Tests-may-touch:** phase metadata
    field with glob syntax, per-file ceiling (≤30 lines), global ceiling (≤3 files),
    and default empty behavior. Enforced by pre-commit hook (Phase 4), dispatcher
    post-merge check (Phase 5), and engineer dirty check (Phase 6) via
    rdf_parse_phase_scope from state/rdf-bus.sh."
  ```

---

### Phase 4: Pre-commit hook — `state/git-hooks/pre-commit`

Create the worktree pre-commit hook script that physically rejects out-of-scope commits. Sources `state/rdf-bus.sh`, parses the current branch to determine phase number, calls `rdf_parse_phase_scope` against PLAN.md, computes scope (Files ∪ Tests-may-touch), validates staged paths and ceilings, exits non-zero on violation. Installed by dispatcher in Phase 5.

**Files:**
- Create: `state/git-hooks/pre-commit` (test: `tests/rdf-bus.bats` — integration test added below)

- **Mode**: serial-agent
- **Accept**: `state/git-hooks/pre-commit` exists, is executable, passes `bash -n` and `shellcheck`. Integration test in `tests/rdf-bus.bats` simulates the hook against a fixture worktree (mock `git diff --cached`, mock branch, fixture PLAN.md) and verifies it rejects an out-of-scope commit and accepts an in-scope commit + flex-zone commit under ceilings.
- **Test**: `tests/rdf-bus.bats::@test "pre-commit hook rejects out-of-scope commit"`, `::@test "pre-commit hook accepts in-scope commit"`, `::@test "pre-commit hook accepts flex-zone commit under ceilings"`, `::@test "pre-commit hook rejects flex-zone commit over file ceiling"`. Run with `bats tests/rdf-bus.bats` — expect: 4 new tests pass (10 total).
- **Edge cases**: hook runs from a non-`rdf/phase-N-*` branch (must no-op, exit 0); PLAN.md missing (must error clearly with hint to run from project root); phase number not in PLAN.md (must error); staged set is empty (must no-op, exit 0); **worktree's PLAN.md is the HEAD-committed version, NOT the operator's locally-modified PLAN.md from main working tree** — if the operator added a phase but did not commit PLAN.md before `/r-build`, the worktree hook reads stale schema and rejects with "Phase N not found". Mitigation: dispatcher copies the main-repo PLAN.md into the worktree pre-dispatch (added in Phase 5 step). Without that copy, the operator must commit PLAN.md before invoking `/r-build`.
- **Regression-case**: `tests/rdf-bus.bats::@test "pre-commit hook rejects out-of-scope commit"`

- [ ] **Step 1: Create `state/git-hooks/pre-commit`**

  ```bash
  #!/usr/bin/env bash
  # state/git-hooks/pre-commit — RDF worktree scope enforcement (Wave A)
  # (C) 2026 R-fx Networks <proj@rfxn.com>
  # GNU GPL v2
  #
  # Installed into worktrees by dispatcher (canonical/agents/dispatcher.md).
  # Rejects commits that touch files outside the phase's declared Files list
  # or Tests-may-touch flex zone (plan-schema.md Rule 8).
  #
  # Bypass: --no-verify (intentional override; dispatcher post-merge check
  # serves as defense-in-depth backstop).
  set -euo pipefail

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

  # Source helpers
  if [[ ! -f "$_proj/state/rdf-bus.sh" ]]; then
      echo "rdf pre-commit: state/rdf-bus.sh not found; skipping scope check" >&2
      exit 0
  fi
  # shellcheck source=/dev/null
  source "$_proj/state/rdf-bus.sh"

  # Derive phase number from branch name: rdf/phase-<N>-<UUID>
  _branch="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")"
  _phase_n=""
  if [[ "$_branch" =~ ^rdf/phase-([0-9]+)- ]]; then
      _phase_n="${BASH_REMATCH[1]}"
  fi
  if [[ -z "$_phase_n" ]]; then
      # Not a worktree branch; no enforcement
      exit 0
  fi

  # Parse phase scope
  eval "$(rdf_parse_phase_scope "$_proj/PLAN.md" "$_phase_n")"
  if [[ -z "${ALLOWED_REGEX:-}" ]]; then
      echo "rdf pre-commit: Phase $_phase_n not found in PLAN.md or has no Files block" >&2
      exit 1
  fi

  # Build union regex
  _scope_regex="$ALLOWED_REGEX"
  if [[ -n "${FLEX_REGEX:-}" ]]; then
      _scope_regex="$_scope_regex|$FLEX_REGEX"
  fi

  # Get staged files
  _staged="$(git diff --cached --name-only)"
  if [[ -z "$_staged" ]]; then
      exit 0   # nothing staged
  fi

  # Validate each staged path
  _violations=""
  while IFS= read -r _path; do
      if ! [[ "$_path" =~ ^(${_scope_regex})$ ]]; then
          _violations="${_violations:+$_violations}$_path"$'\n'
      fi
  done <<< "$_staged"

  if [[ -n "$_violations" ]]; then
      echo "rdf pre-commit: SCOPE VIOLATION — files outside Phase $_phase_n scope:" >&2
      echo "$_violations" >&2
      echo "Phase Files allowed: $(echo "$ALLOWED_REGEX" | command tr '|' ' ')" >&2
      [[ -n "${FLEX_REGEX:-}" ]] && echo "Tests-may-touch flex: $(echo "$FLEX_REGEX" | command tr '|' ' ')" >&2
      echo "If this addition is legitimate test-infra, add the path to" >&2
      echo "the phase's **Tests-may-touch:** field in PLAN.md." >&2
      echo "Bypass with --no-verify only if dispatcher post-merge check is acceptable." >&2
      exit 1
  fi

  # Check ceilings on flex-zone files
  if [[ -n "${FLEX_REGEX:-}" ]]; then
      _flex_files=0
      while IFS= read -r _path; do
          if [[ "$_path" =~ ^(${FLEX_REGEX})$ ]]; then
              _flex_files=$((_flex_files + 1))
              # Per-file line ceiling
              _lines="$(git diff --cached --numstat -- "$_path" | awk '{print $1+$2}')"
              if [[ "$_lines" -gt "${FLEX_LINE_CEILING:-30}" ]]; then
                  echo "rdf pre-commit: file $_path in flex zone changed $_lines lines (ceiling ${FLEX_LINE_CEILING:-30})" >&2
                  exit 1
              fi
          fi
      done <<< "$_staged"
      if [[ "$_flex_files" -gt "${FLEX_FILE_CEILING:-3}" ]]; then
          echo "rdf pre-commit: $_flex_files files in flex zone (ceiling ${FLEX_FILE_CEILING:-3})" >&2
          exit 1
      fi
  fi

  exit 0
  ```

- [ ] **Step 2: Make executable**

  ```bash
  chmod +x state/git-hooks/pre-commit
  # expect: (no output, mode is 755 or 775 after this)
  ls -l state/git-hooks/pre-commit
  # expect: -rwxr-xr-x (or with group write)
  ```

- [ ] **Step 3: Add 4 integration tests to `tests/rdf-bus.bats`**

  Append to the existing `tests/rdf-bus.bats`:

  ```bash
  # Helper: run pre-commit hook in a fixture git repo with mocked PLAN.md
  _setup_fixture_repo() {
      local repo="$1" phase_n="$2"
      git -C "$repo" init -q
      git -C "$repo" checkout -q -b "rdf/phase-${phase_n}-01951c8a-7b30-7c2f-8e1d-a4b3f9c2e105"
      command mkdir -p "$repo/state"
      command cp "$RDF_SRC/state/rdf-bus.sh" "$repo/state/"
      command cp "$RDF_SRC/state/git-hooks/pre-commit" "$repo/.git/hooks/"
      command chmod +x "$repo/.git/hooks/pre-commit"
  }

  @test "pre-commit hook rejects out-of-scope commit" {
      _setup_fixture_repo "$TEST_TMP/repo" 1
      printf '%s\n' '### Phase 1: Test' '- Modify: `state/foo.sh`' > "$TEST_TMP/repo/PLAN.md"
      command mkdir -p "$TEST_TMP/repo/state"
      echo "echo hi" > "$TEST_TMP/repo/state/foo.sh"
      echo "echo bad" > "$TEST_TMP/repo/state/bad.sh"
      git -C "$TEST_TMP/repo" add PLAN.md state/foo.sh state/bad.sh state/rdf-bus.sh
      run git -C "$TEST_TMP/repo" -c user.email=t@t -c user.name=t commit -m "test"
      [ "$status" -ne 0 ]
      [[ "$output" == *"SCOPE VIOLATION"* ]]
  }

  @test "pre-commit hook accepts in-scope commit" {
      _setup_fixture_repo "$TEST_TMP/repo" 1
      printf '%s\n' '### Phase 1: Test' '- Modify: `state/foo.sh`' > "$TEST_TMP/repo/PLAN.md"
      command mkdir -p "$TEST_TMP/repo/state"
      echo "echo hi" > "$TEST_TMP/repo/state/foo.sh"
      git -C "$TEST_TMP/repo" add PLAN.md state/foo.sh state/rdf-bus.sh
      run git -C "$TEST_TMP/repo" -c user.email=t@t -c user.name=t commit -m "test"
      [ "$status" -eq 0 ]
  }

  @test "pre-commit hook accepts flex-zone commit under ceilings" {
      _setup_fixture_repo "$TEST_TMP/repo" 1
      printf '%s\n' \
          '### Phase 1: Test' \
          '- Modify: `state/foo.sh`' \
          '**Tests-may-touch:** tests/fixtures/*.json' \
          > "$TEST_TMP/repo/PLAN.md"
      command mkdir -p "$TEST_TMP/repo/state" "$TEST_TMP/repo/tests/fixtures"
      echo "echo hi" > "$TEST_TMP/repo/state/foo.sh"
      echo '{"a":1}' > "$TEST_TMP/repo/tests/fixtures/x.json"
      git -C "$TEST_TMP/repo" add PLAN.md state/foo.sh state/rdf-bus.sh tests/fixtures/x.json
      run git -C "$TEST_TMP/repo" -c user.email=t@t -c user.name=t commit -m "test"
      [ "$status" -eq 0 ]
  }

  @test "pre-commit hook rejects flex-zone commit over file ceiling" {
      _setup_fixture_repo "$TEST_TMP/repo" 1
      printf '%s\n' \
          '### Phase 1: Test' \
          '- Modify: `state/foo.sh`' \
          '**Tests-may-touch:** tests/fixtures/*.json' \
          > "$TEST_TMP/repo/PLAN.md"
      command mkdir -p "$TEST_TMP/repo/state" "$TEST_TMP/repo/tests/fixtures"
      echo "echo hi" > "$TEST_TMP/repo/state/foo.sh"
      for i in 1 2 3 4; do echo "{\"$i\":$i}" > "$TEST_TMP/repo/tests/fixtures/x$i.json"; done
      git -C "$TEST_TMP/repo" add PLAN.md state/foo.sh state/rdf-bus.sh tests/fixtures/
      run git -C "$TEST_TMP/repo" -c user.email=t@t -c user.name=t commit -m "test"
      [ "$status" -ne 0 ]
      [[ "$output" == *"flex zone"* ]] || [[ "$output" == *"ceiling"* ]]
  }
  ```

  All four fixtures use `printf '%s\n' ...` instead of `cat <<'EOF'` to be **indent-immune** when copied into the test file (the heredoc form would inherit the plan's nested-codeblock 2-space indent and break `rdf_parse_phase_scope`'s anchored regex).

- [ ] **Step 4: Verify lint and tests**

  ```bash
  bash -n state/git-hooks/pre-commit
  # expect: (no output, exit 0)
  shellcheck state/git-hooks/pre-commit
  # expect: (no output, exit 0)
  bats tests/rdf-bus.bats
  # expect: 11 tests pass (7 from Phase 1 + 4 new)
  ```

- [ ] **Step 5: Commit**

  ```bash
  git add state/git-hooks/pre-commit tests/rdf-bus.bats
  git commit -m "Add worktree pre-commit hook for structural scope enforcement

  [New] state/git-hooks/pre-commit — physically rejects out-of-scope commits in
    worktree branches (rdf/phase-<N>-<UUID>); honors Files + Tests-may-touch zone
    + per-file (≤30 lines) and global (≤3 files) ceilings from plan-schema Rule 8
  [New] tests/rdf-bus.bats — 4 integration tests covering reject, accept, flex-zone
    under ceiling, flex-zone over ceiling
  [Fix] Addresses prose-in-payload non-enforcement (M13 dispatch confirmed 5/5
    scope violations went unsurfaced); structural gate forces conversation when
    drift exceeds authorized zone"
  ```

---

### Phase 5: Dispatcher — scoped paths, hook installation, post-merge defense-in-depth

Update `canonical/agents/dispatcher.md` to: (a) source `state/rdf-bus.sh` and derive scoped phase-result paths via `rdf_scoped_filename`, (b) install the pre-commit hook into each worktree on creation (P8 layer 1), (c) add a post-merge scope check using `git diff-tree` + `rdf_parse_phase_scope` (P8 layer 2), honoring Tests-may-touch ceilings.

**Files:**
- Modify: `canonical/agents/dispatcher.md` (test: `tests/adapter.bats`)

- **Mode**: serial-agent
- **Accept**: Dispatcher's Load section sources `state/rdf-bus.sh`. New "Worktree Pre-Commit Hook Installation" subsection appears within the Worktree dispatch path. New "Post-Merge Scope Check (defense-in-depth)" section appears between worktree-merge and Quality Gates. Both sections explicitly cite plan-schema.md Rule 8.
- **Test**: `grep -c 'rdf_scoped_filename\|rdf_parse_phase_scope' canonical/agents/dispatcher.md` — expect: at least 3. `grep -c 'Worktree Pre-Commit Hook Installation\|Post-Merge Scope Check' canonical/agents/dispatcher.md` — expect: at least 2. `grep -c 'plan-schema.md.*Rule 8\|Tests-may-touch' canonical/agents/dispatcher.md` — expect: at least 2. `grep -c 'phase-N-status\.md\b' canonical/agents/dispatcher.md` — expect: 0 (line 295 must be updated to scoped form).
- **Edge cases**: PLAN.md `**Files:**` field unparseable (free-form prose) — log warning, skip post-merge enforcement (matches r-build.md:75-79 fallback). Hook installation fails (filesystem permissions, missing source) — log warning, proceed (post-merge check still applies as backstop). PLAN.md staleness in worktree (worktree gets HEAD-committed PLAN.md, not operator's locally-modified version) — dispatcher copies main-repo PLAN.md into worktree pre-dispatch (added in Step 3 of this phase).
- **Regression-case**: N/A — refactor — protocol documentation only; the canonical edit alone introduces no runtime behavior. Behavior change is realized by Phase 10's `rdf generate claude-code` which regenerates `~/.claude/agents/rdf-dispatcher.md` and is regression-tested by `tests/adapter.bats::@test "regenerated dispatcher mentions RDF_SESSION_ID, Tests-may-touch, hook installation"` (added in Phase 10). Per plan-schema Rule 6 last paragraph: explicit override — *category retained because canonical edit is a protocol assertion change with no in-phase runtime effect; integration regression is the adapter round-trip test.*

- [ ] **Step 1: Update Load section to source helpers and derive scoped path**

  Locate `### Load` (lines 12-22) and replace:

  Old:
  ```
  - Determine phase number N; pass N to the QA subagent in the
    dispatch payload so QA can derive `.rdf/work-output/phase-<N>-result.md`
    for EVIDENCE re-validation (scope ≥ multi-file only)
  ```

  New:
  ```
  - Source `state/rdf-bus.sh` and call `rdf_session_init` to ensure
    `RDF_SESSION_ID` is set before any state-file path is derived.
  - Determine phase number N; pass N AND `RDF_SESSION_ID` to the QA
    subagent in the dispatch payload so QA can derive the scoped
    result file path:
    `.rdf/work-output/phase-<N>-result-<RDF_SESSION_ID>.md`
    (See `state/rdf-bus.sh::rdf_scoped_filename`.)
  ```

- [ ] **Step 2: Update phase-N-status producer reference (line 295)**

  Locate the line in `dispatcher.md` (around line 295 in the "INFORMATIONAL findings — logged" section):

  Old:
  ```
    1. Written to .rdf/work-output/phase-N-status.md
  ```

  New:
  ```
    1. Written to .rdf/work-output/phase-<N>-status-<RDF_SESSION_ID>.md
       (derived via rdf_scoped_filename from state/rdf-bus.sh).
  ```

  This closes the schema/code drift identified in challenge review — Phase 2 declared `phase-N-status-<SESSION_ID>.md` in the framework.md schema but the dispatcher's own producer reference still wrote the un-suffixed form.

- [ ] **Step 3: Add Worktree Pre-Commit Hook Installation subsection (with PLAN.md copy)**

  Insert this new subsection in the dispatcher's worktree-mode protocol (between `### Execute (one of three modes)` parallel-agent block and `### Quality Gates`, before the new Post-Merge Scope Check section that the next step adds):

  ```markdown
  ### Worktree Pre-Commit Hook Installation (and PLAN.md sync)

  When dispatched into a worktree (`PARALLEL_BATCH: true` with
  `PROJECT_ROOT` set to a worktree path), perform two installation
  steps before any engineer subagent is dispatched:

  **(a) Copy PLAN.md from main repo into worktree.**
  Worktrees check out the HEAD-committed working tree, which means
  `PLAN.md` in the worktree is the *committed* version, not the
  operator's locally-modified version in the main repo. The hook
  enforces against whatever PLAN.md it reads, so a stale PLAN.md
  causes false-negative rejections ("Phase N not found") and
  false-positive scope leaks.

  ```bash
  command cp "${PROJECT_ROOT_MAIN}/PLAN.md" "${PROJECT_ROOT}/PLAN.md"
  ```

  This sync is one-shot at worktree creation; subsequent operator
  edits to PLAN.md are not reflected in worktrees. If the operator
  changes PLAN.md mid-build, dispatch must be re-invoked.

  **(b) Install the pre-commit hook.**
  ```bash
  worktree_git_dir=$(git -C "$PROJECT_ROOT" rev-parse --git-dir)
  command cp "${PROJECT_ROOT_MAIN}/state/git-hooks/pre-commit" \
              "${worktree_git_dir}/hooks/pre-commit"
  command chmod +x "${worktree_git_dir}/hooks/pre-commit"
  ```

  `${PROJECT_ROOT_MAIN}` is the main project root (where `state/`
  lives) — passed in the dispatch payload separately from
  `PROJECT_ROOT` (which is the worktree path).

  The hook reads `PLAN.md` from the worktree (now synced via step
  (a)) and rejects commits outside the union of `**Files:**` and
  `**Tests-may-touch:**`. See `plan-schema.md` Rule 8 for the full
  enforcement contract.

  If either step fails (filesystem permission, missing source):
  log a warning and proceed. The Post-Merge Scope Check (next
  section) still applies as a defense-in-depth backstop.
  ```

- [ ] **Step 4: Add Post-Merge Scope Check section**

  Insert immediately after the new Worktree Pre-Commit Hook Installation section, before `### Quality Gates`:

  ```markdown
  ### Post-Merge Scope Check (defense-in-depth)

  After a parallel-worktree engineer returns and before merging the
  branch into base, verify the engineer's commit stayed within the
  phase's declared file scope. This is layer 2 enforcement — the
  worktree pre-commit hook (previous section) is layer 1. Both
  layers cite `plan-schema.md` Rule 8.

  Procedure:

  1. Source `state/rdf-bus.sh`, parse phase scope:
     ```
     eval "$(rdf_parse_phase_scope PLAN.md $N)"
     ```
     This sets `ALLOWED_REGEX`, `FLEX_REGEX`, `FLEX_FILE_CEILING`,
     `FLEX_LINE_CEILING`.

  2. Compute touched paths in engineer's commit:
     ```
     touched=$(git -C "$worktree_path" diff-tree --no-commit-id \
       --name-only -r HEAD)
     ```

  3. For each touched path: check it matches
     `${ALLOWED_REGEX}|${FLEX_REGEX}`. Out-of-scope paths emit a
     Gate 1 NEEDS_CONTEXT verdict with feedback
     `"Scope violation: file <path> not in Files or Tests-may-touch
     of Phase <N>"`. Normal Gate 1 retry/escalation handling applies.

  4. For paths matching `FLEX_REGEX`: count files (≤ FLEX_FILE_CEILING)
     and per-file lines (≤ FLEX_LINE_CEILING). Ceiling violations also
     emit NEEDS_CONTEXT.

  5. If `**Files:**` field cannot be parsed (free-form prose,
     `ALLOWED_REGEX` empty): log warning
     `"Cannot extract scope from Phase <N> Files field; skipping
     post-merge scope check"` and proceed without enforcement
     (matches `r-build.md` Section 2b.4 fallback).

  This check runs ONLY for parallel-worktree dispatches. Serial modes
  (serial-context, serial-agent, file-gated parallel-agent) share the
  working tree and use file-ownership validation at dispatch time
  (`/r-build` Section 2b.4).

  Active session evidence: M13 dispatch produced 5/5 scope violations
  despite explicit prose instruction in the dispatch payload. Layer 1
  (pre-commit hook) is the primary defense — engineers cannot
  physically commit out-of-scope changes. Layer 2 catches if the hook
  was bypassed (`--no-verify`), missing, or buggy.
  ```

- [ ] **Step 5: Verify**

  ```bash
  grep -c 'rdf_scoped_filename\|rdf_parse_phase_scope' canonical/agents/dispatcher.md
  # expect: at least 3 (Load + hook install + post-merge)
  grep -c 'Worktree Pre-Commit Hook Installation\|Post-Merge Scope Check' canonical/agents/dispatcher.md
  # expect: at least 2
  grep -c 'plan-schema.*Rule 8\|Tests-may-touch' canonical/agents/dispatcher.md
  # expect: at least 2
  grep -c '^\s*1\. Written to .rdf/work-output/phase-N-status\.md$' canonical/agents/dispatcher.md
  # expect: 0  (line 295 must be updated)
  grep -c 'phase-<N>-status-<RDF_SESSION_ID>' canonical/agents/dispatcher.md
  # expect: 1  (the new scoped form replaces the old line 295)
  grep -c 'PLAN.md from main repo into worktree\|cp.*PLAN.md.*PROJECT_ROOT' canonical/agents/dispatcher.md
  # expect: at least 1
  ```

- [ ] **Step 6: Commit**

  ```bash
  git add canonical/agents/dispatcher.md
  git commit -m "Dispatcher: scoped phase-result/status paths, hook installation, PLAN.md sync, post-merge scope check

  [Change] dispatcher.md Load: source state/rdf-bus.sh; derive scoped phase-result
    path via rdf_scoped_filename (replaces un-suffixed form that collided across sessions)
  [Change] dispatcher.md line 295 (INFORMATIONAL findings): phase-N-status producer reference
    now uses scoped phase-<N>-status-<RDF_SESSION_ID>.md form (closes schema/code drift)
  [New] dispatcher.md Worktree Pre-Commit Hook Installation: copies state/git-hooks/pre-commit
    into worktree's per-worktree hooks/ dir AND copies main-repo PLAN.md into worktree
    (closes worktree-PLAN-staleness class) before dispatching engineer (P8 layer 1)
  [New] dispatcher.md Post-Merge Scope Check: defense-in-depth backstop using git diff-tree
    + rdf_parse_phase_scope; honors plan-schema Rule 8 Tests-may-touch zone + ceilings
    (P8 layer 2 — addresses 75% leak rate observed in M11 B3 per ~/.rdf/insights.jsonl)"
  ```

---

### Phase 6: Engineer — pre-aggregation dirty check honoring Tests-may-touch

Update `canonical/agents/engineer.md` to add a Setup precondition: before any aggregation/build command (e.g., `make`, codegen), run `git status --porcelain` and fail fast if the working tree contains files outside `**Files:** ∪ **Tests-may-touch:**`. Honors plan-schema Rule 8 ceilings.

**Files:**
- Modify: `canonical/agents/engineer.md` (test: `tests/adapter.bats`)

- **Mode**: serial-context
- **Accept**: Engineer Setup gains a "Pre-aggregation Precondition" subsection. References `git status --porcelain`, names the failure mode, states the action (STOP and report `BLOCKED`), and explicitly cites plan-schema Rule 8 + Tests-may-touch zone.
- **Test**: `grep -c 'git status --porcelain\|Pre-aggregation' canonical/agents/engineer.md` — expect: at least 2. `grep -c 'Tests-may-touch\|plan-schema.*Rule 8' canonical/agents/engineer.md` — expect: at least 1.
- **Edge cases**: phase has no aggregation step (just direct edits) — check is conditional on aggregation/build commands. Phase has empty Tests-may-touch (default) — strict Files-only enforcement applies.
- **Regression-case**: N/A — refactor — protocol documentation only; canonical edit alone introduces no runtime behavior. Behavior change is realized by Phase 10's `rdf generate claude-code` and is regression-tested by the adapter test added in Phase 10 Step 2 (which asserts regenerated dispatcher and engineer surfaces include the new sections). Per plan-schema Rule 6 last paragraph: explicit override — *category retained because canonical edit is a protocol assertion change with no in-phase runtime effect; integration regression is the adapter round-trip test.*

- [ ] **Step 1: Add Pre-aggregation Precondition subsection**

  Locate `### Setup` (lines 13-17) in `canonical/agents/engineer.md`. After the existing 4 bullets, add:

  ```markdown
  ### Pre-aggregation Precondition

  Before running any aggregation or build command that re-assembles
  artifacts from source fragments (`make`, `cat src/*.sh > out`,
  codegen, asset bundling), validate the working tree is clean
  outside your phase scope:

  ```
  git status --porcelain
  ```

  Compute scope by reading PLAN.md for your phase: union of
  `**Files:**` paths and `**Tests-may-touch:**` glob expansion (see
  `canonical/reference/plan-schema.md` Rule 8). The
  `rdf_parse_phase_scope` helper in `state/rdf-bus.sh` produces the
  regex.

  If `git status --porcelain` lists any path outside that union (or
  any path inside the flex zone exceeding ceilings: ≤30 lines per
  file, ≤3 files total), STOP and report:

  ```
  STATUS: BLOCKED
  REASON: working tree contains files outside phase scope: <list>
  ```

  The dispatcher will surface this to the user. Do NOT run the
  aggregation step — the resulting artifact would absorb the
  out-of-scope changes into your phase commit.

  This addresses M10 P4-class incidents where parallel engineers'
  uncommitted work bled into one engineer's aggregated artifact.
  See `docs/specs/2026-04-25-concurrent-sessions-design.md` §2
  for the case study.
  ```

- [ ] **Step 2: Verify**

  ```bash
  grep -c 'git status --porcelain' canonical/agents/engineer.md
  # expect: 1
  grep -c 'Pre-aggregation' canonical/agents/engineer.md
  # expect: 1
  grep -c 'Tests-may-touch\|Rule 8' canonical/agents/engineer.md
  # expect: at least 1
  grep -c 'rdf_parse_phase_scope' canonical/agents/engineer.md
  # expect: 1
  ```

- [ ] **Step 3: Commit**

  ```bash
  git add canonical/agents/engineer.md
  git commit -m "Engineer: pre-aggregation dirty-check precondition honoring Tests-may-touch

  [New] engineer.md Setup: Pre-aggregation Precondition — engineer runs
    'git status --porcelain' before any aggregation/build step; rejects if
    working tree contains files outside Files ∪ Tests-may-touch (plan-schema
    Rule 8) or exceeds flex-zone ceilings
  [Fix] Prevents M10-P4-class incidents where 'make bl' aggregation absorbed
    operator's uncommitted parallel work into wrong phase commit"
  ```

---

### Phase 7: QA — scoped phase-result derivation in EVIDENCE re-validation

Update `canonical/agents/qa.md` to derive `phase-<N>-result-<RDF_SESSION_ID>.md` instead of un-suffixed form when re-validating EVIDENCE blocks.

**Files:**
- Modify: `canonical/agents/qa.md` (test: `tests/adapter.bats`)

- **Mode**: serial-context
- **Accept**: `qa.md` EVIDENCE re-validation section explicitly derives `phase-<N>-result-<RDF_SESSION_ID>.md`. Backwards-compat fallback documented.
- **Test**: `grep -c 'phase-<N>-result-<RDF_SESSION_ID>' canonical/agents/qa.md` — expect: at least 1. `grep -c 'RDF_SESSION_ID' canonical/agents/qa.md` — expect: at least 2.
- **Edge cases**: dispatch payload missing `RDF_SESSION_ID` (older dispatcher) — log warning, fall back to un-suffixed form for backwards compatibility.
- **Regression-case**: N/A — refactor — protocol documentation only; canonical edit alone introduces no runtime behavior. Phase 10's `rdf generate claude-code` regenerates `~/.claude/agents/rdf-qa.md`; the adapter test in Phase 10 Step 2 asserts regenerated content surfaces `phase-<N>-result-<RDF_SESSION_ID>` and `RDF_SESSION_ID`. Per plan-schema Rule 6 last paragraph: explicit override — *category retained because canonical edit is a protocol assertion change with no in-phase runtime effect; integration regression is the adapter round-trip test.*

- [ ] **Step 1: Update EVIDENCE re-validation derivation step**

  In `canonical/agents/qa.md` around line 18 (the `### EVIDENCE re-validation (scope-gated)` section), replace:

  Old:
  ```
    1. Derive the result file path: `.rdf/work-output/phase-<N>-result.md`
       where <N> is the phase number in the dispatch payload
  ```

  New:
  ```
    1. Derive the result file path:
       `.rdf/work-output/phase-<N>-result-<RDF_SESSION_ID>.md`
       where <N> is the phase number and <RDF_SESSION_ID> is the
       session UUIDv7, both from the dispatch payload.
       If RDF_SESSION_ID is absent (older dispatcher), log a warning
       and fall back to un-suffixed `phase-<N>-result.md` for
       backwards compatibility.
  ```

- [ ] **Step 2: Verify**

  ```bash
  grep -c 'phase-<N>-result-<RDF_SESSION_ID>' canonical/agents/qa.md
  # expect: 1
  grep -c 'RDF_SESSION_ID' canonical/agents/qa.md
  # expect: at least 2
  ```

- [ ] **Step 3: Commit**

  ```bash
  git add canonical/agents/qa.md
  git commit -m "QA: scoped phase-result derivation in EVIDENCE re-validation

  [Change] qa.md EVIDENCE re-validation: derive phase-<N>-result-<RDF_SESSION_ID>.md
    from dispatch payload's RDF_SESSION_ID. Backwards-compat fallback to un-suffixed
    form when older dispatcher omits RDF_SESSION_ID."
  ```

---

### Phase 8: r-build.md — UUIDv7 worktree session-id, controller cd, hook copy, build-progress scoped

Update `canonical/commands/r-build.md` to: (a) replace 8-char hex with `${RDF_SESSION_ID}` in §6b, (b) require the controller to `cd` into the worktree before each `Task` dispatch (the actual mechanism per parent CLAUDE.md "Worktree CWD" rule — replaces the no-op `cwd:` payload-field idea after challenge review), (c) add a hook-copy step after `git worktree add`, (d) update `r-build.md:217,284` `build-progress.md` writes to scoped form (the build-progress incident #2 producer that the prior draft missed).

**Files:**
- Modify: `canonical/commands/r-build.md` (test: `tests/adapter.bats`)

- **Mode**: serial-agent
- **Accept**: §6b replaces literal `session-id = 8-char random hex` with `session-id = ${RDF_SESSION_ID}`. Worktree paths in steps 2, 3, 5, 6 reference `${RDF_SESSION_ID}` directly. New hook-copy step appears after `git worktree add`. New explicit step: *"controller MUST `cd .worktrees/rdf-phase-{N}-${RDF_SESSION_ID}` before dispatching each Task"*. Lines 217 and 284 use scoped `build-progress-${RDF_SESSION_ID}.md`. Nested-invocation constraint note appears.
- **Test**: `grep -c 'RDF_SESSION_ID' canonical/commands/r-build.md` — expect: at least 7 (preamble + step 2 + 4 path refs + build-progress refs). `grep -c '8-char random hex\|{session-id}' canonical/commands/r-build.md` — expect: 0. `grep -c 'state/git-hooks/pre-commit' canonical/commands/r-build.md` — expect: 1. `grep -c 'cd \.worktrees\|cd into the worktree' canonical/commands/r-build.md` — expect: at least 1. `grep -nE 'build-progress\.md\b' canonical/commands/r-build.md` — expect: 0 (every occurrence scoped).
- **Edge cases**: nested `/r-build` from inside a subagent — subagents inherit parent `RDF_SESSION_ID`, so worktree paths would collide. Document explicit constraint: worktree dispatch is top-level only (the PARALLEL_BATCH downgrade in dispatcher.md:45-49 already prevents nested parallel; this makes it explicit). Operator runs `/r-build` from a CWD that is not the project root (rare) — the `cd .worktrees/...` instruction already implies project-root execution; document explicitly.
- **Regression-case**: N/A — refactor — replaces ad-hoc hex with standardized session ID, scopes build-progress, documents controller cd; worktree creation/cleanup exercised by /r-build itself. Per plan-schema Rule 6 last paragraph: explicit override — *category retained because canonical edit is a protocol assertion change with no in-phase runtime effect; integration regression is Phase 10's adapter round-trip test asserting regenerated r-build surfaces RDF_SESSION_ID and the cd instruction.*

- [ ] **Step 1: Insert §6b preamble**

  Locate `### 6b. Dispatch Parallel Batch` (line 166). Insert immediately after the heading:

  ```markdown
  Before any worktree creation, source `state/rdf-bus.sh` and call
  `rdf_session_init` to ensure `RDF_SESSION_ID` is set. Worktree paths
  and branch names use the full UUID for collision-free identification
  across concurrent sessions on the same repository.
  ```

- [ ] **Step 2: Replace session-id derivation note**

  Around line 184-185, replace:

  Old:
  ```
     git worktree add .worktrees/rdf-phase-{N}-{session-id} -b rdf/phase-{N}-{session-id} HEAD
     (session-id = 8-char random hex, prevents cross-session collisions)
  ```

  New:
  ```
     git worktree add .worktrees/rdf-phase-{N}-${RDF_SESSION_ID} -b rdf/phase-{N}-${RDF_SESSION_ID} HEAD
     (RDF_SESSION_ID is the full UUIDv7; prevents cross-session collisions)
  ```

- [ ] **Step 3: Add hook-copy step**

  Immediately after the `git worktree add` line in step 2 of the worktree dispatch path, add a new sub-step:

  ```markdown
     After `git worktree add`, install the pre-commit hook into the
     worktree's per-worktree hooks directory:

     ```
     wt_git_dir=$(git -C .worktrees/rdf-phase-{N}-${RDF_SESSION_ID} rev-parse --git-dir)
     command cp state/git-hooks/pre-commit "${wt_git_dir}/hooks/pre-commit"
     command chmod +x "${wt_git_dir}/hooks/pre-commit"
     ```

     The hook enforces phase scope (Files ∪ Tests-may-touch) at
     `git commit` time. See `plan-schema.md` Rule 8 and dispatcher.md
     "Worktree Pre-Commit Hook Installation".
  ```

- [ ] **Step 4: Update remaining `{session-id}` references in §6b**

  Replace every occurrence of `{session-id}` in lines 184-205 with `${RDF_SESSION_ID}`. Specifically the rebase line, merge line, and two cleanup lines (worktree remove + branch -d).

- [ ] **Step 5: Add explicit controller-cd step before Task dispatch**

  The `Task` (Agent) tool does not accept a `cwd` parameter — verified against the live tool surface. The actual mechanism per parent workspace CLAUDE.md "Worktree CWD" note is *"dispatch worktree agents from inside the target project directory."* That means the controller (the bash session running `/r-build`) must `cd` into the worktree before invoking each `Task` call.

  Locate Section 6b "Worktree dispatch" step 3 (the `Dispatch N rdf-dispatcher subagents simultaneously` block, lines ~186-190). Insert this requirement at the start of the step:

  ```markdown
  3. Before each `Task` dispatch, the controller MUST change directory
     into the target worktree:
     ```
     cd .worktrees/rdf-phase-{N}-${RDF_SESSION_ID}
     ```
     The `Task` tool inherits the controller's CWD; the SDK picks an
     adjacent repo non-deterministically when CWD has no `.git/`
     (see workspace CLAUDE.md "Worktree CWD"). This `cd` is the
     actual mechanism that closes the non-deterministic-CWD class.
     For parallel dispatches in a batch, the controller serializes
     the `cd → Task` pair per-phase (parallelism comes from the
     `Task` calls returning before the subagent finishes, not from
     simultaneous `cd`s).

  Then dispatch N rdf-dispatcher subagents:
  ```

  Do NOT add a `cwd:` field to the dispatch payload — it would be a
  documentation no-op since the `Task` tool does not consume it.

- [ ] **Step 6: Update `build-progress.md` writes to scoped form (lines 217, 284)**

  Locate `r-build.md` line 217 ("Progress tracking:" block):

  Old:
  ```
  Write batch progress to `.rdf/work-output/build-progress.md`:
  ```

  New:
  ```
  Write batch progress to `.rdf/work-output/build-progress-${RDF_SESSION_ID}.md`
  (derived via `rdf_scoped_filename` from `state/rdf-bus.sh`):
  ```

  Locate `r-build.md` line 284 (failure-handling Option 3):

  Old:
  ```
     - Option 3: Write progress to build-progress.md, stop. User can
       resume with `/r-build --parallel` (reads progress file)
  ```

  New:
  ```
     - Option 3: Write progress to
       `build-progress-${RDF_SESSION_ID}.md`, stop. User can resume
       with `/r-build --parallel` (which calls `rdf_session_init`
       and reads the scoped progress file).
  ```

  Closes incident #2 (`build-progress.md` overwrites) — the writer site that the prior draft missed; Phase 2 schema declares the scoped form, this step makes the producer match.

- [ ] **Step 7: Add nested-invocation constraint note**

  At the end of §6b worktree dispatch (after step 7 "Collect results"), add:

  ```markdown
  **Constraint:** Worktree dispatch MUST be invoked from a top-level
  session, not from a subagent. Subagents inherit `RDF_SESSION_ID`
  from their parent and would create colliding worktree paths.
  The `PARALLEL_BATCH` downgrade in `dispatcher.md` (lines 45-49)
  already prevents nested parallel dispatch; this is its
  worktree-specific explicit form.
  ```

- [ ] **Step 8: Verify**

  ```bash
  grep -c 'RDF_SESSION_ID' canonical/commands/r-build.md
  # expect: at least 7
  grep -c '8-char random hex\|{session-id}' canonical/commands/r-build.md
  # expect: 0
  grep -c 'state/git-hooks/pre-commit' canonical/commands/r-build.md
  # expect: 1
  grep -c 'cd \.worktrees\|cd into the worktree' canonical/commands/r-build.md
  # expect: at least 1
  grep -nE 'build-progress\.md\b' canonical/commands/r-build.md
  # expect: (no output — every occurrence is the scoped form)
  grep -c 'cwd:' canonical/commands/r-build.md
  # expect: 0  (no payload-field cwd; mechanism is controller cd)
  ```

- [ ] **Step 9: Commit**

  ```bash
  git add canonical/commands/r-build.md
  git commit -m "r-build: UUIDv7 worktree session-id, controller cd, hook copy, scoped build-progress

  [Change] r-build.md §6b: worktree path and branch use full UUIDv7 RDF_SESSION_ID
    (was 8-char ad-hoc hex); preamble sources state/rdf-bus.sh and calls rdf_session_init
  [New] r-build.md §6b: post-worktree-add step copies state/git-hooks/pre-commit into
    worktree's per-worktree hooks/ directory (P8 layer 1 enforcement)
  [New] r-build.md §6b step 3: explicit controller cd into worktree before each Task
    dispatch — actual mechanism per workspace CLAUDE.md 'Worktree CWD' note (Task tool
    does not accept cwd parameter; controller's CWD is what the SDK inherits)
  [Change] r-build.md lines 217, 284: build-progress.md → build-progress-\${RDF_SESSION_ID}.md
    (closes incident #2 producer site that prior draft missed)
  [New] r-build.md §6b: nested-invocation constraint note (worktree dispatch must
    be top-level, not from subagents — colliding RDF_SESSION_ID inheritance)"
  ```

---

### Phase 9: Pipeline writers + all consumers — scoped progress filenames everywhere

Update the three pipeline-stage commands (writers) AND every consumer/cross-reference of the four progress-file basenames (vpe/spec/ship/build-progress). The prior draft only covered writers; challenge review identified five consumer files that would silently miss session-scoped files after Wave A ships and report "no session in progress" for active sessions. This phase covers all eight files in parallel tracks.

**Files:**
- Modify: `canonical/commands/r-vpe.md` (test: `tests/adapter.bats`)
- Modify: `canonical/commands/r-spec.md` (test: `tests/adapter.bats`)
- Modify: `canonical/commands/r-ship.md` (test: `tests/adapter.bats`)
- Modify: `canonical/commands/r-start.md` (test: `tests/adapter.bats`)
- Modify: `canonical/commands/r-status.md` (test: `tests/adapter.bats`)
- Modify: `canonical/commands/r-save.md` (test: `tests/adapter.bats`)
- Modify: `canonical/commands/r-refresh.md` (test: `tests/adapter.bats`)
- Modify: `canonical/reference/session-safety.md` (test: `tests/adapter.bats`)

- **Mode**: parallel-agent (8 independent files; no cross-references between them in this phase)
- **Accept**: All three writers (r-vpe, r-spec, r-ship) reference `${RDF_SESSION_ID}` in their state-write paths and resume protocols. All five consumers (r-start, r-status, r-save, r-refresh, session-safety.md) glob the scoped form (`vpe-progress-*.md` etc.) instead of testing for un-suffixed existence. r-status.md also updates `phase-N-status.md` glob pattern. No file retains an un-suffixed `vpe-progress.md|spec-progress.md|ship-progress.md|build-progress.md` reference except in legacy-import prompts.
- **Test**: `grep -nE 'vpe-progress\.md\b|spec-progress\.md\b|ship-progress\.md\b|build-progress\.md\b' canonical/commands/r-vpe.md canonical/commands/r-spec.md canonical/commands/r-ship.md canonical/commands/r-start.md canonical/commands/r-status.md canonical/commands/r-save.md canonical/commands/r-refresh.md canonical/reference/session-safety.md | grep -v 'legacy\|Import?\|*\\.md' | grep -v 'rdf_scoped_filename'` — expect: (no output) — every reference is scoped or a legacy/glob form. `grep -c 'RDF_SESSION_ID\|rdf_session_init\|vpe-progress-\*\.md\|spec-progress-\*\.md\|ship-progress-\*\.md\|build-progress-\*\.md' canonical/commands/r-start.md canonical/commands/r-status.md` — expect: at least 4 each.
- **Edge cases**: resume/status from a session that crashed before `rdf_session_init` ran — no scoped file matches; if exactly one un-suffixed legacy file exists, consumer prompts user to import it. Multiple session-scoped files exist (e.g., parallel sessions on same project) — consumers list all matching by mtime, most recent at top. r-refresh.md and session-safety.md are documentation references — safe to update without behavior consequence.
- **Regression-case**: N/A — refactor — pure path/glob substitution; behavior change is realized by Phase 10's regeneration. Per plan-schema Rule 6 last paragraph: explicit override — *category retained because canonical edits are documentation/protocol changes; integration regression is Phase 10's adapter test asserting regenerated content has scoped patterns.*

**File ownership boundaries (8 tracks, no overlap):**
- Track A (r-vpe.md writer): `canonical/commands/r-vpe.md` only
- Track B (r-spec.md writer): `canonical/commands/r-spec.md` only
- Track C (r-ship.md writer): `canonical/commands/r-ship.md` only
- Track D (r-start.md consumer): `canonical/commands/r-start.md` only
- Track E (r-status.md consumer): `canonical/commands/r-status.md` only
- Track F (r-save.md consumer): `canonical/commands/r-save.md` only
- Track G (r-refresh.md cross-reference): `canonical/commands/r-refresh.md` only
- Track H (session-safety.md reference): `canonical/reference/session-safety.md` only

- [ ] **Step 1: Update r-vpe.md** *(Track A)*

  In `canonical/commands/r-vpe.md`:

  1. Line 44 — Replace:
     ```
     If --resume is specified or .rdf/work-output/vpe-progress.md exists:
     ```
     With:
     ```
     If --resume is specified, source `state/rdf-bus.sh`, call
     `rdf_session_init`, and look for
     `.rdf/work-output/vpe-progress-${RDF_SESSION_ID}.md`. If not
     found, glob `.rdf/work-output/vpe-progress-*.md` and present
     candidates ordered by mtime. If exactly one un-suffixed
     `.rdf/work-output/vpe-progress.md` exists (legacy from pre-3.1.0),
     prompt: "Found legacy progress file. Import? [Y/n]".
     ```

  2. Line 100 — Replace:
     ```
     Write state:
       .rdf/work-output/vpe-progress.md:
     ```
     With:
     ```
     Write state to .rdf/work-output/vpe-progress-${RDF_SESSION_ID}.md:
     ```

  3. Line 204 — Replace:
     ```
     Clean up: vpe-progress.md retained for session log reference.
     ```
     With:
     ```
     Clean up: vpe-progress-${RDF_SESSION_ID}.md retained for session log reference.
     ```

  4. Line 214 — Replace:
     ```
     - Track state in vpe-progress.md for crash recovery at every stage transition
     ```
     With:
     ```
     - Track state in vpe-progress-${RDF_SESSION_ID}.md for crash recovery at every stage transition
     ```

- [ ] **Step 2: Update r-spec.md** *(Track B)*

  Apply same substitution pattern to `canonical/commands/r-spec.md`. Relevant lines per earlier grep: 13, 72, 228, 295, 562, 608. Insert the source + `rdf_session_init` preamble + legacy-file fallback in the resume protocol section (around line 72).

- [ ] **Step 3: Update r-ship.md** *(Track C)*

  Apply same substitution pattern to `canonical/commands/r-ship.md`. Relevant lines per earlier grep: 19, 24, 26, 265. Insert source + `rdf_session_init` preamble in the resume detection block (around line 19).

- [ ] **Step 4: Update r-start.md** *(Track D — consumer)*

  In `canonical/commands/r-start.md` lines 143-146, the four progress-file existence checks must:
  1. Source `state/rdf-bus.sh` and call `rdf_session_init` first.
  2. Look for the scoped form first; if not found, glob for any session-scoped file (`vpe-progress-*.md`); if exactly one un-suffixed legacy file exists, prompt one-shot import.

  Replace each `<basename>.md exists →` block. Example for the spec line (line 143):

  Old:
  ```
  - `spec-progress.md` exists → `Spec — {topic}, Phase {N}`
  ```

  New:
  ```
  - source `state/rdf-bus.sh`; `rdf_session_init`
  - `.rdf/work-output/spec-progress-${RDF_SESSION_ID}.md` exists →
    `Spec — {topic}, Phase {N}`
  - else, glob `.rdf/work-output/spec-progress-*.md` (other sessions
    may be in progress) → list with mtime, present
  - else, legacy `.rdf/work-output/spec-progress.md` exists → prompt
    "Import legacy spec-progress.md? [Y/n]"
  ```

  Apply the same pattern to lines 144 (vpe), 145 (ship), and 146 (build).

- [ ] **Step 5: Update r-status.md** *(Track E — consumer + phase-N-status pattern)*

  In `canonical/commands/r-status.md`:

  1. Line 30 — Replace:
     ```
     These files follow the pattern `.rdf/work-output/phase-N-status.md`.
     ```
     With:
     ```
     These files follow the pattern
     `.rdf/work-output/phase-<N>-status-<SESSION_ID>.md`. The status
     command globs `phase-*-status-*.md` and groups by session ID
     for display.
     ```

  2. Lines 101-118 — Apply the same source + rdf_session_init + glob-first-then-legacy pattern as Step 4 to all four progress consumers (spec, vpe, ship, build).

- [ ] **Step 6: Update r-save.md** *(Track F — consumer)*

  In `canonical/commands/r-save.md` line 107, replace:

  Old:
  ```
  - If `.rdf/work-output/spec-progress.md` exists, read the `SPEC_PATH`
  ```

  New:
  ```
  - Source `state/rdf-bus.sh`; `rdf_session_init`. If
    `.rdf/work-output/spec-progress-${RDF_SESSION_ID}.md` exists,
    read the `SPEC_PATH`. If not, fall back to glob
    `.rdf/work-output/spec-progress-*.md` (most recent by mtime);
    if neither found, fall back to legacy
    `.rdf/work-output/spec-progress.md` (pre-3.1.0).
  ```

- [ ] **Step 7: Update r-refresh.md** *(Track G — cross-reference)*

  In `canonical/commands/r-refresh.md`:

  1. Lines 262-263 — Update the artifact column entries to reflect the scoped form. Replace:
     ```
     | `spec-progress.md` | *updated* | cross-referenced with `docs/specs/` |
     | `ship-progress.md` | *updated* | stage validated against git tags |
     ```
     With:
     ```
     | `spec-progress-<SESSION_ID>.md` | *updated* | cross-referenced with `docs/specs/` |
     | `ship-progress-<SESSION_ID>.md` | *updated* | stage validated against git tags |
     ```

  2. Lines 269-270 — Replace:
     ```
     `current-phase.md`, `agent-feed.log`, `spec-progress.md`,
     `ship-progress.md`.
     ```
     With:
     ```
     `current-phase.md`, `agent-feed.log`, `spec-progress-<SESSION_ID>.md`,
     `ship-progress-<SESSION_ID>.md`.
     ```

- [ ] **Step 8: Update session-safety.md** *(Track H — reference)*

  In `canonical/reference/session-safety.md` lines 53-59, update the four progress-file references in the stale-session checklist:

  Old:
  ```
     - `.rdf/work-output/spec-progress.md` -- design session in progress; contains topic,
     - `.rdf/work-output/ship-progress.md` -- release workflow in progress; contains stage
     - `.rdf/work-output/vpe-progress.md` -- VPE pipeline state; contains current stage
     - `.rdf/work-output/build-progress.md` -- parallel build state; contains batch
  ```

  New:
  ```
     - `.rdf/work-output/spec-progress-<SESSION_ID>.md` -- design session in progress; contains topic,
     - `.rdf/work-output/ship-progress-<SESSION_ID>.md` -- release workflow in progress; contains stage
     - `.rdf/work-output/vpe-progress-<SESSION_ID>.md` -- VPE pipeline state; contains current stage
     - `.rdf/work-output/build-progress-<SESSION_ID>.md` -- parallel build state; contains batch
  ```

  Add a one-line note immediately above this list: *"Per Wave A (RDF 3.1.0), each progress file is suffixed with the writing session's UUIDv7 RDF_SESSION_ID. Glob `<basename>-*.md` to enumerate across sessions."*

- [ ] **Step 9: Verify all 8 files**

  ```bash
  grep -nE 'vpe-progress\.md\b|spec-progress\.md\b|ship-progress\.md\b|build-progress\.md\b' \
    canonical/commands/r-vpe.md canonical/commands/r-spec.md canonical/commands/r-ship.md \
    canonical/commands/r-start.md canonical/commands/r-status.md canonical/commands/r-save.md \
    canonical/commands/r-refresh.md canonical/reference/session-safety.md \
    | grep -v 'legacy\|Import?\|\*\.md\|<SESSION_ID>'
  # expect: (no output) — every basename reference is either scoped, glob, or legacy-import
  grep -c 'RDF_SESSION_ID' canonical/commands/r-vpe.md
  # expect: at least 3
  grep -c 'RDF_SESSION_ID' canonical/commands/r-spec.md
  # expect: at least 3
  grep -c 'RDF_SESSION_ID' canonical/commands/r-ship.md
  # expect: at least 3
  grep -c 'RDF_SESSION_ID\|rdf_session_init' canonical/commands/r-start.md
  # expect: at least 4 (one per progress check)
  grep -c 'RDF_SESSION_ID\|rdf_session_init' canonical/commands/r-status.md
  # expect: at least 4
  grep -c 'phase-<N>-status-<SESSION_ID>' canonical/commands/r-status.md
  # expect: 1
  ```

- [ ] **Step 10: Commit (single commit covering all 8 files — one logical change)**

  ```bash
  git add canonical/commands/r-vpe.md canonical/commands/r-spec.md canonical/commands/r-ship.md \
          canonical/commands/r-start.md canonical/commands/r-status.md canonical/commands/r-save.md \
          canonical/commands/r-refresh.md canonical/reference/session-safety.md
  git commit -m "Pipeline writers and consumers: scoped progress filenames everywhere

  [Change] r-vpe.md, r-spec.md, r-ship.md (writers): state-write paths now suffixed with
    \${RDF_SESSION_ID} (vpe-progress-<UUID>.md etc.); resume protocols glob scoped form first,
    fall back to legacy un-suffixed file with one-shot import prompt
  [Change] r-start.md, r-status.md (consumers): source state/rdf-bus.sh and call rdf_session_init;
    look for current-session scoped file first, glob across sessions if absent, fall back to legacy
  [Change] r-status.md: phase-N-status pattern documented as
    phase-<N>-status-<SESSION_ID>.md (matches Phase 5 dispatcher producer update)
  [Change] r-save.md, r-refresh.md, session-safety.md: documentation/cross-reference updates for
    scoped form
  [Fix] Closes the silent-miss-after-deployment class identified in challenge review — without
    these consumer updates, /r-start, /r-status, /r-save would report 'no session in progress'
    for active sessions after Wave A ships"
  ```

---

### Phase 10: Tests, regenerate, version bump, changelog

Run BATS, regenerate `~/.claude/`, bump VERSION to 3.1.0, update RDF.md, write batched 3.1.0 entries to CHANGELOG and CHANGELOG.RELEASE.

**Files:**
- Modify: `VERSION` (test: N/A — release metadata)
- Modify: `RDF.md` (test: N/A — release metadata)
- Modify: `CHANGELOG` (test: N/A — release metadata)
- Modify: `CHANGELOG.RELEASE` (test: N/A — release metadata)
- Modify: `tests/adapter.bats` (test: itself — extended with 1 new test)

- **Mode**: serial-agent
- **Accept**: `VERSION` reads `3.1.0`. `RDF.md` version reference is `3.1.0`. CHANGELOG and CHANGELOG.RELEASE both have a `## 3.1.0` section with batched [New]/[Change]/[Fix] entries covering Phases 1-9. `bats tests/rdf-bus.bats tests/adapter.bats` reports all tests pass. `rdf generate claude-code` exits 0. `rdf doctor --all` reports no FAILs.
- **Test**: `bats tests/rdf-bus.bats tests/adapter.bats` — expect: all tests pass (11 from rdf-bus + N from adapter, current count + 1 new). `rdf doctor --all` — expect: zero FAILs. `cat VERSION` — expect: `3.1.0`. `grep -c '## 3.1.0' CHANGELOG` — expect: 1.
- **Edge cases**: `rdf generate claude-code` may regenerate hook scripts that source `state/rdf-bus.sh` — for Wave A, no hook adapter changes required since sourcing happens lazily inside command bodies.
- **Regression-case**: `tests/adapter.bats::@test "regenerated dispatcher.md mentions RDF_SESSION_ID and Tests-may-touch"` (added in this phase, see Step 4)

- [ ] **Step 1: Run the test suite**

  ```bash
  bats tests/rdf-bus.bats
  # expect: 11 tests, 0 failures
  bats tests/adapter.bats
  # expect: all tests pass (count varies)
  ```

- [ ] **Step 2: Add adapter test for new surfaces**

  Read the last 20 lines of `tests/adapter.bats` to match style, then append:

  ```bash
  @test "regenerated dispatcher mentions RDF_SESSION_ID, Tests-may-touch, hook installation" {
      test_home="$(mktemp -d)"
      output_dir="$(mktemp -d)"
      _generate "$test_home" "$output_dir"
      grep -q 'RDF_SESSION_ID' "$output_dir/agents/rdf-dispatcher.md"
      grep -q 'rdf_scoped_filename' "$output_dir/agents/rdf-dispatcher.md"
      grep -q 'Worktree Pre-Commit Hook Installation' "$output_dir/agents/rdf-dispatcher.md"
      grep -q 'Post-Merge Scope Check' "$output_dir/agents/rdf-dispatcher.md"
      grep -q 'Tests-may-touch' "$output_dir/agents/rdf-dispatcher.md"
      grep -q 'phase-<N>-status-<RDF_SESSION_ID>' "$output_dir/agents/rdf-dispatcher.md"
      command rm -rf "$test_home" "$output_dir"
  }

  @test "regenerated r-build mentions UUIDv7 worktree session-id and controller cd" {
      test_home="$(mktemp -d)"
      output_dir="$(mktemp -d)"
      _generate "$test_home" "$output_dir"
      grep -q 'RDF_SESSION_ID' "$output_dir/commands/r-build.md"
      grep -q 'state/git-hooks/pre-commit' "$output_dir/commands/r-build.md"
      grep -q 'cd \.worktrees\|cd into the worktree' "$output_dir/commands/r-build.md"
      grep -q 'build-progress-\${RDF_SESSION_ID}' "$output_dir/commands/r-build.md"
      ! grep -q '8-char random hex' "$output_dir/commands/r-build.md"
      command rm -rf "$test_home" "$output_dir"
  }

  @test "regenerated consumers (r-start, r-status) glob scoped progress files" {
      test_home="$(mktemp -d)"
      output_dir="$(mktemp -d)"
      _generate "$test_home" "$output_dir"
      grep -q 'rdf_session_init\|RDF_SESSION_ID' "$output_dir/commands/r-start.md"
      grep -q 'rdf_session_init\|RDF_SESSION_ID' "$output_dir/commands/r-status.md"
      grep -q 'phase-<N>-status-<SESSION_ID>' "$output_dir/commands/r-status.md"
      command rm -rf "$test_home" "$output_dir"
  }
  ```

  Re-run:
  ```bash
  bats tests/adapter.bats
  # expect: count_before + 3 tests, 0 failures (3 new: dispatcher surfaces, r-build surfaces, consumers glob)
  ```

- [ ] **Step 3: Regenerate ~/.claude/ and verify with doctor**

  ```bash
  rdf generate claude-code
  # expect: (no errors)
  rdf doctor --all
  # expect: zero FAILs
  ```

- [ ] **Step 4: Bump VERSION and RDF.md**

  Update `VERSION` to:
  ```
  3.1.0
  ```

  Read `RDF.md` to find the current version reference (`3.0.7`) and change to `3.1.0`.

- [ ] **Step 5: Write CHANGELOG entry**

  Read the existing top of CHANGELOG to match the format, then prepend:

  ```markdown
  ## 3.1.0 — Concurrent Sessions Wave A (Stop the Bleeding)

  Foundation for multi-session safety. Establishes session identity, scoped
  state filenames, structurally-enforced worktree boundary (pre-commit hook
  + dispatcher backstop), pre-aggregation dirty check, and the Tests-may-touch
  scope-flex zone that makes the enforcement livable. Addresses six recurring
  incidents observed in blacklight (M6–M13); validated against active running
  session feedback (M13 dispatch, 5/5 prose-instruction violations).
  See docs/specs/2026-04-25-concurrent-sessions-design.md.

  [New] state/rdf-bus.sh — helper library: rdf_session_init (UUIDv7),
    rdf_scoped_filename, rdf_session_short, rdf_parse_phase_scope
  [New] state/git-hooks/pre-commit — worktree pre-commit hook physically
    rejecting out-of-scope commits before they land (P8 layer 1 enforcement)
  [New] tests/rdf-bus.bats — 10 unit + integration tests
  [New] framework.md — Session Identity subsection documenting RDF_SESSION_ID;
    Category 2 + Category 3 transient-state tables now use session-suffixed names
  [New] plan-schema.md Rule 8 — Tests-may-touch scope-flex zone with per-file
    (≤30 lines) and global (≤3 files) ceilings
  [New] dispatcher.md — Worktree Pre-Commit Hook Installation step + Post-Merge
    Scope Check (defense-in-depth backstop, addresses 75% leak rate from M11 B3)
  [New] engineer.md — Pre-aggregation Precondition: git status --porcelain
    before any aggregation/build step; honors Tests-may-touch zone (M10 P4 fix)
  [New] r-build.md §6b — pre-commit hook installation step after git worktree add;
    explicit controller `cd` into worktree before each Task dispatch (the actual
    mechanism per workspace CLAUDE.md "Worktree CWD" note — closes non-deterministic
    CWD class; `Task` tool does not accept a cwd parameter);
    nested-invocation constraint note; build-progress.md writes scoped to ${RDF_SESSION_ID}
  [New] tests/adapter.bats — regression test verifying regenerated dispatcher
    surfaces RDF_SESSION_ID, rdf_scoped_filename, hook installation, scope check,
    Tests-may-touch
  [Change] dispatcher.md, qa.md — phase-N-result and phase-N-status paths now
    scoped via rdf_scoped_filename (was un-suffixed; collided across sessions)
  [Change] r-build.md §6b — worktree path and branch use full RDF_SESSION_ID
    UUIDv7 (was 8-char ad-hoc hex)
  [Change] r-vpe.md, r-spec.md, r-ship.md — vpe-progress.md, spec-progress.md,
    ship-progress.md write paths now scoped with ${RDF_SESSION_ID}; resume
    protocols look for scoped form first, prompt to import legacy un-suffixed
    file if present
  ```

- [ ] **Step 6: Write CHANGELOG.RELEASE entry**

  Read top 30 lines of `CHANGELOG.RELEASE` to match style, then prepend:

  ```markdown
  ## 3.1.0 — Concurrent Sessions Wave A

  This release ships the foundation primitives for multi-session safety
  on a single repository. RDF previously assumed serial execution within
  one controller session; in practice, parallel Claude Code sessions
  against the same project (e.g., advancing different milestones in
  different terminals) produced state-file collisions, worktree leakage
  (75% leak rate observed in M11 B3), and aggregation builds absorbing
  uncommitted parallel work.

  Wave A introduces:
  - **Session identity** — every session generates a UUIDv7
    (`RDF_SESSION_ID`), inheritable by subagents
  - **Scoped state filenames** — phase-result, vpe-progress,
    spec-progress, ship-progress files all suffixed with the session ID
  - **Structurally-enforced worktree scope** — pre-commit hook installed
    in every worktree physically rejects out-of-scope commits; dispatcher
    post-merge check is the defense-in-depth backstop
  - **Pre-aggregation dirty check** — engineers fail fast on out-of-scope
    dirty files before running aggregation/build steps
  - **Tests-may-touch scope-flex zone** — optional plan-schema.md Rule 8
    that pre-authorizes paths for trivial test-infra drift (≤30 lines,
    ≤3 files), making the structural enforcement livable

  Backwards compatibility: legacy un-suffixed progress files are detected
  on resume and offered for one-shot import. Older dispatcher invocations
  (no RDF_SESSION_ID in payload) fall back to un-suffixed paths with a
  warning. Phases without `**Tests-may-touch:**` get strict Files-only
  enforcement (current behavior).

  Waves B (cross-session bus + status broadcast + `/r-msg`) and C (atomic
  write helpers + OFD locks + worktree liveness sweeper) are planned
  follow-ons.

  Design: docs/specs/2026-04-25-concurrent-sessions-design.md
  ```

- [ ] **Step 7: Final verification**

  ```bash
  cat VERSION
  # expect: 3.1.0
  grep -c '## 3.1.0' CHANGELOG
  # expect: 1
  grep -c '## 3.1.0' CHANGELOG.RELEASE
  # expect: 1
  grep -c '3.1.0' RDF.md
  # expect: at least 1
  bats tests/rdf-bus.bats tests/adapter.bats
  # expect: all tests pass
  rdf doctor --all
  # expect: zero FAILs
  ```

- [ ] **Step 8: Commit**

  ```bash
  git add VERSION RDF.md CHANGELOG CHANGELOG.RELEASE tests/adapter.bats
  git commit -m "Version 3.1.0 — Concurrent Sessions Wave A release

  [Change] VERSION, RDF.md — 3.0.7 → 3.1.0
  [New] CHANGELOG, CHANGELOG.RELEASE — 3.1.0 section with batched [New]/[Change]
    entries covering all 9 prior phases
  [New] tests/adapter.bats — 3 regression tests covering: regenerated dispatcher
    surfaces (RDF_SESSION_ID, Tests-may-touch, hook installation, post-merge scope
    check, scoped phase-N-status); regenerated r-build surfaces (UUIDv7 session-id,
    controller cd, scoped build-progress); regenerated consumers (r-start, r-status)
    surface rdf_session_init and scoped phase-N-status pattern"
  ```

---
