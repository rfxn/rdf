# Core-Seam Reliability — Design Spec

**Date:** 2026-08-18 · **Tier:** full · **Status:** draft
**Pipeline:** spec → plan → build → ship

## 1. Problem Statement

Three structural seams in RDF's tooling layer have produced shipped defects in
every release since 3.6.0, and one of them is an unshipped data-loss bug:

1. **`rdf sync` can silently truncate canonical agent sources.**
   `lib/cmd/sync.sh:26-44` (`_strip_frontmatter`) is count-based: it emits
   nothing until it has seen two `---` lines. The agents loop
   (`sync.sh:66-96`) calls it unconditionally — no `head -1` check, no
   empty-body guard, both of which the commands loop (`sync.sh:98-132`)
   has. A frontmatter-less input therefore yields an empty body, which the
   loop writes over `canonical/agents/<name>.md`. The trigger is armed in
   production: both adapters (`adapters/claude-code/adapter.sh:103-110`,
   `adapters/claude-plugin/adapter.sh:115-124`) warn-and-continue with a
   plain copy when an agent is missing from `agent-meta.json`. Chain: add a
   7th agent, forget the meta entry, generate, later `rdf sync` → canonical
   source destroyed. `rdf sync` writes the source of truth and is the
   mandated emergency-fix pull-back path; it has exactly one BATS test
   (commands path only, `tests/deploy.bats:123`).

2. **State-helper delivery has broken in three consecutive releases.**
   Helpers are copy-deployed by `_generate_deploy_state_helpers`
   (`lib/cmd/generate.sh:44-68`) from a hard-coded 7-file list, called only
   in the `claude-code` branch of `cmd_generate` — not by `generate all`,
   not by `rdf deploy`, never for plugin installs. CHANGELOG evidence:
   3.6.1/3.6.2 "systemic state-helper paths … silently failed in every
   consuming project" + "pre-commit hook was never deployed"; 3.6.3
   "rdf-overhead.sh deployed copy mis-resolved RDF_HOME" + "plugin-only
   installs never receive the helpers — 10 commands ran degraded with no
   disclosure"; commit ccf4413 is a fourth patch on the same seam. Every
   failure was silent degradation. Plugin installs (the marketed consumer
   path) hard-stop at `/r-build` (`canonical/commands/r-build.md:22-24`)
   because the helpers never arrive.

3. **Frontmatter-strip logic exists in three divergent implementations.**
   sync's count-based loop (`sync.sh:28-44`), doctor's leading-anchored awk
   (`lib/cmd/doctor.sh:348-360`, the verified-correct semantics after the
   3.6.0 leading-only fix), and the adapters' emit-side blocks. The
   divergence *is* the P1 in item 1.

Related catalog fragility: hand-maintained metadata catalogs have shipped two
bugs (3.6.1 codex fabricated catalog; gemini staleness) and arm item 1
(missing `agent-meta.json` entry). No doctor check asserts catalog ↔
canonical consistency, and no check detects stale helper copies in
`~/.rdf/state/`.

## 2. Goals

1. `rdf sync` can never write an empty or truncated body over a canonical
   file: frontmatter-less inputs sync verbatim; unclosed-frontmatter inputs
   are skipped with a warning — on both the agents and commands paths.
2. Exactly one frontmatter-strip implementation exists
   (`rdf_strip_frontmatter` in `lib/rdf_common.sh`); sync and doctor both
   consume it; `_strip_frontmatter` is deleted.
3. `rdf generate claude-code` and `rdf generate claude-plugin` exit non-zero
   with an actionable message when any canonical agent lacks an
   `agent-meta.json` entry (preflight, both adapters).
4. State helpers are delivered by `rdf deploy claude-code` as per-file
   symlinks into `~/.rdf/state/` (glob-driven — no hard-coded list);
   `rdf generate` no longer writes anywhere under `$HOME`.
5. Plugin installs self-deliver state helpers: a SessionStart bootstrap
   script copies `state/*.sh` + `git-hooks/pre-commit` from the plugin root
   into `~/.rdf/state/`, version-stamped, idempotent, and a silent no-op when
   helpers are already symlinks (dev install wins).
6. `rdf doctor` gains `catalogs` and `state-helpers` scopes (11 → 13):
   catalog key mismatches and helper drift are surfaced instead of silent.
7. The 9 commands' plugin-tier absence guards and the `/r-build` hard-stop
   reflect the new reality (helpers bootstrap on plugin tier); the doc lines
   that state plugin installs lack state helpers are corrected.
8. All of the above is BATS-covered; the full suite passes on Debian 12 +
   Rocky 9 (and CI's macOS path is respected: bash 3.2, no `readlink -f`).

## 3. Non-Goals

- No deletion of `rotate-work-output.sh` or `command-meta-v3.json` (roadmap
  item 4 — adapter consolidation).
- No test coverage for `refresh.sh`, `profile.sh`, `github.sh` (separate
  test-debt item).
- No documentation overhaul beyond lines directly falsified by this change
  (roadmap item 2).
- No changes to codex/gemini adapters or their catalogs beyond doctor's
  read-only checks (gemini is frozen legacy).
- No whole-directory symlink of `~/.rdf/state` — `handoff/` inside it is a
  runtime write target (`canonical/scripts/precompact-snapshot.sh:12`).
- No new hooks beyond the one SessionStart bootstrap entry.

## 4. Architecture

### File Map

| File | Action | Est. Δ lines | Purpose |
|------|--------|-------------|---------|
| `lib/rdf_common.sh` | modify | +22 | add `rdf_strip_frontmatter()` (leading-anchored awk) |
| `lib/cmd/sync.sh` | modify | −18/+14 | delete `_strip_frontmatter`; both loops use shared fn; agents loop gains head-1 + empty-body guards |
| `lib/cmd/doctor.sh` | modify | −12/+100 | `_hash_deployed_body` consumes shared fn; add `_check_catalogs`, `_check_state_helpers`; register scopes (11→13); doc-stats expectations updated |
| `lib/cmd/generate.sh` | modify | −27 | remove `_generate_deploy_state_helpers` + its call site |
| `lib/cmd/deploy.sh` | modify | +45 | add `_deploy_state_helpers` (per-file symlink, glob, migration); call from `_deploy_claude_code`; usage text |
| `adapters/claude-code/adapter.sh` | modify | +2 | call `rdf_require_agent_meta` preflight in `cc_generate_all` |
| `adapters/claude-plugin/adapter.sh` | modify | +2 | same preflight call in `cpl_generate_all` (same meta file) |
| `state/rdf-overhead.sh` | modify | +6 | `.rdf-source` pointer fallback for `_rdf_home` (plugin installs) |
| `adapters/claude-code/hooks/hooks.json` | modify | +10 | SessionStart state-bootstrap entry (first, unmatched group) |
| `canonical/scripts/state-bootstrap.sh` | new | ~65 | plugin-tier helper delivery (SessionStart) |
| `canonical/commands/r-build.md` (+8 others, see §7) | modify | ~2 each | absence-guard wording: bootstrap-aware |
| `README.md`, `docs/quickstart.md`, `docs/multi-tool-parity.md` | modify | ~10 total | plugin-tier parity + doctor scope count |
| `tests/deploy.bats` | modify | rewrite 1 + add 5 | generate-fails-on-missing-meta ×2, helper-symlink deploy, migration, generate-no-HOME-write, stale-wording grep guard |
| `tests/sync.bats` | new | ~90 | agents-path guards, verbatim sync, unclosed-fm skip, hr preservation |
| `tests/strip.bats` | new | ~60 | `rdf_strip_frontmatter` unit cases |
| `tests/bootstrap.bats` | new | ~80 | state-bootstrap copy/stamp/no-op paths |
| `tests/doctor.bats` | modify | +2 tests | catalogs + state-helpers checks |
| `tests/overhead.bats` | modify | ~2 tests | re-validate deployed-copy resolution vs symlink + `.rdf-source` |
| `.github/workflows/ci.yml` | modify | +3 | macOS system-bash-3.2 smoke line for `state-bootstrap.sh` (mirrors rdf-bus.sh pattern) |
| `CHANGELOG`, `CHANGELOG.RELEASE` | modify | entries | per commit protocol |

### Size Comparison

| Metric | Before | After (est.) |
|--------|--------|--------------|
| Frontmatter-strip implementations | 3 | 1 |
| `lib/cmd/sync.sh` | 160 | ~156 |
| `lib/cmd/generate.sh` | 218 | ~191 |
| `lib/cmd/deploy.sh` | 327 | ~372 |
| `lib/cmd/doctor.sh` | 1096 | ~1184 |
| Hard-coded helper lists | 1 (7 files) | 0 (glob) |
| Doctor scopes | 11 | 13 |
| BATS tests | 222 | ~240 |

### Dependency Tree

```
bin/rdf
└── lib/rdf_common.sh          (rdf_strip_frontmatter — NEW, no deps beyond awk)
    ├── lib/cmd/sync.sh        (consumes rdf_strip_frontmatter)
    ├── lib/cmd/doctor.sh      (consumes rdf_strip_frontmatter;
    │                           _check_catalogs reads agent-meta.json,
    │                           skill-meta.json, canonical/ globs;
    │                           _check_state_helpers reads ~/.rdf/state,
    │                           $RDF_HOME/state)
    ├── lib/cmd/generate.sh    (no longer touches $HOME)
    │   ├── adapters/claude-code/adapter.sh    (calls rdf_require_agent_meta)
    │   └── adapters/claude-plugin/adapter.sh  (calls rdf_require_agent_meta,
    │                                           same meta file)
    └── lib/cmd/deploy.sh      (_deploy_state_helpers: $RDF_HOME/state/*.sh
                                → ~/.rdf/state/<f> symlinks)

SessionStart (hooks.json / plugin hooks.json)
└── canonical/scripts/state-bootstrap.sh
    reads:  <source-root>/state/*.sh, <source-root>/state/git-hooks/pre-commit,
            <source-root>/VERSION   (source-root derived from $0: ${0%/adapters/*}
            for plugin; ~/.claude/scripts symlink-resolution for checkout deploys
            is unnecessary — symlink case exits early)
    writes: ~/.rdf/state/<f> (copies), ~/.rdf/state/.rdf-version,
            ~/.rdf/state/.rdf-source
```

### Key Changes

1. **Strip convergence.** Doctor's awk (leading-anchored block + one blank
   separator) moves into `lib/rdf_common.sh` as `rdf_strip_frontmatter <file>`
   (stdout). Files not starting with `---` are emitted verbatim — the head-1
   guard becomes intrinsic. Sync's count-based function is deleted.
2. **Delivery ownership inversion.** `generate` builds only into
   `adapters/*/output/`. `deploy claude-code` owns `~/.rdf/state/` on
   checkout installs (symlinks track the checkout — drift is structurally
   impossible). The plugin loader + SessionStart bootstrap own it on plugin
   installs (copies + version stamp — drift is detected by stamp comparison
   and healed next session).
3. **Fail-fast catalogs.** Missing agent-meta is a generate error, not a
   warning; doctor cross-checks catalogs bidirectionally so the failure is
   visible even without running generate.

### Dependency Rules

- `rdf_strip_frontmatter` must be POSIX-awk only (macOS CI), bash-3.2-safe,
  and must not read stdin (file arg only — avoids consuming caller pipes).
- `state-bootstrap.sh` must follow the sibling deployed-hook contract
  exactly (`session-start-inject.sh` et al.): `set -euo pipefail` +
  `trap 'exit 0' EXIT` (never break a session), no output on the success
  path, jq-free.
- `_deploy_state_helpers` must never write inside the checkout and never
  touch `~/.rdf/state/handoff/` or any non-helper file.
- No new hard-coded file lists anywhere — helper enumeration is
  `"${RDF_HOME}/state/"*.sh` + `state/git-hooks/pre-commit`.

## 5. File Contents

### `lib/rdf_common.sh` (modified)

| Function | Signature | Purpose | Dependencies |
|----------|-----------|---------|--------------|
| `rdf_strip_frontmatter` | `(file)` → body on stdout | strip ONLY a leading `--- … ---` block + one following blank line; emit verbatim if line 1 is not `---` | awk |
| `rdf_require_agent_meta` | `(meta_file, agents_dir)` | loop `<agents_dir>/*.md`; collect basenames missing from `<meta_file>` keys; if any → `rdf_die "agents missing from agent-meta.json: <list> — add entries before generating"` | jq |

`rdf_strip_frontmatter` is doctor's existing awk (`doctor.sh:350-358`)
verbatim, parameterized on the file argument.

### `lib/cmd/sync.sh` (modified)

| Function | Current behavior | New behavior | Lines affected |
|----------|-----------------|--------------|----------------|
| `_strip_frontmatter` | count-based strip; empties frontmatter-less input | **deleted** | 26-44 |
| `cmd_sync` agents loop | unconditional strip, no guards; `echo "$body" >` | `head -1` == `---` → `rdf_strip_frontmatter` + empty-body skip-with-warn (mirrors commands loop); else verbatim body; write with `printf '%s\n'` | 66-96 |
| `cmd_sync` commands loop | own head-1 guard + `_strip_frontmatter` | same guard, calls `rdf_strip_frontmatter` | 98-132 |

Note: the agents-loop write also changes `echo "$body"` → `printf '%s\n' "$body"`
to match the commands loop (echo mangles backslash content on some shells).

### `lib/cmd/doctor.sh` (modified)

| Function | Signature | Purpose | Dependencies |
|----------|-----------|---------|--------------|
| `_hash_deployed_body` | `(deployed_file)` → hash | now `rdf_strip_frontmatter "$1" \| rdf_hash_stdin` | rdf_common |
| `_check_catalogs` | `()` | agent-meta keys vs `canonical/agents/*.md` basenames: missing entry → FAIL, orphan entry → WARN; `skill-meta.json` keys ⊆ `canonical/commands/*.md` basenames: orphan → WARN; gemini `command-meta.json` skipped (frozen legacy, noted as info) | jq, canonical globs |
| `_check_state_helpers` | `()` | for each `$RDF_HOME/state/*.sh` + git-hook: dest symlink → OK if target matches source (else WARN "points elsewhere"); dest real file → hash-compare, mismatch = FAIL "stale copy — re-run rdf deploy claude-code (checkout) or restart session (plugin)"; dest absent → WARN "run rdf deploy claude-code"; `.rdf-version` stamp present + ≠ `VERSION` → WARN | rdf_hash_stdin |

Runner: both checks registered in `_doctor_one`'s scope case-statement
(`doctor.sh:933-963`) and the `--all` scope list. `_check_doc_stats` today
verifies command/agent/adapter counts only — it has NO assertion on the
doctor scope count, and this spec adds none (scoped out): the prose
"11 checks" claims in README.md and any sibling docs are hand-updated to 13
in the same commit, verified by the pre-commit grep in §10b.

### `lib/cmd/generate.sh` (modified)

| Function | Current behavior | New behavior | Lines affected |
|----------|-----------------|--------------|----------------|
| `_generate_deploy_state_helpers` | copies 7 hard-coded helpers + hook to `~/.rdf/state` | **deleted** | 41-68 |
| `cmd_generate` claude-code branch | calls the above after adapter run | call removed; usage text unchanged except removing the implicit-HOME-write behavior | 111 |

### `lib/cmd/deploy.sh` (modified)

| Function | Signature | Purpose | Dependencies |
|----------|-----------|---------|--------------|
| `_deploy_state_helpers` | `(dry_run, force)` | `command mkdir -p ~/.rdf/state`; for each `"${RDF_HOME}/state/"*.sh`: **NEW migration pre-step** — if dest is a real file byte-identical to source (`diff -q`), remove it so the copy-deploy install upgrades without `--force` friction (machine-managed content, nothing lost); then `_deploy_symlink` to `~/.rdf/state/<basename>` (existing semantics: differing real file → skip-with-warn, `--force` → backup + replace); plus `state/git-hooks/pre-commit` → `~/.rdf/state/git-hooks/pre-commit` | `_deploy_symlink`, diff |
| `_deploy_claude_code` | deploys 4 symlink dirs, skips hooks | additionally calls `_deploy_state_helpers "$dry_run" "$force"` | 186-200 |

The byte-identical pre-step is new logic in `_deploy_state_helpers` (NOT
existing `_deploy_symlink` behavior, which skips any real file without
`--force`): every existing copy-deploy install has identical copies (or stale
ones — those warn and are caught by doctor FAIL), so `rdf deploy claude-code`
upgrades them to symlinks without `--force` friction while never destroying
user-modified files.

### `adapters/claude-code/adapter.sh` (modified)

| Function | Current behavior | New behavior | Lines affected |
|----------|-----------------|--------------|----------------|
| `cc_generate_all` | preflights meta file existence only | adds `rdf_require_agent_meta "$_CC_AGENT_META" "${RDF_CANONICAL}/agents"` after `rdf_require_file` | ~285 |

The per-agent warn+plain-copy branch in `cc_generate_agents` is kept as
unreachable defense (preflight guarantees it cannot fire).

### `adapters/claude-plugin/adapter.sh` (modified)

| Function | Current behavior | New behavior | Lines affected |
|----------|-----------------|--------------|----------------|
| `cpl_generate_all` | no meta preflight | adds `rdf_require_agent_meta "${RDF_ADAPTERS}/claude-code/agent-meta.json" "${RDF_CANONICAL}/agents"` | ~246 |

The preflight lives in `lib/rdf_common.sh` (see its table) so both adapters
call the same function with explicit args — no cross-adapter sourcing.

### `canonical/scripts/state-bootstrap.sh` (new)

| Function | Signature | Purpose | Dependencies |
|----------|-----------|---------|--------------|
| (main) | hook entry, no args | 1. `trap 'exit 0'` guard style of sibling hooks. 2. Resolve source root: `root="${0%/adapters/*}"`; sanity: `[[ -d "$root/state" ]] \|\| exit 0`. 3. If `~/.rdf/state/rdf-bus.sh` is a symlink → exit 0 (checkout deploy owns). 4. If `~/.rdf/state/.rdf-version` exists and equals `$root/VERSION` content → exit 0 (current). 5. `command mkdir -p ~/.rdf/state/git-hooks`; copy `"$root"/state/*.sh` and `git-hooks/pre-commit` (skip any dest that is a symlink); `command chmod +x` copies. 6. Write `VERSION` content to `.rdf-version` and `$root` to `.rdf-source`. Silent on success. | coreutils only (jq-free) |

Wired in `adapters/claude-code/hooks/hooks.json` SessionStart unmatched group,
**before** `session-start-inject.sh`. `cpl_generate_hooks` rewrites the path
automatically (existing `~/.claude/scripts/` → plugin-root transform). On
checkout installs the same hook runs from `~/.claude/scripts/` (post manual
merge) and exits at step 3.

### `state/rdf-overhead.sh` (modified)

| Function | Current behavior | New behavior | Lines affected |
|----------|-----------------|--------------|----------------|
| (top-level `_rdf_home` resolution) | env → script-dir parent → deploy-symlink readlink recovery → warn | before the warn, read `~/.rdf/state/.rdf-source` (if file exists and its content is a dir with `adapters/claude-code`) as final fallback; warn retained | 19-32 |

## 5b. Examples

**Generate refuses on missing agent metadata:**
```
$ ./bin/rdf generate claude-code        # after adding canonical/agents/sentinel.md
rdf: generating Claude Code adapter output...
rdf: error: agents missing from agent-meta.json: sentinel — add entries before generating
$ echo $?
1
```

**Deploy delivers helpers as symlinks (fresh + migration):**
```
$ ./bin/rdf deploy claude-code
rdf: deploying Claude Code adapter to /home/u/.claude...
rdf: symlinked: /home/u/.claude/agents -> .../adapters/claude-code/output/agents
...
rdf: symlinked: /home/u/.rdf/state/rdf-bus.sh -> .../state/rdf-bus.sh
rdf: symlinked: /home/u/.rdf/state/git-hooks/pre-commit -> .../state/git-hooks/pre-commit
rdf: skipped: hooks.json (manual merge — see 'rdf deploy help')
rdf: deploy complete: 13 items deployed
```

**Sync no longer truncates (before/after):**
```
# Before (3.6.3): output/agents/sentinel.md has no frontmatter
$ rdf sync            # canonical/agents/sentinel.md → EMPTY (data loss)
# After:
$ ./bin/rdf sync
rdf: syncing from claude-code adapter output to canonical...
rdf: sync complete: 0 updated, 44 unchanged      # verbatim body == canonical
```

**Doctor surfaces a stale helper copy (failure case):**
```
$ ./bin/rdf doctor
...
[state-helpers] [FAIL] rdf-state.sh: deployed copy is stale — re-run
  'rdf deploy claude-code' (checkout install) or restart your session
  (plugin install)
```

## 6. Conventions

- All new shell follows workspace standards: `command` prefix on coreutils,
  guarded `cd`, `printf` over `echo` for variable bodies, suppression
  comments on the same line, bash-3.2-compatible (no `${var,,}`, no
  `readlink -f`, no `declare -A`).
- Doctor check functions follow the existing `_check_<scope>` naming, OK/
  WARN/FAIL counters, and remediation-hint message style.
- Hook script follows sibling conventions (`session-start-inject.sh`):
  silent success, bounded work, exit 0 always.
- BATS files follow existing harness (`tests/helpers.bash` if present, else
  scratch `HOME` via `mktemp -d`, bare coreutils per test rules).

## 7. Interface Contracts

- **`rdf generate <target>`** — no longer writes under `$HOME` (contract now
  matches its usage text "output is written to adapters/<target>/output/").
  New failure mode: exit 1 on missing agent-meta entries.
- **`rdf deploy claude-code`** — now also owns `~/.rdf/state/` helper
  symlinks. `--dry-run`/`--force` semantics unchanged and apply to helpers.
- **`~/.rdf/state/` layout** — helpers are symlinks (checkout install) or
  copies + `.rdf-version`/`.rdf-source` stamps (plugin install). `handoff/`
  and any other runtime content untouched.
- **`rdf doctor`** — two new scopes: `catalogs`, `state-helpers`; `--all`
  count 13. Exit semantics unchanged (FAIL ⇒ non-zero under existing rules).
- **hooks.json** — one added SessionStart command entry; manual-merge story
  for checkout installs unchanged; plugin auto-registration unchanged.
- **Commands (canonical)** — the 9 files with absence guards (r-status,
  r-build, r-vpe, r-refresh, r-ship, r-plan, r-save, r-spec,
  r-util-mem-compact) keep the guard, reworded: absence now means "bootstrap
  hasn't run yet" → remediation "restart session (plugin) or
  `rdf deploy claude-code` (checkout)". `/r-build` hard-stop message updated
  identically. CLI surface (bin/rdf flags): unchanged.

## 8. Migration Safety

- **Upgrade (checkout installs):** next `rdf deploy claude-code` replaces
  byte-identical helper copies with symlinks automatically; differing copies
  are skipped-with-warn (recoverable via `--force`, which backs up first) and
  flagged FAIL by doctor. No action lost; `rdf generate claude-code` alone no
  longer refreshes helpers, but symlinks make refresh unnecessary — a
  CHANGELOG upgrade note states "run `rdf deploy claude-code` once after
  updating."
- **Upgrade (plugin installs):** first SessionStart after the plugin update
  copies current helpers and stamps `.rdf-version`; the 10 formerly-degraded
  commands begin working with no user action.
- **Fresh install:** quickstart flow (`generate` → `deploy`) yields symlinked
  helpers; plugin flow yields bootstrap copies. Both verified by BATS.
- **Rollback:** removing the symlinks or the plugin restores pre-3.7 behavior;
  `.rdf-version`/`.rdf-source` are inert stamps. No data format changes.
- **Uninstall:** unchanged (no uninstall path exists for `~/.rdf/state` today;
  not in scope).
- **Test suite impact:** `tests/deploy.bats:146` ("generate deploys state
  helpers") inverts to deploy-owned; rdf-overhead deployed-copy tests
  (3.6.3, 2 cases) re-validated against symlink + `.rdf-source` resolution.

## 9. Dead Code and Cleanup

| Finding | Location | Action |
|---------|----------|--------|
| `_strip_frontmatter` | `sync.sh:26-44` | deleted (goal 2) |
| `_generate_deploy_state_helpers` | `generate.sh:41-68` | deleted (goal 4) |
| `rotate-work-output.sh` orphan, `command-meta-v3.json` dead catalog | `state/`, `adapters/claude-code/` | out of scope — roadmap item 4 (noted, not touched; rotate-work-output continues to ride the glob harmlessly) |

## 10a. Test Strategy

| Goal | Test file | Test description |
|------|-----------|-----------------|
| 1 | `tests/sync.bats` | `@test "sync agents: frontmatter-less output syncs verbatim (no truncation)"` |
| 1 | `tests/sync.bats` | `@test "sync agents: unclosed frontmatter skipped with warning, canonical untouched"` |
| 1 | `tests/sync.bats` | `@test "sync agents: frontmatter stripped, body --- rules preserved, round-trip clean"` |
| 2 | `tests/strip.bats` | `@test "rdf_strip_frontmatter: leading block + blank stripped"` / `"no frontmatter → verbatim"` / `"body hr preserved"` / `"unclosed → empty output"` |
| 2 | `tests/strip.bats` | `@test "single strip implementation: sync.sh defines no local strip"` (grep guard) |
| 3 | `tests/deploy.bats` | `@test "generate claude-code fails listing agents missing from agent-meta"` |
| 3 | `tests/deploy.bats` | `@test "generate claude-plugin fails on same missing agent-meta"` |
| 4 | `tests/deploy.bats` | `@test "deploy claude-code symlinks state helpers per-file (glob)"` |
| 4 | `tests/deploy.bats` | `@test "deploy migrates byte-identical helper copies to symlinks; differing copy skipped"` |
| 4 | `tests/deploy.bats` | `@test "generate claude-code writes nothing under HOME"` |
| 5 | `tests/bootstrap.bats` | `@test "bootstrap copies helpers + stamps version from plugin-root layout"` |
| 5 | `tests/bootstrap.bats` | `@test "bootstrap no-ops when helpers are symlinks"` / `"no-ops when stamp current"` / `"exits 0 on unwritable HOME"` |
| 6 | `tests/doctor.bats` | `@test "doctor catalogs: missing agent-meta entry FAILs, orphan WARNs"` |
| 6 | `tests/doctor.bats` | `@test "doctor state-helpers: stale copy FAILs, symlink OKs, absent WARNs"` |
| 7 | `tests/deploy.bats` | `@test "no canonical command retains 'plugin-only install' stop wording"` (grep guard) |
| 8 | (suite) | full run Debian 12 + Rocky 9 before commit; matrix before push |

## 10b. Verification Commands

```bash
# Goal 1/2 — one strip implementation, guards present
grep -c '^_strip_frontmatter()' lib/cmd/sync.sh
# expect: 0   (function definition gone; rdf_strip_frontmatter call sites remain)
grep -c 'rdf_strip_frontmatter' lib/rdf_common.sh lib/cmd/sync.sh lib/cmd/doctor.sh | awk -F: '$2==0'
# expect: (no output — every file has ≥1 hit)

# Goal 1 — truncation regression (scratch harness, also in BATS)
# frontmatter-less agent output + rdf sync → canonical body unchanged
bash tests/infra/… (BATS) — tests/sync.bats
# expect: all sync.bats tests ok

# Goal 3 — generate hard-fail
jq 'del(.dispatcher)' adapters/claude-code/agent-meta.json > /tmp/m.json && \
  RDF_AGENT_META_OVERRIDE=… ./bin/rdf generate claude-code; echo $?
# expect: stderr lists "dispatcher", exit 1   (BATS does this with a scratch checkout)

# Goal 4 — deploy-owned symlinks, generate HOME-clean
HOME=$(mktemp -d) ./bin/rdf generate claude-code && find "$HOME" -type f | wc -l
# expect: 0
HOME=$(mktemp -d) ./bin/rdf generate claude-code >/dev/null && \
  HOME="$HOME" ./bin/rdf deploy claude-code >/dev/null && \
  find "$HOME/.rdf/state" -maxdepth 1 -type l | wc -l
# expect: 7   (state/*.sh helpers; git-hooks/pre-commit is one level deeper)

# Goal 5 — bootstrap
HOME=$(mktemp -d) bash canonical/scripts/state-bootstrap.sh   # invoked via a
# plugin-root-shaped $0 path in BATS; expect: helpers copied, .rdf-version == VERSION

# Goal 6 — doctor scopes
./bin/rdf doctor --all 2>&1 | grep -c '^\[state-helpers\]\|^\[catalogs\]'
# expect: >= 2

# Goal 7 — no stale wording
grep -rln 'plugin-only install' canonical/commands/ | wc -l
# expect: 0   (superseded wording removed; guards reworded)
grep -rn '11 checks' README.md docs/ RDF.md WORKFORCE.md
# expect: (no output — scope-count prose updated to 13)

# Goal 8 — suite
make -C tests test 2>&1 | tee /tmp/test-rdf-seam-debian12.log | tail -3
# expect: exit 0, "not ok" count 0
```

## 11. Risks

1. **Existing tests encode copy-deploy semantics** (deploy.bats:146,
   overhead tests). *Mitigation:* those tests are rewritten in the same
   phase as the behavior change; suite runs before every commit.
2. **Users with locally-edited helper copies** would lose edits on blind
   overwrite. *Mitigation:* non-`--force` deploy never replaces a differing
   real file (skip-with-warn + doctor FAIL); `--force` backs up first;
   bootstrap only overwrites when the version stamp differs and never
   touches symlinks.
3. **`${0%/adapters/*}` source-root derivation fails if the plugin path
   itself contains `/adapters/`** elsewhere. *Mitigation:* prefix-strip at
   the FIRST match plus `[[ -d "$root/state" ]]` sanity; on failure exit 0
   (helpers arrive via next checkout deploy or a later session; commands'
   absence guards still disclose).
4. **Doc claims of "11 checks" go stale** (README.md and siblings; doctor
   itself has no machine assertion on its scope count). *Mitigation:* all
   scope-count prose updated to 13 in the same commit; §10b adds a grep
   verification (`grep -rn '11 checks' README.md docs/` → no output).
5. **macOS/bash-3.2 regressions** (no `readlink -f`, no `ln --relative`).
   *Mitigation:* plain `readlink`, absolute-path `ln -snf` (existing
   `_deploy_symlink` is already portable); CI macOS job gates push.
6. **Hook ordering:** bootstrap must complete before commands probe
   `~/.rdf/state`. SessionStart hooks run before the first user turn, so any
   `/r-*` command in the session sees the helpers. *Mitigation:* bootstrap is
   listed first in the SessionStart group; worst case (mid-session plugin
   update) is the pre-existing degraded path with accurate wording.

## 11b. Edge Cases

| Scenario | Expected behavior | Handling |
|----------|-------------------|---------|
| Agent output file with no frontmatter (legacy plain copy) | sync writes verbatim body, never empty | head-1 guard: not `---` → verbatim |
| Output file with opening `---` but no closing | sync skips file, warns, canonical untouched | empty-body guard on both loops |
| Body contains `---` horizontal rules | only leading block stripped; hrs preserved byte-for-byte | leading-anchored awk |
| `~/.rdf/state` holds stale real-file copies (3.6.x install) | differing file: skip + warn + doctor FAIL; identical file: silently upgraded to symlink | `_deploy_state_helpers` migration rule |
| Plugin + checkout deploy coexist on one machine | bootstrap sees symlinks → exits; checkout wins | symlink probe, step 3 |
| Bootstrap on read-only/unwritable `$HOME` | silent exit 0, session unaffected | trap/guard contract |
| `rdf deploy --dry-run claude-code` | helper actions logged as `[dry-run]`, nothing written | `_deploy_symlink` dry-run passthrough |
| Canonical agent deleted but meta entry remains | generate succeeds; doctor WARNs orphan entry | `_check_catalogs` direction 2 |
| Canonical agent added without meta entry | generate exits 1 naming it; doctor FAILs | `rdf_require_agent_meta` + `_check_catalogs` |
| `RDF_TARGET` set (test harness) | `~/.claude` targets honor it; `~/.rdf/state` remains `$HOME`-scoped (helpers are per-user, not per-target) | explicit in `_deploy_state_helpers` |
| `generate all` / `generate claude-plugin` | write nothing under `$HOME` (previously claude-code branch wrote helpers) | deletion of generate-side deploy |
| Session starts before plugin fully synced / VERSION file missing at root | sanity check fails → exit 0, retry next session | step 2 sanity |

## 12. Open Questions

None — all design decisions recorded in the session progress file
(`spec-progress-01a01618…md`) with rationale.
