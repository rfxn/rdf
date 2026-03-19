# /r:util:rel-squash — Release Branch Squash

Generate a squash plan for the current release branch by grouping
commits into logical buckets aligned with CHANGELOG.RELEASE entries.
Default: plan summary only. Pass `--apply` to execute after review.

## Arguments

`$ARGUMENTS` — optional flags:
- No args: plan summary only (dry-run)
- `--apply`: present plan, then execute after explicit user confirmation

## Protocol

### 1. Safety Pre-flight

Run all checks in a single Bash call:

```bash
git status --short
git stash list | head -5
git log --oneline -3
git log --merges --oneline "$(git merge-base HEAD master)"..HEAD | head -5
```

**Abort if:**
- Dirty working tree (uncommitted changes)
- Merge commits present in range (rebase cannot squash through merges)
- No commits in range (nothing to squash)

**Detect:** If branch has a remote tracking ref, note that execution
will require `git push --force-with-lease`.

### 2. Determine Scope

```bash
base="master"
merge_base=$(git merge-base HEAD "$base")
total=$(git rev-list --count "$merge_base"..HEAD)
git log --oneline "$merge_base"..HEAD
```

Store the full commit list. Reverse internally to oldest-first order
for grouping (oldest commit is the group anchor/`pick`).

### 3. Read CHANGELOG.RELEASE

Extract the ordered list of changelog entries as target buckets.
Each distinct entry becomes one squash target bucket (B01, B02, ...).

If CHANGELOG.RELEASE is missing: fall back to topic-grouping
heuristics — bucket labels come from commit subject prefixes.

### 4. Generate Squash Plan

Map every commit (oldest-first) to a bucket using sequential
neighbor grouping. Target: one squash group per CHANGELOG entry.

**Grouping rules (priority order):**

1. **Phase prefix match** — commits sharing `Phase N` or `P<N>` cluster
2. **CHANGELOG entry alignment** — keyword match between commit subject
   and changelog description (function names, feature names, flags)
3. **Fix-up absorption** — commits starting with fix/fixup/follow-up,
   or containing "review fix", "QA fix", "address" → absorb into
   preceding non-fixup bucket
4. **Sequential topic runs** — consecutive commits on the same topic
   with no CHANGELOG alignment form their own group. Topics inferred
   from keywords (alert, packaging, test, events, report, etc.)
5. **Natural boundaries** — start new bucket on phase/feature boundary
   or abrupt topic change
6. **Orphan assignment** — unmatched commits go to nearest preceding
   bucket, or to `[misc]` if isolated

**Bucket structure:**
- Bucket number (sequential)
- CHANGELOG ref (B-label or `[misc]`/`[tests]`)
- Commit count
- Anchor commit (oldest = `pick`)
- Fixup commits (all others = `fixup`)
- Proposed squash message (from anchor subject or CHANGELOG entry,
  using project commit format)

### 5. Validate Totals

Before presenting:
1. Sum of bucket commit counts == total commits in range
2. No hash appears in more than one bucket
3. No hash is missing from all buckets

If validation fails, report discrepancy and stop.

### 6. Present Plan

```
# Squash Plan: {branch} -> master

Branch commits: {N}
Squash buckets: {M}
CHANGELOG entries: {K}

| # | Commits | Proposed Message       | Anchor  | Fixups       |
|---|---------|------------------------|---------|--------------|
| 1 |    3    | 2.0.1 | Alert rewrite  | abc1234 | def56, ghi90 |
| 2 |    7    | 2.0.1 | Pool overhaul  | jkl3456 | mno78, ...   |

## Bucket Details
### Bucket 1 — Alert rewrite
Anchor: abc1234 — 2.0.1 | Email rewrite phase 1
Fixup:  def5678 — 2.0.1 | Email rewrite phase 2
        ghi9012 — Fix alert template subject header
```

If remote tracking exists, warn about force-push requirement.

If no `--apply`: stop here with `Plan complete. To execute: --apply`

If `--apply`: pause and require user to type "yes, squash" before
proceeding to execution.

### 7. Execute (only after explicit user approval)

1. Build rebase sequence: `pick` for anchor, `fixup` for rest
2. Write temporary GIT_SEQUENCE_EDITOR script
3. Run: `GIT_SEQUENCE_EDITOR="<script>" git rebase -i "<merge_base>"`
4. Clean up temp script
5. Report before/after commit counts, show new log

## Rules
- **Never execute without explicit user approval** — dry-run is default
- **Never use interactive `git rebase -i`** — always use
  GIT_SEQUENCE_EDITOR with pre-computed script
- **Never squash across merge commits** — detect and abort early
- **Never lose commits** — validate totals before and after
- **Always warn about force-push** when remote tracking ref exists
- Use `fixup` not `squash` — discard intermediate messages
- Proposed messages use the project's detected commit format
- Do not modify CHANGELOG, source files, or any tracked file
