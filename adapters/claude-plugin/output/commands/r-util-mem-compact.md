---
description: >
  Archive stale MEMORY.md entries. Detects staleness, identifies completed
---

Archive stale MEMORY.md entries. Detects staleness, identifies completed
work ready for archival, and proposes compaction. Preview mode by default
— only modifies files when user explicitly confirms.

## Arguments
- `$ARGUMENTS` — optional: `--apply` to execute changes (default: preview only)

## Scope Detection

Read `.rdf/governance/index.md` to identify the current project. Then
locate its MEMORY.md:
- If governance index exists, use the project name to find the memory file
  in the Claude projects memory directory
- If CWD is a project directory with a recognizable git root, search for
  MEMORY.md in the standard Claude projects path
- If multiple projects are in scope (workspace root), process all

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
1. All commits mentioned are reachable from main/master (merged)
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

Also propose:
- Updating stale facts identified in Step 2
- Removing duplicate information
- Consolidating redundant entries

## Step 5: Preview Report

    # Memory Compaction: <project> MEMORY.md

    Current: <N> lines (<STATUS>)
    Target:  <M> lines (after compaction)
    Reduction: <N-M> lines

    ## Stale Facts (<count>)
    | Fact | Recorded | Current |
    |------|----------|---------|

    ## Archival Candidates (<count> sections, <lines> lines)
    1. "Section name" (NN lines) → 2-line summary
    ...

    ## Archive File
    memory/archive-v<version>.md (<total archived lines> lines)

## Step 6: Apply (only with --apply)

If `$ARGUMENTS` contains `--apply`:
1. Create/append to `memory/archive-v<version>.md` with archived sections
2. Replace archived sections in MEMORY.md with summaries
3. Update stale facts with current values
4. Report final line count

If `--apply` not specified, end with:
"Run `/rdf:r-util-mem-compact --apply` to execute these changes."

## Step 7: Lessons / Insights Consolidation (--lessons or near-cap auto)

Runs when `$ARGUMENTS` contains `--lessons`, or automatically when invoked
with no MEMORY target and `~/.rdf/lessons-learned.md` is within 5 of its
50-entry cap.

1. Run the deterministic scanner (read-only — never mutates the lessons file).
   If `~/.rdf/state/rdf-lessons.sh` is absent (plugin-only install), skip this
   consolidation step — MEMORY.md compaction still works; the scanner needs the
   symlink deploy (`rdf generate claude-code`).
   ```bash
   bash ~/.rdf/state/rdf-lessons.sh scan ~/.rdf/lessons-learned.md
   ```
   Parse the JSON: `duplicates` (token-Jaccard >=50% pairs, each with a
   `jaccard` score) and `contradictions` (opposing-polarity pairs, 25-49%
   `overlap`).

2. Present each candidate under the **existing y/n/auto gate** (the same
   approve control used by `/rdf:r-save` §8):
   - **Duplicate:** show both bullets by ID + the proposed merge (keep the
     more-specific, drop the other). `y` merges; `n` skips; `auto` applies
     all remaining safe duplicate merges.
   - **Contradiction:** show both bullets by ID. Propose keeping the more
     specific and flagging the other for review.
     **`auto` NEVER resolves a contradiction** — it requires an explicit `y`
     every time, and `auto` is ignored for these candidates. This is the
     anti-crystallization rule: automatically dropping one side of a
     contradiction can reinforce the wrong lesson.

3. Apply only gate-approved changes to `~/.rdf/lessons-learned.md`, then
   rebuild the index (single writer): `bash ~/.rdf/state/rdf-lessons.sh index`.

4. Repeat the duplicate pass for `~/.rdf/insights.jsonl` (exact-text and
   token-Jaccard >=50% duplicates only; no contradiction pass on insights).

## Safety Rules

- NEVER delete content — always archive to a file first
- NEVER remove protected sections
- NEVER archive sections describing incomplete work
- NEVER modify CLAUDE.md (that file has its own governance)
- Always preserve the archive file if it already exists (append, don't overwrite)
- If MEMORY.md is under 150 lines, report "No compaction needed" and exit
- NEVER auto-resolve a lessons contradiction — always require an explicit `y`
- NEVER delete a lesson/insight without gate approval — dedup merges preserve
  the surviving entry verbatim
