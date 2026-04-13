# Model Cost Optimization — Sonnet Default + Scope-Based Opus Routing

**Date:** 2026-04-12
**Status:** Draft
**Author:** Ryan MacDonald / Claude

---

## 1. Problem Statement

All RDF-managed sessions run on Opus 4.6 by default. The main
conversation handles interactive work — file reads, git commands,
informational commands (`/r-start`, `/r-status`, `/r-save`), build
orchestration — at the Opus token rate. Agent model assignments in
`agent-meta.json` are static: engineer, planner, and reviewer always
dispatch at Opus regardless of task complexity.

Analysis of actual work patterns shows:
- ~85% of main-thread turns are read/execute/render (no deep reasoning)
- Comment discipline, changelog dedup, and vendored lib sync (recent
  high-volume work) are mechanical tasks suited to Sonnet
- The v2→v3 consolidation moved two formerly-Sonnet roles (challenger,
  po/scope) into Opus agents, increasing cost without proportional
  quality gain for those specific tasks
- Challenge review (structural completeness checks) runs at Opus
  despite being pattern-matching, not adversarial reasoning

The dispatcher already classifies scope into 5 levels (docs → focused
→ multi-file → cross-cutting → sensitive) for gate selection. This
classification is not used for model routing — a missed optimization.

## 2. Goals

1. **Default session model is Sonnet 4.6** — new sessions start on
   Sonnet without manual intervention
2. **Engineer dispatches on Sonnet for scope:docs and scope:focused** —
   dispatcher routes model based on existing scope classification
3. **Reviewer dispatches on Sonnet for challenge mode** — all challenge
   review dispatch points pass model override
4. **Opus reserved for high-complexity paths** — engineer multi-file+,
   reviewer sentinel, planner subagent
5. **Zero quality regression on complex work** — shell portability,
   security, cross-project blast radius paths stay Opus
6. **No agent count change** — 6 agents remain; routing is dynamic,
   not structural

## 3. Non-Goals

- Changing effort level (stays `high` per user direction)
- Splitting reviewer into two agents (decided against — maintenance > benefit)
- Downgrading planner from Opus (cheap insurance for rare subagent dispatch)
- Changing QA, UAT, or dispatcher model assignments (already Sonnet)
- Modifying agent-meta.json model fields (all static assignments unchanged)
- Adding model routing to `/r-ship` or `/r-audit` (sentinel-only, stays Opus)
- Restructuring the generate pipeline or adapter.sh

## 4. Architecture

### File Map

| File | Action | Est. Lines Changed | Purpose |
|------|--------|-------------------|---------|
| `canonical/agents/dispatcher.md` | Modify | +12 | Add model routing table after gate mapping |
| `canonical/commands/r-review.md` | Modify | +3 | Add Sonnet override for challenge dispatch |
| `canonical/commands/r-spec.md` | Modify | +3 | Add Sonnet override for challenge review dispatch |
| `canonical/commands/r-plan.md` | Modify | +3 | Add Sonnet override for challenge review dispatch |
| `/root/.claude/settings.json` | Modify | +1 | Add `"model": "claude-sonnet-4-6"` |

### No-Touch Files

These files are explicitly NOT modified:

| File | Reason |
|------|--------|
| `adapters/claude-code/agent-meta.json` | All static model assignments stay the same |
| `adapters/claude-code/adapter.sh` | Generate pipeline unchanged |
| `canonical/agents/reviewer.md` | Agent prompt unchanged; model routing is at dispatch point |
| `canonical/agents/engineer.md` | Agent prompt unchanged; model routing is in dispatcher |
| `canonical/agents/planner.md` | Stays Opus |
| `canonical/agents/qa.md` | Already Sonnet |
| `canonical/agents/uat.md` | Already Sonnet |
| `canonical/commands/r-ship.md` | Sentinel-only dispatches, Opus default correct |
| `canonical/commands/r-audit.md` | Sentinel-only dispatches, Opus default correct |
| `canonical/commands/r-build.md` | Delegates to dispatcher, no direct model logic |

### Size Comparison

| Metric | Before | After |
|--------|--------|-------|
| Agent count | 6 | 6 (unchanged) |
| agent-meta.json model fields | 3 opus, 3 sonnet | 3 opus, 3 sonnet (unchanged) |
| Dispatcher model routing | none | 6-line table |
| Challenge dispatch overrides | 0 | 3 commands |
| Default session model | opus (implicit) | sonnet (explicit) |

### Dependency Tree

```
settings.json (session default: sonnet)
  └─ main conversation runs on sonnet
     ├─ /r-start, /r-status, /r-save → sonnet (session)
     ├─ /r-spec → sonnet (session)
     │   └─ dispatches reviewer (challenge) → sonnet (override)
     ├─ /r-plan → sonnet (session)
     │   └─ dispatches reviewer (challenge) → sonnet (override)
     ├─ /r-review
     │   ├─ --challenge → dispatches reviewer → sonnet (override)
     │   └─ --sentinel → dispatches reviewer → opus (agent default)
     ├─ /r-build → sonnet (session)
     │   └─ dispatches dispatcher (sonnet, agent default)
     │       ├─ scope:docs/focused → engineer sonnet (override)
     │       ├─ scope:multi-file+ → engineer opus (agent default)
     │       ├─ gate 3 sentinel → reviewer opus (agent default)
     │       ├─ gate 2 → qa sonnet (agent default)
     │       └─ gate 4 → uat sonnet (agent default)
     ├─ /r-ship → sonnet (session)
     │   └─ dispatches reviewer (sentinel) → opus (agent default)
     └─ /r-audit → sonnet (session)
         └─ dispatches reviewer (sentinel) → opus (agent default)

agent-meta.json (static, unchanged):
  planner: opus | dispatcher: sonnet | engineer: opus
  qa: sonnet    | uat: sonnet        | reviewer: opus
```

### Key Changes

1. **Session default** — `settings.json` gets `"model": "claude-sonnet-4-6"`.
   All slash commands, interactive work, and informational commands
   run on Sonnet. Agents with explicit `model:` frontmatter override
   this at dispatch time.

2. **Dispatcher model routing** — new section in `dispatcher.md` after
   the existing gate mapping block. Maps scope classification to
   engineer model. Only docs and focused get Sonnet; multi-file and
   above use the engineer's Opus default (no override passed).

3. **Challenge review Sonnet override** — three commands (`r-spec.md`,
   `r-plan.md`, `r-review.md`) add a model override instruction to
   their reviewer dispatch sections. When dispatching challenge mode,
   pass `model: "sonnet"`. Sentinel dispatches from these commands
   (and from dispatcher, `/r-ship`, `/r-audit`) pass no override,
   using the reviewer's Opus default.

### Dependency Rules

- Model routing in dispatcher depends on scope classification — scope
  classification must exist before model routing can reference it
  (already true in current codebase)
- Challenge override in commands is independent — each command is
  self-contained
- settings.json change is independent of all RDF file changes
- `rdf generate claude-code` must be run after canonical changes to
  propagate to deployed agents/commands

## 5. File Contents

### 5.1 `canonical/agents/dispatcher.md` — Change Inventory

| Section | Current behavior | New behavior | Lines affected |
|---------|-----------------|--------------|----------------|
| After Gate mapping (L98-109) | No model routing | Model routing table for engineer dispatch | Insert after L109 |
| After Gate mapping | No reviewer model routing | Model override for challenge-mode reviewer dispatch | Insert after engineer routing |

**New content (insert after line 109, before "### Parallel Gate Execution"):**

```
Model routing (engineer dispatch):
  scope:docs          → pass model: "sonnet" to engineer dispatch
  scope:focused       → pass model: "sonnet" to engineer dispatch
  scope:multi-file    → no override (engineer default: opus)
  scope:cross-cutting → no override (engineer default: opus)
  scope:sensitive     → no override (engineer default: opus)

  When dispatching the engineer subagent, include the model parameter
  in the Agent call if the scope requires a downgrade. Omit the model
  parameter for multi-file and above — the agent's frontmatter default
  (opus) applies automatically.

Model routing (reviewer dispatch):
  Gate 3 (sentinel)     → no override (reviewer default: opus)
  Challenge mode        → pass model: "sonnet" to reviewer dispatch
  End-of-plan sentinel  → no override (reviewer default: opus)
```

### 5.2 `canonical/commands/r-review.md` — Change Inventory

| Section | Current behavior | New behavior | Lines affected |
|---------|-----------------|--------------|----------------|
| Section 5: Dispatch (L99-107) | Dispatches reviewer with no model parameter | Adds model: "sonnet" for challenge mode | L101, +2 lines |

**Current (line 101):**
```
Dispatch the `rdf-reviewer` subagent with the assembled payload.
```

**New:**
```
Dispatch the `rdf-reviewer` subagent with the assembled payload.

Model override: If mode is `challenge`, pass `model: "sonnet"` in
the Agent dispatch call. If mode is `sentinel`, do not pass a model
parameter — the reviewer's default (opus) applies.
```

### 5.3 `canonical/commands/r-spec.md` — Change Inventory

| Section | Current behavior | New behavior | Lines affected |
|---------|-----------------|--------------|----------------|
| Phase 3.2: Challenge Review (L466-471) | Dispatches reviewer with no model parameter | Adds model: "sonnet" for challenge dispatch | ~L471, +2 lines |

**Current (around line 471):**
```
Dispatch the reviewer agent in challenge mode. The dispatch prompt
must include the quality standard as an explicit checklist:
```

**New:**
```
Dispatch the reviewer agent in challenge mode with `model: "sonnet"`.
Challenge review is structural pattern-matching, not adversarial
reasoning — Sonnet handles it at full quality. The dispatch prompt
must include the quality standard as an explicit checklist:
```

### 5.4 `canonical/commands/r-plan.md` — Change Inventory

| Section | Current behavior | New behavior | Lines affected |
|---------|-----------------|--------------|----------------|
| Section 3.1: Plan Review (L364-365) | Dispatches reviewer with no model parameter | Adds model: "sonnet" for challenge dispatch | L364, +2 lines |

**Current (line 364-365):**
```
After writing the full plan, dispatch the reviewer agent in challenge
mode. The dispatch prompt must include the quality standard as an
```

**New:**
```
After writing the full plan, dispatch the reviewer agent in challenge
mode with `model: "sonnet"`. Challenge review is structural — Sonnet
handles plan completeness checks at full quality. The dispatch prompt
must include the quality standard as an
```

### 5.5 `/root/.claude/settings.json` — Change Inventory

| Key | Current | New |
|-----|---------|-----|
| `model` | (absent) | `"claude-sonnet-4-6"` |

Add `"model": "claude-sonnet-4-6"` as a top-level key.

## 5b. Examples

**Before — main session starts:**
```
$ claude
> Model: claude-opus-4-6
> /r-start
(all informational work runs on Opus)
```

**After — main session starts:**
```
$ claude
> Model: claude-sonnet-4-6
> /r-start
(informational work runs on Sonnet)
> /r-build 3
  (dispatches dispatcher on Sonnet)
  (dispatcher classifies scope:focused → engineer dispatched on Sonnet)
  (dispatcher classifies scope:cross-cutting → engineer dispatched on Opus)
  (gate 3 sentinel → reviewer dispatched on Opus)
```

**Before — challenge review:**
```
/r-review --challenge docs/specs/my-spec.md
  → dispatches rdf-reviewer at model: opus (agent default)
```

**After — challenge review:**
```
/r-review --challenge docs/specs/my-spec.md
  → dispatches rdf-reviewer at model: sonnet (command override)
```

**Override for Opus session when needed:**
```
$ claude
> Model: claude-sonnet-4-6
> /model opus
> Model: claude-opus-4-6
(session now runs on Opus for complex interactive work)
```

## 6. Conventions

**Model override syntax** — when a command or agent prompt instructs
a model override, the pattern is:

```
pass `model: "sonnet"` in the Agent dispatch call
```

This maps to the Claude Code Agent tool's `model` parameter. The
string value is the short form (`"sonnet"`, `"opus"`) not the full
model ID.

Prior art: `canonical/commands/r-sync.md` line 127 uses `model: opus`
in a dynamic Agent dispatch, confirming short-form model names work
at the dispatch layer.

**Override vs default** — the convention is "override when downgrading,
omit when using the agent's default." This means:
- Sonnet overrides are explicit (`model: "sonnet"`)
- Opus paths use no override (the agent's frontmatter default applies)
- This ensures Opus is never accidentally downgraded by a missing override

## 7. Interface Contracts

Internal refactor — no user-facing output changes. The model selection
is invisible to the end user. Agent reports, finding formats, and
command output are unchanged.

The only user-visible change: new sessions start on Sonnet instead of
Opus. The `/model` command remains available for manual override.

## 8. Migration Safety

### Upgrade path
- `settings.json` change takes effect on next session start
- RDF canonical changes propagate via `rdf generate claude-code`
- No state migration needed — model routing is stateless

### Rollback
- Remove `"model": "claude-sonnet-4-6"` from settings.json → reverts
  to Opus default
- Revert canonical changes and regenerate → removes model routing
- Both are single-commit reverts

### Backward compatibility
- Agent-meta.json model fields are unchanged — no impact on existing
  worktrees, sessions, or cached agent definitions
- Commands without the model override instruction still work — reviewer
  dispatches at Opus (the default), which is correct but not optimized

### Test suite impact
- No test changes — model routing is in markdown prompts, not runtime code
- Verification is via grep (see Section 10b)

### CHANGELOG
- Commits touching canonical files must update CHANGELOG and
  CHANGELOG.RELEASE per RDF CLAUDE.md conventions

### Fresh install
- `settings.json` is managed by setup scripts on fresh installs.
  The `"model": "claude-sonnet-4-6"` key is a user-environment
  setting, not a governance artifact — it applies to the current
  workstation only. Fresh installs on other machines will need the
  same manual settings.json edit or a follow-on setup.sh update
  (deferred — out of scope for this spec)

## 9. Dead Code and Cleanup

No dead code found. The `lib/dispatch.sh` module (deprecated v2
dispatch abstraction) references model fields in its JSON registry
pattern, but it's already marked deprecated and out of scope for
this spec.

## 10a. Test Strategy

RDF changes are markdown definitions verified by grep and
`rdf generate claude-code`. No BATS tests apply.

| Goal | Verification method | Check |
|------|-------------------|-------|
| Goal 1 (session default) | Inspect settings.json | `model` key present with correct value |
| Goal 2 (engineer routing) | Grep dispatcher.md | Model routing table with scope→model mapping |
| Goal 3 (reviewer challenge) | Grep r-review, r-spec, r-plan | `model: "sonnet"` in challenge dispatch sections |
| Goal 4 (Opus preserved) | Grep agent-meta.json | engineer, reviewer, planner still `"model": "opus"` |
| Goal 5 (no quality regression) | Grep agent-meta.json + dispatcher | No Opus→Sonnet changes for multi-file+/sentinel paths |
| Goal 6 (agent count) | Count agents in agent-meta.json | Still 6 |

## 10b. Verification Commands

```bash
# Goal 1: settings.json has Sonnet default
python3 -c "import json; d=json.load(open('/root/.claude/settings.json')); print(d.get('model','MISSING'))"
# expect: claude-sonnet-4-6

# Goal 2: dispatcher has model routing table
grep -c 'Model routing' canonical/agents/dispatcher.md
# expect: 2 (engineer routing + reviewer routing)

grep 'scope:docs.*sonnet\|scope:focused.*sonnet' canonical/agents/dispatcher.md
# expect: 2 matches

grep 'scope:multi-file.*opus\|scope:cross-cutting.*opus\|scope:sensitive.*opus' canonical/agents/dispatcher.md
# expect: 3 matches

# Goal 3: challenge dispatch points have Sonnet override
grep -c 'model.*sonnet.*challenge\|challenge.*model.*sonnet' canonical/commands/r-review.md
# expect: >= 1

grep -c 'model.*sonnet.*challenge\|challenge.*model.*sonnet' canonical/commands/r-spec.md
# expect: >= 1

grep -c 'model.*sonnet.*challenge\|challenge.*model.*sonnet' canonical/commands/r-plan.md
# expect: >= 1

# Goal 4: agent-meta.json Opus assignments unchanged
python3 -c "
import json
d=json.load(open('adapters/claude-code/agent-meta.json'))
for a in ['planner','engineer','reviewer']:
    print(f\"{a}: {d[a]['model']}\")
"
# expect:
# planner: opus
# engineer: opus
# reviewer: opus

# Goal 5: no Opus→Sonnet change in agent-meta.json
python3 -c "
import json
d=json.load(open('adapters/claude-code/agent-meta.json'))
for a in ['dispatcher','qa','uat']:
    print(f\"{a}: {d[a]['model']}\")
"
# expect:
# dispatcher: sonnet
# qa: sonnet
# uat: sonnet

# Goal 6: agent count unchanged
python3 -c "
import json
d=json.load(open('adapters/claude-code/agent-meta.json'))
agents=[k for k in d if k != 'commands']
print(f'agents: {len(agents)}')
"
# expect: agents: 6

# Regeneration check
bash bin/rdf generate claude-code 2>&1 | tail -3
# expect: success, no errors

# Deployed agents have correct models after regeneration
grep '^model:' adapters/claude-code/output/agents/*.md
# expect:
# dispatcher.md:model: sonnet
# engineer.md:model: opus
# planner.md:model: opus
# qa.md:model: sonnet
# reviewer.md:model: opus
# uat.md:model: sonnet
```

## 11. Risks

1. **Dispatcher fails to apply engineer model override** — scope
   classification is deterministic (file count + path matching), and
   the routing table is a simple lookup. The failure mode is engineer
   runs on Opus for a docs change (waste, not quality loss).
   Mitigation: verification grep confirms routing table exists in
   generated output.

2. **New command dispatches challenge review without Sonnet override** —
   future commands that dispatch reviewer in challenge mode might not
   include the override instruction.
   Mitigation: document the convention in Section 6. The failure mode
   is Opus on challenge (waste). Add a comment in the dispatcher's
   model routing section noting all challenge dispatch points.

3. **`claude-sonnet-4-6` model ID changes in future Claude releases** —
   model IDs evolve. The settings.json value may need updating.
   Mitigation: single-line change in settings.json. No RDF canonical
   files reference the full model ID (they use short form "sonnet").

4. **User forgets to `/model opus` for a session requiring Opus
   reasoning** — interactive architectural discussions may benefit from
   Opus reasoning depth that Sonnet lacks.
   Mitigation: `/model opus` is available. The cost of occasionally
   switching is low. Most interactive work (code reading, debugging,
   following plans) is well within Sonnet's capabilities.

## 11b. Edge Cases

| Scenario | Expected behavior | Handling |
|----------|-------------------|---------|
| Dispatcher cannot determine scope (falls back to `scope:multi-file`) | Engineer dispatched at Opus (default) | Default scope is multi-file → no model override → Opus. Correct behavior — when in doubt, use the expensive model |
| `/r-review` with no flags (defaults to sentinel) | Reviewer dispatched at Opus | No override applied for sentinel default. Correct |
| `/r-review --challenge` on a complex spec | Reviewer dispatched at Sonnet | Challenge review is structural completeness, not adversarial reasoning. Sonnet handles this at v2-equivalent quality |
| `rdf generate claude-code` run without canonical changes | Regenerates with existing agent-meta.json models | No impact — model fields in agent-meta.json are unchanged |
| User runs `/model opus` then dispatches `/r-build` | Dispatcher still runs on Sonnet (agent frontmatter override) | Agent `model:` frontmatter overrides session model. Dispatcher runs Sonnet regardless of session setting |
| Parallel batch dispatch — multiple dispatchers | Each dispatcher independently classifies scope and routes model | Scope classification is per-phase, model routing follows. No cross-phase interference |
| End-of-plan sentinel dispatch | Reviewer dispatched at Opus | End-of-plan sentinel is explicitly a sentinel dispatch (not challenge). No override applied |
| Finding-fix engineer dispatch from dispatcher | Engineer dispatched at Opus | Finding-fix is always multi-file+ severity work. Dispatcher does not apply scope downgrade for fix dispatches |

## 12. Open Questions

None — all design questions resolved in brainstorm phase.
