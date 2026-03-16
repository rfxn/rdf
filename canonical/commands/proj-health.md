Live project health dashboard. Runs non-destructive checks and outputs a
summary table. Do NOT modify any files.

## Detection

Determine project context from the current working directory:
- If CWD is a project directory (has CLAUDE.md), run single-project mode
- If CWD is `/root/admin/work/proj/` (parent), run cross-project mode on all
  subdirectories that contain a CLAUDE.md

## Single-Project Checks

### 1. Lint status
Run `bash -n` on all project shell files (from CLAUDE.md verification section).
Run `shellcheck --severity=error` on the same files. Report PASS/FAIL with
count of errors.

### 2. Git status
- Current branch, uncommitted file count (`git status --porcelain | wc -l`)
- Ahead/behind tracking branch (`git rev-list --left-right --count HEAD...@{u}`)
- Last commit hash and age

### 3. Test count
```bash
grep -rc '@test' tests/*.bats 2>/dev/null | awk -F: '{s+=$2} END {print s}'
```

### 4. CI status
```bash
gh run list --limit 1 --json status,conclusion,name,headBranch 2>/dev/null
```
Report: last run name, branch, status, conclusion. If `gh` unavailable, report N/A.

### 5. Audit health
If AUDIT.md exists, extract:
- Health rating line (e.g., `YELLOW | 79 findings`)
- Severity breakdown (C/M/m/I counts)
- Unresolved count
Report N/A if no AUDIT.md.

### 6. MEMORY.md staleness
- Read MEMORY.md, extract recorded HEAD commit hash
- Compare to actual `git rev-parse HEAD`
- If they differ, report STALE with commit distance
- Report line count and warn if >= 180

### 7. Shared library drift
For each known shared library (tlog_lib, alert_lib, elog_lib):
- Find canonical source under `/root/admin/work/proj/`
- Find project copy (e.g., `files/internals/tlog_lib.sh`)
- Compare `sha256sum` — report SYNCED or DRIFTED
- Skip libraries not present in the project

## Cross-Project Mode

When run from `/root/admin/work/proj/`, iterate over all subdirectories with
CLAUDE.md and produce a summary table:

```
| Project | Branch | Lint | Tests | CI | Audit | Memory | Libs |
|---------|--------|------|-------|----|-------|--------|------|
| lmd     | 2.0.1  | PASS | 343   | OK | YELLOW| FRESH  | OK   |
| apf     | 2.0.1  | PASS | 189   | OK | N/A   | STALE  | OK   |
| bfd     | 1.6.1  | FAIL | 45    | FAIL| N/A  | FRESH  | DRIFT|
```

Then show per-project detail for any FAIL/STALE/DRIFT items.

## Output Format (single project)

```
# Project Health: <name> v<version> (<branch>)

| Check            | Status | Details                    |
|------------------|--------|----------------------------|
| Lint             | PASS   | 8/8 files clean            |
| Git              | OK     | 3 uncommitted, 2 ahead     |
| Tests            | 343    | 26 BATS files              |
| CI               | PASS   | smoke-test on 2.0.1        |
| Audit            | YELLOW | 79 findings (0C/7M/47m/25I)|
| Memory           | FRESH  | 195 lines (warn: near 200) |
| Shared libs      | OK     | tlog_lib, alert_lib synced |
```

## Cache

After producing output, write a compact one-line cache to
`${XDG_RUNTIME_DIR:-/tmp}/rfxn-health-<project>.cache` for context-bar consumption:

```
GREEN|343|FRESH|2026-03-06T12:00:00
```

Format: `rating|test_count|memory_status|timestamp`

Rating logic:
- **GREEN**: All checks PASS, memory FRESH, no lib drift
- **YELLOW**: Any WARN, STALE memory, or audit YELLOW
- **RED**: Any FAIL (lint, CI) or audit RED
