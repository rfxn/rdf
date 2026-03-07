Generate a GitHub Actions CI workflow from the project's batsman test
infrastructure. Creates workflow files for user review — does NOT commit.

`$ARGUMENTS` determines behavior:

- **`<project>`** — generate CI workflow for the specified project
- **`<project> --update`** — update an existing workflow to match current infra

---

## Project Alias Table

| Alias       | Directory                                        |
|-------------|--------------------------------------------------|
| `apf`       | `/root/admin/work/proj/advanced-policy-firewall` |
| `bfd`       | `/root/admin/work/proj/brute-force-detection`    |
| `lmd`       | `/root/admin/work/proj/linux-malware-detect`     |
| `tlog_lib`  | `/root/admin/work/proj/tlog_lib`                 |
| `alert_lib` | `/root/admin/work/proj/alert_lib`                |
| `elog_lib`  | `/root/admin/work/proj/elog_lib`                 |
| `pkg_lib`   | `/root/admin/work/proj/pkg_lib`                  |
| `batsman`   | `/root/admin/work/proj/batsman`                  |

---

## Procedure

### 1. Detect test infrastructure

Switch to the project directory and scan:

**Batsman submodule:**
- Check `tests/infra/` for batsman submodule
- Read `tests/infra/VERSION` for batsman version
- If no batsman submodule: warn and offer basic workflow generation

**Makefile targets:**
- Read `tests/Makefile`
- Extract available targets: `test`, `test-rocky9`, `test-all`, `test-all-parallel`
- Identify Docker image names and Dockerfile paths

**Dockerfile variants:**
- Scan `tests/` for `Dockerfile*` files
- Map each to its OS target (debian12, rocky9, centos7, ubuntu2404, etc.)
- Extract base images and required packages

**Test files:**
- Count `.bats` files in `tests/`
- Estimate test count from `@test` annotations

### 2. Generate workflow

Create `.github/workflows/ci.yml` with:

```yaml
name: CI — <project>

on:
  push:
    branches: [master, main, '<version-branch-pattern>']
  pull_request:
    branches: [master, main]

permissions:
  contents: read

jobs:
  lint:
    name: Lint
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          submodules: recursive
      - name: bash -n
        run: |
          for f in <shell-files>; do
            bash -n "$f" || exit 1
          done
      - name: shellcheck
        run: |
          sudo apt-get install -y shellcheck
          shellcheck <shell-files>

  test-primary:
    name: Test (Debian 12)
    needs: lint
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          submodules: recursive
      - name: Run tests
        run: make -C tests test

  test-rocky9:
    name: Test (Rocky 9)
    needs: lint
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          submodules: recursive
      - name: Run tests
        run: make -C tests test-rocky9
```

**Conditional additions:**
- If `test-all` target exists, add a `test-matrix` job for full OS coverage
- If project has multiple Dockerfile variants, generate matrix strategy
- Add `test-all-parallel` as a manual workflow dispatch option

### 3. Handle --update flag

If `--update` is specified:
- Read existing `.github/workflows/ci.yml`
- Compare detected infrastructure against existing workflow
- Show diff of proposed changes
- Update the file with new targets/images while preserving custom additions

### 4. Report

```
# CI Setup — <project>

## Detected Infrastructure
- Batsman: v<version> (submodule at tests/infra/)
- Makefile targets: <list>
- Dockerfiles: <count> (<OS list>)
- Test files: <count> (.bats files)
- Estimated tests: <count>

## Generated
- `.github/workflows/ci.yml`

## Workflow Jobs
| Job            | OS         | Trigger    |
|----------------|------------|------------|
| lint           | ubuntu     | push, PR   |
| test-primary   | debian-12  | push, PR   |
| test-rocky9    | rocky-9    | push, PR   |
| test-matrix    | all OS     | manual     |

## Next Steps
1. Review the generated workflow: `cat .github/workflows/ci.yml`
2. Test locally: `act -j lint` (if act is installed)
3. Commit when satisfied: `/se "commit CI workflow"`
```

---

## Rules

- **Does NOT commit** — generates files for user review only
- **Does NOT push** — leave that to the user
- Create `.github/workflows/` directory if it doesn't exist
- If `.github/workflows/ci.yml` already exists and `--update` not specified,
  warn and ask before overwriting
- Use `actions/checkout@v4` with `submodules: recursive` (batsman is a submodule)
- Pin action versions to specific tags, not `@main` or `@latest`
- Include proper permissions block (principle of least privilege)
