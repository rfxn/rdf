Governance initialization for any codebase. Scans the project, ingests
existing convention files, detects languages and tooling, and generates
supplementary governance under `.claude/governance/`.

`$ARGUMENTS` is the target path (optional, defaults to `.` for the
current working directory). Can be a subdirectory for monorepo scoping.

---

## Prerequisites

- The governance index schema must exist at `schemas/governance-index.md`
  in the RDF installation (created by Plan 1 Task 2)
- The target path must be a directory (warn if no `.git/` is present)

## Overview

/r:init runs 5 phases in sequence:

1. **Ingest** — scan for existing convention .md files (highest priority)
2. **Codebase scan** — detect languages, frameworks, directory structure
3. **Tooling detection** — CI/CD, containers, linters, git patterns
4. **Generate** — produce supplementary governance files
5. **Validate** — spot-check accuracy, flag low-confidence inferences

Output directory: `.claude/governance/` (relative to target path)

## Phase 1: Ingest Existing Convention Files

Scan the target directory for convention files in priority order.
These files remain authoritative — they are NEVER modified or replaced.

### Priority Cascade

Scan for each file in this order. Higher-priority sources override lower
ones when content overlaps:

```
Priority 1 (curated conventions — highest signal):
  - CLAUDE.md (project root and parent directories)
  - AGENTS.md
  - GEMINI.md

Priority 2 (project state and decisions):
  - MEMORY.md
  - PLAN.md / PLAN*.md

Priority 3 (Cursor conventions):
  - .cursorrules
  - .cursor/rules/*.md

Priority 4 (Copilot conventions):
  - .github/copilot-instructions.md

Priority 5-7 are covered by Phases 2-3 (scan and tooling).
```

### Ingest Procedure

For each file found:

1. Record the file path, line count, and modification date
2. Extract content categories present in the file:
   - **Architecture:** component maps, data flow, system boundaries
   - **Conventions:** coding style, naming, formatting, patterns
   - **Verification:** test commands, lint configs, CI checks
   - **Constraints:** platform targets, version floors, compatibility
   - **Anti-patterns:** known pitfalls, prohibited patterns
3. Build a coverage map: `{category -> [source_file, section_name, line_range]}`
4. DO NOT copy content from these files — only record what they cover
   and where. Governance files will reference them by section name.

### Monorepo Scoping

If `$ARGUMENTS` points to a subdirectory:
- Still check parent directories up to the git root for CLAUDE.md,
  AGENTS.md (these often live at the repo root)
- Scope all other file discovery to the target subdirectory
- Record the scoping in the governance index as `Scope: {subdir}`

### Output of Phase 1

An internal coverage map (not written to disk) that tracks:
- Which files were found and their priority tier
- Which governance categories they cover (full, partial, or none)
- Sections within each file that map to each category

## Phase 2: Codebase Scan

Analyze the target directory to detect languages, frameworks, directory
structure, build system, and test infrastructure.

### Language Detection

Scan file extensions, shebangs, and package manifests:

- **File extensions:** `.py`, `.js`, `.ts`, `.go`, `.rs`, `.java`,
  `.rb`, `.sh`, `.bash`, `.c`, `.cpp`, `.h`
- **Shebangs:** Read first line of files without extensions —
  `#!/bin/bash`, `#!/usr/bin/env python3`, etc.
- **Package manifests:** `package.json`, `pyproject.toml`, `setup.py`,
  `Cargo.toml`, `go.mod`, `Gemfile`, `pom.xml`, `build.gradle`

Record: primary language, secondary languages, percentage breakdown.

### Framework Detection

Identify frameworks from dependency declarations and imports:

- **package.json:** Check `dependencies` and `devDependencies` for
  React, Vue, Next.js, Express, Fastify, etc.
- **pyproject.toml / requirements.txt:** Django, Flask, FastAPI, etc.
- **Cargo.toml:** Actix, Axum, Rocket, etc.
- **go.mod:** Gin, Echo, Fiber, etc.
- **Config files:** `next.config.js`, `nuxt.config.ts`, `angular.json`,
  `webpack.config.js`, `vite.config.ts`

### Directory Structure

Map the project layout:

- Source directories: `src/`, `lib/`, `app/`, `pkg/`, `cmd/`, `files/`
- Test directories: `tests/`, `test/`, `__tests__/`, `spec/`
- Documentation: `docs/`, `doc/`
- Configuration: config files at root level
- Build output: `dist/`, `build/`, `target/`, `out/`

### Build System

Detect how the project builds and runs:

- `Makefile` — scan targets (build, test, install, clean)
- `package.json` scripts — scan script names and commands
- `pyproject.toml` [tool.poetry.scripts] or [project.scripts]
- CI configs (detailed in Phase 3)

### Test Framework

Identify test infrastructure:

- **JavaScript/TypeScript:** jest, vitest, mocha, cypress, playwright
  (from devDependencies + config files)
- **Python:** pytest, unittest, tox (from configs + test file patterns)
- **Bash:** bats (from `.bats` files, `tests/` directory)
- **Go:** standard `go test` (from `_test.go` files)
- **Rust:** standard `cargo test` (from `#[test]` in source)

Record: test framework(s), test directory, test file count,
test runner command.

### Linter/Formatter Detection

Scan for configuration files:

- `.eslintrc*`, `.prettierrc*`, `biome.json` (JS/TS)
- `.flake8`, `pyproject.toml [tool.ruff]`, `setup.cfg` (Python)
- `.shellcheckrc`, shellcheck directives in source (Bash)
- `.golangci.yml` (Go)
- `.editorconfig` (cross-language)
- `.clang-format` (C/C++)

### Output of Phase 2

An internal scan result (not written to disk) containing:
- Language breakdown with percentages
- Detected frameworks with versions where available
- Directory structure map
- Build system and commands
- Test framework, runner command, and test count
- Linter/formatter tools and their config file paths

## Phase 3: Tooling & Infrastructure Detection

Detect CI/CD, containers, platform targets, dependency management,
and git conventions.

### CI/CD Detection

Scan for CI configuration:

- **GitHub Actions:** `.github/workflows/*.yml` — extract job names,
  test matrix (OS, language versions), deployment targets
- **GitLab CI:** `.gitlab-ci.yml` — extract stages, jobs, runners
- **Jenkins:** `Jenkinsfile` — extract stages and agents
- **CircleCI:** `.circleci/config.yml`
- **Travis:** `.travis.yml`

Record: CI platform(s), test matrix, deployment targets, and the
actual test/lint/build commands run in CI.

### Container Detection

- `Dockerfile` — extract base image, exposed ports, entrypoint
- `docker-compose.yml` — extract services, volumes, networks
- `.dockerignore` — note excluded paths

### Platform Targets

Determine target operating systems and environments:

- From CI matrix (e.g., `runs-on: [ubuntu-22.04, macos-latest]`)
- From Dockerfile base images
- From README or CLAUDE.md (already captured in Phase 1)
- From conditional logic in source (`if [[ "$OSTYPE" == ... ]]`)

### Dependency Management

- Lockfiles: `package-lock.json`, `yarn.lock`, `pnpm-lock.yaml`,
  `poetry.lock`, `Pipfile.lock`, `Cargo.lock`, `go.sum`
- Version constraints: minimum versions, pinned versions
- Monorepo tools: `lerna.json`, `pnpm-workspace.yaml`,
  `nx.json`, Turborepo (`turbo.json`)

### Git Patterns

Analyze recent git history (last ~50 commits):

- **Branch naming:** feature/, bugfix/, release/, hotfix/
- **Commit conventions:** conventional commits, custom prefix,
  tag format (e.g., `[New]`, `[Fix]`, `type: description`)
- **Active areas:** files with most recent changes
- **Contributors:** number of unique authors (team size signal)

### Output of Phase 3

An internal tooling result (not written to disk) containing:
- CI platform and configuration summary
- Container setup and base images
- Platform target list
- Dependency management tools and lockfile status
- Git conventions (branch naming, commit format)
- Active development areas

## Phase 4: Generate Supplementary Governance

Create `.claude/governance/` directory and generate governance files.
This phase applies the supplement model: reference existing coverage,
generate from scan data where gaps exist, never duplicate.

### Directory Setup

```bash
mkdir -p .claude/governance
```

If `.claude/governance/` already exists (from a prior /r:init or
/r:refresh), DO NOT delete it. Each file is written only if it does
not already exist — /r:refresh handles updates separately.

### Merge Logic

For each governance file, apply this decision tree:

1. **Full coverage in existing .md files** — governance file contains
   ONLY cross-references:
   ```
   ## Coding Style
   See CLAUDE.md § "Shell Standards" (lines 45-92)
   ```

2. **No coverage in existing .md files** — governance file generates
   full content from Phase 2-3 scan data:
   ```
   ## Coding Style
   Detected conventions from codebase analysis:
   - Indentation: 2-space (consistent across 47 JS files)
   - Semicolons: absent (ESLint no-semi rule in .eslintrc)
   - Quotes: single (Prettier singleQuote: true)
   ```

3. **Partial coverage** — governance file cross-references what exists
   and supplements the gaps:
   ```
   ## Coding Style
   See CLAUDE.md § "Shell Standards" for shell conventions.

   Additional conventions detected from codebase:
   - Python files use black formatter (pyproject.toml [tool.black])
   - Line length: 88 (black default, confirmed in 23 files)
   ```

### Conflict Resolution

When sources disagree:

1. **Higher-priority source wins** per the priority cascade (Phase 1).
   The winning value is used in the governance file.
2. **Conflicts are flagged** with both values shown:
   ```
   ## Indentation
   CONFLICT: CLAUDE.md specifies tabs, .editorconfig specifies 2-space.
   Using CLAUDE.md value (higher priority). Review and resolve.
   ```
3. **Same-tier conflicts** (e.g., two linter configs disagree) —
   document both values and flag for user resolution:
   ```
   ## Line Length
   CONFLICT (same priority): .eslintrc max-len=120, .prettierrc printWidth=80.
   Both documented — resolve by choosing one and updating the other config.
   ```
4. **Never silently pick a side** — every conflict appears in the
   low-confidence report (Phase 5).

### Generate: architecture.md

Content sources: Phase 2 directory structure, Phase 3 container/CI
data, Phase 1 architecture sections from existing .md files.

Structure:
```
# Architecture

## Project Overview
{project name, primary language, framework}

## Components
{directory-to-purpose mapping from Phase 2}

## Data Flow
{inferred from framework detection — e.g., HTTP request flow for
web frameworks, CLI argument flow for CLI tools}

## Key Boundaries
{service boundaries from docker-compose, monorepo workspace boundaries,
module boundaries from package structure}

## External Dependencies
{frameworks, databases, external services from dependency analysis}
```

If existing .md files already describe architecture, this file
contains cross-references and supplements only.

### Generate: conventions.md

Content sources: Phase 2 linter/formatter configs, Phase 1 convention
sections from existing .md files, Phase 3 git commit patterns.

Structure:
```
# Conventions

## Coding Style
{from linter/formatter configs and source analysis}

## Naming
{from source analysis — file naming, function naming, variable naming}

## File Organization
{from directory structure analysis}

## Commit Messages
{from git history analysis in Phase 3}

## Branch Strategy
{from git branch naming patterns in Phase 3}
```

### Generate: verification.md

Content sources: Phase 2 test framework and linter detection,
Phase 3 CI configuration, Phase 1 verification sections.

Structure:
```
# Verification

## Lint
{linter tool, config file, run command}

## Type Checks
{type checker if detected, run command}

## Tests
{test framework, test directory, run command, test count}

## CI Checks
{CI platform, what runs in CI, how to run locally}

## Pre-Commit
{pre-commit hooks if detected, what they check}

## Manual Checks
{anything from existing .md files that requires manual verification}
```

This file is critical — it tells the QA agent exactly what checks
to run. Be specific about commands.

### Generate: constraints.md

Content sources: Phase 3 platform targets, Phase 2 version detection,
Phase 1 constraint sections from existing .md files.

Structure:
```
# Constraints

## Platform Targets
{OS list from CI matrix, Dockerfiles, or existing docs}

## Language Version
{minimum version from configs, CI matrix, or source analysis}

## Compatibility
{backward compat requirements from existing docs or lockfiles}

## Dependencies
{pinned versions, version ranges, known conflicts}

## Performance
{performance constraints from existing docs if any}
```

### Generate: anti-patterns.md

Content sources: Phase 1 anti-pattern sections from existing .md files,
Phase 2 linter suppression comments, Phase 3 git history (reverted
commits, frequent fix areas).

Structure:
```
# Anti-Patterns

## Project-Specific
{from existing .md files — known pitfalls for this project}

## Detected from Linter Config
{rules that are explicitly enabled or have custom severity,
indicating they were problems before}

## Common for {language/framework}
{well-known anti-patterns for the detected stack — but only
include ones that are relevant based on the codebase scan}

## Historical
{from git history — files with frequent reverts or fix commits
suggest fragile areas}
```

### Generate: index.md

Generated LAST, after all other governance files. Follows the schema
from `schemas/governance-index.md`.

Structure (must stay under 50 lines / ~100-150 tokens):
```
# Governance Index

## Project
- Name: {detected project name from package manifest, git remote, or dirname}
- Branch: {current git branch}
- Mode: development
- Plan: none

## Authoritative Files
- CLAUDE.md — {one-line description of what it covers}
- AGENTS.md — {one-line description}
{one line per existing .md file found in Phase 1}

## Governance Files
- architecture.md — {one-line summary of what was generated}
- conventions.md — {one-line summary}
- verification.md — {one-line summary}
- constraints.md — {one-line summary}
- anti-patterns.md — {one-line summary}
{only list files that were actually generated with content}

## Reference
{omit this section if no reference docs exist}
```

Rules for index.md:
- One line per file, no multi-line descriptions
- Authoritative Files = existing project .md files (NOT in governance/)
- Governance Files = generated supplements IN .claude/governance/
- Must stay under 50 lines — this is the always-loaded context
