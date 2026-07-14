# Claude Code Plugin Citizenship — Design Spec

Date: 2026-07-14
Status: draft
Pipeline: spec → plan → build → ship

## 1. Problem Statement

RDF ships a `.claude-plugin/plugin.json` (23 lines) but is not installable
as a Claude Code plugin. Verified against current platform docs
(code.claude.com/docs — plugins-reference, plugin-marketplaces, skills):

- The plugin loader resolves `commands/`, `agents/`, `hooks/` from the
  plugin root by default. RDF's Claude Code content lives in
  `adapters/claude-code/output/` — the loader finds nothing.
- `adapters/claude-code/output/hooks.json` references
  `~/.claude/scripts/*.sh` in 4 places: 3 command hooks (PreToolUse,
  PostToolUse, SubagentStop) plus the top-level `statusLine` key — a
  sibling of `"hooks"`, not inside it. Plugin hooks MUST reference scripts
  via `${CLAUDE_PLUGIN_ROOT}` — the current file breaks under plugin
  install.
- `adapters/claude-code/output/` contains `.rdf-hash` sidecar files
  (37 command + 6 agent) that would ship into the plugin component set
  and trip `claude plugin validate --strict`.
- Canonical command content contains 223 `/r-*` cross-references across
  41 files (e.g. `/r-spec` hands off to `/r-plan`). Plugin commands are
  ALWAYS namespaced (`/rdf:r-start` — no bare invocation, verified); un-
  rewritten references would point at commands that do not exist in a
  plugin install.
- No `.claude-plugin/marketplace.json` exists — `/plugin marketplace add
  rfxn/rdf` has nothing to add.
- `plugin.json` (23 lines) `version` (3.2.1, manually maintained) has no
  wiring to `VERSION`. If it is not bumped per release, plugin users silently
  freeze on the old version (verified platform behavior).

Distribution goal: `/plugin marketplace add rfxn/rdf` +
`/plugin install rdf@rdf`, validated in CI, submitted to
`anthropics/claude-plugins-community`.

## 2. Goals

1. `claude plugin validate . --strict` passes at repo root (plugin AND
   marketplace schema).
2. A new `claude-plugin` adapter target generates plugin-shaped output:
   `rdf generate claude-plugin` produces `adapters/claude-plugin/output/`
   containing commands (cross-refs rewritten `/r-X` → `/rdf:r-X`), agents
   (no hash sidecars), scripts, and a `${CLAUDE_PLUGIN_ROOT}`-relative
   `hooks.json`.
3. `plugin.json` version is stamped from `VERSION` at generate time; a
   BATS test fails when they drift.
4. `.claude-plugin/marketplace.json` declares the repo as its own
   marketplace (`source: "./"`) named `rdf`.
5. `rdf doctor` detects the install mode (symlink / plugin / both) and
   WARNs with guidance on dual-install.
6. `rdf deploy claude-code` WARNs when an RDF plugin install is present.
7. CI gains a plugin job: generate `claude-plugin`, fail on uncommitted
   output drift, run `claude plugin validate . --strict`.
8. Existing symlink deploy behavior is byte-identical to today — bare
   `/r-*` commands preserved; zero migration required for current users.

## 3. Non-Goals

- Deprecating or altering symlink deploy — it remains the documented
  contributor/power-user mode.
- Converting commands to skills (`SKILL.md`) — commands stay commands.
- Plugin equivalents for gemini-cli / codex adapters.
- Automated submission to the community marketplace (manual form, once,
  after CI is green).
- Renaming agents to role-only names in plugin output — plugin agents
  keep `rdf-{stem}` frontmatter names (surfaced as `rdf:rdf-dispatcher`);
  avoids rewriting agent-name references inside command content. Cosmetic
  revisit deferred.
- Rewriting anything in `canonical/` — the namespace transform is
  generate-time only.

## 4. Architecture

### File Map

| File | Action | Est. lines | Purpose |
|------|--------|-----------|---------|
| `adapters/claude-plugin/adapter.sh` | new | ~210 | `cpl_*` generation functions (template: claude-code/adapter.sh, 235) |
| `adapters/claude-plugin/output/commands/*.md` | generated (committed) | 37 files | namespace-rewritten commands |
| `adapters/claude-plugin/output/agents/*.md` | generated (committed) | 6 files | agents without hash sidecars |
| `adapters/claude-plugin/output/scripts/*.sh` | generated (committed) | 12 files | hook + utility scripts |
| `adapters/claude-plugin/output/hooks.json` | generated (committed) | ~40 | `${CLAUDE_PLUGIN_ROOT}` paths |
| `.claude-plugin/marketplace.json` | new | ~15 | repo-as-marketplace declaration |
| `.claude-plugin/plugin.json` | modified | 23→~28 | component paths + stamped version |
| `lib/cmd/generate.sh` | modified | 152→~170 | `claude-plugin` target case (+ in `all`) |
| `lib/cmd/deploy.sh` | modified | 283→~295 | plugin-presence warning in `_deploy_claude_code()` |
| `lib/cmd/doctor.sh` | modified | 909→~950 | `_check_install_mode()` |
| `.github/workflows/ci.yml` | modified | 116→~145 | plugin job |
| `tests/plugin-adapter.bats` | new | ~120 | adapter output + version-sync + transform tests |
| `README.md` | modified | ~+15 | plugin install path in Quick Start / §3 |
| `docs/quickstart.md` | modified | ~+12 | plugin install as consumer path |
| `ROADMAP.md` | modified | ±0 | check off H2 items |

### Size Comparison

| Surface | Before | After |
|---------|--------|-------|
| Adapters | 4 | 5 |
| Committed output files | 105 (cc: 56 content + 43 sidecars + 6 governance) | 105 + 56 (plugin: content only, no sidecars) |
| CI jobs | 4 | 5 |
| Install modes | 1 (symlink) | 2 (symlink primary, plugin consumer) |

Committed-output tradeoff: generating plugin output ephemerally (CI-only,
uncommitted) was considered and rejected — plugin installs clone the repo
directly, so the tree GitHub serves must contain the output. Committing
matches the existing convention for all 4 adapters.

### Dependency Tree

```
bin/rdf
└── lib/cmd/generate.sh          cmd_generate "claude-plugin"
    └── adapters/claude-plugin/adapter.sh   (sourced)
        └── cpl_generate_all                 entry point — calls, in order:
            ├── cpl_generate_commands        reads canonical/commands/  + rewrite
            ├── cpl_generate_agents          reads canonical/agents/    (frontmatter, no sidecars)
            ├── cpl_generate_scripts         reads canonical/scripts/
            ├── cpl_generate_hooks           reads adapters/claude-code/hooks/hooks.json + transform
            └── cpl_stamp_plugin_version     reads VERSION → jq-writes .claude-plugin/plugin.json
lib/cmd/doctor.sh    _check_install_mode()  reads ~/.claude/commands symlink +
                                            jq lookup of "rdf@rdf" in ~/.claude/plugins/installed_plugins.json
lib/cmd/deploy.sh    _deploy_claude_code()  same installed_plugins.json probe before symlinking
.github/workflows/ci.yml  plugin job → bin/rdf generate claude-plugin → git diff → claude plugin validate
```

### Key Changes

1. **Fifth adapter, same contract.** `adapters/claude-plugin/adapter.sh`
   exposes `cpl_generate_all`, wired into `cmd_generate` exactly like the
   existing four (`_generate_adapter "claude-plugin/adapter.sh"
   "cpl_generate_all"`). Output committed, mirroring existing adapters.
2. **Namespace transform at generate time.** `/r-X` → `/rdf:r-X` applied
   to command bodies only, only for names in the actual command inventory,
   only when preceded by start-of-line, whitespace, backtick, `(`, or `|`
   (prevents rewriting file paths like `canonical/commands/r-spec.md`).
3. **Hooks transform.** Every `"command"`-valued field matching
   `~/.claude/scripts/` — ANYWHERE in the file, including the top-level
   `statusLine` key (a sibling of `"hooks"`), not just entries under
   `.hooks` — rewrites to
   `"${CLAUDE_PLUGIN_ROOT}"/adapters/claude-plugin/output/scripts/NAME.sh`
   (4 occurrences today: PreToolUse, PostToolUse, SubagentStop,
   statusLine). Non-command hooks (PreCompact `prompt` type) copy through
   untouched.
4. **Version stamping.** Generation rewrites `.claude-plugin/plugin.json`
   `.version` from `${RDF_VERSION}` via `jq` (already a hard dependency).
5. **Install-mode awareness.** Detection reads the authoritative manifest
   `~/.claude/plugins/installed_plugins.json` for the key `rdf@rdf`
   (`jq -e '.plugins | has("rdf@rdf")'`) — NOT the `plugins/cache/` tree,
   which contains entries for unrelated plugins and may retain stale
   dirs after uninstall. Doctor matrix: symlink-only → OK; plugin-only →
   OK (sync checks N/A); both → WARN "dual install: /r-start and
   /rdf:r-start both active — pick one". Missing manifest file → not
   plugin-installed (no error).

### Dependency Rules

- `adapter.sh` files never source each other; the plugin adapter READS
  `adapters/claude-code/hooks/hooks.json` as data (single hooks source of
  truth) but sources nothing from it.
- Generated output never references repo-absolute or `~`-absolute paths —
  `${CLAUDE_PLUGIN_ROOT}` only.
- `canonical/` is read-only input to generation. No transform writes back.

## 5. File Contents

### `adapters/claude-plugin/adapter.sh` (new)

| Function | Signature | Purpose | Dependencies |
|----------|-----------|---------|--------------|
| `_cpl_rewrite_namespace()` | (src_file, dst_file) | sed-rewrite `/r-X` → `/rdf:r-X` for known command names with boundary guard | command inventory from `canonical/commands/*.md` |
| `cpl_generate_commands()` | () | emit 37 rewritten commands to `output/commands/` | `_cpl_rewrite_namespace()` |
| `cpl_generate_agents()` | () | emit 6 agents with CC frontmatter, NO `.rdf-hash` sidecars | frontmatter builder (shared pattern from cc `_cc_agent_frontmatter`, duplicated — adapters do not cross-source) |
| `cpl_generate_scripts()` | () | copy `canonical/scripts/*.sh`, chmod +x, same profile filter as cc | `rdf_profile_includes()` |
| `cpl_generate_hooks()` | () | read cc `hooks/hooks.json`, transform script paths to `${CLAUDE_PLUGIN_ROOT}`, write `output/hooks.json` | jq |
| `cpl_stamp_plugin_version()` | () | `jq '.version = $v'` into `.claude-plugin/plugin.json` | `RDF_VERSION`, jq |
| `cpl_generate_all()` | () | run all of the above, log summary | all above |

### `.claude-plugin/marketplace.json` (new)

```json
{
  "name": "rdf",
  "owner": { "name": "R-fx Networks", "email": "proj@rfxn.com" },
  "metadata": { "description": "RDF — governance-driven AI development" },
  "plugins": [
    {
      "name": "rdf",
      "source": "./",
      "description": "Convention governance, quality gates, and typed agent personas"
    }
  ]
}
```

### `.claude-plugin/plugin.json` (modified)

| Field | Current | New |
|-------|---------|-----|
| `version` | hand-maintained | stamped from `VERSION` by generate |
| `commands` | absent | `"./adapters/claude-plugin/output/commands"` |
| `agents` | absent | `"./adapters/claude-plugin/output/agents"` |
| `hooks` | absent | `"./adapters/claude-plugin/output/hooks.json"` |

### Modified functions

| File | Function | Current behavior | New behavior | Lines affected |
|------|----------|------------------|--------------|----------------|
| `lib/cmd/generate.sh` | `cmd_generate()` | 4 target cases + `all` | +`claude-plugin` case; `all` loop includes it | 68-152 |
| `lib/cmd/generate.sh` | `_generate_usage()` | lists 4 targets | lists 5 | 7-33 |
| `lib/cmd/deploy.sh` | `_deploy_claude_code()` | symlinks 4 items | first checks `jq -e '.plugins | has("rdf@rdf")'` on `${HOME}/.claude/plugins/installed_plugins.json` (absent file = not installed) → `rdf_warn` dual-install, proceed | 164-186 |
| `lib/cmd/doctor.sh` | `_doctor_one()` | 8 checks | +`_check_install_mode` in default scope | 753-777 |
| `lib/cmd/doctor.sh` | `_check_install_mode()` (new) | — | detect symlink (via existing link probe) + `installed_plugins.json` manifest lookup for `rdf@rdf`; OK/OK/WARN matrix | +~35 |
| `.github/workflows/ci.yml` | `plugin` job (new) | — | generate claude-plugin → `git diff --exit-code adapters/claude-plugin/output .claude-plugin/plugin.json` → npm i -g claude CLI → `claude plugin validate . --strict` | +~28 |

## 5b. Examples

Consumer install (Claude Code):

```
/plugin marketplace add rfxn/rdf
/plugin install rdf@rdf
# commands now available as /rdf:r-start, /rdf:r-spec, ...
```

Generation:

```
$ bin/rdf generate claude-plugin
rdf: generating Claude Plugin adapter output...
rdf: generated 37 command files (namespace-rewritten)
rdf: generated 6 agent files
rdf: generated 12 script files
rdf: generated hooks.json (plugin-root paths)
rdf: stamped plugin.json version: 3.2.1
rdf: plugin generation complete
```

Transform before/after (`canonical/commands/r-spec.md` →
`output/commands/r-spec.md`):

```
before:  Run `/r-plan` to create the implementation plan.
after:   Run `/rdf:r-plan` to create the implementation plan.
```

hooks.json before/after:

```
before:  "command": "~/.claude/scripts/pre-commit-validate.sh"
after:   "command": "\"${CLAUDE_PLUGIN_ROOT}\"/adapters/claude-plugin/output/scripts/pre-commit-validate.sh"
```

Dual-install failure case (`rdf doctor`):

```
  [install-mode]   [WARN]  both symlink deploy and plugin install detected —
                           /r-start and /rdf:r-start are both active; remove one
                           (rdf deploy help | /plugin uninstall rdf@rdf)
```

## 6. Conventions

- Adapter function prefix: `cpl_` (matches `cc_`/`gem_`/`cdx_`/`amd_`).
- Output layout mirrors `adapters/claude-code/output/` minus `governance/`
  (consumed by rdf CLI + project-local `.rdf/governance/`, not the plugin
  loader) and minus hash sidecars.
- All coreutils `command`-prefixed; `jq` via `rdf_require_bin jq`.
- Namespace rewrite pattern (single source of truth inside
  `_cpl_rewrite_namespace`): for each known command name `N`,
  `s/(^|[[:space:]\`(|])\/${N}\b/\1\/rdf:${N}/g` — names sorted
  longest-first so `/r-util-mem-compact` rewrites before `/r-util-mem`
  could partially match.

## 7. Interface Contracts

- `rdf generate claude-plugin` — new CLI target (additive; existing
  targets unchanged).
- `.claude-plugin/plugin.json` — gains `commands`/`agents`/`hooks` fields;
  `version` becomes generated. Schema per plugins-reference (verified).
- `.claude-plugin/marketplace.json` — new; schema per plugin-marketplaces
  (verified; `rdf` not on the reserved-names list).
- `rdf doctor` output — new `install-mode` check category (additive).
- No changes to: symlink deploy paths, canonical content format, existing
  adapter outputs, `rdf` CLI existing arguments.

## 8. Migration Safety

- **Fresh install (first-time plugin consumer):** `/plugin marketplace
  add rfxn/rdf` requires `marketplace.json` + stamped `plugin.json` on
  `main` — both land in the same commit as the generated output, so
  there is no window where the marketplace is addable but the plugin is
  broken. Installing onto a machine with a pre-existing stale symlink
  deploy triggers the dual-install WARN path (§11b row 1).
- **Existing symlink users:** zero change — Goal 8 is byte-identical
  deploy behavior; verification via before/after diff of `~/.claude`
  symlink targets.
- **Upgrade path:** none required. New adapter output appears on next
  `git pull` + generate; plugin fields ignored by symlink flow.
- **Plugin update path:** version stamping means every release bumps
  `plugin.json` → plugin users receive updates. Un-bumped `VERSION` =
  frozen plugin users; guarded by BATS + CI drift check.
- **Rollback:** delete `adapters/claude-plugin/`, `marketplace.json`,
  revert `plugin.json` fields, drop CI job. No state to unwind.
- **Uninstall:** `/plugin uninstall rdf@rdf` (platform-managed cache);
  symlink mode untouched.

## 9. Dead Code and Cleanup

None found in scope. (`adapters/claude-code/teams-meta.json` predates
this work and is tracked under 3.2 T5 debt cleanup — not touched here.)

## 10a. Test Strategy

New file `tests/plugin-adapter.bats` (harness pattern from
`tests/adapter.bats` `_generate()`):

| Goal | Test file | Test description |
|------|-----------|-----------------|
| 1 | CI job (not BATS) | `claude plugin validate . --strict` exits 0 |
| 2 | tests/plugin-adapter.bats | `@test "claude-plugin generates 37 commands, 6 agents, 12 scripts, hooks.json"` |
| 2 | tests/plugin-adapter.bats | `@test "plugin commands rewrite /r-X cross-refs to /rdf:r-X"` |
| 2 | tests/plugin-adapter.bats | `@test "plugin command rewrite does not touch path-like r- strings"` |
| 2 | tests/plugin-adapter.bats | `@test "plugin agents ship no .rdf-hash sidecars"` |
| 2 | tests/plugin-adapter.bats | `@test "plugin hooks.json uses CLAUDE_PLUGIN_ROOT, never ~/.claude"` |
| 3 | tests/plugin-adapter.bats | `@test "generate stamps plugin.json version from VERSION"` |
| 4 | tests/plugin-adapter.bats | `@test "marketplace.json declares plugin rdf with source ./"` |
| 5 | tests/plugin-adapter.bats | `@test "doctor warns on dual install mode"` (fixture: fake cache dir + symlink) |
| 6 | tests/plugin-adapter.bats | `@test "deploy warns when plugin cache present"` |
| 7 | CI job | drift: `git diff --exit-code` after generate |
| 8 | tests/adapter.bats (existing) | existing suite green = symlink path unchanged |

## 10b. Verification Commands

```bash
bin/rdf generate claude-plugin && ls adapters/claude-plugin/output/commands | wc -l
# expect: 37

# Goal 2 — every canonical command containing /r- refs has rewritten refs in output
diff <(cd canonical/commands && grep -l '/r-' ./*.md | sort) \
     <(cd adapters/claude-plugin/output/commands && grep -l '/rdf:r-' ./*.md | sort)
# expect: no output (exit 0)

grep -rn '~/.claude' adapters/claude-plugin/output/hooks.json | wc -l
# expect: 0

grep -c 'CLAUDE_PLUGIN_ROOT' adapters/claude-plugin/output/hooks.json
# expect: 4 (PreToolUse, PostToolUse, SubagentStop, statusLine)

ls adapters/claude-plugin/output/agents/ | grep -c '.rdf-hash'
# expect: 0

diff <(jq -r .version .claude-plugin/plugin.json) VERSION && echo SYNCED
# expect: SYNCED

jq -r '.plugins[0] | "\(.name) \(.source)"' .claude-plugin/marketplace.json
# expect: rdf ./

claude plugin validate . --strict; echo "exit=$?"
# expect: exit=0

# Goal 5 — dual-install WARN (fixture: temp HOME with both a commands
# symlink and a minimal installed_plugins.json containing "rdf@rdf")
HOME="$FIXTURE_HOME" bin/rdf doctor . 2>&1 | grep 'install-mode'
# expect: [install-mode]   [WARN]  both symlink deploy and plugin install detected ...

# Goal 6 — deploy warns when plugin manifest present
HOME="$FIXTURE_HOME" bin/rdf deploy claude-code 2>&1 | grep -c 'plugin install detected'
# expect: 1

make -C tests test 2>&1 | grep -c '^not ok'
# expect: 0
```

## 11. Risks

1. **`claude plugin validate` availability in CI** — npm package name
   unverified in docs. Mitigation: implementation phase probes
   `@anthropic-ai/claude-code` first; if headless validate proves
   infeasible, the CI job degrades to schema validation via jq against
   the documented schema, and validate runs pre-release locally.
2. **Namespace rewrite false positives/negatives** — 223 refs, mechanical
   transform. Mitigation: boundary-guarded pattern + longest-first name
   ordering + dedicated BATS tests for both directions + post-generate
   word-boundary grep in CI drift job.
3. **Platform schema drift** — plugin spec is young and moving.
   Mitigation: CI validate job catches breakage on every push; version
   pinning of the CLI in CI if needed.
4. **Committed-output merge friction** — 56 new generated files amplify
   the existing regenerate-before-commit discipline. Mitigation: CI drift
   check makes stale output un-mergeable (same guard as cc adapter).
5. **Dual-install user confusion** — both `/r-start` and `/rdf:r-start`
   in the picker. Mitigation: doctor WARN with explicit removal guidance;
   docs position one mode per audience.
6. **Hook scripts require `jq` at runtime** — all 4 hooked scripts
   (pre-commit-validate, post-edit-lint, subagent-stop, context-bar)
   parse hook-event JSON with `jq`; a plugin consumer without `jq` gets
   failing hooks and no status line. Mitigation: README/quickstart list
   `jq` as a prerequisite for hook functionality (already required for
   the `rdf` CLI); adding `command -v jq` no-op guards inside the shipped
   scripts is canonical-source surgery deferred to its own change.

## 11b. Edge Cases

| Scenario | Expected behavior | Handling |
|----------|-------------------|---------|
| Both symlink deploy and plugin installed | doctor WARN dual-install with removal guidance; both keep working (namespace prevents hard collision) | `_check_install_mode()` |
| `VERSION` bumped, generate not run | CI plugin job fails on `git diff` (stale stamped version); BATS version-sync test fails | drift guard + test |
| Cross-ref inside a path (`canonical/commands/r-spec.md` in prose) | NOT rewritten | boundary guard requires `/r-` preceded by space/backtick/`(`/line-start; paths have `commands/` before `r-` |
| `/r-util-mem-compact` vs shorter prefix names | full name rewrites atomically | longest-first name ordering in transform loop |
| PreCompact `prompt`-type hook (no command path) | copied through byte-identical | transform touches only `"command"` values matching `~/.claude/scripts/` |
| Top-level `statusLine.command` (sibling of `"hooks"`, easy to miss) | rewritten to `${CLAUDE_PLUGIN_ROOT}` path like the 3 in-hooks entries | transform scoped to the whole file, not `.hooks` subtree; BATS asserts 4 rewrites |
| Plugin user without `jq` on PATH | commands/agents load fine (static content); all 4 hooks + status line fail at runtime | Risk 6 — jq documented as hook prerequisite |
| Marketplace added but plugin not installed | no commands appear; `/plugin install rdf@rdf` instructed in README | docs |
| CI runner lacks network for npm install | plugin job fails loudly (not silently skipped) | job has no `continue-on-error` |
| Future 38th command added to canonical | plugin output regenerates automatically; count assertions in BATS derive from `ls canonical/commands` not hardcoded 37 | test design rule |

## 12. Open Questions

None. Three deferred verify-at-implementation probes (not design
blockers): npm package name for the CLI in CI (Risk 1); whether plugin
`bin/` lands on session PATH (bonus if true — would give plugin users the
`rdf` CLI without a clone; nothing in this design depends on it); whether
the plugin command loader renders frontmatter-less commands with usable
picker descriptions (CC commands ship zero frontmatter today — if the
plugin picker shows blank descriptions, add a description-frontmatter
pass to `cpl_generate_commands` at implementation).
