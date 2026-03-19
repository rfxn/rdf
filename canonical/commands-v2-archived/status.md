Display agent status from work-output/ status files across all projects.

`$ARGUMENTS` determines scope:

- **No args** — scan all projects for status files, display summary
- **`<project>`** — display status for a specific project (uses EM alias table)
- **`all`** — verbose display of all status files across all projects

---

## Project Alias Table

| Alias       | Directory                                        |
|-------------|--------------------------------------------------|
| `apf`       | `/root/admin/work/proj/advanced-policy-firewall` |
| `bfd`       | `/root/admin/work/proj/brute-force-detection`    |
| `lmd`       | `/root/admin/work/proj/linux-malware-detect`     |
| `tlog_lib`  | `/root/admin/work/proj/tlog_lib`                 |
| `alert_lib` | `/root/admin/work/proj/alert_lib`                |
| `elog_lib`  | `/root/admin/work/proj/elog_lib`                 |
| `pkg_lib`   | `/root/admin/work/proj/pkg_lib`                  |
| `batsman`   | `/root/admin/work/proj/batsman`                  |

---

## Procedure

### 1. Locate status files

For each project directory (or just the specified one):
- Check `./work-output/phase-*-status.md` (SE status files)
- Check `./work-output/qa-phase-*-status.md` (QA status files)
- Check `./work-output/agent-feed.log` (subagent stop log)
- Check `/root/admin/work/proj/work-output/em-session.md` (EM session log)

### 2. Parse and display

For each status file found, extract key fields:
- `AGENT`, `PHASE`, `SE_ID`, `STATUS`, `CURRENT_STEP`, `STEP_NAME`
- `DETAIL`, `FILES_MODIFIED`, `TESTS_RUN`, `TESTS_PASSED`, `LINT_STATUS`

### 3. Summary output

```
# Agent Status Dashboard

## Active Work
| Project   | Agent | Phase | Step        | Status  | Detail                    |
|-----------|-------|-------|-------------|---------|---------------------------|
| pkg_lib   | SE-1  | 2     | 3_IMPLEMENT | RUNNING | Writing output functions   |
| pkg_lib   | SE-2  | 3     | 5_VERIFY    | RUNNING | Running shellcheck        |
| bfd       | QA    | 10    | 4_REGRESSION| RUNNING | Executing tier 2 tests    |

## Recently Completed
| Project   | Agent | Phase | Result   | Duration | Tests       |
|-----------|-------|-------|----------|----------|-------------|
| lmd       | SE    | 9     | COMPLETE | 4m 12s   | 359 PASS    |
| lmd       | QA    | 9     | APPROVED | 1m 30s   | trusted SE  |

## Agent Feed (last 5 entries)
<from agent-feed.log if present>
```

### 4. Stale file detection

If any status file has `UPDATED` timestamp older than 1 hour, flag it:
```
WARNING: Stale status files detected (>1h old):
  pkg_lib/work-output/phase-2-status.md — last updated 2h ago
  Likely from a crashed or interrupted session. Run cleanup? [y/n]
```

---

## Rules

- **Read-only** — this command does NOT modify any files
- Display timestamps in human-readable relative format ("3m ago", "1h ago")
- If no status files exist anywhere, report "No active agent work found"
- Sort active work by most recently updated first
