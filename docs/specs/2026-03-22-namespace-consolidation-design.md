# RDF Namespace Consolidation — Design Spec

## 1. Problem Statement

RDF-owned committed artifacts (specs, plans) live in `docs/specs/` and
`docs/plans/` — a namespace the framework does not own. `docs/` is a
common directory in software projects (Sphinx output, API docs, user
guides). RDF squatting there creates collision risk when governing
projects with their own `docs/` directory.

Current state across 7 projects with committed RDF artifacts:
- 33 files across `docs/specs/`, `docs/plans/`, `docs/superpowers/specs/`,
  `docs/superpowers/plans/` (including 1 non-plan metadata file)
- 9 archived plans in `docs/plans/archived/` (RDF only)
- 11 projects have `docs/` directories created by RDF
- `docs/superpowers/` is a parallel hierarchy duplicating the
  `specs/`+`plans/` structure with no differentiation

Additionally:
- Session `PLAN.md` has no end-of-life — completed plans accumulate
  or get dumped into ad-hoc `old_plans/` directories (2 instances)
- 24+ canonical references hardcode `docs/specs/` as the spec output path
- `.rdf/` is wholly excluded from git via `.git/info/exclude`, preventing
  any committed content inside it
- No framework convention prevents volatile state from accumulating in
  documentation artifacts

## 2. Goals

1. All RDF-owned committed artifacts live under `.rdf/` — single
   namespace, clear ownership, zero collision with project `docs/`
2. `.rdf/` supports both committed and ephemeral content via
   `.rdf/.gitignore` (exclude-by-default, whitelist by exception)
3. Session `PLAN.md` is auto-promoted to `.rdf/plans/` on completion
   (dedup-aware: keep newest if duplicate exists), then deleted
4. `rdf migrate` handles full namespace migration: `docs/{specs,plans}/`,
   `docs/superpowers/{specs,plans}/`, `docs/plans/archived/`
5. All canonical references updated from `docs/specs/` to `.rdf/specs/`
   and `docs/plans/` to `.rdf/plans/`
6. `rdf doctor` validates new structure and detects legacy layout
7. `old_plans/` directories eliminated

## 3. Non-Goals

- Relocating project-owned `docs/` content (e.g., `docs/demo-walkthrough.md`)
- Changing the `~/.rdf/` global state directory structure
- Modifying the governance, work-output, or memory directory structure
- Adding new artifact types (only moving existing specs/plans)
- Changing spec or plan file naming conventions (date-prefix stays)
- Modifying CLAUDE.md, MEMORY.md, or AUDIT.md lifecycle

## 4. Architecture

### File Map

| File | Action | Est. Lines | Purpose |
|------|--------|-----------|---------|
| `.rdf/.gitignore` | NEW | 8 | Exclude-by-default, whitelist specs/ and plans/ |
| `lib/cmd/init.sh` | MODIFY | ~20 changed | Create `.rdf/.gitignore`, remove `.rdf/` from exclude entries, add legacy detection |
| `lib/cmd/migrate.sh` | MODIFY | ~80 added | New `_migrate_namespace()` function for docs/ → .rdf/ migration |
| `lib/cmd/doctor.sh` | MODIFY | ~25 changed | New checks for `.rdf/.gitignore`, legacy `docs/specs/` detection, remove `.rdf/` exclude check |
| `state/rdf-state.sh` | MODIFY | ~5 changed | Update specs path from `docs/specs` to `.rdf/specs` |
| `canonical/commands/r-spec.md` | MODIFY | ~12 changed | Update output path from `docs/specs/` to `.rdf/specs/` |
| `canonical/commands/r-plan.md` | MODIFY | ~8 changed | Update spec scan path |
| `canonical/commands/r-build.md` | MODIFY | ~20 added | Add PLAN.md promotion logic at plan completion |
| `canonical/commands/r-save.md` | MODIFY | ~4 changed | Update `docs/specs/` references |
| `canonical/commands/r-status.md` | MODIFY | ~4 changed | Update spec path references |
| `canonical/commands/r-review.md` | MODIFY | ~2 changed | Update spec path reference |
| `canonical/commands/r-init.md` | MODIFY | ~6 changed | Update exclusion documentation |
| `canonical/commands/r-vpe.md` | MODIFY | ~2 changed | Update `docs/specs/` reference |
| `canonical/commands/r-refresh.md` | MODIFY | ~2 changed | Update `docs/specs/` reference |
| `canonical/reference/framework.md` | MODIFY | ~4 changed | Update archived plans path |
| `profiles/core/governance-template.md` | MODIFY | ~4 changed | Update artifact taxonomy, remove `.rdf/` from never-commit list |
| `assets/pipeline.svg` | MODIFY | ~2 changed | Update `docs/specs/*.md` label |
| `README.md` | MODIFY | ~2 changed | Update spec output path reference |
| `CLAUDE.md` | MODIFY | ~4 changed | Update `.rdf/` exclusion statement, spec/plan paths |

### No-Touch Files

These files exist near the change boundary but must NOT be modified:

- `lib/cmd/generate.sh` — adapter generation, no docs/ references
- `lib/cmd/sync.sh` — canonical sync, no docs/ references
- `canonical/commands/r-build.md` — reads PLAN.md (root), no docs/ path
- `canonical/commands/r-ship.md` — release workflow, no docs/ path
- `canonical/commands/r-vpe.md` — pipeline orchestrator, no docs/ path
- `canonical/agents/*.md` — agents reference governance, not docs/
- `profiles/*/governance-template.md` (non-core) — no docs/ references

**Workspace coordination (not in RDF repo):**
- `/root/admin/work/proj/CLAUDE.md` — lists `.rdf/` in "never commit"
  and references `docs/specs/` as committed artifacts. Must be updated
  manually after RDF canonical changes land. Not a git-tracked file.

### Dependency Tree

```
.rdf/.gitignore (NEW — must exist before any committed content)
    │
    ├── lib/cmd/init.sh
    │   ├── _GIT_EXCLUDE_ENTRIES[] — remove ".rdf/" entry
    │   ├── _setup_git_exclude() — remove ".rdf/" from exclude, add legacy removal
    │   └── _create_rdf_structure() — write .rdf/.gitignore during dir creation
    │
    ├── lib/cmd/migrate.sh
    │   ├── _migrate_namespace() — NEW: git mv docs/ content to .rdf/
    │   ├── _remove_rdf_exclude() — NEW: remove ".rdf/" from info/exclude
    │   └── main flow — call _migrate_namespace after existing migration
    │
    ├── lib/cmd/doctor.sh
    │   ├── _check_artifacts() — check .rdf/.gitignore, remove .rdf/ exclude check
    │   └── legacy detection — warn on docs/specs/ or docs/plans/
    │
    ├── state/rdf-state.sh
    │   └── specs count — scan .rdf/specs/ instead of docs/specs/
    │
    └── canonical/ (8 command files + framework.md + README.md)
        ├── r-spec, r-plan, r-save, r-status, r-review, r-init
        ├── r-vpe, r-refresh
        └── path string replacements: docs/specs/ → .rdf/specs/
```

### Key Changes

**1. `.rdf/.gitignore` mechanism (new)**

```gitignore
# RDF namespace — excluded by default, committed by exception
*
!.gitignore
!specs/
!specs/**
!plans/
!plans/**
```

This file is the linchpin. It makes `.rdf/` a mixed namespace:
- Everything is excluded by default (governance, work-output, memory,
  scopes, any future subdirectory)
- Only `specs/` and `plans/` are whitelisted for git tracking
- The `.gitignore` itself is committed (self-documenting, propagates on clone)
- No `.git/info/exclude` entry needed for `.rdf/` — the internal
  `.gitignore` handles all exclusion

**2. `info/exclude` transition**

The `.rdf/` entry is REMOVED from `.git/info/exclude`. This is required
because git cannot override a parent-level exclude from within a child
`.gitignore`. The `.rdf/.gitignore` with `*` handles exclusion of
ephemeral subdirectories instead.

Working files that remain in `info/exclude`: `CLAUDE.md`, `PLAN*.md`,
`AUDIT.md`, `MEMORY.md`.

**3. PLAN.md lifecycle (new)**

On plan completion (all phases executed):
1. Derive topic slug from PLAN.md heading or spec reference
2. Check `.rdf/plans/` for existing plan with matching topic
3. If match found: compare mtime, keep newest
4. If no match: copy `PLAN.md` to `.rdf/plans/YYYY-MM-DD-{topic}.md`
5. `git add` and commit the promoted plan
6. Delete session `PLAN.md`

This is implemented in `/r-build` (dispatcher) at plan completion.
The dispatcher already tracks phase completion and is the authority
on when all phases are done. Adding promotion here avoids splitting
the logic across commands.

**`_promote_session_plan()` function inventory:**

| Function | Signature | Purpose | Dependencies |
|----------|-----------|---------|--------------|
| `_promote_session_plan()` | (plan_path, dest_dir) | Promote PLAN.md to .rdf/plans/, dedup, delete session file | slug derivation, mtime comparison |

Implementation location: new section in `r-build.md` canonical command,
called after all phases complete and before the completion summary.
The function:
1. Reads first `# ` heading from PLAN.md
2. Derives slug (see Section 6 conventions)
3. Checks `.rdf/plans/` for `*-{slug}.md` matches
4. If match: compare mtime, keep newest (overwrite or skip)
5. If no match: copy to `.rdf/plans/YYYY-MM-DD-{slug}.md`
6. `git add` the promoted file
7. Delete session PLAN.md

**4. `docs/superpowers/` elimination**

Superpowers specs and plans are just specs and plans. They merge into
`.rdf/specs/` and `.rdf/plans/` during migration. The `superpowers/`
directory and namespace are eliminated entirely.

### Dependency Rules

- `.rdf/.gitignore` MUST be created before any content is added to
  `.rdf/specs/` or `.rdf/plans/` — otherwise the first `git add`
  will not track the files
- `.rdf/` MUST be removed from `.git/info/exclude` before
  `.rdf/.gitignore` can take effect — parent exclude overrides child
- Migration MUST use `git mv` (not `cp` + `rm`) to preserve history
- `rdf doctor` must detect BOTH old and new layouts during the
  transition period

## 5. File Contents

### `.rdf/.gitignore` (NEW — 8 lines)

Static file, no functions. Created by `/r-init` and `rdf migrate`.

```
# RDF namespace — excluded by default, committed by exception
*
!.gitignore
!specs/
!specs/**
!plans/
!plans/**
```

### `lib/cmd/init.sh` — Changes

| Function | Current Behavior | New Behavior | Lines Affected |
|----------|-----------------|--------------|----------------|
| `_GIT_EXCLUDE_ENTRIES[]` | Contains `".rdf/"` | Remove `".rdf/"` entry | 225-232 |
| `_setup_git_exclude()` | Adds `.rdf/` to exclude | Skips `.rdf/`, removes stale `.rdf/` entry if present | 235-292 |
| (new) `_create_rdf_gitignore()` | N/A | Writes `.rdf/.gitignore` if missing | ~15 new lines |
| `.rdf/` directory creation block | Creates governance, work-output, scopes | Also calls `_create_rdf_gitignore()` | near 355 |

**`_create_rdf_gitignore()` function inventory:**

| Function | Signature | Purpose | Dependencies |
|----------|-----------|---------|--------------|
| `_create_rdf_gitignore()` | `(path)` | Write `.rdf/.gitignore` whitelist file if not present | None |

Logic:
1. Check if `.rdf/.gitignore` exists
2. If missing, write the 8-line gitignore content
3. If present, verify it contains the `!specs/` and `!plans/` whitelist
   entries (future-proofing for adding new whitelisted dirs)
4. Log action

### `lib/cmd/migrate.sh` — Changes

| Function | Current Behavior | New Behavior | Lines Affected |
|----------|-----------------|--------------|----------------|
| main migrate flow | Calls governance, workoutput, memory, excludes | Also calls `_migrate_namespace()` | near 257-260 |
| (new) `_migrate_namespace()` | N/A | Moves docs/{specs,plans,superpowers} to .rdf/ | ~60 new lines |
| (new) `_remove_rdf_exclude()` | N/A | Removes `.rdf/` line from .git/info/exclude | ~20 new lines |

**`_migrate_namespace()` function inventory:**

| Function | Signature | Purpose | Dependencies |
|----------|-----------|---------|--------------|
| `_migrate_namespace()` | `(project_path, dry_run, log_file)` | Move docs/ RDF artifacts to .rdf/ | `_create_rdf_gitignore()`, `_remove_rdf_exclude()` |

Logic:
1. Call `_create_rdf_gitignore()` to ensure `.rdf/.gitignore` exists
2. Call `_remove_rdf_exclude()` to remove `.rdf/` from `info/exclude`
3. Create `.rdf/specs/` and `.rdf/plans/` if missing
4. If `docs/specs/*.md` exists: `git mv` each file to `.rdf/specs/`
5. If `docs/plans/*.md` exists: `git mv` each date-prefixed file
   (`YYYY-MM-DD-*.md`) to `.rdf/plans/`. Non-date-prefixed files
   (e.g., `github-project-ids.md`) are skipped with a warning —
   user must relocate manually
6. If `docs/plans/archived/*.md` exists: `git mv` each to `.rdf/plans/`
7. If `docs/superpowers/specs/*.md` exists: `git mv` each to `.rdf/specs/`
8. If `docs/superpowers/plans/*.md` exists: `git mv` each to `.rdf/plans/`
9. Remove empty `docs/specs/`, `docs/plans/`, `docs/superpowers/`, `docs/`
   (only if completely empty after migration)
10. Log summary: N files moved, directories cleaned

**`_remove_rdf_exclude()` function inventory:**

| Function | Signature | Purpose | Dependencies |
|----------|-----------|---------|--------------|
| `_remove_rdf_exclude()` | `(project_path, dry_run)` | Remove `.rdf/` line from `.git/info/exclude` | None |

Shared by both `init.sh` (via `_setup_git_exclude`) and `migrate.sh`.
Implemented in `migrate.sh` as it is the primary consumer. `init.sh`
calls it defensively (handles case where `.rdf/` entry exists from a
prior init run before the convention change).

Logic:
1. Read `.git/info/exclude`
2. Filter out the line `.rdf/` (exact match)
3. Write back without that line (preserve all other entries)
4. Log action

### `lib/cmd/doctor.sh` — Changes

| Function | Current Behavior | New Behavior | Lines Affected |
|----------|-----------------|--------------|----------------|
| `_check_artifacts()` | Checks `.rdf/` in exclude entries (line 88) | Check `.rdf/.gitignore` exists instead; remove `.rdf/` from exclude check list | 83-101 |
| `_check_artifacts()` | No legacy docs/ detection | WARN if `docs/specs/` or `docs/plans/` exist (suggest `rdf migrate`) | new ~6 lines |
| `_check_artifacts()` | No `.rdf/.gitignore` check | OK if `.rdf/.gitignore` present with correct whitelist | new ~8 lines |
| `_check_artifacts()` | No `.gitignore` conflict check | WARN if project-root `.gitignore` contains `.rdf` pattern | new ~5 lines |

### `state/rdf-state.sh` — Changes

| Function | Current Behavior | New Behavior | Lines Affected |
|----------|-----------------|--------------|----------------|
| specs count block | Scans `docs/specs` (line 203) | Scans `.rdf/specs`, fallback to `docs/specs` for unmigrated projects | 203-206 |

### Canonical Commands — Path Updates

All changes are string replacements of `docs/specs/` → `.rdf/specs/`
and `docs/plans/` → `.rdf/plans/`.

**`r-spec.md`** (6 replacements):

| Line | Old | New |
|------|-----|-----|
| 114 | `docs/specs/` directory | `.rdf/specs/` directory |
| 320 | `docs/specs/YYYY-MM-DD-{topic}-design.md` | `.rdf/specs/YYYY-MM-DD-{topic}-design.md` |
| 461 | `SPEC_PATH: docs/specs/{filename}` | `SPEC_PATH: .rdf/specs/{filename}` |
| 506 | `File: docs/specs/{filename}` | `File: .rdf/specs/{filename}` |
| 534 | `Spec finalized: docs/specs/{filename}` | `Spec finalized: .rdf/specs/{filename}` |
| 552-559 | `docs/specs/{filename}` (2 occurrences) | `.rdf/specs/{filename}` |

**`r-plan.md`** (5 replacements):

| Line | Old | New |
|------|-----|-----|
| 12 | `docs/specs/` | `.rdf/specs/` |
| 13 | `docs/specs/foo.md` | `.rdf/specs/foo.md` |
| 24 | `docs/specs/` | `.rdf/specs/` |
| 30-31 | `docs/specs/` (2 occurrences) | `.rdf/specs/` |
| 147 | `docs/specs/{filename}` | `.rdf/specs/{filename}` |

**`r-save.md`** (2 replacements):

| Line | Old | New |
|------|-----|-----|
| 98 | `docs/specs/` → specs | `.rdf/specs/` → specs |
| 109 | `docs/specs/` has files | `.rdf/specs/` has files |

**`r-status.md`** (2 replacements):

| Line | Old | New |
|------|-----|-----|
| 92 | `docs/specs/2026-03-19-foo.md` | `.rdf/specs/2026-03-19-foo.md` |
| 99 | `docs/specs/` | `.rdf/specs/` |

**`r-review.md`** (1 replacement):

| Line | Old | New |
|------|-----|-----|
| 31 | `docs/specs/` | `.rdf/specs/` |

**`r-vpe.md`** (1 replacement):

| Line | Old | New |
|------|-----|-----|
| 112 | `docs/specs/` | `.rdf/specs/` |

**`r-refresh.md`** (1 replacement):

| Line | Old | New |
|------|-----|-----|
| 213 | `docs/specs/` | `.rdf/specs/` |

**`r-init.md`** (1 replacement):

| Line | Old | New |
|------|-----|-----|
| 720-722 | `verify .rdf/ is in .git/info/exclude` | describe `.rdf/.gitignore` mechanism; remove exclude instruction |

### Other Files — Path Updates

**`canonical/reference/framework.md`:**

| Line | Old | New |
|------|-----|-----|
| 139 | `docs/plans/archived/` | `.rdf/plans/` (archived plans merge into main plans dir) |

**`assets/pipeline.svg`:**

| Line | Old | New |
|------|-----|-----|
| 31 | `Output: docs/specs/*.md` | `Output: .rdf/specs/*.md` |

**`README.md`:**

| Line | Old | New |
|------|-----|-----|
| 120 | `docs/specs/*.md` | `.rdf/specs/*.md` |

**`profiles/core/governance-template.md`:**

| Line | Old | New |
|------|-----|-----|
| 12-13 | `.rdf/) -- exclude via .git/info/exclude` | remove `.rdf/` from never-commit list; add note about `.rdf/.gitignore` |
| 52 | `CLAUDE.md -- project governance` | keep as-is |
| 56 | `.rdf/ -- per-project RDF state` | update to describe mixed committed/ephemeral model |

**`CLAUDE.md` (RDF project):**

| Line | Old | New |
|------|-----|-----|
| 27 | `Never commit: ... .rdf/` | Remove `.rdf/` from never-commit list |
| 28 | `Specs (docs/specs/) and plans (docs/plans/) ARE committed` | `Specs (.rdf/specs/) and plans (.rdf/plans/) ARE committed` |

### 5b. Examples

**After `/r-init` on a new project:**
```
$ rdf init
  [✓] .rdf/ created
  [✓] .rdf/.gitignore created
  [✓] .rdf/governance/ created
  [✓] .rdf/work-output/ created
  [✓] added 4 entries to .git/info/exclude

$ cat .rdf/.gitignore
# RDF namespace — excluded by default, committed by exception
*
!.gitignore
!specs/
!specs/**
!plans/
!plans/**

$ git status
Untracked files:
  .rdf/.gitignore

$ cat .git/info/exclude | grep -v '^#'
CLAUDE.md
PLAN*.md
AUDIT.md
MEMORY.md
```

Note: `.rdf/` is NOT in `info/exclude`. `.rdf/.gitignore` handles
exclusion of ephemeral subdirs.

**After `/r-spec` writes a spec:**
```
$ ls .rdf/specs/
2026-03-22-namespace-consolidation-design.md

$ git status
Untracked files:
  .rdf/specs/2026-03-22-namespace-consolidation-design.md
```

**After `rdf migrate` on a project with existing docs/:**
```
$ rdf migrate
  migrating brute-force-detection to .rdf/ structure...
  [✓] .rdf/.gitignore created
  [✓] removed .rdf/ from .git/info/exclude
  [✓] git mv docs/specs/cdn-trusted-proxy-design.md → .rdf/specs/
  [✓] git mv docs/superpowers/specs/bfd-lib-decomposition-design.md → .rdf/specs/
  [✓] removed empty docs/specs/
  [✓] removed empty docs/superpowers/specs/
  [✓] removed empty docs/superpowers/
  [✓] docs/ has remaining content — preserved
  namespace migration: 2 files moved

$ git status
Changes to be committed:
  renamed: docs/specs/2026-03-21-cdn-trusted-proxy-design.md
        -> .rdf/specs/2026-03-21-cdn-trusted-proxy-design.md
  renamed: docs/superpowers/specs/2026-03-18-bfd-lib-decomposition-design.md
        -> .rdf/specs/2026-03-18-bfd-lib-decomposition-design.md
  new file: .rdf/.gitignore
```

**PLAN.md promotion on completion:**
```
# After all plan phases are executed:
  [✓] Plan complete — all 5 phases executed
  [✓] No existing plan for "namespace-consolidation" in .rdf/plans/
  [✓] Promoted PLAN.md → .rdf/plans/2026-03-22-namespace-consolidation.md
  [✓] Deleted session PLAN.md
```

**Error case — `.rdf/` still in `info/exclude`:**
```
$ rdf doctor
  [WARN] .rdf/ found in .git/info/exclude — blocks committed specs/plans.
         Run 'rdf migrate' to fix.
```

## 6. Conventions

### `.rdf/.gitignore` template (verbatim)

```gitignore
# RDF namespace — excluded by default, committed by exception
*
!.gitignore
!specs/
!specs/**
!plans/
!plans/**
```

This is the canonical content. Written by `_create_rdf_gitignore()` in
`init.sh` and verified by `rdf doctor`. Future whitelisted directories
are added here (append `!dirname/` and `!dirname/**`).

### Spec file naming

```
.rdf/specs/YYYY-MM-DD-{topic}-design.md
```

Date-prefixed, hyphenated topic slug, `-design.md` suffix. Unchanged
from current convention — only the parent directory changes.

### Plan file naming

```
.rdf/plans/YYYY-MM-DD-{topic}.md
```

Date-prefixed, hyphenated topic slug, plain `.md`. Promoted session
plans and formal plans use the same naming.

### PLAN.md promotion slug derivation

1. Read first `# ` heading from `PLAN.md`
2. Extract topic: strip "Implementation Plan:", "Plan:", etc. prefixes
3. Slugify: lowercase, replace spaces/special chars with hyphens,
   collapse consecutive hyphens, strip leading/trailing hyphens
4. Prepend date: `YYYY-MM-DD-{slug}.md`
5. If slug derivation fails, use `YYYY-MM-DD-session-plan.md`

### Migration detection in `rdf doctor`

Legacy layout indicators (any triggers WARN + suggest `rdf migrate`):
- `docs/specs/` directory exists with `.md` files
- `docs/plans/` directory exists with `.md` files
- `docs/superpowers/` directory exists
- `.rdf/` appears in `.git/info/exclude`
- `.rdf/.gitignore` is missing

## 7. Interface Contracts

### CLI changes

**`rdf migrate`** gains namespace migration capability. No new flags —
the migrate command auto-detects which migrations are needed (existing
`.claude/` → `.rdf/` migration continues to work, namespace migration
is additive).

**`rdf doctor`** gains 3 new checks, loses 1:
- NEW: `.rdf/.gitignore` present and correct
- NEW: no legacy `docs/specs/` or `docs/plans/`
- NEW: `.rdf/` not in `.git/info/exclude`
- REMOVED: `.rdf/` in `.git/info/exclude` (was OK, now WARN)

**`rdf init`** creates `.rdf/.gitignore` during directory setup.
No longer adds `.rdf/` to `.git/info/exclude`.

### File format changes

None. Spec and plan files are plain markdown with no format changes.
Only their location changes.

### Config changes

None.

## 8. Migration Safety

### Upgrade path (existing RDF 3.0.x → post-consolidation)

1. User updates RDF (`git pull` in rdf project)
2. User runs `rdf migrate` in each project
3. Migration is idempotent — running twice is safe
4. Projects that have not yet migrated continue to work — `rdf-state.sh`
   falls back to `docs/specs/` if `.rdf/specs/` is empty

### Install path (new `/r-init`)

New projects get the new layout from the start. No migration needed.
`.rdf/.gitignore` is created during init, `.rdf/` is not added to
`info/exclude`.

### Rollback

If migration needs to be reversed:
1. `git mv .rdf/specs/* docs/specs/` and `git mv .rdf/plans/* docs/plans/`
2. Add `.rdf/` back to `.git/info/exclude`
3. Remove `.rdf/.gitignore`

This is manual but straightforward. No data loss is possible because
`git mv` preserves history.

### Backward compatibility

- Old RDF versions will not recognize `.rdf/specs/` — they will see
  zero specs and report pipeline as `idle`. This is cosmetic, not
  breaking.
- The `docs/` directory may become empty after migration. Empty
  `docs/` is removed by the migration. If a project has non-RDF
  content in `docs/` (e.g., `docs/demo-walkthrough.md`), only the
  RDF subdirectories are removed.

### Test suite impact

RDF's own tests: `rdf doctor` tests need updating for new checks.
No other project test suites are affected — tests don't reference
`docs/specs/` or `docs/plans/`.

## 9. Dead Code and Cleanup

| Item | Location | Action |
|------|----------|--------|
| `docs/plans/archived/` convention | `framework.md:139` | Remove — archived plans merge into `.rdf/plans/` |
| `old_plans/` skip in doctor | `doctor.sh:546` | Remove — `old_plans/` directories deleted |
| `docs/superpowers/` namespace | 6 projects | Eliminated — content merges into `.rdf/{specs,plans}` |
| `old_plans/` directories | 2 workspace locations | Delete outright |

## 10a. Test Strategy

| Goal | Test Method | Verification |
|------|------------|-------------|
| Goal 1: artifacts under `.rdf/` | `rdf init` on fresh project, verify `.rdf/specs/` and `.rdf/plans/` are git-trackable | `git add .rdf/specs/test.md` succeeds without `-f` |
| Goal 2: `.rdf/.gitignore` mechanism | Create files in `.rdf/governance/` and `.rdf/specs/`, verify only specs tracked | `git status` shows specs, not governance |
| Goal 3: PLAN.md promotion | Complete a plan, verify promotion to `.rdf/plans/` and PLAN.md deletion | File exists in `.rdf/plans/`, PLAN.md gone |
| Goal 4: `rdf migrate` | Run on project with `docs/specs/`, verify files moved and git history preserved | `git log --follow .rdf/specs/file.md` shows pre-move history |
| Goal 5: canonical references | Grep all canonical/ for `docs/specs/` | Zero matches |
| Goal 6: `rdf doctor` | Run on migrated and unmigrated projects | Correct OK/WARN for each state |
| Goal 7: `old_plans/` gone | Verify directories deleted | `test ! -d old_plans/` |

## 10b. Verification Commands

```bash
# Goal 1: No committed artifacts under docs/specs/ or docs/plans/
find . -path './docs/specs/*.md' -o -path './docs/plans/*.md' | wc -l
# expect: 0

# Goal 2: .rdf/.gitignore exists and has correct content
head -1 .rdf/.gitignore
# expect: # RDF namespace — excluded by default, committed by exception

grep -c '!specs/' .rdf/.gitignore
# expect: 1

# Goal 3: .rdf/ NOT in .git/info/exclude
grep -cxF '.rdf/' .git/info/exclude
# expect: 0

# Goal 4: Ephemeral dirs excluded, committed dirs tracked
git status .rdf/governance/ 2>&1 | head -1
# expect: (empty or "nothing to commit" — governance is excluded)

touch .rdf/specs/test-verify.md && git add .rdf/specs/test-verify.md && echo "ok" && git rm --cached .rdf/specs/test-verify.md > /dev/null && rm .rdf/specs/test-verify.md
# expect: ok (no -f needed)

# Goal 5: No canonical references to old paths
grep -r 'docs/specs/' canonical/ | grep -v '.rdf/specs/' | wc -l
# expect: 0

grep -r 'docs/plans/' canonical/ | grep -v '.rdf/plans/' | wc -l
# expect: 0

# Goal 6: rdf doctor passes on migrated project
rdf doctor . 2>&1 | grep -c FAIL
# expect: 0

# Goal 7: No old_plans/ in workspace
find /root/admin/work/proj -maxdepth 2 -name old_plans -type d | wc -l
# expect: 0
```

## 11. Risks

1. **Partial migration leaves split-brain state.** A project with
   specs in both `docs/specs/` and `.rdf/specs/` would confuse
   commands that scan for specs.
   *Mitigation:* `rdf migrate` moves ALL content atomically. `rdf doctor`
   warns on any legacy `docs/specs/` or `docs/plans/` presence.
   `rdf-state.sh` falls back to `docs/specs/` if `.rdf/specs/` is empty.

2. **User adds `.rdf/` to project `.gitignore`.** Natural instinct for
   a dot-prefixed directory. Would silently prevent specs/plans from
   being tracked.
   *Mitigation:* `rdf doctor` checks for `.rdf` in `.gitignore` and
   warns. Document in governance template that `.rdf/` exclusion is
   managed by `.rdf/.gitignore`, not project-level gitignore.

3. **`git mv` across dot-directory boundary may not follow in all git
   versions.** `git log --follow` across renames into dot-directories
   has historically been unreliable in older git versions.
   *Mitigation:* Test on git 2.x (CentOS 7 floor). If `--follow` breaks,
   document that pre-move history requires `git log -- docs/specs/file.md`.

4. **PLAN.md promotion creates duplicate if topic slug derivation is
   inconsistent.** Different sessions for the same topic could produce
   different slugs.
   *Mitigation:* Dedup check uses fuzzy matching on date + first 3 words
   of slug. If ambiguous, keep both — false duplicates are preferable
   to lost plans.

5. **IDE/tooling hides `.rdf/` dot-directory.** Specs and plans become
   less discoverable in file trees.
   *Mitigation:* Agents access specs/plans by path, not browsing. Users
   who need to browse can configure IDE to show dot-directories. This
   is an accepted trade-off for namespace safety.

## 11b. Edge Cases

| Scenario | Expected Behavior | Handling |
|----------|-------------------|---------|
| Project has `docs/` with non-RDF content (e.g., `docs/README.md`) | Only RDF subdirs (`specs/`, `plans/`, `superpowers/`) are moved; `docs/` preserved with remaining content | `_migrate_namespace()` checks `docs/` empty after RDF content removal before deleting |
| `.rdf/.gitignore` already exists with different content | Verify whitelist entries present; append missing ones, don't overwrite custom additions | `_create_rdf_gitignore()` checks for `!specs/` line, appends if missing |
| Project has no `.git/` (not a git repo) | Skip all git operations (exclude manipulation, git mv) | `_migrate_namespace()` uses `command mv` fallback, warns that history won't be preserved |
| `.rdf/` in both `.git/info/exclude` AND `.rdf/.gitignore` exists | Remove from `info/exclude` — `.rdf/.gitignore` is sufficient | `_remove_rdf_exclude()` always runs during migrate |
| `docs/specs/` and `.rdf/specs/` both have content (partial prior migration) | Move only files from `docs/specs/` that don't already exist in `.rdf/specs/` | Check destination before `git mv`; skip with warning if duplicate filename |
| PLAN.md has no heading (can't derive slug) | Use fallback slug `session-plan` | Slug derivation returns `session-plan` on empty/missing heading |
| PLAN.md promotion target already exists with same name but different content | Compare mtime, keep newest, log which was discarded | `_promote_plan()` reads mtime of both, overwrites older |
| `rdf migrate` run twice on same project | Idempotent — no files to move, no exclude to remove, logs "already migrated" | Each step checks preconditions before acting |
| Project uses `.gitignore` (not `info/exclude`) with `.rdf/` entry | `rdf doctor` warns; `rdf migrate` cannot fix project gitignore automatically | Doctor outputs: "`.rdf/` found in .gitignore — remove manually; .rdf/.gitignore handles exclusion" |
| `git mv` fails (file locked, permission denied) | Abort migration with error, leave project in pre-migration state | `_migrate_namespace()` checks `git mv` exit code, rolls back on failure |

## 12. Open Questions

None. All design decisions resolved during brainstorming.
