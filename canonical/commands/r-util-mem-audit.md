# /r-util-mem-audit — Memory Fact-Check

Stale memory and contradiction detection. Reads MEMORY.md files and
cross-references every factual claim against live project state.
Read-only report — no modifications.

## Scope

- If CWD is a project directory: audit that project's MEMORY.md only
- If CWD is `/root/admin/work/proj/`: audit all project MEMORY.md files

MEMORY.md location:
`.rdf/memory/MEMORY.md`

## Protocol

### 1. Extract Claims

Read each MEMORY.md and extract verifiable factual claims:

**Version claims:**
- "Version: X.Y.Z" → verify against project source (grep VERSION=)
- "Branch: name" → verify against `git branch --show-current`

**Commit claims:**
- "HEAD: abc1234" → compare to `git rev-parse --short HEAD`
- Any commit hash mentioned → verify with `git log --oneline | grep`

**Test claims:**
- "N tests" → verify with `grep -rc '@test' tests/*.bats | awk`
- "all targets green" → check `gh run list --limit 1` if available

**Status claims:**
- Phase status markers → cross-reference PLAN.md
- "COMPLETE" markers → verify commits exist

**File/function claims:**
- "New function: name()" → verify presence in source
- "File deleted" → verify absence
- "Renamed X → Y" → verify Y exists and X doesn't

### 2. Cross-Reference CLAUDE.md

Compare MEMORY.md claims against CLAUDE.md for contradictions:
- Version string mismatches
- Architecture descriptions that conflict
- Function/variable lists with discrepancies

### 3. Cross-Reference Between Projects

If auditing multiple projects, check:
- Shared library version claims that differ between consumers
- Cross-project references that are stale
- Inconsistent convention descriptions

### 4. Output Report

```
# Memory Audit Report

Project: {name} (or "All Projects")
Date: {date}

## Stale Facts ({N})

| Claim | Source | Recorded | Current | Status |
|-------|--------|----------|---------|--------|
| Version | MEMORY.md:3 | 2.0.0 | 2.0.1 | STALE |
| HEAD | MEMORY.md:4 | abc1234 | def5678 | STALE |
| Tests | MEMORY.md:5 | 332 | 343 | STALE |

## Contradictions ({N})

| Claim | MEMORY.md says | CLAUDE.md says | Resolution |
|-------|---------------|----------------|------------|
| Path  | /opt/maldetect | /usr/local/maldetect | Fix MEMORY |

## Unverifiable Claims ({N})
{claims that can't be checked against live state}

## Summary
- Total claims checked: {N}
- Fresh: {N} | Stale: {N} | Contradictions: {N} | Unverifiable: {N}
- Health: GOOD (<5% stale) | FAIR (5-15%) | POOR (>15%)
```

## Rules
- Read-only — do NOT modify any files
- Report unverifiable claims separately (don't count as stale)
- For commit hashes, check both short and long forms
- For test counts, allow +/- 2 tolerance before marking stale
- Skip claims in "Deferred Items" sections (intentionally static)
- CLAUDE.md is authoritative for architecture — MEMORY.md defers
