Structured pattern-class bug finder. Searches project files for instances
of known anti-patterns or a custom pattern. Groups results by file and
function, cross-references AUDIT.md for tracked instances.

## Arguments
- `$ARGUMENTS` — required: a pattern class name from the built-in library,
  `all` for all patterns, or a custom description

## Setup

Read `.rdf/governance/index.md` to identify:
- Project files to scan (from governance/architecture.md)
- Project-specific anti-patterns (from governance/anti-patterns.md)
- Existing audit findings (from AUDIT.md if present)

## Built-in Pattern Library

Universal patterns applicable to any shell project:

| Pattern Class | Pattern | Description |
|---|---|---|
| `backtick-usage` | `` `...` `` | Backtick command substitution |
| `unquoted-var` | `$var` without quotes in command context | Unquoted variable expansion |
| `bare-which` | `\bwhich\b` | Bare `which` instead of `command -v` |
| `deprecated-egrep` | `\begrep\b` | Deprecated `egrep` instead of `grep -E` |
| `dollar-bracket` | `$[` | Old-style arithmetic instead of `$(())` |
| `for-in-cat` | `for .* in \$\(cat` | Unsafe file reading pattern |
| `silent-error` | `\|\| true`, `2>/dev/null` without comment | Silent error suppression |
| `unsafe-temp` | `\$RANDOM`, `\$\$` for temp files | Unsafe temp file creation |
| `eval-usage` | `\beval\b` | Direct eval usage |
| `bare-coreutils` | `^\s*cp \|^\s*mv \|^\s*rm ` | Bare cp/mv/rm without `command` prefix |
| `missing-cd-guard` | `^\s*cd ` without `\|\| exit\|return` | Unguarded cd |
| `local-mask` | `local [a-z_]*=\$(` | Local var=$() masks exit code |

Additional project-specific patterns are loaded from
governance/anti-patterns.md when available.

## Step 1: Select Pattern

If `$ARGUMENTS` matches a pattern class name, use the predefined pattern.
If `$ARGUMENTS` is `all`, run ALL patterns (built-in + project-specific).
If `$ARGUMENTS` is a custom description, translate it to a grep/awk pattern.

## Step 2: Identify Target Files

Read governance to determine scan targets. Exclude: tests/, .git/,
vendor/, node_modules/, working files. If no governance, fall back to
scanning common source directories.

## Step 3: Execute Search

For each target file:
1. Run the pattern(s) with `grep -nE` (or equivalent)
2. For each match, identify the enclosing function name
3. Check if the match is inside a comment or string (reduce false positives)

## Step 4: Cross-Reference AUDIT.md

If AUDIT.md exists, check each finding against tracked findings.
Mark as TRACKED (with finding ID) or UNTRACKED.

## Step 5: Output

    # Code Pattern Scan: <pattern_name>

    Pattern: <regex or description>
    Files scanned: <N>
    Matches: <M>

    ## Results by File

    ### file1.sh (<N> matches)
    | Line | Function | Match | Status |
    |------|----------|-------|--------|
    | 42   | func()   | match text | TRACKED (ID) / UNTRACKED |

    ## Summary
    - Total matches: <M>
    - Tracked in AUDIT.md: <N>
    - Untracked (new): <N>
    - In comments/strings (likely FP): <N>

For `all` mode, produce a combined report with a per-pattern summary
table ahead of the per-file sections:

    ## Per-Pattern Summary

    | Pattern Class | Matches | Tracked | Untracked |
    |---|---|---|---|
    | backtick-usage | 0 | 0 | 0 |
    | bare-coreutils | 12 | 9 | 3 |
    | silent-error | 3 | 0 | 3 |
    ...

This table is the machine-parseable surface for callers that need
counts-only (e.g., `/r-refresh` Stage 1d drift delta). One row per
pattern class, including classes with zero matches — downstream
consumers rely on a stable, complete row set.

## Rules
- Read-only — do NOT modify any files
- Report false positives separately (matches in comments, strings, or
  intentionally suppressed with linter directives)
- For `silent-error`, skip instances with an inline comment explaining why
- For `unquoted-var`, only flag variables in command argument positions
