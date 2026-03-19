# Test Infrastructure Reference

> Reference for systems-engineering profile. BATS test framework and
> batsman submodule conventions.

## Framework

All rfxn projects use BATS (Bash Automated Testing System) via the
batsman submodule at `tests/infra/`.

**batsman version:** 1.2.0 (submodule, pinned per-project)

## Directory Layout

```
tests/
├── infra/              # batsman submodule
│   ├── bats/           # BATS core
│   ├── libs/           # Helper libraries
│   └── Makefile        # Test targets
├── *.bats              # Test files
├── fixtures/           # Test data
└── Makefile            # Project test targets
```

## Running Tests

```bash
make -C tests test              # Default OS (Debian 12)
make -C tests test-rocky9       # Rocky 9
make -C tests test-all          # Full OS matrix
```

## UAT Tests

UAT tests run in Docker containers against installed tools.
- Separate from unit/integration tests
- Docker images built per OS target
- 19 UAT helpers in batsman
- Test files: `tests/uat-*.bats`

## Test Counts (verify from source)

```bash
grep -rc '@test' tests/*.bats | awk -F: '{s+=$2}END{print s}'
```

## Key Conventions

- `mktemp -d` for test isolation — never scan `/tmp` or `/var`
- `run bash -c '...'` for injection testing
- Exit code assertions: `[ "$status" -ne 1 ]` for error-absent checks
- Clean logs between tests to avoid false passes from stale matches
