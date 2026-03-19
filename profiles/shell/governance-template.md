# Systems Engineering Governance Template

> Seed template for /r:init. Provides shell/bash project conventions
> for merging with codebase scan results. Requires core profile.

## Shell Standards

- Shebang: `#!/bin/bash` or `#!/usr/bin/env bash` (project-specific)
- Use `$()` not backticks; `$(())` not `$[]`; `local` for function vars
- Double-quote all variables in command context
- `grep -E` not `egrep`; `command -v` not `which`; `mktemp` not `$RANDOM`/`$$`
- `while IFS= read -r line` -- never `for x in $(cat file)`
- Store regex in variables for `[[ =~ ]]` matching
- No `|| true` or `2>/dev/null` without an inline comment
- `cd` always guarded with `|| exit 1` / `|| return 1`
- cp/mv/rm: use `command cp` in project source, never bare or backslash bypass
- Background subshells inside `$()`: always redirect `( ... ) >/dev/null 2>&1 &`

## Bash Compatibility

- Floor: bash 4.1 (CentOS 6)
- Prohibited: `${var,,}`, `mapfile -d`, `declare -n`, `$EPOCHSECONDS`
- No `declare -A` for global state (breaks when sourced from functions)
- bash 4.x `${var/pat/repl}` trap: store replacement in variable

## Binary Discovery

- All paths via `command -v` at runtime, stored in variables
- Never hardcode `/sbin/`, `/usr/bin/`, or install paths

## AWK Compatibility

- mawk-compatible: no `gensub()`, `strftime()`, `mktime()`, `systime()`,
  multi-dimensional arrays, `length(array)`, `asort()`

## Portability Targets

- CentOS 6/7, Rocky 8/9, Ubuntu 20.04/24.04, Debian 12
- Gentoo, Slackware, FreeBSD (partial)
- See reference/os-compat.md for full matrix

## Testing

- BATS framework via batsman submodule at tests/infra/
- Always tee output: `make -C tests test 2>&1 | tee /tmp/test.log`
- Test isolation: `mktemp -d`, never scan /tmp or /var
- See reference/test-infra.md for framework details

## Verification Before Commit

- `bash -n` and `shellcheck` on all changed shell files
- Grep checks: bare cp/mv/rm, hardcoded paths, backticks,
  `local var=$(...)`, unguarded cd, `|| true` without comment
- See reference/audit-pipeline.md for full audit pipeline

## Code Quality

- Search for existing helpers before writing new logic
- Extract parameterized helpers instead of copy-pasting
- Remove dead code during related work
- Fix bugs at the source function, not in every consumer
- Validate file paths at caller, guard at callee
