# Implementation Plan: Claude account switcher + launcher conventions

**Goal:** `rdf shell init` emits the rfxn Claude Code launcher conventions (`c`, `cs`,
`ch`, `--fs`) with an account switcher, and `rdf account` manages per-account config dirs
that share projects, memory, history and config with `~/.claude`.

**Architecture:** One `CLAUDE_CONFIG_DIR` per extra account (`~/.claude-<name>`) holding only
account-scoped state (login, `.claude.json`, org remote-settings/policy-limits, plugins,
runtime caches); an allowlist of shared entries symlinks back to `~/.claude`. The primary
account is `~/.claude` itself and always launches with `CLAUDE_CONFIG_DIR` unset (setting
it to `~/.claude` would move `.claude.json` from `~/.claude.json`, and the macOS keychain
entry is keyed to the exact `CLAUDE_CONFIG_DIR` string). Shell functions select
an account by a leading `@name` argument or a sticky per-shell `cuse <name>`.

**Tech Stack:** bash (3.2 macOS / 4.1 el6 floor), jq, BATS; emitted shell code must run in
bash and zsh.

**Spec:** N/A — quick-plan; context folded below.

**Phases:** 3

**Plan Version:** 3.0.6

**Tier:** quick-plan

## Context

- Today: `~/.bashrc` hand-defines `c`, `ch`, `cs` (`export IS_SANDBOX=1 ; claude
  --dangerously-skip-permissions`, which leaks IS_SANDBOX into the shell) and a `claude()`
  wrapper mapping `--fs` to `--fork-session`. `~/.claude` is logged in to the Teams org
  (rmacdonald@novilabs.com); the second account is Max (rfxnryan@gmail.com).
- Requirement: both accounts see the same transcripts, auto memory and `--resume` list.
  Per-account dirs (not a token on one dir) keep Remote Control and claude.ai connectors
  on both accounts, and keep the Teams org's cached managed settings out of Max sessions.
- No account selected → env passes through untouched, so `cs` behaves as today.

## Conventions

**Boilerplate** — new `lib/cmd/*.sh` and `tests/*.bats` copy the header block of
`lib/cmd/tokens.sh` / `tests/tokens.bats` (current year only).

**Registry** — `${HOME}/.rdf/accounts`: `# comment` lines plus `name<TAB>/abs/dir`.
Names match `^[a-z0-9][a-z0-9_-]{0,31}$`. At most one entry may point at `${HOME}/.claude`.

**Shared entries** — `projects history.jsonl paste-cache file-history tasks todos plans
CLAUDE.md settings.json keybindings.json skills agents commands rules output-styles scripts
governance reference`.
Never linked: `.credentials.json`, `.claude.json`, `remote-settings*`, `policy-limits*`,
`plugins/`, `sessions/`, runtime caches.

**Commit message format** — free-form, body lines tagged `[New] [Change] [Fix]`.

**CRITICAL:** link never deletes or overwrites a real file/dir in an account dir; remove
never deletes the account dir (it holds that login).

## File Map

### New Files
| File | Lines | Purpose | Test File |
|------|-------|---------|-----------|
| lib/cmd/account.sh | ~200 | `rdf account add\|list\|link\|remove\|dir` | tests/account.bats |
| lib/cmd/shell.sh | ~90 | `rdf shell init` launcher emitter | tests/shell.bats |
| tests/account.bats | ~150 | registry, linking, list, remove, dir | — |
| tests/shell.bats | ~120 | `@name`, sticky, `--fs`, sandbox, passthrough, zsh | — |

### Modified Files
| File | Changes | Test File |
|------|---------|-----------|
| bin/rdf | dispatch + usage lines for `account`, `shell` | tests/account.bats |
| tests/Makefile | add both suites to `test` and `lint` | N/A (config) |
| README.md | §4.4 usage + table rows; multi-account subsection; dir tree | N/A (docs) |
| CHANGELOG, CHANGELOG.RELEASE | Unreleased `[New]` entries | N/A (docs) |

## Phase Dependencies

- Phase 1: none
- Phase 2: [1]
- Phase 3: [1, 2]

## Phase 1: `rdf account` [serial-agent]

**Files:** lib/cmd/account.sh, bin/rdf, tests/account.bats, tests/Makefile

- `add <name>`: creates `~/.claude-<name>` (mode 700), links shared entries, registers.
  `add <name> --primary`: registers `~/.claude` (must exist; only one primary). Duplicate
  name or second primary → `rdf_die` (exit 1, repo convention).
- `link [<name>]`: idempotent re-link for one or every non-primary account; per entry:
  source absent → skip; correct symlink → ok; foreign symlink or real path → warn, keep.
- `list`: name, active marker (`RDF_CLAUDE_ACCOUNT`, else the account at `CLAUDE_CONFIG_DIR`,
  else primary), dir, login
  (`oauthAccount.emailAddress` + `organizationName` from `~/.claude.json` for primary,
  `<dir>/.claude.json` otherwise; "not logged in" when absent), shared `linked/available`.
- `remove <name>`: unregisters, prints the kept dir.
- `dir <name>`: prints the `CLAUDE_CONFIG_DIR` value, an empty line for primary; unknown
  or invalid name → `rdf_die` naming the registered accounts.

**Accept:** account.bats green under a `mktemp -d` HOME: add creates links for present
sources only; a pre-existing real `projects/` survives `link` with a warning; add→remove
roundtrip leaves the registry empty and the dir intact; `dir` exit codes; bad names
(`../x`, `A`, empty) rejected; second `--primary` rejected.

## Phase 2: `rdf shell init` [serial-agent]

**Files:** lib/cmd/shell.sh, bin/rdf, tests/shell.bats, tests/Makefile

Emits (absolute rdf path baked in): a silenced `unalias claude c cs ch cuse`, then
`function name {` definitions (not alias-expanded at parse time) for `claude`, `c`
(plain), `cs` (`--dangerously-skip-permissions`; `IS_SANDBOX=1` scoped to the child only
with `init --sandbox`), `ch` (`--chrome`), `cuse`.

- Leading `@name` (`[a-z0-9_-]`, not `@agent-*`) selects an account unless a path of that
  name exists in cwd and is not a registered account; anything else passes through as
  prompt text. Else `RDF_CLAUDE_ACCOUNT`. Else no env change and no rdf call.
- Selected account → `env -u CLAUDE_CODE_OAUTH_TOKEN -u ANTHROPIC_API_KEY -u
  ANTHROPIC_AUTH_TOKEN [-u CLAUDE_CONFIG_DIR | CLAUDE_CONFIG_DIR=<dir>]
  RDF_CLAUDE_ACCOUNT=<name> claude ...`; resolve failure returns nonzero without launching.
- `--fs` → `--fork-session` anywhere in argv.
- `cuse <name>` validates via `rdf account dir` then exports `RDF_CLAUDE_ACCOUNT`;
  `cuse -` unsets; `cuse` alone runs `rdf account list`.

**Accept:** shell.bats green with a stub `claude` on PATH that prints argv and the
relevant env: `cs @rfxn --fs` → stub sees `CLAUDE_CONFIG_DIR=<dir>`, `IS_SANDBOX=1`,
`--dangerously-skip-permissions --fork-session`; `@primary` unsets an inherited
`CLAUDE_CONFIG_DIR`; no selection passes env through; `@nope` launches nothing;
`claude "@src/a.ts hi"` passes the arg through; IS_SANDBOX absent from the parent shell
after `cs`; init evals cleanly over pre-existing `alias cs=...`; zsh case skips when zsh
is absent (macOS CI runs it).

## Phase 3: Docs + changelog [serial-context]

**Files:** README.md, CHANGELOG, CHANGELOG.RELEASE

**Accept:** README usage block and table list `account` and `shell`; setup steps
(`eval "$(rdf shell init)"`, `rdf account add <name> --primary`, `rdf account add <name>`,
first launch logs in); `rdf doctor --scope doc-truth` and `--scope readme` pass.

## Edge Cases

| Case | Behavior |
|------|----------|
| No registry, no selection | launch identical to plain `claude` (no rdf call) |
| `@name` unknown | stderr lists accounts, nonzero, nothing launched |
| Prompt text starting with `@path` | passed through, not treated as account |
| Source entry created in `~/.claude` after add | `rdf account link` picks it up; `list` shows `linked/available` |
| Account dir already has a real `projects/` (launched before linking) | kept, warned; user merges |
| Nested launch inside a Claude session | inherits `RDF_CLAUDE_ACCOUNT` / `CLAUDE_CONFIG_DIR` from parent |
| Shared `settings.json` with `forceLoginOrgUUID` | blocks the other account's login; documented |
| Shared `settings.json` `remote.defaultEnvironmentId`, `enabledPlugins` | apply to both accounts; documented |
| Org work opened under the other account | transcripts and memory are shared by design (owner requirement); README states it |
| Inherited credential env vars with an account picked | dropped so the account's login wins |
| `ch @name` | Chrome extension keeps the browser's claude.ai login; documented |

## Review (one round, quick-plan)

Challenge review: CONCERNS, no blockers. Applied: shared `paste-cache`/`tasks`/`todos`;
`@` parsing tightened (`@agent-*`, uppercase, existing paths pass through); credential env
vars dropped on account pick; `list` reads `CLAUDE_CONFIG_DIR`; `IS_SANDBOX` opt-in via
`--sandbox` (upstream `setup.sh` `cs` has no IS_SANDBOX; public default stays safe);
`ln -sn`; `HOME` trailing slash normalized; rc-ordering, data-direction and per-account
docs; tests for dangling links, remove/re-add login reuse and the no-rdf-call path.
Declined: per-account `--settings` override file (no current need; documented instead).
Rejected as false positive: alias-collision test cannot fail (it runs with
`expand_aliases`; removing `unalias` or the `function` form fails it, mutation-checked).
Simplicity budget: CLI-only subcommands, no skill or agent context cost.
Pre-ship double-check: Claude Code's Bash-tool shell snapshot keeps functions, aliases
and options but not variables, so the rdf path and `--sandbox` choice are written into
function bodies (`_rdf_bin`, `cs`); a test sources a `declare -f` dump in a clean env.

## Not verified by this plan

Claude Code following a symlinked `projects/` for auto-memory writes under a non-default
`CLAUDE_CONFIG_DIR` needs a logged-in second account; checked in owner acceptance
(`c @<name>`, write a memory, confirm it lands under `~/.claude/projects`). Fallback if
it does not: the `autoMemoryDirectory` setting. Verified offline: CLI writes to a
symlinked `settings.json` under a non-default `CLAUDE_CONFIG_DIR` keep the link and
land in the shared file (`claude plugin install --scope user`, 2.1.308).
