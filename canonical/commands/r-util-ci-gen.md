Generate a GitHub Actions CI workflow from the project's test
infrastructure. Creates workflow files for user review — does NOT commit.

## Arguments
- `$ARGUMENTS` — optional: `--update` to update existing workflow

## Setup

Read `.claude/governance/index.md` to identify:
- Project name and root directory
- Test infrastructure details (from governance/verification.md)
- Target OS matrix (from governance/reference/ if available)

## Procedure

### 1. Detect test infrastructure

Scan the project for:

**Test framework:**
- Check for test submodule (e.g., `tests/infra/`)
- Read version file if present
- Identify test runner (BATS, pytest, jest, etc.)

**Build/run targets:**
- Read `tests/Makefile` or equivalent
- Extract available targets and their OS mappings
- Identify Docker image names and Dockerfile paths

**Dockerfile variants:**
- Scan `tests/` for `Dockerfile*` files
- Map each to its OS target
- Extract base images and required packages

**Test files:**
- Count test files and estimate test count

### 2. Generate workflow

Create `.github/workflows/ci.yml` with:
- Lint job (syntax check + linter appropriate to language)
- Primary test job (default OS target)
- Secondary test jobs (additional OS targets from infrastructure)
- Conditional matrix job for full OS coverage (manual dispatch)

Use `actions/checkout@v4` with `submodules: recursive` if submodules
detected. Pin action versions to specific tags. Include proper
permissions block (principle of least privilege).

### 3. Handle --update flag

If `--update` is specified:
- Read existing `.github/workflows/ci.yml`
- Compare detected infrastructure against existing workflow
- Show diff of proposed changes
- Update with new targets while preserving custom additions

### 4. Report

    # CI Setup — <project>

    ## Detected Infrastructure
    - Test framework: <name> v<version>
    - Build targets: <list>
    - Dockerfiles: <count> (<OS list>)
    - Test files: <count>
    - Estimated tests: <count>

    ## Generated
    - `.github/workflows/ci.yml`

    ## Next Steps
    1. Review the generated workflow
    2. Test locally if possible
    3. Commit when satisfied

## Rules
- Does NOT commit — generates files for user review only
- Does NOT push — leave that to the user
- Create `.github/workflows/` directory if it doesn't exist
- If workflow already exists and `--update` not specified, warn and ask
  before overwriting
- Pin action versions to specific tags, not `@main` or `@latest`
- Include proper permissions block (principle of least privilege)
