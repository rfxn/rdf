Switch the operational mode for the current session.

## Usage

/r:mode [name]          Switch to the named mode
/r:mode                 Show current mode and available modes

## Available Modes

| Mode | Description | When to Use |
|------|-------------|-------------|
| `development` | *Default TDD workflow* | Standard feature work, bug fixes, refactoring |
| `security` | *Security assessment* | Threat modeling, vuln analysis, hardening |
| `performance` | *Performance audit* | Profiling, optimization, bottleneck analysis |
| `migration` | *Version/platform/data migration* | Upgrades, platform moves, data transforms |
| `refactoring` | *Behavior preservation* | Large restructuring, code movement, API changes |
| `debugging` | *Hypothesis-driven* | Bug hunts, incident response, root cause analysis |
| `documentation` | *Read-then-write* | README rewrites, API docs, man pages, guides |

**Aliases:** `security` -> `security-assessment`, `performance` -> `performance-audit`, `dev` -> `development`, `refactor` -> `refactoring`, `debug` -> `debugging`, `docs` -> `documentation`

## Behavior

When invoked with a mode name:

1. Read the mode context file from `modes/{name}/context.md` in the
   RDF repository (resolve aliases per the table above)

2. If `.rdf/governance/index.md` exists in the current project,
   update the `Mode:` line to reflect the new mode

3. Display a mode switch confirmation as a blockquote callout:

```
> **Mode switched**
> `development` -> `security`
>
> - **Methodology:** threat-model-first assessment with STRIDE/DREAD
> - **Gate overrides:** security review pass elevated to *blocking*
> - **Reviewer focus:** input validation, auth boundaries, secret handling
```

   The callout includes:
   - **Before/after** shown as inline code with arrow
   - **Methodology** -- 1-line overview of the mode's approach
   - **Gate overrides** -- what changes from default (italic for emphasis)
   - **Reviewer focus** -- which review passes are elevated

4. The mode context is now active for this session. All subsequent
   agent dispatches (`/r:build`, `/r:verify`, `/r:review`, etc.) will
   include the mode context in their prompts

When invoked without arguments:

1. Check `.rdf/governance/index.md` for the current mode
2. Display current mode with bold label and inline code value:

```
**Current mode:** `development` *(default)*
```

3. Display the Available Modes table (see above)

## Mode Context Loading

The mode context file is appended to agent dispatch prompts. It does
NOT modify governance files permanently -- it is session-scoped context
that changes how agents interpret their existing governance.

**Agents affected:**

| Agent | Mode Effect |
|-------|-------------|
| **Spec Designer** | *Research methodology and brainstorming focus change* |
| **Planner** | *Decomposition strategy and phase risk assessment change* |
| **Dispatcher** | *Quality gate overrides applied* |
| **Reviewer** | *Pass weighting and blocking thresholds change* |
| **QA** | *Additional verification requirements per mode* |
| **UAT** | *Scenario scope adjusted per mode* |
| **Engineer** | *Reads mode context for approach guidance* |

## Examples

```
/r:mode security        # Switch to security assessment mode
/r:mode performance     # Switch to performance audit mode
/r:mode migration       # Switch to migration planning mode
/r:mode dev             # Switch back to default development mode
/r:mode                 # Show current mode and available modes
```

## Constraints

- Mode switching is session-scoped -- it does not persist across sessions
- Mode does not change project governance files (architecture.md, etc.)
- Mode cannot be set to a name that has no context.md in modes/
- The governance index Mode: line is the only persistent artifact updated
