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
