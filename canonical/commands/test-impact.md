Test impact analysis: maps changed or specified functions to the BATS test
files that exercise them. Helps decide which tests to run after a change.
Do NOT modify files — report only.

## Arguments
- `$ARGUMENTS` — optional: function name(s) to analyze. If omitted, derives
  changed functions from `git diff` (staged + unstaged).

## Step 1: Identify Changed Functions

If `$ARGUMENTS` is provided, use those as the function list.

Otherwise, extract from `git diff HEAD`:
```bash
git diff HEAD --unified=0 | grep -E '^\+.*function |^\+.*\(\) \{' | \
  sed 's/.*function //; s/().*//' | sort -u
```

Also extract functions whose body was modified (changed lines within a function
block). Use `git diff HEAD` with context to identify enclosing function names.

If no functions found, report "No function changes detected." and stop.

## Step 2: Search Test Files

For each function name, search `tests/*.bats` for:
1. **Direct calls**: `grep -l "function_name" tests/*.bats`
2. **Setup helpers**: Functions called in `setup()` that invoke the target
3. **Config variables**: If the function reads a config var, find tests that
   set that variable
4. **Assertions on output**: Tests that grep for output strings the function
   produces (check `eout()` calls in the function)

## Step 3: Rank Relevance

Score each test file match:
- **Direct call in @test block**: HIGH (3 points)
- **Called via setup/helper**: MEDIUM (2 points)
- **Config variable reference**: LOW (1 point)
- **Output string match**: LOW (1 point)

## Step 4: Output

```
# Test Impact Analysis

## Changed Functions
- function_name_1 (file:line)
- function_name_2 (file:line)

## Impact Matrix

| Function | Test File | Relevance | Match Type |
|----------|-----------|-----------|------------|
| func_a   | 05-quarantine.bats | HIGH | direct call (line 42) |
| func_a   | 12-reporting.bats  | LOW  | output string match |
| func_b   | 03-scanning.bats   | HIGH | direct call (line 18) |

## Recommended Test Run
```bash
# Minimum (HIGH relevance only)
make -C tests test BATS_FILTER="quarantine|scanning"

# Full coverage (all relevance levels)
make -C tests test
```
```

## Rules

- Only search `tests/*.bats` files (not infra files)
- Report functions with ZERO test coverage separately as "Untested Functions"
- If more than 10 test files match, suggest running the full suite instead
