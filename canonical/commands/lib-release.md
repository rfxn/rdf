Automate the shared library release lifecycle. Handles pre-flight checks,
release preparation, and consumer drift notification.

`$ARGUMENTS` is the library name or alias (required).

---

## Library Alias Table

| Alias       | Directory                            | Repo            |
|-------------|--------------------------------------|-----------------|
| `tlog_lib`  | `/root/admin/work/proj/tlog_lib`     | `rfxn/tlog_lib` |
| `alert_lib` | `/root/admin/work/proj/alert_lib`    | `rfxn/alert_lib`|
| `elog_lib`  | `/root/admin/work/proj/elog_lib`     | `rfxn/elog_lib` |
| `pkg_lib`   | `/root/admin/work/proj/pkg_lib`      | `rfxn/pkg_lib`  |
| `batsman`   | `/root/admin/work/proj/batsman`      | `rfxn/batsman`  |

---

## Procedure

### 1. Pre-flight checks

Switch to the library directory and verify readiness:

**Branch validation:**
- `git branch --show-current` — must be the version branch (e.g., `1.0.2`)
- `git status` — working tree must be clean (no uncommitted changes)
- `git log origin/<branch>..HEAD` — check for unpushed commits

**PLAN verification:**
- Read the library's PLAN file (PLAN.md in project dir, or parent-level
  PLAN file: `PLAN-alert-lib.md`, `PLAN-eloglib.md`, `PLAN-pkglib.md`)
- Verify ALL standalone library phases are COMPLETED/DONE
- If any standalone phases are incomplete, list them and STOP

**Release readiness:**
- Run `/rel-prep` in the library directory
- Capture the output and check for READY / READY WITH WARNINGS / NOT READY

**Report pre-flight status:**
```
# Pre-flight — <lib> v<version>

## Branch
- Current: <branch>
- Clean: yes/no
- Unpushed commits: <count>

## PLAN Status
| Phase | Title            | Status |
|-------|------------------|--------|
| 1     | ...              | DONE   |
| 2     | ...              | DONE   |
| ...   | ...              | ...    |
All standalone phases: COMPLETE / <N> INCOMPLETE

## Release Readiness
<output from /rel-prep>
```

### 2. Release preparation

If pre-flight passes, execute in sequence (stopping on any failure):

**2a. Attribution scrub**
- Run `/rel-scrub` — remove Claude/Anthropic/AI attribution
- Report findings and fixes

**2b. Changelog deduplication**
- Run `/rel-chg-dedup` — deduplicate and clean changelog
- Report changes made

**2c. User approval gate**
Present the final state to the user:
```
## Ready to Release

Version: <version>
Branch: <branch>
Commits since last release: <count>

### CHANGELOG.RELEASE
<display contents>

### Files changed
<git diff --stat against main/master>

Proceed with merge and release? [y/n]
```

**STOP and wait for user confirmation before proceeding.**

### 3. Merge and release

After user approval:

**3a. Generate merge commit**
- Run `/rel-merge` to generate the squash/merge commit message
- Present the commit message to the user for review

**3b. Create PR**
- Run `/rel-ship` to create the PR against main/master
- Report the PR URL

**3c. Monitor CI**
- If the project has CI, monitor the PR checks
- Report pass/fail status

### 4. Consumer notification

After the release merges:

**4a. Identify drifted consumers**
- Run `/proj-lib-sync` to check which projects use this library
- Report version drift for each consumer

**4b. Report consumer status**
```
## Consumer Status — <lib> v<version>

| Consumer | Current Version | Drift | Action Needed |
|----------|----------------|-------|---------------|
| BFD      | v1.0.1         | 1 rev | Update needed |
| LMD      | v1.0.2         | 0     | Current       |
| APF      | not integrated | —     | Pending       |
```

### 5. Post-release updates

- Run `/mem-save` in the library directory
- Update the parent MEMORY.md with new version and release status

---

## Rules

- **NEVER auto-merge** — always require user confirmation before merge
- **NEVER auto-sync consumers** — report drift, let user decide when to update
- **STOP immediately** if any pre-flight check fails — do not proceed to release
- **STOP and wait for user approval** before merge step
- Follow the commit protocol from parent CLAUDE.md
- If `/rel-prep` reports NOT READY, list all blocking items and stop
