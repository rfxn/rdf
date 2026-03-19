Shared library release lifecycle. Handles pre-flight checks, release
preparation, and consumer drift notification.

## Arguments
- `$ARGUMENTS` — required: library name or path

## Setup

Read `.claude/governance/index.md` to identify:
- Library metadata (name, version, repository)
- Consumer projects that use this library
- Release conventions from governance

If the argument does not match a known library, treat it as a directory
path and attempt to identify it as a library project.

## Procedure

### 1. Pre-flight checks

Switch to the library directory and verify readiness. Display results
as a task list with pass/fail state:

```
### Pre-Flight — {library} v{version}

#### Branch Validation
- [x] Current branch is version branch (`{branch}`)
- [x] Working tree is clean ({N} dirty files)
- [ ] No unpushed commits ({N} ahead of `origin/{branch}`)

#### PLAN Verification
- [x] All phases *complete* ({N}/{N})
- [ ] Phase {N} — *in-progress* (STOP)
- [ ] Phase {N} — *pending* (STOP)

#### Release Readiness
- [x] Version strings consistent across files: `{version}`
- [x] No uncommitted changes
- [x] Tests pass ({N}/{N})
```

If any check fails, use a blockquote to halt:

```
> **Pre-flight FAILED** — {N} check(s) did not pass. Resolve before continuing.
```

### 2. Release preparation

If pre-flight passes, execute in sequence (stopping on any failure):

**2a. Attribution scrub**
- Scan for and remove Claude/Anthropic/AI attribution if governance
  requires it
- Report findings and fixes

**2b. Changelog cleanup**
- Run changelog deduplication (equivalent to `/r:util:chg-dedup`)
- Report changes made

**2c. User approval gate**
Present the final state as a release summary table and wait for
confirmation before proceeding:

```
#### Release Summary

| Property | Value |
|----------|-------|
| **Library** | `{name}` |
| **Version** | `{version}` |
| **Branch** | `{branch}` |
| **Commits since last release** | {N} |
| **Files changed** | {N} |
| **Attribution scrub** | *{N items removed / clean}* |
| **Changelog dedup** | *{N duplicates removed / clean}* |
```

Show `CHANGELOG.RELEASE` contents in a fenced code block, then
present the approval gate:

```
- [ ] Approve — proceed with merge and release
- [ ] Reject — return to editing
```

### 3. Merge and release

After user approval:
- Generate merge/squash commit message
- Create PR against main/master
- Report the PR URL
- Monitor CI checks if available

### 4. Consumer notification

After the release merges, run library sync check (equivalent to
`/r:util:lib-sync`) and display consumer drift as a table:

```
#### Consumer Drift

| Consumer | Local Version | Released Version | Status |
|----------|---------------|------------------|--------|
| `{project_a}` | `{old_ver}` | `{new_ver}` | *drifted* |
| `{project_b}` | `{new_ver}` | `{new_ver}` | *synced* |
```

### 5. Post-release updates

- Update project memory with new version and release status

## Rules
- NEVER auto-merge — always require user confirmation before merge
- NEVER auto-sync consumers — report drift, let user decide
- STOP immediately if any pre-flight check fails
- STOP and wait for user approval before merge step
- Follow governance commit protocol
