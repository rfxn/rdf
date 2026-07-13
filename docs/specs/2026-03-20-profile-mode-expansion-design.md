# Design: Profile & Mode Expansion

**Date:** 2026-03-20
**Status:** Implemented (3.0.1)
**Author:** Ryan MacDonald + Claude (Opus 4.6)

---

## 1. Problem Statement

RDF has 6 domain profiles (core, shell, python, frontend, database, go)
and 4 operational modes (development, security, performance, migration).
This covers the rfxn ecosystem's primary languages but leaves gaps for
common production stacks:

- **No Rust profile** — ownership/borrow-checker errors are the #1 LLM
  failure mode in Rust; governance can catch most of them
- **No TypeScript/Node.js backend profile** — frontend profile covers
  React but not Express/Fastify/Nest server patterns, floating promises,
  type narrowing
- **No Perl profile** — legacy sysadmin tooling, CGI scripts, CPAN
  ecosystem. LLMs generate dangerous two-arg `open` and missing
  `strict`/`warnings`
- **No PHP profile** — modern PHP 8.x with strict types, PSR standards,
  Laravel/Symfony. LLMs produce 2.74x more vulnerabilities in PHP than
  human developers (Veracode 2025)
- **No Infrastructure profile** — every rfxn project has CI/Docker but
  no governance for Terraform, K8s manifests, or Ansible
- **Core template is thin** (62 lines) — missing AI-agent-specific
  guidance that applies to ALL projects regardless of language
- **Profile detection is single-match** — `_detect_project_type()`
  returns ONE type but real projects are multi-domain
- **3 workflow gaps** in modes — refactoring, debugging, and
  documentation tasks get default development mode which produces
  suboptimal agent behavior

**Measured impact:**
- 6 detection signals in `_detect_project_type()` — misses `.rs`,
  `.ts`, `.pl`, `.pm`, `.php`, `.tf`, `Dockerfile`, `k8s/`
- Core governance template: 62 lines, 5 sections, 0 AI-agent-specific
  guidance
- `registry.json`: 6 profiles, no `detect` field, no `tier` field
- 4 modes, no refactoring/debugging/documentation mode

## 2. Goals

1. Add 5 new profiles: Rust (full), TypeScript (full), Perl (starter),
   PHP (starter), Infrastructure (starter)
2. Add 3 new modes: refactoring, debugging, documentation
3. Expand core governance template with comprehensive AI agent guidance
4. Make profiles stackable with auto-detection of multiple signals
5. Update `registry.json` schema with `detect`, `tier`, and stacking
6. Update `_detect_project_type()` to return multiple matches
7. Update `rdf init` to handle multi-profile governance template merging
8. Zero breaking changes — existing single-profile projects continue
   working unchanged

## 3. Non-Goals

- Adding Data/ML profile (deferred — low ecosystem relevance)
- Adding Java profile (deferred — no rfxn Java projects)
- Modifying existing language profiles (shell, python, frontend, go,
  database) — their governance templates and reference docs stay as-is
- Changing mode context file format — new modes follow existing pattern
- Adding programmatic profile enforcement (linting) — profiles are
  advisory governance seeds, not runtime enforcers
- CI-native quality gate export (Spec A scope — architecture evolution)

**No-touch files** (must NOT be modified):
- `profiles/shell/governance-template.md` and `reference/` docs
- `profiles/python/governance-template.md` and `reference/` docs
- `profiles/frontend/governance-template.md` and `reference/` docs
- `profiles/database/governance-template.md` and `reference/` docs
- `profiles/go/governance-template.md` and `reference/` docs
- `modes/development/context.md`
- `modes/security-assessment/context.md`
- `modes/performance-audit/context.md`
- `modes/migration/context.md`

## 4. Architecture

### 4.1 Profile Tier System

```
FULL PROFILE (governance-template.md + 3-4 reference docs):
├── rust/
│   ├── governance-template.md      (~120 lines)
│   └── reference/
│       ├── rust-anti-patterns.md
│       ├── ownership-guide.md
│       └── testing-rust.md
└── typescript/
    ├── governance-template.md      (~110 lines)
    └── reference/
        ├── typescript-anti-patterns.md
        ├── node-backend-guide.md
        └── testing-vitest.md

STARTER PROFILE (governance-template.md only):
├── perl/
│   └── governance-template.md      (~80 lines)
├── php/
│   └── governance-template.md      (~90 lines)
└── infrastructure/
    └── governance-template.md      (~100 lines)
```

### 4.2 Stackable Profile Detection

New `_detect_profiles()` function replaces `_detect_project_type()`.
Returns a comma-separated list of detected profiles.

Detection signals (priority order within each):

| Profile | Detection signals | Priority |
|---------|-------------------|----------|
| shell | `files/` dir with executables, `.sh` files, `*.bats` | 1 |
| python | `pyproject.toml`, `requirements.txt`, `setup.py`, `.py` files | 1 |
| go | `go.mod`, `.go` files | 1 |
| rust | `Cargo.toml`, `.rs` files | 1 |
| typescript | `tsconfig.json`, `.ts` files (not `.d.ts` only) | 1 |
| perl | `cpanfile`, `Makefile.PL`, `Build.PL`, `.pl`/`.pm` files | 1 |
| php | `composer.json`, `.php` files | 1 |
| frontend | `package.json` with react/vue/next/nuxt dep, `.tsx`/`.jsx` | 2 |
| database | `migrations/` dir, `.sql` files, `prisma/`, `drizzle/` | 2 |
| infrastructure | `*.tf` files, `Dockerfile`, `k8s/`, `ansible/` | 3 |

Priority rules:
- All priority-1 signals detected → all included
- Priority-2 signals only included if a priority-1 match exists
- Priority-3 (infrastructure) included if any project signal exists
- `core` always implicit — never listed, always active

### 4.3 Registry Schema Extension

```json
{
  "profiles": {
    "rust": {
      "requires": ["core"],
      "removable": true,
      "tier": "full",
      "detect": ["Cargo.toml", "*.rs"],
      "description": "Rust projects. Ownership, error handling, unsafe discipline, cargo conventions",
      "summary": "governance-template + 3 reference docs"
    },
    "infrastructure": {
      "requires": ["core"],
      "removable": true,
      "tier": "starter",
      "detect": ["*.tf", "Dockerfile", "k8s/", "ansible/"],
      "description": "Infrastructure as code. Terraform, Kubernetes, Ansible, CI/CD",
      "summary": "governance-template only"
    }
  }
}
```

New fields:
- `tier`: `"full"` or `"starter"` — controls whether reference docs
  are expected
- `detect`: array of glob patterns used by auto-detection

### 4.4 Governance Template Merge Order

When multiple profiles are detected (e.g., `python,frontend,database`):

```
core/governance-template.md           ← base (always first)
  + python/governance-template.md     ← primary language
  + frontend/governance-template.md   ← secondary domain
  + database/governance-template.md   ← secondary domain
```

Merge rules:
- **Heading match** is exact string match including `##` level
- **Same heading in multiple templates** → concatenate content,
  later profile's entries appended below a `<!-- from: {profile} -->`
  marker. Flag in low-confidence report:
  "Merged section '{heading}' from {N} profiles — review for conflicts"
- **Unique headings** → included as-is in profile order
- **`core` sections** → always appear first within each heading
- **Nested headings** (`### Subsection`) inherit parent merge behavior

**Two init systems:** `rdf init` (CLI, `lib/cmd/init.sh`) handles
directory creation, exclude setup, and CLAUDE.md generation from
templates. `/r-init` (agent command, `r-init.md`) is a 5-phase
agent-driven governance generation system that scans the codebase.
These are complementary:
- `rdf init` CLI → gets multi-profile `_detect_profiles()` and
  merged CLAUDE.md template generation
- `/r-init` agent command → gets profile list passed in governance
  index, uses it to load profile-specific governance seeds during
  Phase 4 (generate). Detection is already handled by its own
  Phase 2 (codebase scan) — profile names in the index tell it
  which templates to merge during governance generation

Reference docs from all detected profiles are copied to
`.rdf/governance/reference/` with no deduplication needed (different
filenames per profile).

### 4.5 New Modes

Three new mode context files following the existing pattern:

```
modes/
├── development/context.md        (existing)
├── security-assessment/context.md (existing)
├── performance-audit/context.md   (existing)
├── migration/context.md           (existing)
├── refactoring/context.md         (NEW ~60 lines)
├── debugging/context.md           (NEW ~65 lines)
└── documentation/context.md       (NEW ~55 lines)
```

### 4.6 File Map

**New files:**

| File | Est. Lines | Purpose |
|------|-----------|---------|
| `profiles/rust/governance-template.md` | ~120 | Rust conventions, ownership, error handling |
| `profiles/rust/reference/rust-anti-patterns.md` | ~250 | LLM-specific Rust pitfalls |
| `profiles/rust/reference/ownership-guide.md` | ~200 | Ownership/borrowing decision guide |
| `profiles/rust/reference/testing-rust.md` | ~180 | cargo test, proptest, mockall patterns |
| `profiles/typescript/governance-template.md` | ~110 | TS backend conventions, strict mode, async |
| `profiles/typescript/reference/typescript-anti-patterns.md` | ~250 | Floating promises, any abuse, hallucinated packages |
| `profiles/typescript/reference/node-backend-guide.md` | ~200 | Express/Fastify patterns, middleware, error handling |
| `profiles/typescript/reference/testing-vitest.md` | ~180 | Vitest/Jest, Supertest, mocking |
| `profiles/perl/governance-template.md` | ~80 | Modern Perl conventions, strict/warnings, OOP |
| `profiles/php/governance-template.md` | ~90 | PHP 8.x, strict_types, PSR, security |
| `profiles/infrastructure/governance-template.md` | ~100 | Terraform, K8s, Ansible, CI/CD, secrets |
| `modes/refactoring/context.md` | ~60 | Behavior preservation, dependency graphs, regression |
| `modes/debugging/context.md` | ~65 | Hypothesis-driven, instrument-first, root cause |
| `modes/documentation/context.md` | ~55 | Read-then-write, accuracy, API surface |

**Modified files:**

| File | Changes |
|------|---------|
| `profiles/core/governance-template.md` | Expand from 62 to ~140 lines — add AI Agent Discipline section |
| `profiles/registry.json` | Add 5 new profiles, add `tier` and `detect` fields to all |
| `profiles/registry.md` | Update tables for new profiles and composition model |
| `lib/cmd/init.sh` | Replace `_detect_project_type()` with `_detect_profiles()`, update merge logic |
| `canonical/commands/r-init.md` | Document multi-profile detection and merge |
| `canonical/commands/r-mode.md` | Add 3 new modes to available modes table |
| `README.md` | Update profile count badge, profiles table, modes mention |
| `profiles/detection-rules.md` | Add detection signals for 5 new profiles |
| `CHANGELOG` | New entries per commit protocol |
| `CHANGELOG.RELEASE` | New entries per commit protocol |

### 4.7 Size Comparison

| Metric | Before | After |
|--------|--------|-------|
| Profiles | 6 | 11 (+5) |
| Full profiles | 6 | 8 (+2: rust, typescript) |
| Starter profiles | 0 | 3 (perl, php, infrastructure) |
| Modes | 4 | 7 (+3) |
| Core template lines | 62 | ~140 |
| Detection signals | 6 | 17 |
| Registry fields | 4 | 6 (+tier, +detect) |
| Profile composition | single | stackable |

### 4.8 Dependency Tree

```
rdf init
  └── _detect_profiles()              ← NEW: returns comma-separated list
        ├── check Cargo.toml → rust
        ├── check tsconfig.json → typescript
        ├── check *.pl/*.pm → perl
        ├── check composer.json → php
        ├── check *.tf/Dockerfile → infrastructure
        ├── check files/ → shell (existing)
        ├── check pyproject.toml → python (existing)
        ├── check go.mod → go (existing)
        ├── check package.json+react → frontend (existing)
        └── check migrations/ → database (existing)
  └── _merge_governance_templates()   ← NEW: merges detected profiles
        ├── read core/governance-template.md
        ├── for each detected profile:
        │     read {profile}/governance-template.md
        │     merge sections by heading
        └── flag conflicts in low-confidence report
  └── _copy_reference_docs()          ← EXISTING: enhanced for multi-profile
        └── for each detected profile with reference/:
              copy to .rdf/governance/reference/

rdf profile list                       ← reads registry.json
rdf profile status                     ← shows detected + active
```

## 5. File Contents

### 5.1 Core Governance Template Expansion

New sections to add to `profiles/core/governance-template.md`:

| Section | Purpose | Lines |
|---------|---------|-------|
| AI Agent Discipline | Verification habits, hallucination awareness, confidence calibration | ~25 |
| Code Generation Standards | Read before write, evidence-based changes, no phantom APIs | ~20 |
| Context Window Hygiene | Progressive disclosure, avoid re-reading, batch commands | ~15 |
| Collaboration Protocol | When to ask vs proceed, scope boundaries, handoff contracts | ~15 |

**AI Agent Discipline section content:**

- Verify every function, API, and import exists before using it —
  hallucinated imports are the #1 AI coding failure mode
- Never generate code for a file you haven't read — inferred patterns
  diverge from actual patterns after the first few files
- When unsure, state uncertainty explicitly — "I believe X but haven't
  verified" is more useful than confident wrong answers
- Grep the codebase before introducing a new helper — the function you
  need probably already exists under a different name
- After making changes, verify the change works by running the project's
  verification commands, not by re-reading your own output
- Do not add defensive code for scenarios that cannot happen — trust
  framework guarantees and validated input at boundaries
- When a fix doesn't work, investigate root cause — do not layer
  workarounds. Three failed attempts at the same approach means step
  back and reconsider

**Code Generation Standards section content:**

- Read the target file before modifying it — match existing
  indentation, naming conventions, and patterns
- Never generate a file path, import, or dependency that you have not
  verified exists in the project or its package registry
- When the project has an existing pattern for X (error handling,
  logging, config), use that pattern — do not introduce a competing
  pattern even if yours is "better"
- Keep changes minimal — a bug fix does not need surrounding code
  cleaned up. A new feature does not need extra configurability
- Remove dead code you encounter during related work — do not defer it

**Context Window Hygiene section content:**

- Batch independent operations into single tool calls
- Use targeted file reads (offset + limit) for large files
- Do not re-read files that haven't changed since your last read
- Prefer grep/glob for discovery over reading entire directories

**Collaboration Protocol section content:**

- Ask before taking irreversible actions (push, delete branch, modify
  shared config)
- When a task requires more than 3 attempts, surface the blocker to
  the user instead of iterating silently
- Respect scope boundaries — if dispatched for Phase 3, do not fix
  issues you notice in Phase 5's files
- End every multi-step task with a summary of what changed and what
  verification was performed

### 5.2 New Profile: Rust (full)

**governance-template.md (~120 lines):**

| Section | Key content |
|---------|-------------|
| Ownership & Borrowing | Prefer owned types unless profiling demands refs; never fight the borrow checker with `.clone()` or `unsafe` |
| Error Handling | `thiserror` for libraries, `anyhow` for applications; never `unwrap()` in production; `?` operator for propagation |
| Unsafe Discipline | Every `unsafe` block requires `// SAFETY:` comment; never use `unsafe` to bypass borrow checker |
| Cargo Conventions | Explicit feature flags (never `["full"]`); workspace-level dependency management; `feature` vs `features` typo check |
| Async Runtime | One runtime per binary crate; never nest runtimes; declare at application boundary |
| Testing | `cargo test`, `cargo clippy`, `cargo fmt --check` in CI; `RUSTFLAGS="-Dwarnings"` |
| Linting | `#[deny(clippy::all)]` in CI not source; never `#[deny(warnings)]` (breaks on compiler upgrades) |
| Security | No `unsafe` without documented invariant; validate deserialized data; check for yanked crates |

**Reference docs (3):**

| File | Lines | Content |
|------|-------|---------|
| `rust-anti-patterns.md` | ~250 | Excessive `.unwrap()`/`.clone()`, reaching for `unsafe`, `["full"]` features, lifetime over-annotation, mixing async runtimes |
| `ownership-guide.md` | ~200 | When to own vs borrow, `Cow<>`, interior mutability (`RefCell`/`Mutex`), `Arc` vs `Rc`, lifetime elision rules |
| `testing-rust.md` | ~180 | `#[test]` modules, `tests/` integration tests, `proptest` property-based testing, `mockall` trait mocking, `insta` snapshot testing |

### 5.3 New Profile: TypeScript (full)

**governance-template.md (~110 lines):**

| Section | Key content |
|---------|-------------|
| Strict Mode | `strict: true` in tsconfig; never `any` (use `unknown` + type guards); `noUncheckedIndexedAccess` |
| Async Discipline | Every async call must be `await`ed; no floating promises; `eslint-plugin-promise` |
| Error Handling | Typed error classes, not thrown strings; async error middleware; `express-async-errors` or Fastify native |
| Package Management | `pnpm` preferred; lockfile committed; `--save-exact`; verify packages exist before install |
| Input Validation | Zod/Joi at API boundary; never trust `req.body` directly |
| Exports | Named exports only; explicit barrel files; no `export default` |
| Node.js Patterns | No `process.exit()` in libraries; graceful shutdown handlers; `SIGTERM`/`SIGINT` |
| Security | Prototype pollution prevention; dependency confusion (scoped packages); parameterized queries |

**Reference docs (3):**

| File | Lines | Content |
|------|-------|---------|
| `typescript-anti-patterns.md` | ~250 | Floating promises, `any` abuse, hallucinated npm packages, wrong version patterns, `export default` |
| `node-backend-guide.md` | ~200 | Express/Fastify/Nest middleware, error handling, streaming, graceful shutdown, health checks |
| `testing-vitest.md` | ~180 | Vitest setup, `describe`/`it` conventions, Supertest HTTP testing, mock boundaries, coverage |

### 5.4 New Profile: Perl (starter)

**governance-template.md (~80 lines):**

| Section | Key content |
|---------|-------------|
| Pragmas | `use strict; use warnings;` in every file — non-negotiable |
| File I/O | Three-argument `open` with lexical filehandles; never two-arg `open` (shell injection) |
| OOP | Moo (lightweight) or Moose; never raw `bless {}` |
| Regex Safety | `\Q...\E` for interpolated variables; never raw `$var` in regex patterns |
| Error Handling | `Try::Tiny` or `Syntax::Keyword::Try`; never bare `eval { }; if ($@)` |
| Variable Scope | Avoid `$_` in large scopes; named lexical variables; `my` declarations |
| Security | Taint mode (`-T`) for external input; `\Q\E` in regex; three-arg `open` |
| Testing | `Test2::V0` (preferred) or `Test::More`; `prove -r t/`; `perlcritic` |

### 5.5 New Profile: PHP (starter)

**governance-template.md (~90 lines):**

| Section | Key content |
|---------|-------------|
| Strict Types | `declare(strict_types=1);` in every file |
| SQL Safety | Parameterized queries always; never string-concatenated SQL |
| Mass Assignment | Explicit `$fillable` on models; never `$guarded = []` |
| Query Performance | Eager loading (`with()`); `Model::preventLazyLoading()` in dev |
| Template Safety | `{{ }}` (escaped) not `{!! !!}` (raw); only raw for pre-sanitized trusted HTML |
| Type Declarations | All parameters, return types, properties typed; use PHP 8.1+ enums |
| Dependencies | `composer.lock` committed; `--no-dev` in production; `composer audit` |
| Testing | PHPUnit or Pest; `phpstan analyse --level=max`; `php-cs-fixer` |
| Security | CSRF tokens on forms; file upload validation; `$fillable` not `$guarded` |

### 5.6 New Profile: Infrastructure (starter)

**governance-template.md (~100 lines):**

| Section | Key content |
|---------|-------------|
| Secrets | Never hardcode secrets, IDs, or account numbers; use variables, data sources, or secret managers |
| Terraform | `for_each` over `count`; `moved` blocks on refactors; remote backend with encryption; plan before apply |
| Kubernetes | `resources.requests` AND `resources.limits`; `runAsNonRoot: true`; `readOnlyRootFilesystem: true` |
| Ansible | Purpose-built modules over `shell`/`command`; `no_log: true` for secrets; `--check` mode |
| CI/CD | OIDC for cloud auth, not long-lived credentials; plan-only on PR, apply-only on merge |
| State Management | Remote state backend; state locking; never local state for shared infra |
| Validation | `terraform validate`, `tflint`, `checkov`; `kubeval`/`kubeconform`; `ansible-lint` |
| Versioning | Pin provider versions; pin module versions; document upgrade path |

### 5.7 New Mode: Refactoring

**modes/refactoring/context.md (~60 lines):**

| Section | Content |
|---------|---------|
| Methodology | Behavior preservation — no new features, no bug fixes, no API changes |
| Planner Behavior | Build dependency graph first; identify move/rename/extract operations; every phase has a regression test step |
| Gate Overrides | Minimum Gates 1+2+3 — reviewer always runs with regression pass elevated to blocking |
| Reviewer Focus | Pass 2 (Regression) is blocking; every moved function must have a before/after test |
| Checklist | Tests pass before AND after; no public API changes; no new dependencies; grep for old names |

### 5.8 New Mode: Debugging

**modes/debugging/context.md (~65 lines):**

| Section | Content |
|---------|---------|
| Methodology | Hypothesis-driven — observe, hypothesize, instrument, verify, fix root cause |
| Planner Behavior | Build hypothesis tree; plan instrumentation before fixes; prioritize by evidence, not intuition |
| Gate Overrides | None — development gates apply; reviewer checks root-cause analysis quality |
| Reviewer Focus | Did the fix address root cause or just symptoms? Is there a regression test for the bug? |
| Engineer Behavior | Instrument before fixing; reproduce the bug with a failing test FIRST; never fix without a reproduction case |
| Checklist | Bug reproduced in test; root cause identified with evidence; fix addresses root cause; regression test added |

### 5.9 New Mode: Documentation

**modes/documentation/context.md (~55 lines):**

| Section | Content |
|---------|---------|
| Methodology | Read-then-write — survey public API surface, verify against source, write docs not code |
| Planner Behavior | Inventory undocumented or stale-documented surfaces; prioritize by user impact |
| Gate Overrides | Gate 4 (UAT) elevated — test docs from user perspective |
| Reviewer Focus | Accuracy against source code; completeness; no hallucinated parameters or options |
| Engineer Behavior | Read every function/endpoint before documenting; verify examples run; cross-reference with tests |
| Checklist | Every documented function verified against source; examples tested; no stale version references |

## 5b. Examples

### `rdf init` with auto-detected multiple profiles

```
$ rdf init /root/admin/work/proj/my-webapp
rdf: auto-detected type: python
rdf: auto-detected profiles: python, frontend, database
rdf: initializing: my-webapp (profiles=python,frontend,database)
rdf:   created CLAUDE.md (template=python, merged: frontend, database)
rdf:   created .rdf/{governance,work-output,memory,scopes}
rdf:   added 4 entries to .git/info/exclude
rdf: init complete: my-webapp
```

### `rdf init --type rust,infrastructure`

```
$ rdf init /root/admin/work/proj/my-service --type rust,infrastructure
rdf: initializing: my-service (profiles=rust,infrastructure)
rdf:   created CLAUDE.md (template=rust, merged: infrastructure)
rdf:   created .rdf/{governance,work-output,memory,scopes}
rdf:   reference docs: 3 (from rust profile)
rdf:   added 4 entries to .git/info/exclude
rdf: init complete: my-service
```

### `rdf profile list`

```
$ rdf profile list
FULL PROFILES:
  core           Always active. Commit protocol, verification, security hygiene
  shell          Bash/shell. Quoting, portability, BATS testing
  python         Python. Typing, packaging, pytest, async
  frontend       Web frontend. Components, a11y, CSS, performance
  database       Database. Schema design, migrations, query discipline
  go             Go. Error handling, concurrency, interfaces
  rust           Rust. Ownership, error handling, unsafe discipline
  typescript     TypeScript/Node.js. Strict mode, async, backend patterns

STARTER PROFILES:
  perl           Perl. strict/warnings, three-arg open, Moo/Moose OOP
  php            PHP 8.x. Strict types, PSR, Laravel/Symfony patterns
  infrastructure IaC. Terraform, Kubernetes, Ansible, CI/CD, secrets

Detected in cwd: shell, infrastructure
```

### `/r-mode refactoring`

```
> **Mode switched**
> `development` -> `refactoring`
>
> - **Methodology:** behavior preservation — no new features, no bug fixes
> - **Gate overrides:** reviewer regression pass elevated to *blocking*
> - **Reviewer focus:** every moved function verified with before/after test
```

## 6. Conventions

### 6.1 Governance Template Format

All governance templates follow the same structure:

```markdown
# {Profile Name} Governance Template

> Seed template for /r-init. Merged with codebase scan results during
> governance generation. Not copied verbatim -- scan data overrides
> where conflicts exist.

## {Section Heading}

- Convention bullet (imperative voice)
- Convention bullet
```

### 6.2 Mode Context File Format

All mode context files follow the existing pattern:

```markdown
# {Mode Name} Mode

> {One-line description of what this mode changes.}

## Methodology
## Planner Behavior
## Quality Gate Overrides
## Reviewer Focus
## Checklist
```

### 6.3 Profile Directory Naming

- Lowercase, hyphenated: `typescript`, `infrastructure`, `perl`, `php`
- Match the profile key in `registry.json`

### 6.4 Reference Doc Naming

- Pattern: `{topic}-{type}.md` where type is `anti-patterns`, `guide`,
  `testing-{framework}`
- Examples: `rust-anti-patterns.md`, `ownership-guide.md`,
  `testing-vitest.md`

## 7. Interface Contracts

### 7.1 `_detect_profiles()` function

```
Input:  project path (absolute)
Output: comma-separated profile names to stdout (e.g., "python,frontend,database")
        If no signals match: "minimal"
        core is always implicit (never listed in output)
```

### 7.2 `--type` flag change

```
Old: --type TYPE     (single value: shell|lib|frontend|security|minimal)
New: --type PROFILES (comma-separated: rust,infrastructure|python,database|shell)
     Single values still work (backward compatible)
     "lib" maps to "shell" (existing behavior preserved)
     "minimal" means core-only (no language profile)
     "security" removed (was already deprecated — use /r-mode security)
```

### 7.3 `registry.json` schema

New required fields per profile:
- `tier`: `"full"` | `"starter"`
- `detect`: array of glob patterns (strings)

Existing fields unchanged: `requires`, `removable`, `description`,
`summary`.

### 7.4 Mode aliases

```
refactoring → refactor (alias)
debugging → debug (alias)
documentation → docs (alias)
```

## 8. Migration Safety

### 8.1 Backward Compatibility

- **Single `--type` values** continue working: `--type shell` produces
  the same governance as before
- **Existing projects** are unaffected: `rdf init` on a project that
  already has governance still refuses (directs to `/r-refresh`)
- **Existing registry.json consumers** tolerate new fields (JSON is
  additive)
- **Existing modes** unchanged: development, security, performance,
  migration context files not modified

### 8.2 Test Suite Impact

No BATS test suites exist for `rdf init`. Testing is manual
verification + shellcheck. Future: `tests/init.bats` with profile
detection test cases.

### 8.3 Upgrade Path

Existing projects don't need to re-run `rdf init`. The new profiles
and modes are available for new projects and `rdf init --force`
regeneration on existing ones.

## 9. Dead Code and Cleanup

| Finding | Location | Action |
|---------|----------|--------|
| `security` type in `_type_to_profile()` | `lib/cmd/init.sh:67` | Remove — already warns and returns `core` |
| `security` type in `_type_to_template()` | `lib/cmd/init.sh:80` | Remove — template doesn't exist |
| `security` in type validation | `lib/cmd/init.sh:384` | Remove from valid types list |
| `detection-rules.md` in profiles/ | `profiles/detection-rules.md` | Update — add 5 new profile detection signals |
| `_type_to_template()` function | `lib/cmd/init.sh:74-83` | Remove — maps to `.md.tmpl` files that don't exist on disk; current system always hits minimal fallback |
| `_type_to_profile()` function | `lib/cmd/init.sh:61-71` | Replace — single-type mapping becomes multi-profile lookup |
| Template file convention (`*.md.tmpl`) | `profiles/*/templates/` | Dead — no template files exist; `_generate_claude_md()` always falls through to minimal inline generation |

## 10a. Test Strategy

| Goal | Test approach | Verification |
|------|--------------|-------------|
| Goal 1: 5 new profiles exist | Check directory structure | `ls profiles/{rust,typescript,perl,php,infrastructure}/governance-template.md` |
| Goal 2: 3 new modes exist | Check mode context files | `ls modes/{refactoring,debugging,documentation}/context.md` |
| Goal 3: Core template expanded | Line count check | `wc -l profiles/core/governance-template.md` >= 120 |
| Goal 4: Stackable detection | Run detection on multi-domain project | `_detect_profiles /path/to/python-react-project` returns "python,frontend" |
| Goal 5: Registry updated | JSON schema check | `jq '.profiles.rust.tier' profiles/registry.json` returns "full" |
| Goal 6: `rdf init` handles multi-profile | Init a test project with multiple signals | Governance template contains sections from all detected profiles |
| Goal 7: r-mode shows new modes | Check mode table | `grep -c 'refactoring\|debugging\|documentation' canonical/commands/r-mode.md` >= 3 |
| Goal 8: No breaking changes | Run existing init on shell project | Same governance output as before |

## 10b. Verification Commands

```bash
# Goal 1: new profile directories exist
ls profiles/rust/governance-template.md profiles/typescript/governance-template.md \
   profiles/perl/governance-template.md profiles/php/governance-template.md \
   profiles/infrastructure/governance-template.md
# expect: all 5 files listed, no errors

# Goal 1b: full profiles have reference docs
ls profiles/rust/reference/ profiles/typescript/reference/
# expect: 3 files each

# Goal 2: new modes exist
ls modes/refactoring/context.md modes/debugging/context.md modes/documentation/context.md
# expect: all 3 files listed

# Goal 3: core template expanded
wc -l profiles/core/governance-template.md
# expect: >= 120

# Goal 5: registry has new profiles with tier+detect fields
jq '.profiles | keys | length' profiles/registry.json
# expect: 11

jq '.profiles.rust.tier' profiles/registry.json
# expect: "full"

jq '.profiles.infrastructure.detect' profiles/registry.json
# expect: ["*.tf", "Dockerfile", "k8s/", "ansible/"]

# Goal 7: r-mode shows new modes
grep -c 'refactoring\|debugging\|documentation' canonical/commands/r-mode.md
# expect: >= 3

# Goal 8: backward compat — shell detection still works
grep -A2 '_detect_project_type\|_detect_profiles' lib/cmd/init.sh | head -10
# expect: new function name, shell detection logic present
```

## 11. Risks

1. **Governance template merge produces incoherent output.** When
   merging shell + infrastructure templates, section ordering may be
   confusing or contradictory.
   **Mitigation:** Merge appends by section heading with `core` first.
   Low-confidence report flags merged sections for user review.

2. **LLM ignores profile-specific governance.** Governance templates
   are advisory — the LLM reads them but may not follow them.
   **Mitigation:** This is an inherent limitation of prompt-based
   governance. Verification commands and anti-pattern greps catch the
   most critical violations.

3. **Starter profile governance templates are too thin to be useful.**
   80-100 lines may not provide enough depth for meaningful governance.
   **Mitigation:** Focus on the top 5-8 conventions that prevent the
   most common LLM mistakes per language. Starter profiles can
   graduate to full profiles in future versions.

4. **Detection false positives.** A project with a single `Dockerfile`
   gets infrastructure profile even if it's a simple build container.
   **Mitigation:** Infrastructure is priority-3 (only included if a
   language signal also matches). Standalone Dockerfile without any
   language files → `minimal` not `infrastructure`.

## 11b. Edge Cases

| # | Scenario | Expected behavior | Handling |
|---|----------|-------------------|---------|
| 1 | Project has only a Dockerfile, no language files | Detect as `minimal`, not `infrastructure` | Infrastructure requires a priority-1 match to activate |
| 2 | `--type shell,rust` — conflicting language profiles | Both included, merge both templates | Template merge appends sections; conflicts flagged |
| 3 | Project has `.ts` files but only `.d.ts` type declarations | Do not detect as TypeScript | Detection checks for non-declaration `.ts` files |
| 4 | Existing project re-runs `rdf init` (governance exists) | Refuse, direct to `/r-refresh` or `--force` | Same as current behavior, unchanged |
| 5 | `--type` specifies a profile not in `registry.json` | Error: unknown profile name | Validate against registry before proceeding |
| 6 | Perl project with `.pl` files in `scripts/` subdirectory | Detect as Perl if `.pl`/`.pm` files exist anywhere in git-tracked tree | Use `git ls-files '*.pl' '*.pm'` for detection |
| 7 | PHP project with `composer.json` but no `.php` files | Detect as PHP (composer.json is sufficient) | Single signal suffices for priority-1 profiles |
| 8 | Project matches 4+ profiles simultaneously | All detected, all merged | Template merge handles N profiles; reference docs from all copied |
| 9 | Mode alias used: `/r-mode debug` | Resolve to `debugging` mode | Alias table in r-mode.md |
| 10 | `rdf profile list` on project with no `.git` | Show all profiles, skip detection | Detection requires git; list shows registry only |

## 12. Open Questions

None — all decisions resolved during brainstorming.

## Phase Decomposition Guidance

1. **Core template expansion** — modify `profiles/core/governance-template.md`
2. **Create 5 new profile directories** — governance templates + reference docs
3. **Create 3 new mode context files**
4. **Update registry.json and registry.md** — add profiles, tier, detect fields
5. **Update init.sh** — `_detect_profiles()`, multi-profile merge, `--type` comma support
6. **Update r-init.md and r-mode.md** — document new profiles and modes
7. **Update README.md** — badge count, profiles table, modes
8. **Verify and push**
