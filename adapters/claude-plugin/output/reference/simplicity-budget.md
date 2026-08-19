# Simplicity Budget

Every command, mode, profile, gate, and always-on rule is context the model
pays for on every task. Surface has a cost even when it is never invoked — it
competes for attention. This budget makes that cost a first-class constraint.

Grounding: Anthropic's *Building Effective Agents* ("only increase complexity
when it demonstrably improves outcomes"; a framework that obscures prompts and
tempts complexity is a liability) and *Writing effective tools for agents*
("too many overlapping tools distract the agent").

## The rule

- **Earn the surface.** Any new command, mode, profile, gate, or rule must
  demonstrably change agent behavior. If you cannot state the behavior it
  changes and how you would observe it, it is ceremony — do not add it.
- **Consolidate, don't accumulate.** Overlapping tools are worse than one
  slightly-more-general tool. Before adding, ask which existing surface already
  covers 80% of this — extend it instead.
- **Prune on contact.** When working in a command/mode/profile you cannot
  justify, flag it for removal. Dead surface is removed, not preserved.
- **Prefer few high-signal rules.** Always-on rules degrade as they grow; keep
  the set small and each rule short. A long rule list is read less carefully
  than a short one.

## When NOT to orchestrate

Parallelism and subagent fan-out are a large token bet (Anthropic's multi-agent
research put it near 15× single-agent cost). They pay off only for **provably
breadth-first, independent** work — parallel exploration, disjoint file sets,
independent audits.

- **Default to the least machinery.** Serial, single-context execution is the
  default. Escalate to a subagent, then to parallel subagents, only when the
  work is genuinely independent and the breadth justifies the cost.
- **Coding is usually interdependent.** Implementation phases that share
  contracts, touch adjacent files, or depend on each other's output are the case
  to *not* over-parallelize — the coordination cost erases the speedup and
  invites merge conflicts.
- **State the justification.** Fanning out requires an explicit reason that the
  work is breadth-first; absent that reason, stay serial.

## Applies to RDF itself

This budget is a merge gate for RDF's own growth, not only for governed
projects. Adding a command or agent to the framework must clear the same bar.
