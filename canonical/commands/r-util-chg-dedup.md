Deduplicate changelog entries for the current version. Scans CHANGELOG
and CHANGELOG.RELEASE for duplicates, overlapping entries, tracking
artifacts, fluff, and section proliferation. Report mode by default —
only modify files when explicitly told to fix.

## Arguments
- `$ARGUMENTS` — optional: `--full` for cross-reference against git log

## Setup

Read `.rdf/governance/index.md` to identify:
- Changelog format and section structure (from governance/conventions.md)
- Changelog file locations
- Version naming convention

## Scoping

Scope to the current branch version ONLY:
1. Get branch name: `git branch --show-current`
2. Find version header line number in CHANGELOG
3. Find NEXT version header (or EOF)
4. Read only that range with offset/limit
5. Read CHANGELOG.RELEASE (typically small — full read is fine)

## Detection Rules

### 1. Tracking artifact removal (MANDATORY)
Strip session artifacts from all entries:
- Finding references: `(F-NNN)`, `(C-NNN)`, `(R-NNN)`
- Phase markers: `Phase N`, `[R-NNN]`
- Pattern: `\([A-Z]-[0-9]+\)` or `\[[A-Z]-[0-9]+\]`

Strip silently — note total count in summary.

### 2. Fluff entries (DROP or MERGE)
**Drop entirely**: copyright header updates, changelog housekeeping,
gitignore changes, comment-only changes, whitespace fixes, formatting.

**Merge into one line**: multiple README updates, multiple man page
corrections, multiple test infrastructure changes.

### 3. Duplicates
- Exact duplicates: identical lines ignoring whitespace
- Near-duplicates: same file + same function = likely duplicate
- Tag mismatches: same change with different tags
- Contradictions: "added X" and "removed X"

### 4. Overlapping entry collapse
Aggressively merge entries describing different facets of the same change:
- Feature + config + docs -> one `[New]` entry
- Sequential fixes for same bug -> keep only the final fix
- Refactor + cleanup of same function -> one `[Change]` entry
- Multiple test additions for same feature -> one entry with count

### 5. Internal-only entries (DROP or FOLD)
**Drop**: internal variable changes, code comments, dead code removal,
test rewrites, internal refactoring names.
**Fold into parent**: entries that describe a sub-step of a larger change.

The sysadmin test: would a user upgrading this software understand and
care about this entry?

### 6. Verbose entries
Flag entries longer than ~100 characters that repeat file paths, restate
the tag meaning, or include implementation details.

### 7. Section proliferation (MANDATORY)
Maximum 3-5 sections. Flag topical micro-sections and propose
consolidation into standard sections (New Features, Bug Fixes, Changes).

### 8. First-release consolidation
For first release of a major version: fold iterative development entries
into single feature entries. `[Change]` tags refining a `[New]` feature
should merge into the parent.

### 9. Cross-reference (OPT-IN — --full only)
When enabled: identify orphaned entries (no matching commit) and missing
entries (commit with no changelog entry). Skip by default.

## Target Entry Counts

| Release size | Target | Max |
|---|---|---|
| Small (< 50 commits) | 10-20 | 30 |
| Medium (50-150 commits) | 20-40 | 60 |
| Large (150-300+ commits) | 35-70 | 90 |

## Process

1. Scope to current branch version
2. Check section structure (rule 7)
3. Strip tracking artifacts (rule 1)
4. Parse every entry
5. Identify internal-only entries (rule 5)
6. Identify fluff (rule 2)
7. Group remaining entries by topic
8. Apply duplicate/overlap/verbose rules (3, 4, 6)
9. If first release: apply consolidation (rule 8)
10. If `--full`: cross-reference against git log (rule 9)
11. Check entry count against target table
12. Compare CHANGELOG vs CHANGELOG.RELEASE for drift

## Output

    ## CHANGELOG Dedup: v<version>

    Entries scanned: <N>
    Tracking artifacts stripped: <N>
    Section structure: <ok / N sections — proposed restructure>
    Entry count: <N> (target: <T> for <size> release)

    ### Section proliferation (if applicable)
    ### Internal-only entries (<N>)
    ### Fluff entries (<N>)
    ### Duplicates (<N>)
    ### Merge candidates (<N> groups)
    ### Verbose entries (<N>)
    ### Tag mismatches (<N>)
    ### Orphaned entries (<N>) — --full only
    ### Missing entries (<N>) — --full only

If no issues: "CHANGELOG v<version> is clean — <N> entries, no issues."

## Rules
- Only examine the current branch version block — ignore history
- Do NOT modify files unless user explicitly says to fix/apply
- Strip tracking artifacts silently — they are never user-facing
- Proposed merges must preserve all meaningful factual content
- Changelogs should be readable by someone with no knowledge of the
  development process
