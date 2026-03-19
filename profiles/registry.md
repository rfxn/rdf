# Profile Registry

> Available governance seed profiles for /r:init.

## Active Profiles

| Profile | Requires | Description |
|---------|----------|-------------|
| core | -- | Always active. Commit protocol, verification checks, artifact taxonomy |
| systems-engineering | core | Bash/shell projects. Shell standards, portability, BATS testing |
| frontend | core | Web/frontend projects. Accessibility, component testing, browser compat |
| security | core | Security assessments. OWASP methodology, threat modeling, severity schema |

## Future Profiles

| Profile | Requires | Description |
|---------|----------|-------------|
| python | core | Python projects. Typing, venv, pytest conventions |
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
