Scaffold a new rfxn project with standard infrastructure. Creates directory
structure, config files, test setup, CI workflow, and memory files matching
rfxn conventions. Interactive — prompts for project details before creating.

## Arguments
- `$ARGUMENTS` — optional: `<name> <type>` (e.g., `pkg_lib library`)

## Step 1: Gather Project Info

If not provided in `$ARGUMENTS`, ask the user:
1. **Project name** (e.g., `pkg_lib`, `apf`, `new-tool`)
2. **Type**: `library` (shared lib) or `application` (standalone tool)
3. **Initial version** (default: `1.0.0` for libraries, `0.1.0` for applications)
4. **Description** (one line)

## Step 2: Create Directory Structure

### For applications:
```
<name>/
  files/
    <name>              # Main script (executable)
    internals/
      internals.conf    # Path discovery, binary detection
      functions         # Function library
    conf.<name>         # User-facing config
  tests/
    infra/              # batsman submodule (git submodule add)
    Makefile            # Test targets
    Dockerfile.debian12 # Primary test container
    01-basic.bats       # Starter test file
  .github/
    workflows/
      smoke-test.yml    # CI workflow using batsman reusable workflow
  install.sh            # Installer
  CHANGELOG             # Full changelog
  CHANGELOG.RELEASE     # Current release changelog
  README.md             # Project readme
```

### For libraries:
```
<name>/
  <name>.sh             # Library source
  tests/
    infra/              # batsman submodule
    Makefile
    Dockerfile.debian12
    01-basic.bats
  .github/
    workflows/
      smoke-test.yml
  CHANGELOG
  CHANGELOG.RELEASE
  README.md
```

## Step 3: Generate File Contents

### CLAUDE.md (project-level)
```markdown
# CLAUDE.md

> **Inherits all shared conventions from parent CLAUDE.md** (`/root/admin/work/proj/CLAUDE.md`)

## Project Overview

<name> is <description>. Written in Bash.

**Version:** <version> | **License:** GNU GPL v2

## Architecture

<placeholder for project architecture>

## Tests

### Running Tests
\`\`\`bash
make -C tests test
\`\`\`
```

### .git/info/exclude
```
CLAUDE.md
PLAN*.md
AUDIT.md
MEMORY.md
.claude/
```

### CHANGELOG
```
<name> changelog

v<version> | <current date>:
[New] Initial project scaffold
```

### CHANGELOG.RELEASE
```
v<version> | <current date>:

  -- New Features --
[New] Initial project scaffold
```

### Main script shebang (applications)
```bash
#!/usr/bin/env bash
```

### Library shebang
```bash
#!/usr/bin/env bash
```

### Makefile (from batsman template)
Use batsman Makefile conventions with project-specific variables:
- `BATSMAN_PROJECT=<name>`
- `BATSMAN_DEFAULT_OS=debian12`

### CI workflow
Use `rfxn/batsman/.github/workflows/test.yml@v1.0.3` reusable workflow.

### MEMORY.md (in Claude projects memory dir)
```markdown
# <Name> Project Memory

## Project State
- **Version:** <version> | **Branch:** `master`
- **Status:** Initial scaffold
```

## Step 4: Initialize Git

```bash
cd /root/admin/work/proj/<name>
git init
git add -A  # Exception: initial scaffold only
git commit -m "[New] Initial project scaffold"
```

## Step 5: Post-Scaffold Report

```
# Project Scaffold: <name>

Type: <type>
Version: <version>
Location: /root/admin/work/proj/<name>

## Created Files
<list all files created>

## Next Steps
1. Edit CLAUDE.md with project-specific architecture
2. Implement core functionality in <main file>
3. Add tests in tests/01-basic.bats
4. Run `make -C tests test` to verify infrastructure
5. Set up GitHub repo: `gh repo create rfxn/<name> --private`
```

## Rules

- Always create under `/root/admin/work/proj/`
- Use parent CLAUDE.md conventions (shebang, permissions, etc.)
- Do NOT create if directory already exists — warn and stop
- Set correct permissions: 755 for executables, 640 for configs, 750 for dirs
- Initialize batsman submodule: `git submodule add https://github.com/rfxn/batsman tests/infra`
- Use the latest batsman tag for CI workflow reference
