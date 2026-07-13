# RDF Simplicity-Budget Audit — 2026-07-13

Applies `reference/simplicity-budget.md` to RDF's own surface. **No cuts are
executed here** — removals are user-facing and several overlap the deferred T5
debt track. This is a candidate list for review, produced as part of 3.2 (T4).

Method: for each surface element, ask "what agent behavior does it change, and
how would I observe that change?" Elements that cannot answer are ceremony.

## Surface inventory

37 commands (21 lifecycle `/r-*`, 16 utility `/r-util-*`) · 6 agents · 7 modes ·
11 profiles · 4-gate review stack (challenge, sentinel, qa, uat).

## Candidates — verify then remove (dead / vestigial)

| Element | Why flagged | Action |
|---------|-------------|--------|
| `lib/rdf_common.sh::rdf_profile_includes` | Unconditional `return 0` since v3 dropped `profile.json` filtering — dead | remove |
| Agent-Teams triad: `docs/specs/dispatch-abstraction.md`, `task-based-coordination.md`, `adapters/claude-code/teams-meta.json`, `lib/dispatch.sh` | Describe an integration RDF's own 2026-04-21 research *rejected* (tool-locked); contradicts the framework | verify unreferenced, then retire |
| `CHANGELOG.RELEASE` | Duplicates the top of `CHANGELOG`; RDF ships no packages, so the dual-file burden (inherited from APF/BFD) has no consumer | consider collapsing to one |
| `profiles/registry.md` "Starter Profiles \| (none…)" | Tombstone row for a removed concept | delete row |

## Candidates — consolidation review (overlap)

- **`/r-util-*` (16 utilities)** — review for overlap, e.g. `code-map` vs
  `code-scan` vs `context-audit` (three structural-read tools); `mem-audit` vs
  `mem-compact`; `chg-dedup` vs `chg-gen`. Each must justify a distinct behavior
  or fold into a sibling.
- **4-gate review stack** — challenge / sentinel / qa / uat. Sentinel and qa
  both re-verify; confirm each gate catches a class the others miss (RDF's own
  lessons-learned says sentinel≠uat — keep both; qa vs sentinel overlap is the
  one to scrutinize).
- **7 modes** — each `context.md` must change agent behavior observably; a mode
  that only re-states the default profile guidance is ceremony.

## Keep (clear behavior justification)

Lifecycle pipeline (`spec→plan→build→ship`, `r-vpe`), the 6 agents, evidence
commands (`r-verify-claim`, `r-review-answer`), `r-context-audit`, core profile
detection. These have stated, observable behavior contracts (now guarded by
`tests/governance-contracts.bats`).

## Note

The verify-then-remove items are the T5 debt track (not selected for 3.2 Core).
Surface reduction is deferred to a follow-up with user review of each cut, per
the budget's "prune on contact, but don't remove behavior you can't confirm is
dead" discipline.
