Shared library release lifecycle. Handles pre-flight checks, release
preparation, and consumer drift notification.

## Arguments
- `$ARGUMENTS` — required: library name or path

## Setup

Read `.claude/governance/index.md` to identify:
- Library metadata (name, version, repository)
- Consumer projects that use this library
- Release conventions from governance

If the argument does not match a known library, treat it as a directory
path and attempt to identify it as a library project.

## Procedure

### 1. Pre-flight checks

Switch to the library directory and verify readiness:

**Branch validation:**
- `git branch --show-current` — must be the version branch
- `git status` — working tree must be clean
- `git log origin/<branch>..HEAD` — check for unpushed commits

**PLAN verification:**
- Read the library's PLAN file
- Verify ALL phases are COMPLETED/DONE
- If any phases are incomplete, list them and STOP

**Release readiness:**
- Verify version strings are consistent across files
- Check for uncommitted changes
- Verify tests pass

Report pre-flight status with branch, PLAN, and readiness sections.

### 2. Release preparation

If pre-flight passes, execute in sequence (stopping on any failure):

**2a. Attribution scrub**
- Scan for and remove Claude/Anthropic/AI attribution if governance
  requires it
- Report findings and fixes

**2b. Changelog cleanup**
- Run changelog deduplication (equivalent to `/r:util:chg-dedup`)
- Report changes made

**2c. User approval gate**
Present the final state: version, branch, commits since last release,
CHANGELOG.RELEASE contents, and files changed. STOP and wait for user
confirmation before proceeding.

### 3. Merge and release

After user approval:
- Generate merge/squash commit message
- Create PR against main/master
- Report the PR URL
- Monitor CI checks if available

### 4. Consumer notification

After the release merges:
- Run library sync check (equivalent to `/r:util:lib-sync`)
- Report version drift for each consumer project

### 5. Post-release updates

- Update project memory with new version and release status

## Rules
- NEVER auto-merge — always require user confirmation before merge
- NEVER auto-sync consumers — report drift, let user decide
- STOP immediately if any pre-flight check fails
- STOP and wait for user approval before merge step
- Follow governance commit protocol
