# Comment Discipline — Reference

> Expanded taxonomy supporting the Code Comments rule in
> `governance-template.md`. This is reference material: engineers
> and reviewers consult it when they need concrete examples or
> want to understand *why* the rule exists. It is not enforcement
> text -- the enforcement primitive lives in governance.

## Why This Rule Exists

Comment cruft is a first-class cost under AI-assisted development.
Three compounding problems:

### 1. Context-window tax

Every verbose function header is tokens the model re-ingests on every
edit of the file. A shared library with 70 functions, each carrying a
6-line docstring that restates its signature, burns ~420 lines of
context that contain zero information not already in the function
definition on the next line. On a long iteration session this is
thousands of tokens of pure overhead -- tokens that displace real
signal (surrounding code, related files, test output).

Terse one-line headers preserve navigation ("what does this do?")
without paying the tax.

### 2. Drift and lies

Comments that restate signatures drift on rename. The function becomes
`pkg_service_kill(name, timeout)` but the header still says
`# Arguments: $1 -- service name`. The comment now lies. Future agents
and humans trust the comment over the code at their peril.

Comments that explain *why* do not drift the same way -- the reason a
`2>/dev/null` exists does not change when the variable name does.

### 3. Grep pollution

`grep foo_bar src/` returns the definition, the callers, *and* every
comment mentioning `foo_bar`. After a rename, stale comments become
permanent grep noise. A file with heavy signature restatement typically
doubles the hit count for every identifier search, and the ratio gets
worse over time as the code evolves and comments drift.

## The Core Rule

> If the next line of code already names a parameter, a comment
> describing that parameter is cruft. Delete it.

This is the single highest-value enforcement primitive. It is
grep-able, mechanical, and language-agnostic.

## Per-Language Examples

### Bash (the pattern that triggered this rule)

**Cruft (delete):**
```bash
# pkg_service_restart name -- restart service now
# Arguments:
#   $1 -- service name
# Returns 0 on success, 1 on error.
pkg_service_restart() {
    local name="$1"
    ...
}
```

**Correct:**
```bash
# pkg_service_restart name -- restart service now
pkg_service_restart() {
    local name="$1"
    ...
}
```

The `Arguments:` block is restatement (next line declares `name`).
The `Returns` line is the bash default -- if it were non-obvious
(e.g., exit 2 means "not applicable"), it would earn its place.

### Python

**Cruft:**
```python
def fetch_user(user_id: int, timeout: float = 5.0) -> User:
    """Fetch a user.

    Args:
        user_id: The user ID to fetch.
        timeout: Timeout in seconds.

    Returns:
        The User object.
    """
```

**Correct:**
```python
def fetch_user(user_id: int, timeout: float = 5.0) -> User:
    """Fetch a user by ID. Raises NotFoundError if the user is
    soft-deleted -- callers expecting hard-deletes must check
    first."""
```

The typed signature tells you what `user_id` and `timeout` are.
The docstring earns its place by capturing the non-obvious
soft-delete behavior.

### Go

**Cruft:**
```go
// FetchUser fetches a user.
// Parameters:
//   userID - the user ID
//   timeout - timeout in seconds
// Returns the user and any error.
func FetchUser(userID int, timeout time.Duration) (*User, error) {
```

**Correct:**
```go
// FetchUser returns the user record, or ErrSoftDeleted if the
// account is pending hard-delete.
func FetchUser(userID int, timeout time.Duration) (*User, error) {
```

### TypeScript

**Cruft:**
```ts
/**
 * Fetch a user.
 * @param userId - The user ID
 * @param timeout - Timeout in ms
 * @returns The user
 */
async function fetchUser(userId: number, timeout: number): Promise<User> {
```

**Correct:**
```ts
/** Throws RateLimitError after 3 failures in a 60s window. */
async function fetchUser(userId: number, timeout: number): Promise<User> {
```

## Load-Bearing Comments (Keep These)

Comments worth their weight share one trait: they capture knowledge
the reader cannot derive from the code.

| Category | Example |
|---|---|
| Platform quirk | `# FreeBSD uses stat -f; GNU stat uses -c` |
| Language gotcha | `# read exits 1 on EOF -- not an error here` |
| Suppression justification | `2>/dev/null  # safe: dangling-symlink race` |
| Ticket / CVE reference | `# CVE-2023-XXXX: sanitize before eval` |
| Non-obvious invariant | `# caller holds flock on $lockfile -- do NOT re-acquire` |
| Compat floor | `# bash 4.1: no mapfile -d, iterate instead` |
| Out-parameter contract | `# Sets global _parse_result on success; unset on failure` |
| Upstream bug reference | `# workaround for bash 4.2 ${var/pat/repl} parser bug` |

These are the comments reviewers should protect. If a sentinel pass
finds them being deleted during a cleanup, that is a regression, not
a win.

## Anti-Patterns (Delete On Sight)

### 1. Signature restatement

See examples above. Any `Arguments:` / `Parameters:` / `@param` block
immediately above code that declares the same parameters is restatement.

### 2. Prose config-variable catalogues in file headers

```bash
# ELOG_APP      -- app name (default: basename $0)
# ELOG_LEVEL    -- severity floor (default: 1)
# ELOG_FORMAT   -- classic or json (default: classic)
# ... 40 more lines ...
```

The `${ELOG_APP:-$(basename $0)}` line in the code is the source of
truth. A header catalogue drifts the instant someone adds a new
variable without updating the header. If consumers need a reference,
put it in README.md or a man page -- one source of truth.

### 3. Banner separators

```bash
###########################################################################
# Internal helpers
###########################################################################
```

Editors do not navigate by ASCII banners. A blank line separates
sections just as well and costs zero scroll.

### 4. Tombstone comments

```bash
# removed 2025-03-14: foo_bar() -- see CHANGELOG
```

`git blame` and CHANGELOG are the source of truth for history. A
tombstone in the code is a third copy that drifts.

### 5. Language-semantics explanations

```bash
# bash word-splits here because we're not quoting $*
echo $*
```

If the reader does not know bash word-splits, a comment will not
teach them. If they do, the comment is noise. The fix is to write
correct code -- quote it -- not to document incorrect code.

### 6. "What" comments

```python
i = 0  # set i to zero
count += 1  # increment count
```

Pure restatement. The reader can read.

## Enforcement Chain

The rule is enforced at three stages of the `spec -> plan -> build`
pipeline:

1. **Engineer agent** reads `governance/conventions.md` (merged from
   core profile) and writes code to the rule. No docstring headers
   above functions whose body declares the same parameters.
2. **Reviewer (sentinel, Anti-Slop pass)** flags signature restatement,
   prose catalogues, banner separators, and tombstone comments as
   anti-slop findings.
3. **Existing projects** pick up the rule the next time `/r-init --force`
   regenerates governance, or via manual edit of their project
   `CLAUDE.md`.

## Grep Patterns for Mechanical Enforcement

Bash-specific (highest-yield):

```bash
# Find multi-line # Arguments: blocks above functions
awk '/^# Arguments:/{n++} END{print n" multi-line arg headers"}' files/*.sh

# Find prose catalogue blocks (10+ consecutive comment lines in first 100 lines)
awk 'NR<=100 && /^#/ {n++; if(n>10) print FILENAME; next} {n=0}' files/*.sh

# Find banner separators
grep -n '^#[#=_-]\{10,\}' files/*.sh
```

Language-agnostic scan (ratio of signature restatement to real comments)
is harder to automate -- this is where the reviewer Anti-Slop pass does
the work humans cannot.
