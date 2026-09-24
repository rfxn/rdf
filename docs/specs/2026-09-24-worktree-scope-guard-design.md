# Worktree Scope Guard for Consumer Projects — Design Spec

**Date:** 2026-09-24 · **Tier:** full · **Tracks:** I-2 (context-economy follow-up) · **Revision:** 3.
Challenge review round 1 raised 6 MUST-FIX and 6 SHOULD-FIX items; revision 2 replaced the mechanism,
switching from per-worktree `core.hooksPath` to an `includeIf "onbranch:"` include (S5). Round 2
raised 1 MUST-FIX and 5 SHOULD-FIX items against the passthrough and installer; revision 3 resolves
them. Every finding is mapped in §13.

## 1. Problem Statement

`/r-build` promises that a pre-commit hook "installed in each dispatched worktree physically rejects
out-of-scope commits" (RDF.md:53-55, README.md:364, plan-schema.md:236-239). In any project other
than RDF itself the hook never runs. Two independent causes were reproduced in a sandbox consumer
repo on git 2.49.0, and the challenge reviewer confirmed both:

1. **Wrong install location.** `r-build.md:253-267` and `dispatcher.md:95-118` copy the hook to
   `$(git -C <wt> rev-parse --git-dir)/hooks/pre-commit`, i.e. `.git/worktrees/<id>/hooks/`.
   - Git never reads that directory. It uses `core.hooksPath`, else `$GIT_COMMON_DIR/hooks`.
   - The directory doesn't exist, so the `cp` fails.
   - In the sandbox, a failing hook placed there by hand did not fire, and an out-of-scope commit
     succeeded.
2. **Wrong helper discovery.** `pre-commit:14-24` searches ancestor directories for
   `state/rdf-bus.sh` and exits 0 when it finds none. Only an RDF checkout has that file. Consumer
   projects get the bus from `~/.rdf/state/rdf-bus.sh`.

RDF masks both bugs. Its `.git/config` sets `core.hooksPath` to `.git/hooks`, which holds a
hand-installed hook copy, and its tree contains `state/rdf-bus.sh`. The hook suites
(`tests/rdf-bus.bats:105-121`, `tests/pre-commit-anti-patterns.bats:13-57`) build exactly that
layout, with no linked worktree, so the consumer path has 0 tests.

**Latent third defect.** Fixing (1) and (2) would expose it. The anti-pattern section
(`pre-commit:124-229`) applies five rfxn shell conventions to every staged file, whatever its type.
Examples are the `command` prefix on coreutils and the same-line comment for `2>/dev/null`. Once the
hook engages in consumer projects, it would reject a README line containing "touch", or a Makefile
using `2>/dev/null`. Those conventions moved to the opt-in `rfxn-workspace` profile in 3.6.5.

Layer 2 is prose that the dispatcher follows: the post-merge `diff-tree` check at
`dispatcher.md:124-181`. It is the only enforcement consumers get today. Its own text records that
prose alone failed: "M13 dispatch produced 5/5 scope violations despite explicit prose instruction"
(dispatcher.md:183-184).

## 2. Goals

1. G1: In a consumer project (no `state/rdf-bus.sh` in the tree, helpers at `~/.rdf/state/`), a
   commit on a `rdf/phase-<N>-*` branch that stages a file outside the phase's
   `Files ∪ Tests-may-touch` is rejected.
2. G2: An in-scope commit on the same branch succeeds.
3. G3: Enforcement does not depend on `CLAUDE_CODE_SESSION_ID` or `RDF_SESSION_ID` in the commit's
   environment. The session id comes from the branch, which covers Codex sessions and manual
   commits.
4. G4: The user's own hooks keep running on phase branches. The prior `pre-commit` runs after RDF's
   check passes, exactly once even when it runs git commands that fire other hooks; the prior
   commit-msg and post-checkout hooks, and any others, run unchanged, including hooks added after
   install.
5. G5: Worktrees on non-phase branches, including the main worktree and worktrees created from
   inside a phase worktree, keep their effective hooks unchanged.
6. G6: Consumer projects get scope enforcement only, and the anti-pattern classes stay off unless
   the project opts in. On every project, only `.sh`/`.bash` files and files with a sh or bash
   shebang are scanned.
7. G7: RDF self-hosting behavior is preserved. All five classes stay on, the legacy
   `governance/ignore.md` opt-outs still work, and `tests/rdf-bus.bats`,
   `tests/pre-commit-anti-patterns.bats` and `tests/adapter.bats` pass. The first and third pass
   byte-unmodified; the second only gains tests.
8. G8: One idempotent installer, `rdf_phase_hook_install`, replaces both duplicated prose snippets.
   It returns rc 2 when git is older than 2.23. A matching `rdf_phase_hook_uninstall` removes
   every RDF artifact.
9. G9: Uninstall restores the exact prior hook resolution, and install leaves no file outside
   `$GIT_COMMON_DIR`.

## 3. Non-Goals

- Changing `/r-build`'s `isolation: "worktree"` dispatch (r-build.md:291). The acceptance probe in
  §10b measures where commits actually land, and any finding is filed as a follow-up.
- Changing the five anti-pattern classes or their regexes (pre-commit:147-161).
- Changing layer 2 (the post-merge `diff-tree` check) or the engineer dirty check.
- Automatic uninstall at the end of `/r-build`. Concurrent sessions on the same repo may still be
  building. The include is inert off phase branches.
- Emitting Codex/Antigravity agents or any other adapter change.

## 4. Architecture

### File Map

| File | Status | Lines (before → est. after) | Purpose |
|------|--------|-----------------------------|---------|
| `state/git-hooks/pre-commit` | modify | 232 → ~275 | Branch-first parse; toplevel/`~/.rdf` bus discovery; branch-derived session id; recorded-main-root plan fallback; `_rdf_pass` chaining; anti-pattern gating |
| `state/rdf-bus.sh` | modify | 235 → ~345 | Add `_rdf_git_at_least`, `_rdf_realdir`, `_rdf_install_exec`, `rdf_phase_hook_install`, `rdf_phase_hook_uninstall`; header Provides list |
| `canonical/commands/r-build.md` | modify | 409 → ~403 | Replace the per-worktree `cp` snippet (253-271) with one install call per batch; keep the literal `state/git-hooks/pre-commit` (asserted by `tests/adapter.bats:334`); add `PROJECT_ROOT_MAIN` to the worktree-dispatch payload (287-290) |
| `canonical/agents/dispatcher.md` | modify | 558 → ~548 | Step (b) (95-118): idempotent helper call; keep the heading `Worktree Pre-Commit Hook Installation` (asserted by `tests/adapter.bats:322`) |
| `canonical/reference/plan-schema.md` | modify | 355 → ~362 | §8d (236-239): installer + mechanism; anti-pattern opt-in/skip + shell-only scope |
| `canonical/reference/framework.md` | modify | +2 lines after 100 | Helper list: `rdf_phase_hook_install` / `rdf_phase_hook_uninstall` |
| `RDF.md` | modify | 53-55 | Mechanism stated precisely (phase-branch include; project hooks chained) |
| `README.md` | modify | 364 | "installed in every dispatched worktree" → "active on every `rdf/phase-*` branch" |
| `WORKFORCE.md` | modify | 71 | Installer column → `/r-build` (`rdf_phase_hook_install`) |
| `.github/workflows/ci.yml` | modify | +~14 after 158 | macOS `/bin/bash` 3.2 smoke: install + rejected commit in a consumer fixture |
| `tests/worktree-hook.bats` | **new** | 0 → ~360 | Consumer-layout suite (§10a, 18 tests) |
| `tests/pre-commit-anti-patterns.bats` | modify | 172 → ~195 | +1 test: self-host skips markdown and `.bats` |
| `tests/Makefile` | modify | +1 name in `test` and `lint` | Register `worktree-hook.bats` |
| `CHANGELOG`, `CHANGELOG.RELEASE` | modify | new `## Unreleased` section | [Fix] entries |
| `adapters/claude-plugin/output/**`, `.claude-plugin/plugin.json` | regenerate | — | `bin/rdf generate claude-plugin` after canonical edits; CI drift gate (ci.yml:109) |

**No-touch (explicit):**
- `tests/adapter.bats` and `tests/rdf-bus.bats`: kept green by preserving the asserted strings and
  the self-host layout.
- `state/rdf-state.sh`, `lib/**`, `bin/rdf`, `adapters/*/adapter.sh` and `agent-meta.json`.
- `canonical/scripts/state-bootstrap.sh`: it already ships `git-hooks/pre-commit`, lines 26-37.
- `lib/cmd/deploy.sh`: it already links the hook, lines 211-213.
- `CLAUDE.md` and `CONTRIBUTING.md`.

### Size Comparison

| Metric | Before | After |
|--------|--------|-------|
| Hook-install implementations | 2 prose snippets (both wrong) | 1 shell function, 2 call sites |
| Consumer-project enforcement | never | scope always; anti-patterns opt-in |
| Tests exercising a linked worktree / consumer layout | 0 | 18 |
| Repo footprint | none (install failed) | `includeIf` section + `.git/rdf-hooks.inc` + `.git/rdf-hooks/` |

### Dependency Tree

```
/r-build controller: once per worktree batch, in the main worktree    dispatcher step (b): idempotent re-call
        │ source ~/.rdf/state/rdf-bus.sh                                        │ ("$PROJECT_ROOT_MAIN")
        └──► rdf_phase_hook_install "$(git rev-parse --show-toplevel)" ◄───────┘
                          ├─ _rdf_git_at_least 2 23            (onbranch: needs git 2.23)
                          ├─ _rdf_realdir                       (cd -P realpath; CDPATH-safe)
                          ├─ $COMMON/rdf-hooks/pre-commit     ◄── cp ~/.rdf/state/git-hooks/pre-commit
                          │                                         (fallback: $MAIN/state/git-hooks/pre-commit)
                          ├─ $COMMON/rdf-hooks/.rdf-main-root      (main worktree toplevel)
                          ├─ $COMMON/rdf-hooks/.rdf-passthrough    (static script)
                          ├─ $COMMON/rdf-hooks/<name>              (atomic copies of .rdf-passthrough: fixed
                          │                                          client-side names + other executable prior hooks)
                          ├─ $COMMON/rdf-hooks.inc                 [core] hooksPath = $COMMON/rdf-hooks
                          └─ $COMMON/config                        [includeIf "onbranch:rdf/phase-**"] path = rdf-hooks.inc

git commit on rdf/phase-<N>-<SID> (any worktree) ──► $COMMON/rdf-hooks/pre-commit
        ├─ branch ^rdf/phase-([0-9]+)-([^/]+)$ ?  no ──► _rdf_pass
        ├─ _top = --show-toplevel; _main = .rdf-main-root (else _top)
        ├─ bus: _top/state/rdf-bus.sh (self-host) | ${HOME}/.rdf/state/rdf-bus.sh ; none ──► warn, _rdf_pass
        ├─ RDF_SESSION_ID = suffix when it matches [A-Za-z0-9-]+
        ├─ plan: rdf_active_plan_path _top || rdf_active_plan_path _main ; none ──► warn, _rdf_pass
        ├─ scope check (logic unchanged) ── violation ──► exit 1
        ├─ anti-pattern: enabled classes ∩ shell files ── hit ──► exit 1
        └─ _rdf_pass ──► RDF_HOOK_NAME=pre-commit exec .rdf-passthrough (when installed) | exit 0

.rdf-passthrough (as <name>): name = RDF_HOOK_NAME or $0 basename; unset RDF_HOOK_NAME
        ├─ prior = last `core.hooksPath` value (-z --type=path --show-origin --get-all) whose origin
        │          is not rdf-hooks.inc, else $COMMON/hooks
        ├─ prior is the RDF hooks dir, missing target, or target carries the RDF marker ──► exit 0
        └─ exec prior/<name> "$@"
```

### Key Changes

1. **Mechanism.** One include in the common config switches `core.hooksPath` to
   `$COMMON/rdf-hooks` only while `HEAD` is on `rdf/phase-**`. Any other branch, in any worktree,
   resolves hooks exactly as before. Sandbox-verified on 2.49.0:
   - The phase worktree resolves to `.git/rdf-hooks`; a feature worktree and the main worktree
     resolve to `.git/hooks`.
   - A worktree created from inside a phase worktree on `feature/y` resolves to `.git/hooks`.
   - The include wins even when the user re-sets `core.hooksPath` afterwards, because git edits the
     existing `[core]` key in place, above the include. Only a later user include that itself sets
     `hooksPath` would win.
   - `--remove-section` restores the prior resolution.
2. **Coexistence.** The last `core.hooksPath` value whose `--show-origin` is not `rdf-hooks.inc`
   (read NUL-delimited with `-z --type=path`, so origins are never C-quoted, so `~` and `~user` expand) is the hooks dir git would use without RDF.
   It is resolved at run time and per worktree, so relative husky-style paths resolve against the
   committing worktree, and a user's own `include.path`/`includeIf` hooksPath is honored. A static
   passthrough script is copied under every standard client-side hook name. `exec` keeps `$0`, so
   hooks that locate files with `dirname "$0"` keep working.
3. **Discovery.** `--show-toplevel` bounds the bus lookup, so it no longer searches ancestor
   directories. The main root is recorded at install time and read by the hook. That makes it
   correct for `--separate-git-dir` and for worktrees nested under `.worktrees/`.
4. **Anti-pattern gating.**
   - Enabled set: all five classes when self-hosting, plus any `# anti-pattern-enable:` lines,
     minus any `# anti-pattern-skip:` lines.
   - Directives are read from `$_main/.rdf/governance/ignore.md` and `$_top/governance/ignore.md`
     (legacy).
   - Only shell files are scanned. `.bats` is excluded: its bats shebang doesn't match, and BATS
     files use bare coreutils by convention.

### Dependency Rules

- `state/rdf-bus.sh` is sourced into agent shells. New functions use `return` only, never `set` or
  `exit`, and carry `command` prefixes.
- Everything must run on bash 3.2: no `mapfile`, no `local -A`, no `${v,,}`, and
  `"${a[@]+"${a[@]}"}"` for possibly-empty arrays.
- Declare `local` separately from `x=$(…)`.
- The hook keeps `set -euo pipefail`. Every current `exit 0` becomes `_rdf_pass`; the `exit 1`
  sites are unchanged. The hook must not source the bus before the branch check.
- Generated or copied hook scripts are static. The passthrough has no install-time interpolation,
  so there is no generated-code quoting surface.
- Every installed executable is written atomically (temp file in the same directory, `chmod +x`,
  then `command mv -f`), because other sessions may be committing while `/r-build` re-installs.
- All validation (steps 1-5) completes before the first write (step 6).

## 5. File Contents

### 5.1 `state/rdf-bus.sh` — new functions

| Function | Signature | Purpose | Dependencies |
|----------|-----------|---------|--------------|
| `_rdf_git_at_least` | `(major, minor)` → rc 0/1 | Parse `git version` (tolerates the `(Apple Git-154)` suffix); rc 1 when unparsable | `git` |
| `_rdf_realdir` | `(dir [base])` → stdout abs path, rc 1 on failure | Physical absolute path; relative `dir` resolves against `base`. `(CDPATH= cd -P -- "$base" >/dev/null && CDPATH= cd -P -- "$dir" >/dev/null && pwd -P)` | none |
| `_rdf_install_exec` | `(src, dest)` → rc 0/1 | Atomic executable install: `tmp=$(command mktemp "${dest%/*}/.tmp.XXXXXX")`, `command cp`, `command chmod 755` (mktemp creates 0600; `+x` would leave 0711, unreadable to other users of a shared repo), `command mv -f "$tmp" "$dest"`; removes `tmp` on failure | `command mktemp/cp/chmod/mv/rm` |
| `rdf_phase_hook_install` | `([dir [hook_src]])` → rc 0 installed or refreshed / 1 not a repo, not the main worktree toplevel, or no hook source / 2 git < 2.23 | Install or refresh the phase-branch scope guard for the repo whose main worktree toplevel is `dir` (default `$PWD`) | `_rdf_git_at_least`, `_rdf_realdir`, `_rdf_install_exec`, `git`, `command mkdir` |
| `rdf_phase_hook_uninstall` | `([dir])` → rc 0 / 1 not a repo | Remove the include section, `rdf-hooks.inc` and `rdf-hooks/` | `_rdf_realdir`, `git`, `command rm` |

`rdf_phase_hook_install` steps. Failures print `rdf_phase_hook_install: <reason>` to stderr.

| # | Step | rc on failure |
|---|------|---------------|
| 1 | `git -C "$dir" rev-parse --git-dir >/dev/null` | 1 ("not a git repository") |
| 2 | `_rdf_git_at_least 2 23` | 2 ("git >= 2.23 required (includeIf onbranch)") |
| 3 | Set `common` from `_rdf_realdir "$(git -C "$dir" rev-parse --git-common-dir)" "$dir"`. Set `gitdir` from `_rdf_realdir "$(git -C "$dir" rev-parse --absolute-git-dir)"` | 1 |
| 4 | Main root: if `gitdir == common`, use `git -C "$dir" rev-parse --show-toplevel`, and a failure there (bare repo, or `dir` inside `.git/modules`) is fatal. Else, if `${common##*/} == .git`, use `${common%/*}`. Else fail | 1 ("run from the main worktree toplevel"), before any write |
| 5 | Hook source: `$2`, else `${HOME:-}/.rdf/state/git-hooks/pre-commit`, else `$main/state/git-hooks/pre-commit` | 1 ("pre-commit hook source not found") |
| 6 | `hdir="$common/rdf-hooks"`. `command mkdir -p`. `_rdf_install_exec` the source to `$hdir/pre-commit`. Write `$main` to `$hdir/.rdf-main-root`. Write the static passthrough (§5.3) to a temp file and `_rdf_install_exec` it to `$hdir/.rdf-passthrough` | 1 |
| 7 | Passthrough names: the fixed client-side set `applypatch-msg pre-applypatch post-applypatch pre-merge-commit prepare-commit-msg commit-msg post-commit pre-rebase post-checkout post-merge pre-push post-rewrite pre-auto-gc`, plus any other regular executable file (not `pre-commit`, not `*.sample`) in the install-time prior dir (resolved as in §5.3; relative resolves against `$main`). Hooks with a per-operation cost, such as `reference-transaction` and `post-index-change`, are wrapped only when the user already has them. `_rdf_install_exec` `.rdf-passthrough` to `$hdir/<name>` for each | — |
| 8 | `git config --file "$common/rdf-hooks.inc" core.hooksPath "$hdir"` | 1 |
| 9 | Unless `git config --file "$common/config" --get 'includeIf.onbranch:rdf/phase-**.path'` already equals `rdf-hooks.inc`, set it. Relative include paths resolve against `$common` | 1 |

`rdf_phase_hook_uninstall` runs `git config --file "$common/config" --remove-section
'includeIf.onbranch:rdf/phase-**'` only when `--get 'includeIf.onbranch:rdf/phase-**.path'` succeeds
(`--remove-section` on a missing section exits 128, so it is never called blind). It then runs
`command rm -rf -- "$common/rdf-hooks" "$common/rdf-hooks.inc"` and returns 0; repeat calls are no-ops.

### 5.2 `state/git-hooks/pre-commit` — change inventory

| Region | Current behavior | New behavior | Lines affected |
|--------|------------------|--------------|----------------|
| Header | "Installed into worktrees by dispatcher" | "Installed by `rdf_phase_hook_install`; active on `rdf/phase-**` branches via an `includeIf onbranch` include". Line 2 keeps the marker phrase `RDF worktree scope enforcement` | 2-10 |
| `_rdf_pass()` (new) | — | `_hd=$(command dirname "$0")`. If `$_hd/.rdf-passthrough` is executable, `RDF_HOOK_NAME=pre-commit exec "$_hd/.rdf-passthrough"`; otherwise `exit 0` (legacy `.git/hooks` installs and tests) | new, after `set` |
| Branch parse | `^rdf/phase-([0-9]+)-` (39) after sourcing the bus | Runs first. `_phase_re='^rdf/phase-([0-9]+)-([^/]+)$'` (the same branch set the `onbranch:rdf/phase-**` include matches, since `**` does not cross `/` there) captures `_phase_n` and `_sfx`. `export RDF_SESSION_ID="$_sfx"` only when `_sfx` has no chars outside `[A-Za-z0-9-]` (`case`); otherwise the session env decides. No match calls `_rdf_pass` | 34-45 |
| Root + bus | Ancestor walk; exit 0 if none | `_top` = `git rev-parse --show-toplevel`. `_main` = `$(< "$_hd/.rdf-main-root")` when that file exists, else `_top`. If `$_top/state/rdf-bus.sh` exists, `_self_host=1` and source it; else source `${HOME:-}/.rdf/state/rdf-bus.sh`; else print `rdf pre-commit: rdf-bus.sh not found (checked <top>/state and ~/.rdf/state); skipping scope check` and call `_rdf_pass` | 14-32 |
| Plan resolve | `rdf_active_plan_path "$_proj"`; exit 0 if empty | `rdf_active_plan_path "$_top"`, then `rdf_active_plan_path "$_main"`, then empty (`\|\| true`); empty prints a warning and calls `_rdf_pass` | 50-54 |
| Nothing staged | `exit 0` | `_rdf_pass` | 81 |
| Anti-pattern config | Skip list from `$_proj/governance/ignore.md` | `_ap_enabled=()`, filled with all five when `_self_host=1`. For each of `$_main/.rdf/governance/ignore.md` and `$_top/governance/ignore.md` that exists: `# anti-pattern-enable: all\|<class>` adds, `# anti-pattern-skip: <class>` adds to skips. `${#_ap_enabled[@]} -eq 0` calls `_rdf_pass` before any diff work | 163-181 |
| Per-file loop | Every staged file | `_ap_is_shell "$_ap_path" \|\| continue`; the class loop checks `_ap_class_enabled` and then `_ap_class_skipped`; `"${_ap_enabled[@]+"${_ap_enabled[@]}"}"` | 184-225 |
| `_ap_is_shell()` (new) | — | rc 0 for `*.sh\|*.bash`. Otherwise `IFS= read -r _l < <(git cat-file -p ":$1" 2>/dev/null) \|\| true` (deleted or empty blob means no shebang), then `[[ "$_l" =~ $_ap_shebang_re ]]` with `_ap_shebang_re='^#!.*(/\|[[:space:]])(ba)?sh([[:space:]]\|$)'` | new |
| Remediation text | "…to governance/ignore.md." | "…to .rdf/governance/ignore.md." | 222 |
| Final | `exit 0` | `_rdf_pass` | 232 |

### 5.3 `$COMMON/rdf-hooks/.rdf-passthrough` — static content (written by step 6)

| Element | Behavior |
|---------|----------|
| Shebang / marker | `#!/usr/bin/env bash`, then `# RDF phase-branch passthrough` |
| Name | `name="${RDF_HOOK_NAME:-${0##*/}}"; unset RDF_HOOK_NAME`. Cleared before `exec` so git commands run inside the user's hook fire their own hooks by name (N1) |
| Prior dir | Read `git config -z --type=path --show-origin --get-all core.hooksPath` as NUL-delimited origin/value pairs (`while IFS= read -r -d '' o && IFS= read -r -d '' v`; bash 3.2-safe). `-z` output is never C-quoted, whereas the line form quotes origins with non-ASCII, `"` or `\\` bytes and would defeat the filter. Skip pairs whose origin ends in `rdf-hooks.inc`, and keep the last remaining value (rc 1 when unset, which means the default; same-line comment). Empty becomes `"$(git rev-parse --git-common-dir)/hooks"`. `--type=path` expands `~` and `~user`; relative values resolve against cwd, since git runs hooks at the worktree top |
| Self-loop guard | If `prior` resolves (`cd -P`) to the passthrough's own directory, `exit 0` |
| Missing target | `[[ -x "$prior/$name" ]] \|\| exit 0` (git's own "no hook = success") |
| RDF copy guard | If `grep -q 'RDF worktree scope enforcement' "$prior/$name"`, `exit 0` (RDF's own `.git/hooks` copy is never re-run) |
| Hand-off | `exec "$prior/$name" "$@"`; stdin and environment are inherited |

### 5.4 Canonical prose and docs — change inventory

| File | Current | New | Lines |
|------|---------|-----|-------|
| `r-build.md` | Per-worktree `cp` snippet and "per-worktree hooks directory" prose after `git worktree add`; the worktree-dispatch payload lacks `PROJECT_ROOT_MAIN` | Before the worktree loop, once per batch, in the main worktree: `source ~/.rdf/state/rdf-bus.sh && rdf_phase_hook_install "$(git rev-parse --show-toplevel)" \|\| echo "warn: phase scope guard (layer 1) not installed; post-merge scope check still applies" >&2`. Then one sentence: the helper copies `~/.rdf/state/git-hooks/pre-commit` (self-hosting: `state/git-hooks/pre-commit`) into the repo's `rdf-hooks/`, active only on `rdf/phase-*` branches; rc 2 means git < 2.23. Keeps the `plan-schema.md` Rule 8 cross-reference. The worktree-dispatch payload (287-290) gains `PROJECT_ROOT_MAIN: {main worktree toplevel}`, which dispatcher steps (a) and (b) already read | 253-271, 287-290 |
| `dispatcher.md` | Step (b): `cp` snippet + 3 paragraphs on the deployed hook | Keep the heading at 63. Step (b): `rdf_phase_hook_install "$PROJECT_ROOT_MAIN"`, idempotent (`/r-build` normally installed it). One sentence on the mechanism. "If either step fails" (120-122) is unchanged | 95-118 |
| `plan-schema.md` | "installed in worktrees by dispatcher" | "installed by `/r-build` (`rdf_phase_hook_install`), active on `rdf/phase-*` branches; the project's own hooks still run". Plus: anti-pattern classes scan shell files only; RDF self-hosting enables all five; consumers opt in with `# anti-pattern-enable: <class>\|all` in `.rdf/governance/ignore.md`; uninstall with `rdf_phase_hook_uninstall` | 236-239 |
| `framework.md` | Helper list ends at `rdf_parse_phase_scope` | + `rdf_phase_hook_install [dir]` and `rdf_phase_hook_uninstall [dir]`, one line each | after 100 |
| `RDF.md` | "A pre-commit hook installed in each dispatched worktree physically rejects out-of-scope commits" | "A pre-commit hook active on every `rdf/phase-*` branch (one `includeIf` include; the project's own hooks still run) physically rejects out-of-scope commits" | 53-55 |
| `README.md` | "installed in every dispatched worktree" | "active on every `rdf/phase-*` branch" | 364 |
| `WORKFORCE.md` | "dispatcher (installer)" | "`/r-build` (installer: `rdf_phase_hook_install`)" | 71 |
| `ci.yml` | macOS smokes: bus, init, bootstrap | + "Smoke phase scope guard under system bash 3.2 (macOS)": populates `HOME=$(mktemp -d)` with `.rdf/state/{rdf-bus.sh,git-hooks/pre-commit}` from the checkout; builds a consumer repo (no `state/`) committing `a.sh` and `p.md` (`### Phase 1: x` / ``- Modify: `a.sh` ``) with `.rdf/active-plan` pointing at `p.md`; runs `/bin/bash -c 'source state/rdf-bus.sh; rdf_phase_hook_install "$repo"'`, then commits an out-of-scope file on `rdf/phase-1-x` with `PATH=/bin:/usr/bin:$PATH` (so `env bash` resolves to 3.2) and requires `rc != 0` plus `SCOPE VIOLATION` | after 158 |

## 5b. Examples

Install (once per repo; re-runs refresh):
```
$ source ~/.rdf/state/rdf-bus.sh
$ rdf_phase_hook_install "$PWD"; echo "rc=$?"
rc=0
$ tail -2 .git/config
[includeIf "onbranch:rdf/phase-**"]
	path = rdf-hooks.inc
$ git rev-parse --git-path hooks                 # on main: unchanged
.git/hooks
$ git -C .worktrees/rdf-phase-1-0199… rev-parse --git-path hooks
/home/u/app/.git/rdf-hooks
```

Out-of-scope commit on a phase branch (G1):
```
$ git add outside.txt && git commit -m wip
rdf pre-commit: SCOPE VIOLATION — files outside Phase 1 scope:
outside.txt

Phase Files allowed: src/a\.sh
If this addition is legitimate test-infra, add the path to
the phase's **Tests-may-touch:** field in PLAN.md.
Bypass with --no-verify only if dispatcher post-merge check is acceptable.
$ echo $?
1
```

Failure case (old git):
```
$ rdf_phase_hook_install "$PWD"; echo "rc=$?"
rdf_phase_hook_install: git >= 2.23 required (includeIf onbranch)
rc=2
```

Uninstall:
```
$ rdf_phase_hook_uninstall "$PWD"; echo "rc=$?"
rc=0
$ git config --get-regexp '^includeif\.'; echo "rc=$?"
rc=1
```

State before and after (per repo):
```
before: .git/{config,hooks/…}
after:  .git/config + [includeIf "onbranch:rdf/phase-**"] path = rdf-hooks.inc
        .git/rdf-hooks.inc  ([core] hooksPath = <abs>/.git/rdf-hooks)
        .git/rdf-hooks/{pre-commit,.rdf-main-root,.rdf-passthrough[,<one per prior hook>]}
```

## 6. Conventions

- Function header: one line, `# name args — purpose`. The rc contract goes on a second line
  (a non-obvious caller contract).
- Stderr prefixes: `rdf_phase_hook_install:` for the installer and `rdf pre-commit:` for the hook
  (existing).
- Regexes used with `[[ =~ ]]` live in variables.
- Every new `2>/dev/null` or `|| true` carries a same-line reason.
- BATS: bare coreutils; `mktemp -d` sandboxes; `HOME` pointed at the sandbox so `~/.rdf/state` is
  a fixture; git identity passed per command with `-c user.email=… -c user.name=…`.

## 7. Interface Contracts

- **New shell API** (exported by `state/rdf-bus.sh`, delivered by deploy symlink and plugin
  bootstrap):
  - `rdf_phase_hook_install [dir [hook_src]]` → 0/1/2
  - `rdf_phase_hook_uninstall [dir]` → 0/1
- **New governance directive:** `# anti-pattern-enable: <class>|all` in
  `.rdf/governance/ignore.md`. `# anti-pattern-skip:` is now read there as well, and the legacy
  `governance/ignore.md` is still honored.
- **Repo config written:** `[includeIf "onbranch:rdf/phase-**"] path = rdf-hooks.inc` in the
  common config.
- **Hook behavior:** off phase branches it exits 0, or chains the prior pre-commit when installed
  via the helper. Scope-violation messages are unchanged.
- **CLI (`bin/rdf`):** unchanged.

## 8. Migration Safety

- **Upgrade:**
  - Checkout installs pick up the new hook and bus through per-file symlinks (`deploy.sh:202-213`).
  - Plugin installs copy them at SessionStart only when `VERSION` changes
    (`state-bootstrap.sh:20-24`), so plugin users get the fix at the next release, not from
    `## Unreleased`.
  - The first `/r-build` worktree batch after the upgrade runs the installer.
  - Earlier failed installs left nothing git reads, so there's nothing to migrate.
- **Install:** no new installed files. `state/git-hooks/pre-commit` already ships on both tiers.
- **Rollback:**
  - Reverting the commit restores the old prose.
  - The already-written include keeps pointing at a hook copy that still works standalone: the
    old bus discovery simply skips.
  - `rdf_phase_hook_uninstall` (or `git config --remove-section 'includeIf.onbranch:rdf/phase-**'`
    followed by `rm -rf .git/rdf-hooks .git/rdf-hooks.inc`) removes everything.
- **Uninstall:** `rdf_phase_hook_uninstall`. The test in §10a proves the prior resolution is
  restored.
- **RDF self-hosting:**
  - RDF's `.git/config` `core.hooksPath` (`.git/hooks`, holding a hand-installed copy) becomes the
    passthrough's prior dir.
  - The RDF-copy guard skips it, so the hook doesn't run twice.
  - The hook's self-host branch keeps today's in-tree bus.
- **Test suite:**
  - `tests/rdf-bus.bats` and `tests/adapter.bats` stay byte-unmodified; §10b checks this.
  - `tests/pre-commit-anti-patterns.bats` gains one test.
  - The new suite is registered in both Makefile targets.

## 9. Dead Code and Cleanup

| Finding | Location | Action |
|---------|----------|--------|
| Duplicate hook-install snippet (second copy of the same wrong logic) | `dispatcher.md:98-107` vs `r-build.md:257-267` | Both replaced by the helper call |
| Redundant second bus-existence check | `pre-commit:26-30` | Removed by the discovery rewrite |
| Stale local governance notes | `.rdf/governance/ignore.md:33`, `.rdf/governance/verification.md` (Pre-Commit) | Not committed (gitignored). `/r-refresh` after ship |

## 10a. Test Strategy

`tests/worktree-hook.bats` fixture (`setup`):
- `HOME=$(mktemp -d)` with `.rdf/state/{rdf-bus.sh,git-hooks/pre-commit}` copied from the source
  tree.
- A consumer repo with no `state/`, committing `src/a.sh` and `docs/plans/p.md`
  (`### Phase 1: x` / `**Files:**` / ``- Modify: `src/a.sh` ``).
- `.rdf/` listed in `.git/info/exclude`.
- A main-root pointer `.rdf/active-plan-<SID>` pointing at the plan.
- `rdf_phase_hook_install` run from the main root, and a worktree
  `.worktrees/rdf-phase-1-<SID>` on branch `rdf/phase-1-<SID>`.

Commits run under `env -u CLAUDE_CODE_SESSION_ID -u RDF_SESSION_ID` unless a test says otherwise.

| Goal | Test file | Test description |
|------|-----------|------------------|
| G8, G5 | worktree-hook.bats | `@test "install writes the onbranch include; main and feature worktrees keep their hooks path"` |
| G1 | worktree-hook.bats | `@test "consumer: out-of-scope commit on a phase branch is rejected"` |
| G2 | worktree-hook.bats | `@test "consumer: in-scope commit on a phase branch succeeds"` |
| G3 | worktree-hook.bats | `@test "consumer: session id comes from the branch with no session env"` |
| G3 | worktree-hook.bats | `@test "worktree-local plan pointer takes precedence over the main-root pointer"` |
| G3 | worktree-hook.bats | `@test "phase branch with a non-SID suffix is still enforced"` (`rdf/phase-1-a.b`; env `RDF_SESSION_ID=<SID>`) |
| G4 | worktree-hook.bats | `@test "prior pre-commit runs after RDF passes and its failure blocks the commit"` |
| G4 | worktree-hook.bats | `@test "prior pre-commit does not run when RDF rejects"` |
| G4 | worktree-hook.bats | `@test "other prior hooks run through the passthrough (commit-msg), including from a non-ASCII repo path"` (repo under `café/`) |
| G4 | worktree-hook.bats | `@test "prior pre-commit running git checkout fires post-checkout, not itself again"` (N1: pre-commit runs exactly once; post-checkout runs) |
| G4 | worktree-hook.bats | `@test "relative hooksPath absent in the phase worktree: commit proceeds"` (husky-style `.husky/_`) |
| G7 | worktree-hook.bats | `@test "an RDF hook copy in the prior hooks dir is not re-run"` |
| G5 | worktree-hook.bats | `@test "worktree added from inside a phase worktree on a feature branch is not enforced"` |
| G6 | worktree-hook.bats | `@test "consumer: anti-pattern classes are off by default"` |
| G6 | worktree-hook.bats | `@test "anti-pattern-enable opts a consumer in; non-shell files are never scanned"` |
| G8 | worktree-hook.bats | `@test "install refuses with rc 2 when git is older than 2.23"` (PATH shim answering `git version`) |
| G8 | worktree-hook.bats | `@test "reinstall is idempotent: one include entry, symlinked repo path handled"` (repo reached via `ln -s`) |
| G9 | worktree-hook.bats | `@test "uninstall removes the include and files, restores prior hook resolution, and is repeatable"` |
| G6, G7 | pre-commit-anti-patterns.bats | `@test "self-hosting: staged markdown and .bats files are not scanned"` |
| G7 | rdf-bus.bats, adapter.bats, pre-commit-anti-patterns.bats | existing tests pass (§10b G7) |

## 10b. Verification Commands

`BASE` is the commit before implementation (the spec commit).

```bash
# G1-G6, G8, G9 — new suite + full suite
make -C tests test 2>&1 | tee /tmp/test-rdf-i2.log | tail -2
grep -c '^not ok' /tmp/test-rdf-i2.log
# expect: 0
grep -c '@test' tests/worktree-hook.bats
# expect: 18
grep -c 'worktree-hook.bats' tests/Makefile
# expect: 2
# G1 (consumer rejection) spot-run
bats -f 'out-of-scope commit on a phase branch is rejected' tests/worktree-hook.bats
# expect: ok 1 … (1 test, 0 failures)
# G7 — self-host suites unmodified or additive only
git diff --exit-code "$BASE" -- tests/rdf-bus.bats tests/adapter.bats; echo "rc=$?"
# expect: rc=0
git diff "$BASE" -- tests/pre-commit-anti-patterns.bats | grep -c '^-[^-]'
# expect: 0
# G8 — single implementation, stale snippets gone
grep -rn 'rev-parse --git-dir)/hooks\|wt_git_dir}/hooks\|worktree_git_dir}/hooks' canonical/
# expect: (no output)
grep -c 'rdf_phase_hook_install' canonical/commands/r-build.md canonical/agents/dispatcher.md
# expect: canonical/commands/r-build.md:1   canonical/agents/dispatcher.md:1   (each >= 1)
# Lint + drift
bash -n state/rdf-bus.sh state/git-hooks/pre-commit && shellcheck state/rdf-bus.sh state/git-hooks/pre-commit; echo "rc=$?"
# expect: rc=0
bin/rdf generate claude-plugin >/dev/null && git diff --exit-code --stat adapters/claude-plugin/output .claude-plugin/plugin.json; echo "rc=$?"
# expect: rc=0 (after the regenerated output is committed)
bin/rdf doctor 2>&1 | grep -c '\[FAIL\]'
# expect: 0
```

**Acceptance probe (M6: the real delivery path; controller-run after build, recorded in the ship
notes).**
- (a) Run the new `r-build.md` worktree-dispatch snippet verbatim in a fresh consumer sandbox
  against the deployed `~/.rdf/state`. Then have a **subagent**, i.e. a real harness Bash
  environment, commit an out-of-scope file in the phase worktree.
  `# expect: rc != 0 with "SCOPE VIOLATION"`.
- (b) Dispatch a subagent with `isolation: "worktree"` from the repo and record where its commit
  lands: branch name, directory, and whether the hook fired.
  `# expect: a recorded observation. If commits land off rdf/phase-*, file the §3 isolation
  follow-up and keep RDF.md wording scoped to "rdf/phase-* branches".`

## 11. Risks

1. **Persistent footprint in user repos** (the include section plus two paths under `.git/`).
   *Mitigation:*
   - It is inert off `rdf/phase-*` branches.
   - It is RDF-namespaced and removable with one function, which a test proves round-trips.
   - It is documented in plan-schema §8d and the CHANGELOG.
2. **Hook-name coverage.** A hook type outside the fixed client-side set that the user adds after
   install (e.g. `reference-transaction`) is skipped on phase branches until the next `/r-build`
   batch re-installs.
   *Mitigation:* the fixed set covers every standard client-side hook that is free to wrap, and
   re-install runs every batch.
3. **User hooks silently skipped on phase branches** if the passthrough is wrong.
   *Mitigation:* the four G4 tests cover pre-commit order, failure propagation, a non-pre-commit
   hook, and an absent relative path.
4. **Behavior change for RDF self-hosting:** markdown and `.bats` files stop being scanned.
   *Mitigation:*
   - This is intended; the old behavior produced false positives on prose words and BATS bare
     coreutils.
   - A dedicated test pins it, and the CHANGELOG states it.
5. **bash 3.2 regressions.**
   *Mitigation:* §4 Dependency Rules, plus a new macOS CI smoke that runs the consumer path under
   `/bin/bash`.
6. **Commits made during `/r-build` may land off phase branches** (`isolation: "worktree"`).
   *Mitigation:*
   - The acceptance probe (b) measures it.
   - Doc wording claims enforcement on phase branches only, which is exactly what the mechanism
     guarantees.
7. **Old git (< 2.23).**
   *Mitigation:* the installer returns rc 2, and the call sites warn and fall back to layer 2.

## 11b. Edge Cases

| Scenario | Expected behavior | Handling |
|----------|-------------------|---------|
| git < 2.23 | rc 2; nothing written | Step 2 runs before any write |
| Called from a linked worktree whose common dir is not named `.git` | rc 1 ("run from the main worktree toplevel") | Step 4 |
| `--separate-git-dir` main repo | Works when called with the main worktree toplevel, which the r-build call site passes; a `dir` outside any worktree returns rc 1 | Step 4, first branch |
| Submodule checkout | Works when called from the submodule's own worktree (sandbox: the hook fired in its main and linked worktrees); a `dir` inside `.git/modules` fails `--show-toplevel` and returns rc 1 before any write | Step 4, fatal branch |
| Bare repo used through worktrees | rc 1 (no toplevel; common dir not named `.git`). Unsupported; layer 2 applies | Step 4 |
| Repo reached through a symlinked path (macOS `/var` → `/private/var`) | Realpaths are compared and recorded | `_rdf_realdir` (`cd -P`/`pwd -P`) |
| Husky-style relative `core.hooksPath` absent in the phase worktree | The passthrough finds no target and exits 0 | Missing-target rule |
| Prior hooks dir is RDF's own `.git/hooks` holding an RDF copy | Not re-run | Marker guard |
| Someone points `core.hooksPath` at `rdf-hooks` directly | No exec loop | Self-loop guard |
| Worktree created from inside a phase worktree on `feature/*` | Not enforced | onbranch matches `HEAD` only |
| Phase branch suffix is not a valid SID (`rdf/phase-1-a.b`) | Still enforced; session from env | Suffix validated separately from the phase match |
| Commit from Codex or by hand (no session env) | Enforced | Branch-derived SID |
| Detached `HEAD` (rebase) | Not enforced; prior hooks as usual | onbranch fails to match, so git's normal resolution applies |
| Staged deletion of a shell file | Not scanned | `cat-file` read fails harmlessly; empty diff |
| Extensionless `#!/usr/bin/env bash` script | Scanned when classes are enabled | Shebang rule |
| `git commit --no-verify` | Bypassed | Layer 2 (unchanged) |
| User runs `git config core.hooksPath X` after install | RDF still active on phase branches; `X` becomes the chained prior | `git config` edits the existing `[core]` key above the include (sandbox-verified) |
| User's own `include.path`/`includeIf` sets `core.hooksPath` (dotfile work/personal split) | Chained as the prior dir | `--show-origin` filter keeps every non-RDF origin |
| User pre-commit runs `git checkout -- .` (pre-commit framework or lint-staged stash) | The post-checkout passthrough runs the user's post-checkout; pre-commit runs once | `unset RDF_HOOK_NAME` before `exec` |
| Another session commits while `/r-build` re-installs | Runs either the old or the new complete script | Atomic temp-file + `mv` installs |

## 12. Open Questions

None blocking. Observed and deferred: `r-build.md:291` stacks `isolation: "worktree"` on the
RDF-managed worktree. Acceptance probe (b) will measure where those commits land, and the outcome
is filed as a follow-up.

## 13. Challenge Round 1 Resolution

| Finding | Resolution |
|---------|------------|
| M1 inherited `config.worktree` | Removed by S5: there's no per-worktree config, and onbranch evaluates each worktree's own `HEAD`. Test added: "worktree added from inside a phase worktree…" |
| M2 realpath vs logical path | `_rdf_realdir` (`cd -P`) for every compared or recorded path. Symlinked-path case added to the idempotency test |
| M3 `adapter.bats:334` literal | New r-build prose keeps `state/git-hooks/pre-commit`; the dispatcher keeps the heading asserted at `adapter.bats:322`. `adapter.bats` is no-touch |
| M4 file map | Added `README.md`, `framework.md`, `ci.yml`, `.claude-plugin/plugin.json`; `adapter.bats` and `rdf-bus.bats` listed as no-touch |
| M5 per-goal verification | §10b labels each command with its goals; G7 `git diff` checks added |
| M6 unmeasured delivery path | Acceptance probe (a)+(b) with a real subagent commit; doc claims scoped to `rdf/phase-*` branches |
| S1 v1 repos | Moot: no extension is written |
| S2 submodule / separate-git-dir | Main root recorded at install (`.rdf-main-root`); table corrected |
| S3 narrowed regex | Phase match is `^rdf/phase-([0-9]+)-([^/]+)$` (round 2, I9); SID validated separately; a non-SID suffix is still enforced (test added) |
| S4 missing wrapper target | Passthrough exits 0 when the target is missing |
| S5 simpler alternative | Adopted |
| S6 set -e / 3.2 hazards | Pinned in §4 and §5.2: process-substitution read, `$(< file)`, `${HOME:-}`, guarded empty arrays, CDPATH-safe `cd -P`, separate `local` |
| I1 plugin delivery | §8 Upgrade |
| I2 no 3.2 run of the consumer path | New macOS CI smoke (§5.4) |
| I3 stale local governance | §9 (`/r-refresh` after ship) |
| I4 line nits | Fixed (remediation at 222, dispatcher step (b) 95-118, test counts agree) |
| I5 relative call-site path | The install call passes `$(git rev-parse --show-toplevel)` (round 2, S7) |
| I6 security | No new trust boundary; the passthrough is static (no generated code) |
| I7 `.bats` false positives | `.bats` excluded from the shell set |

### Challenge Round 2 Resolution

| Finding | Resolution |
|---------|------------|
| N1 `RDF_HOOK_NAME` leaks, so a user pre-commit running git recurses | The passthrough unsets `RDF_HOOK_NAME` after reading it (§5.3); G4 test added |
| S7 separate-git-dir / submodule call site | Both call sites pass the main worktree toplevel; a step 4 `--show-toplevel` failure is fatal before any write; §11b rows corrected |
| S8 `--remove-section` exits 128 on a missing section | Uninstall checks with `--get` first; the G9 test asserts a repeat uninstall |
| S9 include-provided and `~user` hooksPath values | `--type=path --show-origin --get-all`, drop the `rdf-hooks.inc` origin, last value wins; Risk 2 replaced |
| S10 non-atomic re-install | `_rdf_install_exec` (temp file + `mv`); §4 rule |
| S11 `PROJECT_ROOT_MAIN` never set | Added to the r-build worktree-dispatch payload |
| I8 install-time snapshot of hook names | Fixed client-side name set plus any names already present |
| I9 include vs hook regex branch sets | Hook regex `([^/]+)` matches the include's branch set |
| I10 bare repo | §11b row |
| I11 CI fixture | The §5.4 ci.yml row specifies the full fixture |
| I12 "include stays last" | Reworded (§4, §11b) |

### Challenge Round 3 Resolution

| Finding | Resolution |
|---------|------------|
| R1 C-quoted `--show-origin` origins defeat the filter | NUL-delimited `-z` parse (§5.3); non-ASCII repo path added to the G4 commit-msg test |
| R2 `mktemp` + `chmod +x` leaves mode 0711 | `_rdf_install_exec` uses `chmod 755` |
| R3 CI smoke `"$repo"` inside single quotes | Plan note: pass `repo` as `$1` (`/bin/bash -c '…' _ "$repo"`) |

Reviewer verdict after round 3: ready to approve once R1 is applied (applied in this revision).
