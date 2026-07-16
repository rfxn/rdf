---
description: >
  Route every finding in a sentinel or challenge report to a structured
---

# /rdf:r-review-answer — Reviewer-Feedback Routing

Route every finding in a sentinel or challenge report to a structured
response — FIX, REBUT, or DEFER — and write an audit-trail artifact.

Advisory by design: it records how each finding was answered and flags
any unanswered MUST-FIX, but it does not block `/rdf:r-build`, `/rdf:r-ship`, or
merge. The value is the trail, not a gate.

## Invocation

```
/rdf:r-review-answer [<report-file>]
/rdf:r-review-answer --from <path>
```

- No argument: resolve the most recent session-scoped report —
  `.rdf/work-output/sentinel-*-${RDF_SESSION_ID}.md`. If none match the
  current session, glob any `sentinel-*.md` and use the newest. If still
  none, report "No review report found — run /rdf:r-review --sentinel first"
  and stop.
- `<report-file>` / `--from <path>`: use the given report. Challenge
  reports (MUST-FIX(blocking-concern) …) are accepted too.

## Protocol

### 1. Resolve and Read the Report

Resolve the report path per the Invocation rules. Read it and confirm it
contains findings; if it has zero findings, report "Report has no
findings — nothing to answer" and stop.

### 2. Parse Findings

Extract each finding with its severity token and locus:

- `MUST-FIX(...)` — answer required (advisory)
- `SHOULD-FIX(...)` — answer recommended
- `INFORMATIONAL(...)` — answer optional

Preserve each finding's ordinal, `file:line` (when present), and text.

### 3. Answer Each Finding

Produce exactly one verdict per finding:

| Verdict | Meaning | Required evidence |
|---------|---------|-------------------|
| `FIX` | Addressed in the code | commit `<sha>` or `<path>:<line>`; for a current-state claim, back it with `/rdf:r-verify-claim` |
| `REBUT` | Finding is wrong or not applicable | the reason; for a current-state dispute, run `/rdf:r-verify-claim` and cite its PASS |
| `DEFER` | Valid but out of scope now | issue link, or a one-line reason plus the scope it belongs to |

Reuse `/rdf:r-verify-claim --from-finding <report>` to generate evidence for
FIX and REBUT of current-state claims — do not hand-roll grep/log output
that the verify skill already produces in a checked form.

### 4. Write the Audit Trail

Write `.rdf/work-output/sentinel-N-answer-${RDF_SESSION_ID}.md`, where `N`
mirrors the source report's ordinal (or `plan-final` for the plan
sentinel):

```
REPORT: <resolved report path>
ANSWERED: <ISO-8601 timestamp>

- FINDING 1 [MUST-FIX(fix-or-refute)] path:line — <text>
  VERDICT: FIX
  EVIDENCE: <sha> | <path>:<line> | <verify-claim verdict>
- FINDING 2 [SHOULD-FIX(advisory-concern)] — <text>
  VERDICT: REBUT
  EVIDENCE: /rdf:r-verify-claim PASS — <one-line result>
- FINDING 3 [INFORMATIONAL(risk-area)] — <text>
  VERDICT: DEFER
  EVIDENCE: issue #NNN | <scope note>
```

### 5. Report Summary (advisory — no gate)

Print a one-line tally: `N findings — X FIX, Y REBUT, Z DEFER, W unanswered`.

- If any MUST-FIX is unanswered: warn
  `⚠ W MUST-FIX unanswered — resolve before merge (advisory)`.
- Flag any REBUT that carries no evidence (boilerplate "not applicable"):
  `⚠ N REBUT without evidence — cite a /rdf:r-verify-claim PASS or downgrade to DEFER`.

Never block a downstream command, never modify source files, never commit.

## Constraints

- Read-only with respect to source; the only file written is the answer
  artifact under `.rdf/work-output/`
- Advisory only — does not gate `/rdf:r-build`, `/rdf:r-ship`, or merge; unanswered
  or boilerplate findings are surfaced, not enforced
- Every REBUT of a current-state claim should cite a `/rdf:r-verify-claim` PASS;
  a bare REBUT is flagged in the summary
- Exits cleanly when no report exists — it does not fabricate findings
