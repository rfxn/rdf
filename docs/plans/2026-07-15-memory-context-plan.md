# Implementation Plan: RDF 3.4 "Memory & Context"

**Goal:** Merge zero-effort auto-learning/memory with context thrift — a
SessionEnd capture hook (appends to the session journal + writes a cache),
a `/r-save` that does measurably less work at save time (cache-hit skip +
deterministic classification moved into `rdf-state.sh`), auto-acting
thresholds, a lessons ID-index injected at SessionStart, a gated
consolidation pass, `paths:`-scoped governance rules (T3), a published
per-session token-cost harness, and an `rdf-lite` minimal deployment —
without adding a top-level command, changing the 6 agents, or altering the
4 lifecycle verbs.

**Architecture:** Two new Claude-side hooks (`session-end-capture.sh`,
`session-start-inject.sh`) wired into `adapters/claude-code/hooks/hooks.json`;
two new deterministic state helpers (`state/rdf-lessons.sh`,
`state/rdf-overhead.sh`); a `cc_generate_rules()` adapter function emitting
`output/rules/<profile>.md` (core unscoped, language `paths:`-scoped); a
`--lite` generate/deploy variant sourcing a condensed
`profiles/lite/governance-lite.md`; and canonical-command edits that consume
the capture cache and turn thresholds into actions. Native auto-memory owns
conversational memory and MEMORY.md loading; RDF owns the delta.

**Tech Stack:** bash 4.1+ (`#!/bin/bash` + `set -uo pipefail` for hooks;
`#!/usr/bin/env bash` + `set -euo pipefail` for state helpers/adapters), jq
(degrade gracefully when absent), BATS via batsman, GitHub Actions.

**Spec:** docs/specs/2026-07-15-memory-context-design.md

**Phases:** 9 (Phase 0 re-triage + 8 build phases)

**Plan Version:** 3.6

## Progress

Not started. Phase 0 first (re-triage), then build.

## Conventions

**Hook script boilerplate** — new hook scripts start with:

```bash
#!/bin/bash
# canonical/scripts/<name>.sh — <SessionEnd|SessionStart> hook
# (C) 2026 R-fx Networks <proj@rfxn.com>
# GNU GPL v2
set -uo pipefail   # NOT -e: a probe failure must never abort a hook
```

Hooks ALWAYS exit 0. Every `2>/dev/null` / `|| true` carries a same-line
justification comment. No coreutils bare — `command`-prefix in project
source (hooks ship to target OSes).

**State-helper boilerplate** — `state/*.sh` start with:

```bash
#!/usr/bin/env bash
# state/<name>.sh — <purpose>
# (C) 2026 R-fx Networks <proj@rfxn.com>
# GNU GPL v2
set -euo pipefail
```

**Naming pattern** — adapter function `cc_generate_rules()`, private helper
`_cc_paths_frontmatter()`; lessons IDs `[<CategoryInitial><ordinal>]`
persisted as `<!-- id:W1 -->`.

**Commit message format** — free-form summary line; body lines tagged
`[New]` / `[Change]` / `[Fix]` / `[Remove]`; stage files explicitly by name;
CHANGELOG + CHANGELOG.RELEASE updated only in the final release phase
(Phase 8) per RDF batch pattern for a single-version feature branch.

**Test harness pattern** — `tests/memory-context.bats` mirrors
`tests/adapter.bats`: hermetic `mktemp -d` HOME + RDF_HOME per test, bare
coreutils inside `.bats` (Docker containers, no alias), `run bash -c '...'`
for hook invocations to control stdin.

**CRITICAL:**
- `canonical/` stays tool-agnostic + frontmatter-free. `paths:` frontmatter,
  `hookSpecificOutput` JSON, and SessionEnd matcher lists live ONLY in
  `adapters/claude-code/` and hook scripts.
- Adapter CC output (`adapters/claude-code/output/**`) is local-only
  (`.git/info/exclude`) — NOT committed. Verify `git check-ignore
  adapters/claude-code/output/rules/core.md` exits 0 before assuming.
- `sed` stays POSIX BRE-portable (macOS CI runs BATS) — no `\b`, no `\|`.
- Hooks + state helpers degrade to a no-op (exit 0 / empty output) when `jq`
  is absent — never block startup/shutdown.
- `bash -n` + `shellcheck` on every touched shell file before each commit.

## RC Contract Evidence

Helpers with return-code contracts used by new code (verified against source):

| call-site (new code) | helper | expected-rc | rc-source |
|----------------------|--------|-------------|-----------|
| adapters/claude-code/adapter.sh `cc_generate_rules` | `rdf_get_active_profiles` | 0 always (echoes `core` + active list) | lib/rdf_common.sh:159 — echo + read loop, no non-zero return path |
| adapters/claude-code/adapter.sh `cc_generate_rules` | `rdf_require_bin jq` | 0, or exits 1 via `rdf_die` | lib/rdf_common.sh:98-103 |
| adapters/claude-code/adapter.sh `cc_generate_rules` | `rdf_log` | 0 (echo to stderr) | lib/rdf_common.sh:94-96 |
| adapters/claude-code/adapter.sh `cc_generate_rules` | `rdf_require_file` | 0, or exits 1 via `rdf_die` | lib/rdf_common.sh:105-111 |
| canonical/scripts/session-end-capture.sh | `command git rev-parse --git-dir` | 0 in a git repo, non-0 otherwise (→ clean no-op) | git; no rdf-state.sh dependency (F11 — inline git-only snapshot) |
| canonical/scripts/session-start-inject.sh | (none — READ-ONLY, F7) | reads cached index only; no helper calls that write | index build is `/r-save`'s job, not the hook's |
| state/rdf-lessons.sh `cmd_index` | `flock` (when available) | 0 on lock; degrade to direct write if `flock` absent | single-writer guard (F7); `command -v flock` probed |
| state/rdf-overhead.sh | `rdf_get_active_profiles` | 0 always | lib/rdf_common.sh:159 |
| canonical/commands/r-save.md → | `state/rdf-lessons.sh index` | 0 on write; non-0 → report warning | new (Phase 2); `/r-save` is the sole caller (F7) |
| lib/cmd/generate.sh `--lite` path | `_generate_adapter` | 0 on success, non-0 propagated | lib/cmd/generate.sh:56 |

No ambiguous helper names (each grep above returns a single definition).

## File Map

### New Files
| File | Lines | Purpose | Test File |
|------|------:|---------|-----------|
| `canonical/scripts/session-end-capture.sh` | ~70 | SessionEnd deterministic snapshot | `tests/memory-context.bats` |
| `canonical/scripts/session-start-inject.sh` | ~55 | SessionStart lessons-index injection | `tests/memory-context.bats` |
| `state/rdf-lessons.sh` | ~180 | `index` + `scan` subcommands | `tests/memory-context.bats` |
| `state/rdf-overhead.sh` | ~130 | isolate RDF per-session token overhead | `tests/memory-context.bats` |
| `profiles/lite/governance-lite.md` | ~90 | condensed core governance (~700 tokens) | `tests/memory-context.bats` |
| `docs/memory-context.md` | ~120 | native-memory coexistence doc | N/A (docs) |
| `tests/memory-context.bats` | ~230 | all-goal coverage | self |
| `tests/fixtures/lessons/lessons-sample.md` | ~20 | dedup/contradiction fixture | consumed by bats |

### Modified Files
| File | Changes | Test File |
|------|---------|-----------|
| `state/rdf-state.sh` | add deterministic `diff_categories` field (F6) | `tests/memory-context.bats` |
| `tests/governance-contracts.bats` | +never-scope-core, +no-auto-resolve-contradiction (F9) | self |
| `adapters/claude-code/hooks/hooks.json` | +matcher-less SessionStart, +SessionEnd (on top of 3.3.x; 5 s timeouts) | `tests/memory-context.bats` |
| `adapters/claude-code/adapter.sh` | `cc_generate_rules()`; `--lite` in `cc_generate_all` | `tests/memory-context.bats` |
| `lib/cmd/generate.sh` | `--lite` flag parse + pass-through | `tests/memory-context.bats` |
| `lib/cmd/deploy.sh` | opt-in `rules/` symlink; `--lite` skips hooks | `tests/memory-context.bats` |
| `canonical/commands/r-save.md` | consume snapshot; background phases; auto-act thresholds | `tests/memory-context.bats` |
| `canonical/commands/r-start.md` | auto-act thresholds; lessons-index note | `tests/memory-context.bats` |
| `canonical/commands/r-util-mem-compact.md` | lessons/insights consolidation pass + gate | `tests/memory-context.bats` |
| `canonical/commands/r-context-audit.md` | surface `rdf_overhead` field | `tests/memory-context.bats` |
| `README.md` | published cost + rdf-lite install | N/A (docs) |
| `ROADMAP.md` | check off delivered items | N/A (docs) |
| `CHANGELOG` / `CHANGELOG.RELEASE` / `VERSION` | 3.4.0 | N/A |

### Deleted Files
| File | Reason |
|------|--------|
| — | none |

## Phase Dependencies

- Phase 0 (re-triage): none
- Phase 1 (SessionEnd capture): [0]
- Phase 2 (lessons index + SessionStart inject): [0] — serializes after 1 on `hooks.json`
- Phase 3 (r-save/r-start): [1, 2]
- Phase 4 (consolidation): [2]
- Phase 5 (T3 scoped rules): [0] — **parallelizable** with 1-4 (disjoint files: adapter.sh + deploy.sh + registry read; shares only `tests/memory-context.bats`)
- Phase 6 (published cost): [5] — overhead measures rule weight
- Phase 7 (rdf-lite): [5, 6] — reuses scoped rules + measured budget
- Phase 8 (docs + release): [1,2,3,4,5,6,7]

Parallel batches (for `/r-build`): after Phase 0 → **{1→2 (hooks.json serial), 5 in parallel}**; then **{3, 4}**; then **6**; then **7**; then **8**.
Shared file `tests/memory-context.bats` is created in Phase 1 and appended by
every later phase — `/r-build`'s file-ownership check serializes appends.

---

### Phase 0: Re-triage — SessionEnd matcher confirmation (Q1 resolved)

**Q1 RESOLVED by coordinator (F4) — no probe needed.** 3.3.x lands TODAY: a
PreCompact **command** hook (`precompact-snapshot.sh` →
`~/.rdf/state/handoff/<session_id>.md`, timeout 10) ALONGSIDE the existing
PreCompact prompt hook, plus a SessionStart `matcher:"compact"` entry
(`session-start-context.sh`, timeout 10). 3.4 edits `hooks.json` on top of
that version and adds its lessons-inject as a DISTINCT, matcher-less
SessionStart array entry — never appended into the 3.3.x compact entry. This
is fixed; Phases 1-2 implement it directly. Only Q2 remains.

**Files:** none (single doc-confirmation)

- **Mode**: serial-context
- **Accept**: Q2 answered and recorded below with a go/no-go note for Phase 1
- **Test**: N/A (investigation)
- **Edge cases**: spec §12 Q2 (SessionEnd `clear` trigger, stdin `session_id`)
- **Regression-case**: N/A — investigation, no runtime surface

- [ ] **Step 1: Q2 — SessionEnd matcher + stdin schema**

  Re-read the code.claude.com hooks reference (SessionEnd section). Confirm
  and record in this plan: (a) SessionEnd fires on `clear` (not only
  `logout`) — determines how often the safety-net capture fires; (b) whether
  stdin includes `session_id` on all four triggers. The Phase-1 hook already
  falls back to `$(date +%s)-$$` when `session_id` is absent, so (b) is
  non-blocking — record it for completeness only.

- [ ] **Step 2: Confirm 3.3.x hooks.json shape is present** — before Phase 1
  edits, verify the current `hooks.json` actually contains the 3.3.x
  PreCompact command entry and SessionStart compact entry (so Phase 1/2 edit
  the right base):

  ```bash
  jq '.hooks.PreCompact | length' adapters/claude-code/hooks/hooks.json   # expect: 2 (prompt + command)
  jq '.hooks.SessionStart' adapters/claude-code/hooks/hooks.json           # expect: the compact-matcher entry
  ```
  If the 3.3.x change has NOT landed yet, HOLD Phase 1/2 until it does (do
  not clobber; the two changes must compose).

- [ ] **Step 3: Record findings** — append a "Phase 0 Findings" note with the
  Q2 answer and confirmation of the 3.3.x base. No commit (investigation).

---

### Phase 1: SessionEnd capture hook

Zero-effort safety net: a SessionEnd hook takes an inline git-only snapshot
(F11) and APPENDS a deterministic entry to `.rdf/work-output/session-log.jsonl`
(the journal `/r-start` reads via `rdf-state.sh:252` `tail -1`) AND writes a
`session-end-<id>.json` cache for `/r-save` — so the journal survives even
when `/r-save` is never run (F5: something actually reads the entry).

**Files:**
- Create: `canonical/scripts/session-end-capture.sh`
- Create: `tests/memory-context.bats` (header + harness + 2 tests)
- Modify: `adapters/claude-code/hooks/hooks.json` (matcher-less SessionEnd entry, on top of 3.3.x)
- Modify: `tests/Makefile` (add `memory-context.bats` to explicit test + lint lists — the Makefile does not glob; verify during execution)

- **Mode**: serial-agent
- **Accept**: in a git repo, piping `{"session_id":"t","trigger":"clear","cwd":"$PWD"}`
  to the hook exits 0, APPENDS one `insight:null` line to
  `.rdf/work-output/session-log.jsonl`, and writes
  `.rdf/work-output/session-end-t.json`; run in a non-git dir it exits 0 and
  writes NO journal line (masked degrade path)
- **Test**: `tests/memory-context.bats` — @test "session-end-capture appends journal entry + writes cache, exits 0", @test "session-end-capture is a no-op outside a git repo"
- **Edge cases**: spec §11b "SessionEnd logout, no git repo" (git-check guard, no rdf-state dependency); "No ~/.rdf dir" (mkdir -p guard)
- **Regression-case**: tests/memory-context.bats::@test "session-end-capture appends journal entry + writes cache, exits 0" (file created in this phase)

- [ ] **Step 1: Create `canonical/scripts/session-end-capture.sh`**

  ```bash
  #!/bin/bash
  # canonical/scripts/session-end-capture.sh — SessionEnd hook
  # (C) 2026 R-fx Networks <proj@rfxn.com>
  # GNU GPL v2
  # Inline git-only snapshot appended to the session journal (+ a cache for
  # /r-save) so sessions that never run /r-save are still recorded. No
  # rdf-state.sh call — stays well inside the 5s budget. No model work.
  set -uo pipefail   # NOT -e: a probe failure must never abort the hook

  input="$(cat)"

  # Parse stdin with jq when present; degrade to safe defaults without it.
  session_id=""; trigger="other"; cwd=""
  if command -v jq >/dev/null 2>&1; then
      session_id="$(printf '%s' "$input" | jq -r '.session_id // empty' 2>/dev/null)"   # malformed json → empty
      trigger="$(printf '%s' "$input" | jq -r '.trigger // "other"' 2>/dev/null)"
      cwd="$(printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null)"
  fi
  [ -n "$cwd" ] && { cd "$cwd" 2>/dev/null || exit 0; }   # bad cwd: bail cleanly (guarded cd)
  [ -n "$session_id" ] || session_id="$(date +%s)-$$"      # id fallback (Phase 0 Q2)

  # Not a git repo → nothing to snapshot (clean no-op — the masked degrade path).
  command git rev-parse --git-dir >/dev/null 2>&1 || exit 0

  branch="$(command git branch --show-current 2>/dev/null)"
  head="$(command git rev-parse --short HEAD 2>/dev/null)"
  dirty="$(command git status --porcelain 2>/dev/null | grep -c . || true)"   # grep -c exits 1 at 0; captured value is "0"
  ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

  out_dir=".rdf/work-output"
  command mkdir -p "$out_dir" 2>/dev/null || exit 0   # unwritable tree: give up quietly

  # Minimal JSON escape for the branch (backslash + quote only realistically).
  b_esc="${branch//\\/\\\\}"; b_esc="${b_esc//\"/\\\"}"
  line="{\"timestamp\":\"${ts}\",\"head_after\":\"${head}\",\"branch\":\"${b_esc}\",\"dirty_files\":${dirty:-0},\"trigger\":\"${trigger}\",\"source\":\"session-end-hook\",\"insight\":null}"

  # Single O_APPEND write (concurrency-safe for a short line) to the journal
  # /r-start reads, plus a cache /r-save consumes.
  printf '%s\n' "$line" >> "${out_dir}/session-log.jsonl"
  printf '%s\n' "$line" >  "${out_dir}/session-end-${session_id}.json"
  exit 0
  ```

  > Self-correction note: `set -uo pipefail` WITHOUT `-e` is deliberate — a
  > failed probe must fall through to `exit 0`. There is NO `rdf-state.sh`
  > dependency (F11) — the snapshot is inline git, so capture always finishes
  > inside 5 s. The journal APPEND (not just the cache) is what makes Goal 1
  > real: `/r-start` reads `session-log.jsonl` via `rdf-state.sh:252`
  > `tail -1` (F5).

- [ ] **Step 2: Add SessionEnd to `adapters/claude-code/hooks/hooks.json`**
  (on top of the 3.3.x version — F4)

  The base is the 3.3.x `hooks.json` (PreCompact = prompt + command;
  SessionStart = the `matcher:"compact"` entry — confirmed in Phase 0
  Step 2). Add a NEW `SessionEnd` key to the `.hooks` object; do NOT modify
  PreCompact or the existing SessionStart entry. Add a comma after whichever
  array now precedes it:

  ```json
      "SessionEnd": [
        {
          "hooks": [
            { "type": "command", "command": "~/.claude/scripts/session-end-capture.sh", "timeout": 5 }
          ]
        }
      ]
  ```

  Verify composition preserved: `jq '.hooks.PreCompact | length'` still
  returns 2 and `jq '.hooks.SessionStart[0].matcher'` still returns `compact`.

- [ ] **Step 3: Create `tests/memory-context.bats`** (header + harness + 2 tests)

  ```bash
  #!/usr/bin/env bats
  # tests/memory-context.bats — RDF 3.4 memory & context
  # (C) 2026 R-fx Networks <proj@rfxn.com>
  # GNU GPL v2
  # shellcheck disable=SC2154,SC2164,SC1090,SC1091

  RDF_SRC="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  export RDF_SRC

  setup() {
      TEST_HOME="$(mktemp -d)"
      TEST_PROJ="$(mktemp -d)"
      mkdir -p "${TEST_PROJ}/.rdf/work-output"
      export _TEST_HOME="$TEST_HOME" _TEST_PROJ="$TEST_PROJ"
  }
  teardown() {
      rm -rf "${_TEST_HOME}" "${_TEST_PROJ}" 2>/dev/null || true # cleanup, ignore errors
  }

  @test "session-end-capture appends journal entry + writes cache, exits 0" {
      cd "$TEST_PROJ"
      git init -q . && git -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
      run bash -c 'printf "%s" "$1" | HOME="$2" bash "$3/canonical/scripts/session-end-capture.sh"' \
          -- '{"session_id":"t","trigger":"clear","cwd":"'"$TEST_PROJ"'"}' "$TEST_HOME" "$RDF_SRC"
      [ "$status" -eq 0 ]
      # journal APPEND is the load-bearing behavior (Goal 1 / F5)
      [ -f "${TEST_PROJ}/.rdf/work-output/session-log.jsonl" ]
      run jq -r '.trigger, .insight' <(tail -1 "${TEST_PROJ}/.rdf/work-output/session-log.jsonl")
      [[ "$output" == *"clear"* ]]
      [[ "$output" == *"null"* ]]
      # cache for /r-save enrichment
      [ -f "${TEST_PROJ}/.rdf/work-output/session-end-t.json" ]
  }

  @test "session-end-capture is a no-op outside a git repo" {
      # NON-git tmp dir — masks the git repo so the degrade path is real
      NONGIT="$(mktemp -d)"
      run bash -c 'printf "%s" "$1" | HOME="$2" bash "$3/canonical/scripts/session-end-capture.sh"' \
          -- '{"session_id":"t2","trigger":"logout","cwd":"'"$NONGIT"'"}' "$TEST_HOME" "$RDF_SRC"
      [ "$status" -eq 0 ]
      [ ! -f "${NONGIT}/.rdf/work-output/session-log.jsonl" ]   # no journal write outside a repo
      rm -rf "$NONGIT"
  }
  ```

  > Note: the second test masks a real non-git directory (F13/F14) so the
  > `command git rev-parse --git-dir` guard is actually exercised — asserting
  > both exit 0 AND no journal write.

- [ ] **Step 4: Lint + test**

  ```bash
  bash -n canonical/scripts/session-end-capture.sh
  shellcheck canonical/scripts/session-end-capture.sh
  python3 -c "import json;json.load(open('adapters/claude-code/hooks/hooks.json'));print('json ok')"
  make -C tests test 2>&1 | tee /tmp/test-rdf-P1-debian12.log | grep -c '^not ok'
  # expect: 0
  ```

- [ ] **Step 5: Commit**

  ```bash
  git add canonical/scripts/session-end-capture.sh adapters/claude-code/hooks/hooks.json \
      tests/memory-context.bats tests/Makefile
  git commit -m "Add SessionEnd capture hook — zero-effort session journal

  [New] session-end-capture.sh — inline git-only snapshot APPENDED to
        .rdf/work-output/session-log.jsonl (the journal /r-start reads) plus a
        session-end-<id>.json cache for /r-save; no model work, always exits 0,
        clean no-op outside a git repo, jq-optional
  [New] hooks.json matcher-less SessionEnd entry (5s timeout), on top of 3.3.x
  [New] tests/memory-context.bats harness + capture tests"
  ```

---

### Phase 2: Lessons ID-index + SessionStart injection

Cheap ~100-token lessons overview injected at session start; full bodies
fetched on demand by ID. Adds a DISTINCT matcher-less SessionStart entry on
top of the 3.3.x `matcher:"compact"` entry (F4). The hook is READ-ONLY (F7).

**Files:**
- Create: `state/rdf-lessons.sh` (`index` subcommand; `scan` stub added in Phase 4)
- Create: `canonical/scripts/session-start-inject.sh`
- Create: `tests/fixtures/lessons/lessons-sample.md`
- Modify: `adapters/claude-code/hooks/hooks.json` (matcher-less SessionStart entry)
- Modify: `tests/memory-context.bats` (+3 tests)

- **Mode**: serial-agent
- **Accept**: `rdf-lessons.sh index` on the fixture writes `lessons-index.md`
  ≤ 400 bytes with stable `[ID]` markers across two runs; the inject hook
  emits `additionalContext` JSON for `{"source":"startup"}`, emits NOTHING
  for `{"source":"resume"}`, and writes NO file (read-only)
- **Test**: `tests/memory-context.bats` — @test "rdf-lessons index emits <=400 byte ID-index", @test "rdf-lessons index assigns stable IDs across two runs", @test "session-start-inject injects on startup, skips resume, is read-only"
- **Edge cases**: spec §11b "zero lessons" (empty index, inject nothing), "resume" (skip), "compact" (re-inject intended — F12); "subagent" accepted-but-capped (no guard — F1)
- **Regression-case**: tests/memory-context.bats::@test "session-start-inject injects on startup, skips resume, is read-only" (file created in Phase 1 of this plan)

- [ ] **Step 1: Create `state/rdf-lessons.sh`** (index subcommand)

  ```bash
  #!/usr/bin/env bash
  # state/rdf-lessons.sh — lessons-learned index + consolidation scan
  # (C) 2026 R-fx Networks <proj@rfxn.com>
  # GNU GPL v2
  # Usage: rdf-lessons.sh index [lessons-file]   -> writes <dir>/lessons-index.md
  #        rdf-lessons.sh scan  [lessons-file]   -> JSON candidates to stdout (Phase 4)
  set -euo pipefail

  _LESSONS="${2:-${HOME}/.rdf/lessons-learned.md}"
  _INDEX="$(command dirname "$_LESSONS")/lessons-index.md"
  _MAX_LINES=12          # cap injected entries
  _MAX_BYTES=400         # hard size cap for the index body

  # Category initial for the ID: derived from the nearest "## <Category>" heading.
  _cat_initial() {
      local heading="$1"
      printf '%s' "${heading:0:1}" | tr '[:lower:]' '[:upper:]'
  }

  # Assign stable <!-- id:X --> markers to un-tagged bullets in-place, then
  # emit a compact index (most-recent _MAX_LINES, size-capped).
  cmd_index() {
      [ -f "$_LESSONS" ] || { : > "$_INDEX"; return 0; }   # no lessons: empty index

      # Single-writer lock (F7): /r-save and /r-util-mem-compact both write via
      # this function — serialize with flock when available; degrade to a
      # direct write if flock is missing (CentOS 6 has it; be defensive).
      if command -v flock >/dev/null 2>&1; then
          exec 9>"${_LESSONS}.lock" 2>/dev/null && flock 9 2>/dev/null || true  # best-effort; never block the write
      fi

      # Pass 1: ensure every bullet has an id marker (idempotent).
      local cat="X" ord=0 line
      local tmp; tmp="$(command mktemp)"
      while IFS= read -r line; do
          if [[ "$line" =~ ^##[[:space:]] ]]; then
              cat="$(_cat_initial "${line#\#\# }")"; ord=0
              printf '%s\n' "$line" >> "$tmp"; continue
          fi
          if [[ "$line" =~ ^-[[:space:]] ]]; then
              ord=$((ord + 1))
              if [[ "$line" == *"<!-- id:"* ]]; then
                  printf '%s\n' "$line" >> "$tmp"
              else
                  printf '%s <!-- id:%s%d -->\n' "$line" "$cat" "$ord" >> "$tmp"
              fi
              continue
          fi
          printf '%s\n' "$line" >> "$tmp"
      done < "$_LESSONS"
      command mv "$tmp" "$_LESSONS"

      # Pass 2: emit the index (id + first clause). No tab delimiter — extract
      # id and body with two separate seds per line (F3: BSD sed emits literal
      # 't' for `\t` in the replacement; POSIX-portable is per-field extraction).
      {
          printf '%s\n' "RDF lessons available (fetch full text by ID from ~/.rdf/lessons-learned.md):"
          grep -E '^-[[:space:]].*<!-- id:' "$_LESSONS" 2>/dev/null \
            | head -n "$_MAX_LINES" \
            | while IFS= read -r bline; do
                  id="$(printf '%s' "$bline" | sed -nE 's/.*<!-- id:([A-Z0-9]+) -->.*/\1/p')"
                  body="$(printf '%s' "$bline" | sed -E 's/^-[[:space:]]+//; s/ *<!-- id:[A-Z0-9]+ -->.*//')"
                  clause="${body%%.*}"; clause="${clause%%;*}"
                  printf '[%s] %s\n' "$id" "${clause:0:70}"
              done
      } | head -c "$_MAX_BYTES" > "$_INDEX"
      return 0
  }

  cmd_scan() {   # Phase 4 fills this in
      printf '{"duplicates":[],"contradictions":[]}\n'
      return 0
  }

  case "${1:-}" in
      index) cmd_index ;;
      scan)  cmd_scan ;;
      *) echo "usage: rdf-lessons.sh {index|scan} [lessons-file]" >&2; exit 2 ;;
  esac
  ```

  > Self-correction note (F3): the index emission uses per-field `sed -nE`
  > extraction, NOT a `\t`-delimited replacement — BSD sed (macOS CI) emits a
  > literal `t` for `\t` in the replacement, which would corrupt the parse.
  > `sed -E` is portable across GNU/BSD. IDs are `<Cat><ordinal>`, written
  > back once, so a second `index` run skips re-tagging (idempotent).

- [ ] **Step 2: Create fixture `tests/fixtures/lessons/lessons-sample.md`**

  Bullets calibrated so the Phase-4 scanner numbers are the ones actually
  computed (F2): the two Workflow bullets are a 50% Jaccard duplicate; the
  two `commit`-gating Testing bullets are a 36%-overlap opposing-polarity
  contradiction; every other cross-pair is 0% overlap. Do NOT reword without
  re-running the tokenizer.

  ```markdown
  # Lessons Learned

  ## Workflow
  - designate one owner per shared file before launching parallel agents
  - fanning out parallel agents: pick one owner per shared file at dispatch

  ## Testing
  - update tests in the same phase as a source refactor or false-green
  - always run the full test matrix before every commit
  - never run the full matrix before commit; Debian12 and Rocky9 is the minimum
  ```

- [ ] **Step 3: Create `canonical/scripts/session-start-inject.sh`**

  ```bash
  #!/bin/bash
  # canonical/scripts/session-start-inject.sh — SessionStart hook
  # (C) 2026 R-fx Networks <proj@rfxn.com>
  # GNU GPL v2
  # Inject the lessons ID-index as additionalContext. READ-ONLY: never writes
  # lessons-learned.md or lessons-index.md (single-writer is /r-save).
  set -uo pipefail   # NOT -e: never block startup

  input="$(cat)"
  command -v jq >/dev/null 2>&1 || exit 0   # no jq: emit nothing, exit clean

  # source enum is startup|resume|clear|compact (there is NO subagent value —
  # F1). Skip only resume (context already present); inject on startup/clear/
  # compact — compact re-inject is intended, it restores lessons lost to
  # compaction (F12).
  source="$(printf '%s' "$input" | jq -r '.source // ""' 2>/dev/null)"
  [ "$source" = "resume" ] && exit 0

  index="${HOME}/.rdf/lessons-index.md"
  [ -s "$index" ] || exit 0   # no index: nothing to inject (do NOT regenerate — F7)

  body="$(head -c 400 "$index")"   # 400 B hard cap bounds the per-spawn cost (subagents included)
  jq -cn --arg c "$body" '{hookSpecificOutput:{additionalContext:$c}}' 2>/dev/null || exit 0
  exit 0
  ```

  > Self-correction note (F1/F7): no subagent guard exists because the
  > SessionStart `source` enum has no `subagent` value — the 400 B cap is the
  > cost bound instead. The hook is strictly READ-ONLY: it never calls
  > `rdf-lessons.sh index`; a stale/absent index is simply not injected until
  > `/r-save` rebuilds it (single-writer).

- [ ] **Step 4: Add a DISTINCT SessionStart entry to `hooks.json`** (F4)

  The 3.3.x `SessionStart` array already has a `matcher:"compact"` entry
  (`session-start-context.sh`). Append a SEPARATE, matcher-less object to the
  SAME array — do NOT merge into or modify the compact entry:

  ```json
      "SessionStart": [
        { "matcher": "compact", "hooks": [ { "type": "command", "command": "~/.claude/scripts/session-start-context.sh", "timeout": 10 } ] },
        { "hooks": [ { "type": "command", "command": "~/.claude/scripts/session-start-inject.sh", "timeout": 5 } ] }
      ],
  ```

  (Only the second object is added by 3.4; the first is the 3.3.x entry shown
  for context.) Verify: `jq '.hooks.SessionStart | length'` returns 2 and
  `jq -r '.hooks.SessionStart[0].matcher'` still returns `compact`.

- [ ] **Step 5: Add 3 tests to `tests/memory-context.bats`**

  ```bash
  @test "rdf-lessons index emits <=400 byte ID-index" {
      cp -r "${RDF_SRC}/tests/fixtures/lessons/lessons-sample.md" "${TEST_HOME}/.rdf-lessons.md" 2>/dev/null || \
        { mkdir -p "${TEST_HOME}"; cp "${RDF_SRC}/tests/fixtures/lessons/lessons-sample.md" "${TEST_HOME}/lessons-learned.md"; }
      run bash "${RDF_SRC}/state/rdf-lessons.sh" index "${TEST_HOME}/lessons-learned.md"
      [ "$status" -eq 0 ]
      [ -f "${TEST_HOME}/lessons-index.md" ]
      [ "$(wc -c < "${TEST_HOME}/lessons-index.md")" -le 400 ]
      grep -q '^\[W1\]' "${TEST_HOME}/lessons-index.md"
  }

  @test "rdf-lessons index assigns stable IDs across two runs" {
      cp "${RDF_SRC}/tests/fixtures/lessons/lessons-sample.md" "${TEST_HOME}/lessons-learned.md"
      bash "${RDF_SRC}/state/rdf-lessons.sh" index "${TEST_HOME}/lessons-learned.md"
      first="$(grep -c '<!-- id:' "${TEST_HOME}/lessons-learned.md")"
      bash "${RDF_SRC}/state/rdf-lessons.sh" index "${TEST_HOME}/lessons-learned.md"
      second="$(grep -c '<!-- id:' "${TEST_HOME}/lessons-learned.md")"
      [ "$first" -eq "$second" ]   # no duplicate markers on re-run
  }

  @test "session-start-inject injects on startup, skips resume, is read-only" {
      cp "${RDF_SRC}/tests/fixtures/lessons/lessons-sample.md" "${TEST_HOME}/lessons-learned.md"
      bash "${RDF_SRC}/state/rdf-lessons.sh" index "${TEST_HOME}/lessons-learned.md"
      idx_before="$(md5sum "${TEST_HOME}/lessons-index.md")"
      # startup → inject
      run bash -c 'printf "%s" "$1" | HOME="$2" bash "$3/canonical/scripts/session-start-inject.sh"' \
          -- '{"source":"startup"}' "$TEST_HOME" "$RDF_SRC"
      [ "$status" -eq 0 ]
      echo "$output" | jq -e '.hookSpecificOutput.additionalContext' >/dev/null
      # resume → no injection
      run bash -c 'printf "%s" "$1" | HOME="$2" bash "$3/canonical/scripts/session-start-inject.sh"' \
          -- '{"source":"resume"}' "$TEST_HOME" "$RDF_SRC"
      [ "$status" -eq 0 ]
      [ -z "$output" ]
      # READ-ONLY: index unchanged (F7)
      idx_after="$(md5sum "${TEST_HOME}/lessons-index.md")"
      [ "$idx_before" = "$idx_after" ]
  }
  ```

- [ ] **Step 6: Lint + test**

  ```bash
  bash -n state/rdf-lessons.sh canonical/scripts/session-start-inject.sh
  shellcheck state/rdf-lessons.sh canonical/scripts/session-start-inject.sh
  python3 -c "import json;json.load(open('adapters/claude-code/hooks/hooks.json'));print('json ok')"
  make -C tests test 2>&1 | tee /tmp/test-rdf-P2-debian12.log | grep -c '^not ok'
  # expect: 0
  ```

- [ ] **Step 7: Commit**

  ```bash
  git add state/rdf-lessons.sh canonical/scripts/session-start-inject.sh \
      adapters/claude-code/hooks/hooks.json tests/memory-context.bats \
      tests/fixtures/lessons/lessons-sample.md
  git commit -m "Add lessons ID-index and SessionStart injection

  [New] state/rdf-lessons.sh index — stable [ID] markers + <=400 byte index
        (POSIX-portable per-field extraction, no \\t sed)
  [New] session-start-inject.sh — inject lessons index as additionalContext;
        READ-ONLY (never regenerates), skips resume, re-injects on compact,
        400B cap bounds subagent cost, degrades without jq
  [New] hooks.json matcher-less SessionStart entry (5s), distinct from 3.3.x compact entry"
  ```

---

### Phase 3: /r-save less-work-at-save-time + auto-acting thresholds

Move deterministic diff classification into `rdf-state.sh` (F6), consume the
SessionEnd cache with an explicit selection rule (F5), and turn MEMORY/context
thresholds from warnings into actions in `/r-save` and `/r-start`.

**Files:**
- Modify: `state/rdf-state.sh` (new deterministic `diff_categories` field)
- Modify: `canonical/commands/r-save.md`
- Modify: `canonical/commands/r-start.md`
- Modify: `tests/memory-context.bats` (+3 tests)

- **Mode**: serial-agent
- **Accept**: `bash state/rdf-state.sh --full . | jq -e .diff_categories`
  succeeds (real measurement — the model no longer classifies); `r-save.md`
  §1 documents the `$RDF_SESSION_ID`-first cache-selection rule; §3/§8
  auto-run `/r-util-mem-compact` preview at ≥180 lines; `r-start.md`
  §Warnings auto-runs the preview
- **Test**: `tests/memory-context.bats` — @test "rdf-state --full emits diff_categories object", @test "r-save selects session-end cache and skips state re-run", @test "r-save and r-start auto-run mem-compact preview at MEMORY threshold"
- **Edge cases**: spec §11b "/r-save runs, no prior cache" (fallback), "MEMORY.md exactly 180 lines" (>= fires)
- **Regression-case**: tests/memory-context.bats::@test "rdf-state --full emits diff_categories object" (file created in Phase 1 of this plan)

- [ ] **Step 1: rdf-state.sh — add deterministic `diff_categories` (F6)** —
  in `--full` mode, after the `_recent_commits` block (rdf-state.sh:145),
  classify porcelain-status files by path prefix and build a JSON object.
  Insert inside the `if [[ "$_full_mode" -eq 1 ]]; then` git block:

  ```bash
      # Deterministic diff classification (was model work in /r-save §1)
      _dc_cmd=0; _dc_agt=0; _dc_scr=0; _dc_cli=0; _dc_adp=0; _dc_spec=0; _dc_doc=0; _dc_oth=0
      while IFS= read -r _dcf; do
          [[ -z "$_dcf" ]] && continue
          _dcf="${_dcf:3}"   # strip porcelain status prefix
          case "$_dcf" in
              canonical/commands/*) _dc_cmd=$((_dc_cmd+1)) ;;
              canonical/agents/*)   _dc_agt=$((_dc_agt+1)) ;;
              canonical/scripts/*)  _dc_scr=$((_dc_scr+1)) ;;
              lib/cmd/*|bin/*)      _dc_cli=$((_dc_cli+1)) ;;
              adapters/*)           _dc_adp=$((_dc_adp+1)) ;;
              docs/specs/*)         _dc_spec=$((_dc_spec+1)) ;;
              *.md)                 _dc_doc=$((_dc_doc+1)) ;;
              *)                    _dc_oth=$((_dc_oth+1)) ;;
          esac
      done < <($TIMEOUT_PREFIX git -C "$_project_path" status --porcelain 2>/dev/null)
      _diff_categories="{\"commands\":${_dc_cmd},\"agents\":${_dc_agt},\"scripts\":${_dc_scr},\"cli\":${_dc_cli},\"adapters\":${_dc_adp},\"specs\":${_dc_spec},\"docs\":${_dc_doc},\"other\":${_dc_oth}}"
  ```

  Initialize `_diff_categories="{}"` near the other full-mode defaults
  (rdf-state.sh ~L205), and add `"diff_categories": ${_diff_categories},` to
  the output JSON heredoc (rdf-state.sh:337 area, after `"in_flight"`).

- [ ] **Step 2: r-save.md §1 — consume the cache with explicit selection (F5)**
  — in `### 1. Compute Session Diff` (r-save.md:36-54), replace the opening
  "Run ONE command" block. Old (r-save.md:38-42):

  ```
  Run ONE command to gather current project state:
  ```bash
  bash state/rdf-state.sh --full .
  ```
  ```

  New:

  ````
  A SessionEnd hook may have precomputed this session's deterministic state.
  **Cache selection rule:** if `$RDF_SESSION_ID` is set, look for
  `.rdf/work-output/session-end-${RDF_SESSION_ID}.json`; otherwise glob
  `.rdf/work-output/session-end-*.json` and take the newest one NOT ending in
  `.consumed`. On a hit, parse it, SKIP the `rdf-state.sh --full` re-run, and
  rename the file to `*.consumed`. If no cache is found, run:
  ```bash
  bash state/rdf-state.sh --full .
  ```
  Read `.diff_categories` from the state JSON and format the top-3 summary from
  it — do NOT re-classify files by hand; that classification is now
  deterministic in `rdf-state.sh`. (The SessionEnd cache carries only the git
  snapshot, not `diff_categories` — a cache hit still requires this one
  `rdf-state.sh` call to obtain them.)
  ````

- [ ] **Step 3: r-save.md §3 — auto-act on MEMORY size** — in `### 3. Sync
  MEMORY.md`, replace the `**Size guard**` block (r-save.md:149-150). Old:

  ```
  **Size guard**: After updating, count total lines. If >=180, record
  a warning for the report.
  ```

  New:

  ```
  **Size guard (auto-act)**: After updating, count total lines. If >=180,
  invoke `/r-util-mem-compact` in preview mode and carry its proposed
  reduction into the report (§8) as an action line — not a passive warning.
  ```

- [ ] **Step 4: r-save.md §8 — thresholds become directives** — in the
  Warnings block (r-save.md:344-358), replace the MEMORY and Context lines.
  Old:

  ```
  > ⚠ MEMORY.md at {N}/200 lines — `/r-util-mem-compact`
  > ⚠ Context at ~{N}% — consider fresh session or `/half-clone`
  ```

  New:

  ```
  > ▶ MEMORY.md {N}/200 — previewed compaction saves {M} lines; apply? y/n
  > ▶ Context ~{N}% — start a fresh session or `/half-clone` now
  ```

  And add to the threshold list (r-save.md:352-357): "Memory: >=180 lines →
  auto-run preview; Context: >60% → directive (not passive warning)."

- [ ] **Step 5: r-save.md §7 — refresh index after lessons write (single
  writer, F7)** — in `### 7. Lessons Learned Prompt`, in the "Appending to
  lessons-learned.md" block, add after the append step: "After appending (y
  or auto), run `state/rdf-lessons.sh index` to rebuild
  `~/.rdf/lessons-index.md` AND backfill any missing `<!-- id -->` markers.
  This is the ONLY place these files are written programmatically — the
  SessionStart hook is read-only."

- [ ] **Step 6: r-start.md §Warnings — auto-act** — in `**Warnings**`
  (r-start.md:192-204), replace the threshold line (r-start.md:195) so
  MEMORY ≥180 runs `/r-util-mem-compact` preview inline and Context >60%
  renders a directive. Add a one-line note in the `**Insights**` area: "N
  lessons indexed (fetch by ID) — injected at session start." Old
  (r-start.md:195):

  ```
  > ⚠ Governance {T}h old — `/r-refresh` | MEMORY.md {N}/200 — `/r-util-mem-compact`
  ```

  New:

  ```
  > ▶ Governance {T}h old — `/r-refresh` | MEMORY.md {N}/200 — previewed compaction saves {M} lines
  ```

- [ ] **Step 7: Add 3 tests**

  ```bash
  @test "rdf-state --full emits diff_categories object" {
      cd "$TEST_PROJ"
      git init -q . && git -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
      run bash -c 'bash "$1/state/rdf-state.sh" --full . | jq -e ".diff_categories | type == \"object\""' -- "$RDF_SRC"
      [ "$status" -eq 0 ]
  }

  @test "r-save selects session-end cache and skips state re-run" {
      grep -q 'RDF_SESSION_ID' "${RDF_SRC}/canonical/commands/r-save.md"
      grep -q 'Cache selection rule' "${RDF_SRC}/canonical/commands/r-save.md"
      grep -q 'diff_categories' "${RDF_SRC}/canonical/commands/r-save.md"
  }

  @test "r-save and r-start auto-run mem-compact preview at MEMORY threshold" {
      grep -q 'invoke .*/r-util-mem-compact.* in preview' "${RDF_SRC}/canonical/commands/r-save.md"
      grep -q 'previewed compaction saves' "${RDF_SRC}/canonical/commands/r-start.md"
  }
  ```

- [ ] **Step 8: Deploy check + test**

  ```bash
  bash -n state/rdf-state.sh && shellcheck state/rdf-state.sh
  bin/rdf generate claude-code >/dev/null 2>&1 && echo "generate ok"
  make -C tests test 2>&1 | tee /tmp/test-rdf-P3-debian12.log | grep -c '^not ok'
  # expect: 0
  git checkout -- adapters/ 2>/dev/null; git clean -fdq adapters/claude-code/output 2>/dev/null || true # discard local-only regen
  ```

- [ ] **Step 9: Commit**

  ```bash
  git add state/rdf-state.sh canonical/commands/r-save.md canonical/commands/r-start.md tests/memory-context.bats
  git commit -m "/r-save: less work at save time + auto-acting thresholds

  [New] rdf-state.sh diff_categories — deterministic path-prefix classification
        (the model no longer classifies changed files in /r-save §1)
  [Change] r-save: RDF_SESSION_ID-first cache selection skips the rdf-state
           re-run on a hit; MEMORY>=180 auto-runs mem-compact preview;
           context>60% becomes a directive; rebuild lessons index on write
  [Change] r-start: MEMORY>=180 shows previewed reduction; lessons-index note"
  ```

---

### Phase 4: Consolidation pass (dedup + contradiction prune)

Fold a gated lessons/insights consolidation into `/r-util-mem-compact`; no
new top-level command.

**Files:**
- Modify: `state/rdf-lessons.sh` (`cmd_scan` real implementation)
- Modify: `canonical/commands/r-util-mem-compact.md` (consolidation § + gate)
- Modify: `tests/memory-context.bats` (+2 tests)
- Modify: `tests/governance-contracts.bats` (+1 anti-crystallization contract — F9)

- **Mode**: serial-agent
- **Accept**: `rdf-lessons.sh scan` on the fixture returns JSON with exactly 1
  duplicate (the two worktree bullets, computed Jaccard **50%** ≥50) and
  exactly 1 contradiction (the two commit-gating bullets, computed **36%**
  overlap in [25,50) + opposing polarity); every 0%-overlap negative pair is
  absent from both arrays; mem-compact.md documents the y/n/auto gate with
  contradictions never auto-resolved
- **Test**: `tests/memory-context.bats` — @test "rdf-lessons scan flags exactly the 50% duplicate", @test "rdf-lessons scan flags exactly the 36% contradiction"; **governance-contracts.bats** — @test "consolidation never auto-resolves a contradiction"
- **Edge cases**: spec §11b "identical text" (Jaccard=100 → dup), "contradiction pair" (auto never resolves — F9), negatives at 0% not flagged
- **Regression-case**: governance-contracts.bats::@test "consolidation never auto-resolves a contradiction" (F9 — added in this phase)

- [ ] **Step 1: Implement `cmd_scan` in `state/rdf-lessons.sh`** — replace
  the Phase-2 stub. Deterministic token-Jaccard dedup + a conservative
  contradiction heuristic:

  ```bash
  # Normalize a bullet to a sorted unique lowercase token set (letters only).
  _tokens() {
      printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | tr -cs '[:alpha:]' '\n' \
        | grep -vE '^(the|a|an|to|of|for|and|or|in|on|per|before|at|is|be)$' \
        | sort -u
  }
  # Jaccard of two token sets given as newline lists → integer percent.
  # a and b are already sorted-unique (from _tokens) — comm needs sorted input.
  _jaccard_pct() {
      local a="$1" b="$2" inter uni
      inter="$(comm -12 <(printf '%s\n' "$a") <(printf '%s\n' "$b") | grep -c . || true)"
      uni="$(printf '%s\n%s\n' "$a" "$b" | sort -u | grep -c . || true)"
      [ "$uni" -gt 0 ] || { echo 0; return; }
      echo $(( inter * 100 / uni ))
  }

  # Polarity flags for a bullet (order-independent contradiction detection).
  _has_max() { printf '%s' "$1" | grep -qiE '(^|[^a-z])(always|every|full|all|must)([^a-z]|$)'; }
  _has_min() { printf '%s' "$1" | grep -qiE '(^|[^a-z])(never|no|not|minimum|only|none)([^a-z]|$)'; }

  # Thresholds computed against tests/fixtures/lessons/lessons-sample.md:
  #   dup pair = 50% ; contradiction pair = 36% ; all negatives = 0%.
  _DUP_MIN=50; _CONTRA_MIN=25   # contra range is [_CONTRA_MIN, _DUP_MIN)

  cmd_scan() {
      [ -f "$_LESSONS" ] || { printf '{"duplicates":[],"contradictions":[]}\n'; return 0; }
      local -a bodies=() ids=()
      local line body id
      while IFS= read -r line; do
          [[ "$line" =~ ^-[[:space:]] ]] || continue
          id="$(printf '%s' "$line" | sed -nE 's/.*<!-- id:([A-Z0-9]+) -->.*/\1/p')"
          body="$(printf '%s' "$line" | sed -E 's/^-[[:space:]]+//; s/ *<!-- id:[A-Z0-9]+ -->.*//')"
          bodies+=("$body"); ids+=("${id:-?}")
      done < "$_LESSONS"

      local dups="" contras="" i j pct
      for ((i=0; i<${#bodies[@]}; i++)); do
          for ((j=i+1; j<${#bodies[@]}; j++)); do
              pct="$(_jaccard_pct "$(_tokens "${bodies[$i]}")" "$(_tokens "${bodies[$j]}")")"
              if [ "$pct" -ge "$_DUP_MIN" ]; then
                  dups="${dups}{\"a\":\"${ids[$i]}\",\"b\":\"${ids[$j]}\",\"jaccard\":${pct}},"
              elif [ "$pct" -ge "$_CONTRA_MIN" ]; then
                  # Opposing polarity, order-independent: (i.max & j.min) | (i.min & j.max)
                  if { _has_max "${bodies[$i]}" && _has_min "${bodies[$j]}"; } \
                     || { _has_min "${bodies[$i]}" && _has_max "${bodies[$j]}"; }; then
                      contras="${contras}{\"a\":\"${ids[$i]}\",\"b\":\"${ids[$j]}\",\"overlap\":${pct}},"
                  fi
              fi
          done
      done
      printf '{"duplicates":[%s],"contradictions":[%s]}\n' "${dups%,}" "${contras%,}"
      return 0
  }
  ```

  > Self-correction note (F2): thresholds are the numbers actually computed
  > against the fixture — dup ≥50 catches the 50% worktree pair; contra
  > [25,50) + opposing polarity catches the 36% commit-gating pair; the dup
  > branch fires first so the 50% pair never reaches the contra branch; all
  > 0%-overlap negatives fall through both. Polarity is order-independent via
  > `(i.max ∧ j.min) ∨ (i.min ∧ j.max)`. `local -a` (not `-A`) — parallel-array
  > rule. `_has_max`/`_has_min` use `[^a-z]` word boundaries (POSIX, no `\b`).

- [ ] **Step 2: Add consolidation § to `r-util-mem-compact.md`** — after
  `## Step 6: Apply (only with --apply)` (mem-compact.md:89-98), before
  `## Safety Rules`, insert:

  ````
  ## Step 7: Lessons / Insights Consolidation (--lessons or near-cap auto)

  Runs when `$ARGUMENTS` contains `--lessons`, or automatically when invoked
  with no MEMORY target and `~/.rdf/lessons-learned.md` is within 5 of its
  50-entry cap.

  1. Run the deterministic scanner:
     ```bash
     bash state/rdf-lessons.sh scan ~/.rdf/lessons-learned.md
     ```
     Parse the JSON: `duplicates` (token-Jaccard >=50% pairs) and
     `contradictions` (opposing-polarity pairs, 25-49% overlap).

  2. Present each candidate under the **existing y/n/auto gate** (the same
     approve control used by `/r-save` §8):
     - **Duplicate:** show both bullets + the proposed merge (keep the
       more-specific, drop the other). `y` merges; `n` skips; `auto` applies
       all remaining duplicate merges.
     - **Contradiction:** show both bullets. Propose keeping the more
       specific and flagging the other for review. **`auto` NEVER resolves a
       contradiction** — it requires an explicit `y` every time. This is the
       anti-crystallization rule: automatically dropping one side of a
       contradiction can reinforce the wrong lesson.

  3. Apply approved changes to `~/.rdf/lessons-learned.md`, then rebuild the
     index: `bash state/rdf-lessons.sh index`.

  4. Repeat the duplicate pass for `~/.rdf/insights.jsonl` (exact-text and
     token-Jaccard>=50% duplicates only; no contradiction pass on insights).
  ````

- [ ] **Step 3: Extend `## Safety Rules`** — add two bullets
  (mem-compact.md:100-107): "NEVER auto-resolve a lessons contradiction —
  always require explicit `y`." and "NEVER delete a lesson/insight without
  gate approval — dedup merges preserve the surviving entry verbatim."

- [ ] **Step 4: Add 2 memory-context tests + 1 governance-contract (F9)**

  In `tests/memory-context.bats`:

  ```bash
  @test "rdf-lessons scan flags exactly the 50% duplicate" {
      cp "${RDF_SRC}/tests/fixtures/lessons/lessons-sample.md" "${TEST_HOME}/lessons-learned.md"
      bash "${RDF_SRC}/state/rdf-lessons.sh" index "${TEST_HOME}/lessons-learned.md"
      run bash "${RDF_SRC}/state/rdf-lessons.sh" scan "${TEST_HOME}/lessons-learned.md"
      [ "$status" -eq 0 ]
      echo "$output" | jq -e '.duplicates | length == 1' >/dev/null
      echo "$output" | jq -e '.duplicates[0].jaccard == 50' >/dev/null
  }

  @test "rdf-lessons scan flags exactly the 36% contradiction" {
      cp "${RDF_SRC}/tests/fixtures/lessons/lessons-sample.md" "${TEST_HOME}/lessons-learned.md"
      bash "${RDF_SRC}/state/rdf-lessons.sh" index "${TEST_HOME}/lessons-learned.md"
      run bash "${RDF_SRC}/state/rdf-lessons.sh" scan "${TEST_HOME}/lessons-learned.md"
      echo "$output" | jq -e '.contradictions | length == 1' >/dev/null
      echo "$output" | jq -e '.contradictions[0].overlap == 36' >/dev/null
  }
  ```

  In `tests/governance-contracts.bats` (uses the existing `_contract` helper,
  which greps `canonical/<relpath>`):

  ```bash
  @test "consolidation never auto-resolves a contradiction" {
      _contract commands/r-util-mem-compact.md 'NEVER resolves a contradiction'
  }
  ```

- [ ] **Step 5: Lint + test**

  ```bash
  bash -n state/rdf-lessons.sh && shellcheck state/rdf-lessons.sh
  make -C tests test 2>&1 | tee /tmp/test-rdf-P4-debian12.log | grep -c '^not ok'
  # expect: 0
  ```

- [ ] **Step 6: Commit**

  ```bash
  git add state/rdf-lessons.sh canonical/commands/r-util-mem-compact.md \
      tests/memory-context.bats tests/governance-contracts.bats
  git commit -m "Lessons/insights consolidation pass with y/n/auto gate

  [New] rdf-lessons.sh scan — token-Jaccard dedup (>=50) + order-independent
        opposing-polarity contradiction heuristic [25,50) (flags only)
  [Change] r-util-mem-compact: --lessons consolidation step; dedup honors
           auto, contradictions require explicit y (anti-crystallization)
  [New] governance-contract: consolidation never auto-resolves a contradiction"
  ```

---

### Phase 5: T3 — `paths:`-scoped governance rules

Emit `output/rules/<profile>.md`: core unscoped (survives compaction),
language profiles `paths:`-scoped from `registry.json` detect globs.
Parallelizable with Phases 1-4 (disjoint files).

**Files:**
- Modify: `adapters/claude-code/adapter.sh` (`cc_generate_rules()` + wire into `cc_generate_all`)
- Modify: `lib/cmd/deploy.sh` (opt-in `rules/` symlink)
- Modify: `tests/memory-context.bats` (+2 tests)
- Modify: `tests/governance-contracts.bats` (+1 never-scope-core contract — F9)

- **Mode**: parallel-agent (owns adapter.sh + deploy.sh; shares only the two bats files)
- **Accept**: `rdf generate claude-code` writes `output/rules/core.md` with
  NO `paths:` frontmatter and `output/rules/python.md` with a `paths:` block
  derived from `["pyproject.toml","requirements.txt","*.py"]`; one rule per
  active profile
- **Test**: `tests/memory-context.bats` — @test "core rule has no paths frontmatter; python rule has paths from detect globs", @test "generate emits one rule per active profile"
- **Edge cases**: spec §11b "only core profile active" (rules/core.md only), "mixed repo" (core + scoped language rules), §4.3 "never scope core"
- **Regression-case**: tests/memory-context.bats::@test "core rule has no paths frontmatter; python rule has paths from detect globs" (file created in Phase 1 of this plan)

- [ ] **Step 1: Add `cc_generate_rules()` to `adapters/claude-code/adapter.sh`**
  — insert the DEFINITION between functions: after the closing `}` of
  `cc_generate_governance()` (adapter.sh:190) and before the
  `# Full CC generation pipeline` comment (adapter.sh:192). NOT inside
  `cc_generate_all` (F10):

  ```bash
  # Build a `paths:` frontmatter block from a profile's registry detect globs.
  # Args: $1 = profile name. Emits nothing for core (never scoped).
  _cc_paths_frontmatter() {
      local profile="$1"
      local registry="${RDF_HOME}/profiles/registry.json"
      [[ "$profile" == "core" ]] && return 0   # core is always-loaded, never scoped (spec §4.3)
      [[ -f "$registry" ]] || return 0
      local globs
      globs="$(jq -r --arg p "$profile" '.profiles[$p].detect[]?' "$registry" 2>/dev/null)"  # missing profile → empty
      [[ -n "$globs" ]] || return 0
      echo "---"
      echo "paths:"
      while IFS= read -r g; do
          [[ -z "$g" ]] && continue
          case "$g" in
              */) printf '  - "**/%s**"\n' "$g" ;;      # directory glob
              */*) printf '  - "**/%s"\n' "$g" ;;        # path glob
              *) printf '  - "**/%s"\n' "$g" ;;          # extension/file glob
          esac
      done <<< "$globs"
      echo "---"
  }

  # Emit .claude/rules/<profile>.md — core unscoped, language paths-scoped.
  cc_generate_rules() {
      local dst_dir="${_CC_OUTPUT_DIR}/rules"
      command mkdir -p "$dst_dir"
      local count=0 active profile gov_file front
      active="$(rdf_get_active_profiles)"
      while IFS= read -r profile; do
          [[ -z "$profile" ]] && continue
          gov_file="${RDF_HOME}/profiles/${profile}/governance-template.md"
          [[ -f "$gov_file" ]] || continue
          front="$(_cc_paths_frontmatter "$profile")"
          {
              [[ -n "$front" ]] && printf '%s\n' "$front"
              command cat "$gov_file"
          } > "${dst_dir}/${profile}.md"
          count=$((count + 1))
      done <<< "$active"
      rdf_log "generated ${count} rule files"
  }
  ```

  > Self-correction note: `command cat` (coreutils prefix, project source).
  > `_cc_paths_frontmatter core` returns empty → the `[[ -n "$front" ]]`
  > guard omits the block, so `rules/core.md` starts with the governance body
  > (no `---`). The BATS test asserts `head -1` is not `---`.

- [ ] **Step 2: Wire the CALL into `cc_generate_all()`** — the call MUST run
  while `_CC_OUTPUT_DIR` still points at the staging dir `_output_new`, i.e.
  BEFORE the swap-back. Insert after the `cc_generate_governance` call
  (adapter.sh:213) and before the `# Atomic swap` comment (adapter.sh:215)
  (F10 — so `rules/` lands inside the atomic swap):

  ```bash
      cc_generate_rules
  ```

  Extend the completion-log block (adapter.sh:224-229) to count rules:
  `rule_count="$(find "${_CC_OUTPUT_DIR}/rules" -name '*.md' 2>/dev/null | wc -l)"`
  and append `, ${rule_count} rules` to the summary line (adapter.sh:229).

- [ ] **Step 3: Opt-in rules symlink in `lib/cmd/deploy.sh`** — in
  `_deploy_claude_code()`, after the governance symlink (deploy.sh:187),
  add a guarded rules symlink behind a `--rules` / lite flag (default OFF —
  scoped governance is opt-in per spec §3):

  ```bash
      if [[ "${deploy_rules:-0}" -eq 1 && -d "${output_dir}/rules" ]]; then
          _deploy_symlink "${output_dir}/rules" "${dest_base}/rules" "$dry_run" "$force"
      fi
  ```

  Add `deploy_rules` parsing to the deploy arg loop (`--rules` sets it to 1;
  lite deploy sets it in Phase 7). Default 0 = no behavior change for
  existing users.

- [ ] **Step 4: Add 2 tests**

  ```bash
  @test "core rule has no paths frontmatter; python rule has paths from detect globs" {
      bash "${RDF_SRC}/bin/rdf" generate claude-code >/dev/null 2>&1
      local out="${RDF_SRC}/adapters/claude-code/output/rules"
      [ -f "${out}/core.md" ]
      run head -1 "${out}/core.md"
      [ "$output" != "---" ]
      if [ -f "${out}/python.md" ]; then
          run head -1 "${out}/python.md"
          [ "$output" = "---" ]
          grep -q '"\*\*/\*.py"' "${out}/python.md"
      fi
  }

  @test "generate emits one rule per active profile" {
      bash "${RDF_SRC}/bin/rdf" generate claude-code >/dev/null 2>&1
      local rules
      rules="$(find "${RDF_SRC}/adapters/claude-code/output/rules" -name '*.md' | wc -l)"
      [ "$rules" -ge 1 ]
  }
  ```

  In `tests/governance-contracts.bats` — the never-scope-core invariant is an
  ADAPTER mechanic (the `_contract` helper only greps `canonical/`), so this
  contract greps `adapter.sh` directly (noted inline), keeping the promise in
  the governance-contract suite where the reviewer wants it (F9):

  ```bash
  @test "adapter never scopes core governance" {
      # _contract is canonical-only; never-scope-core lives in the adapter.
      grep -qE '\[\[ "\$profile" == "core" \]\] && return 0' \
          "${RDF_SRC}/adapters/claude-code/adapter.sh"
  }
  ```

  > Note: the two `@test`s above generate against the real repo output
  > (local-only, not committed). Restore the tree in Step 6 to avoid dirtying
  > the checkout.

- [ ] **Step 5: Lint + test**

  ```bash
  bash -n adapters/claude-code/adapter.sh lib/cmd/deploy.sh
  shellcheck adapters/claude-code/adapter.sh lib/cmd/deploy.sh
  make -C tests test 2>&1 | tee /tmp/test-rdf-P5-debian12.log | grep -c '^not ok'
  # expect: 0
  ```

- [ ] **Step 6: Real-repo smoke + restore**

  ```bash
  bin/rdf generate claude-code >/dev/null 2>&1
  head -1 adapters/claude-code/output/rules/core.md          # expect: NOT '---'
  head -1 adapters/claude-code/output/rules/python.md 2>/dev/null # expect: '---'
  git checkout -- adapters/ 2>/dev/null; git clean -fdq adapters/claude-code/output 2>/dev/null || true # local-only output
  ```

- [ ] **Step 7: Commit**

  ```bash
  git add adapters/claude-code/adapter.sh lib/cmd/deploy.sh \
      tests/memory-context.bats tests/governance-contracts.bats
  git commit -m "T3: emit paths-scoped governance rules (core unscoped)

  [New] cc_generate_rules — output/rules/<profile>.md; language profiles get
        paths: frontmatter from registry detect globs, core stays unscoped so
        it survives compaction (spec §4.3)
  [Change] deploy: opt-in rules/ symlink (--rules) — default off, no behavior
           change for existing symlink users
  [New] governance-contract: adapter never scopes core governance"
  ```

---

### Phase 6: Published context cost + measurement harness

Isolate RDF's per-session token overhead, publish it, and guard the number
against drift. Depends on Phase 5 (rules contribute to the measured weight).

**Files:**
- Create: `state/rdf-overhead.sh`
- Modify: `canonical/commands/r-context-audit.md` (surface `rdf_overhead`)
- Modify: `README.md` (published number)
- Modify: `tests/memory-context.bats` (+2 tests, incl. drift guard)

- **Mode**: serial-agent
- **Accept**: `state/rdf-overhead.sh` emits JSON with `default_boot_tokens`,
  `rules_boot_tokens`, `lite_boot_tokens`, a `breakdown`, and an `excluded`
  block (hooks.json bytes NOT in any boot figure — F8); README states the
  DEFAULT and `--rules` figures SEPARATELY; the drift-guard test verifies the
  published default against measurement (±15%)
- **Test**: `tests/memory-context.bats` — @test "rdf-overhead emits default/rules/lite figures and excludes hooks.json", @test "published README default number is within tolerance of measurement"
- **Edge cases**: spec §11b measurement reuse of context-audit byte→token heuristic; scoped rules counted as dormant (not in boot); rules opt-in so default excludes core.md
- **Regression-case**: tests/memory-context.bats::@test "published README default number is within tolerance of measurement" (file created in Phase 1 of this plan)

- [ ] **Step 1: Create `state/rdf-overhead.sh`**

  ```bash
  #!/usr/bin/env bash
  # state/rdf-overhead.sh — isolate RDF's always-loaded token overhead
  # (C) 2026 R-fx Networks <proj@rfxn.com>
  # GNU GPL v2
  # Output: JSON to stdout. bytes/4 token heuristic (matches context-audit.sh).
  # hooks.json is EXCLUDED from every boot figure (runtime config — F8).
  set -euo pipefail

  _rdf_home="${RDF_HOME:-$(cd "$(command dirname "$0")/.." && pwd)}"
  _out="${_rdf_home}/adapters/claude-code/output"

  _bytes() { command cat "$@" 2>/dev/null | wc -c | tr -d ' '; }   # 0 if missing
  _tok() { echo $(( ${1:-0} / 4 )); }

  lessons_idx_b="$(_bytes "${HOME}/.rdf/lessons-index.md")"     # the ONLY default-loaded RDF context
  core_rule_b="$(_bytes "${_out}/rules/core.md")"              # loads only with --rules (opt-in)
  lite_core_b="$(_bytes "${_rdf_home}/profiles/lite/governance-lite.md")"
  hooks_b="$(_bytes "${_out}/hooks.json")"                     # EXCLUDED from boot (runtime config)

  # Scoped language rules are dormant (load only on a matching file read).
  dormant_b=0
  if [[ -d "${_out}/rules" ]]; then
      for f in "${_out}/rules"/*.md; do
          [[ -f "$f" ]] || continue
          [[ "$(command basename "$f")" == "core.md" ]] && continue
          dormant_b=$(( dormant_b + $(_bytes "$f") ))
      done
  fi

  # Default deploy: governance is symlinked to ~/.claude/governance (NOT
  # auto-loaded) and rules deploy is opt-in — so the only always-loaded RDF
  # context by default is the lessons-index injection.
  default_boot_b=$(( lessons_idx_b ))
  rules_boot_b=$(( lessons_idx_b + core_rule_b ))          # opt-in --rules figure
  lite_boot_b=$(( lessons_idx_b + lite_core_b ))

  commit="$(git -C "$_rdf_home" rev-parse --short HEAD 2>/dev/null || echo unknown)"  # non-git → unknown

  command cat <<JSON
  {
    "default_boot_tokens": $(_tok "$default_boot_b"),
    "rules_boot_tokens": $(_tok "$rules_boot_b"),
    "lite_boot_tokens": $(_tok "$lite_boot_b"),
    "breakdown": {
      "lessons_index": $(_tok "$lessons_idx_b"),
      "core_governance_rule": $(_tok "$core_rule_b"),
      "scoped_rules_dormant": $(_tok "$dormant_b"),
      "lite_core_governance": $(_tok "$lite_core_b")
    },
    "excluded": { "hooks_json_runtime_config": $(_tok "$hooks_b") },
    "measured_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
    "commit": "${commit}"
  }
  JSON
  ```

  > Self-correction note (F8): hooks.json is runtime config and never enters
  > model context, so it is reported under `excluded`, NOT in any boot figure.
  > Rules deploy is opt-in (default-off), so `default_boot_tokens` counts only
  > the lessons-index; `rules_boot_tokens` adds `core.md`. The `bytes/4`
  > heuristic mirrors context-audit.sh — a stable published figure guarded
  > against drift, not an exact token count.

- [ ] **Step 2: Surface in `r-context-audit.md`** — in `### 1. Run
  Measurement Script` (r-context-audit.md:15, matching the file's existing
  `rdf/state/…` path prefix — F14), add after the baseline block:

  ```
  Also run the RDF-overhead isolator to report RDF's own contribution:
  ```bash
  bash rdf/state/rdf-overhead.sh 2>/dev/null
  ```
  Surface `default_boot_tokens`, `rules_boot_tokens`, and `lite_boot_tokens`
  in the report header alongside total boot cost — these are the numbers
  published in the README. `hooks.json` is runtime config, not model context,
  and appears only under `excluded`.
  ```

- [ ] **Step 3: Publish in `README.md`** — add a short "Context cost"
  subsection near the context-audit row (README.md:133 area). Publish DEFAULT
  and opt-in `--rules` figures separately (F8):

  ```
  **Context cost:** RDF's default deploy adds ~{D}K always-loaded tokens per
  session (lessons-index only — governance is read on demand); the opt-in
  scoped-governance deploy (`--rules`) adds ~{R}K; rdf-lite ~{L}K.
  `hooks.json` is runtime config and is not counted. Measured by
  `rdf/state/rdf-overhead.sh`, guarded in CI.
  ```

  Fill `{D}`/`{R}`/`{L}` from `bash rdf/state/rdf-overhead.sh` at build time
  (round to 1 decimal K). The drift guard keys on `{D}` (the default figure).

- [ ] **Step 4: Add 2 tests (incl. drift guard on the DEFAULT figure)**

  ```bash
  @test "rdf-overhead emits default/rules/lite figures and excludes hooks.json" {
      run bash -c 'RDF_HOME="$1" bash "$1/state/rdf-overhead.sh"' -- "$RDF_SRC"
      [ "$status" -eq 0 ]
      echo "$output" | jq -e '.default_boot_tokens != null and .rules_boot_tokens != null and .lite_boot_tokens != null' >/dev/null
      echo "$output" | jq -e '.excluded.hooks_json_runtime_config != null' >/dev/null
  }

  @test "published README default number is within tolerance of measurement" {
      bash "${RDF_SRC}/bin/rdf" generate claude-code >/dev/null 2>&1
      measured="$(RDF_HOME="$RDF_SRC" bash "${RDF_SRC}/state/rdf-overhead.sh" | jq -r '.default_boot_tokens')"
      # README states the DEFAULT number in K after "default deploy adds ~".
      published_k="$(grep -oE 'default deploy adds ~[0-9]+(\.[0-9])?K' "${RDF_SRC}/README.md" | head -1 | grep -oE '[0-9]+(\.[0-9])?')"
      [ -n "$published_k" ]
      meas_k="$(awk "BEGIN{printf \"%.2f\", ${measured}/1000}")"
      ok="$(awk "BEGIN{d=(${meas_k}-${published_k}); d=(d<0?-d:d); print (d <= 0.15*${published_k}+0.2)?1:0}")"
      [ "$ok" -eq 1 ]
      git -C "$RDF_SRC" checkout -- adapters/ 2>/dev/null || true
      git -C "$RDF_SRC" clean -fdq adapters/claude-code/output 2>/dev/null || true
  }
  ```

- [ ] **Step 5: Lint + test**

  ```bash
  bash -n state/rdf-overhead.sh && shellcheck state/rdf-overhead.sh
  make -C tests test 2>&1 | tee /tmp/test-rdf-P6-debian12.log | grep -c '^not ok'
  # expect: 0
  ```

- [ ] **Step 6: Commit**

  ```bash
  git add state/rdf-overhead.sh canonical/commands/r-context-audit.md README.md tests/memory-context.bats
  git commit -m "Publish RDF per-session context cost + measurement harness

  [New] state/rdf-overhead.sh — isolate RDF's always-loaded overhead into
        default / --rules / lite figures; hooks.json excluded (runtime config);
        scoped rules counted dormant
  [Change] r-context-audit surfaces default/rules/lite boot tokens
  [Change] README publishes default + --rules separately; BATS drift guard
           keys on the default figure"
  ```

---

### Phase 7: rdf-lite minimal profile

Minimal-overhead deployment: condensed core governance, lifecycle commands
only, no hooks/statusline, language governance scoped/dormant. Depends on
Phase 5 (rules) and Phase 6 (budget measurement). **Fast-follow candidate —
defer to 3.4.1 if release scope tightens** (see plan summary).

**Files:**
- Create: `profiles/lite/governance-lite.md`
- Modify: `adapters/claude-code/adapter.sh` (`--lite` branch in `cc_generate_all`)
- Modify: `lib/cmd/generate.sh` (`--lite` flag)
- Modify: `lib/cmd/deploy.sh` (`--lite` sets `deploy_rules`, skips hooks)
- Modify: `tests/memory-context.bats` (+2 tests)

- **Mode**: serial-agent
- **Accept**: `rdf generate claude-code --lite` produces `rules/core.md`
  sourced from `governance-lite.md`, emits no hooks, and
  `state/rdf-overhead.sh` reports `lite_boot_tokens <= 1000`
- **Test**: `tests/memory-context.bats` — @test "lite generate sources condensed core and skips hooks", @test "lite footprint is <=1000 tokens"
- **Edge cases**: spec §11b "--lite with language profiles" (condensed core unscoped + language scoped dormant; hooks skipped)
- **Regression-case**: tests/memory-context.bats::@test "lite footprint is <=1000 tokens" (file created in Phase 1 of this plan)

- [ ] **Step 1: Create `profiles/lite/governance-lite.md`** — hand-authored
  ~700-token distillation of core governance (commit protocol one-liner,
  coreutils `command` prefix, `cd` guards, security hygiene, top anti-
  patterns). Frontmatter-free. Verify byte budget: `wc -c
  profiles/lite/governance-lite.md` should be ≲ 2800 bytes (~700 tokens).

- [ ] **Step 2: `--lite` branch in `cc_generate_all()`** — thread a
  `_CC_LITE` flag (default 0). In lite mode: `cc_generate_rules` sources
  `profiles/lite/governance-lite.md` for `rules/core.md` instead of the full
  core template; skip `cc_generate_hooks`; restrict `cc_generate_commands`
  to the lifecycle set (`r-spec r-plan r-build r-ship r-start r-save`). Add a
  guard list and a `[[ "$_CC_LITE" -eq 1 ]]` conditional; keep the full path
  byte-identical when the flag is 0.

- [ ] **Step 3: `--lite` flag in `lib/cmd/generate.sh`** — in the arg loop
  (generate.sh ~L69-79), parse `--lite` → export `_CC_LITE=1` before calling
  `_generate_adapter "claude-code/adapter.sh" "cc_generate_all"`. Update
  `_generate_usage` (generate.sh:7-15) with a `--lite` Options line.

- [ ] **Step 4: `--lite` deploy** — in `lib/cmd/deploy.sh`, `--lite` sets
  `deploy_rules=1` (rules ARE the governance in lite) and forces the hooks
  skip (already skipped) — document that lite deploy is the intended path for
  scoped rules.

- [ ] **Step 5: Add 2 tests**

  ```bash
  @test "lite generate sources condensed core and skips hooks" {
      _CC_LITE=1 bash -c 'RDF_HOME="$1" _CC_LITE=1 bash "$1/bin/rdf" generate claude-code --lite' -- "$RDF_SRC" >/dev/null 2>&1 || \
        bash "${RDF_SRC}/bin/rdf" generate claude-code --lite >/dev/null 2>&1
      [ -f "${RDF_SRC}/adapters/claude-code/output/rules/core.md" ]
      # condensed core is smaller than full core template
      lite_b="$(wc -c < "${RDF_SRC}/adapters/claude-code/output/rules/core.md")"
      full_b="$(wc -c < "${RDF_SRC}/profiles/core/governance-template.md")"
      [ "$lite_b" -lt "$full_b" ]
      git -C "$RDF_SRC" checkout -- adapters/ 2>/dev/null || true
      git -C "$RDF_SRC" clean -fdq adapters/claude-code/output 2>/dev/null || true
  }

  @test "lite footprint is <=1000 tokens" {
      run bash -c 'RDF_HOME="$1" bash "$1/state/rdf-overhead.sh" | jq -r .lite_boot_tokens' -- "$RDF_SRC"
      [ "$status" -eq 0 ]
      [ "$output" -le 1000 ]
  }
  ```

- [ ] **Step 6: Lint + test + restore**

  ```bash
  bash -n adapters/claude-code/adapter.sh lib/cmd/generate.sh lib/cmd/deploy.sh
  shellcheck adapters/claude-code/adapter.sh lib/cmd/generate.sh lib/cmd/deploy.sh
  make -C tests test 2>&1 | tee /tmp/test-rdf-P7-debian12.log | grep -c '^not ok'
  # expect: 0
  git checkout -- adapters/ 2>/dev/null; git clean -fdq adapters/claude-code/output 2>/dev/null || true
  ```

- [ ] **Step 7: Commit**

  ```bash
  git add profiles/lite/governance-lite.md adapters/claude-code/adapter.sh \
      lib/cmd/generate.sh lib/cmd/deploy.sh tests/memory-context.bats
  git commit -m "Add rdf-lite minimal deployment (~700-token footprint)

  [New] profiles/lite/governance-lite.md — condensed core governance
  [New] rdf generate claude-code --lite — condensed core, lifecycle commands
        only, no hooks; language governance scoped/dormant
  [Change] deploy --lite: rules-as-governance, hooks skipped"
  ```

---

### Phase 8: Docs, coexistence, and release

Native-memory coexistence doc, ROADMAP, CHANGELOG, VERSION 3.4.0. Depends on
all prior phases.

**Files:**
- Create: `docs/memory-context.md`
- Modify: `ROADMAP.md`, `CHANGELOG`, `CHANGELOG.RELEASE`, `VERSION`

- **Mode**: serial-context
- **Accept**: `docs/memory-context.md` states the RDF-vs-native division of
  labor (spec §4.5); ROADMAP checks delivered items; CHANGELOG +
  CHANGELOG.RELEASE have 3.4.0 entries; `VERSION` is `3.4.0`;
  `rdf doctor` 0 FAIL; full suite green
- **Test**: N/A (docs + version) — verification greps below
- **Edge cases**: spec §11b coexistence (no file written to native memory dir)
- **Regression-case**: N/A — docs/release phase, no new runtime surface

- [ ] **Step 1: Create `docs/memory-context.md`** — user-facing coexistence:
  the §4.5 table (native owns conversational memory + MEMORY.md loading; RDF
  owns lessons, insights, governance, project-state hygiene, session
  journal), plus a short "what RDF does NOT do" (no parallel memory system,
  no writes to `~/.claude/projects/<slug>/memory/`).

- [ ] **Step 2: ROADMAP.md** — move the "Deferred: Context-scoped governance
  loading (3.2 T3)" line to delivered; add a memory/context bullet under a
  shipped section. Leave rdf-lite unchecked if Phase 7 was deferred.

- [ ] **Step 3: CHANGELOG + CHANGELOG.RELEASE** — add a `## 3.4.0` block
  (New Features / Changes) covering: SessionEnd journal-append capture,
  `/r-save` cache-skip + deterministic `diff_categories` in rdf-state.sh,
  auto-acting thresholds, lessons ID-index + read-only SessionStart inject,
  gated consolidation pass, T3 scoped rules, published default/rules context
  cost + harness, rdf-lite. Follow the soft-wrap/tag style in the existing
  3.3.0 entries.

- [ ] **Step 4: VERSION** — set to `3.4.0`.

- [ ] **Step 5: Verify + full matrix**

  ```bash
  cat VERSION                                   # expect: 3.4.0
  grep -q 'native' docs/memory-context.md && echo "coexistence doc ok"
  bash bin/rdf doctor 2>&1 | grep -c 'FAIL'     # expect: 0
  make -C tests test 2>&1 | tee /tmp/test-rdf-P8-debian12.log | grep -c '^not ok'   # expect: 0
  DOCKER_HOST=tcp://192.168.2.189:2376 DOCKER_TLS_VERIFY=1 DOCKER_CERT_PATH=~/.docker/tls \
    make -C tests test-rocky9 2>&1 | tee /tmp/test-rdf-P8-rocky9.log | grep -c '^not ok'   # expect: 0
  ```

- [ ] **Step 6: Commit**

  ```bash
  git add docs/memory-context.md ROADMAP.md CHANGELOG CHANGELOG.RELEASE VERSION
  git commit -m "3.4.0 — Memory & Context: coexistence doc, roadmap, changelog

  [New] docs/memory-context.md — native-memory vs RDF division of labor
  [Change] ROADMAP: T3 scoped governance + memory/context delivered
  [Change] CHANGELOG/CHANGELOG.RELEASE: 3.4.0 entries; VERSION 3.4.0"
  ```

---

## Post-Plan: Sentinel

After Phase 8, dispatch an end-of-plan sentinel review (mandatory — this plan
is dispatched as a batch, and the orchestrator does not auto-trigger a
sentinel for manually dispatched phases). Sentinel must verify: no bare
coreutils in new shell source, all hooks exit 0 on degrade paths, core rule
never carries `paths:`, and a full-repo grep for stale `⚠ MEMORY.md`/`⚠
Context` warning strings that should now be `▶` directives.
