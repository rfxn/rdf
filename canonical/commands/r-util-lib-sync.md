Cross-project shared library drift detection. Compares canonical library
sources against all consumer copies. Report mode by default; optional
sync mode copies and verifies.

## Arguments
- `$ARGUMENTS` — optional: `--sync` to execute copy operations (default: report only)

## Setup

Read `.rdf/governance/index.md` to identify:
- Shared libraries used by this project (from governance/architecture.md
  or by scanning for library version variables)
- Canonical source locations for each library
- Consumer paths within the project

If governance does not specify library locations, fall back to scanning
for files with `_LIB_VERSION=` patterns to identify shared libraries.

## Step 1: Detect Context

- If CWD is a project directory, check only that project's library copies
- If CWD is a workspace root, check all projects under it

For each project, determine which libraries it consumes by checking for
the presence of library files.

## Step 2: Compare

For each canonical-to-consumer pair:
1. **Checksum**: `sha256sum` both files, compare
2. **Version**: Extract version variable from both and compare
3. **Status**: SYNCED (identical checksum) or DRIFTED

## Step 3: Drift Report

Display the report using structured formatting with inline code for
versions and paths, and italic for status keywords:

```
### Shared Library Sync Report

| Library | Canonical | Consumer | Local | Status |
|---------|-----------|----------|-------|--------|
| `lib_a` | `1.0.4` | `proj_x` | `1.0.4` | *synced* |
| `lib_a` | `1.0.4` | `proj_y` | `1.0.3` | *drifted* |
| `lib_b` | `2.0.1` | `proj_x` | — | *n/a* |

#### Totals

| *drifted* | *synced* | *n/a* |
|-----------|----------|-------|
| {N} | {N} | {N} |
```

For *drifted* entries, show the `diff --stat` summary in a fenced
code block.

If reverse drift is detected (consumer ahead of canonical), use a
blockquote warning:

```
> **Reverse Drift** — `{project}/{library}` is ahead of canonical.
> Local modifications may need to be upstreamed first.
```

## Step 4: Sync (only with --sync)

If `$ARGUMENTS` contains `--sync`:

For each DRIFTED library:
1. `command cp` canonical to consumer path
2. `command chmod 750` consumer path
3. Run `bash -n` on the copied file to verify syntax
4. Run `sha256sum` to confirm match
5. Report success/failure

After sync, display results as a task list:

```
#### Sync Results
- [x] `lib_a` -> `proj_y`: *synced* (`bash -n` pass, checksum verified)
- [ ] `lib_b` -> `proj_z`: *failed* (syntax error in canonical)
```

End with a blockquote:

```
> **{N} libraries synced.** Review with `git diff` before committing.
```

If `--sync` not specified, end with:

```
> Run `/r-util-lib-sync --sync` to copy drifted libraries.
```

## Rules
- NEVER edit a shared library inside a consuming project
- NEVER sync if the canonical source has syntax errors (`bash -n` check first)
- Always show the diff before syncing (in report mode)
- Skip libraries whose canonical source doesn't exist
- Warn if a consumer has local modifications not present in canonical
  (reverse drift — consumer ahead of canonical)
