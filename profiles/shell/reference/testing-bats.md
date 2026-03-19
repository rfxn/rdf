# BATS Testing Reference

> Deep reference for the Bash Automated Testing System (BATS). Covers
> test structure, assertions, isolation patterns, common pitfalls, and
> advanced usage.

---

## Test Structure

A BATS test file is a bash script with `@test` blocks. Each block runs
in its own subshell with automatic pass/fail based on exit code.

```bash
setup() {
    # Runs before EVERY test -- create fixtures, set variables
    TEST_DIR=$(mktemp -d)
    export MY_CONFIG="$TEST_DIR/config"
}

teardown() {
    # Runs after EVERY test, even on failure -- always clean up here
    rm -rf "$TEST_DIR"
}

@test "descriptive name of what is being tested" {
    run my_command --flag argument
    [ "$status" -eq 0 ]
    [[ "$output" == *"expected substring"* ]]
}
```

The `run` command captures a command's exit code in `$status`, its
combined stdout/stderr in `$output`, and individual lines in the
`$lines` array. Without `run`, a non-zero exit code fails the test
immediately.

---

## Assertions

Common assertion patterns using BATS built-in variables:

```bash
# Exit code checks
[ "$status" -eq 0 ]            # success
[ "$status" -ne 0 ]            # any failure
[ "$status" -eq 2 ]            # specific exit code

# Output content
[[ "$output" == *"expected"* ]]        # substring match
[[ "$output" =~ regex_pattern ]]       # regex match
[[ "${lines[0]}" == "first line" ]]    # specific line

# Line count
[ "${#lines[@]}" -eq 5 ]       # exactly 5 lines of output

# Negation
[[ "$output" != *"error"* ]]   # must NOT contain string

# File-based assertions
[ -f "$TEST_DIR/created_file" ]        # file exists
[ -s "$TEST_DIR/created_file" ]        # file exists and is non-empty
[ ! -f "$TEST_DIR/removed_file" ]      # file does not exist
```

For richer assertions, load `bats-assert` and `bats-support`:
```bash
load 'bats-support/load'
load 'bats-assert/load'

@test "using bats-assert" {
    run my_command
    assert_success
    assert_output --partial "expected text"
    refute_output --partial "unwanted text"
    assert_line --index 0 "first line exactly"
}
```

---

## Fixtures and Isolation

Tests must never depend on or pollute shared state. Use `mktemp -d` for
all temporary files and directories.

```bash
setup() {
    TEST_DIR=$(mktemp -d)
    # Create fixture files
    echo "test data" > "$TEST_DIR/input.txt"
    mkdir -p "$TEST_DIR/subdir"
}

teardown() {
    rm -rf "$TEST_DIR"
}
```

Never scan shared directories (`/tmp`, `/var`, `/home`) in tests. They
contain unpredictable content from other processes, test runs, and
build artifacts. Always create isolated directories.

Skip tests when prerequisites are missing:
```bash
@test "requires root" {
    [ "$EUID" -eq 0 ] || skip "requires root privileges"
    run privileged_command
    [ "$status" -eq 0 ]
}

@test "requires network" {
    command -v curl >/dev/null || skip "curl not available"
    run curl -sf http://example.com
    [ "$status" -eq 0 ]
}
```

Load shared helpers with the `load` command:
```bash
load 'test_helper'       # loads test_helper.bash from same directory
load 'lib/common'        # loads lib/common.bash relative to test file
```

---

## Common Pitfalls

### run uses eval

Shell metacharacters in `run` arguments expand before the command
starts. This causes hangs or unintended execution when testing
injection scenarios.

```bash
# Bad: $() expands prematurely, may hang or execute
run my_command "$(malicious_payload)"

# Good: use run bash -c to defer expansion
run bash -c 'my_command "$(malicious_payload)"'
```

### Pipe-only output loss

Piping test output without `tee` discards details on failure, forcing
a full re-run to diagnose.

```bash
# Bad: failure details lost
bats tests/*.bats | tail -5

# Good: capture everything, show summary
bats tests/*.bats 2>&1 | tee /tmp/test.log
grep "not ok" /tmp/test.log
```

### Shared state leaks

Variables and files from one test can leak into subsequent tests if
cleanup is incomplete. Always use `teardown` for cleanup (it runs even
on assertion failure, unlike inline cleanup).

```bash
# Bad: cleanup skipped if assertion fails
@test "inline cleanup fails" {
    mkdir /tmp/test_dir
    run my_command
    [ "$status" -eq 0 ]
    rm -rf /tmp/test_dir      # never reached on failure
}

# Good: teardown always runs
teardown() { rm -rf "$TEST_DIR"; }
```

### Stale log matches

Log files accumulate across tests. A match from a prior test causes a
false pass in a later test.

```bash
setup() {
    TEST_DIR=$(mktemp -d)
    export LOG_FILE="$TEST_DIR/app.log"
    : > "$LOG_FILE"           # truncate between tests
}
```

---

## Advanced Patterns

### Parallel execution

BATS supports parallel test execution with `--jobs`:
```bash
bats --jobs 4 tests/*.bats
```

Parallel tests must be fully isolated -- no shared files, no shared
ports, no shared environment variables modified at runtime.

### Custom helpers

Create reusable assertion functions in helper files:
```bash
# test_helper.bash
assert_file_contains() {
    local file="$1" expected="$2"
    if ! grep -qF "$expected" "$file"; then
        echo "Expected '$file' to contain: $expected" >&2
        echo "Actual contents:" >&2
        cat "$file" >&2
        return 1
    fi
}
```

### Setup/teardown scoping

`setup_file` and `teardown_file` run once per file (not per test),
useful for expensive one-time setup:
```bash
setup_file() {
    export SHARED_FIXTURE=$(mktemp -d)
    build_expensive_fixture "$SHARED_FIXTURE"
}

teardown_file() {
    rm -rf "$SHARED_FIXTURE"
}
```

### Testing exit-on-error scripts

Scripts with `set -e` exit immediately on failure, which is correct
behavior but makes fine-grained assertions difficult. Use `run` to
capture the exit:
```bash
@test "script exits on bad input" {
    run bash my_script.sh --invalid-flag
    [ "$status" -ne 0 ]
    [[ "$output" == *"usage"* ]]
}
```
