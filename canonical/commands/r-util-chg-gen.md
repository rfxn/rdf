Generate changelog entries from the current diff or commit range. Read
governance for changelog format rules.

## Arguments
- `$ARGUMENTS` — optional: commit range (e.g., `HEAD~3..HEAD`) or
  `--commit` to auto-apply and prepare a commit

## Setup

Read `.claude/governance/index.md` to identify:
- Changelog format conventions (from governance/conventions.md)
- Changelog file locations (CHANGELOG, CHANGELOG.RELEASE, or equivalent)
- Tag conventions ([New], [Change], [Fix] or project-specific)

## 1. Determine scope

Priority order:
1. If there are staged changes (`git diff --cached`), use those
2. If an argument like `HEAD~3..HEAD` is provided, use that commit range
3. Otherwise, use unstaged changes (`git diff`)

If no changes found, report and exit.

## 2. Analyze the diff

For each changed file, classify the change:

| Tag | Criteria |
|-----|----------|
| `[New]` | New function, file, feature, config variable, test file |
| `[Change]` | Modified behavior, refactored logic, updated docs |
| `[Fix]` | Bug fix, corrected condition, fixed regression |

Read actual diff hunks (not just file names) to determine what changed.

## 3. Generate entries

Produce entries matching the project's changelog format from governance.

### Entry quality rules
- One entry per logical change (not per file, not per commit)
- Group related file changes into a single entry
- Keep entries under 100 characters when possible
- State what changed for the user, not implementation details

### Collapse rules
- Feature + config + docs for the same thing -> one `[New]` entry
- Bug fix + validation for the same field -> one `[Fix]` entry
- Multiple test additions for one feature -> one entry with count

### Entries to skip
- Copyright header updates
- Comment-only changes
- Whitespace/formatting-only changes
- Working file changes (CLAUDE.md, PLAN.md, MEMORY.md, .claude/)

### Never include tracking artifacts
No audit finding codes, phase markers, or internal tracking references.

## 4. Output

Display the proposed entries using structured formatting:

```
### Proposed CHANGELOG Entries

**Source**: `<staged diff / commit range / unstaged diff>`
**Files changed**: {N}

#### Tag Summary

| Tag | Count |
|-----|-------|
| `[New]` | {N} |
| `[Change]` | {N} |
| `[Fix]` | {N} |

#### Entries ({N})
```

Show the proposed entries themselves in a fenced code block so they
are copy-pasteable without formatting artifacts:

````
```
[Tag] entry one
[Tag] entry two
...
```
````

If there are ambiguities or items needing manual review, use a
blockquote callout:

```
> **Review Notes**
> - {ambiguity or item needing manual attention}
> - {additional note}
```

## 5. Apply mode

**Manual**: User says to apply after reviewing proposed entries.
**`--commit` flag**: Auto-apply, then stage and prepare a commit.

### Apply behavior
- CHANGELOG: append entries under the current version header
- CHANGELOG.RELEASE: place entries under appropriate section headers
- Do NOT duplicate entries that already exist — check first

### --commit mode additional steps
1. Stage changelog files explicitly by name
2. Generate a commit message following governance format
3. Show staged diff and proposed commit message
4. Ask user to confirm before committing

## Rules
- Do NOT read source files beyond the diff — the diff is your only input
- Do NOT invent changes not present in the diff
- Do NOT include working file changes in entries
- Do NOT include tracking codes in entries
- Without `--commit`: propose entries only
- If the diff is empty, say so and exit
