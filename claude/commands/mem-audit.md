Stale memory and contradiction detection. Reads all MEMORY.md files and
cross-references every factual claim against live project state. Detects
contradictions between MEMORY.md and CLAUDE.md. Report only — no modifications.

## Scope Detection

- If CWD is a project directory, audit that project's MEMORY.md only
- If CWD is `/root/admin/work/proj/`, audit all project MEMORY.md files

MEMORY.md files are in the Claude projects memory directory:
`/root/.claude/projects/-root-admin-work-proj-<project>/memory/MEMORY.md`

## Step 1: Extract Claims

Read each MEMORY.md and extract verifiable factual claims:

### Version claims
- "Version: X.Y.Z" → verify against project source
- "Branch: name" → verify against `git branch --show-current`

### Commit claims
- "Commit: abc1234" → verify with `git log --oneline | grep abc1234`
- "Latest commit: hash" → compare to `git rev-parse --short HEAD`

### Test claims
- "Tests: N across M files" → verify with
  `grep -rc '@test' tests/*.bats | awk -F: '{s+=$2} END {print s}'`
- "N BATS files" → verify with `ls tests/*.bats | wc -l`
- "all targets green" → check `gh run list --limit 1`

### Status claims
- "Status: <description>" → cross-reference PLAN.md phase markers
- "COMPLETE" markers → verify commits exist and are merged

### Function/variable claims
- "New function: name()" → verify with `grep -l 'function_name\|name()' files/`
- "Variable removed" → verify absence in source
- "Renamed X → Y" → verify Y exists and X doesn't

### File claims
- "File deleted" → verify absence
- "File created" → verify presence

## Step 2: Cross-Reference CLAUDE.md

Compare MEMORY.md claims against CLAUDE.md for contradictions:
- Version string mismatches
- Architecture descriptions that conflict
- Function lists that don't match
- Config variable lists with discrepancies

## Step 3: Cross-Reference Between MEMORY.md Files

If auditing multiple projects, check for:
- Shared library version claims that differ between consumers
- Cross-project references that are stale
- Inconsistent convention descriptions

## Step 4: Output Report

```
# Memory Audit Report

Project: <name> (or "All Projects")
Date: <date>

## Stale Facts (<N>)

| Claim | Source | Recorded | Current | Status |
|-------|--------|----------|---------|--------|
| Version | MEMORY.md:3 | 2.0.0 | 2.0.1 | STALE |
| HEAD | MEMORY.md:4 | abc1234 | def5678 | STALE |
| Tests | MEMORY.md:5 | 332 | 343 | STALE |
| Branch | MEMORY.md:3 | master | 2.0.1 | STALE |

## Contradictions (<N>)

| Claim | MEMORY.md says | CLAUDE.md says | Resolution |
|-------|---------------|----------------|------------|
| Install path | /opt/maldetect | /usr/local/maldetect | Fix MEMORY.md |

## Unverifiable Claims (<N>)
<claims that can't be checked against live state>

## Summary
- Total claims checked: <N>
- Fresh: <N>
- Stale: <N>
- Contradictions: <N>
- Unverifiable: <N>
- Health: GOOD (<5% stale) / FAIR (5-15%) / POOR (>15%)
```

## Rules

- Read-only — do NOT modify any files
- Report unverifiable claims separately (don't count as stale)
- For commit hashes, check both short and long forms
- For test counts, allow +/- 2 tolerance before marking stale
- Skip checking claims in "Deferred Items" sections (they're intentionally static)
- Cross-reference is informational — CLAUDE.md is authoritative for architecture
