# De-rfxn Core — "Drop It on Any Repo" Design

**Date:** 2026-08-18 · **Tier:** full · **Target release:** 3.6.5
**Seed:** ROADMAP 2026-08 top-5 item #2 (fresh-user / de-rfxn wave; all
findings verified against source before this spec — zero false positives).

## 1. Problem Statement

RDF's README promises "Drop it on any repo — no rfxn context required."
Four verified defect groups make that false today:

1. **rfxn leakage into consumer machines and repos.**
   - `canonical/scripts/subagent-stop.sh:37-42` hardcodes
     `/root/admin/work/proj` as fallback feed-log location and runs
     `command mkdir -p` on it. The script is an **auto-active plugin hook**
     (SubagentStop in `adapters/claude-plugin/output/hooks.json`), so every
     plugin user on another machine gets a permission-denied stderr on every
     subagent stop.
   - `lib/cmd/init.sh:444-447` (`_copy_reference_docs`) always copies core
     reference docs including `profiles/core/reference/cross-project.md`
     (38 lines of APF/BFD/LMD shared-library consumer tables) into every
     initialized repo.
   - `lib/cmd/init.sh:509-510` (`_generate_companion_files`) hardcodes
     `proj@rfxn.com`, org fallback `rfxn`, and `GNU GPL v2` into strangers'
     generated SECURITY.md / CONTRIBUTING.md. *(net-new, same class)*
   - `canonical/scripts/comment-snapshot.sh` targets six rfxn shared
     libraries under `WORKSPACE=${WORKSPACE:-/root/admin/work/proj}` and is
     copied into **every** adapter's `scripts/` output. *(net-new, same class)*
   - `canonical/commands/r-util-proj-cross.md:9` and
     `r-util-mem-audit.md:10` hardcode `/root/admin/work/proj/` in prose.
   - `canonical/reference/framework.md:21,26` hardcodes the workspace path
     in its artifact table — and that table is extracted into the
     **tracked** `adapters/agents-md/output/AGENTS.md` (:73/:78) by the
     agents-md adapter, so the leak is already committed in a release
     artifact. *(net-new, same class — completes the 9-hit canonical/
     workspace-path accounting: subagent-stop ×4, r-util commands ×2,
     comment-snapshot ×1, framework.md ×2)*
2. **Missing reference/ docs in every install.** 24 deployed files link
   `../reference/*.md` (claude-code: 8 commands; claude-plugin: 8
   commands; agent-skills: 8 SKILL.md — agent files mention reference
   docs only as bare text, not links), primarily `tiers.md`,
   `plan-schema.md`, `progress-tracking.md` — but no adapter emits
   `reference/` and `deploy.sh` never symlinks it. Tier semantics and
   the plan schema are silently absent from every install. Shipping
   `~/.claude/reference/` also makes the agents' bare-text pointers
   (`reference/tiers.md` etc.) resolvable when read from `~/.claude/`.
3. **Doc falsehoods.** `rdf deploy` exits 0 after skipping every item on an
   existing `~/.claude` (the situation of every established Claude Code
   user); `deploy.sh:238` points to `rdf deploy help` for a hooks-merge
   how-to that isn't there; README advertises `rdf init --tools` (lines
   232, 603) which warns not-implemented; README puts `/r-init` (an agent
   slash command) inside `bash` fences (lines 61-64, 92-95);
   `docs/quickstart.md:8` claims bash 4.1+ while CONTRIBUTING.md:32 and CI
   target/smoke bash 3.2 (macOS system bash) — telling macOS users they
   don't qualify; broken Pages links: `quickstart.md:109`
   (`../README.md#4-usage`), `quickstart.md:111` (`../ROADMAP.md`) — both
   outside the Pages site root — and `memory-context.md:66`
   (`specs/…` — `_config.yml` excludes `specs/`).
4. **Node/JS detection gap.** `_detect_profiles` has branches for
   shell/python/go/rust/typescript/perl/php; a plain `package.json` + `.js`
   project falls through to `minimal`.

## 2. Goals

1. Zero `/root/admin/work/proj` occurrences in `canonical/`, `lib/`,
   `state/`, and regenerated adapter `output/` trees.
2. `rdf init` on a non-rfxn repo produces zero rfxn-specific artifacts:
   no cross-project.md, no `proj@rfxn.com`, no forced `rfxn` org, no
   forced GPL v2.
3. rfxn content preserved behind an **opt-in** `rfxn-workspace` profile
   (never auto-detected).
4. `~/.claude/reference/` (7 docs) exists after `rdf deploy claude-code`;
   plugin and agent-skills outputs carry `reference/` so all 24
   `../reference/*.md` links resolve.
5. `rdf deploy` exits non-zero when any item was skipped.
6. `rdf deploy help` contains the hooks.json merge how-to.
7. README/quickstart/memory-context claims all true: no `--tools`
   advertisement, `/r-init` not in bash fences, bash floor stated as 3.2+,
   no broken Pages links.
8. A plain Node repo (`package.json` + `.js`, no tsconfig) auto-detects
   the new `node` profile.
9. Full BATS suite green; `rdf doctor --all` zero FAILs; CI green.

## 3. Non-Goals

- No changes to `adapters/gemini-cli/` generation (frozen legacy tier) —
  its committed output retains the old script copies until its next
  regeneration; not a shipped-fresh surface.
- No retroactive sweep of pre-existing suppression comments (per RDF
  CLAUDE.md scope rule).
- No `rdf init --tools` implementation — only removing its advertisement.
- No CHANGELOG.RELEASE retirement (open governance call).
- No auto-detection heuristics for `rfxn-workspace` (git-remote sniffing
  rejected as fragile — opt-in only).
- No renaming of existing profiles; no registry schema changes.
- No de-branding of the agents-md adapter's self-description (title
  "AGENTS.md — rfxn Development Framework", the rfxn-ecosystem context
  paragraph in `sections.json`): the adapter is RDF-self-referential by
  documented design decision — it describes the RDF project itself, not a
  consumer repo. Only its hardcoded workspace-path rows (inherited from
  framework.md) are in scope.

## 4. Architecture

**Design precedent (researched):** the generic-core + org-overlay split is
the settled pattern across config ecosystems — ESLint shareable configs and
Renovate config presets (org preset extends community base, opt-in per
repo), Spec Kit presets/bundles/constitutions (org policy layered over
generic templates, resolved top-down), CMake presets vs user presets. RDF
already has the exact machinery for the org layer: profiles with an opt-in
state file (`.rdf-profiles`) and `--type` selection. The design therefore
**extracts rfxn content into a `rfxn-workspace` profile** rather than
inventing a new mechanism.

### File Map

| File | Action | Est. Δ lines | Purpose |
|------|--------|--------------|---------|
| `profiles/rfxn-workspace/governance-template.md` | new | ~35 | Org overlay: shared-lib workflow + consumer-verification conventions |
| `profiles/rfxn-workspace/reference/cross-project.md` | moved | 38 | Moved verbatim from `profiles/core/reference/` |
| `profiles/rfxn-workspace/scripts/comment-snapshot.sh` | moved | ~40 | Moved from `canonical/scripts/` (org tool, no longer shipped); one-line change: `METRICS="$(command dirname "$0")/../../../canonical/scripts/comment-metrics.sh"` — repo-relative, since `comment-metrics.sh` (generic) stays in `canonical/scripts/` and the org tool runs only from a checkout |
| `profiles/core/reference/cross-project.md` | deleted | −38 | Leak source removed from always-copied core set |
| `canonical/scripts/comment-snapshot.sh` | deleted | −40 | Leak source removed from adapter script pipelines |
| `profiles/node/governance-template.md` | new | ~90 | Node.js conventions (template style of go/python profiles) |
| `profiles/registry.json` | modified | +18 | `rfxn-workspace` (detect: []) + `node` entries |
| `profiles/detection-rules.md` | modified | +10 | Document node detection + rfxn-workspace opt-in |
| `lib/cmd/init.sh` | modified | ~+30/−10 | node detect branch; `_KNOWN_PROFILES` += node, rfxn-workspace; de-rfxn `_generate_companion_files` |
| `canonical/scripts/subagent-stop.sh` | modified | ~±8 | `~/.rdf/agent-feed.log` fallback, HOME guard |
| `canonical/commands/r-util-proj-cross.md` | modified | ~±4 | Generic workspace-root wording |
| `canonical/commands/r-util-mem-audit.md` | modified | ~±4 | Generic workspace-root wording |
| `canonical/reference/framework.md` | modified | ±2 | Artifact-table rows :21/:26 → `<workspace>/…` placeholders (also fixes tracked AGENTS.md :73/:78 via regeneration) |
| `adapters/agents-md/output/AGENTS.md` | regenerated | — | Tracked release artifact — inherits framework.md fix on `rdf generate all` |
| `adapters/claude-code/adapter.sh` | modified | +25 | `cc_generate_reference()` + wire into `cc_generate_all` + count line |
| `adapters/claude-plugin/adapter.sh` | modified | +22 | `cpl_generate_reference()` + wire into `cpl_generate_all` |
| `adapters/agent-skills/adapter.sh` | modified | +12 | Emit `.agents/skills/reference/` |
| `lib/cmd/deploy.sh` | modified | ~+20 | reference symlink; exit 1 on skips; hooks-merge how-to in usage |
| `lib/cmd/doctor.sh` | modified | ~+25 | `reference` + `governance` added to sync-completeness loop (`_check_sync`, :469); third loop in `_check_content_drift` (:319-397) validating `reference/*.md` against `.rdf-hash` sidecars (plain-file hashing, commands pattern) |
| `README.md` | modified | ~±10 | drop `--tools`; `/r-init` out of bash fences |
| `docs/quickstart.md` | modified | ~±5 | bash 3.2+ floor; absolute GitHub links |
| `docs/memory-context.md` | modified | ~±2 | absolute GitHub spec link |
| `tests/derfxn.bats` | new | ~120 | Regression suite for goals 1-8 (see §10a) |
| `tests/deploy.bats` | modified | +~25 | exit-code + reference-symlink cases |
| `adapters/*/output/**` | regenerated | — | `rdf generate all` output committed |
| CHANGELOG, CHANGELOG.RELEASE | modified | +~15 | Release entries |

**No-touch files:** `adapters/gemini-cli/**` (generation source), `adapters/codex/adapter.sh`,
`canonical/scripts/` vendored set (context-bar.sh, setup.sh,
clone-conversation.sh, half-clone-conversation.sh, test-half-clone.sh,
color-preview.sh, check-context.sh), `state/*.sh`, `lib/cmd/sync.sh`,
`profiles/{shell,python,go,rust,typescript,perl,php,frontend,database,infrastructure,lite}/**`,
CLI case statements in `bin/rdf`.
*(Note: `adapters/gemini-cli/output/**` and `adapters/codex/output/**` WILL
change — `rdf generate all` regenerates them and drops the deleted
`comment-snapshot.sh` from their `scripts/`; that is the regeneration
pipeline working as designed, not a generation-source edit.)*

### Size Comparison

| Metric | Before | After |
|--------|--------|-------|
| `/root/admin/work/proj` hits in canonical/+lib/+state/ | 7 (2 scripts, 2 commands) | 0 |
| Profiles | 12 (11 + lite) | 14 (+node, +rfxn-workspace) |
| Adapter outputs carrying reference/ | 0 of 3 CC-family | 3 of 3 |
| Files with dangling `../reference/*.md` links in shipped outputs | 24 | 0 (gemini legacy excluded) |
| rfxn identifiers written into stranger repos by init | 3 (cross-project.md, email, org) | 0 |

### Dependency Tree (delivery chain for new pieces)

```
canonical/reference/*.md ──┬─ cc_generate_reference ─→ adapters/claude-code/output/reference/ ─→ deploy symlink ─→ ~/.claude/reference/
                           ├─ cpl_generate_reference ─→ adapters/claude-plugin/output/reference/ (plugin root ships it)
                           └─ sk_generate_all ───────→ adapters/agent-skills/output/.agents/skills/reference/

profiles/rfxn-workspace/ ──┬─ governance-template.md ─→ _generate_claude_md (only when opted in via --type / .rdf-profiles)
                           ├─ reference/cross-project.md ─→ _copy_reference_docs (only when opted in)
                           └─ scripts/comment-snapshot.sh (inert org tool — not consumed by any pipeline)

profiles/node/governance-template.md ─→ _detect_profiles (new branch) ─→ _generate_claude_md / cc_generate_rules
```

### Key Changes

1. **Core stays generic; org layer is opt-in.** `rfxn-workspace` has
   `detect: []` and never appears in `_detect_profiles`. Activation paths:
   `rdf init --type shell,rfxn-workspace` or `rdf profile install
   rfxn-workspace` (existing machinery, both already generic).
2. **Hook safety on foreign machines.** `subagent-stop.sh` fallback chain
   becomes `./.rdf/work-output/` → `./.rdf/` → `~/.rdf/agent-feed.log`
   (mkdir `~/.rdf` only). If `HOME` is unset/empty, exit 0 silently
   (hooks must never error).
3. **reference/ becomes a first-class adapter artifact** with `.rdf-hash`
   sidecars (claude-code), matching the commands/agents delivery pattern
   end-to-end: it joins BOTH doctor loops — `_check_content_drift`
   (:319-397; gains a third loop hashing `reference/*.md` against
   sidecars, plain-file pattern like commands) and the `_check_sync`
   completeness loop (:469, which also gains the pre-existing missing
   `governance` target while the line is being edited).
4. **Deploy is truthful**: any skip → exit 1; help contains the
   hooks-merge procedure it advertises.

### Dependency Rules

- Nothing in `canonical/`, `lib/`, `state/`, or `adapters/*/adapter.sh`
  may reference an absolute rfxn path or rfxn org identifier (enforced by
  new BATS grep test).
- `profiles/rfxn-workspace/` may reference rfxn freely — that is its job.
- Adapter reference generation reads only `canonical/reference/` (never
  `profiles/*/reference/` — those are init-time per-project copies).

## 5. File Contents

### profiles/rfxn-workspace/ (new)

| File | Contents |
|------|----------|
| `governance-template.md` | `## Cross-Project Coordination` (shared-lib release order, consumer verification before session end), `## Workspace Layout` (non-git workspace root, batch init), pointer to reference/cross-project.md. ~35 lines, template style per §6. |
| `reference/cross-project.md` | Byte-identical move of current `profiles/core/reference/cross-project.md`. |
| `scripts/comment-snapshot.sh` | Move of current `canonical/scripts/comment-snapshot.sh` with one line rewritten: `METRICS="$(command dirname "$0")/../../../canonical/scripts/comment-metrics.sh"` (repo-relative; `comment-metrics.sh` is generic and stays in canonical). Also gains `#!/usr/bin/env bash`-consistency check n/a (already env shebang). |

### profiles/node/governance-template.md (new)

Sections mirroring sibling templates: `## Code Conventions` (ESM vs CJS
declared in package.json `type`, engines field, lockfile committed),
`## Anti-Patterns` (unhandled promise rejection, sync fs in request paths,
floating promises, `npm install` in CI instead of `npm ci`),
`## Error Handling`, `## Testing` (node:test / jest, npm scripts),
`## Security` (npm audit, provenance, no postinstall trust). ~90 lines.

**Deliberate asymmetry:** sibling language profiles ship
`governance-template + 3 reference docs`; node ships template-only at
introduction (registry `summary: "governance-template only"`). Reference
docs are added when real usage identifies what they should contain —
shipping filler to satisfy symmetry contradicts the simplicity budget.

### Function inventory — new functions

| Function | Signature | Purpose | Dependencies |
|----------|-----------|---------|--------------|
| `cc_generate_reference()` | () | Copy `canonical/reference/*.md` → `${_CC_OUTPUT_DIR}/reference/` + `.rdf-hash` sidecars | `_cc_write_hash_sidecar()` |
| `cpl_generate_reference()` | () | Copy `canonical/reference/*.md` → `${_CPL_OUTPUT_DIR}/reference/` | — |
| (inline in `sk_generate_all`) | — | Copy `canonical/reference/*.md` → `<staging>/.agents/skills/reference/` | — |

### Change inventory — modified functions

| Function / site | Current behavior | New behavior | Lines (current) |
|-----------------|------------------|--------------|-----------------|
| `subagent-stop.sh` feed-log resolution | `./.rdf/work-output` → hardcoded `/root/admin/work/proj/.rdf` (mkdir) | `./.rdf/work-output` → `./.rdf` → `${HOME}/.rdf/agent-feed.log` (mkdir `~/.rdf`); `[[ -z "${HOME:-}" ]] && exit 0` | 31-43 |
| `_detect_profiles()` (init.sh) | php branch is last language | + node branch after typescript group: fires only when `package.json` exists AND typescript did not fire → `node`, `has_language=1`. Bare `*.js`/`*.mjs`/`*.cjs` globs are NOT a standalone trigger (a lone `webpack.config.js` in a Python repo must not activate node); registry `detect` globs still list them for rules paths-scoping only | 91-186 |
| `_KNOWN_PROFILES` (init.sh) | 11 names | + `node`, `rfxn-workspace` | 39 |
| `_generate_companion_files()` (init.sh) | `contact_email="proj@rfxn.com"`, `org="rfxn"`, `license="GNU GPL v2"` | contact = `git -C path config user.email` fallback "the maintainers via the repository issue tracker"; org fallback = project basename; license = grep LICENSE head for MIT/Apache/GPL fallback "see the LICENSE file" | 486-545 |
| `_deploy_claude_code()` | 4 symlinks + state helpers | + `_deploy_symlink "${output_dir}/reference" "${dest_base}/reference"` | 225-235 |
| `cmd_deploy()` summary | warn + implicit return 0 | skip path: warn + `return 1` | 361-365 |
| `_deploy_usage()` | mentions manual merge only | + `Hooks merge (claude-code):` block with jq one-liner + manual alternative | 8-35 |
| `cc_generate_all()` / `cpl_generate_all()` | 6 / 5 generation steps | + reference step; cc summary line gains reference count | 281-322 / 244-279 |
| `sk_generate_all()` | emits skills only | + reference copy into staging before swap | 53-75 |
| doctor `_check_sync` completeness | `for target in commands agents scripts` | `for target in commands agents scripts governance reference` (governance is a pre-existing gap folded in while editing the line) | 469 |
| doctor `_check_content_drift` | two loops: agents (frontmatter-stripped) + commands | + third loop: `reference/*.md` hashed against `.rdf-hash` sidecars (plain-file pattern, no frontmatter strip) | 319-397 |
| `subagent-stop.sh` shebang | `#!/bin/bash` | `#!/usr/bin/env bash` (RDF shell standard, folded in while file is open) | 1 |
| `r-util-proj-cross.md` / `r-util-mem-audit.md` | name `/root/admin/work/proj/` | "the workspace root (a non-git parent directory containing project repos)" | 9 / 10 |

### Doc change inventory

| File | Site | Change |
|------|------|--------|
| README.md | :232 table row | `rdf init <path> [--type] [--github]` (drop `--tools`) |
| README.md | :603 example | drop `--tools claude-code` |
| README.md | :61-64, :92-95 | `/r-init` lines moved out of `bash` fences into adjacent prose/plain fence ("then, inside your agent session:") |
| docs/quickstart.md | :8 | `bash` 3.2+ (macOS system bash works; CI-verified) |
| docs/quickstart.md | :109 | `https://github.com/rfxn/rdf#4-usage` (or `#readme`) |
| docs/quickstart.md | :111 | `https://github.com/rfxn/rdf/blob/main/ROADMAP.md` |
| docs/memory-context.md | :66 | `https://github.com/rfxn/rdf/blob/main/docs/specs/2026-07-15-memory-context-design.md` |

## 5b. Examples

Fresh non-rfxn user, existing `~/.claude` content (the previously silent
half-install):

```
$ rdf deploy claude-code
rdf: deploying Claude Code adapter to /home/dev/.claude...
rdf: warning: /home/dev/.claude/commands exists (not a symlink). Back it up and re-run, or use --force.
...
rdf: warning: deploy complete: 3 deployed, 4 skipped (use --force to override)
$ echo $?
1
```

After a clean deploy:

```
$ ls ~/.claude/reference/
framework.md  memory-standards.md  plan-schema.md  progress-tracking.md
session-safety.md  simplicity-budget.md  tiers.md
```

Plain Node repo init (before: `minimal`; after):

```
$ rdf init ~/apps/my-api
rdf: auto-detected profiles: node
rdf: initializing: my-api (profiles=node, version=0.1.0)
```

rfxn machine opting in to the org layer:

```
$ rdf init /root/admin/work/proj/newlib --type shell,rfxn-workspace
```

Error case — deploy with nothing generated (unchanged behavior):

```
$ rdf deploy claude-code
rdf: error: output not found — run 'rdf generate claude-code' first
$ echo $?
1
```

## 6. Conventions

- New profile templates follow sibling structure: `# {Name} Governance
  Template`, blockquote preamble ("Seed template for /r-init … Requires
  core profile."), `##` sections, `--` em-dash style.
- Generation functions follow the existing per-adapter naming
  (`cc_`/`cpl_`/`sk_` prefixes), staging-dir pattern, `rdf_log` counts.
- All new shell follows workspace standards: `command` prefix on
  coreutils, suppressions carry same-line justification comments, bash
  3.2-safe (no `${var,,}`, no `declare -A` globals).

## 7. Interface Contracts

- **CLI:** no new flags. `--type` accepts two new profile names (`node`,
  `rfxn-workspace`). **Behavior change:** `rdf deploy` exit code 1 when
  ≥1 item skipped (was 0) — documented as `[Change]` in CHANGELOG.
- **File formats:** unchanged (registry.json gains entries within existing
  schema; hooks.json untouched).
- **Deployed surface:** adds `~/.claude/reference/` (symlink), plugin
  `output/reference/`, `.agents/skills/reference/`.
- Existing `.rdf-profiles` files remain valid; new names are additive.

## 8. Migration Safety

- **Upgrade (rfxn machines):** next `rdf generate all` +
  `rdf deploy claude-code` delivers reference/ and drops
  comment-snapshot.sh from `~/.claude/scripts` (symlinked dir — automatic).
  Ryan's workspaces keep working: project dirs have `.rdf/work-output/` so
  the feed-log fallback change is a no-op there; the workspace-level
  hardcoded branch is replaced by the cwd `./.rdf` check which covers the
  same case when hooks run at workspace root. To restore org governance,
  `rdf profile install rfxn-workspace` once (documented in CHANGELOG).
- **Upgrade (previously initialized consumer repos):** stale
  `.rdf/governance/reference/cross-project.md` copies remain on disk;
  harmless. `/r-refresh` regenerates from the now-clean profile set.
  Not force-deleted (never delete user-repo files on upgrade).
- **Fresh install:** unchanged flow; deploy now fails loudly on conflicts
  instead of silently half-installing.
- **Rollback:** all changes are in-repo + regenerated outputs; `git revert`
  of the release commits fully restores prior behavior. The deploy symlink
  farm re-points on next generate/deploy.
- **Uninstall:** N/A (no installer changes beyond one added symlink, which
  existing `--force`/backup semantics govern).
- **Test suite impact:** grep confirmed no existing BATS file hardcodes a
  script count or references comment-snapshot.sh; the build phase touching
  deploy exit codes must still run the full deploy.bats to catch any
  implicit exit-0 assumption, and fix in the same phase if one surfaces.

## 9. Dead Code and Cleanup

| Finding | Action |
|---------|--------|
| `comment-snapshot.sh` in adapter outputs | Only `adapters/claude-plugin/output/` is git-tracked (`.gitignore`/`.git/info/exclude` cover the rest — local build artifacts); regeneration drops the script from the tracked plugin output and from any locally generated trees |
| No other dead code found in touched files | — |

## 10a. Test Strategy

New `tests/derfxn.bats` unless noted; fixtures under `tests/fixtures/`.

| Goal | Test file | Test description |
|------|-----------|------------------|
| 1 | derfxn.bats | `@test "no rfxn workspace path in canonical, lib, state"` (grep `-r '/root/admin/work/proj'` → 0 hits) |
| 1 | derfxn.bats | `@test "generated adapter outputs contain no rfxn workspace path"` (skips gemini output) |
| 2 | derfxn.bats | `@test "init on plain repo copies no cross-project.md"` |
| 2 | derfxn.bats | `@test "init companion files carry no rfxn contact when remote absent"` |
| 3 | derfxn.bats | `@test "rfxn-workspace profile is opt-in: not auto-detected, valid via --type"` |
| 4 | derfxn.bats | `@test "cc output ships reference docs with hash sidecars"` |
| 4 | derfxn.bats | `@test "plugin output and agent-skills output ship reference docs"` |
| 4 | deploy.bats | `@test "deploy claude-code symlinks reference into target"` |
| 5 | deploy.bats | `@test "deploy exits nonzero when items are skipped"` |
| 5 | deploy.bats | `@test "deploy exits zero on clean full deploy"` |
| 6 | deploy.bats | `@test "deploy help documents hooks.json merge"` |
| 7 | derfxn.bats | `@test "README does not advertise --tools; quickstart states bash 3.2 floor"` |
| 8 | derfxn.bats | `@test "plain node fixture detects node profile"` |
| 8 | derfxn.bats | `@test "typescript fixture does not add node profile"` |
| 1 (hook) | derfxn.bats | `@test "subagent-stop falls back to HOME .rdf without hardcoded path"` (run with `HOME=$BATS_TEST_TMPDIR`, cwd without .rdf) |
| 1 (hook) | derfxn.bats | `@test "subagent-stop exits 0 when HOME unset"` |

## 10b. Verification Commands

```bash
grep -rn '/root/admin/work/proj' canonical/ lib/ state/ bin/
# expect: no output (exit 1)

grep -rn '/root/admin/work/proj' adapters/claude-code/output adapters/claude-plugin/output adapters/agent-skills/output adapters/agents-md/output
# expect: no output (exit 1)

ls adapters/claude-code/output/reference/*.md | wc -l
# expect: 7
ls adapters/claude-code/output/reference/*.rdf-hash | wc -l
# expect: 7

t=$(mktemp -d); RDF_TARGET="$t" ./bin/rdf deploy claude-code; echo "clean_exit=$?"
# expect: clean_exit=0
t=$(mktemp -d); mkdir -p "$t/commands"; RDF_TARGET="$t" ./bin/rdf deploy claude-code; echo "skip_exit=$?"
# expect: skip warning for commands; skip_exit=1

./bin/rdf deploy help | grep -c 'jq'
# expect: >= 1 (usage now contains the jq hooks-merge one-liner, not just a pointer)

grep -c 'rfxn-workspace\|"node"' profiles/registry.json
# expect: >= 2

grep -n 'tools' README.md | grep -- '--tools'
# expect: no output

grep -n '4\.1' docs/quickstart.md
# expect: no output

make -C tests test 2>&1 | tail -3
# expect: all tests pass, 0 failures

rdf doctor --all 2>&1 | grep -c FAIL
# expect: 0
```

## 11. Risks

1. **Deploy exit-code change breaks a caller that treats skip-as-ok.**
   Mitigation: grep repo + CI for `rdf deploy` invocations; document as
   `[Change]`; skips already print actionable warnings.
2. **Node branch misfires on repos with incidental JS** (e.g., a Python
   repo with one `webpack.config.js`). Mitigation: `package.json` is the
   sole activation gate — JS-file globs never trigger the branch on their
   own; suppressed when typescript matched. Residual: a Python repo with a
   real `package.json` (docs tooling) gets `python,node` — multi-profile
   activation is the established, accepted semantic for mixed repos.
3. **rfxn machines silently lose cross-project governance** after upgrade.
   Mitigation: CHANGELOG migration note + `rdf profile install
   rfxn-workspace` one-liner; content preserved verbatim in the new
   profile.
4. **Doctor sync-completeness false-FAILs** if reference is added to the
   loop before outputs are regenerated. Mitigation: single commit contains
   adapter change + regenerated outputs + doctor change; test ordering in
   plan enforces regenerate-before-doctor-check.
5. **Plugin manifest/validator rejects new output dir.** Mitigation:
   plugin.json enumerates agents only; reference/ is inert content —
   verified via `claude plugin validate --strict` in CI (already wired).
6. **hooks.json how-to drifts from actual hook set.** Mitigation: how-to
   documents the jq merge command generically, not the hook list.

## 11b. Edge Cases

| Scenario | Expected behavior | Handling |
|----------|-------------------|----------|
| SubagentStop fires with `HOME` unset/empty | exit 0, no log entry | explicit guard before fallback |
| SubagentStop fires in cwd with `.rdf/` but no `work-output/` | append to `./.rdf/agent-feed.log` | second chain step |
| `~/.rdf` not creatable (read-only HOME) | mkdir fails → script still exits 0 (`set -uo` without `-e`; append fails silently to stderr) | acceptable: hooks never block the session; stderr is per-user-fixable |
| `rdf init --type rfxn-workspace` alone (no language profile) | valid: core + rfxn-workspace governance merge | `_validate_profiles` accepts; merge handles any set |
| `rdf init --type node` on a TS repo | honored — explicit `--type` always wins over detection | existing precedence unchanged |
| Repo with `package.json` + `tsconfig.json` | `typescript` only (node suppressed) | detection branch condition |
| Repo with `.jsx` + `package.json`, no framework dep | `node,frontend` | independent branch activation (existing semantic) |
| Deploy target where only `reference` conflicts | other items deploy; exit 1 with skip warning naming reference | per-item accounting already exists |
| `deploy --dry-run` against conflicted target | same skip accounting → exit 1 (predicts real run) | no special-casing |
| Old consumer repo with stale `.rdf/governance/reference/cross-project.md` | untouched; `/r-refresh` regenerates clean set | never delete user files on upgrade |
| `rdf profile install rfxn-workspace` on non-rfxn machine | works — profile is generic machinery; content is inert docs | no path assumptions in profile content |

## 12. Open Questions

None — all decisions resolved in brainstorm (recorded in
`spec-progress-01a01708…md` with rationale).
