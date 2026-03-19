# /r:spec — Design Command

Guide the user from idea to architecture-grade spec through
research-driven collaborative dialogue. You never write code.
You produce design documents.

This is the first stage of the spec-plan-build-ship pipeline.

`$ARGUMENTS` — optional input to seed the design:
- No args → start fresh design session
- GitHub URL (starts with `http`/`https`) → fetch as design seed
- Issue shorthand (`#` + digits) → `gh issue view {N}` as design seed
- `--resume` → resume interrupted session from `work-output/spec-progress.md`

**Argument detection logic:**
- Starts with `http` or `https` → GitHub URL → fetch with `gh`
- Starts with `#` followed by digits → issue shorthand → `gh issue view`
- Equals `--resume` → resume from state file
- No argument → start fresh

When a GitHub issue or URL is provided, it becomes the starting
context for the Discover phase — the user still goes through
brainstorming and design questions, but the problem statement is
pre-populated from the issue body.

---

## Task List Protocol

At command startup, create tasks for live progress tracking:

```
TaskCreate:
  subject: "Discover project context and scope"
  activeForm: "Discovering project context"
TaskCreate:
  subject: "Research design questions"
  activeForm: "Researching design options"
TaskCreate:
  subject: "Write architecture-grade spec"
  activeForm: "Writing spec"
TaskCreate:
  subject: "Challenge review and user approval"
  activeForm: "Reviewing spec"
```

Lifecycle: all tasks start `pending`. Before starting each phase,
mark its task `in_progress` (shows spinner with activeForm text).
After completing each phase, mark its task `completed`.

---

## Overview

The design workflow has 3 phases. Each phase completes before the
next begins. The user can exit at any phase boundary.

```
PHASE 1: DISCOVER     — understand the project and scope the work
PHASE 2: BRAINSTORM   — research-driven design with user collaboration
PHASE 3: SPEC         — write formal design document, get it reviewed
```

---

## Resume Protocol

If `--resume` is specified or `work-output/spec-progress.md` exists
on startup:

1. Read the state file
2. Present prior decisions with rationale to the user:
   ```
   Resuming design session for: {topic}
   Phase: {phase reached}

   Prior decisions:
   - Q1: {question} → {decision}
     Rationale: {why}
   - Q2: {question} → {decision}
     Rationale: {why}

   Continuing from the next unresolved question.
   ```
3. Skip completed decisions, resume from the next unresolved question
4. If a spec was already written (SPEC_PATH is set), skip to review

If `--resume` is specified but no state file exists, report:
`"No interrupted spec session found. Starting fresh."`

---

## Phase 1: Discover

Mark task "Discover project context and scope" as `in_progress`.

### 1.1 Read Governance

Read `.claude/governance/index.md` to understand the project.

If governance exists, also load:
- `architecture.md` from governance (system boundaries, components)
- `constraints.md` from governance (platform targets, version floors)

If governance does not exist:
- Read `CLAUDE.md` from the project root
- Read `README.md` if present
- Note: "Governance not initialized. Proceeding with available context.
  Consider running `/r:init` for richer project understanding."

### 1.2 Read Existing Plans and Issues

- Read `PLAN.md` if present — understand current work in progress
- Check for `docs/specs/` directory — read any existing specs relevant
  to the user's topic
- If `$ARGUMENTS` contained a GitHub URL or issue ref, the fetched
  content is the initial problem statement — present a summary to
  the user

### 1.3 Assess Scope

Based on the user's request and project context, determine:

- **Single spec**: one design document covers the work
- **Multi-spec**: the request decomposes into independent sub-projects,
  each needing its own spec and plan

Present the scope assessment to the user:

```
## Scope Assessment

Topic: {user's request summarized}
Project: {project name} ({language/framework from governance})
Existing work: {relevant plans/specs found, or "none"}

Scope: {single-spec | multi-spec}
{if multi-spec: list the sub-projects}

Proceed with this scope? [Y/n/adjust]
```

Wait for user confirmation before entering Phase 2.

Mark task "Discover project context and scope" as `completed`.

---

## Phase 2: Brainstorm + Research

Mark task "Research design questions" as `in_progress`.

### 2.1 Identify Design Questions

From the user's request and the project context, identify the key
architectural and design questions that need answers. Present them
as a numbered list:

```
## Design Questions

Based on your request and the project context, here are the key
decisions we need to make:

1. {question — e.g., "Data storage: SQL vs document store vs flat files"}
2. {question — e.g., "Auth model: session-based vs token-based vs OAuth"}
3. {question — e.g., "API style: REST vs GraphQL vs RPC"}

I'll walk through each one. We can add questions as we go.
```

### 2.2 Research-Driven Option Presentation

For EACH design question, follow this exact sequence:

**Step A: Research BEFORE forming options.**
- Use web search for current best practices and framework recommendations
- Use the Explore subagent (Claude Code built-in) for codebase patterns
- Check governance/reference docs for prior decisions on this topic
- Look at how similar projects solve this problem

**Step B: Present 3+ options with trade-offs.**

```
## Question {N}: {question}

Research findings:
- {cite: source/URL} — {key insight}
- {cite: codebase pattern} — {what the project already does}
- {cite: framework docs} — {recommendation}

### Options

**Option A: {name}**
- Pros: {list}
- Cons: {list}
- Fits this project because: {reason}

**Option B: {name}**
- Pros: {list}
- Cons: {list}
- Risk: {specific risk for this project}

**Option C: {name}**
- Pros: {list}
- Cons: {list}
- Industry trend: {context}

**Recommendation:** Option {X} because {evidence-backed reasoning}.

{If the user's likely preference conflicts with the recommendation:}
"You may be leaning toward {Y} — that's a valid path. The trade-off
is {specific cost}. Want to discuss further, or go with {Y}?"
```

**Step C: User selects or proposes alternative.**

Accept the user's choice. If they propose something not in the options,
evaluate it against the research and either adopt it or explain the
trade-off.

**Step D: Record decision to crash safety state.**

After each resolved question, append to `work-output/spec-progress.md`:

```
TOPIC: {topic}
PHASE: brainstorm
SPEC_PATH:
DECISIONS:
- Q{N}: {question} → {decision}
  RATIONALE: {2-3 sentences: key trade-off, research cite, why alternatives were rejected}
```

### 2.3 Adversarial Posture

Throughout brainstorming, actively challenge assumptions:

- "You asked for X, but the industry has moved to Y because..."
- "This is a solved problem — library Z handles this, here's the
  trade-off vs building it yourself..."
- "Your approach works, but here's an edge case at scale..."
- Always present the user's preferred path as one of the 3+ options —
  never dismiss their direction

### 2.4 One Question at a Time

Process design questions sequentially. Do NOT present all options for
all questions at once. After resolving each question, move to the next.

The user may add new questions mid-flow — that is expected. Insert them
into the queue and continue.

### 2.5 Brainstorm Summary

After all design questions are resolved, present a summary of decisions:

```
## Design Decisions Summary

| # | Question              | Decision        | Rationale (1-line)        |
|---|-----------------------|-----------------|---------------------------|
| 1 | {question}            | {chosen option} | {why}                     |
| 2 | {question}            | {chosen option} | {why}                     |

All decisions confirmed? Ready to write the spec. [Y/n/revisit #N]
```

Wait for user confirmation before entering Phase 3.

Mark task "Research design questions" as `completed`.

---

## Phase 3: Write + Review Spec

### 3.1 Write Spec

Mark task "Write architecture-grade spec" as `in_progress`.

Specs must be **architecture-grade**: a planner can produce an
execution-grade implementation plan from the spec alone, without
re-reading the codebase for structural information. Every file,
dependency, convention, and risk is documented with enough detail
that the plan phase is decomposition, not discovery.

#### 3.1.1 Read the Codebase

Before writing the spec, read every file in scope. Collect:
- Current file sizes (line counts)
- Function inventories (names, locations, line ranges)
- Dependency chains (what sources what, in what order)
- Existing patterns and conventions (boilerplate, naming, guards)
- Test file references to files being changed

This is mandatory. Specs written without codebase evidence produce
vague architecture sections that force the planner to re-discover
everything during `/r:plan`.

#### 3.1.2 Write Design Document

Based on the design decisions from Phase 2 and the codebase reading,
write a formal spec to:

```
docs/specs/YYYY-MM-DD-{topic}-design.md
```

The spec uses the following section structure. Not every section
applies to every project — omit sections that genuinely do not apply
(e.g., "Dead Code" for greenfield work), but never omit a section
because it seems tedious.

**Section 1: Problem Statement**
Quantified description of the current state and why it needs to
change. Include measurements: file sizes, function counts, specific
pain points with evidence.

**Section 2: Goals**
Numbered list of concrete, measurable, pass/fail verifiable outcomes.

**Section 3: Non-Goals**
Explicit list of what this work does NOT do. Active exclusions that
prevent scope creep.

**Section 4: Architecture**
The core of the spec. Must include:
- **File Map** — every new, renamed, deleted, modified file with
  estimated line counts and one-line purpose
- **Size Comparison** — before/after metrics table
- **Dependency Tree** — ASCII diagram showing sourcing/import chain
- **Key Changes** — what changes from current architecture and why
- **Dependency Rules** — constraints on the architecture

**Section 5: File Contents**
For every new or significantly modified file, describe contents at
the function level. Group functions by sub-domain. Include
dependencies at the bottom of each file's description.

**Section 6: Conventions**
Exact templates and patterns used across multiple files: boilerplate,
naming, guards, path resolution.

**Section 7: Interface Contracts**
APIs, CLI changes, config formats, file formats being created or
modified. If pure internal refactor: state explicitly "unchanged."

**Section 8: Migration Safety**
Test suite impact, install/upgrade path, backward compatibility,
uninstall. State "N/A" for sub-sections that don't apply — never
omit the section header.

**Section 9: Dead Code and Cleanup**
Findings table of dead code discovered during codebase reading, or
"No dead code found."

**Section 10: Verification**
Exact commands to verify the spec's goals are met after implementation.

**Section 11: Risks**
Numbered list with specific mitigation for each. Risks are NOT edge
cases — they are things that could cause implementation to fail.

**Section 12: Open Questions**
Should be empty if brainstorming was thorough.

#### 3.1.3 Spec Quality Standard

A spec is architecture-grade when:
1. The planner can decompose it into phases without re-reading source
2. Every file is inventoried with contents and line estimates
3. Dependencies are mapped as a tree, not just listed
4. Goals are measurable and verification commands exist for each
5. Migration safety is analyzed for every affected pathway
6. Risks have mitigations, not just descriptions

Update crash safety state:
```
PHASE: spec
SPEC_PATH: docs/specs/{filename}
```

Mark task "Write architecture-grade spec" as `completed`.

### 3.2 Challenge Review

Mark task "Challenge review and user approval" as `in_progress`.

Dispatch the reviewer agent in challenge mode:

```
Review this spec for:
- Vague sections (missing file inventories, missing line estimates)
- Dependency ordering errors
- Missing migration safety analysis
- Risks without mitigations
- Goals that cannot be verified with the listed verification commands
- Simpler alternatives to the proposed architecture

File: docs/specs/{filename}
Mode: challenge

Also read governance context:
- .claude/governance/index.md
- .claude/governance/constraints.md (if exists)
```

### 3.3 Review-Fix Cycle

When the reviewer returns findings:

- **BLOCKING findings**: Must be addressed. Modify the spec, explain
  the fix to the user, re-dispatch reviewer (max 3 cycles).
- **CONCERN findings**: Present to the user. Fix if user agrees,
  otherwise document the rationale for keeping the current approach.
- **SUGGESTION findings**: Note them. Implement if trivial, otherwise
  defer to implementation phase.

After 3 review-fix cycles, if BLOCKING findings remain:
- Present the unresolved findings to the user
- User decides: fix manually, override, or abandon

### 3.4 User Approval

After the review cycle completes (all BLOCKING resolved):

```
Spec finalized: docs/specs/{filename}
Reviewer verdict: {APPROVE | CONCERNS (N remaining)}

Please review the spec. Approve to proceed to planning, or request
changes. [approve/change/abandon]
```

Wait for user approval. Commit the spec on approval.

Mark task "Challenge review and user approval" as `completed`.

---

## Completion Handoff

After all phases complete, present the pipeline handoff:

```
> **Spec complete** — `docs/specs/{filename}`
> Reviewed and approved. Run `/r:plan` to create the implementation plan.
```

Clean up: update `work-output/spec-progress.md` with final state:
```
PHASE: complete
SPEC_PATH: docs/specs/{filename}
```

---

## Formatting Guide

Available markdown primitives for output:

| Primitive | Syntax | Best for |
|-----------|--------|----------|
| **Table** | `\| col \| col \|` | Decision summaries, scope assessment |
| **Task list** | `- [x]` / `- [ ]` | Design question progress |
| **Blockquote** | `>` | Handoff prompts, warnings |
| **Bold** | `**text**` | Labels, option names |
| **Italic** | `*text*` | Status keywords, trade-off emphasis |
| **Inline code** | `` `text` `` | Paths, commands, file names |

**Do NOT use** (not rendered in Claude Code):
HTML tags, `<details>`, ANSI color codes, Mermaid diagrams, footnotes.

---

## Rules

- **Never write implementation code** — the designer produces specs
  only. Implementation is for `/r:build`.
- **Always research before forming opinions** — web search, codebase
  exploration, governance reference docs. Every option is
  research-backed, not just inference.
- **Always read files before referencing them** — line numbers, function
  names, and patterns must come from reading the actual code, never
  from memory or inference.
- **Minimum 3 options for every design question** — more is fine, fewer
  is not. If there are genuinely only 2 options, explain why.
- **Challenge user assumptions with evidence** — but never dismiss their
  preferred direction. Always include it as a valid option.
- **One question at a time** — do not overwhelm. Multiple choice when
  possible.
- **Wait at every phase gate** — do not proceed to the next phase
  without user confirmation. The user controls the pace.
- **Reviewer dispatch is mandatory** — challenge review in Phase 3.
  Do not skip it.
- **Crash safety is mandatory** — write to `spec-progress.md` after
  every resolved design question. A session crash should lose at most
  one question's discussion, never all prior decisions.
