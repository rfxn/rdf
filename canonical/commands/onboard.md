Lightweight intake for an unfamiliar project. Detects project structure and
creates the standard rfxn scaffold files (CLAUDE.md, MEMORY.md, git exclusions).

`$ARGUMENTS` is the project path (required). Can be absolute or relative.

---

## Procedure

### 1. Validate target

- Verify the path exists and is a directory
- Check for `.git/` — if absent, warn and ask user if they want to continue
- Determine the absolute path for all subsequent operations

### 2. Detect project characteristics

Scan the directory to identify:

**Project type:**
- Shell project: `.sh` files, main executable script without extension
- Python project: `*.py`, `setup.py`, `pyproject.toml`
- Mixed: combination of above
- Unknown: flag for manual review

**For shell projects, identify:**
- Main script (largest executable in `files/` or project root)
- Config file (`conf.*`, `*.conf`, `internals.conf`)
- Version string (grep for `VER=`, `VERSION=`, `version=`)
- License (grep for GPL, MIT, etc. in headers or LICENSE file)
- Install script (`install.sh`, `Makefile`)
- Test infrastructure (`tests/`, `*.bats`, `Makefile` test targets)
- Shared library usage (grep for `tlog_lib`, `alert_lib`, `elog_lib`, `pkg_lib`)

**Source file inventory:**
- Count shell files, total lines
- List function definitions (`function_name()` patterns)
- Identify sourced files (`. "$path"` or `source "$path"`)

### 3. Run quick lint

- `bash -n` on all detected shell files
- Report pass/fail summary (do NOT run shellcheck — keep onboard fast)

### 4. Create scaffold files

**CLAUDE.md** (in project root):

```markdown
> Inherits all conventions from the parent CLAUDE.md at
> `/root/admin/work/proj/CLAUDE.md`. This file covers only
> project-specific architecture, variables, and test details.

# <Project Name>

## Overview
- **Version:** <detected version>
- **License:** <detected license>
- **Main script:** `<path>`
- **Config:** `<path>`

## Architecture

### Source Files
| File | Purpose | Lines |
|------|---------|-------|
| `<file>` | <detected purpose> | <count> |

### Key Functions
<list of detected function definitions with file locations>

### Configuration Loading
<detected config loading order from source analysis>

## Testing
<detected test infrastructure, or "No test infrastructure detected">

## Known Issues
<populated from bash -n results, if any failures>
```

**MEMORY.md** (in Claude projects memory directory):

Determine the correct memory path from the project directory:
- Convert absolute path to the Claude memory slug format
  (e.g., `/root/admin/work/proj/myproject` -> `-root-admin-work-proj-myproject`)
- Create `/root/.claude/projects/<slug>/memory/MEMORY.md`

```markdown
# <Project Name> Memory

## Project State
- **Version:** <detected>
- **Branch:** <current git branch>
- **Status:** Onboarded — initial assessment

## Onboard Summary (<date>)
- Shell files: <count>
- Total lines: <count>
- Functions: <count>
- Lint: <pass/fail summary>
- Test infra: <present/absent>
- Shared libs: <list or "none detected">

## Open Work Items
- Run `/modernize <project>` for full maturity assessment
```

### 5. Configure git exclusions

If `.git/` exists, add exclusion entries to `.git/info/exclude`:

```
# rfxn working files
CLAUDE.md
MEMORY.md
PLAN*.md
AUDIT.md
work-output/
.claude/
```

Only add entries that are not already present. Create the `info/` directory
and `exclude` file if they don't exist.

### 6. Report

```
# Onboard Complete — <project>

## Detected
- Type: <shell/python/mixed/unknown>
- Version: <version or "not detected">
- Files: <count> shell files, <total lines> lines
- Functions: <count> definitions
- Lint: <pass/fail summary>

## Created
- CLAUDE.md (<path>)
- MEMORY.md (<path>)
- .git/info/exclude entries added

## Recommended Next Steps
1. Review generated CLAUDE.md — fill in architecture details
2. Run `/modernize <project>` for full maturity assessment
3. Run `/code-validate` for detailed lint report
```

---

## Rules

- **Does NOT modify existing project files** — only creates new scaffold files
- **Does NOT create test infrastructure** — that's `/proj-scaffold`'s job
- If CLAUDE.md already exists in the project, warn and ask before overwriting
- If MEMORY.md already exists, warn and ask before overwriting
- Keep onboard fast — `bash -n` only, no shellcheck, no tests
- For non-shell projects, create minimal CLAUDE.md with detected structure
