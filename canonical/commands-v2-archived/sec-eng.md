Dispatch the Security Engineer agent for security assessment work.

Read CLAUDE.md before taking any action.

## Usage

`/sec-eng` — Start a security assessment of the current project
`/sec-eng <target>` — Assess a specific target (file, component, system)

## Behavior

1. Read CLAUDE.md, MEMORY.md, and any existing AUDIT.md
2. Identify the assessment scope
3. Run offensive/defensive security analysis
4. Report findings with severity, evidence, and recommendations
5. Write results to work-output/

## Agent

Dispatches: rfxn-sec-eng (opus model)
