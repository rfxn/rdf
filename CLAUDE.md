# RDF — Project CLAUDE.md

## About
RDF (rfxn Development Framework) — convention governance, agent pipelines,
and project orchestration for the rfxn ecosystem. Tool-agnostic by design.

## Development
- All content development in `canonical/` — pure markdown, no tool frontmatter
- Run `rdf generate claude-code` to deploy to /root/.claude/
- Run `rdf sync` to pull emergency edits back to canonical
- Run `rdf doctor` to check for drift

## Shell Standards
- Shebang: `#!/usr/bin/env bash`
- `set -euo pipefail` in all scripts
- Bash 4.1+ floor (CentOS 6 compatibility)
- All variables double-quoted in command context
- `command -v` for binary discovery, never hardcoded paths
- `command cp`/`command mv`/`command rm` in project source (not bare, not `/usr/bin/`)

## Commit Protocol
- Free-form descriptive messages (no version prefix)
- Tag body lines: [New] [Change] [Fix] [Remove]
- No Co-Authored-By / AI attribution
- Stage files explicitly by name — never `git add -A` or `git add .`
- Never commit: PLAN*.md, AUDIT.md, MEMORY.md, .claude/
- Both CHANGELOG and CHANGELOG.RELEASE updated on code-changing commits

## Testing
- CLI tools: manual verification + shellcheck
- Adapter output: diff against expected output
- State helper: JSON validation + accuracy checks
- Canonical content: frontmatter-free verification, stale-name grep

## Naming Convention
- Agents: role-only names (`planner`, `engineer`, `qa`, etc.)
- CC agent names: `rdf-{file-stem}` (e.g., `rdf-engineer`, `rdf-qa`)
- Lifecycle commands: `/r:{name}` (e.g., `/r:start`, `/r:plan`)
- Utility commands: `/r:util:{subject}-{verb}` (e.g., `/r:util:mem-compact`)
- CC slash commands use hyphens: `/r-start`, `/r-util-mem-compact`
