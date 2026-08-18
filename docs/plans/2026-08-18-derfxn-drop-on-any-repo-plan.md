# Implementation Plan: De-rfxn Core — "Drop It on Any Repo" (3.6.5)

**Goal:** Make the README's "drop it on any repo" claim true: extract rfxn-specific content into an opt-in `rfxn-workspace` profile, ship `canonical/reference/` through the CC-family adapters and deploy, make `rdf deploy` truthful (exit 1 on skips + real hooks-merge how-to), close the plain-Node detection gap, and sweep the verified doc falsehoods.

**Architecture:** Overlay/preset pattern — generic core, org layer as an opt-in profile using existing profile machinery. Reference docs become a first-class adapter artifact with hash sidecars wired into both doctor loops. See spec §4.

**Tech Stack:** Bash 3.2+ floor (macOS system bash; CI-smoked), BATS (tests/, local `make -C tests test` equivalent: `bats tests/`), jq, shellcheck.

**Spec:** docs/specs/2026-08-18-derfxn-drop-on-any-repo-design.md

**Phases:** 8

**Plan Version:** 3.0.6

**Tier:** full

## RC Contract Evidence

| Caller | Helper | Contract | Evidence |
|--------|--------|----------|----------|
| `cmd_deploy` (deploy.sh:361-365) | summary path | NEW: returns 1 when `_DEPLOY_SKIPPED>0`, 0 otherwise (Phase 6) | current code falls through `if/else` returning 0 always — verified deploy.sh:361-366 |
| `_deploy_claude_code` | `_deploy_symlink` | returns 1 + increments `_DEPLOY_SKIPPED` on missing source (deploy.sh:51-54) — so a skeleton without `reference/` makes every deploy exit 1 after Phase 6; Phase 6 Step 1 therefore updates `_make_deploy_skeleton` FIRST | verified deploy.sh:51-54, tests/deploy.bats:20-27 |
| `subagent-stop.sh` | (self) | always exits 0; `set -uo pipefail` without `-e`, so a failed mkdir/append does not abort — preserved by Phase 2 | verified line 8, 57 |
| `_generate_claude_md` | profile template probe | missing `governance-template.md` → `rdf_warn` + continue (init.sh:325-330) — why Phase 3 (node) must land its template in the same phase as its `_KNOWN_PROFILES` entry | verified init.sh:321-331 |

## Conventions

**Shell:** bash 3.2-safe (no `${var,,}`, no `declare -A` globals); `command` prefix on coreutils in project source; suppressions (`2>/dev/null`, `|| true`) get a same-line justification comment; `#!/usr/bin/env bash` shebang.

**Commit format (RDF):** free-form descriptive subject, body lines tagged `[New]`/`[Change]`/`[Fix]`/`[Remove]`. Stage files explicitly by name. No AI attribution.

**CHANGELOG:** per RDF parallel-exception, Phases 1-7 do NOT touch CHANGELOG/CHANGELOG.RELEASE; Phase 8 consolidates both (noted here explicitly as the plan's declared exception).

**Regeneration rule:** any commit touching `canonical/` runs `rdf generate claude-code` first (project CLAUDE.md). Phases 2 and 7 touch `canonical/`; to avoid three interleaved output-regen commits and churn, output regeneration is consolidated in Phase 8 (`rdf generate all`) — declared here as the plan's regen exception; Phase 8 depends on all prior phases.

**Verification baseline per shell-touching phase:** `bash -n <file>` + `shellcheck <file>` before commit.

**CRITICAL:** never `git add -A`; never modify frozen CLI case arms; do not edit `adapters/gemini-cli/` generation source; do not edit vendored `canonical/scripts/` (context-bar.sh, setup.sh, clone-conversation.sh, half-clone-conversation.sh, test-half-clone.sh, color-preview.sh, check-context.sh).

## File Map

### New Files
| File | Lines | Purpose | Test File |
|------|-------|---------|-----------|
| `profiles/rfxn-workspace/governance-template.md` | ~35 | Org overlay governance | `tests/derfxn.bats` |
| `profiles/node/governance-template.md` | ~90 | Node.js governance | `tests/derfxn.bats` |
| `tests/derfxn.bats` | ~150 | Regression suite for spec goals 1-8 — created in Phase 1, extended incrementally by Phases 2-5, 7-8 (12 tests total at Phase 8) | (self) |

### Moved Files (expressed as Create+Delete pairs for machine parsing)
| File | From | Test File |
|------|------|-----------|
| `profiles/rfxn-workspace/reference/cross-project.md` | `profiles/core/reference/` | `tests/derfxn.bats` |
| `profiles/rfxn-workspace/scripts/comment-snapshot.sh` | `canonical/scripts/` (+1-line METRICS path fix) | N/A (org tool; `bash -n` only) |

### Modified Files
| File | Changes | Test File |
|------|---------|-----------|
| `lib/cmd/init.sh` | `_KNOWN_PROFILES` += rfxn-workspace, node; node detect branch; companion de-rfxn | `tests/derfxn.bats` |
| `canonical/reference/framework.md` | artifact-table rows :21/:26 → `<workspace>/…` | `tests/derfxn.bats` (grep) |
| `CLAUDE.md` | bash-floor bullet (line 27) reconciled with CONTRIBUTING/CI | N/A (docs) |
| `canonical/scripts/subagent-stop.sh` | shebang; feed-log fallback chain | `tests/derfxn.bats` |
| `canonical/commands/r-util-proj-cross.md` | generic workspace wording | `tests/derfxn.bats` (grep) |
| `canonical/commands/r-util-mem-audit.md` | generic workspace wording | `tests/derfxn.bats` (grep) |
| `profiles/registry.json` | +rfxn-workspace, +node entries | `tests/derfxn.bats` |
| `profiles/detection-rules.md` | +node, +rfxn-workspace sections | N/A (docs) |
| `adapters/claude-code/adapter.sh` | `cc_generate_reference()` + wiring + summary | `tests/derfxn.bats` |
| `adapters/claude-plugin/adapter.sh` | `cpl_generate_reference()` + wiring | `tests/derfxn.bats` |
| `adapters/agent-skills/adapter.sh` | reference copy in `sk_generate_all` | `tests/derfxn.bats` |
| `lib/cmd/doctor.sh` | content-drift 3rd loop; sync loop += governance reference | `tests/doctor.bats` (existing pass) |
| `lib/cmd/deploy.sh` | reference symlink; exit 1 on skips; usage how-to | `tests/deploy.bats` |
| `tests/deploy.bats` | skeleton += reference; 3 new tests; skip-case status updates | (self) |
| `reference/templates/SECURITY.md` | `Email:` → `Contact:` | `tests/derfxn.bats` |
| `README.md` | drop `--tools`; `/r-init` out of bash fences; doc-stats counts (P3) | `tests/derfxn.bats` (grep) |
| `WORKFORCE.md` | doc-stats scripts count 17→16 (P3) | N/A (docs) |
| `docs/index.md` | doc-stats profiles count 11→13 (P3) | N/A (docs) |
| `docs/quickstart.md` | bash 3.2+; absolute links | `tests/derfxn.bats` (grep) |
| `docs/memory-context.md` | absolute spec link | N/A (docs) |
| `adapters/claude-plugin/output/**` | regenerated + committed (Phases 5, 8) — tracked (plugin install artifact) | `tests/derfxn.bats` |
| `adapters/agents-md/output/AGENTS.md` | regenerated + committed (Phase 8) — tracked (release artifact); inherits the framework.md path fix from Phase 2 | `tests/derfxn.bats` |

Untracked output trees (claude-code, gemini-cli, codex, agent-skills) regenerate locally as gitignored artifacts — never staged, covered by skip-guarded tests.
| `CHANGELOG`, `CHANGELOG.RELEASE` | consolidated entries (Phase 8) | N/A (docs) |

### Deleted Files
| File | Reason |
|------|--------|
| `profiles/core/reference/cross-project.md` | moved to rfxn-workspace (leak source) |
| `canonical/scripts/comment-snapshot.sh` | moved to rfxn-workspace (leak source) |

(The tracked `adapters/claude-plugin/output/scripts/comment-snapshot.sh` disappears via the `adapters/claude-plugin/output/**` regeneration rows above; untracked outputs regenerate clean locally.)

## Phase Dependencies

- Phase 1: none
- Phase 2: [1]
- Phase 3: [2]
- Phase 4: [3]
- Phase 5: [4]
- Phase 6: [5]
- Phase 7: [6]
- Phase 8: [7]

(Strictly sequential by design: `tests/derfxn.bats` is created in Phase 1 and extended by Phases 2-5, 7-8 (TDD — each phase lands its own tests), and `lib/cmd/init.sh` / `profiles/registry.json` / `profiles/detection-rules.md` are each touched by multiple phases. Sequential ownership eliminates every shared-file conflict; phases are small, so lost parallelism is negligible.)

---

### Phase 1: Extract the rfxn-workspace profile

Create the opt-in org overlay and move the two rfxn leak sources into it.

**Files:**
- Create: `profiles/rfxn-workspace/governance-template.md`
- Create: `tests/derfxn.bats`
- Create: `profiles/rfxn-workspace/reference/cross-project.md`
- Create: `profiles/rfxn-workspace/scripts/comment-snapshot.sh`
- Delete: `profiles/core/reference/cross-project.md`
- Delete: `canonical/scripts/comment-snapshot.sh`
- Modify: `profiles/registry.json`
- Modify: `lib/cmd/init.sh`
- Modify: `profiles/detection-rules.md`

(The Create/Delete pairs are `git mv` moves — Step 1.)

- **Goals:** 2, 3
- **Mode**: serial-agent
- **Accept**: `[[ ! -e profiles/core/reference/cross-project.md && ! -e canonical/scripts/comment-snapshot.sh ]]`; `jq -e '.profiles["rfxn-workspace"].detect == []' profiles/registry.json` exits 0; `grep -c 'rfxn-workspace' lib/cmd/init.sh` returns 1; `bash -n` + `shellcheck` clean on moved script; `bats tests/derfxn.bats` green.
- **Test**: `tests/derfxn.bats::@test "rfxn-workspace profile is opt-in: not auto-detected, valid via --type"` and `::@test "init on plain repo copies no cross-project.md"` (both created this phase) + step verifications below.
- **Edge cases**: spec 11b "rdf init --type rfxn-workspace alone" (valid via `_validate_profiles` once in `_KNOWN_PROFILES`); "profile install rfxn-workspace on non-rfxn machine" (content is inert docs — no path assumptions added).
- **Regression-case**: `tests/derfxn.bats::@test "rfxn-workspace profile is opt-in: not auto-detected, valid via --type"` (file created in this phase)

- [ ] **Step 1: Move the two files with git mv**

  ```bash
  command mkdir -p profiles/rfxn-workspace/reference profiles/rfxn-workspace/scripts
  git mv profiles/core/reference/cross-project.md profiles/rfxn-workspace/reference/cross-project.md
  git mv canonical/scripts/comment-snapshot.sh profiles/rfxn-workspace/scripts/comment-snapshot.sh
  ```

- [ ] **Step 2: Fix the moved snapshot script's METRICS path and the moved reference's preamble**

  `profiles/rfxn-workspace/scripts/comment-snapshot.sh` line 9, old→new:

  ```bash
  # old
  METRICS="$(command dirname "$0")/comment-metrics.sh"
  # new (comment-metrics.sh is generic and stays in canonical/scripts/)
  METRICS="$(command dirname "$0")/../../../canonical/scripts/comment-metrics.sh"
  ```

  `profiles/rfxn-workspace/reference/cross-project.md` lines 3-4, old→new:

  ```
  # old
  > Reference for core profile. Patterns for managing
  > shared libraries and consumer updates across the rfxn ecosystem.
  # new
  > Reference for the rfxn-workspace profile (opt-in org overlay).
  > Patterns for managing shared libraries and consumer updates across
  > the rfxn ecosystem.
  ```

- [ ] **Step 3: Create `profiles/rfxn-workspace/governance-template.md`**

  Full content:

  ```markdown
  # rfxn Workspace Governance Template

  > Seed template for /r-init. R-fx Networks org overlay — opt-in only
  > (never auto-detected). Requires core profile. Activate with
  > `rdf init --type <lang>,rfxn-workspace` or `rdf profile install
  > rfxn-workspace`.

  ## Cross-Project Coordination

  - Shared libraries (tlog_lib, alert_lib, elog_lib, pkg_lib, geoip_lib,
    batsman) develop and test in their canonical repo first -- never edit a
    library copy inside a consuming project
  - Release order: library first, then consumers -- update submodule pins in
    each consumer and run its test suite before committing the pin
  - When a bug is root-caused to a shared library, verify all consuming
    projects before the session ends -- do not defer consumer verification
  - See reference/cross-project.md for the library-to-consumer matrix and
    the integration test sequence

  ## Workspace Layout

  - The workspace root is a non-git parent directory containing the project
    repos; workspace-level state lives in `<workspace>/.rdf/` (flat)
  - Use `rdf init --batch` from the workspace root to initialize new
    project sets; per-project `.rdf/work-output/` takes precedence over
    workspace state for hooks and dispatch artifacts

  ## Org Tooling

  - `scripts/comment-snapshot.sh` (this profile) runs comment-density
    metrics across the shared library set -- run from an RDF checkout
  ```

- [ ] **Step 4: Add the registry entry**

  `profiles/registry.json` — after the closing brace of the `"infrastructure"` entry (last key in `.profiles`), add (keep JSON valid — add a comma to the preceding entry):

  ```json
  "rfxn-workspace": {
    "requires": ["core"],
    "removable": true,
    "tier": "full",
    "detect": [],
    "description": "R-fx Networks org overlay. Opt-in only (never auto-detected): shared-library release workflow, consumer verification, workspace tooling",
    "summary": "governance-template + 1 reference doc"
  }
  ```

- [ ] **Step 5: Register the profile name in init.sh**

  `lib/cmd/init.sh:39`, old→new:

  ```bash
  # old
  _KNOWN_PROFILES="shell python go rust typescript perl php frontend database infrastructure minimal"
  # new
  _KNOWN_PROFILES="shell python go rust typescript perl php frontend database infrastructure minimal rfxn-workspace"
  ```

- [ ] **Step 6: Document opt-in in detection-rules.md**

  Append at end of `profiles/detection-rules.md`:

  ```markdown
  ### rfxn-workspace (opt-in only)

  Never auto-detected (`detect: []`). The R-fx Networks org overlay is
  activated explicitly: `rdf init --type <lang>,rfxn-workspace` or
  `rdf profile install rfxn-workspace`. Auto-detection heuristics
  (git-remote sniffing, path matching) were rejected as fragile — org
  overlays must be a deliberate choice (see spec 2026-08-18 §4).
  ```

- [ ] **Step 7: Create `tests/derfxn.bats` with the shared harness + this phase's 2 tests**

  New file. Harness mirrors tests/deploy.bats:14-16 (`RDF_SRC` resolution) plus two helpers reused by later phases; bare coreutils are correct in `.bats`:

  ```bash
  #!/usr/bin/env bats
  # tests/derfxn.bats — de-rfxn regression suite (spec 2026-08-18)
  # (C) 2026 R-fx Networks <proj@rfxn.com>
  # GNU GPL v2
  #
  # Hermetic: every fixture under mktemp -d; no shared-directory scans.
  # shellcheck disable=SC2154,SC2164,SC1090,SC1091,SC2016

  RDF_SRC="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  export RDF_SRC

  # _rdf_call <fn-and-args...> — run an init.sh function against the checkout
  _rdf_call() {
      bash -c '
          rdf_src="$1"; shift
          RDF_HOME="$rdf_src"; RDF_LIBDIR="${rdf_src}/lib"
          source "${rdf_src}/lib/rdf_common.sh"
          rdf_init
          source "${rdf_src}/lib/cmd/init.sh"
          "$@"
      ' -- "$RDF_SRC" "$@"
  }

  setup() { FIX="$(mktemp -d)"; export FIX; }
  teardown() { rm -rf "$FIX" 2>/dev/null || true; }  # cleanup, ignore errors

  @test "rfxn-workspace profile is opt-in: not auto-detected, valid via --type" {
      touch "$FIX/x.sh"
      run _rdf_call _detect_profiles "$FIX"
      [ "$status" -eq 0 ]
      [[ "$output" != *rfxn-workspace* ]]
      run _rdf_call cmd_init "$FIX" --type shell,rfxn-workspace --no-memory
      [ "$status" -eq 0 ]
      grep -q 'Cross-Project Coordination' "$FIX/CLAUDE.md"
      # spec 11b: rfxn-workspace ALONE (no language profile) is also valid
      local alone; alone="$(mktemp -d)"
      run _rdf_call cmd_init "$alone" --type rfxn-workspace --no-memory
      [ "$status" -eq 0 ]
      grep -q 'Cross-Project Coordination' "$alone/CLAUDE.md"
      rm -rf "$alone"
  }

  @test "init on plain repo copies no cross-project.md" {
      touch "$FIX/x.sh"
      run _rdf_call cmd_init "$FIX" --type shell --no-memory
      [ "$status" -eq 0 ]
      [ ! -f "$FIX/.rdf/governance/reference/cross-project.md" ]
  }
  ```

  > Self-correction note: if `rdf_init` needs different plumbing, adapt from whatever makes Phase 1 Step 8's `bats` run pass — the harness shape is the contract, not the exact env lines.

- [ ] **Step 8: Verify**

  ```bash
  jq -e '.profiles["rfxn-workspace"].detect == []' profiles/registry.json && echo OK
  # expect: true + OK
  bash -n profiles/rfxn-workspace/scripts/comment-snapshot.sh && echo SYNTAX-OK
  # expect: SYNTAX-OK
  ls canonical/scripts/comment-snapshot.sh profiles/core/reference/cross-project.md 2>&1 | grep -c 'No such file'
  # expect: 2
  grep -c 'rfxn-workspace' lib/cmd/init.sh
  # expect: 1
  shellcheck profiles/rfxn-workspace/scripts/comment-snapshot.sh; echo "sc=$?"
  # expect: sc=0
  bats tests/derfxn.bats 2>&1 | tail -1
  # expect: 0 failures
  ```

- [ ] **Step 9: Commit**

  ```bash
  git add profiles/rfxn-workspace/governance-template.md profiles/rfxn-workspace/reference/cross-project.md profiles/rfxn-workspace/scripts/comment-snapshot.sh profiles/registry.json profiles/detection-rules.md lib/cmd/init.sh tests/derfxn.bats
  git commit -m "Extract rfxn-workspace profile: org content out of generic core

[New] profiles/rfxn-workspace/ — opt-in org overlay (detect: [], never
      auto-detected): governance template, cross-project.md reference,
      comment-snapshot.sh org tool
[Change] cross-project.md moved out of profiles/core/reference/ — rdf init
         no longer copies APF/BFD/LMD dependency tables into consumer repos
[Change] comment-snapshot.sh moved out of canonical/scripts/ — no longer
         shipped in adapter outputs; METRICS resolves repo-relative
[New] tests/derfxn.bats — de-rfxn regression suite (harness + opt-in and
      no-cross-project tests; later phases extend)"
  ```

---

### Phase 2: De-rfxn canonical scripts and commands

Remove the hardcoded workspace path from the auto-active SubagentStop hook and genericize the two workspace-scanning commands.

**Files:**
- Modify: `canonical/scripts/subagent-stop.sh`
- Modify: `canonical/commands/r-util-proj-cross.md`
- Modify: `canonical/commands/r-util-mem-audit.md`
- Modify: `canonical/reference/framework.md`
- Modify: `tests/derfxn.bats`

(framework.md lines 21/26 are the last 2 workspace-path hits in canonical/ and feed AGENTS.md:73/78 via the agents-md adapter's canonical-section extract.)

- **Goals:** 1
- **Mode**: serial-agent
- **Accept**: `grep -rn '/root/admin/work/proj' canonical/` returns nothing (exit 1); `head -1 canonical/scripts/subagent-stop.sh` = `#!/usr/bin/env bash`; hook exits 0 with HOME unset; `bats tests/derfxn.bats` green.
- **Test**: `tests/derfxn.bats::@test "no rfxn workspace path in canonical, lib, state, bin"`, `::@test "subagent-stop falls back to HOME .rdf without hardcoded path"`, `::@test "subagent-stop exits 0 when HOME unset"` (all appended this phase).
- **Edge cases**: spec 11b "HOME unset" (explicit guard), "cwd has .rdf but no work-output" (second chain step), "read-only HOME" (no `-e`; mkdir/append fail without aborting — script still exits 0, verified against line 8 `set -uo pipefail`).
- **Regression-case**: `tests/derfxn.bats::@test "subagent-stop falls back to HOME .rdf without hardcoded path"` (test appended this phase; file exists from Phase 1)

- [ ] **Step 1: Rewrite subagent-stop.sh shebang and fallback chain**

  Line 1, old→new: `#!/bin/bash` → `#!/usr/bin/env bash`

  Lines 31-43, old:

  ```bash
  # Determine the feed log location.
  # Project-level: .rdf/work-output/agent-feed.log (inside work-output, project-scoped)
  # Workspace-level: .rdf/agent-feed.log (flat, cross-project)
  feed_log=""
  if [[ -d "./.rdf/work-output" ]]; then
      feed_log="./.rdf/work-output/agent-feed.log"
  elif [[ -d "/root/admin/work/proj/.rdf" ]]; then
      feed_log="/root/admin/work/proj/.rdf/agent-feed.log"
  else
      # Create workspace .rdf/ if nothing exists
      command mkdir -p "/root/admin/work/proj/.rdf"
      feed_log="/root/admin/work/proj/.rdf/agent-feed.log"
  fi
  ```

  New:

  ```bash
  # Determine the feed log location.
  # Project-level: .rdf/work-output/agent-feed.log (inside work-output, project-scoped)
  # Workspace-level: ./.rdf/agent-feed.log (flat, when cwd is a workspace root)
  # Fallback: ~/.rdf/agent-feed.log (machine-global; no hardcoded paths)
  feed_log=""
  if [[ -d "./.rdf/work-output" ]]; then
      feed_log="./.rdf/work-output/agent-feed.log"
  elif [[ -d "./.rdf" ]]; then
      feed_log="./.rdf/agent-feed.log"
  else
      [[ -z "${HOME:-}" ]] && exit 0   # hooks must never error; no HOME means nowhere safe to log
      command mkdir -p "${HOME}/.rdf"
      feed_log="${HOME}/.rdf/agent-feed.log"
  fi
  ```

  > Self-correction note: keep `set -uo pipefail` (line 8) — do NOT add `-e`. A read-only HOME must not turn the mkdir failure into a nonzero hook exit.

- [ ] **Step 2: Genericize r-util-proj-cross.md**

  Lines 3-5, old→new: replace `Cross-project analysis for rfxn projects.` with `Cross-project analysis for workspace project sets.` (rest of sentence unchanged).

  Lines 7-20, old (the `## Projects` section through the shared-libraries sentence) → new:

  ```markdown
  ## Projects

  The workspace root is the parent directory of the current project (or
  CWD itself when it is a non-git directory containing project repos).
  Scan all directories under the workspace root that contain a
  `CLAUDE.md` or `.git/` directory.

  Also scan shared-library repos if present (directories whose name ends
  in `_lib` or that a workspace profile's cross-project reference lists).
  ```

  (Deletes the rfxn alias table — the org mapping lives in `profiles/rfxn-workspace/reference/cross-project.md` now.)

- [ ] **Step 3: Genericize r-util-mem-audit.md**

  Line 10, old→new:

  ```
  # old
  - If CWD is `/root/admin/work/proj/`: audit all project MEMORY.md files
  # new
  - If CWD is a workspace root (non-git parent of project repos): audit all project MEMORY.md files
  ```

- [ ] **Step 3b: De-rfxn framework.md's artifact table**

  `canonical/reference/framework.md:21`, old→new:

  ```
  # old
  | Parent CLAUDE.md | `/root/admin/work/proj/CLAUDE.md` | Human |
  # new
  | Parent CLAUDE.md | `<workspace>/CLAUDE.md` | Human |
  ```

  `canonical/reference/framework.md:26`, old→new:

  ```
  # old
  | Shared reference | `/root/admin/work/proj/reference/*.md` | Human |
  # new
  | Shared reference | `<workspace>/reference/*.md` | Human |
  ```

  > Why here: these are the 8th and 9th of the 9 canonical/ workspace-path hits; framework.md ships in Phase 5's reference delivery AND feeds the tracked `adapters/agents-md/output/AGENTS.md` table (regenerated in Phase 8) — without this step, Phase 2's Accept grep and Phase 8's leak guard both fail.

- [ ] **Step 4: Append this phase's 3 tests to `tests/derfxn.bats`**

  ```bash
  @test "no rfxn workspace path in canonical, lib, state, bin" {
      run grep -rn '/root/admin/work/proj' "$RDF_SRC/canonical" "$RDF_SRC/lib" "$RDF_SRC/state" "$RDF_SRC/bin"
      [ "$status" -ne 0 ]
  }

  @test "subagent-stop falls back to HOME .rdf without hardcoded path" {
      local h; h="$(mktemp -d)"
      cd "$FIX"
      run bash -c 'echo "{\"agent_id\":\"t\"}" | HOME="$1" bash "$2/canonical/scripts/subagent-stop.sh"' -- "$h" "$RDF_SRC"
      [ "$status" -eq 0 ]
      grep -q AGENT_STOP "$h/.rdf/agent-feed.log"
      # middle branch (spec 11b): cwd has .rdf/ but no work-output/ → local log, not HOME
      mkdir "$FIX/.rdf"
      run bash -c 'echo "{\"agent_id\":\"t\"}" | HOME="$1" bash "$2/canonical/scripts/subagent-stop.sh"' -- "$h" "$RDF_SRC"
      [ "$status" -eq 0 ]
      grep -q AGENT_STOP "$FIX/.rdf/agent-feed.log"
      rm -rf "$h"
  }

  @test "subagent-stop exits 0 when HOME unset" {
      cd "$FIX"
      run bash -c 'echo "{\"agent_id\":\"t\"}" | env -u HOME bash "$1/canonical/scripts/subagent-stop.sh"' -- "$RDF_SRC"
      [ "$status" -eq 0 ]
  }
  ```

- [ ] **Step 5: Verify**

  ```bash
  grep -rn '/root/admin/work/proj' canonical/; echo "grep_exit=$?"
  # expect: no matches, grep_exit=1
  bash -n canonical/scripts/subagent-stop.sh && shellcheck canonical/scripts/subagent-stop.sh && echo LINT-OK
  # expect: LINT-OK
  bats tests/derfxn.bats 2>&1 | tail -1
  # expect: 0 failures
  ```

- [ ] **Step 6: Commit**

  ```bash
  git add canonical/scripts/subagent-stop.sh canonical/commands/r-util-proj-cross.md canonical/commands/r-util-mem-audit.md tests/derfxn.bats
  git commit -m "De-rfxn canonical: hook fallback to ~/.rdf, generic workspace wording

[Fix] subagent-stop.sh no longer hardcodes /root/admin/work/proj — fallback
      chain is ./.rdf/work-output -> ./.rdf -> ~/.rdf/agent-feed.log with a
      HOME-unset guard; plugin users on other machines stop getting
      permission-denied stderr per subagent stop
[Change] subagent-stop.sh shebang to #!/usr/bin/env bash (shell standard)
[Change] r-util-proj-cross + r-util-mem-audit describe the workspace root
         generically; rfxn project aliases live in the rfxn-workspace profile
[New] derfxn.bats: workspace-path grep guard + subagent-stop fallback and
      HOME-unset tests"
  ```

---

### Phase 3: Node profile + detection branch

Add the `node` profile and close the plain-JS detection gap.

**Files:**
- Create: `profiles/node/governance-template.md`
- Modify: `lib/cmd/init.sh`
- Modify: `profiles/registry.json`
- Modify: `profiles/detection-rules.md`
- Modify: `tests/derfxn.bats`
- Modify: `README.md`
- Modify: `WORKFORCE.md`
- Modify: `docs/index.md`

(README/WORKFORCE/docs-index: doc-stats count reconciliation — Phase 1
changed scripts 17→16 and profiles 11→12; this phase adds node → 13.
Counts stabilize here, restoring `rdf doctor --scope doc-stats` to 0 FAIL
before Phase 5's doctor.bats run. Surfaced by Phase 1's build gate.)

- **Goals:** 8
- **Mode**: serial-agent
- **Accept**: fixture dir with only `package.json`+`index.js` detects `node`; fixture with `tsconfig.json`+`package.json` detects `typescript` only; `_KNOWN_PROFILES` contains `node`; `bats tests/derfxn.bats` green.
- **Test**: `tests/derfxn.bats::@test "plain node fixture detects node profile"` and `::@test "typescript fixture does not add node profile"` (appended this phase).
- **Edge cases**: spec 11b "package.json + tsconfig.json → typescript only" (branch condition), "--type node on TS repo honored" (existing explicit-type precedence, no code change — verified init.sh:776-779 only auto-detects when `--type` empty), ".jsx + package.json, no framework dep → node,frontend" (independent branches).
- **Regression-case**: `tests/derfxn.bats::@test "plain node fixture detects node profile"` (test appended this phase; file exists from Phase 1)

- [ ] **Step 1: Add the detection branch**

  `lib/cmd/init.sh` — insert after the php branch (currently lines 137-141, ends `fi` before `# --- Priority 2`):

  ```bash
      # node: package.json is the sole activation gate — a stray
      # webpack.config.js in a non-JS repo must not activate; suppressed
      # when typescript already matched (TS repos all have package.json)
      if [[ -f "${path}/package.json" ]] \
              && [[ ",${profiles}," != *",typescript,"* ]]; then
          profiles="${profiles:+${profiles},}node"
          has_language=1
      fi
  ```

  > Self-correction note: the branch must come AFTER the typescript branch (line 124-128) for the suppression check to see typescript in `$profiles`. Placing it after php (the last language branch) satisfies this.

- [ ] **Step 2: Register the name**

  `lib/cmd/init.sh:39` (as modified by Phase 1), old→new:

  ```bash
  # old
  _KNOWN_PROFILES="shell python go rust typescript perl php frontend database infrastructure minimal rfxn-workspace"
  # new
  _KNOWN_PROFILES="shell python go rust typescript perl php node frontend database infrastructure minimal rfxn-workspace"
  ```

- [ ] **Step 3: Add the registry entry**

  `profiles/registry.json` — insert after the `"typescript"` entry (comma-correct):

  ```json
  "node": {
    "requires": ["core"],
    "removable": true,
    "tier": "full",
    "detect": ["package.json", "*.js", "*.mjs", "*.cjs"],
    "description": "Node.js (plain JavaScript). Module-system discipline, async patterns, npm hygiene",
    "summary": "governance-template only"
  }
  ```

  > Note: `detect` globs here drive rules paths-scoping frontmatter only (`_cc_paths_frontmatter`); bash detection deliberately gates on package.json alone. Precedent: the frontend profile's registry globs already diverge from its bash logic (registry lists bare `package.json`; bash requires a framework dep).

- [ ] **Step 4: Create `profiles/node/governance-template.md`**

  Full content (sibling template style — `#` title, blockquote preamble, `##` sections, `--` dashes):

  ```markdown
  # Node.js Governance Template

  > Seed template for /r-init. Provides Node.js (plain JavaScript) best
  > practices for merging with codebase scan results. Requires core profile.
  > Assumes Node 18+ LTS baseline (built-in fetch, node:test). For
  > TypeScript projects the typescript profile applies instead.

  ## Code Conventions

  - Declare the module system explicitly: `"type": "module"` (ESM) or
    `"type": "commonjs"` in package.json -- never rely on the default
  - Declare `"engines": { "node": ">=X" }` and enforce it in CI
  - Commit exactly one lockfile (package-lock.json OR pnpm-lock.yaml OR
    yarn.lock) matching the package manager the project documents
  - Use the `node:` prefix for builtin imports (`node:fs`, `node:path`) --
    disambiguates from npm packages and fails fast on typos
  - Prefer builtin capabilities over dependencies: `fetch`, `node:test`,
    `node:util` parseArgs -- every dependency is an attack surface
  - Executable entry points declare `"bin"` in package.json; libraries
    declare `"exports"` -- do not reach into package internals

  ## Anti-Patterns

  - Floating promises -- every promise is awaited, returned, or explicitly
    voided with a comment; unhandled rejections crash Node 15+
  - `process.exit()` in library code -- throw and let the caller decide;
    exit only from the CLI entry point
  - Synchronous fs/crypto calls (`readFileSync`, `pbkdf2Sync`) on request
    paths -- blocks the event loop for every concurrent request
  - `npm install` in CI -- use `npm ci` for lockfile-exact, reproducible
    installs
  - Monkey-patching require/module internals -- breaks under ESM and
    bundlers; use dependency injection
  - Swallowing errors in `.catch(() => {})` -- log or rethrow with context
  - Wildcard or `latest` version ranges in dependencies -- pin or use caret
    ranges with a committed lockfile

  ## Error Handling

  - Fail fast on programmer errors (TypeError, assertion); recover only
    from operational errors (network, fs, user input)
  - Wrap-and-rethrow with `new Error("context", { cause: err })` -- never
    discard the original error
  - One process-level `unhandledRejection` / `uncaughtException` handler:
    log, flush, exit nonzero -- never continue on unknown state
  - Async resource cleanup in `finally` (or `await using` where available)

  ## Testing

  - Tests live in `test/` or `*.test.js` colocated -- one convention per
    repo, documented in package.json scripts
  - `npm test` must run the full suite with a nonzero exit on failure --
    CI calls the script, never the runner directly
  - Prefer `node:test` for zero-dependency projects; jest/vitest acceptable
    when the project already depends on them
  - Every bug fix lands with a regression test in the same commit

  ## Security

  - `npm audit --omit dev` gates release builds; document accepted
    advisories with expiry dates
  - No `postinstall` scripts in first-party packages without justification;
    review transitive postinstall scripts before adding a dependency
  - Never interpolate untrusted input into `child_process.exec` -- use
    `execFile`/`spawn` with argument arrays
  - Secrets come from the environment or a secret store -- never from
    committed .env files
  ```

- [ ] **Step 5: Document detection in detection-rules.md**

  Insert a `### node` section after the existing `### frontend` block (before whatever follows it):

  ```markdown
  ### node

  Activate when ALL of:
  - Config: `package.json` present
  - The typescript profile did NOT activate (no `tsconfig.json`, no real
    `.ts` files) — TS repos are covered by the typescript profile

  Notes:
  - `.js`/`.mjs`/`.cjs` files alone never activate node — a stray
    `webpack.config.js` in a Python repo is not a Node project
  - Registry detect globs include the JS extensions for rules
    paths-scoping only
  ```

- [ ] **Step 5b: Reconcile doc-stats counts (scripts 17→16 from Phase 1; profiles 11→13 after this phase)**

  `README.md:634`, old→new:

  ```
  # old
  **6 agents -- 37 commands -- 17 scripts -- 11 profiles -- 6 adapters -- 7 modes**
  # new
  **6 agents -- 37 commands -- 16 scripts -- 13 profiles -- 6 adapters -- 7 modes**
  ```

  `WORKFORCE.md:253`, old→new:

  ```
  # old
  **Total: 6 agents + 37 commands + 17 scripts = 60 primitives**
  # new
  **Total: 6 agents + 37 commands + 16 scripts = 59 primitives**
  ```

  `docs/index.md:23`, old→new:

  ```
  # old
  **6 agents · 37 commands · 11 profiles · 6 adapters · 7 modes**
  # new
  **6 agents · 37 commands · 13 profiles · 6 adapters · 7 modes**
  ```

- [ ] **Step 6: Append this phase's 2 tests to `tests/derfxn.bats`**

  ```bash
  @test "plain node fixture detects node profile" {
      echo '{}' > "$FIX/package.json"; echo 'x' > "$FIX/index.js"
      run _rdf_call _detect_profiles "$FIX"
      [ "$status" -eq 0 ]
      [ "$output" = "node" ]
      # spec 11b: .jsx + package.json, no framework dep → node,frontend
      local jx; jx="$(mktemp -d)"
      echo '{}' > "$jx/package.json"; echo 'x' > "$jx/app.jsx"
      run _rdf_call _detect_profiles "$jx"
      [ "$status" -eq 0 ]
      [ "$output" = "node,frontend" ]
      rm -rf "$jx"
  }

  @test "typescript fixture does not add node profile" {
      echo '{}' > "$FIX/package.json"; echo '{}' > "$FIX/tsconfig.json"
      run _rdf_call _detect_profiles "$FIX"
      [ "$status" -eq 0 ]
      [ "$output" = "typescript" ]
  }
  ```

- [ ] **Step 7: Verify**

  ```bash
  bash -n lib/cmd/init.sh && shellcheck lib/cmd/init.sh && echo LINT-OK
  # expect: LINT-OK
  jq -e '.profiles.node.requires == ["core"]' profiles/registry.json && echo REG-OK
  # expect: true + REG-OK
  bats tests/derfxn.bats 2>&1 | tail -1
  # expect: all tests ok, exit 0
  ./bin/rdf doctor --scope doc-stats 2>&1 | grep -c FAIL
  # expect: 0 (counts reconciled — was 4 FAIL after Phase 1)
  ```

- [ ] **Step 8: Commit**

  ```bash
  git add profiles/node/governance-template.md profiles/registry.json profiles/detection-rules.md lib/cmd/init.sh tests/derfxn.bats README.md WORKFORCE.md docs/index.md
  git commit -m "Add node profile: plain-JS projects no longer detect as minimal

[New] profiles/node/ governance template (module system, async discipline,
      npm hygiene, security) + registry entry
[New] init.sh detection branch: package.json is the sole gate, suppressed
      when typescript matched; JS globs scope rules only
[Change] detection-rules.md documents the node signals and the deliberate
         template-only asymmetry (simplicity budget)
[Change] doc-stats counts reconciled: 16 scripts (comment-snapshot moved to
         rfxn-workspace profile), 13 profiles (+rfxn-workspace, +node)
[New] derfxn.bats: node detection + typescript suppression tests"
  ```

---

### Phase 4: De-rfxn companion file generation

Stop writing rfxn contact/org/license into strangers' SECURITY.md and CONTRIBUTING.md.

**Files:**
- Modify: `lib/cmd/init.sh`
- Modify: `reference/templates/SECURITY.md`
- Modify: `tests/derfxn.bats`

(init.sh: `_generate_companion_files` lines 486-545; SECURITY.md line 15 `Email:` → `Contact:`.)

- **Goals:** 2
- **Mode**: serial-agent
- **Accept**: init on a fixture repo with no git remote and no repo-LOCAL `user.email` produces SECURITY.md containing `Contact: the maintainers via the repository issue tracker` (NOT the operator's global git identity) and CONTRIBUTING.md containing `under the terms in the LICENSE file`; no `rfxn` or `proj@rfxn.com` in either; `bats tests/derfxn.bats` green.
- **Test**: `tests/derfxn.bats::@test "init companion files carry no rfxn contact when remote absent"` (appended this phase) + inline MIT-detection verify below.
- **Edge cases**: repo with MIT LICENSE → `under the MIT License`; repo with repo-local user.email set → that email as Contact; plain `git config` global fall-through explicitly rejected (would leak the operator's personal email — the `--local` flag is load-bearing).
- **Regression-case**: `tests/derfxn.bats::@test "init companion files carry no rfxn contact when remote absent"` (test appended this phase; file exists from Phase 1)

- [ ] **Step 1: Rewrite the hardcoded values in `_generate_companion_files`**

  `lib/cmd/init.sh` — old lines 493-511 region. Old:

  ```bash
      # Resolve org from git remote (fallback: rfxn)
      local org="rfxn"
  ```

  New:

  ```bash
      # Resolve org from git remote (fallback: project name)
      local org="$name"
  ```

  Old (lines 509-510):

  ```bash
      local contact_email="proj@rfxn.com"
      local license="GNU GPL v2"
  ```

  New:

  ```bash
      # Contact: repo-LOCAL git identity only — plain `git config` falls
      # through to the operator's global user.email, which would leak the
      # machine owner's personal address into the target repo
      local contact_email
      contact_email="$(git -C "$path" config --local user.email 2>/dev/null || echo "")"  # non-git dir (exit 128) / unset key (exit 1) → generic fallback below
      [[ -z "$contact_email" ]] && contact_email="the maintainers via the repository issue tracker"

      # License: detect from LICENSE head; phrase completes "under the {{LICENSE}}."
      local license="terms in the LICENSE file"
      if [[ -f "${path}/LICENSE" ]]; then
          local license_head
          license_head="$(command head -5 "${path}/LICENSE")"
          case "$license_head" in
              *"MIT License"*)                license="MIT License" ;;
              *"Apache License"*)             license="Apache License 2.0" ;;
              *"GNU GENERAL PUBLIC LICENSE"*)
                  case "$license_head" in
                      *"Version 3"*) license="GNU GPL v3" ;;
                      *"Version 2"*) license="GNU GPL v2" ;;
                  esac ;;
          esac
      fi
  ```

- [ ] **Step 2: Adjust the SECURITY.md template contact line**

  `reference/templates/SECURITY.md:15`, old→new:

  ```
  # old
  Email: {{CONTACT_EMAIL}}
  # new
  Contact: {{CONTACT_EMAIL}}
  ```

  (CONTRIBUTING.md template line 34 `under the {{LICENSE}}.` needs no change — both fallback and detected values complete the sentence.)

- [ ] **Step 3: Append this phase's test to `tests/derfxn.bats`**

  ```bash
  @test "init companion files carry no rfxn contact when remote absent" {
      git -C "$FIX" init -q    # no repo-local user.email set — --local read must NOT fall through to the operator's global identity
      touch "$FIX/x.sh"
      run _rdf_call cmd_init "$FIX" --type shell --no-memory
      [ "$status" -eq 0 ]
      run grep -l 'rfxn' "$FIX/SECURITY.md" "$FIX/CONTRIBUTING.md"
      [ "$status" -ne 0 ]
      grep -q 'Contact: the maintainers via the repository issue tracker' "$FIX/SECURITY.md"
      grep -q 'under the terms in the LICENSE file' "$FIX/CONTRIBUTING.md"
  }
  ```

- [ ] **Step 4: Verify**

  ```bash
  bash -n lib/cmd/init.sh && shellcheck lib/cmd/init.sh && echo LINT-OK
  # expect: LINT-OK
  t=$(mktemp -d); git -C "$t" init -q; touch "$t/x.sh"    # no local user.email — --local must not read the global one
  printf 'MIT License\n\nCopyright\n' > "$t/LICENSE"
  bash -c 'RDF_HOME=$PWD; RDF_LIBDIR=$PWD/lib; source lib/rdf_common.sh; rdf_init; source lib/cmd/init.sh; cmd_init "$1" --type shell --no-memory' -- "$t" >/dev/null 2>&1
  grep -c 'under the MIT License' "$t/CONTRIBUTING.md"
  # expect: 1
  bats tests/derfxn.bats 2>&1 | tail -1
  # expect: 0 failures
  ```

- [ ] **Step 5: Commit**

  ```bash
  git add lib/cmd/init.sh reference/templates/SECURITY.md tests/derfxn.bats
  git commit -m "De-rfxn companion files: derive contact/org/license from the repo

[Fix] rdf init no longer writes proj@rfxn.com, org 'rfxn', or a forced GPL
      v2 into generated SECURITY.md/CONTRIBUTING.md — contact from git
      config user.email (generic fallback), org falls back to project name,
      license detected from LICENSE head
[Change] SECURITY.md template line reads 'Contact:' so the non-email
         fallback stays grammatical
[New] derfxn.bats: companion-file de-rfxn test"
  ```

---

### Phase 5: Ship reference/ through adapters + doctor coverage

Emit `canonical/reference/` in claude-code (with sidecars), claude-plugin, and agent-skills outputs; wire reference into both doctor loops and fold in the pre-existing missing `governance` sync target.

**Files:**
- Modify: `adapters/claude-code/adapter.sh`
- Modify: `adapters/claude-plugin/adapter.sh`
- Modify: `adapters/agent-skills/adapter.sh`
- Modify: `lib/cmd/doctor.sh`
- Modify: `adapters/claude-plugin/output/**`
- Modify: `tests/derfxn.bats`

(New `cc_generate_reference` after `cc_generate_scripts` ~line 194 + call/count in `cc_generate_all`; new `cpl_generate_reference` + call; reference copy in `sk_generate_all`; doctor `_check_content_drift` third loop ~line 399 + `_check_sync` list line 469; plugin output regenerated by the verify step.)

- **Goals:** 4
- **Mode**: serial-agent
- **Accept**: after `rdf generate claude-code`: `ls adapters/claude-code/output/reference/*.md | wc -l` = 7 and `*.rdf-hash` = 7; after plugin + agent-skills generation their reference dirs hold 7 docs each; `rdf doctor --scope content-drift` OK; existing `tests/doctor.bats` still green.
- **Test**: `tests/derfxn.bats::@test "cc output ships reference docs with hash sidecars"` and `::@test "plugin and agent-skills outputs ship reference docs"` (appended this phase); `bats tests/doctor.bats tests/adapter.bats tests/plugin-adapter.bats tests/agent-skills.bats` all pass.
- **Edge cases**: spec 11b "doctor false-FAILs if loops extended before regen" — mitigated by running generation inside this phase's verify (outputs regenerate again in Phase 8 for the full set).
- **Regression-case**: `tests/derfxn.bats::@test "cc output ships reference docs with hash sidecars"` (test appended this phase; file exists from Phase 1)

- [ ] **Step 1: Add `cc_generate_reference()` to adapters/claude-code/adapter.sh**

  Insert after `cc_generate_scripts()` (ends line 194):

  ```bash
  # Generate reference docs — commands link ../reference/*.md; ship the
  # target with hash sidecars so doctor covers drift like commands.
  cc_generate_reference() {
      local src_dir="${RDF_CANONICAL}/reference"
      local dst_dir="${_CC_OUTPUT_DIR}/reference"
      local count=0

      command mkdir -p "$dst_dir"

      for src_file in "${src_dir}"/*.md; do
          [[ -f "$src_file" ]] || continue
          local basename_f
          basename_f="$(basename "$src_file")"
          command cp "$src_file" "${dst_dir}/${basename_f}"
          _cc_write_hash_sidecar "$src_file" "${dst_dir}/${basename_f}"
          count=$((count + 1))
      done
      rdf_log "generated ${count} reference docs"
  }
  ```

  In `cc_generate_all()` add `cc_generate_reference` after the `cc_generate_scripts` call (line 301), and extend the summary block (lines 315-321):

  ```bash
  # old
      local agent_count command_count script_count rule_count
  # new
      local agent_count command_count script_count rule_count reference_count
  ```

  after the rule_count line add:

  ```bash
      reference_count="$(find "${_CC_OUTPUT_DIR}/reference" -name '*.md' 2>/dev/null | wc -l)"  # reference/ absent → 0, not an error
  ```

  and old→new final log line:

  ```bash
  # old
      rdf_log "CC generation complete: ${agent_count} agents, ${command_count} commands, ${script_count} scripts, ${rule_count} rules"
  # new
      rdf_log "CC generation complete: ${agent_count} agents, ${command_count} commands, ${script_count} scripts, ${rule_count} rules, ${reference_count} reference docs"
  ```

- [ ] **Step 2: Add `cpl_generate_reference()` to adapters/claude-plugin/adapter.sh**

  Insert after `cpl_generate_scripts()`:

  ```bash
  # Copy reference docs — plugin commands link ../reference/*.md relative
  # to the plugin output root.
  cpl_generate_reference() {
      local src_dir="${RDF_CANONICAL}/reference"
      local dst_dir="${_CPL_OUTPUT_DIR}/reference"
      local count=0

      command mkdir -p "$dst_dir"

      for src_file in "${src_dir}"/*.md; do
          [[ -f "$src_file" ]] || continue
          command cp "$src_file" "${dst_dir}/$(basename "$src_file")"
          count=$((count + 1))
      done
      rdf_log "generated ${count} reference docs"
  }
  ```

  In `cpl_generate_all()` add `cpl_generate_reference` after `cpl_generate_scripts` (line 261).

- [ ] **Step 3: Emit reference in agent-skills output**

  `adapters/agent-skills/adapter.sh`, in `sk_generate_all()` after `sk_emit_skills "${_output_new}/.agents/skills"`:

  ```bash
      # SKILL.md bodies link ../reference/*.md — resolve from skills root
      command mkdir -p "${_output_new}/.agents/skills/reference"
      command cp "${RDF_CANONICAL}/reference/"*.md "${_output_new}/.agents/skills/reference/"
  ```

- [ ] **Step 4: Extend doctor `_check_content_drift` and `_check_sync`**

  `lib/cmd/doctor.sh` — after the commands loop in `_check_content_drift` (closes ~line 399, before the `missing_sidecar_count` summary block), add a third loop (copy of the commands loop shape):

  ```bash
      # Check reference docs: plain files, same sidecar contract as commands
      for dst_file in "${output_dir}/reference"/*.md; do
          [[ -f "$dst_file" ]] || continue
          basename_f="$(basename "$dst_file")"
          sidecar="${dst_file}.rdf-hash"

          if [[ ! -f "$sidecar" ]]; then
              missing_sidecar_count=$((missing_sidecar_count + 1))
              continue
          fi

          local stored_hash actual_hash
          stored_hash="$(< "$sidecar")"
          actual_hash="$(_hash_deployed_body "$dst_file")"

          if [[ "$stored_hash" != "$actual_hash" ]]; then
              _add_result "content-drift" "$_FAIL" \
                  "deployed file modified since last generate: reference/${basename_f}"
              drift_count=$((drift_count + 1))
          fi
          checked_count=$((checked_count + 1))
      done
  ```

  `lib/cmd/doctor.sh:469`, old→new:

  ```bash
  # old
      for target in commands agents scripts; do
  # new (governance was a pre-existing gap — folded in while editing)
      for target in commands agents scripts governance reference; do
  ```

- [ ] **Step 5: Append this phase's 2 tests to `tests/derfxn.bats`**

  ```bash
  @test "cc output ships reference docs with hash sidecars" {
      # cc + agent-skills outputs are gitignored build artifacts (absent on
      # a CI checkout) — skip unless generated locally; the plugin test
      # below covers CI (plugin output IS committed)
      [ -d "$RDF_SRC/adapters/claude-code/output" ] || skip "no generated cc output"
      [ "$(ls "$RDF_SRC"/adapters/claude-code/output/reference/*.md | wc -l)" -eq 7 ]
      [ "$(ls "$RDF_SRC"/adapters/claude-code/output/reference/*.rdf-hash | wc -l)" -eq 7 ]
  }

  @test "plugin and agent-skills outputs ship reference docs" {
      [ "$(ls "$RDF_SRC"/adapters/claude-plugin/output/reference/*.md | wc -l)" -eq 7 ]
      if [ -d "$RDF_SRC/adapters/agent-skills/output" ]; then
          [ "$(ls "$RDF_SRC"/adapters/agent-skills/output/.agents/skills/reference/*.md | wc -l)" -eq 7 ]
      fi
  }
  ```

  > Self-correction note: exactly two output trees are git-tracked — `adapters/claude-plugin/output/` and `adapters/agents-md/output/` (verified: `git ls-files`; `.gitignore:29-33` + `.git/info/exclude` cover claude-code/gemini-cli/codex/agent-skills outputs). Plugin assertions run everywhere; cc/agent-skills assertions only where generated. agents-md is handled in Phase 8 (regeneration inherits Phase 2's framework.md fix).

- [ ] **Step 6: Verify**

  ```bash
  bash -n adapters/claude-code/adapter.sh adapters/claude-plugin/adapter.sh adapters/agent-skills/adapter.sh lib/cmd/doctor.sh && echo SYNTAX-OK
  # expect: SYNTAX-OK
  shellcheck adapters/claude-code/adapter.sh adapters/claude-plugin/adapter.sh adapters/agent-skills/adapter.sh lib/cmd/doctor.sh; echo "sc=$?"
  # expect: sc=0
  ./bin/rdf generate claude-code 2>&1 | tail -1
  # expect: "... 7 reference docs" in the completion line
  ls adapters/claude-code/output/reference/*.md | wc -l; ls adapters/claude-code/output/reference/*.rdf-hash | wc -l
  # expect: 7 then 7
  ./bin/rdf generate claude-plugin >/dev/null 2>&1; ls adapters/claude-plugin/output/reference/*.md | wc -l
  # expect: 7
  ./bin/rdf generate agent-skills >/dev/null 2>&1; ls adapters/agent-skills/output/.agents/skills/reference/*.md | wc -l
  # expect: 7
  ./bin/rdf doctor --scope content-drift 2>&1 | grep -c FAIL
  # expect: 0
  bats tests/doctor.bats tests/adapter.bats tests/plugin-adapter.bats tests/agent-skills.bats tests/derfxn.bats 2>&1 | tail -2
  # expect: all tests pass, 0 failures
  ```

- [ ] **Step 7: Commit** (adapter sources + the regenerated plugin output — the only tracked output tree; cc/agent-skills outputs are gitignored local artifacts)

  ```bash
  git add adapters/claude-code/adapter.sh adapters/claude-plugin/adapter.sh adapters/agent-skills/adapter.sh lib/cmd/doctor.sh adapters/claude-plugin/output tests/derfxn.bats
  git commit -m "Ship canonical/reference/ in CC-family adapter outputs

[New] cc_generate_reference (hash sidecars) + cpl_generate_reference +
      agent-skills reference emit — 24 ../reference/*.md links in deployed
      commands/skills now resolve; tiers and plan-schema no longer silently
      absent from installs
[New] doctor: content-drift third loop for reference/*.md sidecars; sync
      completeness loop gains reference and the pre-existing missing
      governance target
[New] derfxn.bats: reference-delivery tests (cc sidecars, plugin + skills)"
  ```

---

### Phase 6: Deploy truthfulness

Reference symlink, exit 1 on skips, and a real hooks-merge how-to in the usage text.

**Files:**
- Modify: `lib/cmd/deploy.sh`
- Modify: `tests/deploy.bats`

(deploy.sh: symlink line, summary return, usage block; deploy.bats: `_make_deploy_skeleton` += reference, 3 new tests.)

- **Goals:** 5, 6
- **Mode**: serial-agent
- **Accept**: clean deploy to fresh target exits 0; deploy with a pre-existing real dir exits 1; `~claude`-target gains a `reference` symlink; `cmd_deploy help` output contains the jq merge one-liner; full `tests/deploy.bats` green.
- **Test**: `bats tests/deploy.bats` — existing 11 + 3 new = 14 tests pass.
- **Edge cases**: spec 11b "only reference conflicts → others deploy, exit 1" (per-item accounting, covered by skip test), "dry-run against conflicted target → exit 1" (same accounting; assert in new exit-code test), "hooks.json always-skipped is log-only and never trips exit 1" (it bypasses `_DEPLOY_SKIPPED` — verified deploy.sh:237-238).
- **Regression-case**: `tests/deploy.bats::@test "deploy exit codes: clean deploy 0, skipped items 1"`

- [ ] **Step 1: Update the test skeleton FIRST (RC contract: missing source dir would make every deploy exit 1)**

  `tests/deploy.bats` `_make_deploy_skeleton` (lines 20-27), old→new:

  ```bash
  # old
      mkdir -p "${out}/agents" "${out}/commands" "${out}/scripts" \
               "${out}/governance" "${out}/rules"
  # new
      mkdir -p "${out}/agents" "${out}/commands" "${out}/scripts" \
               "${out}/governance" "${out}/rules" "${out}/reference"
  ```

- [ ] **Step 2: Deploy reference + return 1 on skips + usage how-to**

  `lib/cmd/deploy.sh` — after the governance symlink (line 228) add:

  ```bash
      _deploy_symlink "${output_dir}/reference" "${dest_base}/reference" "$dry_run" "$force"
  ```

  Summary block (lines 361-365), old→new:

  ```bash
  # old
      if [[ $_DEPLOY_SKIPPED -gt 0 ]]; then
          rdf_warn "deploy complete: ${_DEPLOY_OK} deployed, ${_DEPLOY_SKIPPED} skipped (use --force to override)"
      else
          rdf_log "deploy complete: ${_DEPLOY_OK} items deployed"
      fi
  # new
      if [[ $_DEPLOY_SKIPPED -gt 0 ]]; then
          rdf_warn "deploy complete: ${_DEPLOY_OK} deployed, ${_DEPLOY_SKIPPED} skipped (use --force to override)"
          return 1
      fi
      rdf_log "deploy complete: ${_DEPLOY_OK} items deployed"
  ```

  Usage heredoc — after the `Options:` block (line 24) and before the `Symlinked directories...` paragraph, insert:

  ```
  Hooks merge (claude-code symlink deploy only; plugin installs auto-register):
    hooks.json is never symlinked. Merge it into ~/.claude/settings.json:
      jq -s '.[0] * .[1]' ~/.claude/settings.json adapters/claude-code/hooks/hooks.json > /tmp/settings.merged && cp /tmp/settings.merged ~/.claude/settings.json
    Review the result: '*' merges objects recursively but REPLACES arrays —
    if you already define hooks for the same event, merge those manually.

  Exit status: 0 all items deployed; 1 if any item was skipped.
  ```

  > Self-correction note: the one-liner writes to /tmp then `cp` (not `mv`, and never `> settings.json` directly — jq reading and shell truncating the same file would empty it). This is display text inside a quoted heredoc; bash -n/shellcheck do not parse it, but keep the coreutils bare here intentionally: it is user-facing copy-paste for THEIR shell, and the heredoc is exempt from the source-code coreutils rule (matches the existing usage text style).

- [ ] **Step 3: Update existing skip-case assertions and add 3 tests**

  Verified current state: the existing test `"deploy claude-code symlink create/replace/skip/force"` has NO status assertion on its skip/force legs (only leg 1 asserts `-eq 0`), so it passes unchanged after the `return 1` change — no edits to existing tests are required unless the full-file read below reveals another test asserting deploy success after a skip. Read all 11 existing `@test` blocks once to confirm, then add the 3 new tests. (BATS `run` captures nonzero status without aborting, even with `set -euo pipefail` inside `_run_deploy`'s `bash -c`, because `cmd_deploy` is the terminal statement.)

  Append three tests (harness per existing file conventions — bare coreutils are correct in .bats):

  ```bash
  @test "deploy exit codes: clean deploy 0, skipped items 1" {
      run _run_deploy "$FIX_HOME" claude-code
      [ "$status" -eq 0 ]
      rm -rf "${FIX_HOME}/.claude"
      mkdir -p "${FIX_HOME}/.claude/commands"     # real dir → skip
      run _run_deploy "$FIX_HOME" claude-code
      [ "$status" -eq 1 ]
      [[ "$output" == *"skipped"* ]]
      run _run_deploy "$FIX_HOME" --dry-run claude-code   # dry-run predicts the same skip
      [ "$status" -eq 1 ]
      # spec 11b: ONLY reference conflicts → other items deploy, still exit 1
      rm -rf "${FIX_HOME}/.claude"
      mkdir -p "${FIX_HOME}/.claude/reference"
      run _run_deploy "$FIX_HOME" claude-code
      [ "$status" -eq 1 ]
      [ -L "${FIX_HOME}/.claude/commands" ]
  }

  @test "deploy claude-code symlinks reference into target" {
      run _run_deploy "$FIX_HOME" claude-code
      [ "$status" -eq 0 ]
      [ -L "${FIX_HOME}/.claude/reference" ]
  }

  @test "deploy help documents the hooks.json merge" {
      run _run_deploy "$FIX_HOME" help
      [ "$status" -eq 0 ]
      [[ "$output" == *"jq -s"* ]]
      [[ "$output" == *"Exit status"* ]]
  }
  ```

  > Self-correction note: `_run_deploy ... help` hits the `help|--help|-h` case arm before target validation (deploy.sh:326) — no target needed; the helper appends claude-code only when no known target token is present, and `help` is not a target token, so the call becomes `cmd_deploy help claude-code`. Check the case ordering: `help` matches first and returns usage before the extra token is parsed — if it does not, use `bash -c 'source ...; cmd_deploy help'` directly instead.

- [ ] **Step 4: Verify**

  ```bash
  bash -n lib/cmd/deploy.sh && shellcheck lib/cmd/deploy.sh && echo LINT-OK
  # expect: LINT-OK
  bats tests/deploy.bats 2>&1 | tail -2
  # expect: 0 failures (existing tests with updated skip-status assertions + the 3 new tests)
  t=$(mktemp -d); RDF_TARGET="$t" ./bin/rdf deploy claude-code >/dev/null 2>&1; echo "clean=$?"; [ -L "$t/reference" ] && echo REF-LINK
  # expect: clean=0, REF-LINK
  t=$(mktemp -d); mkdir -p "$t/commands"; RDF_TARGET="$t" ./bin/rdf deploy claude-code >/dev/null 2>&1; echo "skip=$?"
  # expect: skip=1
  ./bin/rdf deploy help | grep -c 'jq -s'
  # expect: 1
  ```

- [ ] **Step 5: Commit**

  ```bash
  git add lib/cmd/deploy.sh tests/deploy.bats
  git commit -m "Deploy truthfulness: exit 1 on skips, reference symlink, hooks how-to

[Change] rdf deploy exits 1 when any item is skipped — an established
         ~/.claude no longer produces a silent half-install with exit 0;
         exit contract documented in usage
[New] deploy claude-code symlinks output/reference -> ~/.claude/reference
[Fix] 'see rdf deploy help' for the hooks.json merge now resolves — usage
      contains the jq merge one-liner and the array-replacement caveat
[New] deploy.bats: exit-code matrix, reference symlink, help how-to tests"
  ```

---

### Phase 7: Doc falsehood sweep

Make README/quickstart/memory-context claims true.

**Files:**
- Modify: `README.md`
- Modify: `docs/quickstart.md`
- Modify: `docs/memory-context.md`
- Modify: `CLAUDE.md`
- Modify: `tests/derfxn.bats`

(README lines 61-64/92-95/232/603; quickstart lines 8/109/111; memory-context line 66; CLAUDE.md line 27 — tracked in the RDF repo, verified `git ls-files`.)

- **Goals:** 7
- **Mode**: serial-agent
- **Accept**: `grep -n -- '--tools' README.md` empty; no `/r-init` line inside a ```bash fence in README; `grep -n '4\.1' docs/quickstart.md` empty; no relative `../` or `specs/` links in the two Pages docs; `bats tests/derfxn.bats` green.
- **Test**: `tests/derfxn.bats::@test "README and quickstart claims are truthful"` (appended this phase) + grep verifications below.
- **Edge cases**: none (docs + one guard test).
- **Regression-case**: `tests/derfxn.bats::@test "README and quickstart claims are truthful"` (test appended this phase; file exists from Phase 1)

- [ ] **Step 1: README — `/r-init` out of bash fences**

  Lines 61-64, old:

  ````
  # 4. Initialize a project with governance
  cd /path/to/your/project
  /r-init                               # auto-detects project type, suggests profiles
  ```
  ````

  New (close the bash fence after the cd, move the slash command to prose):

  ````
  # 4. Go to your project
  cd /path/to/your/project
  ```

  Then, inside your agent session (Claude Code prompt, not the shell), run
  `/r-init` — it auto-detects the project type and suggests profiles.
  ````

  Lines 92-95, old:

  ````
  ```bash
  cd /path/to/project
  /r-init                               # auto-detects profiles, generates governance
  ```
  ````

  New:

  ````
  ```bash
  cd /path/to/project
  ```

  Then, from your agent session: `/r-init` — auto-detects profiles and
  generates governance.
  ````

- [ ] **Step 2: README — drop `--tools`**

  Line 232, old→new:

  ```
  # old
  | `rdf init <path> [--type] [--tools] [--github]` | Project initialization with governance templates |
  # new
  | `rdf init <path> [--type] [--github]` | Project initialization with governance templates |
  ```

  Line 603, old→new:

  ```bash
  # old
  rdf init /path/to/project --type shell --tools claude-code --github
  # new
  rdf init /path/to/project --type shell --github
  ```

- [ ] **Step 3: quickstart + memory-context fixes**

  `docs/quickstart.md:8`, old→new:

  ```
  # old
  No rfxn context required. You need `git`, `bash` 4.1+, `jq`, and an AI
  # new
  No rfxn context required. You need `git`, `bash` 3.2+ (macOS system bash
  works — CI-verified), `jq`, and an AI
  ```

  `docs/quickstart.md:109`, old→new:

  ```
  # old
  - [README — full command reference](../README.md#4-usage)
  # new
  - [README — full command reference](https://github.com/rfxn/rdf#4-usage)
  ```

  `docs/quickstart.md:111`, old→new:

  ```
  # old
  - [ROADMAP](../ROADMAP.md)
  # new
  - [ROADMAP](https://github.com/rfxn/rdf/blob/main/ROADMAP.md)
  ```

  `docs/memory-context.md:66`, old→new:

  ```
  # old
  - Design spec: [`docs/specs/2026-07-15-memory-context-design.md`](specs/2026-07-15-memory-context-design.md)
  # new
  - Design spec: [`docs/specs/2026-07-15-memory-context-design.md`](https://github.com/rfxn/rdf/blob/main/docs/specs/2026-07-15-memory-context-design.md)
  ```

- [ ] **Step 3b: Reconcile the RDF CLAUDE.md bash-floor line**

  `CLAUDE.md:27` (RDF project CLAUDE.md, Shell Standards bullet), old→new:

  ```
  # old
  - Bash 4.1+ floor (CentOS 6 compatibility)
  # new
  - Bash floor: target 3.2 (macOS system bash — CI-smoked) and 4.1 (CentOS 6); avoid features newer than either (matches CONTRIBUTING.md)
  ```

- [ ] **Step 4: Append this phase's test to `tests/derfxn.bats`**

  ```bash
  @test "README and quickstart claims are truthful" {
      run grep -- '--tools' "$RDF_SRC/README.md"
      [ "$status" -ne 0 ]
      run grep '4\.1' "$RDF_SRC/docs/quickstart.md"
      [ "$status" -ne 0 ]
      run bash -c 'awk "/^\`\`\`bash/,/^\`\`\`$/" "$1/README.md" | grep "/r-init"' -- "$RDF_SRC"
      [ "$status" -ne 0 ]
  }
  ```

- [ ] **Step 5: Verify**

  ```bash
  grep -n -- '--tools' README.md; echo "tools=$?"
  # expect: tools=1 (no matches)
  awk '/^```bash/,/^```$/' README.md | grep -c '/r-init'
  # expect: 0
  grep -n '4\.1' docs/quickstart.md; echo "floor=$?"
  # expect: floor=1
  grep -n '](\.\./' docs/quickstart.md docs/memory-context.md; echo "rel=$?"
  # expect: rel=1
  grep -n '](specs/' docs/memory-context.md; echo "specs=$?"
  # expect: specs=1
  bats tests/derfxn.bats 2>&1 | tail -1
  # expect: 0 failures
  ```

- [ ] **Step 6: Commit**

  ```bash
  git add README.md docs/quickstart.md docs/memory-context.md CLAUDE.md tests/derfxn.bats
  git commit -m "Doc truth sweep: --tools, /r-init fences, bash floor, Pages links

[Fix] README no longer advertises unimplemented 'rdf init --tools'
[Fix] /r-init moved out of bash fences — it is an agent slash command, not
      a shell command
[Fix] quickstart states the real bash 3.2+ floor (was 4.1+ — told macOS
      users they don't qualify while CI smokes system bash 3.2)
[Fix] Pages links: quickstart README/ROADMAP and memory-context spec links
      now absolute GitHub URLs (../ and specs/ were 404 on Pages)
[Change] CLAUDE.md bash-floor bullet reconciled with CONTRIBUTING/CI
         (target 3.2 macOS + 4.1 CentOS 6)
[New] derfxn.bats: doc-truth guard test"
  ```

---

### Phase 8: Regenerate all, final leak guard, changelog consolidation

Regenerate every adapter (drops comment-snapshot.sh from stale outputs, refreshes command bodies changed in Phase 2), add the final output-leak guard test, run the full suite + doctor, consolidate changelogs.

**Files:**
- Modify: `tests/derfxn.bats`
- Modify: `adapters/claude-plugin/output/**`
- Modify: `adapters/agents-md/output/AGENTS.md`
- Modify: `CHANGELOG`
- Modify: `CHANGELOG.RELEASE`

(derfxn.bats gains the 12th and final test; `rdf generate all` regenerates every output tree but only the two tracked ones are staged — agents-md's AGENTS.md workspace-path rows fix themselves via Phase 2's framework.md change; untracked trees regenerate locally.)

- **Goals:** 1, 9
- **Mode**: serial-agent
- **Accept**: `rdf generate all` clean; `grep -rn '/root/admin/work/proj' canonical/ lib/ state/ bin/ adapters/claude-code/output adapters/claude-plugin/output adapters/agent-skills/output` empty; `bats tests/` full suite green; `rdf doctor --all` zero FAILs; both changelogs updated.
- **Test**: `tests/derfxn.bats::@test "generated CC-family outputs contain no rfxn workspace path"` (appended this phase) + full suite run.
- **Edge cases**: spec 11b "stale consumer cross-project.md copies remain — untouched" (documented in CHANGELOG migration note, no deletion code); rfxn-machine migration note (`rdf profile install rfxn-workspace`).
- **Regression-case**: `tests/derfxn.bats::@test "generated CC-family outputs contain no rfxn workspace path"` (test appended this phase; file exists from Phase 1)

- [ ] **Step 1: Append the final test to `tests/derfxn.bats`**

  ```bash
  @test "generated CC-family outputs contain no rfxn workspace path" {
      # plugin + agents-md outputs are always present (committed); the
      # others only when generated locally — grep whichever exist
      local dirs=("$RDF_SRC/adapters/claude-plugin/output" "$RDF_SRC/adapters/agents-md/output")
      [ -d "$RDF_SRC/adapters/claude-code/output" ] && dirs+=("$RDF_SRC/adapters/claude-code/output")
      [ -d "$RDF_SRC/adapters/agent-skills/output" ] && dirs+=("$RDF_SRC/adapters/agent-skills/output")
      run grep -rn '/root/admin/work/proj' "${dirs[@]}"
      [ "$status" -ne 0 ]
  }
  ```

- [ ] **Step 2: Regenerate all adapters and verify the tree**

  ```bash
  ./bin/rdf generate all 2>&1 | tail -3
  # expect: "all adapters generated successfully"
  grep -rn '/root/admin/work/proj' canonical/ lib/ state/ bin/ adapters/claude-code/output adapters/claude-plugin/output adapters/agent-skills/output adapters/codex/output adapters/agents-md/output; echo "leak=$?"
  # expect: leak=1 (agents-md/output/AGENTS.md inherits Phase 2's framework.md fix via regeneration)
  find adapters -path '*/output/*' -name 'comment-snapshot.sh' | grep -v gemini; echo "snap=$?"
  # expect: snap=1 (gemini output is frozen legacy — regenerated only if 'generate all' rebuilt it; if rebuilt, drop the grep -v)
  ```

  > Self-correction note: `rdf generate all` DOES regenerate gemini-cli (generate.sh:148-151) — so comment-snapshot.sh disappears from gemini output too; expect the plain `find ... -name comment-snapshot.sh` under output dirs to return nothing. Verify with: `find adapters -path '*/output/*' -name 'comment-snapshot.sh' | wc -l` → 0.

- [ ] **Step 3: Full suite + doctor**

  ```bash
  bats tests/ 2>&1 | tee /tmp/test-rdf-P8-full.log | tail -3
  # expect: 0 failures
  ./bin/rdf doctor --all 2>&1 | grep -c FAIL
  # expect: 0
  ./bin/rdf deploy claude-code; echo "deploy=$?"
  # expect: deploy=0 (dev machine symlink farm; delivers ~/.claude/reference)
  ```

- [ ] **Step 4: Consolidated changelog entries**

  Add a `## 3.6.5` section to `CHANGELOG` (style per 3.6.4 — `-- New Features --` / `-- Bug Fixes --` / `-- Changes --`, entries stacked, wrapped ~80c):

  ```
  ## 3.6.5

  -- New Features --

  [New] rfxn-workspace profile — opt-in org overlay (detect: []) housing
        cross-project.md and comment-snapshot.sh; core stays generic
  [New] node profile: plain package.json projects no longer detect as
        minimal (package.json sole gate; suppressed when typescript matches)
  [New] canonical/reference/ ships in claude-code (hash sidecars), plugin,
        and agent-skills outputs; deploy symlinks ~/.claude/reference —
        24 ../reference/*.md links now resolve in installs
  [New] doctor: content-drift covers reference/*.md; sync completeness loop
        gains reference + governance
  [New] tests/derfxn.bats de-rfxn regression suite; deploy.bats exit-code
        and reference-symlink tests

  -- Bug Fixes --

  [Fix] subagent-stop.sh hardcoded /root/admin/work/proj fallback removed —
        plugin users on other machines no longer get permission-denied
        stderr per subagent stop; fallback is ./.rdf -> ~/.rdf
  [Fix] rdf init no longer writes rfxn artifacts into consumer repos:
        cross-project.md (APF/BFD/LMD tables), proj@rfxn.com contact,
        forced rfxn org and GPL v2 in SECURITY.md/CONTRIBUTING.md
  [Fix] doc truth: README --tools advertisement removed, /r-init out of
        bash fences, quickstart bash floor 3.2+ (was 4.1+), Pages links
        absolute (README/ROADMAP/spec links were 404 on Pages)
  [Fix] rdf deploy help now contains the hooks.json jq-merge how-to it
        points to

  -- Changes --

  [Change] rdf deploy exits 1 when any item is skipped — established
           ~/.claude setups get a loud partial-deploy signal instead of a
           silent exit-0 half-install
  [Change] rfxn machines: run 'rdf profile install rfxn-workspace' once to
           re-activate org governance after upgrade; stale
           .rdf/governance/reference/cross-project.md copies in initialized
           repos are harmless and refresh out via /r-refresh
  ```

  Mirror a condensed version into `CHANGELOG.RELEASE` (match its existing per-release format — read its head first).

- [ ] **Step 5: Commit**

  ```bash
  git add tests/derfxn.bats adapters/claude-plugin/output adapters/agents-md/output CHANGELOG CHANGELOG.RELEASE
  # (claude-plugin/output and agents-md/output are the two tracked output
  # trees; the rest are gitignored local artifacts — never staged.
  # If `git status --porcelain` shows nothing for claude-plugin/output,
  # Phase 5 already committed the final plugin output — fine.)
  git commit -m "Regenerate adapters, final leak guard, 3.6.5 changelog

[New] derfxn.bats: generated-output leak guard (final test of the suite)
[Change] all adapter outputs regenerated: comment-snapshot.sh dropped,
         reference/ shipped, subagent-stop fallback + command wording
         updates propagated
[Change] CHANGELOG + CHANGELOG.RELEASE consolidated for 3.6.5 (declared
         exception: phases 1-7 deferred changelog to this commit)"
  ```

---
