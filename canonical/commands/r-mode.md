Switch the operational mode for the current session.

## Usage

/r:mode [name]          Switch to the named mode
/r:mode                 Show current mode and available modes

## Available Modes

- `development` -- default TDD workflow (implicit, no context file needed)
- `security` -- security assessment (alias: `security-assessment`)
- `performance` -- performance audit (alias: `performance-audit`)
- `migration` -- version/platform/data migration

## Behavior

When invoked with a mode name:

1. Read the mode context file from `modes/{name}/context.md` in the
   RDF repository (resolve aliases: `security` -> `security-assessment`,
   `performance` -> `performance-audit`)

2. If `.claude/governance/index.md` exists in the current project,
   update the `Mode:` line to reflect the new mode

3. Display a summary of the mode's effect:
   - Methodology overview (1-2 lines)
   - Quality gate overrides (what changes from default)
   - Reviewer focus changes (which passes are elevated)

4. The mode context is now active for this session. All subsequent
   agent dispatches (/r:build, /r:verify, /r:review, etc.) will
   include the mode context in their prompts

When invoked without arguments:

1. Check `.claude/governance/index.md` for the current mode
2. If no index exists, report "development (default)"
3. List all available modes with one-line descriptions

## Mode Context Loading

The mode context file is appended to agent dispatch prompts. It does
NOT modify governance files permanently -- it is session-scoped context
that changes how agents interpret their existing governance.

Agents affected:
- **Planner** -- methodology and brainstorming focus change
- **Dispatcher** -- quality gate overrides applied
- **Reviewer** -- pass weighting and blocking thresholds change
- **QA** -- additional verification requirements per mode
- **UAT** -- scenario scope adjusted per mode
- **Engineer** -- reads mode context for approach guidance

## Aliases

For convenience, short names map to full directory names:
- `security` -> `security-assessment`
- `performance` -> `performance-audit`
- `dev` -> `development`

## Examples

```
/r:mode security        # Switch to security assessment mode
/r:mode performance     # Switch to performance audit mode
/r:mode migration       # Switch to migration planning mode
/r:mode dev             # Switch back to default development mode
/r:mode                 # Show current mode
```

## Constraints

- Mode switching is session-scoped -- it does not persist across sessions
- Mode does not change project governance files (architecture.md, etc.)
- Mode cannot be set to a name that has no context.md in modes/
- The governance index Mode: line is the only persistent artifact updated
