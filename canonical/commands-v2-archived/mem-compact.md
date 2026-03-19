Memory archival and compaction for MEMORY.md files. Detects staleness,
identifies completed work ready for archival, and proposes compaction.
Preview mode by default — only modifies files when user explicitly confirms.

## Arguments
- `$ARGUMENTS` — optional: `--apply` to execute changes (default: preview only)

## Scope Detection

Determine which MEMORY.md to compact:
- If CWD is a project directory, use the project's MEMORY.md from the Claude
  projects memory directory (path pattern:
  `/root/.claude/projects/-root-admin-work-proj-<project>/memory/MEMORY.md`)
- If CWD is `/root/admin/work/proj/`, process all project MEMORY.md files

## Step 1: Read and Measure

Read the target MEMORY.md. Report:
- Total line count
- Status: OK (< 180), WARN (180-200), OVER (> 200)
- Number of sections

## Step 2: Staleness Detection

Cross-reference factual claims against live state:
- **Commit hashes**: Does the recorded HEAD match `git rev-parse HEAD`?
- **Test counts**: Does the recorded count match
  `grep -rc '@test' tests/*.bats | awk -F: '{s+=$2} END {print s}'`?
- **Version strings**: Does the recorded version match the project source?
- **Branch names**: Does the recorded branch match `git branch --show-current`?
- **CI status**: Is the last recorded CI outcome current?
- **Completed phases**: Are PLAN.md phases marked consistently?

Report each stale fact with current vs recorded values.

## Step 3: Archival Candidates

Identify sections describing **completed work** that meet ALL criteria:
1. All commits mentioned are reachable from master (merged)
2. Section describes implementation detail, not patterns/lessons
3. Section is not in a protected category (see below)

**Protected sections (NEVER archive):**
- Project State (always keep, update instead)
- Key Patterns
- Known Gotchas
- Verified False Positives
- Deferred Items
- Test Infrastructure
- Any section with "Lesson" or "Convention" in its heading

**Archival candidates** are typically:
- Completed feature sections (e.g., "Native Hex Engine Rewrite — COMPLETE")
- Completed remediation batches
- Completed audit phases with all findings resolved

## Step 4: Propose Changes

For each archival candidate, propose:
1. Move full section content to `memory/archive-v<version>.md`
2. Replace in MEMORY.md with a 1-2 line summary linking to the archive

Example replacement:
```
## Native Hex Engine Rewrite — COMPLETE
See [archive-v2.0.1.md](archive-v2.0.1.md) for details. 8 commits, grep -F
batch engine replaced Perl hexfifo/hexstring scripts.
```

Also propose:
- Updating stale facts identified in Step 2
- Removing duplicate information
- Consolidating redundant entries

## Step 5: Preview Report

```
# Memory Compaction: <project> MEMORY.md

Current: <N> lines (<STATUS>)
Target:  <M> lines (after compaction)
Reduction: <N-M> lines

## Stale Facts (<count>)
| Fact | Recorded | Current |
|------|----------|---------|
| HEAD | abc1234  | def5678 |
| Tests| 332      | 343     |

## Archival Candidates (<count> sections, <lines> lines)
1. "Native Hex Engine Rewrite" (42 lines) → 2-line summary
2. "Batch Parallel MD5 Scanning" (18 lines) → 2-line summary
3. ...

## Archive File
memory/archive-v<version>.md (<total archived lines> lines)
```

## Step 6: Apply (only with --apply)

If `$ARGUMENTS` contains `--apply`:
1. Create/append to `memory/archive-v<version>.md` with archived sections
2. Replace archived sections in MEMORY.md with summaries
3. Update stale facts with current values
4. Report final line count

If `--apply` not specified, end with:
"Run `/mem-compact --apply` to execute these changes."

## Safety Rules

- NEVER delete content — always archive to a file first
- NEVER remove protected sections
- NEVER archive sections describing incomplete work
- NEVER modify CLAUDE.md (that file has its own governance)
- Always preserve the archive file if it already exists (append, don't overwrite)
- If MEMORY.md is under 150 lines, report "No compaction needed" and exit
