# Profile Registry

> Available governance seed profiles for /r:init.

## Active Profiles

| Profile | Requires | Description |
|---------|----------|-------------|
| core | -- | Always active. Commit protocol, verification, security hygiene, dependency management |
| shell | core | Bash/shell projects. Quoting, portability, signal handling, BATS testing |
| python | core | Python projects. Typing, packaging, pytest, async conventions |
| frontend | core | Web frontend. Component architecture, a11y, CSS methodology, performance |
| database | core | Database engineering. Schema design, migration safety, query discipline |
| go | core | Go projects. Error handling, concurrency, interfaces, modules |

## Future Profiles

| Profile | Requires | Description |
|---------|----------|-------------|
| rust | core | Rust projects. Ownership patterns, error handling, cargo conventions |
| java | core | Java projects. Build tooling, dependency management, testing frameworks |
| full-stack | core, frontend, python | Cross-layer integration. Composes frontend + backend profiles |

## Profile Structure

Each profile directory contains:
- `governance-template.md` -- seed data for /r:init governance generation
- `reference/` -- docs copied to .claude/governance/reference/

Profiles do NOT contain:
- Agent lists (agents are universal in 3.0)
- Command lists (commands are universal in 3.0)
- CLAUDE.md templates (governance is generated, not templated)

## Composition

Multiple profiles compose naturally. /r:init merges governance
templates in dependency order (core first, then domain profiles).
When templates conflict, the more specific profile wins.

## Machine-Readable Registry

`registry.json` is the authoritative source for profile metadata.
CLI commands (`rdf profile list/install/remove/status`) read from
registry.json. This markdown file is for human reference only.
