Generate GitHub release notes from CHANGELOG.RELEASE. Transforms changelog
entries into GitHub-flavored markdown with proper formatting, links, and
test matrix summary. Do NOT publish unless `--publish` flag is provided.

## Arguments
- `$ARGUMENTS` — optional: `--publish` to create GitHub release via `gh`

## Step 1: Read Source Data

1. Read CHANGELOG.RELEASE for the current version's entries
2. Extract version from project source (main script or CLAUDE.md)
3. Get release date from CHANGELOG header or current date
4. Get test matrix summary from CI (`gh run list --limit 1`) if available

If CHANGELOG.RELEASE is empty, report "No release entries found." and stop.

## Step 2: Transform Entries

Convert changelog format to GitHub release notes markdown:

### Section Mapping
- `[New]` entries → `### New Features` section
- `[Change]` entries → `### Changes` section
- `[Fix]` entries → `### Bug Fixes` section

### Entry Formatting
- Convert issue references (`#N`) to GitHub links: `[#N](../../issues/N)`
- Convert PR references (`pr#N`) to GitHub links: `[PR #N](../../pull/N)`
- Strip leading tags (they become section headers instead)
- Wrap code/function names in backticks if not already

## Step 3: Generate Release Notes

```markdown
# v<version>

Released: <date>

<one-paragraph summary of the release's highlights>

### New Features
- Feature description ([#N](../../issues/N))
- Feature description

### Changes
- Change description
- Change description

### Bug Fixes
- Fix description ([#N](../../issues/N))
- Fix description

### Test Matrix
| Target | Status |
|--------|--------|
| Debian 12 | PASS |
| Rocky 9 | PASS |
| Ubuntu 24.04 | PASS |
| ... | ... |

### Installation
```bash
git clone https://github.com/rfxn/linux-malware-detect.git
cd linux-malware-detect
./install.sh
```

### Full Changelog
See [CHANGELOG](CHANGELOG) for the complete history.
```

## Step 4: Output

Display the generated release notes for review.

If `--publish` not specified, also output the `gh` command:
```bash
gh release create v<version> --title "v<version>" --notes-file /tmp/release-notes.md
```

## Step 5: Publish (only with --publish)

If `$ARGUMENTS` contains `--publish`:
1. Write release notes to a temp file
2. Run `gh release create v<version> --title "v<version>" --notes-file <tmpfile>`
3. Report the release URL
4. Clean up temp file

If `--publish` not specified, end with:
"Run `/rel-notes --publish` to create the GitHub release."

## Rules

- Source from CHANGELOG.RELEASE only (not raw git log)
- Never include internal tracking codes (F-NNN, phase markers)
- Keep the summary paragraph concise (2-3 sentences max)
- If no CI data available, omit the Test Matrix section
- Adjust repository URL based on `gh repo view --json nameWithOwner`
