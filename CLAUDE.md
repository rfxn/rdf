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
- Agents/commands: `{domain}-{role}` for domain-specific, `{role}` for core
- Domain shortcodes: sys, sec, fe, php, py, iaas, fs
- CC agent names: `rfxn-{file-stem}` (e.g., rfxn-sys-eng)
- Slash commands: `/{file-stem}` (e.g., /sys-eng)
