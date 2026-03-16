# Systems Engineering Governance

> RDF systems-engineering profile — conventions for bash/shell project
> development across the rfxn ecosystem (APF, BFD, LMD, shared libraries).
> Requires the core profile.

---

## Shell Standards

- Shebang: `#!/bin/bash` (APF/BFD) or `#!/usr/bin/env bash` (LMD)
- Use `$()` not backticks; `$(())` not `$[]`; `local` for function-scoped variables
- Double-quote all variables in command context
- `grep -E` not `egrep`; `command -v` not `which`; `mktemp` not `$RANDOM`/`$$`
- `while IFS= read -r line` — never `for x in $(cat file)`
- Store regex in variables for `[[ =~ ]]` matching
- No `|| true` or `2>/dev/null` without an inline comment explaining why the error is safe to ignore
- Background subshells inside `$()` callers: always redirect `( ... ) >/dev/null 2>&1 &` — inheriting the pipe causes the caller to hang indefinitely
- **cp/mv/rm alias safety** — bare `cp`/`mv`/`rm` hang in non-interactive contexts because `~/.bashrc` aliases them to `-i`. Three contexts, three rules:
  - **Bash tool calls** (agent/Claude context): use `/usr/bin/cp`, `/usr/bin/mv`, `/usr/bin/rm`
  - **Project source code** (ships to target OSes): use `command cp`, `command mv`, `command rm` — bypasses aliases via PATH portably (pre-usr-merge distros lack `/usr/bin/`)
  - **BATS test files** (`.bats`): use bare `rm`/`cp`/`mv` — Docker containers have no alias, and CentOS 6 has coreutils at `/bin/` not `/usr/bin/`. Never use `/usr/bin/rm` in tests
  - **Prohibited everywhere**: backslash bypass (`\cp`/`\rm`/`\mv` — fragile, not portable across shells)
- `cd "$dir"` without `|| exit 1` or `|| return 1` is a latent bug — if the directory is missing, execution continues in the wrong CWD. Always guard `cd` calls
- Never assign `"$@"` to a scalar — `args="$@"` collapses with IFS. Use `"$*"` for a space-joined string, or `args=("$@")` for array semantics
- **Tar flag ordering:** `tar xfz --flag` makes `f` consume `--flag` as the archive filename. Always place long flags before positional options: `tar --flag -xzf "$archive"`. Note: `--no-absolute-names` is NOT a valid GNU tar flag — tar strips absolute paths by default; `-P` preserves them
- Shellcheck: dynamic sources use `# shellcheck disable=SC1090,SC1091`; static sources use `# shellcheck source=`; no non-ASCII after `disable=` (breaks SC1125)

### Binary Paths

All paths discovered via `command -v` in `internals.conf` and stored in variables. Never hardcode `/sbin/ip`, `/etc/apf`, install paths, etc. Use `$inspath` for the install prefix.

### Bash 4.1+ Floor (CentOS 6)

Prohibited: `${var,,}`, `mapfile -d`, `declare -n`, `$EPOCHSECONDS`. Never use `declare -A` for global state — creates locals when sourced from inside functions (BATS `load`). Use parallel indexed arrays instead.

**bash 4.x `${var/pat/repl}` trap:** On bash 4.2 (CentOS 7), `${var/YARA./{YARA\}}` outputs `{YARA\}` with a literal backslash. The `}` in the replacement confuses the parser. Fix: store the replacement in a variable: `rep="{YARA}"; result="${var/YARA./$rep}"`. Fixed in bash 5.x.

### AWK (BFD only)

mawk-compatible: no `gensub()`, `strftime()`, `mktime()`, `systime()`, multi-dimensional arrays, `length(array)`, `asort()`

---

## Code Quality

- Search for existing helpers before writing new logic — call them, don't re-implement
- Extract parameterized helpers instead of copy-pasting blocks with different variable names
- Remove dead code encountered during related work — don't defer it
- Fix bugs at the source function, not in every consumer
- When fixing one failure mode, grep the entire codebase for the same pattern — fix the class
- Validate file path arguments at the caller and guard at the callee; never pass empty or unvalidated paths
- New file artifacts (`.html`, `.json`, metadata) need absence handling in upgrade paths — prior versions never created them
- Never implement an audit finding without verifying it against actual code — check for false positives

### Guiding Principles

**Lint Is Necessary, Not Sufficient** — `bash -n` and shellcheck catch syntax errors
and known anti-patterns. They cannot detect semantic incorrectness, silent
wrong-output, empty-path propagation, IFS state contamination, or bash 4.1 compat
violations. Treat lint-passing as a floor, not a ceiling.

**Trust Is Earned with Evidence, Not Claims** — SE self-review is not a substitute
for independent verification. QA must independently verify correctness-critical
properties (test execution, bash 4.1 compliance) regardless of SE's stated results.
Every DONE item in a self-review must include one-line evidence.

**Adversarial Inputs Are Required Before Merge** — At minimum one adversarial
challenge must occur per tier 2+ change: pre-implementation (Challenger agent) and
post-implementation (Sentinel agent). This is not punitive — it is the difference
between "code that works on my test input" and "code that works on inputs we haven't
thought of yet."

**Regression Is a First-Class Concern** — Every change that modifies existing
behavior must include a regression scenario that verifies the pre-existing behavior
still holds. This is separate from new feature tests. It belongs in the test suite,
not just in QA's head.

**Challenges Must Be Responded To** — When a challenge agent (Challenger, Sentinel)
raises a concern, SE must respond: either fix the issue or document why it is not a
real concern with evidence. Silence is not acceptable. QA validates that SE responded.

**CLI Operations Must Be Symmetric** — Every input form accepted by an add/create
operation (`-d`, `-a`, `-td`, `-ta`) must also be accepted by the corresponding
remove operation (`-u`). When extending a validation gate (e.g., `valid_host()`,
`valid_trust_entry()`) to accept a new input class on the add path, verify the
remove path has the same gate extension. Test with a roundtrip: add via CLI, then
remove the same string via CLI, assert both succeed and state is clean. This applies
to any paired operation, not just trust commands.

---

## CLI (FROZEN)

Existing case-statement arguments must NOT be modified. New options may be added.
- APF: `files/apf` | LMD: `files/maldet` | BFD: `files/bfd`

---

## Portability

**OS targets:** CentOS 6, CentOS 7, Rocky 8, Rocky 9, Ubuntu 20.04, Ubuntu 24.04, Debian 12, Gentoo, Slackware, FreeBSD (LMD partial)

Key pitfalls:
- **usr-merge:** CentOS 6 (and historical Ubuntu 12.04) have NOT undergone the `/usr` merge — coreutils (`rm`, `mv`, `cp`, `cat`, `chmod`, etc.) live at `/bin/`, not `/usr/bin/`. Modern distros (Rocky 8+, Ubuntu 20+, Debian 12) have `/usr/bin/`. Never hardcode either path in source code — use `command <util>` for portable resolution via PATH
- **sbin split:** `/sbin/` vs `/usr/sbin/` differs across distros — discover via `command -v` at runtime
- No systemd on legacy distros (CentOS 6, Ubuntu 14.04)
- TLS gaps on deep legacy
- See `reference/os-compat.md` for full matrix

---

## Testing

All projects use BATS via batsman submodule at `tests/infra/`. See `reference/test-infra.md`.

**Commands:** `make -C tests test` (Debian 12) | `make -C tests test-rocky9` | `make -C tests test-all`

**Always tee output — never pipe-only:**
```bash
make -C tests test 2>&1 | tee /tmp/test-<project>-<os>.log | tail -30
grep "not ok" /tmp/test-<project>-<os>.log
```
Pipe-only discards failure details and forces a second full run. When running multiple phases or OS targets, include phase number in the log path (e.g., `/tmp/test-apf-P3-debian12.log`) to avoid collisions.

**When to run:**
- Full suite: new features, multi-file refactors, core logic changes
- Lint only: docs, comments, single-line fixes, changelog-only edits
- Sequence: lint → Debian 12 → Rocky 9 → full matrix for major changes only
- Wait for all target results before pushing

**Test quality:** No duplicate coverage, no tautological assertions, no expensive setup when lighter paths cover the same logic. Config-matrix features need tests for each value and for the missing-artifact case (upgrade paths encounter old-format state).

**Test isolation:** Never scan shared directories (`/tmp`, `/var`, `/home`) in tests — they contain unpredictable content (test fixtures, build artifacts). Always use `mktemp -d` for clean scan targets. For regression tests guarding against error paths, assert the error code is absent (`[ "$status" -ne 1 ]`) rather than a specific success code, when the command's output may legitimately vary.

**BATS `run` uses `eval`:** Shell metacharacters (backticks, `$()`) in `run` arguments expand before the command starts, causing hangs or unintended execution. When testing injection rejection, use `$()` syntax in the payload string, or restructure with `run bash -c '...'` to avoid premature expansion.

---

## Verification Before Commit

Applies to commits touching shell files (APF, BFD, LMD). Doc-only commits to non-shell repos (workforce/RDF) are exempt from `bash -n`/`shellcheck`.

```bash
bash -n <all-shell-files>
shellcheck <all-shell-files>
grep -rn '\bwhich\b' files/
grep -rn '\begrep\b' files/
grep -rn '`' files/              # backtick usage
grep -rn '|| true' files/        # every hit must have an inline comment on the same line
grep -rn '2>/dev/null' files/    # every hit must have an inline comment on the same line
grep -rn '^\s*cp \|^\s*mv \|^\s*rm ' files/  # bare cp/mv/rm — must use 'command' prefix
grep -rn '/usr/bin/\(rm\|mv\|cp\)' files/  # hardcoded coreutils — must use 'command rm' etc.
grep -rn '\\cp \|\\mv \|\\rm ' files/      # backslash alias bypass — use 'command' prefix
grep -rn 'local [a-z_]*=\$(' files/        # local var=$() masks exit code — declare separately
grep -rn '^\s*cd ' files/                  # every cd must have || exit/return guard
```
Also grep for hardcoded project-specific paths (binary paths, install paths) — see each project's CLAUDE.md for the exact patterns.

---

## Shared Libraries

1. All development and testing in the canonical project first — never edit a shared library inside a consuming project
2. Libraries contain zero project-specific references
3. Update the version variable on every API change
4. Use portable defaults: `VAR="${VAR:-/tmp}"` — but never use `/tmp` as a default for security-sensitive paths (keys, certs, credentials)
5. No `declare -A` for global state — breaks when sourced from functions

---

## Audit Pipeline

Full: `/audit` | Static-only: `/audit-quick` | Schema + pipeline details: `reference/audit-pipeline.md`

---

## Common Anti-Patterns

23. NEVER mark self-review items DONE without evidence — include one-line proof (grep
    output, file path, commit reference) for each category
24. NEVER trust lint-passing as proof of correctness — bash -n and shellcheck cannot
    detect Class C/D/F/G bugs; test execution and semantic review are required
25. NEVER run `local var=$(...)` without declaring separately — always returns 0
    (masks subshell exit code)
26. NEVER use `IFS=` inside a function without explicit save/restore pattern —
    IFS changes persist through the function body
27. NEVER pass a conditionally-set path variable to a function that does `< "$var"`,
    `cat "$var"`, or `base64 < "$var"` — validate non-empty or downgrade first
28. NEVER complete a refactor without grepping the full codebase for the old
    name/pattern — include grep output as REFACTOR_GREP_EVIDENCE in result file
29. NEVER trust `grep -c` exit code — it exits 1 when count is 0; use with fallback
30. NEVER use `\t` or `\n` inside `stat -c` format strings — `stat -c` does not
    interpret escape sequences (use `stat --printf` instead). `stat -c %Y` (no
    escapes) is fine
31. NEVER use bare `cp`/`mv`/`rm` or backslash bypass (`\cp`/`\rm`/`\mv`) — see
    Shell Standards §cp/mv/rm for the three-context rule (Bash tool calls →
    `/usr/bin/cp`; project source → `command cp`; BATS tests → bare `rm`).
    CI failures from wrong context: 6267a07, c247880, aa27d36
32. NEVER use `cd` without a failure guard (`|| exit 1` / `|| return 1`) — if the
    directory is missing, execution silently continues in the wrong CWD
33. NEVER assign `"$@"` to a scalar string (`args="$@"`) — it collapses with IFS.
    Use `"$*"` for a space-joined string or `args=("$@")` for array semantics
34. NEVER generate shell code (via printf/heredoc) with unquoted variables in the
    body — variables inside generated scripts must be quoted as if they were real
    shell code, even though the outer template is correctly structured
