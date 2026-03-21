# RDF 3.0 Command Mapping — Claude Code Adapter

## Skill Commands (main conversation context)

| Command    | Skill File                       | Replaces (2.x)           |
|------------|----------------------------------|--------------------------|
| /r:start   | canonical/commands/r-start.md    | /reload                  |
| /r:status  | canonical/commands/r-status.md   | /proj-status, /status    |
| /r:plan    | canonical/commands/r-plan.md     | /po, /scope              |
| /r:spec    | canonical/commands/r-spec.md     | *(new in 3.0)*           |
| /r:build   | canonical/commands/r-build.md    | /mgr, /sys-eng           |
| /r:verify  | canonical/commands/r-verify.md   | /sys-qa                  |
| /r:test    | canonical/commands/r-test.md     | /sys-uat                 |
| /r:review  | canonical/commands/r-review.md   | /sys-sentinel, /sys-challenger |
| /r:ship    | canonical/commands/r-ship.md     | /rel-ship                |
| /r:audit   | canonical/commands/r-audit.md    | /audit                   |
| /r:save    | canonical/commands/r-save.md     | *(new in 3.0)*           |
| /r:mode    | canonical/commands/r-mode.md     | *(new in 3.0)*           |
| /r:init    | canonical/commands/r-init.md     | *(new in 3.0)*           |
| /r:refresh | canonical/commands/r-refresh.md  | *(new in 3.0)*           |
| /r:sync    | canonical/commands/r-sync.md     | *(new in 3.0)*           |
| /r:tasks   | canonical/commands/r-tasks.md    | *(new in 3.0)*           |
| /r:vpe     | canonical/commands/r-vpe.md      | *(new in 3.0)*           |

## Deployment Path

v3 commands live in `canonical/commands/` and are deployed to
`~/.claude/commands/` via `rdf generate claude-code`.

## Claude Code Slash Command Naming

Claude Code derives the slash command name from the filename:
- `r-start.md` -> `/r-start`

The `/r:` colon namespace in the spec is the user-facing name. The
actual Claude Code command uses a hyphen: `/r-start`. Documentation
and help text should reference `/r:start` but note the actual
invocation as `/r-start`.

## Agent Registration

Agent metadata is in `adapters/claude-code/agent-meta.json` with
6 universal agents (rdf- prefix). Command dispatch metadata is in
`adapters/claude-code/command-meta-v3.json`.
