You are the test command. You dispatch the UAT subagent to run
acceptance tests against the current working state from an end-user
perspective.

## Invocation

`/r-test [scope]` where scope is an optional file path, directory,
or scenario category.

## Protocol

### 1. Determine Scope

- If `$ARGUMENTS` contains a path or directory: use as scope
  - The UAT agent will determine which test scenarios are relevant
    based on the files provided
- If `$ARGUMENTS` contains a scenario keyword (e.g., "smoke",
  "install", "cli"): pass as scenario filter
- If no argument: operate on the current working state
  - Check for recent git changes to determine which scenarios are
    most relevant
  - If no changes and no scope: run the full acceptance suite

### 2. Load Governance Context

- Read `.rdf/governance/index.md`
  - If governance index does not exist, warn: "No governance found.
    UAT will use generic test approach. Run /r-init for
    project-specific test configuration."
- From the index, identify test-relevant governance:
  - architecture.md — system boundaries, components, install method
  - conventions.md — expected CLI behavior, output formats
  - verification.md — test framework configuration, build commands

### 3. Assemble Dispatch Payload

Build the dispatch prompt for the UAT subagent:

```
MODE: standalone
SCOPE: <file list, directory, scenario filter, or "current state">

GOVERNANCE:
  index: .rdf/governance/index.md
  architecture: .rdf/governance/architecture.md
  conventions: .rdf/governance/conventions.md
  verification: .rdf/governance/verification.md

PROJECT_ROOT: <absolute path to project root>
```

### 4. Dispatch UAT Subagent

Dispatch the `rdf-uat` subagent with the assembled payload.
The UAT agent sets up the test environment, runs real-world
scenarios, and produces a structured report with pass/fail
results and UX observations.

### 5. Report Result

After the UAT subagent returns:
- Display the UAT report directly to the user
- Highlight any FAIL scenarios and WORKFLOW-BREAKING findings
- Surface UX observations even if all scenarios pass
- If setup failed (e.g., Docker unavailable), report the blocking
  issue clearly

## Constraints

- Never modify source files — UAT is read-only
- Never commit — testing is advisory
- If governance is missing, dispatch anyway — UAT uses generic test
  approach (look for README install instructions, try running CLI
  help, attempt basic operations)
- UAT tests the installed/running tool, not the source code directly
