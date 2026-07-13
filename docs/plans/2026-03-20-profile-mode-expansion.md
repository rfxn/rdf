# Implementation Plan: Profile & Mode Expansion

**Goal:** Add 5 new profiles (Rust, TypeScript, Perl, PHP, Infrastructure), 3 new
modes (refactoring, debugging, documentation), expand the core governance template
with AI agent discipline, and make profiles stackable with multi-signal auto-detection.

**Architecture:** Content-first — create all profile/mode files before touching CLI
code. Registry update enables detection. CLI changes last since they consume the
registry. Profiles and modes are independent tracks that can parallelize.

**Tech Stack:** Markdown content files, JSON registry, Bash 4.1+ CLI (`lib/cmd/init.sh`)

**Spec:** `docs/specs/2026-03-20-profile-mode-expansion-design.md`

**Phases:** 8

---

## Conventions

**Commit message format** (RDF — free-form descriptive):
```
{Description}

[New] description
[Change] description
[Remove] description
```

**CRITICAL:**
- Never `git add -A` or `git add .` — stage files explicitly by name
- Never commit PLAN.md, CLAUDE.md, MEMORY.md, .claude/, .rdf/
- Governance template boilerplate for new profiles:
  ```markdown
  # {Profile Name} Governance Template

  > Seed template for /r-init. Merged with codebase scan results during
  > governance generation. Not copied verbatim -- scan data overrides
  > where conflicts exist.
  ```
- Mode context file boilerplate:
  ```markdown
  # {Mode Name} Mode

  > {One-line description.}

  ## Methodology
  ## Planner Behavior
  ## Quality Gate Overrides
  ## Reviewer Focus
  ## Checklist
  ```
- **No-touch files:** existing profile governance templates (shell, python,
  frontend, database, go), existing mode context files (development,
  security-assessment, performance-audit, migration)

---

## File Map

### New Files
| File | Est. Lines | Purpose | Test |
|------|-----------|---------|------|
| `profiles/rust/governance-template.md` | ~120 | Rust conventions | N/A (governance content) |
| `profiles/rust/reference/rust-anti-patterns.md` | ~250 | LLM-specific Rust pitfalls | N/A (reference doc) |
| `profiles/rust/reference/ownership-guide.md` | ~200 | Ownership/borrowing decisions | N/A (reference doc) |
| `profiles/rust/reference/testing-rust.md` | ~180 | cargo test, proptest, mockall | N/A (reference doc) |
| `profiles/typescript/governance-template.md` | ~110 | TS backend conventions | N/A (governance content) |
| `profiles/typescript/reference/typescript-anti-patterns.md` | ~250 | Floating promises, any abuse | N/A (reference doc) |
| `profiles/typescript/reference/node-backend-guide.md` | ~200 | Express/Fastify patterns | N/A (reference doc) |
| `profiles/typescript/reference/testing-vitest.md` | ~180 | Vitest/Jest, Supertest | N/A (reference doc) |
| `profiles/perl/governance-template.md` | ~80 | Modern Perl conventions | N/A (governance content) |
| `profiles/php/governance-template.md` | ~90 | PHP 8.x, PSR, security | N/A (governance content) |
| `profiles/infrastructure/governance-template.md` | ~100 | Terraform, K8s, Ansible | N/A (governance content) |
| `modes/refactoring/context.md` | ~60 | Behavior preservation mode | N/A (mode context) |
| `modes/debugging/context.md` | ~65 | Hypothesis-driven debugging | N/A (mode context) |
| `modes/documentation/context.md` | ~55 | Read-then-write docs mode | N/A (mode context) |

### Modified Files
| File | Changes | Test |
|------|---------|------|
| `profiles/core/governance-template.md` | Expand 62→~140 lines (AI agent sections) | N/A (governance content) |
| `profiles/registry.json` | Add 5 profiles, add `tier`+`detect` fields | `jq` validation |
| `profiles/registry.md` | Update tables for new profiles | N/A (docs) |
| `profiles/detection-rules.md` | Add 5 new profile detection signals | N/A (docs) |
| `lib/cmd/init.sh` | `_detect_profiles()`, merge logic, `--type` comma support | `bash -n`, manual verify |
| `canonical/commands/r-init.md` | Document multi-profile detection | N/A (command content) |
| `canonical/commands/r-mode.md` | Add 3 new modes to table + aliases | N/A (command content) |
| `README.md` | Badge count, profiles table, modes | N/A (docs) |
| `CHANGELOG` | New entries | N/A (docs) |
| `CHANGELOG.RELEASE` | New entries | N/A (docs) |

### Deleted Code
| Code | Location | Reason |
|------|----------|--------|
| `_type_to_template()` | `lib/cmd/init.sh:74-83` | Dead — maps to `.md.tmpl` files that don't exist |
| `security` type handling | `lib/cmd/init.sh:67,80,384` | Dead — already deprecated, warns and returns core |

## Phase Dependencies

```
Phase 1 (core template)
  ├──► Phase 2 (full profiles: rust, typescript)     ← parallel
  ├──► Phase 3 (starter profiles: perl, php, infra)  ← parallel
  ├──► Phase 4 (modes: refactoring, debugging, docs) ← parallel
  │
  ├──► [wait for 2+3+4] ──► Phase 5 (registry + detection-rules)
  │                            └──► Phase 6 (init.sh CLI changes)
  │                                   └──► Phase 7 (commands + docs)
  └──────────────────────────────────────► Phase 8 (verify, push)
```

Phases 2, 3, 4 are independent content creation — can run in parallel.
Phase 5 waits for all three since registry references the new profiles.

---

### Phase 1: Expand core governance template

Add AI Agent Discipline, Code Generation Standards, Context Window
Hygiene, and Collaboration Protocol sections to the core template
that seeds every project.

**Files:**
- Modify: `profiles/core/governance-template.md` (62→~140 lines)

- **Mode**: serial-context
- **Risk**: low
- **Type**: feature
- **Gates**: G1
- **Accept**: `wc -l profiles/core/governance-template.md` >= 120;
  `grep -c 'AI Agent\|Code Generation\|Context Window\|Collaboration' profiles/core/governance-template.md` >= 4
- **Test**: `wc -l` >= 120, grep for 4 new section headings
- **Edge cases**: none

- [ ] **Step 1: Add AI Agent Discipline section**

  After the existing `## Session Safety` section (end of file, line 63),
  append:

  ```markdown
  ## AI Agent Discipline

  - Verify every function, API, and import exists before using it --
    hallucinated imports are the #1 AI coding failure mode
  - Never generate code for a file you haven't read -- inferred
    patterns diverge from actual patterns after the first few files
  - When unsure, state uncertainty explicitly -- "I believe X but
    haven't verified" is more useful than confident wrong answers
  - Grep the codebase before introducing a new helper -- the function
    you need probably already exists under a different name
  - After making changes, verify with the project's verification
    commands, not by re-reading your own output
  - Do not add defensive code for scenarios that cannot happen --
    trust framework guarantees and validated input at boundaries
  - When a fix doesn't work after three attempts, step back and
    reconsider the approach -- do not layer workarounds
  - Never forward-copy values from prior state files -- always read
    from source (git, grep, file reads) for current values

  ## Code Generation Standards

  - Read the target file before modifying it -- match existing
    indentation, naming conventions, and patterns exactly
  - Never generate a file path, import, or dependency without
    verifying it exists in the project or its package registry
  - When the project has an existing pattern for X (error handling,
    logging, config), use that pattern -- do not introduce a competing
    approach even if yours is theoretically better
  - Keep changes minimal -- a bug fix does not need surrounding code
    cleaned up. A new feature does not need extra configurability
  - Remove dead code encountered during related work -- do not defer
  - Search for existing helpers before writing new logic -- call
    them, do not re-implement

  ## Context Window Hygiene

  - Batch independent tool calls into single messages
  - Use targeted file reads (offset + limit) for large files
  - Do not re-read files that haven't changed since your last read
  - Prefer grep/glob for discovery over reading entire directories
  - Push repetitive data gathering into shell scripts that return
    structured output (JSON)

  ## Collaboration Protocol

  - Ask before taking irreversible actions (push, delete, modify
    shared config) -- the cost of pausing is low, the cost of an
    unwanted action is high
  - When a task requires more than 3 failed attempts, surface the
    blocker to the user instead of iterating silently
  - Respect scope boundaries -- if dispatched for Phase 3, do not
    fix issues in Phase 5's files
  - End every multi-step task with a summary of what changed and
    what verification was performed
  ```

- [ ] **Step 2: Verify**

  ```bash
  wc -l profiles/core/governance-template.md
  # expect: >= 120

  grep -c '## AI Agent Discipline\|## Code Generation Standards\|## Context Window Hygiene\|## Collaboration Protocol' profiles/core/governance-template.md
  # expect: 4
  ```

- [ ] **Step 3: Commit**

  ```bash
  git add profiles/core/governance-template.md
  git commit -m "$(cat <<'EOF'
  Expand core governance template with AI agent discipline

  [New] AI Agent Discipline: hallucination awareness, verification habits, confidence calibration
  [New] Code Generation Standards: read-before-write, pattern matching, minimal changes
  [New] Context Window Hygiene: batching, targeted reads, structured output
  [New] Collaboration Protocol: scope boundaries, irreversible action gates, failure escalation
  EOF
  )"
  ```

---

### Phase 2: Create full profiles (Rust, TypeScript)

Create governance templates and reference docs for Rust and TypeScript.
These are full-tier profiles with 3 reference docs each.

**Files:**
- Create: `profiles/rust/governance-template.md`
- Create: `profiles/rust/reference/rust-anti-patterns.md`
- Create: `profiles/rust/reference/ownership-guide.md`
- Create: `profiles/rust/reference/testing-rust.md`
- Create: `profiles/typescript/governance-template.md`
- Create: `profiles/typescript/reference/typescript-anti-patterns.md`
- Create: `profiles/typescript/reference/node-backend-guide.md`
- Create: `profiles/typescript/reference/testing-vitest.md`

- **Mode**: parallel-agent
- **Risk**: low
- **Type**: feature
- **Gates**: G1
- **Accept**: all 8 files exist and are non-empty;
  `wc -l profiles/rust/governance-template.md` >= 100;
  `wc -l profiles/typescript/governance-template.md` >= 90;
  each reference doc >= 150 lines
- **Test**: `ls profiles/rust/governance-template.md profiles/rust/reference/*.md profiles/typescript/governance-template.md profiles/typescript/reference/*.md` — all exist;
  `wc -l` checks on each file
- **Edge cases**: none

**File ownership boundaries:**
- Track A (Rust): `profiles/rust/` — all files
- Track B (TypeScript): `profiles/typescript/` — all files

- [ ] **Step 1: Create Rust profile directory and governance template**

  Create `profiles/rust/governance-template.md` (~120 lines) with sections:
  Ownership & Borrowing, Error Handling, Unsafe Discipline, Cargo
  Conventions, Async Runtime, Testing, Linting, Security.

  Content sourced from spec Section 5.2 and the profile research data.
  Use the convention boilerplate from this plan's Conventions section.

- [ ] **Step 2: Create Rust reference docs**

  Create 3 files in `profiles/rust/reference/`:
  - `rust-anti-patterns.md` (~250 lines): excessive unwrap/clone, reaching
    for unsafe, full feature flags, lifetime over-annotation, mixed runtimes
  - `ownership-guide.md` (~200 lines): own vs borrow decisions, Cow,
    interior mutability, Arc vs Rc, lifetime elision
  - `testing-rust.md` (~180 lines): #[test] modules, integration tests,
    proptest, mockall, insta snapshot testing

- [ ] **Step 3: Create TypeScript profile directory and governance template**

  Create `profiles/typescript/governance-template.md` (~110 lines) with
  sections: Strict Mode, Async Discipline, Error Handling, Package
  Management, Input Validation, Exports, Node.js Patterns, Security.

  Content sourced from spec Section 5.3 and the profile research data.

- [ ] **Step 4: Create TypeScript reference docs**

  Create 3 files in `profiles/typescript/reference/`:
  - `typescript-anti-patterns.md` (~250 lines): floating promises, any
    abuse, hallucinated npm packages, wrong version patterns, export default
  - `node-backend-guide.md` (~200 lines): Express/Fastify/Nest middleware,
    error handling, streaming, graceful shutdown, health checks
  - `testing-vitest.md` (~180 lines): Vitest setup, describe/it, Supertest
    HTTP testing, mock boundaries, coverage

- [ ] **Step 5: Verify**

  ```bash
  ls profiles/rust/governance-template.md profiles/rust/reference/*.md
  # expect: 4 files listed

  ls profiles/typescript/governance-template.md profiles/typescript/reference/*.md
  # expect: 4 files listed

  wc -l profiles/rust/governance-template.md
  # expect: >= 100

  wc -l profiles/typescript/governance-template.md
  # expect: >= 90
  ```

- [ ] **Step 6: Commit**

  ```bash
  git add profiles/rust/governance-template.md \
        profiles/rust/reference/rust-anti-patterns.md \
        profiles/rust/reference/ownership-guide.md \
        profiles/rust/reference/testing-rust.md \
        profiles/typescript/governance-template.md \
        profiles/typescript/reference/typescript-anti-patterns.md \
        profiles/typescript/reference/node-backend-guide.md \
        profiles/typescript/reference/testing-vitest.md
  git commit -m "$(cat <<'EOF'
  Add Rust and TypeScript full profiles

  [New] profiles/rust/: governance template + 3 reference docs (anti-patterns, ownership, testing)
  [New] profiles/typescript/: governance template + 3 reference docs (anti-patterns, node backend, testing)
  EOF
  )"
  ```

---

### Phase 3: Create starter profiles (Perl, PHP, Infrastructure)

Create governance templates only (no reference docs) for the three
starter-tier profiles.

**Files:**
- Create: `profiles/perl/governance-template.md`
- Create: `profiles/php/governance-template.md`
- Create: `profiles/infrastructure/governance-template.md`

- **Mode**: serial-agent
- **Risk**: low
- **Type**: feature
- **Gates**: G1
- **Accept**: all 3 files exist; `wc -l profiles/perl/governance-template.md` >= 70;
  `wc -l profiles/php/governance-template.md` >= 80;
  `wc -l profiles/infrastructure/governance-template.md` >= 90
- **Test**: `ls profiles/{perl,php,infrastructure}/governance-template.md` — all exist;
  `wc -l` checks on each
- **Edge cases**: none

- [ ] **Step 1: Create Perl governance template**

  Create `profiles/perl/governance-template.md` (~80 lines) with sections:
  Pragmas, File I/O, OOP, Regex Safety, Error Handling, Variable Scope,
  Security, Testing.

  Content sourced from spec Section 5.4 and the profile research data.

- [ ] **Step 2: Create PHP governance template**

  Create `profiles/php/governance-template.md` (~90 lines) with sections:
  Strict Types, SQL Safety, Mass Assignment, Query Performance, Template
  Safety, Type Declarations, Dependencies, Testing, Security.

  Content sourced from spec Section 5.5 and the profile research data.

- [ ] **Step 3: Create Infrastructure governance template**

  Create `profiles/infrastructure/governance-template.md` (~100 lines) with
  sections: Secrets, Terraform, Kubernetes, Ansible, CI/CD, State Management,
  Validation, Versioning.

  Content sourced from spec Section 5.6 and the profile research data.

- [ ] **Step 4: Verify**

  ```bash
  ls profiles/perl/governance-template.md profiles/php/governance-template.md \
     profiles/infrastructure/governance-template.md
  # expect: 3 files listed

  wc -l profiles/perl/governance-template.md profiles/php/governance-template.md \
       profiles/infrastructure/governance-template.md
  # expect: perl >= 70, php >= 80, infrastructure >= 90
  ```

- [ ] **Step 5: Commit**

  ```bash
  git add profiles/perl/governance-template.md \
        profiles/php/governance-template.md \
        profiles/infrastructure/governance-template.md
  git commit -m "$(cat <<'EOF'
  Add Perl, PHP, and Infrastructure starter profiles

  [New] profiles/perl/: governance template — strict/warnings, three-arg open, Moo OOP, taint mode
  [New] profiles/php/: governance template — strict_types, PSR, parameterized queries, Laravel patterns
  [New] profiles/infrastructure/: governance template — Terraform, Kubernetes, Ansible, secrets, CI/CD
  EOF
  )"
  ```

---

### Phase 4: Create new modes (refactoring, debugging, documentation)

Create three new operational mode context files following the existing
pattern established by development, security-assessment, etc.

**Files:**
- Create: `modes/refactoring/context.md`
- Create: `modes/debugging/context.md`
- Create: `modes/documentation/context.md`

- **Mode**: serial-agent
- **Risk**: low
- **Type**: feature
- **Gates**: G1
- **Accept**: all 3 files exist; each follows the standard mode format
  (Methodology, Planner Behavior, Quality Gate Overrides, Reviewer Focus, Checklist)
- **Test**: `ls modes/{refactoring,debugging,documentation}/context.md` — all exist;
  `grep -c '## Methodology' modes/refactoring/context.md` = 1
- **Edge cases**: EC9 (mode alias `/r-mode debug` → `debugging`)

- [ ] **Step 1: Create refactoring mode**

  Create `modes/refactoring/context.md` (~60 lines) with content from
  spec Section 5.7: behavior preservation methodology, dependency graph
  focus, G1+G2+G3 minimum gates, regression pass blocking, checklist.

- [ ] **Step 2: Create debugging mode**

  Create `modes/debugging/context.md` (~65 lines) with content from
  spec Section 5.8: hypothesis-driven methodology, instrument-before-fix,
  default development gates, root-cause reviewer focus, checklist.

- [ ] **Step 3: Create documentation mode**

  Create `modes/documentation/context.md` (~55 lines) with content from
  spec Section 5.9: read-then-write methodology, API surface survey,
  G4 (UAT) elevated, accuracy reviewer focus, checklist.

- [ ] **Step 4: Verify**

  ```bash
  ls modes/refactoring/context.md modes/debugging/context.md modes/documentation/context.md
  # expect: 3 files listed

  for f in modes/refactoring/context.md modes/debugging/context.md modes/documentation/context.md; do
    echo "$(basename $(dirname $f)): $(grep -c '## ' "$f") sections"
  done
  # expect: each has >= 5 sections
  ```

- [ ] **Step 5: Commit**

  ```bash
  git add modes/refactoring/context.md modes/debugging/context.md \
        modes/documentation/context.md
  git commit -m "$(cat <<'EOF'
  Add refactoring, debugging, and documentation modes

  [New] modes/refactoring/: behavior preservation, regression pass blocking, no new features
  [New] modes/debugging/: hypothesis-driven, instrument-first, root cause focus
  [New] modes/documentation/: read-then-write, API surface survey, accuracy review
  EOF
  )"
  ```

---

### Phase 5: Update registry and detection rules

Add 5 new profiles to `registry.json` with `tier` and `detect` fields.
Update `registry.md` and `detection-rules.md` to match.

**Files:**
- Modify: `profiles/registry.json`
- Modify: `profiles/registry.md`
- Modify: `profiles/detection-rules.md`

- **Mode**: serial-context
- **Risk**: low
- **Type**: config
- **Gates**: G1
- **Accept**: `jq '.profiles | keys | length' profiles/registry.json` = 11;
  `jq '.profiles.rust.tier' profiles/registry.json` = `"full"`;
  `jq '.profiles.rust.detect' profiles/registry.json` returns array;
  all existing profiles also have `tier` and `detect` fields
- **Test**: `jq` validation commands with expected output; `grep -c 'rust\|typescript\|perl\|php\|infrastructure' profiles/detection-rules.md` >= 5
- **Edge cases**: EC5 (unknown profile name validation), EC7 (composer.json is sufficient for PHP)

- [ ] **Step 1: Update registry.json — add 5 new profiles + tier/detect to all**

  Add `tier` and `detect` fields to existing profiles:
  ```json
  "core": { ..., "tier": "full", "detect": [] }
  "shell": { ..., "tier": "full", "detect": ["*.sh", "*.bash", "files/", ".bats"] }
  "python": { ..., "tier": "full", "detect": ["pyproject.toml", "requirements.txt", "*.py"] }
  "frontend": { ..., "tier": "full", "detect": ["*.tsx", "*.jsx", "*.vue", "package.json"] }
  "database": { ..., "tier": "full", "detect": ["*.sql", "migrations/", "schema.prisma"] }
  "go": { ..., "tier": "full", "detect": ["go.mod", "*.go"] }
  ```

  Add 5 new profile entries:
  ```json
  "rust": {
    "requires": ["core"], "removable": true, "tier": "full",
    "detect": ["Cargo.toml", "*.rs"],
    "description": "Rust projects. Ownership, error handling, unsafe discipline, cargo conventions",
    "summary": "governance-template + 3 reference docs"
  },
  "typescript": {
    "requires": ["core"], "removable": true, "tier": "full",
    "detect": ["tsconfig.json", "*.ts"],
    "description": "TypeScript/Node.js. Strict mode, async discipline, backend patterns",
    "summary": "governance-template + 3 reference docs"
  },
  "perl": {
    "requires": ["core"], "removable": true, "tier": "starter",
    "detect": ["cpanfile", "Makefile.PL", "*.pl", "*.pm"],
    "description": "Perl projects. strict/warnings, three-arg open, Moo/Moose OOP",
    "summary": "governance-template only"
  },
  "php": {
    "requires": ["core"], "removable": true, "tier": "starter",
    "detect": ["composer.json", "*.php"],
    "description": "PHP 8.x. Strict types, PSR standards, Laravel/Symfony patterns",
    "summary": "governance-template only"
  },
  "infrastructure": {
    "requires": ["core"], "removable": true, "tier": "starter",
    "detect": ["*.tf", "Dockerfile", "k8s/", "ansible/"],
    "description": "Infrastructure as code. Terraform, Kubernetes, Ansible, CI/CD",
    "summary": "governance-template only"
  }
  ```

- [ ] **Step 2: Update registry.md**

  Add 5 new profiles to the Active Profiles table. Remove the "Future
  Profiles" section (rust is no longer future). Update the Composition
  section to describe stackable multi-profile model.

- [ ] **Step 3: Update detection-rules.md**

  Add detection signal blocks for rust, typescript, perl, php, and
  infrastructure, following the existing format (### heading, "Activate
  when ANY of:", bullet list of signals, confidence boost section).

  For infrastructure: note priority-3 rule (only activates if a
  priority-1 language signal also matches).

- [ ] **Step 4: Verify**

  ```bash
  jq '.profiles | keys | length' profiles/registry.json
  # expect: 11

  jq '.profiles.rust.tier' profiles/registry.json
  # expect: "full"

  jq '.profiles.perl.tier' profiles/registry.json
  # expect: "starter"

  jq '.profiles.infrastructure.detect' profiles/registry.json
  # expect: ["*.tf","Dockerfile","k8s/","ansible/"]

  # All profiles have tier and detect fields
  jq '[.profiles[] | has("tier","detect")] | all' profiles/registry.json
  # expect: true

  grep -c '### rust\|### typescript\|### perl\|### php\|### infrastructure' profiles/detection-rules.md
  # expect: 5
  ```

- [ ] **Step 5: Commit**

  ```bash
  git add profiles/registry.json profiles/registry.md profiles/detection-rules.md
  git commit -m "$(cat <<'EOF'
  Update profile registry with 5 new profiles, tier, and detect fields

  [New] registry.json: rust, typescript, perl, php, infrastructure profiles
  [New] registry.json: tier (full/starter) and detect (glob array) fields on all profiles
  [Change] registry.md: add new profiles to Active Profiles table, remove Future Profiles
  [Change] detection-rules.md: add detection signals for 5 new profiles
  EOF
  )"
  ```

---

### Phase 6: Update init.sh for multi-profile detection and merge

Replace `_detect_project_type()` with `_detect_profiles()`, add
governance template merge logic, support comma-separated `--type`,
remove dead code.

**Files:**
- Modify: `lib/cmd/init.sh`

- **Mode**: serial-agent
- **Risk**: medium
- **Type**: feature
- **Gates**: G1+G2
- **Accept**: `bash -n lib/cmd/init.sh` passes;
  `_detect_profiles()` function exists; `_type_to_template()` removed;
  `--type rust,infrastructure` accepted without error
- **Test**: `bash -n lib/cmd/init.sh`; `grep -c '_detect_profiles' lib/cmd/init.sh` >= 1;
  `grep -c '_type_to_template' lib/cmd/init.sh` = 0
- **Edge cases**: EC1 (Dockerfile-only → minimal), EC2 (conflicting profiles → merge both,
  flag conflicts), EC3 (.d.ts-only → not TypeScript), EC5 (unknown profile → error),
  EC6 (Perl .pl in subdirectory → detected via git ls-files), EC8 (4+ profiles → all merged),
  EC10 (rdf profile list without git → show registry only)

- [ ] **Step 1: Replace `_detect_project_type()` with `_detect_profiles()`**

  Remove the existing `_detect_project_type()` function (lines 38-58).
  Replace with `_detect_profiles()` that reads `registry.json` detect
  fields and checks the project for matching signals. Returns
  comma-separated list (e.g., `"python,frontend,database"`).

  The function should:
  - Read `profiles/registry.json` for detect patterns per profile
  - Use `git ls-files` when in a git repo for file extension checks
  - Fall back to `find` for non-git directories
  - Apply priority rules: priority-1 (language) always, priority-3
    (infrastructure) only if a language match exists
  - Skip `.d.ts` files for TypeScript detection (EC3)
  - Return `"minimal"` if no signals match

  > Self-correction note: `jq` is not guaranteed on CentOS 6. Hardcode
  > detection logic in bash (like the current `_detect_project_type()`),
  > using `registry.json` only for `rdf profile list` display. The
  > detection function uses file-existence checks and glob matching,
  > not JSON parsing at runtime.

- [ ] **Step 2: Replace `_type_to_profile()` and `_type_to_template()`**

  Remove `_type_to_profile()` (lines 61-71) — no longer needed, profile
  names come directly from `_detect_profiles()`.

  Remove `_type_to_template()` (lines 74-83) — dead code, template files
  don't exist on disk.

  Remove `security` type handling (line 67 warning, line 80 template
  mapping, line 384 validation).

- [ ] **Step 3: Rewrite `_generate_claude_md()` for template merge**

  Replace the current template file lookup (lines 196-259) with a merge
  system that:
  1. Reads `profiles/core/governance-template.md` as base
  2. For each detected profile, reads its `governance-template.md`
  3. Merges by `## ` heading: same heading → concatenate with
     `<!-- from: {profile} -->` marker, unique heading → append
  4. Writes merged output to `{path}/CLAUDE.md`

  > Self-correction note: the current `_generate_claude_md()` uses sed
  > for template variable substitution ({{PROJECT_NAME}}, etc.). The new
  > merge system doesn't use template variables — governance templates
  > are project-agnostic. The project-specific header (name, version)
  > should be generated inline before the merged template content.

- [ ] **Step 4: Update `cmd_init()` argument parsing for comma-separated --type**

  Change the `--type` validation (line 382-387) to accept
  comma-separated values: `--type rust,infrastructure`.

  Split on comma, validate each against `registry.json` profile keys.

  Update `_init_one()` to accept a profile list instead of a single type.

- [ ] **Step 5: Copy reference docs for detected profiles**

  In `_init_one()`, after generating CLAUDE.md, copy reference docs
  from all detected profiles that have a `reference/` directory:
  ```bash
  command mkdir -p "${path}/.rdf/governance/reference"
  for profile in ${profiles//,/ }; do
    local ref_dir="${RDF_HOME}/profiles/${profile}/reference"
    if [[ -d "$ref_dir" ]]; then
      command cp -a "${ref_dir}/." "${path}/.rdf/governance/reference/"
    fi
  done
  ```

- [ ] **Step 6: Verify**

  ```bash
  bash -n lib/cmd/init.sh
  # expect: exit 0

  grep -c '_detect_profiles' lib/cmd/init.sh
  # expect: >= 1

  grep -c '_type_to_template' lib/cmd/init.sh
  # expect: 0

  grep -c '_detect_project_type' lib/cmd/init.sh
  # expect: 0

  grep 'security.*removed\|security.*deprecated' lib/cmd/init.sh
  # expect: 0 (security type fully removed, not just deprecated)
  ```

- [ ] **Step 7: Commit**

  ```bash
  git add lib/cmd/init.sh
  git commit -m "$(cat <<'EOF'
  Rewrite init.sh for multi-profile detection and governance merge

  [New] _detect_profiles(): auto-detect multiple profiles from project signals
  [New] Governance template merge: core + detected profiles merged by section heading
  [New] --type accepts comma-separated profiles (rust,infrastructure)
  [New] Reference doc copying from all detected profiles with reference/ dirs
  [Remove] _detect_project_type(): replaced by _detect_profiles()
  [Remove] _type_to_template(): dead code — template files never existed on disk
  [Remove] _type_to_profile(): replaced by direct profile name usage
  [Remove] security type: fully removed (was deprecated, use /r-mode security)
  EOF
  )"
  ```

---

### Phase 7: Update canonical commands and documentation

Update r-init.md, r-mode.md, README.md, CHANGELOG, and
CHANGELOG.RELEASE for the new profiles and modes.

**Files:**
- Modify: `canonical/commands/r-init.md`
- Modify: `canonical/commands/r-mode.md`
- Modify: `README.md`
- Modify: `CHANGELOG`
- Modify: `CHANGELOG.RELEASE`

- **Mode**: serial-context
- **Risk**: low
- **Type**: config
- **Gates**: G1
- **Accept**: `grep -c 'multi-profile\|comma-separated\|_detect_profiles' canonical/commands/r-init.md` >= 2;
  `grep -c 'refactoring\|debugging\|documentation' canonical/commands/r-mode.md` >= 3;
  README profile count badge shows 11
- **Test**: grep verification commands
- **Edge cases**: EC9 (mode aliases in r-mode.md)

- [ ] **Step 1: Update r-init.md**

  In the Overview section, update to reference multi-profile detection.
  In the Phase 2 section (Codebase Scan), note that `_detect_profiles()`
  returns multiple matches. In the Phase 4 section (Generate), document
  the governance template merge behavior.

  Update `--type` option description to note comma-separated support.

- [ ] **Step 2: Update r-mode.md**

  Add 3 new rows to the Available Modes table (after line 15):
  ```
  | `refactoring` | *Behavior preservation* | Large restructuring, code movement, API changes |
  | `debugging` | *Hypothesis-driven* | Bug hunts, incident response, root cause analysis |
  | `documentation` | *Read-then-write* | README rewrites, API docs, man pages, guides |
  ```

  Update aliases line (line 17) to add:
  `refactoring` -> `refactor`, `debugging` -> `debug`, `documentation` -> `docs`

- [ ] **Step 3: Update README.md**

  Update profile count badge from 6 to 11.
  Update the profiles table to include new profiles.
  Add a note about modes table including new modes.

- [ ] **Step 4: Update CHANGELOG and CHANGELOG.RELEASE**

  Add entries under 3.1.0 section.

- [ ] **Step 5: Verify**

  ```bash
  grep -c 'multi-profile\|comma-separated\|_detect_profiles' canonical/commands/r-init.md
  # expect: >= 2

  grep -c 'refactoring\|debugging\|documentation' canonical/commands/r-mode.md
  # expect: >= 3

  grep -c 'refactor.*refactoring\|debug.*debugging\|docs.*documentation' canonical/commands/r-mode.md
  # expect: >= 3 (aliases)
  ```

- [ ] **Step 6: Deploy**

  ```bash
  bash bin/rdf generate claude-code 2>&1 | tail -3
  ```

- [ ] **Step 7: Commit**

  ```bash
  git add canonical/commands/r-init.md canonical/commands/r-mode.md \
        README.md CHANGELOG CHANGELOG.RELEASE
  git commit -m "$(cat <<'EOF'
  Update commands and docs for profile/mode expansion

  [Change] r-init.md: document multi-profile detection and governance merge
  [Change] r-mode.md: add refactoring, debugging, documentation modes with aliases
  [Change] README.md: update profile count (6→11), add new profiles/modes to tables
  [Change] CHANGELOG, CHANGELOG.RELEASE: add profile/mode expansion entries
  EOF
  )"
  ```

---

### Phase 8: Regenerate, verify, push

Full deployment cycle and comprehensive verification.

**Files:**
- None modified — verification only

- **Mode**: serial-context
- **Risk**: low
- **Type**: config
- **Gates**: G1
- **Accept**: `rdf generate claude-code` succeeds; all verification
  commands from spec 10b pass; `bash -n` on all shell files passes
- **Test**: full verification suite from spec Section 10b
- **Edge cases**: none

- [ ] **Step 1: Regenerate**

  ```bash
  bash bin/rdf generate claude-code 2>&1 | tail -5
  # expect: successful generation
  ```

- [ ] **Step 2: Verify all new files exist**

  ```bash
  ls profiles/rust/governance-template.md profiles/typescript/governance-template.md \
     profiles/perl/governance-template.md profiles/php/governance-template.md \
     profiles/infrastructure/governance-template.md
  # expect: all 5

  ls profiles/rust/reference/*.md profiles/typescript/reference/*.md
  # expect: 6 files (3 each)

  ls modes/refactoring/context.md modes/debugging/context.md modes/documentation/context.md
  # expect: all 3
  ```

- [ ] **Step 3: Verify registry**

  ```bash
  jq '.profiles | keys | length' profiles/registry.json
  # expect: 11

  jq '[.profiles[] | has("tier","detect")] | all' profiles/registry.json
  # expect: true
  ```

- [ ] **Step 4: Verify core template expansion**

  ```bash
  wc -l profiles/core/governance-template.md
  # expect: >= 120
  ```

- [ ] **Step 5: Verify init.sh**

  ```bash
  bash -n lib/cmd/init.sh
  # expect: exit 0

  grep -c '_detect_profiles' lib/cmd/init.sh
  # expect: >= 1

  grep -c '_type_to_template\|_detect_project_type' lib/cmd/init.sh
  # expect: 0
  ```

- [ ] **Step 6: Push**

  ```bash
  git push
  ```

---
