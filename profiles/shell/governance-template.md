# Shell Governance Template

> Seed template for /r-init. Provides bash/shell best practices for
> merging with codebase scan results. Requires core profile.
> Assumes bash 4.3+ baseline. Project-specific version floors
> (e.g., bash 4.1 for CentOS 6) detected by /r-init override these defaults.

## Code Conventions

- Shebang: `#!/bin/bash` or `#!/usr/bin/env bash` (project-specific)
- Use `$()` not backticks; `$(())` not `$[]`; `local` for function vars
- Double-quote all variables in command context
- `grep -E` not `egrep`; `command -v` not `which`; `mktemp` not `$RANDOM`/`$$`
- `while IFS= read -r line` -- never `for x in $(cat file)`
- Store regex in variables for `[[ =~ ]]` matching
- `cd` always guarded with `|| exit 1` / `|| return 1`
- cp/mv/rm: use `command` prefix in project source, never bare or
  backslash bypass (`\rm`)
- Background subshells inside `$()`: always redirect
  `( ... ) >/dev/null 2>&1 &` -- inheriting the pipe causes hangs
- Prefer `printf` over `echo` for portability (echo behavior varies)

## Anti-Patterns

- `|| true` and `2>/dev/null` without inline comment explaining why
  the error is safe to ignore
- `local var=$(...)` -- masks exit code (always returns 0); declare
  the variable separately, then assign
- `declare -A` for global state -- breaks when sourced from functions;
  use parallel indexed arrays instead
- `"$@"` assigned to scalar (`args="$@"`) -- collapses with IFS;
  use `"$*"` for space-joined string or `args=("$@")` for array
- Tar flag ordering: `tar xfz --flag` makes `f` consume `--flag` as
  filename; place long flags before positional options
- `${var/pat/repl}` with braces in replacement -- bash 4.x parser
  bug; store replacement in a variable
- Generated shell code (via printf/heredoc) with unquoted variables
  in the body -- variables must be quoted even in generated scripts
- Hardcoded binary paths (`/usr/bin/rm`, `/sbin/ip`) -- use
  `command -v` for discovery; usr-merge differs across distros
- `eval` with any user-controlled input -- command injection vector
- `for x in $(cat file)` -- word splits on whitespace AND globbing

## Error Handling

- `set -euo pipefail` in scripts (not in libraries meant to be sourced)
- Trap `EXIT` / `ERR` for cleanup (temp files, lock files, child processes)
- Exit codes: 0=success, 1=general error, 2=usage error -- document
  project-specific codes in usage/man page
- Functions that can fail: return a code, don't `exit` (let caller decide)
- Validate inputs at function entry -- empty string, missing file,
  non-integer where integer expected
- `|| true` is acceptable ONLY with inline comment on the same line

## Security

- Command injection: never interpolate untrusted input into `eval`,
  `source`, `$()`, backticks, or unquoted command position
- Path traversal: validate paths before operations, reject `../`
- Temp file races: `mktemp` with restrictive umask, never predictable
  names; symlink-safe patterns only
- SUID/privilege confusion: drop privileges early, validate `$EUID`,
  don't trust `$PATH` in privileged contexts
- Secrets in environment: restrict visibility (unexport after use),
  never log, never pass via command line (visible in /proc)
- File permissions: `umask 077` for sensitive files, check before write
- Never pass secrets as CLI arguments -- they appear in `ps` and `/proc`

## Testing

- BATS framework (or project-specific test framework detected by /r-init)
- Test isolation: `mktemp -d` for temp directories, never scan shared
  directories (`/tmp`, `/var`) -- they contain unpredictable content
- Always tee output: `cmd 2>&1 | tee /tmp/test.log` -- pipe-only
  discards failure details and forces re-runs
- Regression tests: assert error code is absent (`[ "$status" -ne 1 ]`)
  rather than a specific success code when output may vary
- BATS `run` uses `eval` -- shell metacharacters expand prematurely;
  use `$()` syntax or `run bash -c '...'` to prevent
- Cleanup in `teardown`, not inline -- survives assertion failures
- Clear log files between tests to avoid stale-match false passes

## Portability

- Binary discovery: `command -v` at runtime, store in variables
- usr-merge awareness: `/bin/` vs `/usr/bin/` differs across distros
  (CentOS 6 has NOT undergone usr-merge); never hardcode either
- sbin split: `/sbin/` vs `/usr/sbin/` -- discover, don't hardcode
- AWK: assume `mawk` unless project specifies `gawk` -- no `gensub()`,
  `strftime()`, multi-dimensional arrays, `length(array)`, `asort()`
- `stat -c` does not interpret `\t` or `\n` -- use `stat --printf`
  for escape sequences; `stat -c %Y` (no escapes) is fine
- Shell arithmetic: `$(())` not `$[]` (deprecated)
- `readlink -f` not portable to macOS/BSD -- use `realpath` or
  `cd "$(dirname "$0")" && pwd` pattern
