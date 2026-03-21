# Profile Registry

> Available governance seed profiles for /r:init.

## Full Profiles

| Profile | Requires | Description |
|---------|----------|-------------|
| core | -- | Always active. Commit protocol, verification, security hygiene, dependency management, AI agent discipline |
| shell | core | Bash/shell projects. Quoting, portability, signal handling, BATS testing |
| python | core | Python projects. Typing, packaging, pytest, async conventions |
| frontend | core | Web frontend. Component architecture, a11y, CSS methodology, performance |
| database | core | Database engineering. Schema design, migration safety, query discipline |
| go | core | Go projects. Error handling, concurrency, interfaces, modules |
| rust | core | Rust projects. Ownership, error handling, unsafe discipline, cargo conventions |
| typescript | core | TypeScript/Node.js. Strict mode, async discipline, backend patterns |
| perl | core | Perl projects. strict/warnings, three-arg open, Moo/Moose OOP |
| php | core | PHP 8.x. Strict types, PSR standards, Laravel/Symfony patterns |
| infrastructure | core | Infrastructure as code. Terraform, Kubernetes, Ansible, CI/CD |

## Starter Profiles

| Profile | Requires | Description |
|---------|----------|-------------|
| (none — all profiles promoted to full) | | |

## Profile Tiers

- **Full** -- governance-template.md + 3-4 reference docs. Deep
  coverage with anti-patterns, testing guides, and domain-specific
  reference material.
- **Starter** -- governance-template.md only. Top conventions that
  prevent the most common AI agent mistakes. Can graduate to full
  tier in future versions.

## Profile Structure

Each profile directory contains:
- `governance-template.md` -- seed data for /r:init governance generation
- `reference/` -- docs copied to .rdf/governance/reference/ (full tier only)

Profiles do NOT contain:
- Agent lists (agents are universal in 3.0)
- Command lists (commands are universal in 3.0)
- CLAUDE.md templates (governance is generated, not templated)

## Composition

Multiple profiles stack naturally. `rdf init` auto-detects all
matching profiles and merges governance templates in dependency
order (core first, then domain profiles). When templates share a
section heading, content is concatenated with profile attribution
markers. Conflicts are flagged in the low-confidence report.

Specify manually with `--type`: `rdf init --type rust,infrastructure`

## Machine-Readable Registry

`registry.json` is the authoritative source for profile metadata.
Each profile has: `requires`, `removable`, `tier`, `detect`, `description`, `summary`.
CLI commands (`rdf profile list/install/remove/status`) read from
registry.json. This markdown file is for human reference only.
