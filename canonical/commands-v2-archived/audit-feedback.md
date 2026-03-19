False positive feedback loop for the audit pipeline. Harvests FP and
ACCEPTABLE annotations from AUDIT.md, merges with MEMORY.md knowledge, and
generates a structured database that future audits can reference to reduce
repeat false positives.

## Step 1: Harvest from AUDIT.md

Read AUDIT.md and extract all findings marked as:
- **FALSE POSITIVE** — with their rationale
- **ACCEPTABLE** — with their rationale

For each, capture:
- Finding ID (F-NNN)
- Severity
- Title / description
- DEDUP_CLASS
- File and line references
- Rationale text

If no AUDIT.md exists, report "No AUDIT.md found." and stop.

## Step 2: Harvest from MEMORY.md

Read the project's MEMORY.md and extract:
- "Verified False Positives" section entries
- Any "Known Gotchas" that explain why certain patterns are intentional

## Step 3: Merge and Deduplicate

Combine sources, deduplicate by:
- Same DEDUP_CLASS → merge rationales
- Same file + pattern → merge into one entry
- Same conceptual finding across audit cycles → keep latest rationale

## Step 4: Generate FP Database

Write to `audit-output/fp-database.md`:

```markdown
# False Positive Database

Generated: <date>
Sources: AUDIT.md, MEMORY.md

## By DEDUP_CLASS

### CLASS_NAME
- **Pattern:** description of what triggers this FP
- **Rationale:** why it's a false positive
- **Files:** file1.sh, file2.sh
- **Finding IDs:** F-001, F-042
- **Last verified:** <date>

### CLASS_NAME_2
...

## By File

### file.sh
- F-001 (CLASS): rationale
- F-042 (CLASS): rationale

## Statistics
- Total FP entries: <N>
- Total ACCEPTABLE entries: <N>
- Unique DEDUP_CLASSes: <N>
- Files referenced: <N>
```

## Step 5: Update audit-context

Read `/root/.claude/commands/audit-context.md` and verify it includes
instructions to read the FP database. If not present, add a section:

```markdown
## False Positive Database

If `audit-output/fp-database.md` exists, read it and include its content
in the context harvest. This helps domain agents avoid re-flagging known
false positives.
```

Only add this section if it doesn't already exist. Do NOT modify other
sections of audit-context.md.

## Step 6: Output

```
# Audit Feedback Report

## Harvested Entries
- From AUDIT.md: <N> FP, <M> ACCEPTABLE
- From MEMORY.md: <N> verified FPs

## FP Database
Written to: audit-output/fp-database.md
Total entries: <N>

## audit-context.md
Status: <updated / already configured>

## Impact
Future audits will reference <N> known FP patterns, reducing
repeat false positive rate.
```

## Rules

- Never modify AUDIT.md — read only
- Never modify MEMORY.md — read only (use `/mem-save` for that)
- Create `audit-output/` directory if it doesn't exist
- Overwrite `fp-database.md` on each run (it's regenerated, not accumulated)
- Only add to `audit-context.md` if the FP database section is missing
- Preserve all existing content in `audit-context.md` when adding
