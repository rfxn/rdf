You are running the /r:refresh governance refresh. This command
re-scans the codebase and updates governance files to match current
reality, preserving user modifications.

## Arguments

$ARGUMENTS — optional scope:
- No args or `all`: full refresh (governance + state files)
- `governance`: refresh .claude/governance/ files only
- `state`: refresh MEMORY.md and PLAN.md only (v2 behavior)
- `github`: sync GitHub issue state with local plan (deterministic)

## Setup

- Read .claude/governance/index.md to understand current governance
- Check governance file ages (modification times)
- Read .claude/governance/.user-modified if it exists (list of files
  the user has manually edited — these get merge treatment, not
  overwrite)

## Stage 1: Codebase Re-Scan (init phases 2-3)

Re-run the /r:init codebase analysis against current state:

### 1a. Phase 2 — Codebase Scan
- Language detection (file extensions, shebangs, package manifests)
- Framework detection (package.json deps, imports, config files)
- Directory structure mapping (src/, tests/, lib/, etc.)
- Build system (Makefile, package.json scripts, CI configs)
- Test framework (jest, pytest, bats, go test, etc.)
- Linter/formatter configs (.eslintrc, .prettierrc, shellcheck, etc.)

### 1b. Phase 3 — Tooling & Infrastructure Detection
- CI/CD: .github/workflows/, .gitlab-ci.yml, Jenkinsfile
- Containers: Dockerfile, docker-compose.yml
- Platform targets: CI matrix, target OS in configs
- Dependencies: lockfiles, version constraints
- Git patterns: branch naming, commit conventions (from log)

### 1c. Diff Against Current Governance
- Compare scan results with existing governance files
- Identify: new findings, removed findings, changed findings
- Track drift (governance says X but codebase now shows Y)

## Stage 2: Re-Ingest Authoritative Files (init phase 1, partial)

- Re-read CLAUDE.md, AGENTS.md, and other convention files
- Compare against governance references to these files
- If authoritative files have changed, update governance pointers
- Do NOT modify the authoritative files themselves

## Stage 3: Update Governance Files (init phase 4)

For each governance file in .claude/governance/:

### 3a. Check User-Modified Status
- If the file is listed in .user-modified: MERGE mode
  - Show the user what would change
  - Ask for confirmation before applying
  - Preserve user additions, update only generated sections
- If the file is NOT user-modified: UPDATE mode
  - Overwrite with regenerated content

### 3b. Update Each File
- index.md — regenerate from current scan (always updated)
- architecture.md — update component map, boundaries
- conventions.md — update coding patterns from scan
- verification.md — update check list from detected tools
- constraints.md — update platform targets, version floors
- anti-patterns.md — update from codebase patterns

### 3c. Track Changes
- Record what changed in each file
- Note any new governance files needed (new framework detected, etc.)
- Note any governance files that are now unnecessary (framework removed)

## Stage 4: Validate (init phase 5)

- Spot-check updated governance against codebase
- Verify file references in index.md still point to existing files
- Flag low-confidence inferences for user review
- If drift was detected in Stage 1, report it prominently

## Stage 5: Refresh State Files (if scope includes state)

### 5a. Refresh MEMORY.md
- Locate MEMORY.md (auto-memory path or project-local)
- Update version, branch, HEAD hash from git
- Update test count from test files
- Append new commits since last recorded hash
- Cross-reference PLAN.md phase statuses
- Size guard: warn if >= 180 lines

### 5b. Refresh PLAN.md
- Cross-reference phases against git log
- Mark completed phases with commit hash evidence
- Update status summary

### 5c. Sync GitHub Issues (if scope includes github)
- Cross-reference GitHub issues with PLAN.md
- Close phase issues for completed phases
- Reopen issues for incomplete phases marked closed
- Update initiative status if all children complete

## Stage 6: Output Summary

    ## Refresh: {project} {version} ({branch})

    ### Governance
    - index.md: {updated/unchanged}
    - architecture.md: {updated/unchanged/user-modified merge}
    - conventions.md: {updated/unchanged/user-modified merge}
    - verification.md: {updated/unchanged}
    - constraints.md: {updated/unchanged}
    - anti-patterns.md: {updated/unchanged}

    ### Drift Detected
    - {description of each drift item, or "None"}

    ### State Files
    - MEMORY.md: {updated/skipped/not found} — {N} new commits
    - PLAN.md: {updated/skipped/not found} — {N} phases updated
    - GitHub: {synced/skipped/not configured} — {N} resolved

    ### Low-Confidence Items
    - {items flagged for user review, or "None"}

## Constraints
- Never overwrite user-modified governance files without confirmation
- Never modify authoritative files (CLAUDE.md, AGENTS.md, etc.)
- Always validate governance after update (phase 5 spot-check)
- State file refresh follows the same rules as v2 /refresh:
  grep from source, never forward-copy stale values
- Do NOT commit — refresh is a working-tree operation only
