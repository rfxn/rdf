# RDF 3.0 Command Mapping — Claude Code Adapter

## Skill Commands (main conversation context)

| Command    | Skill File                         | Replaces (2.x)       |
|------------|------------------------------------|-----------------------|
| /r:start   | canonical/commands-v3/r-start.md   | /reload               |
| /r:status  | canonical/commands-v3/r-status.md  | /proj-status, /status |
| /r:plan    | canonical/commands-v3/r-plan.md    | /po, /scope           |

## Deployment Path

During development, v3 skills live in `canonical/commands-v3/` and
are NOT deployed to `~/.claude/commands/`. The existing 2.x commands
remain active.

At cutover (Plan 8 — Migration):
1. v3 skills are copied to `~/.claude/commands/` with `r-` prefix
   (e.g., `r-start.md` becomes available as `/r:start` or `/r-start`)
2. 2.x commands that are replaced are removed
3. 2.x commands that are absorbed (into lifecycle commands) are removed
4. 2.x commands promoted to utilities get `/r:util:` prefix

## Claude Code Slash Command Naming

Claude Code derives the slash command name from the filename:
- `r-start.md` → `/r-start`

The `/r:` colon namespace in the spec is the user-facing name. The
actual Claude Code command uses a hyphen: `/r-start`. Documentation
and help text should reference `/r:start` but note the actual
invocation as `/r-start`.

## Adapter Generator Changes

The `rdf generate claude-code` command needs these updates for v3:
- Recognize `commands-v3/` as a source directory
- Use `r-` prefix for v3 command filenames
- Strip any frontmatter (v3 files should have none, but guard against it)
- Copy agent-meta-v3.json for agent registration
