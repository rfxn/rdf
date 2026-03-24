# /r-util-test-scope — Test Scope Recommendation

Analyze the current diff to recommend which tests to run and map
changed functions to their test files. Combines test tier selection
with function-to-test impact analysis. Read-only — does not execute
tests.

## Arguments

`$ARGUMENTS` — optional:
- No args: analyze `git diff` (staged + unstaged)
- Function name(s): analyze those specific functions
- `--full`: show full impact matrix (not just summary)

## Protocol

### Part 1: Test Tier Selection

#### 1.1 Classify Change Scope

Run `git diff --name-only` and `git diff --cached --name-only` to
get all modified files. Categorize each file:

| Category | File Patterns |
|----------|--------------|
| DOCS | README.md, CHANGELOG*, *.md, man/*, docs/* |
| CONFIG | conf.*, internals.conf, compat.conf, .ca.def |
| CORE | functions*, *.lib.sh, main entry point internals |
| CLI | main entry point case dispatcher, help/usage |
| INSTALL | install.sh, uninstall.sh, importconf, cron* |
| TEST | tests/*.bats, tests/helpers/*, Makefile |
| CI | .github/*, Dockerfile*, run-tests.sh |

#### 1.2 Determine Test Tier

Based on the highest-impact category in the diff:

**Tier 0 — Lint only** (DOCS only, no code changes)
```bash
bash -n <project shell files>
shellcheck <project shell files>
```

**Tier 1 — Primary OS** (CONFIG, CLI, single-file CORE)
```bash
make -C tests test          # Debian 12
```

**Tier 2 — Primary + RHEL** (multi-file CORE, INSTALL, compat)
```bash
make -C tests test           # Debian 12
make -C tests test-rocky9    # Rocky 9
```

**Tier 3 — Full matrix** (CI changes, Dockerfile, cross-OS logic)
```bash
make -C tests test-all
```

**Tier 4 — Full matrix + deep legacy** (bash 4.1 floor changes,
iptables-legacy, vault repos)
```bash
make -C tests test-all
make -C tests test-deep-legacy
```

### Part 2: Function Impact Analysis

#### 2.1 Identify Changed Functions

If `$ARGUMENTS` provides function names, use those.

Otherwise extract from `git diff HEAD`:
- Functions added or modified (grep for `function ` and `() {`)
- Functions whose body was modified (changed lines within a function
  block — use diff context to identify enclosing function)

If no functions found, skip Part 2.

#### 2.2 Search Test Files

For each function name, search `tests/*.bats` for:

1. **Direct calls**: `grep -l "function_name" tests/*.bats`
2. **Setup helpers**: functions called in `setup()` that invoke target
3. **Config variables**: if function reads a config var, find tests
   that set that variable
4. **Assertions on output**: tests that grep for output strings the
   function produces

#### 2.3 Rank Relevance

Score each test file match:
- **Direct call in @test block**: HIGH (3 points)
- **Called via setup/helper**: MEDIUM (2 points)
- **Config variable reference**: LOW (1 point)
- **Output string match**: LOW (1 point)

### Part 3: Output

```
## Test Scope: {project} ({branch})

Files changed: {N} ({categories})
Tier: {0-4} — {rationale}

### Recommended Commands
{exact make/run-tests commands to execute}

### Function Impact ({N} functions changed)

| Function | Test File | Relevance | Match |
|----------|-----------|-----------|-------|
| func_a | 05-quarantine.bats | HIGH | direct (L42) |
| func_a | 12-reporting.bats | LOW | output match |
| func_b | 03-scanning.bats | HIGH | direct (L18) |

### Targeted Run (faster)
{specific test files that cover changed functions}

```bash
# HIGH relevance only
bats tests/05-quarantine.bats tests/03-scanning.bats

# All relevance levels
make -C tests test
```

### Untested Functions
{functions with ZERO test file matches — coverage gap}

### Skip Rationale (Tier 0 only)
{why tests aren't needed for this change}
```

## Rules
- Do NOT execute tests — only recommend what to run
- If in doubt between tiers, recommend the higher tier
- If no tests/ directory exists, report it and suggest lint only
- Report untested functions separately as coverage gaps
- If >10 test files match, suggest running full suite instead
- Account for project CLAUDE.md test preferences if present
- For bash projects: always include `bash -n` + `shellcheck` in
  every tier (they're fast and catch syntax errors)
