# RDF — Project CLAUDE.md

Inherits conventions from the parent workspace CLAUDE.md at
`/root/admin/work/proj/CLAUDE.md` (rfxn-wide shell standards, commit protocol,
testing norms). Project-specific rules below override parent defaults where
explicit.

Also read `CLAUDE.md.ref` in this directory — a condensed 6-section operating-
primitives reference (Trust but Verify, Scope Discipline, Adversarial Review,
Context Preservation, Comment Discipline, Safe Execution). These are
cross-cutting behavioral invariants, not RDF-specific conventions.

## About
RDF (rfxn Development Framework) — convention governance, agent pipelines,
and project orchestration for the rfxn ecosystem. Tool-agnostic by design.

## Development
- All content development in `canonical/` — pure markdown, no tool frontmatter
- `~/.rdf/` is the global state directory (lessons-learned, session logs, insights) — never committed
- Run `rdf generate claude-code` to deploy to /root/.claude/ — **mandatory before any commit touching `canonical/`**
- Run `rdf sync` to pull emergency edits back to canonical
- Run `rdf doctor` before push to verify zero drift

## Shell Standards
- Shebang: `#!/usr/bin/env bash`
- `set -euo pipefail` in all scripts
- Bash 4.1+ floor (CentOS 6 compatibility)
- All variables double-quoted in command context
- `command -v` for binary discovery, never hardcoded paths
- `command cp`/`command mv`/`command rm` in project source (not bare, not `/usr/bin/`)
- **Suppression comments (`2>/dev/null`, `|| true`) — RDF scope:** the workspace
  rule (same-line justification comment) applies to **new or modified** suppressions
  in first-party source, and is enforced on added diff lines by
  `state/git-hooks/pre-commit` (`suppression-no-comment` class). RDF is operator-run
  developer tooling, not an adversarial-input-facing scanner like APF/BFD/LMD, so a
  retroactive sweep of the many self-evidently-safe pre-existing suppressions
  (`git`/`jq`/`find` probes whose empty-on-failure result is the intended value) is
  **not** required. Add the comment when you touch the line; do not mass-annotate.
  Vendored `canonical/scripts/` (ykdojo/claude-code-tips: `context-bar.sh`,
  `setup.sh`, `clone-conversation.sh`, `half-clone-conversation.sh`,
  `test-half-clone.sh`, `color-preview.sh`, `check-context.sh`) is advisory-only —
  fix upstream, not in-tree.

## Commit Protocol
- Free-form descriptive messages (no version prefix)
- Tag body lines: [New] [Change] [Fix] [Remove]
- No Co-Authored-By / AI attribution
- Stage files explicitly by name — never `git add -A` or `git add .`
- Never commit: root-level PLAN*.md, AUDIT.md, MEMORY.md, .claude/, .rdf/
- Specs (`docs/specs/`) and plans (`docs/plans/`) ARE committed project artifacts
- Both CHANGELOG and CHANGELOG.RELEASE updated on code-changing commits
- **Parallel exception:** agents in parallel worktrees skip CHANGELOG; controller consolidates post-merge

## Testing
- Shell files (`bin/`, `lib/`, `state/`): `bash -n` + `shellcheck` on commits touching them
- Adapter output: `rdf generate claude-code` then diff against expected output
- State helper: `bash state/rdf-state.sh --full .` — validate JSON structure + accuracy
- Canonical content: frontmatter-free verification, stale-name grep
- Post-migration / post-init: `rdf doctor --all` must show zero FAILs before push

## Naming Convention
- Agents: role-only names (`planner`, `engineer`, `qa`, etc.)
- CC agent names: `rdf-{file-stem}` (e.g., `rdf-engineer`, `rdf-qa`)
- Lifecycle commands: `/r-{name}` (e.g., `/r-start`, `/r-plan`)
- Utility commands: `/r-util-{subject}-{verb}` (e.g., `/r-util-mem-compact`)
