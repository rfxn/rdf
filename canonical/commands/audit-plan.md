Generate a PLAN.md from AUDIT.md findings. Parses the REMEDIATION ROADMAP,
groups findings by shared fix location, and produces implementation phases
with dependencies and commit templates. Do NOT modify files — output only.

## Prerequisites

- AUDIT.md must exist in the project root
- Read CLAUDE.md to understand project structure and conventions

## Step 1: Parse AUDIT.md

Read AUDIT.md and extract from the REMEDIATION ROADMAP section:
- All findings with: ID (F-NNN), severity, title, status, dedup class
- Group status: OPEN, RESOLVED, FALSE POSITIVE, ACCEPTABLE, DEFERRED
- Filter to OPEN findings only

If no AUDIT.md exists, report "No AUDIT.md found — run `/audit` first." and stop.
If no OPEN findings exist, report "All findings resolved." and stop.

## Step 2: Group by Shared Fix

Cluster OPEN findings that share a fix location:
- Same file + same function → single phase
- Same dedup class → single phase (even across files)
- Same pattern class (e.g., "unquoted variable") → single phase

Each group becomes one PLAN.md phase.

## Step 3: Dependency Analysis

Determine phase ordering:
1. **Critical severity first** — always Phase 1
2. **Dependency order** — if fixing F-012 requires the helper from F-008, F-008
   comes first
3. **Smallest effort first** within same severity — quick wins unblock progress
4. **Test coverage gaps last** — they don't block other fixes

## Step 4: Generate Phases

For each phase, output:

```markdown
### Phase N: <title> (<severity>)

**Findings:** F-NNN, F-NNN
**Files:** path/to/file1, path/to/file2
**Changes:**
- Specific change description for F-NNN
- Specific change description for F-NNN

**Dependencies:** Phase M (if any)
**Test tier:** lint-only | primary-os | primary+rhel | full-matrix
**Commit template:**
```
[Fix] description; F-NNN, F-NNN
```
```

## Step 5: Output

```markdown
# PLAN.md — Audit Remediation

Generated from AUDIT.md (health: <rating>, <N> open findings)

## Summary
- Total phases: <N>
- Critical: <N> | Major: <N> | Minor: <N> | Info: <N>
- Estimated commits: <N>

<phases>

## Deferred Items
<list findings marked DEFERRED with rationale>
```

## Rules

- Never propose changes to frozen CLI case statements
- Never propose changes to files inside `tests/infra/`
- For each finding, verify it's still valid by reading the referenced code
- Flag any finding that appears to be a false positive (suggest marking in AUDIT.md)
- Include CHANGELOG entries in each phase's commit template
- Group documentation-only changes into a single "docs sync" phase at the end
