# Shell Anti-Patterns Reference

> Deep reference for common bash/shell anti-patterns. Each section shows
> the broken pattern, explains why it fails, and provides the correct
> alternative. Companion to the shell governance template.

---

## Exit Code Masking

`local` always returns 0, silently hiding failures from subshells.

Bad:
```bash
local output=$(command_that_may_fail)
if [[ $? -ne 0 ]]; then
    echo "This branch never executes"
fi
```

`local` overwrites `$?` with its own exit code (always 0). The subshell
failure is invisible. This is the single most common source of silent
wrong-behavior in bash functions.

Good:
```bash
local output
output=$(command_that_may_fail)
if [[ $? -ne 0 ]]; then
    echo "Now this correctly detects the failure"
fi
```

Declare the variable on one line, assign on the next. The assignment's
exit code is preserved.

---

## Quoting Failures

Unquoted variables undergo word splitting and pathname expansion (globbing).

Bad:
```bash
file_list=$(ls /some/dir)
for f in $file_list; do
    rm $f
done
```

If a filename contains spaces, it splits into multiple tokens. If it
contains `*` or `?`, bash expands them as globs. An empty variable
becomes zero arguments, not an empty string.

Good:
```bash
while IFS= read -r f; do
    rm -- "$f"
done < <(find /some/dir -maxdepth 1 -type f)
```

Always double-quote variables in command position. Use `"$var"` to
preserve whitespace and prevent globbing. The `--` prevents filenames
starting with `-` from being interpreted as options.

---

## Process Management

Background subshells inside `$()` inherit the pipe and block the caller.

Bad:
```bash
result=$(
    some_command
    ( long_running_task ) &
)
# Caller hangs until long_running_task finishes
```

The background subshell inherits stdout from the command substitution.
`$()` waits for all writers on that pipe to close, so the caller blocks
indefinitely.

Good:
```bash
result=$(
    some_command
    ( long_running_task ) >/dev/null 2>&1 &
)
# Caller returns immediately
```

Redirect both stdout and stderr to `/dev/null` before backgrounding.
This detaches the subshell from the pipe so `$()` can close cleanly.

For signal handling, trap `EXIT` to clean up child processes:
```bash
cleanup() { kill "$child_pid" 2>/dev/null; wait "$child_pid" 2>/dev/null; }
trap cleanup EXIT
long_running_task &
child_pid=$!
```

---

## String Processing

The bash 4.x `${var/pat/repl}` substitution has a parser bug with braces.

Bad:
```bash
# On bash 4.2 (CentOS 7), this produces a literal backslash
result="${var/PATTERN/{REPLACEMENT\}}"
```

The `}` in the replacement string confuses the bash 4.x parser. It
tries to match it as the end of the parameter expansion, producing
`{REPLACEMENT\}` with a literal backslash. Fixed in bash 5.x.

Good:
```bash
rep="{REPLACEMENT}"
result="${var/PATTERN/$rep}"
```

Store the replacement in a variable first. The variable expansion
happens after the parameter expansion parsing is complete.

Backtick nesting is fragile and unreadable:
```bash
# Bad: nested backticks require escaping
outer=`echo \`echo inner\``

# Good: $() nests cleanly
outer=$(echo "$(echo inner)")
```

Never use `eval` with user-controlled input:
```bash
# Bad: command injection
eval "grep $user_input /etc/passwd"

# Good: pass as argument, never as code
grep -F -- "$user_input" /etc/passwd
```

---

## File Operations

Bare `cp`/`mv`/`rm` can hang in interactive contexts; hardcoded paths
break across distros.

Bad:
```bash
rm -rf /tmp/workdir
cp /usr/bin/tool /opt/dest/
```

Many systems alias `cp`/`mv`/`rm` to their `-i` (interactive) variants
in `.bashrc`. Bare invocations hang waiting for confirmation in
non-interactive scripts. Hardcoding `/usr/bin/` fails on pre-usr-merge
distros where coreutils live at `/bin/`.

Good:
```bash
command rm -rf /tmp/workdir
tool_path=$(command -v tool)
command cp "$tool_path" /opt/dest/
```

Use `command` prefix to bypass aliases via PATH. Use `command -v` for
binary discovery. Never hardcode `/usr/bin/` or `/bin/` paths.

TOCTOU (time-of-check-time-of-use) race with temp files:
```bash
# Bad: predictable name, race window
tmpfile="/tmp/myscript.$$"
echo "data" > "$tmpfile"

# Good: mktemp creates atomically with random name
tmpfile=$(mktemp /tmp/myscript.XXXXXXXX)
echo "data" > "$tmpfile"
```

Always use `mktemp` with a restrictive umask for temp files. The
`XXXXXXXX` suffix provides sufficient entropy to prevent name guessing.

---

## Control Flow

Unguarded `cd` silently continues in the wrong directory if the target
is missing.

Bad:
```bash
cd "$build_dir"
rm -rf ./*
# If cd failed, this runs in the PREVIOUS directory
```

If `$build_dir` does not exist, `cd` fails but execution continues.
The `rm -rf ./*` then operates on whatever directory the script was
previously in -- potentially catastrophic.

Good:
```bash
cd "$build_dir" || exit 1
rm -rf ./*
```

Always guard `cd` with `|| exit 1` (in scripts) or `|| return 1`
(in functions).

`set -e` does not propagate into subshells the way most expect:
```bash
# Bad: set -e does not catch this
set -e
result=$(failing_command)  # exits...
result=$(failing_command || true)  # ...but this suppresses it

# Also tricky: set -e is disabled inside conditionals
if failing_command; then  # set -e does not apply here
    echo "ok"
fi
```

`set -e` is disabled inside `if` conditions, `while` conditions, and
the left side of `&&` / `||`. Commands in those positions never trigger
`set -e` regardless of exit code. Use explicit error checking for
critical commands even when `set -e` is active.
