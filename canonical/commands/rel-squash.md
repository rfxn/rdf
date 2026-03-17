Generate a squash plan for the current release branch by grouping commits into
logical buckets aligned with CHANGELOG.RELEASE entries. Default: summary output
only. Pass `--apply` to execute the rebase after review.

## Arguments
- `$ARGUMENTS` — optional: `--apply` (present plan, then execute after
  explicit user confirmation). Default (no flag): plan summary only.

## Step 0: Safety pre-flight

Before doing anything else, run all three checks in a single Bash call:

```bash
git status --short
git stash list | head -5
git log --oneline -3
```

Abort with a clear error if any of these conditions are true:
- **Dirty working tree**: uncommitted changes or untracked files that overlap
  with tracked files. Instruct the user to stash or commit first.
- **Merge commits present** in the range: `git log --merges --oneline
  "$(git merge-base HEAD master)"..HEAD | head -5`. If any exist, warn that
  `git rebase -i` cannot squash through merge commits. Report the hashes and
  stop — do not proceed without user acknowledgment.
- **No commits in range**: if commit count is 0, report "No commits to squash."
  and stop.

Also detect remote tracking:
```bash
git log --format='%D' HEAD | head -1
```
If the branch has a remote tracking ref (contains `origin/`), note that
execution will require a force-push. Store this for the warning in Step 5.

## Step 1: Determine scope

Run in one Bash call:

```bash
base="master"
merge_base=$(git merge-base HEAD "$base")
total=$(git rev-list --count "$merge_base"..HEAD)
echo "MERGE_BASE=$merge_base"
echo "TOTAL_COMMITS=$total"
git log --oneline "$merge_base"..HEAD
```

Store the full commit list (newest first, as `git log` returns them). Reverse
it internally to produce oldest-first order for grouping — squash plans must
read chronologically (oldest commit is the group anchor/`pick`, newer commits
become `fixup`).

## Step 2: Read CHANGELOG.RELEASE

Read CHANGELOG.RELEASE in full. Extract the ordered list of changelog entries
as the target bucket list. Each distinct entry (or collapsed group of entries
that belong to the same feature) is one squash target bucket.

If CHANGELOG.RELEASE is missing or empty:
- Warn the user that bucket mapping will be approximate
- Fall back to topic-grouping heuristics only (Steps 3 grouping rules apply,
  but bucket labels come from commit subject prefixes instead)

Assign each CHANGELOG.RELEASE entry a sequential bucket number: B01, B02,
... BNN. This is the target plan structure.

## Step 3: Generate squash plan

Map every commit (oldest-first) to a bucket using sequential neighbor grouping.
The goal is one squash group per logical CHANGELOG.RELEASE entry. Process
commits left-to-right (chronologically); once a commit is assigned, move on.

### Grouping rules (apply in priority order)

**Rule 1 — Phase prefix match**
If a commit subject contains `Phase N` or `P<N>` and adjacent commits share
the same phase label, group them together.

**Rule 2 — CHANGELOG entry alignment**
Map each commit to the CHANGELOG.RELEASE entry it most likely implements.
Use keyword matching between commit subject and changelog description:
- Match on function names, feature names, flag names, subsystem names
- A commit implementing "periodic threat reports" maps to the report entry
- A commit fixing "CIDR country code" maps to the CIDR entry
Commits that clearly implement the same entry as their neighbors cluster
into that bucket.

**Rule 3 — Fix-up / follow-on absorption**
A commit is a fix-up if its subject matches any of these patterns:
- Starts with: `fix`, `Fix`, `fixup`, `follow-up`, `follow up`, `correction`
- Contains: `address review`, `sentinel fix`, `QA fix`, `review fix`,
  `resolve`, `address`, `remediation`
- Is a pure changelog/doc commit with no behavior change
Absorb it into the bucket of the immediately preceding non-fixup commit.

**Rule 4 — Sequential topic runs**
Consecutive commits on the same topic (alert, packaging, test, pressure,
events, report, watch, install) that have no clear CHANGELOG alignment form
their own group. Topic is inferred from commit subject keywords:
- `alert`, `email`, `smtp`, `slack`, `telegram`, `discord` → alert
- `pack`, `rpm`, `deb`, `install`, `uninstall`, `importconf` → packaging
- `test`, `bats`, `spec`, `fixture`, `coverage` → tests
- `pressure`, `score`, `weight`, `trip`, `half-life` → pressure
- `event`, `pool`, `attack.pool`, `apool` → events
- `report`, `trend`, `template` → reports
- `watch`, `daemon`, `lock`, `SIGHUP` → watch mode
- `geoip`, `country`, `ipcountry`, `cidr` → geoip
- `tlog`, `elog`, `pkg_lib`, `alert_lib`, `geoip_lib` → library sync

**Rule 5 — Natural boundaries**
Start a new bucket when:
- Commit subject contains a clear phase or feature boundary marker
- Topic changes abruptly (two consecutive commits from different topic buckets
  with no bridging context)
- A commit explicitly reverts or replaces a prior commit in the same range

**Rule 6 — Orphan assignment**
Any commit not matched by Rules 1-5 is assigned to the nearest preceding
matched bucket, or to a new `[misc]` bucket if it is isolated.

### Bucket structure

Each bucket has:
- **Bucket number**: sequential integer (1, 2, ... N)
- **CHANGELOG ref**: B-label of the matching CHANGELOG.RELEASE entry, or
  `[misc]` / `[tests]` / `[packaging]` for unanchored groups
- **Commit count**: number of commits in this bucket
- **Anchor commit**: the oldest commit in the bucket (becomes the `pick`)
- **Fixup commits**: all other commits in the bucket (become `fixup`)
- **Proposed squash message**: the commit message for the squashed result.
  Source from: the anchor commit's subject (cleaned up), OR the CHANGELOG.RELEASE
  entry text if it is more descriptive. Use the project's commit format (e.g.,
  `2.0.1 | Description` for BFD, detected from existing commit messages).

## Step 4: Validate totals

Before presenting the plan, verify:
1. `sum of all bucket commit counts == total commits in range`
2. No commit hash appears in more than one bucket
3. No commit hash is missing from all buckets

If validation fails, report the discrepancy and do NOT proceed to execution.
Fix the plan mapping before continuing.

## Step 5: Present the squash plan

Output the plan as a table plus a summary section:

```
# Squash Plan: <branch> -> master

Branch commits: <N>
Squash buckets: <M>
CHANGELOG entries: <K>

| # | Commits | Proposed Message | Anchor Hash | Fixup Hashes |
|---|---------|-----------------|-------------|--------------|
| 1 |    3    | 2.0.1 | Alert email rewrite | abc1234 | def5678, ghi9012 |
| 2 |    7    | 2.0.1 | Attack pool overhaul | jkl3456 | mno7890, ... |
...
| N |    2    | 2.0.1 | CIDR country code resolution | xyz1234 | uvw5678 |

Total: <sum> commits in <M> buckets

## Bucket Details

### Bucket 1 — Alert email rewrite
CHANGELOG: [New] Rewrote email alert system with SMTP relay support...
Anchor: abc1234 — 2.0.1 | Email rewrite phase 1
Fixup:  def5678 — 2.0.1 | Email rewrite phase 2
        ghi9012 — Fix alert template subject header

### Bucket 2 — Attack pool overhaul
...
```

After the table and details, output the force-push warning if applicable:

```
WARNING: Branch '<branch>' has a remote tracking ref (origin/<branch>).
Execution will rewrite history and require:
  git push --force-with-lease origin <branch>

Only proceed if no other developers are working from this branch.
```

If no `--apply` flag was given, end here:
```
Plan complete. Review the squash groups above.
To execute: rerun with --apply
```

If `--apply` was passed, pause and require explicit user confirmation
before running Step 6. Print:
```
--apply: ready to rewrite history. Type "yes, squash" to proceed.
```
Do NOT proceed until the user responds with unambiguous confirmation.

## Step 6: Execute the squash (only after explicit user approval)

### 6a: Build the rebase sequence file

Construct the exact rebase todo content. For each bucket:
- First commit: `pick <hash> <subject>`
- Remaining commits: `fixup <hash> <subject>`

Emit the sequence in oldest-first order matching the chronological commit list.
Verify the total line count equals the total commit count before proceeding.

### 6b: Write the editor script

Write a temporary shell script that GIT_SEQUENCE_EDITOR will invoke. The
script replaces the default todo file with the pre-computed sequence:

```bash
#!/bin/bash
# Auto-generated by rel-squash — do not edit manually
cat > "$1" <<'SQUASH_EOF'
pick <hash1> <subject1>
fixup <hash2> <subject2>
fixup <hash3> <subject3>
pick <hash4> <subject4>
fixup <hash5> <subject5>
...
SQUASH_EOF
```

Write the script to a temp file: `$(mktemp /tmp/rel-squash-editor.XXXXXX.sh)`
Set it executable: `chmod +x <tmpfile>`

### 6c: Run the rebase

```bash
GIT_SEQUENCE_EDITOR="<tmpfile>" git rebase -i "<merge_base>"
```

Capture exit code. If non-zero, report the error and instruct the user to
run `git rebase --abort` if the rebase is in a conflicted state.

### 6d: Amend squash commit messages

After the rebase completes, the squashed commits will have auto-generated
messages from `fixup` (which discards fixup messages) or `squash` (which
concatenates). Since we used `fixup`, the anchor message is preserved.

If any bucket's anchor commit message needs cleanup (e.g., it is a mid-phase
commit with a generic message like "Phase 2 fix"), offer to `git commit --amend`
with the proposed squash message from Step 3.

List any commits that may need message cleanup and offer to amend them
interactively.

### 6e: Clean up

Remove the temp editor script:
```bash
rm -f "<tmpfile>"
```

### 6f: Post-rebase report

```
# Squash Complete: <branch>

Before: <N> commits
After:  <M> commits
Reduction: <N-M> commits removed (<pct>%)

## Result (git log --oneline)
<first 10 lines of new log>

## Next steps
1. Verify the squashed history looks correct:
   git log --oneline $(git merge-base HEAD master)..HEAD

2. Run tests to confirm nothing broke:
   make -C tests test

3. If branch was pushed previously, force-push is required:
   git push --force-with-lease origin <branch>
   (NEVER use --force on a shared branch without team coordination)

4. Open the PR when satisfied:
   /rel-ship
```

## Rules

- **Never execute without explicit user approval** — dry-run is the default
- **Never use `git rebase -i` with a terminal editor** — always use
  GIT_SEQUENCE_EDITOR with a pre-computed script to avoid interactive prompts
- **Never squash across merge commits** — detect and abort early (Step 0)
- **Never lose commits** — validate totals before and after execution
- **Always warn about force-push** before execution when a remote tracking ref
  exists for the branch
- **Do not modify CHANGELOG, source files, or any tracked file** during this
  operation — squash only affects git history
- **If the rebase fails**, do not attempt to recover automatically — instruct
  the user to run `git rebase --abort` and report what went wrong
- **Proposed messages use the project's commit format** — detect format from
  existing commit messages in the log (e.g., `VERSION | Description` for BFD/APF,
  `[Type] description` for LMD)
- **`fixup` not `squash`** — use `fixup` to discard intermediate messages and
  keep the anchor message. Never use `squash` unless the user explicitly requests
  message concatenation for a specific bucket.
- **Bucket count target** is roughly one per CHANGELOG.RELEASE entry — err on
  the side of fewer, larger buckets rather than many small ones
- **Default** (no flag) produces the plan report and stops — summary only
- **`--apply`** produces the plan, then pauses for explicit confirmation
  before running Step 6. The flag alone is not consent — the user must confirm.
