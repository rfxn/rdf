# /r:util:proj-cross — Cross-Project Analysis

Cross-project analysis for rfxn projects. Reads MEMORY.md, PLAN.md,
AUDIT.md, and CLAUDE.md from all projects to identify shared patterns,
duplicate effort, convention drift, and alignment opportunities.

## Projects

Scan all directories under `/root/admin/work/proj/` that contain a
`CLAUDE.md` or `.git/` directory. Known projects:

| Alias | Directory |
|-------|-----------|
| apf | advanced-policy-firewall |
| bfd | brute-force-detection |
| lmd | linux-malware-detect |
| rdf | rdf |

Also scan shared libraries if present: tlog_lib, alert_lib, elog_lib,
pkg_lib, geoip_lib, batsman.

## Protocol

### 1. Open Work Overlap

Compare open PLAN.md items across projects. Flag:
- Same class of fix needed in multiple projects (e.g., "copyright
  year update", "bash 4.1 compat fix")
- Shared infrastructure improvements (test parallelism, CI matrix,
  Dockerfile patterns)
- Deferred items that could be batched across projects

### 2. Audit Finding Patterns

If AUDIT.md exists in multiple projects, compare:
- Same finding class appearing across projects
- Shared false positives (candidates for parent CLAUDE.md)
- Common severity distribution patterns

### 3. Convention Drift

Compare key patterns across project CLAUDE.md files:
- Commit message format consistency
- Verification checklist completeness
- Test infrastructure parity (parallelism, CI targets, OS matrix)
- Variable naming conventions
- Shell standards adherence

Flag differences that should be aligned. Distinguish intentional
per-project differences from unintentional drift.

### 4. Shared Library Drift

For each shared library (tlog_lib, alert_lib, elog_lib, pkg_lib,
geoip_lib), check all consuming projects:

- Compare version variables across canonical and consumer copies
- Compute `sha256sum` of all copies — warn if checksums differ
  (even at same version, detects project-specific edits)
- Flag any project-specific references that leaked into the library
- Check that wrapper scripts (e.g., `files/tlog`) are consistent

### 5. MEMORY.md Lessons

Read all MEMORY.md "Lessons Learned" / "Mistakes Made" / feedback
memory sections. Flag:
- Lessons from one project applicable to others
- Anti-patterns documented in one project but not enforced in parent
  CLAUDE.md
- Patterns that should be promoted to shared conventions

### 6. Output

```
# Cross-Project Analysis ({date})

## Open Work Overlap ({N} batch opportunities)
| Item | Projects | Action |
|------|----------|--------|
| {description} | APF, BFD | Batch across both |

## Convention Drift ({N} differences)
| Convention | APF | BFD | LMD | Aligned? |
|-----------|-----|-----|-----|----------|
| Commit format | VERSION \| desc | VERSION \| desc | [Type] desc | NO |

## Shared Library Drift ({N} mismatches)
| Library | Canonical | APF | BFD | LMD | Status |
|---------|-----------|-----|-----|-----|--------|
| tlog_lib | 1.2.0 | 1.2.0 | 1.1.9 | 1.2.0 | DRIFT |

## Lessons to Propagate ({N})
- {lesson from project X} → add to parent CLAUDE.md § {section}

## Recommendations
1. {numbered action items}
```

## Rules
- Read-only — do NOT modify any files
- Report convention drift as differences, not violations — some
  differences are intentional (e.g., LMD commit format)
- For library drift, the canonical copy is authoritative
- Focus on actionable items — skip trivial differences
- If a project has no PLAN.md/AUDIT.md/MEMORY.md, note it and
  continue with available data
