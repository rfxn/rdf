# RDF Dispatch Abstraction — Interface Specification

> Defines the contract for `lib/dispatch.sh` — the mode-aware agent dispatch
> layer that bridges subagent and Agent Teams execution models.

## 1. Design Principles

### 1.1 Instructions, Not Execution

The dispatch library generates **structured dispatch instructions** — it does
not make API calls. The mgr agent/command interprets these instructions and
makes the actual tool calls in its LLM context window.

Output format: structured markdown blocks that embed tool call parameters as
JSON. The mgr agent reads these blocks and translates them into tool calls.

### 1.2 Mode Transparency

Callers (mgr agent/command) use the same interface regardless of mode. The
dispatch output changes structure based on `RDF_AGENT_TEAMS` but the semantic
intent is identical: "spawn agent X with role Y, model Z, prompt P."

### 1.3 Zero Regression

When `RDF_AGENT_TEAMS=false` (default), output is functionally identical to
current hardcoded dispatch instructions in mgr.md. The abstraction replaces
inline dispatch blocks, not the dispatch behavior.

## 2. Feature Flag

**Environment variable:** `RDF_AGENT_TEAMS`
**Values:** `true` | `false` (default: `false`)
**Scope:** Read by `lib/dispatch.sh` at generation time, propagated into
generated mgr command/agent content.

When `rdf generate claude-code` runs:
- Reads `RDF_AGENT_TEAMS` from environment
- Passes it to the dispatch library
- Generated mgr command includes mode-appropriate dispatch blocks

Runtime override: The mgr agent can also check `RDF_AGENT_TEAMS` at dispatch
time and select the appropriate instruction set. This allows switching modes
without regenerating.

## 3. Agent Registry

File: `lib/dispatch-agents.json`

Maps agent roles to their properties across both dispatch modes.

```json
{
  "agents": {
    "sys-eng": {
      "role": "Senior Engineer",
      "canonical": "canonical/agents/sys-eng.md",
      "command": "canonical/commands/sys-eng.md",
      "model": "opus",
      "cc_name": "rfxn-sys-eng",
      "subagent_type": "general-purpose",
      "team_agent_type": "general-purpose",
      "tools": ["Bash", "Read", "Write", "Edit", "Glob", "Grep"],
      "disallowed_tools": [],
      "can_write": true,
      "pipeline_stage": ["implementation"],
      "timeout_minutes": 10
    },
    "sys-qa": {
      "role": "QA Engineer",
      "canonical": "canonical/agents/sys-qa.md",
      "command": "canonical/commands/sys-qa.md",
      "model": "sonnet",
      "cc_name": "rfxn-sys-qa",
      "subagent_type": "general-purpose",
      "team_agent_type": "general-purpose",
      "tools": ["Bash", "Read", "Glob", "Grep"],
      "disallowed_tools": ["Write", "Edit"],
      "can_write": false,
      "pipeline_stage": ["verification"],
      "timeout_minutes": 10
    }
  }
}
```

Each agent entry contains everything needed to dispatch in either mode.

## 4. Task Templates

File: `lib/dispatch-tasks.json`

Defines pipeline stages as reusable task templates with dependency chains.

```json
{
  "templates": {
    "scope-validate": {
      "subject": "Scope: Validate Phase {phase}",
      "agent": "scope",
      "mode": "validate",
      "depends_on": [],
      "output_file": "work-output/scope-validation-{phase}.md"
    },
    "scope-workorder": {
      "subject": "Scope: Work Order for Phase {phase}",
      "agent": "scope",
      "mode": "workorder",
      "depends_on": [],
      "output_file": "work-output/scope-workorder-P{phase}.md"
    },
    "se-plan": {
      "subject": "SE: Plan Phase {phase}",
      "agent": "sys-eng",
      "mode": "plan-only",
      "depends_on": ["scope-workorder"],
      "output_file": "work-output/implementation-plan.md"
    },
    "challenger": {
      "subject": "Challenger: Review Phase {phase} Plan",
      "agent": "sys-challenger",
      "mode": "review",
      "depends_on": ["se-plan"],
      "output_file": "work-output/challenge-{phase}.md"
    },
    "se-implement": {
      "subject": "SE: Implement Phase {phase}",
      "agent": "sys-eng",
      "mode": "workorder",
      "depends_on": ["challenger"],
      "output_file": "work-output/phase-result.md"
    },
    "qa-gate": {
      "subject": "QA: Gate Phase {phase}",
      "agent": "sys-qa",
      "mode": "gate",
      "depends_on": ["se-implement"],
      "output_file": "work-output/qa-phase-{phase}-verdict.md"
    },
    "sentinel": {
      "subject": "Sentinel: Review Phase {phase}",
      "agent": "sys-sentinel",
      "mode": "standard",
      "depends_on": ["se-implement"],
      "output_file": "work-output/sentinel-{phase}.md"
    },
    "ux-review": {
      "subject": "UX Review: Phase {phase}",
      "agent": "sys-ux",
      "mode": "output-review",
      "depends_on": ["se-implement"],
      "output_file": "work-output/ux-review-{phase}.md"
    },
    "uat": {
      "subject": "UAT: Phase {phase}",
      "agent": "sys-uat",
      "mode": "standard",
      "depends_on": ["qa-gate"],
      "output_file": "work-output/uat-phase-{phase}-verdict.md"
    }
  }
}
```

## 5. Dispatch Function Interface

### rdf_dispatch_agent()

```
rdf_dispatch_agent <agent-name> <mode> <phase> <project-path> [extra-context]
```

Reads the agent registry, applies the feature flag, and outputs a structured
dispatch block.

**Subagent mode output:**
```markdown
### Dispatch: {role} ({agent-name})

**Tool:** Agent
**Parameters:**
- subagent_type: {cc_name} (fallback: {subagent_type} with model {model})
- prompt: "{generated_prompt}"
- timeout: {timeout_minutes} minutes

**Expected output:** {output_file}
```

**Agent Teams mode output:**
```markdown
### Dispatch: {role} ({agent-name})

**Tool:** Task (teammate)
**Parameters:**
- team_name: "rfxn-pipeline"
- name: "{agent-name}"
- subagent_type: "{team_agent_type}"
- model: "{model}"
- prompt: "{generated_prompt}"
- run_in_background: true

**Task:** {task_subject}
**Blocked by:** {dependency_list}
**Expected output:** {output_file}
```

### rdf_dispatch_pipeline()

```
rdf_dispatch_pipeline <tier> <phase> <project-path> [flags]
```

Generates the complete pipeline dispatch sequence for a given tier.

**Tier 0-1 output:** scope (optional) -> SE -> QA-lite
**Tier 2+ output:** scope -> SE-plan -> challenger -> SE-implement -> (QA + sentinel + ux-review parallel) -> UAT

In Agent Teams mode, this produces a complete TaskCreate sequence with
dependency chains, allowing the team to self-coordinate.

### rdf_dispatch_team_setup()

```
rdf_dispatch_team_setup <team-name> <description>
```

Agent Teams mode only. Generates TeamCreate instructions.

### rdf_dispatch_team_teardown()

```
rdf_dispatch_team_teardown <team-name>
```

Agent Teams mode only. Generates shutdown + TeamDelete instructions.

## 6. Prompt Generation

Each dispatch generates a role-specific prompt from a template. Templates
reference:
- The agent's canonical command file (`/root/.claude/commands/{name}.md`)
- The project CLAUDE.md path
- The parent CLAUDE.md path
- The work order path
- The output file path
- Mode-specific instructions (validate, workorder, gate, gate-lite, etc.)

Templates are stored in `lib/dispatch-tasks.json` as `prompt_template` fields,
with `{phase}`, `{project_path}`, `{output_file}` placeholders.

## 7. Adapter Integration

The Claude Code adapter gains optional Agent Teams configuration:

`adapters/claude-code/teams-meta.json`:
```json
{
  "team_name_prefix": "rfxn",
  "default_team_description": "rfxn engineering pipeline",
  "delegate_mode": true,
  "teammate_mode": "in-process",
  "hooks": {
    "TaskCompleted": {
      "script": "scripts/task-completed-gate.sh",
      "description": "Verify lint + test pass before task completion"
    },
    "TeammateIdle": {
      "script": "scripts/teammate-idle-handler.sh",
      "description": "Auto-assign next unblocked task"
    }
  },
  "settings": {
    "env": {
      "CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS": "1"
    },
    "teammateMode": "in-process"
  }
}
```

When `RDF_AGENT_TEAMS=true`, `rdf generate claude-code` includes Agent Teams
configuration in the generated output.

## 8. Migration Path

### Phase A: Abstraction (this phase)
- lib/dispatch.sh generates instructions
- mgr.md/mgr command updated to consume dispatch output
- Feature flag defaults to false
- No behavioral change for current users

### Phase B: Opt-in Testing (future)
- Set RDF_AGENT_TEAMS=true
- EM operates as team lead in delegate mode
- Test with tier 2+ phases (parallel QA + Sentinel benefits most)
- Compare token costs and wall time

### Phase C: Default Flip (future, after API stabilizes)
- Change default to true
- Subagent mode remains available via RDF_AGENT_TEAMS=false
- Document migration notes
