Scan CHANGELOG and CHANGELOG.RELEASE for the current branch version only.
Deduplicate, merge overlapping entries, strip tracking artifacts, remove fluff,
condense verbose wording, and enforce section structure in CHANGELOG.RELEASE.
Report findings first — only modify files when explicitly told to fix.

## Scoping to current version

Gather branch name and (if cross-ref requested) commit list in ONE Bash call:

```bash
ver=$(git branch --show-current)
echo "VERSION=$ver"
# Only if --full or user requested cross-reference:
# git log --oneline "$(git merge-base HEAD master)..HEAD"
```

Then scope the changelogs — do NOT read the full files. Find the version
header line number first, then read only that block:

1. Use Grep to find the line number of the version header in CHANGELOG
2. Use Grep to find the NEXT version header (or note EOF)
3. Use Read with offset/limit to extract only that range
4. Read CHANGELOG.RELEASE (typically small — full read is fine)
5. If the branch version doesn't match any CHANGELOG header, warn and use
   the first (newest) block as fallback

## Detection rules

### 1. Tracking artifact removal (MANDATORY — strip before all other analysis)

Strip these Claude/AI session artifacts from all entries. They are internal
tracking primitives that mean nothing to readers:

- **Finding references**: `(F-NNN)`, `(C-NNN)`, `(R-NNN)`, `(D-NNN)` —
  parenthesized alphanumeric codes appended to entries
- **Phase markers**: `Phase 1`, `Phase 2`, `[R-001]`, `[R-002]` etc.
- **Tracking prefixes**: `F-NNN:`, `C-NNN:` at the start of descriptions
- **Pattern**: anything matching `\([A-Z]-[0-9]+\)` or `\[[A-Z]-[0-9]+\]`
  in entry text should be removed

Strip these in-place — do not report them as separate findings. Just remove
them silently and note the total count in the output summary.

### 2. Fluff entries (DROP or MERGE)

These entry types are housekeeping noise — not user-facing behavioral changes.
They should be dropped entirely or merged into a single summary line:

**Drop entirely** (no changelog entry warranted):
- Copyright header updates (`add standard copyright header`, `update copyright`)
- CHANGELOG/CHANGELOG.RELEASE housekeeping (`changelog updates`, `sync changelog`)
- `.dockerignore`, `.gitignore` changes
- Comment-only changes (`correct comment`, `improve docs in conf.apf` when the
  config behavior didn't change)
- Whitespace, formatting, indentation-only fixes
- Config file formatting (`split X onto separate lines for readability`)
- Internal code style (`extract inline regex to named variables`)

**Merge into one summary line** (keep but compress):
- Multiple README/README.md updates → one `[Change] update README documentation`
- Multiple man page text corrections → one `[Change] man page corrections`
- Multiple test infrastructure changes (Makefile, Dockerfile, CI workflow) →
  one `[Change] test infrastructure updates` (only in CHANGELOG, not CHANGELOG.RELEASE)
- Multiple config file comment improvements → drop unless behavior changed

**Judgment calls** — keep if the entry describes a real behavioral change even
if the file seems like "docs":
- `[Fix] README: troubleshooting corrected from 'apf -l' to 'apf --rules'` — KEEP
  (fixes incorrect user guidance)
- `[Change] conf.apf: correct DOCKER_COMPAT comment` — DROP (comment-only)
- `[New] README section 2.4 Uninstallation` — can fold into the uninstall.sh entry

### 3. Duplicates
1. **Exact duplicates**: identical lines (ignoring leading whitespace)
2. **Near-duplicates**: entries describing the same change with different wording
   - Same file path + same function name = likely duplicate
   - Same tag + overlapping description keywords = likely duplicate
3. **Tag mismatches**: same change described as [New] in one entry and [Fix] in another
4. **Contradictions**: one entry says "added X" and another says "removed X"

### 4. Overlapping entry collapse

Aggressively merge entries that describe different facets of the same feature
or fix. A reader should see one entry per logical change, not one per commit:

- **Feature + config + compat + docs** for the same variable → one `[New]` entry
- **Sequential fix + fix** for the same bug → keep only the final fix
- **Refactor + follow-up cleanup** of the same function → one `[Change]` entry
- **Multiple test file additions** for the same feature → one `[New] tests for <feature> (<N> tests)`
- **Bug fix + validation addition** for the same field → one `[Fix]` entry
- **install.sh + importconf** entries for the same concern → one entry
- **Multiple entries touching the same function** → collapse unless they
  describe genuinely independent changes
- **Multiple entries for the same file** (e.g., 3 `install.sh` [Fix] entries,
  2 `.ca.def` [Fix] entries) → collapse into one per file
- **[New] internal function + [Fix] describing same behavior** → keep whichever
  tag is user-facing; e.g., `[New] snapshot_save()` + `[Fix] Fast load validation`
  → one `[Fix]` entry covering the user-visible improvement
- **Multiple CLI option additions** → collapse into one `[New] New CLI commands:`
  entry listing all options in a single sentence
- **Multiple same-theme hygiene entries** (e.g., 3 separate entries for
  shell compat, local vars, temp files) → one `[Fix] Code hygiene:` entry
- **Vendored library updates** → collapse all lib updates into one entry

When collapsing, the merged entry must preserve all factual content that
matters to the reader. Drop implementation details (function names, line
counts, internal variable names) that don't help users understand what changed.

### 5. Internal-only entries (DROP or FOLD)

These entries describe implementation details, not user-facing changes. They
should be dropped entirely or folded into the parent feature/fix entry:

**Drop entirely:**
- Internal variable initialization (`IPT_FLAGS="" before conditional append`)
- Code comments added/corrected (unless the comment IS the documentation,
  e.g., a config file comment that users read)
- Dead code removal (`remove redundant -z test and elif`)
- Test rewrites that don't change coverage (`rewrite importconf tests`)
- Internal refactoring names (`extract _maybe_block_escalate() helper`)

**Fold into parent entry:**
- `[Fix] move ELOG vars to internals.conf` → fold into elog_lib [New] entry
- `[Fix] sh to bash invocations for pkg_lib` → fold into pkg_lib [New] entry
- `[Fix] add audit.log to logrotate` → fold into elog_lib [New] entry
- `[New] snapshot_save()` → fold into fast-load [Fix] entry

**The test:** Would a sysadmin reading the changelog understand or care about
this entry? If it requires knowledge of the source code to understand, it
belongs in a commit message, not a changelog.

### 6. Verbose entries

Flag entries longer than ~100 characters that:
- Repeat file paths already implied by context or section
- Restate what the tag already means (`[Fix] fix the bug that...`)
- Include implementation details (grep patterns, sed commands, variable names)
  that belong in commit messages, not changelogs
- List every affected file in parentheses when the function name is sufficient
- Enumerate every internal variable a feature validates (e.g., listing 15
  config variable names) — summarize as categories instead
- Describe every sub-section of a CLI output (e.g., --info listing all
  dashboard sections) — one sentence suffices

### 7. Section proliferation (MANDATORY — check structure first)

CHANGELOG.RELEASE must use **3-5 sections maximum**:
- New Features, Bug Fixes, Changes (required when entries exist)
- Documentation, Test Suite (optional, for 3+ standalone entries)

**Anti-pattern: topical micro-sections.** Changelogs organized by topic
(e.g., "-- Alert Delivery --", "-- Attack Pool --", "-- Watch Mode --",
"-- pkg_lib Integration --") instead of by change type are the #1 noise
source. When detected:

1. Flag the total section count and list all section headers
2. Propose consolidation into the standard 3-5 sections
3. Re-sort entries by tag ([New] → New Features, [Fix] → Bug Fixes, etc.)
4. Apply all other dedup rules AFTER restructuring

**Anti-pattern: New Features buried.** New Features must be the FIRST section.
If it appears after other sections, flag immediately.

**Anti-pattern: duplicate sections.** Multiple sections with the same tag type
(e.g., "-- Fixes --" and "-- SMTP Relay Fixes --" and "-- UAT Fixes --")
must be collapsed into one "-- Bug Fixes --" section.

### 8. First-release consolidation

For the FIRST release of a major version (e.g., 2.0.1), apply stricter
condensation:

- Fold `[Change]` tags that refine a `[New]` feature into the parent `[New]`
  entry — "improved rotation handling" is misleading when rotation itself is new
- Multiple entries describing iterative development of the same feature
  (add → fix → refine → test) should become one `[New]` entry
- Preserve distinct `[New]` entries for genuinely independent user-facing features

### 9. Cross-reference (OPT-IN — skip by default)

Cross-referencing is expensive (reads full branch git log). **Skip this step
unless the user passes `--full` or explicitly requests cross-reference.**

When enabled:
- **Orphaned entries**: changelog entry with no matching `git log` commit
- **Missing entries**: `git log` commit with behavioral change but no changelog entry
- Scope git log to branch commits only: `git log --oneline $(git merge-base HEAD master)..HEAD`

## CHANGELOG.RELEASE section structure

CHANGELOG.RELEASE entries MUST be organized into categorical sections using
this header format:

```
- VERSION | DATE:

  -- New Features --

[New] entries here...

  -- Bug Fixes --

[Fix] entries here...

  -- Changes --

[Change] entries here...
```

**Section rules:**
- Only include sections that have entries (skip empty sections)
- Section order: New Features → Bug Fixes → Changes
- Each `[New]` entry goes under New Features, `[Fix]` under Bug Fixes,
  `[Change]` under Changes
- Entries with mixed semantics: use the dominant tag (see tag priority below)
- **Documentation, Test Suite** — optional additional sections; use only when
  there are 3+ standalone entries that don't naturally group under the main
  sections. Prefer folding doc/test entries into their parent feature entries.
- Section headers are indented 2 spaces with `--` delimiters
- **Maximum 5 sections total** — if you have more, collapse

If CHANGELOG.RELEASE is missing section headers or has topical micro-sections,
report it and propose the restructured version in the output.

## Target entry counts

Use these as rough guidelines for a healthy changelog. A release with
300+ commits should NOT have 120+ changelog entries — that's a commit log,
not a changelog.

| Release size | Target entries | Max entries |
|-------------|---------------|-------------|
| Small (< 50 commits) | 10-20 | 30 |
| Medium (50-150 commits) | 20-40 | 60 |
| Large (150-300+ commits) | 35-70 | 90 |

If the current entry count exceeds the max for its release size, be more
aggressive with merging, internal-only dropping, and verbose condensation.

## Process

1. Scope to current branch version (see Scoping section — single Bash call,
   targeted reads with offset/limit)
2. **Check section structure first** (rule 7) — flag proliferation immediately
3. **Strip tracking artifacts** (rule 1) — count removals
4. Parse every entry: tag, description, continuation lines
5. **Identify internal-only entries** (rule 5) — propose drops/folds
6. **Identify and flag fluff** (rule 2) — propose drops/merges
7. Group remaining entries by topic (feature area, function, subsystem)
8. Within each group, apply duplicate/overlap/verbose rules (3-6)
9. **If first release:** apply first-release consolidation (rule 8)
10. **If `--full` or user requested:** cross-reference against branch git log
    for orphaned/missing (rule 9). Otherwise skip.
11. Check entry count against target table
12. Compare CHANGELOG block vs CHANGELOG.RELEASE for drift

## Output

```
## CHANGELOG Dedup: v<version>

Entries scanned: <N>
Tracking artifacts stripped: <N>
Section structure: <ok / N sections (max 5) — proposed below>
Entry count: <N> (target: <T> for <size> release)
CHANGELOG vs CHANGELOG.RELEASE: <match / N differences>

### Section proliferation (if > 5 sections)
Current sections: <list all headers>
Proposed: New Features, Bug Fixes, Changes [, Documentation, Test Suite]

### Internal-only entries (<N> to drop, <M> to fold)
<for each:>
  L<nn>: [Tag] <entry>
  Action: DROP / FOLD into L<mm>
  Reason: <brief reason>

### Fluff entries (<N> to drop, <M> to merge)
<for each:>
  L<nn>: [Tag] <entry>
  Action: DROP / MERGE with L<mm>
  Reason: <brief reason>

### Duplicates (<N>)
<for each: line numbers + both entries + recommended action (keep/drop)>

### Merge candidates (<N> groups, <M> entries → <K> merged)
<for each group:>
  Group: <topic>
  Entries:
    L<nn>: [Tag] original entry 1
    L<nn>: [Tag] original entry 2
    ...
  Proposed merge:
    [Tag] condensed single entry

### Verbose entries (<N>)
<for each:>
  L<nn>: [Tag] <original>
  Suggested: [Tag] <shortened>

### Tag mismatches (<N>)
<entries where tag doesn't match the change type>

### Orphaned entries (<N>) — only with --full
<entries with no matching commit>

### Missing entries (<N>) — only with --full
<commits with no changelog entry>
```

If no issues found: `CHANGELOG v<version> is clean — <N> entries, no issues.`

## Rules
- Only examine the current branch version block — ignore history
- Do NOT modify files unless the user explicitly says to fix/apply
- Strip tracking artifacts silently — they are never user-facing
- Proposed merges must preserve all factual content meaningful to a reader
- When merging, keep the most specific tag ([Fix] wins over [Change] if a
  bug was fixed, [New] wins if the feature didn't exist before)
- Continuation lines (indented 6 spaces) belong to the entry above them
- CHANGELOG.RELEASE gets section breakout; CHANGELOG follows project convention
- Changelogs should be readable by someone with no knowledge of the
  development process — no internal references, no phase tracking, no
  audit finding codes, no internal function names unless the function IS
  the user-facing interface (e.g., `eout()` is user-facing, `_log_drop()` is not)
- The sysadmin test: for every entry, ask "would a sysadmin upgrading this
  software understand and care about this?" If no, drop or fold it.
