Generate proposed CHANGELOG entries from the current staged diff (or from
a commit range). Read the project's CLAUDE.md for changelog format rules.

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
| `[New]` | New function, new file, new feature, new config variable, new test file |
| `[Change]` | Modified behavior, refactored logic, improved performance, updated docs |
| `[Fix]` | Bug fix, corrected condition, fixed regression, resolved error |

Read the actual diff hunks (not just file names) to determine:
- What functions were added, modified, or removed
- What config variables were added or changed
- What behavior changed (look for conditionals, return values, error handling)
- What tests were added (count `@test` additions)

## 3. Generate entries

Produce entries matching the project's changelog format:

**APF/BFD format:**
```
[Tag] concise description of what changed
      continuation if needed (indented 6 spaces)
```

**LMD format:**
```
[Tag] concise description; issue #N, pr#N (if applicable)
```

### Entry quality rules

- One entry per logical change (not per file, not per commit)
- Group related file changes into a single entry
- Keep entries under 100 characters when possible (continuations allowed)
- Use the function/feature name, not the file path, as the subject
- State what changed for the user, not implementation details
- If a new config variable was added, mention its name and default

### Collapse rules — one entry per logical change

- **Feature + config + compat + docs** for the same thing → one `[New]` entry
- **Bug fix + validation** for the same field → one `[Fix]` entry
- **Refactor + follow-up cleanup** of the same function → one `[Change]` entry
- **install.sh + importconf** for the same concern → one entry
- **Multiple test additions** for one feature → `[New] tests for <feature> (<N> tests)`

### Entries to skip (not changelog-worthy)

Do NOT generate entries for:
- Copyright header updates
- Comment-only changes (unless correcting user-facing misinformation)
- `.dockerignore`, `.gitignore` changes
- CHANGELOG/CHANGELOG.RELEASE formatting
- Whitespace, indentation, formatting-only changes
- Working file changes (CLAUDE.md, PLAN.md, MEMORY.md, .claude/)

Merge multiple README.md/man-page text updates into one line unless they fix
genuinely different user-facing errors.

### Never include tracking artifacts

Do NOT include audit finding codes (`F-NNN`, `C-NNN`, `R-NNN`), phase
markers (`Phase 1`, `[R-001]`), or any internal tracking references in
generated entries. These are session artifacts, not user-facing information.

## 4. Output

```
## Proposed CHANGELOG entries

Based on: <staged diff / commit range / unstaged diff>
Files changed: <N>

### Entries (<N>)
[Tag] entry one
[Tag] entry two
...

### Notes
- <any ambiguity or items needing manual review>
- <any files changed that don't warrant a changelog entry>
```

## 5. Apply mode

Two ways to trigger apply:

1. **Manual**: User says to apply after reviewing proposed entries
2. **`--commit` flag**: If `$ARGUMENTS` contains `--commit`, auto-apply after
   generating entries, then stage and prepare a commit

### Apply behavior (both modes)

**CHANGELOG** — append entries as a flat tagged list under the current version
header. No section grouping. Newest entries at the bottom of the version block.

**CHANGELOG.RELEASE** — place entries under the appropriate section headers:
```
  -- New Features --
  -- Bug Fixes --
  -- Changes --
```
Only include sections that have entries. Create section headers if they don't
exist yet. Place each `[New]` under New Features, `[Fix]` under Bug Fixes,
`[Change]` under Changes.

Do NOT duplicate entries that already exist — check first.

### `--commit` mode additional steps

After applying entries to both files:

1. Stage explicitly by name: `git add CHANGELOG CHANGELOG.RELEASE`
2. Generate a commit message following the project's format:
   - LMD: `[Change] Update CHANGELOG for v<version>`
   - APF/BFD: `VERSION | Update CHANGELOG`
3. Show the staged diff and proposed commit message
4. Ask the user to confirm before committing
5. If confirmed, create the commit

## Rules
- Do NOT read source files beyond the diff — the diff is your only input
- Do NOT invent changes not present in the diff
- Do NOT include working file changes (CLAUDE.md, PLAN.md, .claude/) in entries
- Do NOT include tracking codes (F-NNN, C-NNN, phase markers) in entries
- Without `--commit`: propose entries only — do not write to CHANGELOG unless told to apply
- With `--commit`: apply, stage, and prompt for commit confirmation
- If the diff is empty, say so and exit
