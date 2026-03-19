Cross-project audit coordination. Runs lightweight delta checks across all
rfxn projects, compares finding patterns, and generates a cross-project
remediation plan for batch-fixable issues. Run from `/root/admin/work/proj/`.

## Prerequisites

- Must be run from `/root/admin/work/proj/` (parent project directory)
- At least one project must have an AUDIT.md
- Uses `/audit-delta` logic for per-project checks

## Step 1: Discover Projects

Scan `/root/admin/work/proj/` for subdirectories with CLAUDE.md:
```bash
for dir in /root/admin/work/proj/*/; do
    [[ -f "$dir/CLAUDE.md" ]] && echo "$dir"
done
```

For each project, record:
- Name, version, branch
- Whether AUDIT.md exists
- Last audit date (from AUDIT.md header)
- Last commit date

## Step 2: Per-Project Delta Check

For each project with an AUDIT.md, run a lightweight delta check (equivalent
to `/audit-delta` logic):

1. Determine baseline from AUDIT.md timestamp
2. Get changed files since baseline
3. Run quick standards checks (shellcheck, anti-pattern grep) on changed files
4. Count new vs known findings

For projects without AUDIT.md, note as "No baseline — full audit recommended."

Use the Agent tool with haiku model for parallel per-project checks.

## Step 3: DEDUP_CLASS Distribution Analysis

Across all projects that have AUDIT.md, aggregate DEDUP_CLASS occurrences:

```
| DEDUP_CLASS | LMD | APF | BFD | Total | Status |
|-------------|-----|-----|-----|-------|--------|
| hardcoded-path | 2 | 5 | 1 | 8 | systemic |
| unquoted-var | 0 | 3 | 2 | 5 | systemic |
| missing-local | 1 | 0 | 0 | 1 | isolated |
```

Flag classes appearing in 2+ projects as "systemic" — these are batch-fixable.

## Step 4: Cross-Project Pattern Detection

Look for patterns that indicate systemic issues:
- Same DEDUP_CLASS in multiple projects → convention gap
- Same function name with different implementations → sync opportunity
- Same shared library with different versions → drift
- Same config variable with different defaults → consistency issue

## Step 5: Generate Cross-Project Remediation Plan

For systemic patterns, propose batch fixes:

```markdown
## Batch Remediation Opportunities

### 1. Hardcoded Paths (8 instances across 3 projects)
- **Pattern:** Direct use of `/sbin/`, `/usr/sbin/` paths
- **Fix:** Replace with `command -v` discovered variables
- **Projects:** LMD (2), APF (5), BFD (1)
- **Effort:** S per project, can batch in one session
- **Priority:** Medium (portability risk)

### 2. Unquoted Variables (5 instances across 2 projects)
...
```

## Step 6: Output

```
# Cross-Project Audit Report

Date: <date>
Projects: <N> scanned

## Per-Project Summary

| Project | Version | Branch | Audit Age | Delta | New Findings |
|---------|---------|--------|-----------|-------|--------------|
| lmd     | 2.0.1   | 2.0.1  | 2 days    | OK    | 0            |
| apf     | 2.0.1   | 2.0.1  | 5 days    | WARN  | 3            |
| bfd     | 1.6.1   | 1.6.1  | N/A       | N/A   | —            |

## Systemic Patterns (<N> classes across <M> projects)

<DEDUP_CLASS table from Step 3>

## Batch Remediation Plan (<N> opportunities)

<remediation proposals from Step 5>

## Recommendations
1. <highest-priority action>
2. <next action>
3. ...

## Projects Needing Full Audit
<list projects with no AUDIT.md or audit older than 2 weeks>
```

## Rules

- Read-only — do NOT modify any project files
- Do NOT run full audits — this is a coordination/comparison tool
- Use Agent tool with haiku for per-project delta checks (speed over depth)
- Skip projects that are not rfxn Bash projects (e.g., gpubench)
- If only one project has AUDIT.md, skip cross-project comparison and just
  run a delta check on that project
- Recommend `/audit` for projects with stale or missing audits
