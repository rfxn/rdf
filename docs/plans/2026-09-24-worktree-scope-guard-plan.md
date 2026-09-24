# Implementation Plan: Phase-Branch Scope Guard for Consumer Projects (I-2)

**Goal:** Make `/r-build`'s pre-commit scope guard work in every project, not just RDF's own
checkout. An out-of-scope commit on an `rdf/phase-*` branch should be rejected, while the project's
own hooks keep running.

**Architecture:**
- `rdf_phase_hook_install` (in `state/rdf-bus.sh`) adds `[includeIf "onbranch:rdf/phase-**"] path =
  rdf-hooks.inc` to the repo config. That include points `core.hooksPath` at `.git/rdf-hooks/`, and
  a static passthrough in that directory chains the project's own hooks.
- The hook finds its helpers at `<top>/state` when self-hosting and at `~/.rdf/state` otherwise.
  It takes the session id from the branch name and falls back to the main worktree's plan pointer.
- Anti-pattern classes scan shell files only, and are opt-in outside RDF.
- `/r-build` and the dispatcher replace their two broken `cp` snippets with one helper call.

**Tech Stack:** bash 3.2/4.1 floor, git >= 2.23 (`includeIf onbranch`), BATS (system bats),
shellcheck

**Spec:** docs/specs/2026-09-24-worktree-scope-guard-design.md

**Phases:** 3

**Plan Version:** 3.0.6

**Tier:** full

## How this plan delivers code

Every line of code in this plan was implemented and validated in a scratch clone at `8cce78d`
before the plan was written. Validation evidence:

| Check | Result |
|-------|--------|
| `make -C tests test` | 0 `not ok`; runs `1..443` (423 existing + 19 in `tests/worktree-hook.bats` + 1 in `tests/pre-commit-anti-patterns.bats`; each suite registered once per Makefile target) |
| CI lint set (error severity, including `state/git-hooks/pre-commit`) and `tests/*.bats` | rc 0 |
| Default-severity shellcheck on the 3 new/changed shell files | rc 0 |
| `rdf doctor` | 0 FAIL |
| `claude plugin validate --strict` (repo + skills tree) | passed |
| Real **bash 3.2.57** (`bash:3.2` Docker image, git 2.49.1) | consumer install, out-of-scope rejection, in-scope commit, opt-in anti-pattern and double uninstall all passed; the new CI smoke block passed under both bash 5 and 3.2 |
| Replay | the four patches applied in sequence to a fresh clone of `8cce78d` reproduced the scratch tree byte-for-byte, including the regenerated plugin output |
| Plan challenge review, round 1 | 2 MUST-FIX and 1 SHOULD-FIX, all resolved in this revision: Makefile double registration, unmapped edge cases, legacy-pointer precedence |

The exact changes sit next to this plan:

```
docs/plans/2026-09-24-worktree-scope-guard-patches/
  p1-tests.patch  p1-code.patch  p2-code.patch  p3-code.patch
```

Phase 1 runs red→green: apply the tests patch, watch the named tests fail, apply the code patch,
and watch them pass. Phases 2 and 3 are prose, docs and CI; existing tests plus grep checks guard
them. Apply patches in phase order.

> Self-correction notes carried from validation (do not re-discover):
> - **`git worktree add` fires `post-checkout`.** On a phase branch it goes through the
>   passthrough, so the N1 recursion test clears its marker file after creating the worktree.
>   The code was right; the first test draft counted two post-checkouts.
> - **Spec `_rdf_install_exec src dest` is realized as `_rdf_atomic_write dest mode < stdin`.** One
>   helper atomically writes the hook copy, the passthrough, the passthrough-named copies, and
>   `.rdf-main-root`. The temp file lives in the target dir (`mktemp` + `chmod <mode>` + `mv -f`),
>   so hooks are 0755, not 0711 (round-3 R2).
> - **`_rdf_pass` uses `export RDF_HOOK_NAME=pre-commit` then `exec`**, not a prefix assignment on
>   `exec`. The passthrough unsets it right after reading it (spec N1).
> - **Every `worktree-hook.bats` repo lives under `…/café/app`.** Reassigning `REPO` inside one test
>   tripped SC2030/SC2031, and a non-ASCII path in every test covers the `-z` origin-quoting case
>   (round-3 R1) everywhere.
> - **The CI smoke passes the repo path as `$1` to `/bin/bash -c` (round-3 R3)** and runs the commit
>   with `PATH=/bin:/usr/bin:$PATH`, so `#!/usr/bin/env bash` resolves to macOS system bash 3.2.
> - **Every existing hook suite passes unmodified.** `tests/rdf-bus.bats` and
>   `tests/pre-commit-anti-patterns.bats` build the self-host layout (in-tree `state/rdf-bus.sh`,
>   hook in `.git/hooks`). No `.rdf-passthrough` exists there, so `_rdf_pass` exits 0 as before.
> - **The Makefile registers the suite once per target.** The first patch draft added it twice to
>   `test` and never to `lint`, and a whole-file `grep -c` = 2 hid it. The Accept checks now use
>   `make -n` per target and assert the `1..443` plan line.
> - **Session-scoped pointers are checked in both roots before any legacy fallback**
>   (`_rdf_session_plan`). Otherwise a stale committed `PLAN.md` in the worktree would shadow the
>   main root's session pointer and reject in-scope commits. The regression test is "main-root
>   session pointer outranks a stale committed PLAN.md in the worktree"; it was verified to fail
>   against the pre-fix hook.
> - `cp` is aliased to `cp -i` on the dev host. Use `/usr/bin/cp` in Bash tool calls; the patches
>   handle every file write anyway.

## Conventions

**Boilerplate:** shell files keep their existing headers. The new BATS suite carries
`# tests/<file> — <purpose>` / `# (C) 2026 R-fx Networks <proj@rfxn.com>` / `# GNU GPL v2`.

**Naming:**
- `rdf_*` public bus helpers; `_rdf_*` private bus helpers.
- `_ap_*` hook anti-pattern internals.
- Hook stderr prefix is `rdf pre-commit:`; installer stderr prefix is `rdf_phase_hook_install:`.

**Commit message format:** free-form subject. Every body line is tagged `[New]` `[Change]` `[Fix]`
`[Remove]`. No Co-Authored-By or AI attribution. Stage files explicitly by name: never
`git add -A` / `git add .`.

**CRITICAL:**
- **Canonical changes regenerate output.** Phase 2 must run `bin/rdf generate claude-code` and
  `bin/rdf generate claude-plugin`, and commit the regenerated `adapters/claude-plugin/output/**`
  files in the same commit (CI drift gate: `git diff --exit-code adapters/claude-plugin/output
  .claude-plugin/plugin.json`). `plugin.json` is unchanged by this plan.
- **Changelog lands once.** `CHANGELOG` gains an `## Unreleased` section, and `CHANGELOG.RELEASE`
  becomes `# RDF Unreleased Release Notes`, in Phase 3 only. This follows the 3.8.0 precedent at
  `88e175a`; the version is assigned at ship.
- **Shell floor and suppressions:** bash 3.2/4.1, so no `mapfile`, `local -A`, `${v,,}` or
  `declare -n`. Every new `2>/dev/null` / `|| true` carries a same-line justification (already
  true in the patches).
- **Bus stays sourceable.** `state/rdf-bus.sh` is sourced into agent shells: `return` only, never
  `set`/`exit`.

## RC Contract Evidence

| Helper | Contract | Callers and how they treat rc |
|--------|----------|--------------------------------|
| `rdf_phase_hook_install [dir [hook_src]]` | 0 installed/refreshed (from the main worktree or a linked worktree whose common dir is `.git`); 1 outside any worktree, bare, a linked worktree whose common dir is not `.git`, or no hook source; 2 git < 2.23 | `r-build.md` and `dispatcher.md` step (b): any non-zero prints a warning and falls back to the post-merge scope check (layer 2). `worktree-hook.bats` asserts 0 (install tests) and 2 (old-git shim) |
| `rdf_phase_hook_uninstall [dir]` | 0 (repeat calls are no-ops); 1 not a repo | `worktree-hook.bats` asserts 0 twice in a row |
| `_rdf_git_at_least major minor` | 0 when git ≥ major.minor; 1 below, or when `git version` is unparsable | `rdf_phase_hook_install` step 2: non-zero means rc 2 |
| `_rdf_realdir dir [base]` | 0 plus the physical path on stdout; non-zero when `cd` fails | install/uninstall: non-zero means rc 1 |
| `_rdf_atomic_write dest mode` | 0 written; 1 when mktemp, cat, chmod or mv fails (temp removed) | install: non-zero means rc 1 |
| `_rdf_session_plan root` (hook-local) | 0 plus the plan named by `<root>/.rdf/active-plan-$RDF_SESSION_ID`; 1 when there's no id, no pointer, or the file is missing | Hook: `_rdf_session_plan "$_top" \|\| _rdf_session_plan "$_main" \|\| rdf_active_plan_path "$_top" \|\| rdf_active_plan_path "$_main" \|\| true`, where empty means warn + `_rdf_pass` |
| `rdf_active_plan_path [root]` (existing) | 0 plus path; 1 none | The legacy-fallback tail of the chain above |

## File Map

### New Files
| File | Lines | Purpose | Test File |
|------|-------|---------|-----------|
| `tests/worktree-hook.bats` | 302 | Consumer-layout suite: install, enforcement, chaining, gating, refusal, idempotency, uninstall | N/A (test) |

### Modified Files
| File | Changes | Test File |
|------|---------|-----------|
| `state/rdf-bus.sh` | +`_rdf_git_at_least`, `_rdf_realdir`, `_rdf_atomic_write`, `_rdf_passthrough_script`, `rdf_phase_hook_install`, `rdf_phase_hook_uninstall`; Provides header (235 → 371) | `tests/worktree-hook.bats` |
| `state/git-hooks/pre-commit` | Branch-first parse; toplevel / `~/.rdf` bus; branch-derived session id; main-root plan fallback; `_rdf_pass` chaining; session-pointer-first plan resolution; anti-pattern enable/skip + shell-only (232 → 287) | `tests/worktree-hook.bats`, `tests/pre-commit-anti-patterns.bats`, `tests/rdf-bus.bats` |
| `tests/pre-commit-anti-patterns.bats` | +1 test (self-host skips markdown and `.bats`) | N/A (test) |
| `tests/Makefile` | Register `worktree-hook.bats` in `test` and `lint` | N/A (test) |
| `canonical/commands/r-build.md` | Hook install becomes one helper call per batch; payload gains `PROJECT_ROOT_MAIN` | `tests/adapter.bats` |
| `canonical/agents/dispatcher.md` | Step (b) becomes an idempotent helper call; heading kept | `tests/adapter.bats` |
| `canonical/reference/plan-schema.md` | §8d installer, mechanism, anti-pattern opt-in, uninstall | N/A (docs) |
| `canonical/reference/framework.md` | Helper list + install/uninstall | N/A (docs) |
| `adapters/claude-plugin/output/agents/dispatcher.md` | Regenerated from canonical | `tests/plugin-adapter.bats` |
| `adapters/claude-plugin/output/reference/framework.md` | Regenerated from canonical | `tests/plugin-adapter.bats` |
| `adapters/claude-plugin/output/reference/plan-schema.md` | Regenerated from canonical | `tests/plugin-adapter.bats` |
| `adapters/claude-plugin/output/skills/r-build/SKILL.md` | Regenerated from canonical | `tests/plugin-adapter.bats` |
| `adapters/claude-plugin/output/skills/reference/framework.md` | Regenerated from canonical | `tests/plugin-adapter.bats` |
| `adapters/claude-plugin/output/skills/reference/plan-schema.md` | Regenerated from canonical | `tests/plugin-adapter.bats` |
| `RDF.md`, `README.md`, `WORKFORCE.md` | Mechanism wording | `tests/doc-truth.bats` |
| `.github/workflows/ci.yml` | + macOS `/bin/bash` 3.2 phase-scope-guard smoke | N/A (CI; block executed locally in Phase 3 Step 2) |
| `CHANGELOG`, `CHANGELOG.RELEASE` | `## Unreleased` entries | N/A (docs) |

### Deleted Files
| File | Reason |
|------|--------|
| (none) | — |

## Phase Dependencies

- Phase 1: none
- Phase 2: [1]
- Phase 3: [1, 2]

---

### Phase 1: Phase-branch installer and consumer-aware hook

Adds the installer and uninstaller to the bus and rewrites the hook's discovery, session-id,
chaining and anti-pattern gating. It also adds the consumer-layout suite: the first tests that run
the hook outside RDF's own layout.

**Files:**
- Modify: `state/rdf-bus.sh` (installer, uninstaller, private helpers)
- Modify: `state/git-hooks/pre-commit` (discovery, chaining, gating)
- Create: `tests/worktree-hook.bats` (consumer-layout suite)
- Modify: `tests/pre-commit-anti-patterns.bats` (self-host shell-only test)
- Modify: `tests/Makefile` (register the new suite)

- **Mode**: serial-agent
- **Goals:** 1, 2, 3, 4, 5, 6, 7, 8, 9
- **Accept**:
  - `bats tests/worktree-hook.bats tests/pre-commit-anti-patterns.bats tests/rdf-bus.bats`
    reports 0 `not ok`.
  - `grep -c '@test' tests/worktree-hook.bats` = 19.
  - `make -n -C tests test | grep -c worktree-hook` = 1 and `make -n -C tests lint | grep -c worktree-hook` = 1.
  - `git diff --exit-code 8cce78d -- tests/rdf-bus.bats` rc 0.
  - `bash -n` + `shellcheck` clean on `state/rdf-bus.sh`, `state/git-hooks/pre-commit`,
    `tests/worktree-hook.bats` and `tests/pre-commit-anti-patterns.bats`.
- **Test**: 20 new tests (19 in `tests/worktree-hook.bats`, 1 in `tests/pre-commit-anti-patterns.bats`):
  - `tests/worktree-hook.bats::@test "install writes the onbranch include; main and feature worktrees keep their hooks path"`
  - `tests/worktree-hook.bats::@test "consumer: out-of-scope commit on a phase branch is rejected"`
  - `tests/worktree-hook.bats::@test "consumer: in-scope commit on a phase branch succeeds"`
  - `tests/worktree-hook.bats::@test "consumer: session id comes from the branch with no session env"`
  - `tests/worktree-hook.bats::@test "worktree-local plan pointer takes precedence over the main-root pointer"`
  - `tests/worktree-hook.bats::@test "main-root session pointer outranks a stale committed PLAN.md in the worktree"`
  - `tests/worktree-hook.bats::@test "phase branch with a non-SID suffix is still enforced"`
  - `tests/worktree-hook.bats::@test "prior pre-commit runs after RDF passes and its failure blocks the commit"`
  - `tests/worktree-hook.bats::@test "prior pre-commit does not run when RDF rejects"`
  - `tests/worktree-hook.bats::@test "other prior hooks run through the passthrough (commit-msg), including from a non-ASCII repo path"`
  - `tests/worktree-hook.bats::@test "prior pre-commit running git checkout fires post-checkout, not itself again"`
  - `tests/worktree-hook.bats::@test "relative hooksPath absent in the phase worktree: commit proceeds"`
  - `tests/worktree-hook.bats::@test "an RDF hook copy in the prior hooks dir is not re-run"`
  - `tests/worktree-hook.bats::@test "worktree added from inside a phase worktree on a feature branch is not enforced"`
  - `tests/worktree-hook.bats::@test "consumer: anti-pattern classes are off by default"`
  - `tests/worktree-hook.bats::@test "anti-pattern-enable opts a consumer in; non-shell files are never scanned"`
  - `tests/worktree-hook.bats::@test "install refuses with rc 2 when git is older than 2.23"`
  - `tests/worktree-hook.bats::@test "reinstall is idempotent: one include entry, symlinked repo path handled"`
  - `tests/worktree-hook.bats::@test "uninstall removes the include and files, restores prior hook resolution, and is repeatable"`
  - `tests/pre-commit-anti-patterns.bats::@test "self-hosting: staged markdown and .bats files are not scanned"`
  Existing guard tests that must stay green: `tests/rdf-bus.bats` "pre-commit hook rejects out-of-scope commit" and `tests/pre-commit-anti-patterns.bats` "scope-check ordering preserved (scope first, anti-pattern second)".
- **Edge cases**:
  - git < 2.23 → rc 2, nothing written
  - symlinked repo path
  - relative husky-style hooksPath absent in the worktree
  - RDF hook copy in the prior dir is not re-run
  - self-loop guard
  - nested worktree on a feature branch is not enforced
  - non-SID branch suffix is still enforced
  - Codex/manual commit with no session env
  - detached HEAD is not enforced
  - staged deletion is not scanned
  - extensionless shebang script is scanned when enabled
  - a user's `git config core.hooksPath X` is chained
  - user pre-commit running `git checkout -- .`
  - concurrent re-install (atomic writes)
  - the user's own `include.path`/`includeIf` sets `core.hooksPath`: chained through the
    `--show-origin` filter (reviewer-probed)
  - `git commit --no-verify` bypasses the hook: deferred to layer 2 (post-merge scope check,
    unchanged), so no test here
  - called from a linked worktree whose common dir is not named `.git` → rc 1; from a linked
    worktree whose common dir is `.git` → maps to the main root, rc 0
  - a `dir` outside any worktree, or a bare repo → rc 1
  - a stale committed `PLAN.md` in the worktree does not shadow the session pointer
- **Regression-case**: tests/worktree-hook.bats::@test "consumer: out-of-scope commit on a phase branch is rejected"

- [ ] **Step 1: Apply the tests patch**

  ```bash
  P=docs/plans/2026-09-24-worktree-scope-guard-patches
  git hash-object "$P/p1-tests.patch"
  # expect: 6952ed250baa941d3035f3eabd07376a897bbe5d
  git apply --check "$P/p1-tests.patch" && git apply "$P/p1-tests.patch" && echo applied
  # expect: applied
  ```

- [ ] **Step 2: Red. The new tests fail before the code exists**

  ```bash
  bats tests/worktree-hook.bats tests/pre-commit-anti-patterns.bats 2>&1 | grep -c '^not ok'
  # expect: 20
  bats tests/pre-commit-anti-patterns.bats 2>&1 | grep '^not ok' | sed 's/^not ok [0-9]* //'
  # expect: self-hosting: staged markdown and .bats files are not scanned
  ```

  All 19 `worktree-hook.bats` tests fail: `rdf_phase_hook_install` does not exist yet, and the old
  hook scans markdown.

- [ ] **Step 3: Apply the code patch**

  The patch:
  - adds `_rdf_git_at_least`, `_rdf_realdir`, `_rdf_atomic_write`, `_rdf_passthrough_script`,
    `rdf_phase_hook_install` and `rdf_phase_hook_uninstall` to `state/rdf-bus.sh`, and extends the
    Provides header
  - rewrites the hook as follows:
    - parse the branch first with `_phase_re='^rdf/phase-([0-9]+)-([^/]+)$'`
    - `export RDF_SESSION_ID` from a valid suffix
    - `_top` comes from `--show-toplevel`; `_main` comes from `rdf-hooks/.rdf-main-root`
    - the bus is `<top>/state/rdf-bus.sh` when self-hosting, else `${HOME}/.rdf/state/rdf-bus.sh`
    - the plan is `_rdf_session_plan` (session pointer) in `_top`, then `_main`, before
      `rdf_active_plan_path` legacy fallbacks in either root
    - every former `exit 0` becomes `_rdf_pass` (exec `.rdf-passthrough` when present)
    - anti-pattern classes are enabled for self-host or `# anti-pattern-enable:`, minus
      `# anti-pattern-skip:`, read from `<main>/.rdf/governance/ignore.md` and the legacy
      `<top>/governance/ignore.md`
    - `_ap_is_shell` limits scanning to `.sh`/`.bash` or a sh/bash shebang (first 256 bytes of
      the staged blob)

  ```bash
  git hash-object "$P/p1-code.patch"
  # expect: f1fee3fd88ba09bd974ff86fb778ba4d2bb79355
  git apply --check "$P/p1-code.patch" && git apply "$P/p1-code.patch" && echo applied
  # expect: applied
  ```

- [ ] **Step 4: Green + lint**

  ```bash
  bats tests/worktree-hook.bats tests/pre-commit-anti-patterns.bats tests/rdf-bus.bats 2>&1 | grep -c '^not ok'
  # expect: 0
  grep -c '@test' tests/worktree-hook.bats
  # expect: 19
  make -n -C tests test | grep -c worktree-hook
  # expect: 1
  make -n -C tests lint | grep -c worktree-hook
  # expect: 1
  git diff --exit-code 8cce78d -- tests/rdf-bus.bats && echo unmodified
  # expect: unmodified
  bash -n state/rdf-bus.sh && bash -n state/git-hooks/pre-commit && shellcheck state/rdf-bus.sh state/git-hooks/pre-commit tests/worktree-hook.bats tests/pre-commit-anti-patterns.bats && echo lint-ok
  # expect: lint-ok
  ```

- [ ] **Step 5: Commit**

  ```bash
  git add state/rdf-bus.sh state/git-hooks/pre-commit tests/worktree-hook.bats tests/pre-commit-anti-patterns.bats tests/Makefile
  git commit -F - <<'EOF'
  Scope guard: activate the phase pre-commit on rdf/phase-* branches in any project

  [New] rdf_phase_hook_install / rdf_phase_hook_uninstall (state/rdf-bus.sh): includeIf "onbranch:rdf/phase-**" points core.hooksPath at .git/rdf-hooks, whose static passthrough chains the project's own hooks; atomic writes; git >= 2.23 (rc 2 below)
  [Fix] pre-commit hook: finds rdf-bus.sh at <top>/state or ~/.rdf/state instead of an in-tree-only ancestor walk; session id from the phase branch; session pointers in the worktree and main root are checked before legacy fallbacks
  [Change] pre-commit anti-pattern classes scan shell files only and are opt-in outside RDF's own checkout (# anti-pattern-enable: in .rdf/governance/ignore.md)
  [New] tests/worktree-hook.bats: 19 consumer-layout tests (first coverage of the hook outside RDF's own layout); self-host shell-only test
  EOF
  git log --oneline -1
  # expect: <hash> Scope guard: activate the phase pre-commit on rdf/phase-* branches in any project
  ```

---

### Phase 2: /r-build and dispatcher install through the helper

Replaces the two broken `cp`-into-`.git/worktrees/<id>/hooks` snippets with one idempotent
`rdf_phase_hook_install` call, adds `PROJECT_ROOT_MAIN` to the worktree dispatch payload, updates
the schema and framework references, and regenerates adapter output.

**Files:**
- Modify: `canonical/commands/r-build.md` (install call; payload)
- Modify: `canonical/agents/dispatcher.md` (step (b))
- Modify: `canonical/reference/plan-schema.md` (§8d)
- Modify: `canonical/reference/framework.md` (helper list)
- Modify: `adapters/claude-plugin/output/agents/dispatcher.md` (regenerated)
- Modify: `adapters/claude-plugin/output/reference/framework.md` (regenerated)
- Modify: `adapters/claude-plugin/output/reference/plan-schema.md` (regenerated)
- Modify: `adapters/claude-plugin/output/skills/r-build/SKILL.md` (regenerated)
- Modify: `adapters/claude-plugin/output/skills/reference/framework.md` (regenerated)
- Modify: `adapters/claude-plugin/output/skills/reference/plan-schema.md` (regenerated)

- **Mode**: serial-agent
- **Goals:** 8
- **Accept**:
  - `grep -rn 'rev-parse --git-dir)/hooks\|wt_git_dir}/hooks\|worktree_git_dir}/hooks' canonical/`
    prints nothing.
  - `grep -c rdf_phase_hook_install` ≥ 1 in both `r-build.md` and `dispatcher.md`.
  - `grep -c 'PROJECT_ROOT_MAIN: {main worktree toplevel}' canonical/commands/r-build.md` = 1.
  - `bats tests/adapter.bats tests/plugin-adapter.bats` reports 0 `not ok`.
  - `bin/rdf generate claude-plugin` leaves `git diff --exit-code adapters/claude-plugin/output
    .claude-plugin/plugin.json` clean after the commit.
- **Test**:
  - `tests/adapter.bats::@test "regenerated r-build mentions UUIDv7 worktree session-id and controller cd"`
    (asserts the `state/git-hooks/pre-commit` literal the new prose keeps)
  - `tests/adapter.bats` dispatcher assertions (heading `Worktree Pre-Commit Hook Installation`)
  - `tests/plugin-adapter.bats`
- **Edge cases**:
  - `--separate-git-dir` and submodule call sites: `r-build.md` passes
    `$(git rev-parse --show-toplevel)` from the main worktree
  - a bare repo gets rc 1, then the warning, then layer 2
- **Regression-case**: tests/adapter.bats::@test "regenerated r-build mentions UUIDv7 worktree session-id and controller cd"

- [ ] **Step 1: Apply the code patch**

  ```bash
  P=docs/plans/2026-09-24-worktree-scope-guard-patches
  git hash-object "$P/p2-code.patch"
  # expect: 8f28e5aaad09ae11e3387c955dd31a0ebaeab927
  git apply --check "$P/p2-code.patch" && git apply "$P/p2-code.patch" && echo applied
  # expect: applied
  ```

- [ ] **Step 2: Regenerate and verify**

  ```bash
  bin/rdf generate claude-code 2>&1 | grep -o 'complete: [0-9]* agents'
  # expect: complete: 8 agents
  bin/rdf generate claude-plugin 2>&1 | grep -o 'complete: [0-9]* skills'
  # expect: complete: 37 skills
  git status --short adapters/claude-plugin/output .claude-plugin/plugin.json | wc -l
  # expect: 6
  grep -rn 'rev-parse --git-dir)/hooks\|wt_git_dir}/hooks\|worktree_git_dir}/hooks' canonical/ | wc -l
  # expect: 0
  grep -c 'PROJECT_ROOT_MAIN: {main worktree toplevel}' canonical/commands/r-build.md
  # expect: 1
  grep -c rdf_phase_hook_install canonical/commands/r-build.md canonical/agents/dispatcher.md
  # expect:
  # canonical/commands/r-build.md:1
  # canonical/agents/dispatcher.md:1
  bats tests/adapter.bats tests/plugin-adapter.bats 2>&1 | grep -c '^not ok'
  # expect: 0
  ```

- [ ] **Step 3: Commit**

  ```bash
  git add canonical/commands/r-build.md canonical/agents/dispatcher.md canonical/reference/plan-schema.md canonical/reference/framework.md adapters/claude-plugin/output/agents/dispatcher.md adapters/claude-plugin/output/reference/framework.md adapters/claude-plugin/output/reference/plan-schema.md adapters/claude-plugin/output/skills/r-build/SKILL.md adapters/claude-plugin/output/skills/reference/framework.md adapters/claude-plugin/output/skills/reference/plan-schema.md
  git commit -F - <<'EOF'
  /r-build + dispatcher: install the phase scope guard through rdf_phase_hook_install

  [Fix] r-build.md and dispatcher.md step (b) copied the hook into .git/worktrees/<id>/hooks, which git never reads; both now call the idempotent rdf_phase_hook_install and fall back to the post-merge scope check on failure
  [Fix] r-build.md worktree dispatch payload carries PROJECT_ROOT_MAIN, which dispatcher steps (a) and (b) already read
  [Change] plan-schema.md §8d and framework.md describe the phase-branch include, anti-pattern opt-in, and rdf_phase_hook_uninstall
  [Change] regenerated claude-plugin output
  EOF
  git log --oneline -1
  # expect: <hash> /r-build + dispatcher: install the phase scope guard through rdf_phase_hook_install
  bin/rdf generate claude-plugin >/dev/null 2>&1; git diff --exit-code --stat adapters/claude-plugin/output .claude-plugin/plugin.json && echo no-drift
  # expect: no-drift
  ```

---

### Phase 3: Docs, bash 3.2 CI smoke, and changelog

Brings the mechanism wording in RDF.md, README.md and WORKFORCE.md up to date. Adds a macOS
`/bin/bash` 3.2 CI smoke of the consumer path, and records the change under `## Unreleased`.

**Files:**
- Modify: `RDF.md` (lines 53-55 wording)
- Modify: `README.md` (line 364 wording)
- Modify: `WORKFORCE.md` (line 71 installer column)
- Modify: `.github/workflows/ci.yml` (new macOS smoke step at end of the tests job)
- Modify: `CHANGELOG` (new `## Unreleased` section)
- Modify: `CHANGELOG.RELEASE` (becomes Unreleased release notes)

- **Mode**: serial-agent
- **Goals:** 1
- **Accept**:
  - The CI smoke block, extracted from `ci.yml` and run under local bash, prints
    `bash 3.2 phase scope guard smoke: OK`.
  - `grep -c 'active on every `rdf/phase-\*` branch' README.md` = 1.
  - `head -3 CHANGELOG | tail -1` = `## Unreleased`.
  - `bin/rdf doctor --scope doc-truth` reports 0 FAIL.
  - `make -C tests test` reports 0 `not ok`.
- **Test**:
  - Step 2 runs the extracted smoke block (`# expect: bash 3.2 phase scope guard smoke: OK`).
  - `tests/doc-truth.bats`.
  - Full `make -C tests test`.
- **Edge cases**: bash 3.2 execution of the consumer path. CI covers it on macOS; it was validated
  locally in `bash:3.2` Docker.
- **Regression-case**: N/A — refactor — docs, changelog and a CI smoke step only; no production code changes in this phase

- [ ] **Step 1: Apply the code patch**

  ```bash
  P=docs/plans/2026-09-24-worktree-scope-guard-patches
  git hash-object "$P/p3-code.patch"
  # expect: 10ce21047dacf604268ef54e83114b69119fea1e
  git apply --check "$P/p3-code.patch" && git apply "$P/p3-code.patch" && echo applied
  # expect: applied
  ```

- [ ] **Step 2: Run the new CI smoke block locally**

  ```bash
  python3 - > /tmp/i2-ci-smoke.sh <<'PY'
  s=open('.github/workflows/ci.yml').read()
  blk=s.split("- name: Smoke phase scope guard under system bash 3.2 (macOS)")[1].split("run: |\n",1)[1]
  print("set -euo pipefail"); print("\n".join(l[10:] for l in blk.splitlines()))
  PY
  bash /tmp/i2-ci-smoke.sh
  # expect: bash 3.2 phase scope guard smoke: OK
  ```

- [ ] **Step 3: Full verification**

  ```bash
  make -C tests test > /tmp/test-rdf-i2-P3.log 2>&1; grep -c '^not ok' /tmp/test-rdf-i2-P3.log
  # expect: 0
  grep -m1 '^1\.\.' /tmp/test-rdf-i2-P3.log
  # expect: 1..443
  grep -rc '^\s*@test ' tests/*.bats | awk -F: '{s+=$2}END{print s}'
  # expect: 443
  grep -c 'active on every `rdf/phase-\*` branch' README.md
  # expect: 1
  bin/rdf doctor --scope doc-truth 2>&1 | tail -1
  # expect:   Summary: 12 OK, 0 WARN, 0 FAIL
  bin/rdf doctor 2>&1 | grep -c '\[FAIL\]'
  # expect: 0
  head -3 CHANGELOG | tail -1
  # expect: ## Unreleased
  ```

- [ ] **Step 4: Commit**

  ```bash
  git add RDF.md README.md WORKFORCE.md .github/workflows/ci.yml CHANGELOG CHANGELOG.RELEASE
  git commit -F - <<'EOF'
  Docs + CI + changelog: phase-branch scope guard

  [Change] RDF.md, README.md, WORKFORCE.md: the scope guard is active on every rdf/phase-* branch and installed by /r-build via rdf_phase_hook_install
  [New] CI: macOS smoke runs the consumer-project scope guard (install + rejected out-of-scope commit) under system /bin/bash 3.2
  [Change] CHANGELOG / CHANGELOG.RELEASE: Unreleased entries for the scope guard fix
  EOF
  git log --oneline -1
  # expect: <hash> Docs + CI + changelog: phase-branch scope guard
  ```

---

## Post-Build Acceptance (controller-run; spec §10b M6)

These run after Phase 3 and are not dispatched to a phase. Results go in the ship notes.

- **(a) Real harness commit.**
  1. In a fresh consumer sandbox, run the new `r-build.md` worktree-dispatch snippet verbatim
     against the deployed `~/.rdf/state` (checkout deploy symlinks point at this repo's `state/`).
  2. Have a **subagent**, i.e. a real harness Bash environment, commit an out-of-scope file in the
     phase worktree. `# expect: commit rc != 0, stderr contains "SCOPE VIOLATION"`.
  3. Have the subagent commit an in-scope file. `# expect: rc 0`.
- **(b) `isolation: "worktree"` landing.** Dispatch a subagent with `isolation: "worktree"` and
  record its worktree path, branch, and whether the hook fires on a commit there.
  `# expect: a recorded observation. If the branch is not rdf/phase-*, file the §3 isolation
  follow-up.`
