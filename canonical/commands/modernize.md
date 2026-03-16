Assess a project's modernization maturity and generate a phased remediation plan.
This is a **read-only assessment** — it does NOT modify any project files.

`$ARGUMENTS` is the project name or alias (required).

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

If the argument does not match an alias, treat it as a directory path.

---

## Procedure

### 1. Read project context

- Read `./CLAUDE.md` in the project directory
- Read the project's MEMORY.md from the Claude projects memory directory
- Read `./PLAN.md` if present
- Read `/root/admin/work/proj/CLAUDE.md` (parent conventions)

### 2. Run static analysis

Execute these checks and capture all output:

**Lint sweep:**
- `bash -n` on all shell files (`.sh`, main script, `internals.conf`)
- `shellcheck` on all shell files
- Capture pass/fail counts

**Anti-pattern density:**
Run `/code-validate` and `/code-grep` to detect:
- Hardcoded binary paths (`/sbin/ip`, `/usr/sbin/iptables`, etc.)
- Hardcoded install paths
- Backtick usage
- `$[expr]` arithmetic
- `egrep` / `which` usage
- `$RANDOM` / `$$` temp files
- Unquoted variables in command context
- `for x in $(cat)` patterns
- Bash 4.2+ features (`${var,,}`, `mapfile -d`, `declare -n`)

### 3. Score 5 dimensions (0-100 each)

**3a. Lint Score**
- Start at 100
- Deduct 5 per `bash -n` failure
- Deduct 2 per shellcheck warning (excluding info-level)
- Floor at 0

**3b. Anti-Pattern Score**
- Start at 100
- Deduct 3 per hardcoded path
- Deduct 5 per backtick or `$[expr]`
- Deduct 2 per `egrep` / `which`
- Deduct 10 per bash 4.2+ feature
- Floor at 0

**3c. Test Coverage Score**
- 100: comprehensive BATS suite with >80% function coverage
- 75: BATS suite exists, moderate coverage
- 50: basic tests exist
- 25: minimal or broken tests
- 0: no test infrastructure

**3d. Documentation Score**
- 25 pts: man page exists and is current
- 25 pts: README/README.md exists and is current
- 25 pts: usage/help functions match actual CLI options
- 25 pts: config file comments document all variables

**3e. Shared Library Integration Score**
- 25 pts each for: tlog_lib, alert_lib, elog_lib, pkg_lib
- Score based on whether project uses the shared library vs inline implementation

### 4. Map findings to phases

Group findings by logical unit (not by severity):
1. Critical lint fixes (bash -n failures) — always Phase 1
2. Shell standard modernization (backticks, egrep, which, etc.)
3. Binary/install path hardcoding remediation
4. Error handling gaps (silent suppression, missing exit codes)
5. Test infrastructure and coverage gaps
6. Shared library adoption (tlog_lib, alert_lib, elog_lib)
7. Documentation alignment (help, man page, README, config)
8. Dead code removal and duplication extraction

Order phases by dependency: fixes before features, infrastructure before consumers.

### 5. Generate assessment report

Output the report directly (do NOT write to a file):

```
# Modernization Assessment — <project> v<version>

## Maturity Scores
| Dimension             | Score | Grade |
|-----------------------|-------|-------|
| Lint                  | XX    | A-F   |
| Anti-Patterns         | XX    | A-F   |
| Test Coverage         | XX    | A-F   |
| Documentation         | XX    | A-F   |
| Library Integration   | XX    | A-F   |
| **Overall**           | XX    | A-F   |

Grade scale: A=90-100, B=80-89, C=70-79, D=60-69, F=<60

## Key Findings
- <finding 1>
- <finding 2>
- ...

## Remediation Phases
| Phase | Title                          | Est. Scope | Dependencies |
|-------|--------------------------------|-----------|--------------|
| 1     | Critical lint fixes            | N files   | none         |
| 2     | Shell standard modernization   | N files   | Phase 1      |
| ...   | ...                            | ...       | ...          |

## Recommended Next Steps
1. <action> — <rationale>
2. <action> — <rationale>
```

### 6. Offer PLAN generation

After displaying the report, ask the user:
"Generate `PLAN-modernize.md` with the remediation phases? [y/n]"

If yes, write `PLAN-modernize.md` to the project directory using the standard
PLAN format with numbered phases, status markers, and dependency fields.

---

## Rules

- **Read-only assessment** — do NOT modify any existing project files
- **No code changes** — assessment only, remediation is dispatched via `/mgr phase`
- Score objectively — do not inflate grades
- Include evidence (file:line) for every finding
- If the project already has a PLAN.md with modernization phases, note overlap
  and recommend merging rather than duplicating
