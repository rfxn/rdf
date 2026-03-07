Structured pattern-class bug finder. Searches all project shell files for
instances of known anti-patterns or a custom pattern. Groups results by
file and function, cross-references AUDIT.md for tracked instances.

## Arguments
- `$ARGUMENTS` — required: a DEDUP_CLASS name from the built-in library OR
  a custom description (e.g., "functions that call eval")

## Built-in Pattern Library

| DEDUP_CLASS | Pattern | Description |
|-------------|---------|-------------|
| `backtick-usage` | `` `...` `` | Backtick command substitution |
| `hardcoded-path` | `/sbin/`, `/usr/sbin/`, `/usr/local/maldetect` | Hardcoded binary/install paths |
| `unquoted-var` | `$var` without quotes in command context | Unquoted variable expansion |
| `bare-which` | `\bwhich\b` | Bare `which` instead of `command -v` |
| `deprecated-egrep` | `\begrep\b` | Deprecated `egrep` instead of `grep -E` |
| `dollar-bracket` | `$[` | Old-style arithmetic instead of `$(())` |
| `for-in-cat` | `for .* in \$\(cat` | Unsafe file reading pattern |
| `silent-error` | `\|\| true`, `2>/dev/null` without comment | Silent error suppression |
| `hardcoded-install` | `/usr/local/maldetect` (outside internals.conf) | Hardcoded install path |
| `unsafe-temp` | `\$RANDOM`, `\$\$` for temp files | Unsafe temp file creation |
| `missing-local` | function vars without `local` | Missing local declarations |
| `eval-usage` | `\beval\b` | Direct eval usage |
| `empty-file-arg` | `< "$var"`, `cat "$var"`, `base64 < "$var"` where `$var` has conditional assignment | File redirect on potentially empty/unset path variable |
| `config-gated-file` | file creation gated on config value but consumers don't check existence | Config-conditional artifact with unconditional consumption |

## Step 1: Select Pattern

If `$ARGUMENTS` matches a DEDUP_CLASS name from the library, use the
predefined pattern and description.

If `$ARGUMENTS` is a custom description, translate it to a grep/awk pattern:
- Parse the description for key terms
- Construct appropriate regex patterns
- May require multiple passes (grep + awk for context)

## Step 2: Identify Target Files

Read the project's CLAUDE.md to determine which files to scan. Typically:
- All files under `files/` (excluding binary data, signatures)
- `install.sh`, `cron.daily`
- Exclude: `tests/`, `.git/`, `audit-output/`, working files

## Step 3: Execute Search

For each target file:
1. Run the pattern(s) with `grep -nE` (or equivalent)
2. For each match, identify the enclosing function name:
   - Search backward from match line for `function <name>` or `<name>() {`
   - Report as `file:line (in function_name)`
3. Check if the match is inside a comment or string (reduce false positives)

## Step 4: Cross-Reference AUDIT.md

If AUDIT.md exists, for each finding:
- Check if it matches a tracked finding (by file:line proximity or description)
- Mark as TRACKED (with finding ID) or UNTRACKED

## Step 5: Output

```
# Code Pattern Scan: <pattern_name>

Pattern: <regex or description>
Files scanned: <N>
Matches: <M>

## Results by File

### file1.sh (<N> matches)
| Line | Function | Match | Status |
|------|----------|-------|--------|
| 42   | prerun() | `which curl` | TRACKED (F-012) |
| 108  | scan()   | `which yara` | UNTRACKED |

### file2.sh (<N> matches)
...

## Summary
- Total matches: <M>
- Tracked in AUDIT.md: <N>
- Untracked (new): <N>
- In comments/strings (likely FP): <N>
```

## Multi-Pattern Mode

If `$ARGUMENTS` is `all`, run ALL built-in patterns and produce a combined
report:

```
# Full Anti-Pattern Scan

| Pattern | Matches | Tracked | New |
|---------|---------|---------|-----|
| backtick-usage | 0 | — | — |
| hardcoded-path | 3 | 2 | 1 |
| bare-which | 0 | — | — |
| ...

Total: <N> matches across <M> patterns
```

## Rules

- Read-only — do NOT modify any files
- Report false positives separately (matches in comments, strings, or
  intentionally suppressed with shellcheck directives)
- For `unquoted-var`, only flag variables in command argument positions
  (not inside `[[ ]]` or assignments)
- For `silent-error`, skip instances that have an inline comment explaining why
