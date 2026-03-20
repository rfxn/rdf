Assess codebase modernization maturity and generate a phased remediation
plan. This is a **read-only assessment** — it does NOT modify any project
files.

## Arguments
- `$ARGUMENTS` — optional: project name or path (default: CWD)

## Setup

Read `.rdf/governance/index.md` to identify:
- Project name, language, and conventions
- Verification checks (from governance/verification.md)
- Anti-patterns (from governance/anti-patterns.md)
- Constraints (from governance/constraints.md)

## Procedure

### 1. Read project context

- Read governance index and relevant governance files
- Read PLAN.md if present (check for existing modernization phases)
- Identify the project's language, framework, and toolchain

### 2. Run static analysis

Execute checks appropriate to the project's language:

**For shell projects:**
- `bash -n` on all shell files
- `shellcheck` on all shell files
- Anti-pattern density (via code-scan pattern library)

**For other languages:**
- Run the project's linter(s) as identified in governance/verification.md
- Run type checker if applicable
- Scan for language-specific anti-patterns from governance

### 3. Score 5 dimensions (0-100 each)

**3a. Lint Score**
- Start at 100
- Deduct per syntax/lint failure (severity-weighted)
- Floor at 0

**3b. Anti-Pattern Score**
- Start at 100
- Deduct per anti-pattern instance (severity-weighted)
- Floor at 0

**3c. Test Coverage Score**
- 100: comprehensive suite with high coverage
- 75: suite exists, moderate coverage
- 50: basic tests exist
- 25: minimal or broken tests
- 0: no test infrastructure

**3d. Documentation Score**
- 25 pts each for: primary docs (man page/API docs), README, CLI help/usage,
  configuration documentation

**3e. Dependency Hygiene Score**
- Score based on dependency management practices: version pinning,
  shared library usage, vendoring strategy, upgrade paths

### 4. Map findings to phases

Group findings by logical unit (not by severity). Order phases by
dependency: fixes before features, infrastructure before consumers.

### 5. Generate assessment report

    # Modernization Assessment — <project> v<version>

    ## Maturity Scores
    | Dimension             | Score | Grade |
    |-----------------------|-------|-------|
    | Lint                  | XX    | A-F   |
    | Anti-Patterns         | XX    | A-F   |
    | Test Coverage         | XX    | A-F   |
    | Documentation         | XX    | A-F   |
    | Dependency Hygiene    | XX    | A-F   |
    | **Overall**           | XX    | A-F   |

    Grade scale: A=90-100, B=80-89, C=70-79, D=60-69, F=<60

    ## Key Findings
    - <finding with file:line evidence>
    ...

    ## Remediation Phases
    | Phase | Title | Est. Scope | Dependencies |
    |-------|-------|-----------|--------------|
    ...

    ## Recommended Next Steps
    1. <action> — <rationale>
    ...

### 6. Offer PLAN generation

After displaying the report, ask:
"Generate PLAN-modernize.md with the remediation phases? [y/n]"

If yes, write PLAN-modernize.md using standard PLAN format.

## Rules
- Read-only assessment — do NOT modify any existing project files
- Score objectively — do not inflate grades
- Include evidence (file:line) for every finding
- If PLAN.md already has modernization phases, note overlap and recommend
  merging rather than duplicating
