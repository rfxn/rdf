Shared library drift detection and sync for rfxn projects. Compares canonical
library sources against all consumer copies. Report mode by default; optional
sync mode copies and verifies.

## Arguments
- `$ARGUMENTS` — optional: `--sync` to execute copy operations (default: report only)

## Library Table

| Library | Canonical Source | Consumer Paths |
|---------|-----------------|----------------|
| tlog_lib | `/root/admin/work/proj/tlog_lib/tlog_lib.sh` | `files/internals/tlog_lib.sh` |
| alert_lib | `/root/admin/work/proj/alert_lib/alert_lib.sh` | `files/internals/alert_lib.sh` |
| elog_lib | `/root/admin/work/proj/elog_lib/elog_lib.sh` | `files/internals/elog_lib.sh` |

Extend this table as new shared libraries are created (e.g., pkg_lib).

## Step 1: Detect Context

- If CWD is a project directory, check only that project's copies
- If CWD is `/root/admin/work/proj/`, check all projects under it

For each project, determine which libraries it consumes by checking for the
file's presence.

## Step 2: Compare

For each canonical → consumer pair:

1. **Checksum**: `sha256sum` both files, compare
2. **Version**: Extract version variable from both (e.g., `_TLOG_LIB_VERSION=`)
   and compare
3. **Status**: SYNCED (identical checksum) or DRIFTED

## Step 3: Drift Report

```
# Shared Library Sync Report

| Library | Canonical Ver | Project | Local Ver | Status |
|---------|--------------|---------|-----------|--------|
| tlog_lib | 1.0.4 | lmd | 1.0.4 | SYNCED |
| tlog_lib | 1.0.4 | bfd | 1.0.3 | DRIFTED |
| alert_lib| 1.0.2 | lmd | 1.0.2 | SYNCED |
| alert_lib| 1.0.2 | apf | — | N/A |

Drifted: 1 | Synced: 2 | N/A: 1
```

For DRIFTED entries, show a brief `diff --stat` of the differences.

## Step 4: Sync (only with --sync)

If `$ARGUMENTS` contains `--sync`:

For each DRIFTED library:
1. `/usr/bin/cp` canonical → consumer path
2. Set permissions per project convention (750 for LMD, 750 for APF/BFD)
3. Run `bash -n` on the copied file to verify syntax
4. Run `sha256sum` to confirm match
5. Report success/failure

After sync:
- Do NOT commit — leave files staged for user review
- Report: "Synced N libraries. Review with `git diff` before committing."

If `--sync` not specified, end with:
"Run `/proj-lib-sync --sync` to copy drifted libraries."

## Rules

- NEVER edit a shared library inside a consuming project
- NEVER sync if the canonical source has syntax errors (`bash -n` check first)
- Always show the diff before syncing (in report mode)
- Skip libraries whose canonical source doesn't exist
- Warn if a consumer has local modifications not present in canonical
  (reverse drift — consumer ahead of canonical)
