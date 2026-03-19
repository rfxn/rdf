Re-scan the codebase and update governance files while preserving user
modifications. This is an incremental update — not a full re-init.

`$ARGUMENTS` is the target path (optional, defaults to `.`).

---

## Prerequisites

- `.claude/governance/` must already exist (created by /r:init)
- If governance does not exist, instruct the user to run /r:init first

## Protocol

### Step 1: Detect User Modifications

Before updating any governance file, check for user modifications:

1. Read `.claude/governance/.user-modified` if it exists — this file
   lists governance files the user has manually edited.
2. For each governance file, check if it has been modified since the
   last /r:init or /r:refresh by comparing content against the
   generated markers.
3. Build a protected-files list — these files will NOT be overwritten.

### Step 2: Re-Ingest Convention Files (Phase 1 Lite)

Re-read existing convention files to check for changes since last init:

- If a convention file has been added (e.g., new CLAUDE.md), incorporate
  it into the coverage map.
- If a convention file has been modified, update cross-references in
  governance files to reflect new section names or line ranges.
- If a convention file has been removed, flag this and convert
  cross-references to inline content from scan data.

### Step 3: Re-Run Phase 2 (Codebase Scan)

Follow the same procedure as /r:init Phase 2. Compare results against
existing governance to identify:

- New languages or frameworks added to the project
- Removed dependencies or changed tooling
- New test files or changed test infrastructure
- New or changed linter configurations

### Step 4: Re-Run Phase 3 (Tooling Detection)

Follow the same procedure as /r:init Phase 3. Compare against existing
governance for:

- New or changed CI workflows
- New Dockerfiles or compose configurations
- Changed platform targets
- New git patterns (branch naming changes, commit convention changes)

### Step 5: Update Governance Files (Phase 4 Incremental)

For each governance file that is NOT in the protected-files list:

1. **Regenerate** the file content using the same merge logic as
   /r:init Phase 4 (reference existing .md, generate from scan, etc.)
2. **Diff** the new content against the existing governance file
3. **Apply updates** — overwrite the file with new content
4. If the file IS in the protected-files list, generate the new
   content but write it to `.claude/governance/.pending/{filename}`
   instead, with a note:
   ```
   User-modified file not updated. Pending changes written to:
   .claude/governance/.pending/{filename}
   Review and merge manually.
   ```

### Step 6: Re-Run Phase 5 (Validate)

Follow the same validation procedure as /r:init Phase 5.

### Step 7: Update Index

Regenerate `.claude/governance/index.md` to reflect current state.
The index is ALWAYS regenerated (never user-protected) because it
must accurately reflect the current governance file set.

## Output Report

```
+-- /r:refresh Complete --------------------------------------------+
| Target:     {path}                                                |
| Duration:   {elapsed time}                                        |
+-------------------------------------------------------------------+
|                                                                   |
| CHANGES DETECTED:                                                 |
|   {list of meaningful changes since last init/refresh}            |
|                                                                   |
| UPDATED FILES:                                                    |
|   {filename} — {summary of changes}                               |
|   ...                                                             |
|                                                                   |
| PROTECTED FILES (user-modified):                                  |
|   {filename} — pending changes in .pending/{filename}             |
|   ...                                                             |
|                                                                   |
| CONFIDENCE:                                                       |
|   HIGH: {count} | MEDIUM: {count} | LOW: {count}                 |
|                                                                   |
+-------------------------------------------------------------------+
```

---

## Rules

1. **NEVER delete existing governance files** — update or skip, never remove.
2. **NEVER overwrite user-modified files** — write pending changes to
   `.pending/` for manual review.
3. **ALWAYS regenerate index.md** — it must reflect current reality.
4. If no changes are detected, report "Governance is up to date" and
   skip file writes.
5. The `.user-modified` marker file uses a simple format:
   ```
   # User-modified governance files
   # Add filenames (one per line) to protect from /r:refresh overwrites
   conventions.md
   anti-patterns.md
   ```
   Users can add or remove entries manually to control protection.
