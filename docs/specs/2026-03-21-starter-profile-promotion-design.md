# Design: Starter Profile Promotion to Full Tier

**Date:** 2026-03-21
**Status:** Implemented (3.0.4)
**Author:** Ryan MacDonald + Claude (Opus 4.6)

---

## 1. Problem Statement

RDF has 3 starter profiles (Perl, PHP, Infrastructure) that provide
governance-template.md only — no reference docs. Full profiles (shell,
python, go, rust, typescript) include 3-4 reference docs covering
anti-patterns with code examples, testing framework patterns, and
domain-specific guidance. This creates a two-class system:

- **Full profile agents** get 700-1500 lines of deep domain knowledge
  including specific bad/good code patterns, false-positive annotations,
  and testing discipline
- **Starter profile agents** get 95-139 lines of top-level conventions
  with no depth, no anti-pattern catalog, and no testing evidence
  primitives

The gap produces measurable outcomes:
- Perl governance: 95 lines, 8 sections, 0 anti-pattern entries with
  code examples, 0 "when safe" annotations
- PHP governance: 111 lines, 9 sections, 0 anti-pattern entries with
  code examples, 0 "when safe" annotations
- Infrastructure governance: 139 lines, 8 sections, 0 anti-pattern
  entries with code examples, 0 "when safe" annotations
- Full profile average: governance template (~100 lines) + 3 reference
  docs (~900 lines total) = ~1000 lines of domain knowledge

Without anti-pattern depth, agents in starter-profile stacks generate
false positives (flagging safe patterns as violations) and miss real
issues (lacking the pattern catalog to recognize them).

## 2. Goals

1. Add 3 reference docs to each starter profile (9 new files total)
2. Embed evidence-backed verification in anti-patterns docs via
   context-gate preamble + inline "When this is safe" annotations
3. Embed testing evidence discipline in testing docs (prove, PHPUnit,
   IaC validation)
4. Update registry.md and registry.json: tier starter → full,
   summary updates
5. Maintain structural consistency with existing full profiles
   (preamble, bad/good code blocks, section organization)

## 3. Non-Goals

- Modifying existing governance-template.md files (they're solid;
  depth belongs in reference docs)
- Adding a 4th reference doc to any profile
- Modifying existing full profiles
- Backfilling existing anti-patterns docs with Verification Preamble
  or "When this is safe" annotations (separate future effort — these
  new conventions are being piloted in the promoted profiles first)
- Changing profile tooling (rdf profile, rdf init, detection)
- Adding new profiles

## 4. Architecture

### File Map

| File | Status | Lines (est) | Purpose |
|------|--------|-------------|---------|
| `profiles/perl/reference/perl-anti-patterns.md` | NEW | 400-500 | Anti-pattern catalog with bad/good examples, "when safe" annotations |
| `profiles/perl/reference/testing-prove.md` | NEW | 300-400 | Test2::V0/prove patterns, evidence discipline, coverage |
| `profiles/perl/reference/regex-security.md` | NEW | 250-350 | Regex injection, catastrophic backtracking, safe interpolation |
| `profiles/php/reference/php-anti-patterns.md` | NEW | 400-500 | Anti-pattern catalog with bad/good examples, "when safe" annotations |
| `profiles/php/reference/testing-phpunit.md` | NEW | 300-400 | PHPUnit/Pest patterns, evidence discipline, database testing |
| `profiles/php/reference/security-web-php.md` | NEW | 250-350 | OWASP top-10 PHP-specific patterns, framework protections |
| `profiles/infrastructure/reference/iac-anti-patterns.md` | NEW | 400-500 | IaC anti-patterns across Terraform/K8s/Ansible/Docker |
| `profiles/infrastructure/reference/testing-iac.md` | NEW | 300-400 | IaC validation pipeline, plan-based testing, policy-as-code |
| `profiles/infrastructure/reference/terraform-patterns.md` | NEW | 250-350 | Module patterns, state management, refactoring with moved blocks |
| `profiles/registry.md` | MODIFIED | 62→62 | Move perl/php/infrastructure from Starter to Full table |
| `profiles/registry.json` | MODIFIED | 53→53 | Update tier and summary fields for 3 profiles |

**Total new content:** ~3,150 lines across 9 files
**Total modified content:** ~10 lines across 2 files

### Size Comparison

| Metric | Before | After |
|--------|--------|-------|
| Full profiles | 8 | 11 |
| Starter profiles | 3 | 0 |
| Total reference docs | 27 | 36 |
| Perl domain knowledge | 95 lines | ~1,145 lines |
| PHP domain knowledge | 111 lines | ~1,161 lines |
| Infrastructure domain knowledge | 139 lines | ~1,189 lines |

### Dependency Tree

```
profiles/
├── registry.md          ← modified (table moves)
├── registry.json        ← modified (tier + summary)
├── perl/
│   ├── governance-template.md   (unchanged)
│   └── reference/               ← NEW directory
│       ├── perl-anti-patterns.md
│       ├── testing-prove.md
│       └── regex-security.md
├── php/
│   ├── governance-template.md   (unchanged)
│   └── reference/               ← NEW directory
│       ├── php-anti-patterns.md
│       ├── testing-phpunit.md
│       └── security-web-php.md
└── infrastructure/
    ├── governance-template.md   (unchanged)
    └── reference/               ← NEW directory
        ├── iac-anti-patterns.md
        ├── testing-iac.md
        └── terraform-patterns.md
```

No sourcing/import dependencies — these are standalone markdown
reference docs consumed by `rdf init` during governance generation.

### Dependency Rules

- Reference docs reference their companion governance template but
  never modify it
- Anti-patterns docs must not duplicate content from governance
  templates — they expand on it with code examples and depth
- Each reference doc is self-contained (no cross-references between
  reference docs within a profile)

## 5. File Contents

### 5.1 Anti-Patterns Docs (perl, php, infrastructure)

All three follow identical structure. Entry count targets:

| Profile | Entries (est) | Sections |
|---------|---------------|----------|
| Perl | 15-18 | Scope & Variables, I/O & Files, OOP, Error Handling, Security |
| PHP | 15-18 | Type Safety, Query Safety, Mass Assignment, Template Safety, Error Handling |
| Infrastructure | 15-18 | Terraform, Kubernetes, Ansible, Docker, CI/CD |

**Structural pattern** (matches python/go/rust anti-patterns docs):

```markdown
# {Language} Anti-Patterns Reference

> Deep reference for common {language} anti-patterns. Each entry shows
> the broken pattern, explains why it fails, and provides the correct
> alternative. Companion to the {language} governance template.

## Verification Preamble

Before reporting any pattern from this document as a finding:
1. Verify the pattern exists in project code (not just dependencies)
2. Check whether framework or library protections already mitigate it
3. Confirm the code path is reachable from an entry point
4. Read the "When this is safe" annotation if present

A pattern match is a candidate. A verified pattern match is a finding.

---

## {Section Name}

### {Anti-Pattern Title}

{1-2 sentence explanation of why this fails.}

Bad:
```{lang}
{broken code}
```

Good:
```{lang}
{correct code}
```

{Explanation of the fix and why the good version is correct.}

When this is safe: {conditions under which the bad pattern is
acceptable, or omitted entirely if never safe}

---
```

**Function inventory for anti-patterns docs:**

| Entry category | Perl entries | PHP entries | Infrastructure entries |
|----------------|-------------|-------------|----------------------|
| Scope/type safety | Two-arg open, $_ in large scope, our vs my, missing strict | Missing strict_types, mixed types, annotation-only types, loose comparison | count vs for_each, unversioned providers, latest tags |
| Data handling | Unquoted interpolation, raw regex vars, binary mode | Raw SQL concat, mass assignment, raw template output, N+1 queries | Unencrypted state, local state for shared infra, manual state edits |
| Error handling | Bare eval/$@, unchecked system calls, silent close | Bare catch, swallowed exceptions, error_reporting(0) | Missing plan before apply, auto-approve production, no rollback |
| Security | Shell injection via system(), eval $string, taint bypass | CSRF gaps, file upload without validation, APP_DEBUG=true | Hardcoded secrets, long-lived credentials, privileged containers |
| OOP/structure | Raw bless, deep inheritance, package globals | God controllers, service locator, static facades | Inline shell in Ansible, missing handlers, no idempotency guards |

### 5.2 Testing Docs (prove, phpunit, iac)

All three follow identical structure:

```markdown
# {Framework} Testing Reference

> Deep reference for {framework} testing patterns. Covers {key areas}.
> Companion to the {language} governance template.

## Evidence Discipline

Tests are evidence, not ceremony. Every test must:
- Assert a specific, falsifiable claim about code behavior
- Fail meaningfully when the claim is violated (not just "exit 1")
- Be reproducible in isolation (no shared state, no test ordering)
- Name what it proves (test name = specification)

Before trusting a passing test suite as evidence:
- Verify tests actually execute the code path in question
- Check for tautological assertions (always-true conditions)
- Confirm mocks match real interface contracts
- Review coverage for the specific change, not just total coverage %

---

## {Section: Framework Patterns}
## {Section: Fixture/Setup Patterns}
## {Section: Assertion Patterns}
## {Section: Coverage & CI}
```

**Function inventory for testing docs:**

| Section | Perl (prove) | PHP (PHPUnit) | Infrastructure (IaC) |
|---------|-------------|---------------|---------------------|
| Framework patterns | Test2::V0 vs Test::More, prove flags, TAP output | PHPUnit vs Pest, phpstan integration, php-cs-fixer | terraform validate + tflint + checkov pipeline, policy-as-code |
| Fixture/setup | Test isolation (per-process), temp files, mock modules | RefreshDatabase, factories, in-memory SQLite, setUp/tearDown | terraform plan -out capture, fixture .tf files, test workspaces |
| Assertion patterns | is/ok/like/dies_ok, subtest grouping, done_testing | assertEquals vs assertSame, expectException, data providers | Plan output parsing, resource count assertions, drift detection |
| Coverage & CI | Devel::Cover, prove -j for parallel, perlcritic in CI | PHPUnit coverage, infection (mutation testing), CI matrix | Pre-commit hooks, PR plan-only gates, apply-only on merge |

### 5.3 Domain-Specific Docs

**regex-security.md (Perl):**

| Section | Content |
|---------|---------|
| Regex injection | \Q\E discipline, qr// precompilation, user input in patterns |
| Catastrophic backtracking | Nested quantifiers, ReDoS patterns, timeout guards |
| Safe interpolation | Variable interpolation in s///, capturing vs non-capturing |
| Taint mode interaction | Regex-based untainting, safe untaint patterns |
| Unicode safety | \X vs . for grapheme clusters, /u flag, UTF-8 boundary issues |

**security-web-php.md (PHP):**

| Section | Content |
|---------|---------|
| SQL injection | PDO::ATTR_EMULATE_PREPARES, Eloquent raw methods, doctrine DQL |
| XSS prevention | Blade escaping, raw output gates, CSP headers, HttpOnly cookies |
| Authentication | Framework auth vs custom, password hashing, session fixation |
| File upload safety | Extension allowlist, MIME validation, storage outside webroot |
| Deserialization | unserialize() dangers, JSON as alternative, signed payloads |

**terraform-patterns.md (Infrastructure):**

| Section | Content |
|---------|---------|
| Module design | Input validation, output contracts, minimal dependencies |
| State management | Remote backends, state locking, sensitive data in state |
| Refactoring safely | moved blocks, import blocks, state mv operations |
| Environment separation | Workspace vs directory patterns, variable inheritance |
| Upgrade paths | Provider version bumps, module version migration, state format changes |

## 5b. Examples

Internal content change — no user-facing CLI output changes. The
reference docs are consumed by `rdf init` during governance generation.

The observable change is in `rdf profile list` output. The `Components:`
line for each promoted profile changes:

Before:
```
  perl          Perl projects. strict/warnings, three-arg open, Moo/Moose OOP
                Components: governance-template only
```

After:
```
  perl          Perl projects. strict/warnings, three-arg open, Moo/Moose OOP
                Components: governance-template + 3 reference docs
```

The `registry.json` `tier` field changes from `"starter"` to `"full"`
and `summary` from `"governance-template only"` to
`"governance-template + 3 reference docs"` for all 3 profiles.

## 6. Conventions

### Anti-Pattern Entry Template

```markdown
### {Pattern Name}

{1-2 sentence explanation.}

Bad:
```{lang}
{code}
```

Good:
```{lang}
{code}
```

{Fix explanation.}

When this is safe: {conditions, or omit if never safe}
```

### Context-Gate Preamble Template

```markdown
## Verification Preamble

Before reporting any pattern from this document as a finding:
1. Verify the pattern exists in project code (not just dependencies)
2. Check whether framework or library protections already mitigate it
3. Confirm the code path is reachable from an entry point
4. Read the "When this is safe" annotation if present

A pattern match is a candidate. A verified pattern match is a finding.
```

### Testing Evidence Discipline Template

```markdown
## Evidence Discipline

Tests are evidence, not ceremony. Every test must:
- Assert a specific, falsifiable claim about code behavior
- Fail meaningfully when the claim is violated
- Be reproducible in isolation
- Name what it proves

Before trusting a passing test suite as evidence:
- Verify tests execute the code path in question
- Check for tautological assertions
- Confirm mocks match real interface contracts
- Review coverage for the specific change, not just total %
```

### Blockquote Preamble Template

```markdown
> Deep reference for common {domain} {doc-type}. {Scope sentence}.
> Companion to the {profile} governance template.
```

## 7. Interface Contracts

**Unchanged.** Reference docs are passive content consumed by:
- `rdf init` — copies reference/ contents to
  `.rdf/governance/reference/` during governance generation
- `rdf profile install` — activates profile, references appear in
  next `rdf init` or `rdf generate`
- Agents — reference docs loaded as context during dispatch

No CLI changes, no config format changes, no API changes.

## 8. Migration Safety

### Install/upgrade path

Existing projects with governance already generated will not
automatically pick up the new reference docs. Users must run
`rdf init --refresh` or `rdf generate` to pull new reference
docs into their project's governance directory.

### Backward compatibility

No breaking changes. The tier field change (starter→full) is
cosmetic — it affects `rdf profile list` display only. No
behavioral change in profile stacking, detection, or governance
generation.

### Test suite impact

No existing tests affected. New content is markdown — validation
is structural (file existence, frontmatter-free, consistent
section headings).

### Rollback

`git revert` the commit. No state files, no migrations, no
generated artifacts to clean up.

## 9. Dead Code and Cleanup

The `profiles/registry.md` "Starter Profiles" table will become
empty after promotion. Options:
- Remove the "Starter Profiles" section entirely
- Keep it with "(none)" for future starters

Decision: Keep the section with `(none — all profiles promoted to
full)` as a placeholder. The tier system is documented infrastructure
and removing it implies starters are no longer supported.

## 10a. Test Strategy

| Goal | Test method | Verification |
|------|------------|--------------|
| Goal 1: 9 new reference docs | File existence | `ls profiles/*/reference/*.md` |
| Goal 2: Evidence preambles | Grep for "Verification Preamble" | `grep -l "Verification Preamble" profiles/*/reference/*anti-patterns.md` |
| Goal 2: "When safe" annotations | Grep for "When this is safe" | `grep -c "When this is safe" profiles/*/reference/*anti-patterns.md` |
| Goal 3: Testing evidence | Grep for "Evidence Discipline" | `grep -l "Evidence Discipline" profiles/*/reference/testing-*.md` |
| Goal 4: Registry updated | Grep registry.json for tier | `grep -A1 '"perl"' profiles/registry.json` |
| Goal 5: Structural consistency | Section heading pattern | `grep -c '^## ' profiles/*/reference/*.md` per doc |

## 10b. Verification Commands

```bash
# Goal 1: All 9 reference docs exist
ls profiles/perl/reference/perl-anti-patterns.md \
   profiles/perl/reference/testing-prove.md \
   profiles/perl/reference/regex-security.md \
   profiles/php/reference/php-anti-patterns.md \
   profiles/php/reference/testing-phpunit.md \
   profiles/php/reference/security-web-php.md \
   profiles/infrastructure/reference/iac-anti-patterns.md \
   profiles/infrastructure/reference/testing-iac.md \
   profiles/infrastructure/reference/terraform-patterns.md
# expect: all 9 files listed, exit 0

# Goal 2: Anti-patterns docs have verification preamble
grep -l "Verification Preamble" profiles/*/reference/*anti-patterns.md | wc -l
# expect: 3

# Goal 2: Anti-patterns docs have "When this is safe" annotations
grep -c "When this is safe" profiles/perl/reference/perl-anti-patterns.md
# expect: >= 5
grep -c "When this is safe" profiles/php/reference/php-anti-patterns.md
# expect: >= 5
grep -c "When this is safe" profiles/infrastructure/reference/iac-anti-patterns.md
# expect: >= 5

# Goal 3: Testing docs have evidence discipline section
grep -l "Evidence Discipline" profiles/*/reference/testing-*.md | wc -l
# expect: 3

# Goal 4: Registry shows all 3 as full tier
python3 -c "import json; r=json.load(open('profiles/registry.json')); print(all(r['profiles'][p]['tier']=='full' for p in ['perl','php','infrastructure']))"
# expect: True

# Goal 4: Registry summaries updated
grep '"summary"' profiles/registry.json | grep -c 'governance-template only'
# expect: 0

# Goal 5: No starter profiles in registry.md
grep -c "Starter Profiles" profiles/registry.md
# expect: 1 (section header remains)
grep -A5 "Starter Profiles" profiles/registry.md | grep -c '| perl\|| php\|| infrastructure'
# expect: 0

# Structural: Line count ranges
wc -l profiles/*/reference/*anti-patterns.md
# expect: each 400-500
wc -l profiles/*/reference/testing-*.md
# expect: each 300-400
wc -l profiles/perl/reference/regex-security.md \
      profiles/php/reference/security-web-php.md \
      profiles/infrastructure/reference/terraform-patterns.md
# expect: each 250-350

# Structural: No frontmatter in any new reference doc
head -1 profiles/perl/reference/*.md profiles/php/reference/*.md profiles/infrastructure/reference/*.md | grep -c "^---"
# expect: 0

# Structural: Bad/Good code pattern present in anti-patterns
grep -c "^Bad:" profiles/*/reference/*anti-patterns.md
# expect: >= 10 per file

# Structural: Blockquote preamble present
head -5 profiles/*/reference/*.md | grep -c "^>"
# expect: >= 9 (one per file minimum)
```

## 11. Risks

1. **Content quality drift** — Reference docs written without deep
   domain expertise may contain inaccurate patterns.
   *Mitigation:* Model entries on existing full-profile patterns
   that have been validated across sessions. Use the governance
   template content as the accuracy baseline — it was already
   reviewed during the profile-mode expansion (3.0.1).

2. **Context window bloat** — 9 new docs (~2,250 lines) increase
   total profile corpus by ~35%.
   *Mitigation:* Reference docs are loaded selectively by profile
   activation, not all at once. A Perl project loads only Perl +
   core reference docs (~900 lines), not all 36 docs.

3. **"When this is safe" annotations create loopholes** — Agents
   may use safety annotations as justification to skip real issues.
   *Mitigation:* The context-gate preamble establishes that safety
   annotations explain exceptions, not defaults. The verification
   protocol (verify pattern exists, check framework protections,
   confirm reachability) must be followed regardless.

4. **Maintenance burden** — 9 new docs need updates as languages
   and frameworks evolve.
   *Mitigation:* Reference docs are versioned with the profile.
   The `/r:audit` pipeline flags stale reference docs. The starter
   governance templates already exist and have been maintained —
   reference docs follow the same lifecycle.

## 11b. Edge Cases

| Scenario | Expected behavior | Handling |
|----------|-------------------|---------|
| Project has perl + infrastructure active | Both profiles' reference docs loaded | Profile stacking handles this — no conflict between profile reference dirs |
| Existing project runs `rdf init --refresh` after upgrade | New reference docs copied to governance | `rdf init` reads reference/ dirs for active profiles and copies new files |
| User runs `rdf profile remove perl` after promotion | Profile deactivated, reference docs remain in governance until next init | Consistent with existing full profile removal behavior |
| Anti-pattern has no "When this is safe" case | Annotation omitted entirely | Silence = never safe (documented in preamble) |
| Framework protection makes entire anti-pattern section irrelevant | Agent should note framework protection and skip section | Preamble rule #2: "Check whether framework protections already mitigate it" |
| IaC project uses only Terraform, not K8s/Ansible | K8s/Ansible anti-patterns loaded but not applicable | Anti-patterns are organized by sub-domain sections — agent reads relevant sections only |
| Reference doc entry conflicts with governance template | Governance template is authoritative (seed data) | Reference doc preamble: "Companion to the governance template" — template wins |

## 12. Open Questions

None — all design questions resolved in brainstorming.
