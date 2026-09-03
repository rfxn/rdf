# Task-Class Tiers

Single source of truth for RDF's scale-adaptive ceremony. One tier value —
the closed set `full | quick-plan | bugfix` — is chosen once (at `/r-spec` or
`/r-plan` entry, recorded as a `**Tier:**` plan marker and session-scoped in
`.rdf/active-tier-${RDF_SESSION_ID}`) and every downstream verb reads it. The
tier scales Clarify, plan review, build gates, and the living-spec fold
*together*. `full` is the default on every path — an absent marker, an empty
pointer, or a bare-Enter selection all resolve to `full`, so untiered work
behaves exactly as it does today.

`/r-spec`, `/r-plan`, `/r-build`, and `dispatcher` cite this file; none restate
the gate table.

## Definitions

The tier scales five ceremonies at once:

| Tier | Clarify | Spec artifact | Plan review | Build gates (dispatcher) | Living spec |
|------|---------|---------------|-------------|--------------------------|-------------|
| `full` | full pass | `docs/specs/*.md` | challenge review | scope→gate map (unchanged) | fold on ship |
| `quick-plan` | 1 round | condensed, folded | single review | cap at sentinel-lite | optional |
| `bugfix` | skipped | none (test-first) | schema-only | Gate 1 + regression-lite | skipped |

## Heuristic signals (suggestion only — the user always confirms)

The tier prompt *suggests* a tier from the signals below; it never
auto-selects. On a bare Enter the prompt defaults to `[1] full`.

- **`bugfix`** — the input is a bug/issue reference or describes a defect in
  existing behavior, the scope looks single-file, and a reproducing test can
  be written first.
- **`quick-plan`** — the change is well-understood, touches ≤ ~3 files, and has
  no open architecture questions.
- **`full`** — otherwise. The default on any ambiguity or multi-component work.

## Gate caps

The tier acts as a **Tier Cap**: a ceiling applied *after* the dispatcher's
existing scope→gate selection, but the Security floor below always wins.
Effective gate set is `max(security_floor, min(scope_gate, tier_cap))` — the
cap only *removes* ceremony (security floor aside), never adds it. It can
never raise a `scope:docs` phase's gates, and it can never lower gates below
the security floor.

- **`full`** — no cap. The scope→gate mapping applies as-is.
- **`quick-plan`** — cap Gate 3 at sentinel-lite (2-pass), skip the End-of-Plan
  Sentinel, keep Gates 1+2; Gate 4 (UAT) only if the file list forces it.
- **`bugfix`** — Gate 1 + a regression-only sentinel-lite; skip Gate 2's full
  matrix (run the single regression test), skip Gate 4, skip the End-of-Plan
  Sentinel. The engineer MUST land the failing test first (red→green).

### Security floor (overrides the cap — non-negotiable)

The Security floor evaluates FIRST and the cap NEVER applies against it. When
the dispatcher marks a phase `scope:sensitive`, OR any changed file matches the
security-sensitive indicators, `bugfix`/`quick-plan` still run Gate 2 and a
sentinel-full (3-pass, Security included) pass regardless of tier. Effective
selection is `max(security_floor, min(scope_gate, tier_cap))`.

The indicator list is **reused verbatim** from the reviewer Early-Exit Rubric
(`reviewer.md:183-187`) — do NOT define a second list:

- filename contains `auth`, `cred`, `secret`, `token`, `key`, `passwd`,
  `encrypt`, `hash`, `sign`, `cert`, `session`, or `permission`; or
- the path is flagged security-sensitive in `governance/anti-patterns.md`; or
- the phase is `scope:sensitive`.

Rationale: the 3.3.0 Critical RCE fix (C1, `context-audit.sh`) was a
single-file change with a reproducing test and an issue ref — the exact shape
the `bugfix` heuristic matches. A tier must never let a security patch skip the
Security pass or the QA gate.
