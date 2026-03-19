Governance initialization for any codebase. Scans the project, ingests
existing convention files, detects languages and tooling, and generates
supplementary governance under `.claude/governance/`.

`$ARGUMENTS` is the target path (optional, defaults to `.` for the
current working directory). Can be a subdirectory for monorepo scoping.

### Options

- `--force` — delete existing `.claude/governance/` and regenerate
  from scratch. Without this flag, /r:init refuses to run when
  governance already exists (directs to `/r:refresh` instead).

## Progress Tracking

At command startup, set up progress tracking for user feedback:

**If TaskCreate tool is available** (Claude Code):
```
TaskCreate: subject: "Ingest convention files"
  activeForm: "Ingesting conventions"
TaskCreate: subject: "Scan codebase"
  activeForm: "Scanning codebase"
TaskCreate: subject: "Detect tooling"
  activeForm: "Detecting tooling"
TaskCreate: subject: "Generate governance"
  activeForm: "Generating governance"
TaskCreate: subject: "Validate accuracy"
  activeForm: "Validating"
```
Mark each `in_progress` → `completed` as phases complete.
For >30s operations, update activeForm with progress.

**If TaskCreate is NOT available** (Gemini CLI, Codex):
Output a markdown checklist and update inline as phases complete:
```
- [ ] Ingest conventions
- [ ] Scan codebase
- [ ] Detect tooling
- [ ] Generate governance
- [ ] Validate
```
Replace each `[ ]` with `[x]` as the phase completes.

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

Mark task "Ingest existing convention files" as in_progress.

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

Mark task "Ingest existing convention files" as completed.

## Phase 2: Codebase Scan

Mark task "Scan codebase: languages, frameworks, structure" as in_progress.

Analyze the target directory to detect languages, frameworks, directory
structure, build system, and test infrastructure.

### Codebase Size Assessment

Before scanning, measure the codebase to select the right strategy:

```bash
# Use git ls-files to respect .gitignore (excludes node_modules, vendor, build, etc.)
git ls-files 2>/dev/null | wc -l
```

| Size | Files | Strategy |
|------|-------|----------|
| Small | <500 | Full scan — read configs, sample source files |
| Medium | 500-5,000 | Targeted scan — configs + extension counting only |
| Large | 5,000-50,000 | Fast scan — `git ls-files` + extension stats, no source reads |
| Monorepo | >50,000 | Scoped scan — require `--scope` or auto-detect top-level services |

For all sizes, **always use `git ls-files`** (not `find`) to avoid
scanning build output, node_modules, vendor directories, and other
gitignored paths. If not a git repo, use `find` with explicit
exclusions:

```bash
find . -not -path './.git/*' -not -path '*/node_modules/*' \
  -not -path '*/vendor/*' -not -path '*/.venv/*' \
  -not -path '*/dist/*' -not -path '*/build/*' \
  -not -path '*/target/*' -not -path '*/__pycache__/*' \
  -type f
```

Report the file count and chosen strategy in the output.

### Language Detection

Use `git ls-files` with extension counting for fast, accurate results:

```bash
git ls-files | sed 's/.*\.//' | sort | uniq -c | sort -rn | head -20
```

For extensionless files, check shebangs:
```bash
git ls-files | while read -r f; do
  [[ "$f" == *.* ]] && continue
  head -1 "$f" 2>/dev/null | grep -q '^#!' && head -1 "$f"
done | sort | uniq -c | sort -rn
```

Supplement with package manifests: `package.json`, `pyproject.toml`,
`Cargo.toml`, `go.mod`, `Gemfile`, `pom.xml`, `build.gradle`.

Record: primary language, secondary languages, percentage breakdown,
total file count, approximate total lines (`git ls-files | xargs wc -l`
for small/medium, `wc -l` on a sample for large).

### Version Detection

Detect the project version from (first match wins):
- `package.json` → `.version`
- `pyproject.toml` → `[project] version` or `[tool.poetry] version`
- `Cargo.toml` → `[package] version`
- `VERSION` or `VERSION.txt` file
- Source grep: `VERSION=`, `__version__`, `APP_VERSION`
- Git tags: `git describe --tags --abbrev=0 2>/dev/null`

### License Detection

Check for `LICENSE`, `LICENSE.md`, `LICENSE.txt`, `COPYING`.
Extract the license type from the first line or SPDX identifier.

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

Mark task "Scan codebase: languages, frameworks, structure" as completed.

## Phase 3: Tooling & Infrastructure Detection

Mark task "Detect tooling and infrastructure" as in_progress.

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

Mark task "Detect tooling and infrastructure" as completed.

## Phase 4: Generate Supplementary Governance

Mark task "Generate supplementary governance" as in_progress.

Create `.claude/governance/` directory and generate governance files.
This phase applies the supplement model: reference existing coverage,
generate from scan data where gaps exist, never duplicate.

### Directory Setup

```bash
mkdir -p .claude/governance
```

If `.claude/governance/` already exists (from a prior /r:init or
/r:refresh):

- **Without `--force`:** stop and direct the user to `/r:refresh`
  (see Error Handling #4). DO NOT modify existing files.
- **With `--force`:** delete the existing `.claude/governance/`
  directory entirely, then proceed with fresh generation. Log the
  deletion: `Removed existing governance ({N} files)`.

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

Mark task "Generate supplementary governance" as completed.

## Phase 5: Validate

Mark task "Validate and spot-check accuracy" as in_progress.

Verify generated governance accuracy and flag low-confidence inferences
for user review.

### Spot-Check Procedure

For each generated governance file, perform at least 3 spot checks:

1. **conventions.md** — pick 3 claimed conventions, verify each against
   actual source files. Example: if conventions.md says "2-space indent",
   check 3 source files to confirm.

2. **verification.md** — verify that each listed command actually works:
   - If a test command is listed, confirm the test runner is installed
     or documented in package manifest
   - If a lint command is listed, confirm the linter config file exists

3. **architecture.md** — verify that listed components exist as actual
   directories or files in the project.

4. **constraints.md** — verify platform targets match CI matrix or
   documentation. Cross-check version floors against actual configs.

5. **anti-patterns.md** — verify that referenced linter rules exist
   in the actual linter config files.

### Confidence Scoring

Assign confidence to each governance file section:

- **HIGH** — derived from explicit configuration files or existing
  .md documentation. Example: test command from CI workflow file.
- **MEDIUM** — inferred from source code patterns with consistent
  evidence. Example: indent style from 90%+ file consistency.
- **LOW** — inferred from limited evidence or conflicting signals.
  Example: platform targets guessed from Dockerfile alone.

### Low-Confidence Report

Collect all LOW confidence items and any conflicts into a report
presented to the user after generation:

```
Low-confidence items (review recommended):
- constraints.md § Platform Targets: inferred from Dockerfile only
  (ubuntu:22.04) — no CI matrix or docs to confirm
- conventions.md § Line Length: CONFLICT between .eslintrc (120)
  and .prettierrc (80) — using .eslintrc value
- anti-patterns.md § Historical: limited git history (< 20 commits)
  — fragile area detection may be incomplete
```

### Validation Failures

If a spot check reveals an inaccuracy:

1. Fix the governance file content immediately
2. Downgrade the confidence level for that section to LOW
3. Add the item to the low-confidence report
4. DO NOT skip generation — a partially-accurate governance file
   with flagged uncertainties is better than no governance

Mark task "Validate and spot-check accuracy" as completed.

## Output Report

After all 5 phases complete, present one clean, compact summary. This
is the user's first impression of RDF — it must feel like a superpower.

**Target: under 25 lines.** Drop rows where the value is `(not detected)`.
Only show what was actually found — absence is not information.

```markdown
## {Project} initialized — {N} governance files from {N} sources

| Codebase | Governance | Confidence |
|----------|-----------|------------|
| {lang} {pct}%, {N} files, ~{N}k lines | {N} files ingested, {N} generated | {N} HIGH / {N} MED / {N} LOW |

**Stack**: {language} {version} · {framework} · {test framework} ({N} tests) · {linters} · {CI platform}

**Governance** ({N} files, {total_lines} lines):
- [x] `index.md` — project identity, always loaded
- [x] `architecture.md` — {source: scan / refs / mixed}
- [x] `conventions.md` — {source}
- [x] `verification.md` — {source}
- [x] `constraints.md` — {source}
- [x] `anti-patterns.md` — {source}

{only if LOW > 0 or conflicts:}
> **Review**: {N} low-confidence items — {1-line summary of top concern}

> **Ready** — `/r:start` to begin | `/r:spec` to design | `/r:plan` to plan
```

**Adaptation rules:**
- The heading includes the project name and a count — makes the
  output feel like a result, not a form
- The **Stack** line is a single `·`-separated string — dense and
  scannable. Omit fields that weren't detected rather than showing
  empty slots.
- The governance checklist shows what was created and where the
  content came from — this is RDF's value prop in action
- Low-confidence items get ONE blockquote line, not a full table.
  Details are in the governance files themselves.
- The **Ready** line replaces the old 5-row "Next Steps" table — the
  user knows what commands exist, they need a nudge not a menu
- Git state is NOT shown — the user already has their terminal, the
  init output should be about what RDF did, not what git looks like
- Duration is NOT shown — fast is felt, not reported

### Git Exclusion

After generating governance, verify `.rdf/` is in `.git/info/exclude`.
If not, add it automatically — governance is local operational state,
not committed source. Do not prompt the user; this is the default.

---

## Rules

### Supplement Model

1. **NEVER modify existing convention files** — CLAUDE.md, AGENTS.md,
   GEMINI.md, MEMORY.md, PLAN.md, .cursorrules, and
   .github/copilot-instructions.md are read-only inputs to /r:init.
2. **NEVER duplicate content** — if an existing file covers a topic,
   the governance file MUST cross-reference it by section name and
   line range instead of copying the content.
3. **Generate only for gaps** — governance files contain original
   content only for topics not covered by any existing file.
4. **Never silently resolve conflicts** — every disagreement between
   sources must appear in the low-confidence report.

### Error Handling

1. If the target path does not exist, report an error and stop.
2. If the target path has no `.git/`, warn the user that git history
   analysis (Phase 3) will be skipped, then continue with remaining
   phases.
3. If no convention files AND no source files are found, report that
   the directory appears empty and stop.
4. If `.claude/governance/` already exists with files AND `--force`
   is NOT set, warn the user:
   - "Governance files already exist. To update, use `/r:refresh`."
   - "To regenerate from scratch, use `/r:init --force`."
   - Stop without modifying existing governance files.
   If `--force` IS set, delete `.claude/governance/` and continue.

### Monorepo Behavior

1. `/r:init .` at the repo root produces governance for the dominant
   patterns across the whole repository.
2. `/r:init ./services/api` scopes Phases 2-3 to that subdirectory
   but still checks parent directories for convention files (Phase 1).
3. Scoped governance is written to `{subdir}/.claude/governance/`,
   NOT to the repo root's `.claude/governance/`.
4. The architecture.md for a root-level init in a monorepo documents
   all service boundaries and their individual technology stacks.

### Re-Init vs Refresh

- `/r:init` is for first-time governance generation. It refuses to
  run if `.claude/governance/` already exists (see Error Handling #4).
- `/r:init --force` deletes existing governance and regenerates from
  scratch. Use when governance is stale, corrupt, or after major
  codebase restructuring that `/r:refresh` can't handle.
- `/r:refresh` is for updating governance after codebase changes.
  It preserves user modifications and updates scan-derived content.

### Performance

**Phase 1 (ingest):**
- Read convention files in full only if under 500 lines. For files
  >500 lines, scan section headers (`## `) and extract the coverage
  map from headings without reading every line.
- Maximum 10 convention files. If more exist (e.g., many
  `.cursor/rules/*.md`), read the 10 most recently modified.

**Phase 2 (scan):**
- Always use `git ls-files` for file enumeration — never bare `find`
- Language detection via extension counting is O(N) on the file list,
  no file reads needed
- Line counting: for <5k files, use `git ls-files | xargs wc -l`.
  For >5k files, sample 100 files per language and extrapolate.
- Do NOT read source files for convention detection — that comes
  from configs and linter files only

**Phase 3 (tooling):**
- Read only specific config file paths (CI workflows, Dockerfiles,
  linter configs) — do NOT traverse the file tree
- Git history analysis: `git log --oneline -50` (last 50 commits)
- Contributor count: `git shortlog -sn --no-merges | wc -l`

**Target wall times:**
- Small (<500 files): under 30 seconds
- Medium (500-5k files): under 60 seconds
- Large (5k-50k files): under 90 seconds
- Monorepo (>50k files): under 120 seconds (scoped mode)

**Context budget:** The init command should not consume more than
~20% of the context window. For large codebases, prefer running
bash commands for stats over reading files into context.

### Idempotency

If /r:init is run and produces governance files, running /r:init
again (without `--force`) will NOT modify anything — it detects
existing governance and directs the user to `/r:refresh`.
With `--force`, idempotency is explicitly broken — existing
governance is deleted and regenerated from the current codebase state.
