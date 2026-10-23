# Implementation Plan: `rdf account primary`, move the primary to another account

**Goal:** `rdf account primary <name> [--dry-run]` makes a registered account the one
logged in to `~/.claude`, and moves the previous primary's login to `~/.claude-<old>`,
without touching the shared state every account links to.

**Architecture:** The primary is defined by where its login lives: `~/.claude` (with
`~/.claude.json` beside it) and `CLAUDE_CONFIG_DIR` unset. Shared entries
(`_ACCOUNT_SHARED`) stay in `~/.claude`; only per-account entries move. A swap is three
sets of renames (old primary out, target in, target's links dropped) plus a registry
rewrite. Every rename before the registry write is recorded and reversed on failure.

**Tech Stack:** bash (3.2 macOS / 4.1 el6 floor), jq, BATS.

**Spec:** N/A (quick-plan; context folded below).

**Phases:** 1

**Tier:** quick-plan

## Context

- `~/.claude` is logged in to the Novi Labs Teams org; the workspace assumes `rfxn`
  (Max, `~/.claude-rfxn`) is what bare `claude` (IDE, cron, `claude -p`, scripts) uses.
- `add --primary` refuses a second primary and nothing re-designates one. Rename-only
  (`remove` + `add --primary`) leaves the Novi login in `~/.claude`.
- Probed 2026-10-23 on this host (Claude Code 2.1.309):
  - per-account files that embed the config dir path: only `plugins/*.json`
    (`installPath`, `installLocation`); `jobs/*/state.json` paths point into shared
    `projects/`; `.claude.json` holds no config-dir paths
  - live sessions: `sessions/<pid>.json` per running session; process `comm` is `claude`
  - per-account entries in `~/.claude` include `daemon*`, `jobs`, `sessions.db`,
    `remote-settings*`, `policy-limits*` (Teams managed policy) and junk (`*.bak-*`)

## Phase 1: `rdf account primary` [serial-context]

**Files:** lib/cmd/account.sh, tests/account.bats, README.md, CHANGELOG, CHANGELOG.RELEASE

Preflight (all before any change; `--dry-run` runs them and prints the moves):
- target registered, not already primary; a primary is registered
- not macOS: the keychain entry is keyed to the config dir path and cannot be moved
- target dir exists and holds `.credentials.json` (it is logged in)
- `~/.claude-<old>` does not exist
- every shared-name entry in the target dir is a link to `~/.claude/<entry>`, or has no
  counterpart in `~/.claude` (it then moves in and becomes shared); anything else refuses
- no entry to be moved is a symlink (it would dangle or loop after the move)
- no live session: a live pid in either dir's `sessions/*.json` or `daemon/roster.json`, or
  a process of this user whose comm, argv0 or `/proc/<pid>/exe` is `claude` or under
  `claude/versions/` → refuse (dry-run warns)
- a stray `~/.claude/.claude.json` is reported and left in place

Swap:
1. `mkdir -m 700 ~/.claude-<old>`; move every non-shared entry of `~/.claude` into it, and
   `~/.claude.json` → `~/.claude-<old>/.claude.json`
2. move every non-link entry of the target dir into `~/.claude`;
   `<target>/.claude.json` → `~/.claude.json`
3. registry: target → `@primary`, old → `~/.claude-<old>` (tmp + mv)
4. on failure in 1-3: reverse recorded renames (never onto a path recreated meanwhile),
   remove the new dir, exit 1
5. rewrite config-dir prefixes in both dirs' `plugins/*.json` in place, keeping mode and
   owner (jq; failure warns)
6. drop the target's links and remove its dir (non-empty → warn, keep); re-link shared
   entries into every non-primary account, so entries that just became shared reach all

Names, `rdf account default` and `RDF_CLAUDE_ACCOUNT` are unchanged, so launchers keep
working by name.

**Accept:** account.bats green with `ps`/`uname` stubbed on PATH:
- swap moves credentials, `.claude.json`, plugins and org policy files both ways;
  shared entries untouched; registry and `list` show the new layout; other accounts'
  links still resolve
- plugin JSON paths rewritten both ways
- `--dry-run` changes nothing
- refusals leave the tree unchanged: unknown name, already primary, no primary,
  not logged in, existing `~/.claude-<old>`, own copy of a shared entry, symlinked
  entry, live session (pid file, daemon roster, `claude` and version-named processes),
  Darwin
- a failed rename or registry write mid-swap restores the original tree; a path
  recreated mid-swap is reported, never overwritten
- adversarial sentinel review (2026-10-23): findings 1-8 and 10 fixed with regressions

## Edge Cases

| Case | Behavior |
|------|----------|
| Target has a shared-name entry absent from `~/.claude` | moves in, becomes shared |
| Old primary not logged in | allowed; its dir is created without a login |
| Stale `sessions/<pid>.json` with a recycled live pid | refuses (fail-safe); message names the file |
| `~/.claude.json.tmp.*` crash leftovers in `$HOME` | left in place |
| Target dir not empty after swap | kept, warned |
