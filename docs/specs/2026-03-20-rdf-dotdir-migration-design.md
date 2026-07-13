# Design: `.rdf/` Directory Migration

**Date:** 2026-03-20
**Status:** Implemented (3.0.1)
**Author:** Ryan MacDonald + Claude (Opus 4.6)

---

## 1. Problem Statement

RDF claims to be tool-agnostic but is architecturally coupled to Claude
Code through 78 hardcoded `.claude/governance/` references across 28
canonical files. Every agent and command reads governance from
`.claude/governance/` — a path that only exists in Claude Code
deployments. Gemini CLI and Codex cannot use the same canonical content
without path rewrites.

Per-project operational state is scattered across three locations:
- `.claude/governance/` — 6 governance files per project
- `work-output/` — session logs, phase artifacts, progress files
- `~/.claude/projects/{path-encoded}/memory/` — auto-memory (CC-specific)

This creates two visible dot-directories at project root and couples
memory to Claude Code's path-encoding scheme.

**Measured impact:**
- 78 `.claude/governance/` refs across 4 agents + 24 commands + 6 templates + 3 reference docs
- 44 bare `work-output/` refs needing `.rdf/` prefix across 9 commands + 1 agent + 1 script
- 8 `/root/.claude/projects/` memory path refs across 3 commands + 1 reference doc
- 47 CC-specific deployment refs across 11 files (correctly tool-specific, must NOT change)
- 6 CLI functions with hardcoded `.claude` paths (init.sh, doctor.sh, refresh.sh, deploy.sh)

## 2. Goals

1. All per-project RDF state consolidates into `{project}/.rdf/` — one invisible directory
2. Governance path in all agents and commands is `.rdf/governance/` — literal, tool-agnostic
3. `work-output/` content moves to `.rdf/work-output/`
4. Auto-memory moves to `.rdf/memory/` (symlinked to CC's real dir for compatibility)
5. Three-tier `.rdf/` hierarchy operational: global (`~/.rdf/`), workspace, project
6. `rdf init` creates `.rdf/` structure on new projects
7. `rdf migrate` converts existing projects from `.claude/governance/` + `work-output/`
8. `rdf doctor` validates `.rdf/` health and detects legacy state
9. Zero `.claude/governance/` references remain in `canonical/`
10. CC deployment (`~/.claude/agents/`, `~/.claude/commands/`) continues working via symlinks

## 3. Non-Goals

- Moving adapter deployment targets (`~/.claude/agents/`, `~/.gemini/commands/`) — correctly tool-specific
- Changing CLAUDE.md / GEMINI.md file locations — tool conventions
- Replacing CC's auto-memory system — we symlink to it, not replace it
- Migrating archived v2 content (`canonical/commands-v2-archived/`, `canonical/agents-v2-archived/`)
- Changing `PLAN.md`, `AUDIT.md`, `MEMORY.md` locations at project root — human-facing, not infrastructure
- Modifying r-sync.md — all 20+ `.claude` refs are CC deployment paths

## 4. Architecture

### 4.1 Three-Tier Hierarchy

```
~/.rdf/                                        GLOBAL (user-wide)
├── config.json                                preferences, auto_commit_insights
├── insights.jsonl                             rolling 30 session insights
└── lessons-learned.md                         curated permanent wisdom

{workspace}/.rdf/                              WORKSPACE (multi-project container)
├── session-log.jsonl                          cross-project session history
└── agent-feed.log                             cross-project agent activity

{project}/.rdf/                                PROJECT (git repo root)
├── governance/                                per-project governance
│   ├── index.md
│   ├── architecture.md
│   ├── conventions.md
│   ├── constraints.md
│   ├── verification.md
│   ├── anti-patterns.md
│   └── reference/
├── work-output/                               session operational state
│   ├── session-log.jsonl
│   ├── agent-feed.log
│   ├── spec-progress.md
│   ├── ship-progress.md
│   ├── current-phase.md
│   └── phase-N-*.md
├── memory/                                    → symlink to CC auto-memory
└── scopes/                                    sub-scope governance overrides
    └── {name}/governance/
```

### 4.2 Discovery Rules

| Tier | Discovery | Rule |
|------|-----------|------|
| **Global** | `$HOME/.rdf/` | Fixed path, always available |
| **Workspace** | `$(dirname "$(git rev-parse --show-toplevel)")/.rdf/` | Parent of git root |
| **Project** | `$(git rev-parse --show-toplevel)/.rdf/` | Same directory as `.git/` |

If workspace tier is not found, workspace-level state falls back to
the project tier.

### 4.3 File Map

**New files:**

| File | Lines (est.) | Purpose | Test File |
|------|-------------|---------|-----------|
| `lib/cmd/migrate.sh` | ~150 | `rdf migrate` subcommand | `tests/migrate.bats` (future) |

**Modified files — governance path (`.claude/governance/` → `.rdf/governance/`):**

| File | Lines | Refs to change | Change |
|------|-------|---------------|--------|
| `canonical/agents/dispatcher.md` | 88 | 1 (line 14) | `.claude/governance/` → `.rdf/governance/` |
| `canonical/agents/engineer.md` | 47 | 1 (line 14) | Same |
| `canonical/agents/qa.md` | 59 | 1 (line 13) | Same |
| `canonical/agents/uat.md` | 56 | 1 (line 14) | Same |
| `canonical/commands/r-audit.md` | 223 | 1 (line 15) | Same |
| `canonical/commands/r-build.md` | 113 | 7 (lines 51, 77-82) | Governance + context block |
| `canonical/commands/r-init.md` | 851 | ~20 | `.claude/governance/` → `.rdf/governance/` throughout |
| `canonical/commands/r-mode.md` | 94 | 2 (lines 26, 52) | Same |
| `canonical/commands/r-refresh.md` | 295 | ~5 | Same |
| `canonical/commands/r-review.md` | 123 | 8 (lines 49, 69-71, 85-88) | Governance + context blocks |
| `canonical/commands/r-ship.md` | 303 | 1 (line 12) | Same |
| `canonical/commands/r-spec.md` | 604 | 2 (lines 99, 417) | Governance read + verification grep template |
| `canonical/commands/r-start.md` | 233 | 2 (lines 19, 50) | Same |
| `canonical/commands/r-status.md` | 199 | 2 (lines 10, 40) | Same |
| `canonical/commands/r-test.md` | 75 | 5 (lines 26, 44-47) | Governance + context block |
| `canonical/commands/r-verify.md` | 73 | 6 (lines 25, 45-49) | Governance + context block |
| `canonical/commands/r-util-chg-dedup.md` | 130 | 1 (line 11) | Same |
| `canonical/commands/r-util-chg-gen.md` | 123 | 1 (line 10) | Same |
| `canonical/commands/r-util-ci-gen.md` | 116 | 1 (line 9) | Same |
| `canonical/commands/r-util-code-modernize.md` | 111 | 1 (line 10) | Same |
| `canonical/commands/r-util-code-scan.md` | 90 | 1 (line 11) | Same |
| `canonical/commands/r-util-doc-gen.md` | 178 | 1 (line 11) | Same |
| `canonical/commands/r-util-lib-release.md` | 119 | 1 (line 9) | Same |
| `canonical/commands/r-util-lib-sync.md` | 103 | 1 (line 10) | Same |
| `canonical/commands/r-util-mem-compact.md` | 107 | 1 (line 10) | Same |
| `canonical/commands/r-util-test-dedup.md` | 104 | 1 (line 10) | Same |
| `canonical/commands/templates/governance-*.md` | 6 files | 1 each (line 4) | `.user-modified` marker |
| `canonical/commands/templates/governance-index.md` | 25 | 2 (lines 11, 16) | Same |
| `canonical/reference/framework.md` | 226 | 4 (lines 23-24, 111, 221) | Artifact taxonomy |
| `canonical/reference/memory-standards.md` | 33 | 1 (line 9) | Memory path |
| `schemas/governance-index.md` | 52 | 3 (lines 6, 47, 49) | Schema paths |

**Modified files — work-output path (`work-output/` → `.rdf/work-output/`):**

| File | Refs to change |
|------|---------------|
| `canonical/agents/dispatcher.md` | 2 (lines 67, 87) |
| `canonical/commands/r-save.md` | 3 (lines 57, 118, 137) |
| `canonical/commands/r-start.md` | 7 (lines 45-47, 62-67, 73) |
| `canonical/commands/r-spec.md` | 5 (lines 13, 68, 224, 291, 556) |
| `canonical/commands/r-ship.md` | 3 (lines 19, 26, 265) |
| `canonical/commands/r-status.md` | 7 (lines 29-30, 101, 111, 116, 142, 193) |
| `canonical/commands/r-build.md` | 1 (line 97) |
| `canonical/commands/r-refresh.md` | 1 (line 218) |
| `canonical/reference/framework.md` | 6 |
| `canonical/scripts/subagent-stop.sh` | 6 (lines 32-40) |
| `canonical/reference/session-safety.md` | 7 |

**Modified files — memory path (`/root/.claude/projects/{encoded}/` → `.rdf/memory/`):**

| File | Refs to change |
|------|---------------|
| `canonical/commands/r-save.md` | 1 (line 79) |
| `canonical/commands/r-util-mem-audit.md` | 1 (line 13) |
| `canonical/reference/memory-standards.md` | 1 (line 9) |

**Modified CLI files:**

| File | Lines | Functions affected | Change |
|------|-------|-------------------|--------|
| `lib/cmd/init.sh` | 428 | `_setup_git_exclude()` (136-193), `_init_one()` (262-338) | Exclude entries, create `.rdf/` structure |
| `lib/cmd/doctor.sh` | 582 | `_check_artifacts()` (59-95), `_check_memory()` (137-179), `_check_sync()` (282-357) | Check `.rdf/`, legacy detection |
| `lib/cmd/refresh.sh` | 397 | `_resolve_memory_path()` (39-44) | Memory path from `.rdf/memory/` |
| `bin/rdf` | 55 | Case statement (41-55) | Add `migrate)` case, update help text |

**Modified documentation:**

| File | Change |
|------|--------|
| `README.md` | Directory structure, data flow diagram |
| `RDF.md` | Directory structure, scope description |
| `CLAUDE.md` | Exclude list |
| `CHANGELOG` | New entries |
| `CHANGELOG.RELEASE` | New entries |
| `profiles/core/governance-template.md` | `.claude/` → `.rdf/` in exclude example |
| `profiles/registry.md` | Reference doc path |

**Files NOT modified (CC-specific deployment paths — must NOT change):**

| File | `.claude` refs | Why no change |
|------|---------------|---------------|
| `canonical/scripts/setup.sh` | 11 | Configures `~/.claude/settings.json`, Read permissions |
| `canonical/scripts/check-context.sh` | 2 | Install instructions for `~/.claude/scripts/` |
| `canonical/scripts/clone-conversation.sh` | 1 | `CLAUDE_DIR` for CC session data |
| `canonical/scripts/half-clone-conversation.sh` | 1 | Same |
| `canonical/scripts/pre-commit-validate.sh` | 2 | Runtime governance read (deployed path) |
| `canonical/scripts/test-half-clone.sh` | 2 | Test references to CC data |
| `canonical/commands/r-sync.md` | 20+ | All CC deployment paths (`~/.claude/agents/`, etc.) |
| `adapters/claude-code/hooks/hooks.json` | 4 | Hook paths reference `~/.claude/scripts/` |
| `lib/cmd/deploy.sh` | 3 | Deployment target `dest_base="${HOME}/.claude"` |
| `lib/cmd/sync.sh` | ~5 | Sync from `~/.claude/` back to canonical |
| `adapters/claude-code/adapter.sh` | ~5 | CC-specific generation logic |

**Bare-path agents requiring audit:**

| File | Issue |
|------|-------|
| `canonical/agents/reviewer.md` | Bare `governance/anti-patterns.md` (no prefix) — verify context resolution |
| `canonical/agents/planner.md` | No governance refs — confirm no implicit assumptions |

### 4.4 Size Comparison

| Metric | Before | After |
|--------|--------|-------|
| Visible dot-dirs at project root | 2 (`.claude/`, `work-output/`) | 1 (`.rdf/`) |
| `.claude/governance/` refs in canonical | 78 | 0 |
| Bare `work-output/` refs in canonical | 44 | 0 |
| CC auto-memory path refs | 8 | 0 (all `.rdf/memory/`) |
| Git exclude entries per project | 9 | 5 |
| Files in `lib/cmd/` | 10 | 11 (+migrate.sh) |

### 4.5 Dependency Tree

```
bin/rdf
  └── sources lib/rdf_common.sh (RDF_HOME, RDF_CANONICAL, RDF_ADAPTERS)
        └── sources lib/cmd/{subcommand}.sh

lib/cmd/init.sh
  ├── _setup_git_exclude()     ← writes .git/info/exclude
  ├── _init_one()              ← creates .rdf/ structure
  └── calls lib/cmd/github.sh  ← GitHub scaffolding

lib/cmd/migrate.sh [NEW]
  ├── _migrate_governance()    ← moves .claude/governance/ → .rdf/governance/
  ├── _migrate_workoutput()    ← moves work-output/ → .rdf/work-output/
  ├── _setup_memory_symlink()  ← creates .rdf/memory/ symlink
  ├── _update_excludes()       ← updates .git/info/exclude
  └── calls lib/cmd/doctor.sh  ← post-migration verification

lib/cmd/doctor.sh
  ├── _check_artifacts()       ← checks .rdf/ structure
  ├── _check_memory()          ← checks .rdf/memory/ symlink
  └── _check_sync()            ← checks CC deployment symlinks (unchanged)

lib/cmd/refresh.sh
  └── _resolve_memory_path()   ← reads from .rdf/memory/MEMORY.md

lib/cmd/deploy.sh              ← UNCHANGED (CC deployment stays at ~/.claude/)
lib/cmd/sync.sh                ← UNCHANGED (syncs from ~/.claude/ to canonical/)
```

### 4.6 CC Auto-Memory Symlink Strategy

CC hardcodes auto-memory at `~/.claude/projects/{path-encoded}/memory/`.
CC owns that path and may recreate it as a real directory at any time.

**Strategy:** CC's directory is the real storage. `.rdf/memory/` is a
symlink pointing TO it.

```
{project}/.rdf/memory/
  → ~/.claude/projects/-root-admin-work-proj-rdf/memory/
```

- CC reads/writes its own real directory — zero interference
- Other tools read `.rdf/memory/` which follows the symlink
- `rdf doctor` validates the symlink is intact

**Non-CC environments:** If CC is not installed or the auto-memory path
does not exist, `.rdf/memory/` is created as a real directory.

**Path encoding:** Replace `/` with `-`, strip leading `-`.
Example: `/root/admin/work/proj/rdf` → `-root-admin-work-proj-rdf`

## 5. File Contents

### 5.1 New file: `lib/cmd/migrate.sh` (~150 lines)

| Function | Signature | Purpose | Dependencies |
|----------|-----------|---------|--------------|
| `_migrate_usage()` | () | Display usage for `rdf migrate` | None |
| `_migrate_governance()` | (project_path) | Copy `.claude/governance/` → `.rdf/governance/`, verify, remove source | `rdf_require_dir()` |
| `_migrate_workoutput()` | (project_path) | Copy `work-output/` → `.rdf/work-output/`, verify, remove source | `rdf_require_dir()` |
| `_setup_memory_symlink()` | (project_path) | Create `.rdf/memory/` → CC auto-memory path, or real dir if CC absent | `_encode_project_path()` |
| `_encode_project_path()` | (abs_path) | Convert `/root/admin/work/proj/rdf` → `-root-admin-work-proj-rdf` | None |
| `_update_excludes()` | (project_path) | Remove old entries (`.claude/`, `work-output/`, `audit-output/`, `REGR.md`), add `.rdf/` | None |
| `_migrate_one()` | (project_path, dry_run) | Orchestrate single-project migration: governance → workoutput → memory → excludes | All above |
| `cmd_migrate()` | ("$@") | Main dispatcher: parse args, single or `--all` mode | `_migrate_one()` |

### 5.2 Modified file: `lib/cmd/init.sh` (428 lines)

| Function | Current behavior | New behavior | Lines affected |
|----------|-----------------|--------------|----------------|
| `_setup_git_exclude()` | Writes `.claude/`, `work-output/`, `audit-output/`, `REGR.md` | Writes `.rdf/` only (replaces 4 entries with 1) | 123-133 |
| `_init_one()` | Creates `work-output/` at project root | Creates `.rdf/governance/`, `.rdf/work-output/`, `.rdf/memory/`, `.rdf/scopes/` | 285-293 |

### 5.3 Modified file: `lib/cmd/doctor.sh` (582 lines)

| Function | Current behavior | New behavior | Lines affected |
|----------|-----------------|--------------|----------------|
| `_check_artifacts()` | Checks `work-output/` exists | Checks `.rdf/` structure (governance/, work-output/, memory/) | 59-95 |
| `_check_artifacts()` | Checks `.claude/`, `work-output/` in exclude | Checks `.rdf/` in exclude | 77-94 |
| `_check_memory()` | Reads from `~/.claude/projects/{encoded}/memory/` | Reads from `.rdf/memory/MEMORY.md` | 137-179 |
| `_check_sync()` | N/A | NEW: warn if `.claude/governance/` still exists (legacy detection) | After line 357 |

### 5.4 Modified file: `lib/cmd/refresh.sh` (397 lines)

| Function | Current behavior | New behavior | Lines affected |
|----------|-----------------|--------------|----------------|
| `_resolve_memory_path()` | Returns `/root/.claude/projects/{safe_path}/memory/MEMORY.md` | Returns `{project}/.rdf/memory/MEMORY.md` | 39-44 |

### 5.5 Modified file: `bin/rdf` (55 lines)

| Change | Current | New | Line |
|--------|---------|-----|------|
| Case statement | No `migrate)` branch | Add `migrate) shift; source "${RDF_LIBDIR}/cmd/migrate.sh"; cmd_migrate "$@" ;;` | After line 53 |
| Help text | `sync Pull /root/.claude/ changes back to canonical` | `migrate Migrate project from .claude/ + work-output/ to .rdf/` (add line) | 23 |

## 5b. Examples

### `rdf migrate` — successful migration

```
$ rdf migrate /root/admin/work/proj/apf
rdf: migrating apf to .rdf/ structure...
  [✓] .rdf/ created
  [✓] governance: .claude/governance/ → .rdf/governance/ (6 files)
  [✓] work-output: work-output/ → .rdf/work-output/ (3 files)
  [✓] memory: .rdf/memory/ → ~/.claude/projects/-root-admin-work-proj-apf/memory/
  [✓] .git/info/exclude updated (removed .claude/, work-output/; added .rdf/)
  [✓] removed empty .claude/
rdf: migration complete — run 'rdf doctor' to verify
```

### `rdf migrate --dry-run`

```
$ rdf migrate --dry-run /root/admin/work/proj/apf
rdf: [dry-run] would migrate apf to .rdf/ structure:
  WOULD CREATE: .rdf/
  WOULD MOVE: .claude/governance/ → .rdf/governance/ (6 files)
  WOULD MOVE: work-output/ → .rdf/work-output/ (3 files)
  WOULD SYMLINK: .rdf/memory/ → ~/.claude/projects/-root-admin-work-proj-apf/memory/
  WOULD UPDATE: .git/info/exclude
  WOULD REMOVE: .claude/ (if empty)
rdf: no files modified (dry run)
```

### `rdf doctor` — post-migration (new checks)

```
$ rdf doctor /root/admin/work/proj/apf
artifacts:
  [OK]   CLAUDE.md present
  [OK]   .rdf/governance/ present (6 files)
  [OK]   .rdf/work-output/ present
  [OK]   .rdf/memory/ symlink intact
  [OK]   .git/info/exclude has .rdf/
...
```

### `rdf doctor` — legacy detection

```
$ rdf doctor /root/admin/work/proj/apf
artifacts:
  [WARN] .claude/governance/ still exists — run 'rdf migrate' to consolidate
  [WARN] work-output/ at project root — run 'rdf migrate' to move to .rdf/work-output/
...
```

### Before/after project root

```
BEFORE:                          AFTER:
apf/                             apf/
├── .claude/                     ├── .rdf/
│   └── governance/              │   ├── governance/
│       ├── index.md             │   │   ├── index.md
│       └── ...                  │   │   └── ...
├── work-output/                 │   ├── work-output/
│   ├── session-log.jsonl        │   │   ├── session-log.jsonl
│   └── ...                      │   │   └── ...
├── CLAUDE.md                    │   ├── memory/ → ~/.claude/projects/.../memory/
├── PLAN.md                      │   └── scopes/
└── files/                       ├── CLAUDE.md
                                 ├── PLAN.md
                                 └── files/
```

### `.git/info/exclude` before/after

```
BEFORE:                          AFTER:
CLAUDE.md                        # RDF working files (managed by rdf init)
PLAN*.md                         CLAUDE.md
AUDIT.md                         PLAN*.md
REGR.md                          AUDIT.md
MEMORY.md                        MEMORY.md
.claude/                         .rdf/
audit-output/
work-output/
```

## 6. Conventions

### 6.1 Path Resolution

All canonical agents and commands use literal `.rdf/governance/` paths:

```markdown
### Setup
- Read .rdf/governance/index.md
- Load conventions.md, constraints.md from governance
```

No variables, no placeholders, no adapter injection.

### 6.2 Git Exclusion

New standard exclude entries (written by `rdf init`):

```
# RDF working files (managed by rdf init)
CLAUDE.md
PLAN*.md
AUDIT.md
MEMORY.md
.rdf/
```

### 6.3 Migration Log

`rdf migrate` logs every operation to `/tmp/rdf-migrate-{project}.log`
(outside `.rdf/` for safety). Format: one line per operation with
timestamp, action, source, destination.

### 6.4 Sub-Scope Pattern

```
{project}/.rdf/scopes/{scope-name}/governance/
```

Scope name: subdirectory path with `/` → `-`.
Example: `files/internals` → `files-internals`.

## 7. Interface Contracts

### 7.1 `rdf migrate` CLI

```
Usage: rdf migrate [options] [path]

Migrate project from .claude/governance/ + work-output/ to .rdf/

Arguments:
  path        Project directory (default: cwd)

Options:
  --dry-run   Show changes without modifying
  --all       Migrate all projects in workspace

Exit codes:
  0   Migration successful
  1   Migration failed (check /tmp/rdf-migrate-{project}.log)
  2   Nothing to migrate (already .rdf/ or fresh project)
  3   Conflict detected (both .claude/governance/ and .rdf/governance/ exist)
```

### 7.2 Updated `rdf init` output

Creates `.rdf/` with subdirectories instead of `.claude/governance/`
and `work-output/`.

### 7.3 Updated `rdf doctor` checks

| Check | Category | Pass condition |
|-------|----------|---------------|
| `.rdf/governance/` present | artifacts | Directory exists with index.md |
| `.rdf/work-output/` present | artifacts | Directory exists |
| `.rdf/memory/` present | artifacts | Symlink or directory exists |
| `.git/info/exclude` has `.rdf/` | artifacts | grep -qxF '.rdf/' |
| No legacy `.claude/governance/` | artifacts | Directory does NOT exist |
| No legacy `work-output/` at root | artifacts | Directory does NOT exist |
| Memory symlink intact | memory | `readlink` resolves to valid path |

## 8. Migration Safety

### 8.1 Backward Compatibility

- **Existing projects:** `rdf migrate` handles transition. `rdf doctor` warns about legacy.
- **New projects:** `rdf init` creates `.rdf/` directly.
- **Mixed state:** Both `.claude/governance/` and `.rdf/governance/` → exit code 3, manual resolution.
- **CC auto-memory:** Symlink preserves CC functionality. If broken, `rdf doctor` detects and offers fix.

### 8.2 Rollback

`rdf migrate` uses copy-then-verify-then-delete:

1. Create `.rdf/` structure (additive)
2. Copy governance and work-output into `.rdf/`
3. Verify copies match originals (file count + spot-check)
4. Only after verification: remove old directories
5. Log every operation to `/tmp/rdf-migrate-{project}.log`

**Manual rollback from partial state:**
```bash
# If .rdf/ created but old dirs not removed:
rm -rf .rdf/    # safe — old dirs still intact

# If old dirs removed but .rdf/ is corrupt:
rdf init . --force    # regenerate governance from profile
```

### 8.3 Test Suite Impact

No test suites read from `.claude/governance/` or `work-output/` at
runtime. BATS tests use `mktemp -d` for isolation. Zero test impact.

### 8.4 Affected Exclude Lists

Every project's `.git/info/exclude` needs updating. `rdf migrate --all`
handles this. Individual projects use `rdf migrate`.

## 9. Dead Code and Cleanup

| Finding | Location | Lines | Action |
|---------|----------|-------|--------|
| v2 archived commands | `canonical/commands-v2-archived/` | ~2000 | Delete — v2 is dead |
| v2 archived agents | `canonical/agents-v2-archived/` | ~800 | Delete — v2 is dead |
| v2 agent metadata | `adapters/claude-code/agent-meta-v2.json` | 83 | Delete — v2 metadata |
| `audit-output/` in exclude | `lib/cmd/init.sh` line 131 | 1 | Remove — unused in 3.0 |
| `REGR.md` in exclude | `lib/cmd/init.sh` line 128 | 1 | Remove — unused in 3.0 |
| `work-output/` in exclude | `lib/cmd/init.sh` line 132 | 1 | Remove — now under `.rdf/` |
| `.claude/` in exclude | `lib/cmd/init.sh` line 130 | 1 | Remove — governance in `.rdf/` |

## 10a. Test Strategy

| Goal | Test approach | Verification |
|------|--------------|-------------|
| Goal 1: consolidate into `.rdf/` | `rdf init` on fresh project, verify structure | `ls .rdf/{governance,work-output,memory,scopes}` |
| Goal 2: `.rdf/governance/` in all canonical | grep post-migration | `grep -r '\.claude/governance/' canonical/ \| wc -l` → 0 |
| Goal 3: work-output in `.rdf/` | `rdf migrate` on project with work-output | `ls .rdf/work-output/session-log.jsonl` |
| Goal 4: memory symlink | `rdf migrate` on CC-enabled project | `readlink .rdf/memory/` resolves |
| Goal 5: three-tier hierarchy | `rdf init` + verify `~/.rdf/` + workspace `.rdf/` | `ls ~/.rdf/ {workspace}/.rdf/ {project}/.rdf/` |
| Goal 6: `rdf init` creates `.rdf/` | `rdf init` on fresh project, verify structure | `ls .rdf/{governance,work-output,memory,scopes}` |
| Goal 7: migrate command | `rdf migrate` on project with `.claude/governance/` | Exit code 0, `.claude/governance/` gone |
| Goal 8: doctor detects legacy | `rdf doctor` on unmigrated project | Output contains "WARN" for `.claude/governance/` |
| Goal 9: zero `.claude` refs | Post-migration grep | See 10b |
| Goal 10: CC deployment works | `rdf deploy claude-code` post-migration | Symlinks intact in `~/.claude/` |

RDF does not currently have BATS tests for CLI commands. Testing is
manual verification + shellcheck. Future: `tests/migrate.bats`.

## 10b. Verification Commands

```bash
# Goal 2: zero .claude/governance/ refs in canonical
grep -r '\.claude/governance/' canonical/ | wc -l
# expect: 0

# Goal 3: zero bare work-output/ refs (should all be .rdf/work-output/)
grep -r 'work-output/' canonical/ | grep -v '\.rdf/work-output/' | grep -v 'r-sync.md' | wc -l
# expect: 0

# Goal 4: zero CC auto-memory path refs
grep -r '/root/\.claude/projects/' canonical/ | wc -l
# expect: 0

# Goal 6: rdf init creates .rdf/ structure
rdf init /tmp/test-project && ls /tmp/test-project/.rdf/{governance,work-output,memory,scopes}
# expect: governance  memory  scopes  work-output

# Goal 7: migrate succeeds on all projects
rdf migrate --all
# expect: exit 0, each project shows [✓] lines

# Goal 8: doctor passes post-migration
rdf doctor --all
# expect: all OK, no WARN for .claude/governance/

# Goal 9: only CC-specific .claude refs remain
grep -r '\.claude' canonical/ | grep -v 'r-sync.md' | grep -v 'scripts/' | wc -l
# expect: 0

# Goal 10: CC deployment intact
ls -la ~/.claude/commands ~/.claude/agents ~/.claude/scripts
# expect: all symlinks pointing to adapter output/
```

## 11. Risks

1. **Stale `.claude/governance/` in unmigrated projects.** If canonical
   content is regenerated with `.rdf/` paths before projects are migrated,
   agents reference a path that doesn't exist.
   **Mitigation:** Phase ordering — CLI tooling and migration run BEFORE
   canonical content is updated.

2. **CC auto-memory symlink race.** If CC creates its memory dir before
   `rdf init` runs, the symlink setup finds an existing real directory.
   **Mitigation:** `_setup_memory_symlink()` detects existing real dir,
   preserves its contents, and replaces with symlink.

3. **Large rename diff.** 87+ files changing paths produces a noisy diff.
   **Mitigation:** Dedicated commit for string replacement, separate
   commits for structural changes.

4. **workspace `.rdf/` false discovery.** Parent of git root might
   have a `.rdf/` from an unrelated context.
   **Mitigation:** Workspace `.rdf/` only created by `rdf init` at
   known workspace roots. `rdf doctor` validates.

## 11b. Edge Cases

| # | Scenario | Expected behavior | Handling |
|---|----------|-------------------|---------|
| 1 | Both `.claude/governance/` and `.rdf/governance/` exist | Error, refuse to proceed | `rdf migrate` exits code 3, message: "conflict detected, manual resolution needed" |
| 2 | `.rdf/` exists but is empty (partial init) | Treat as fresh, populate structure | `rdf init` creates missing subdirs idempotently |
| 3 | CC auto-memory path doesn't exist (CC not installed) | Create `.rdf/memory/` as real directory | `_setup_memory_symlink()` detects absence, uses `mkdir` instead of `ln -s` |
| 4 | CC auto-memory symlink target deleted after setup | `.rdf/memory/` is dangling symlink | `rdf doctor` detects dangling symlink, offers to recreate as real dir |
| 5 | Project has sub-scope governance in `.claude/governance/` subdirs | Migrate to `.rdf/scopes/` | `_migrate_governance()` detects subdirectory governance, maps to scope names |
| 6 | `work-output/` contains files from active dispatch (mid-phase) | Migration could interrupt running agent | `rdf migrate` checks for `.rdf/work-output/current-phase.md` mtime < 1h, warns if stale |
| 7 | `.git/info/exclude` has custom entries mixed with RDF entries | Must preserve custom entries | `_update_excludes()` only removes entries matching the old RDF array, preserves everything else |
| 8 | Project is not a git repo (no `.git/`) | Cannot set up exclude, cannot determine project root | `rdf migrate` requires `.git/`, exits code 1 with message |
| 9 | Workspace root has legacy `work-output/` from RDF 2.x | Not a git repo, different scope | `rdf migrate --all` skips workspace root (no `.git/`), workspace `.rdf/` created separately |
| 10 | `rdf migrate` run twice on same project | Should be idempotent | Second run detects `.rdf/` exists, old dirs absent → exit code 2 "nothing to migrate" |

## 12. Open Questions

None — all decisions resolved.

## Phase Decomposition Guidance

**Critical: CLI tooling must be updated BEFORE canonical content.**

1. **Update CLI tooling** — init.sh, doctor.sh, refresh.sh (additive — creates `.rdf/`, backward-compat)
2. **Create `rdf migrate` command** — new `lib/cmd/migrate.sh`
3. **Migrate active projects** — `rdf migrate --all` across workspace
4. **Update canonical agents** — 4 files, governance path only
5. **Update canonical commands** — 30 files, governance + work-output paths
6. **Update canonical templates and reference** — 9 files
7. **Update documentation** — README, RDF.md, CLAUDE.md, profiles
8. **Delete dead code** — v2 archives, stale metadata
9. **Regenerate, verify, push** — `rdf generate all`, `rdf doctor --all`
