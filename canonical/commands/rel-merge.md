Generate a squash/merge commit message for the current release branch.
Consolidates all branch commits and CHANGELOG.RELEASE into a formatted
message suitable for merging to master. Do NOT execute the merge — output only.

## Arguments
- `$ARGUMENTS` — optional: base branch override (default: `master`)

## Step 1: Determine Scope

```bash
base="${ARGUMENTS:-master}"
merge_base=$(git merge-base HEAD "$base")
commit_count=$(git rev-list --count "$merge_base"..HEAD)
```

If `commit_count` is 0, report "No commits to merge." and stop.

## Step 2: Gather Data

1. **Commit log**: `git log --oneline "$merge_base"..HEAD`
2. **Full diff stats**: `git diff --stat "$merge_base"..HEAD`
3. **CHANGELOG.RELEASE**: Read the current release entries
4. **Version**: Extract from project source (CLAUDE.md or main script)

## Step 3: Generate Merge Commit Message

Use the project's commit format. For LMD:

```
v<version> release merge

[New] feature description 1
[New] feature description 2
[Change] change description 1
[Fix] bug fix description 1
[Fix] bug fix description 2

---
<N> commits | <files changed> files | +<insertions> -<deletions>
```

Rules for the message body:
- Source entries from CHANGELOG.RELEASE (authoritative, already deduplicated)
- Group by tag: [New] first, then [Change], then [Fix]
- One entry per line, no bullets or dashes (just the tag)
- Do NOT include individual commit hashes or per-commit details
- Add a stats line at the bottom

## Step 4: Generate PR Command

Also output a ready-to-use `gh pr create` command:

```bash
gh pr create --title "v<version> release" --body "$(cat <<'EOF'
## Summary
<3-5 bullet points from CHANGELOG.RELEASE>

## Changes
<full tagged entry list>

## Test Results
<CI status from `gh run list --limit 1` if available>

## Merge Instructions
Squash merge recommended. Use the commit message above.
EOF
)"
```

## Step 5: Output

```
# Merge Message: <project> v<version>

## Commit Message (copy below)

<generated message>

## PR Command (copy below)

<gh pr create command>

## Branch Stats
- Commits: <N>
- Files changed: <N>
- Insertions: +<N>
- Deletions: -<N>
```

## Rules

- Always source from CHANGELOG.RELEASE, not raw git log
- If CHANGELOG.RELEASE is empty or missing, warn and fall back to git log
- Never include working file changes in the stats
- Strip any audit codes (F-NNN) or phase markers from entries
