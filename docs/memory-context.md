# Memory & Context — RDF alongside native auto-memory

RDF 3.4 assumes Claude Code's native auto-memory is present and does not
compete with it. Native memory owns conversational recall and the loading of
your project's `MEMORY.md`; RDF owns the **delta** — cross-project lessons,
rolling insights, governance, project-state hygiene, and a durable session
journal. This page draws the line explicitly so the two never duplicate or
clobber each other.

## Division of labor

Native auto-memory owns `~/.claude/projects/<slug>/memory/MEMORY.md` (the
first ~200 lines / 25 KB are loaded every session, topic files on demand, and
the set is re-injected after compaction). RDF layers its delta on top:

| Concern | Owner | Location | RDF's role |
|---------|-------|----------|------------|
| Conversational memory (what we discussed) | **Native** | `~/.claude/projects/<slug>/memory/` | none — do not touch |
| Project-state index (version, HEAD, pipeline position, phase status) | **RDF content, native loading** | RDF's `MEMORY.md` already lives where native loads it | RDF owns hygiene (`/r-util-mem-compact`, staleness checks); native owns the free re-inject |
| Cross-session / cross-project lessons | **RDF** | `~/.rdf/lessons-learned.md` (+ `lessons-index.md`) | native memory is per-project — it cannot hold cross-project wisdom; RDF owns it |
| Rolling session insights | **RDF** | `~/.rdf/insights.jsonl` | append + cap + consolidate |
| Governance / conventions | **RDF** | `.claude/rules/` (scoped) + project `.rdf/governance/` | RDF emits; the platform loads scoped rules on demand |
| Session journal | **RDF** | `.rdf/work-output/session-log.jsonl` | SessionEnd hook + `/r-save` append |

## How RDF's delta reaches a session

- **SessionEnd capture** — `session-end-capture.sh` takes an inline git-only
  snapshot and appends one deterministic line to the session journal (plus a
  cache `/r-save` consumes), so a session that never runs `/r-save` is still
  recorded. It never writes to the native memory directory.
- **SessionStart injection** — `session-start-inject.sh` injects a
  size-capped (≤400 byte) lessons ID-index as `additionalContext`. It is
  **read-only**: full lesson bodies are fetched on demand by ID from
  `~/.rdf/lessons-learned.md`. The index is rebuilt only by `/r-save`
  (single-writer) via `state/rdf-lessons.sh index`.
- **Scoped governance** — language rules are `paths:`-scoped and stay dormant
  until a matching file is read; the core rule is unscoped so it survives
  compaction. Deploy them opt-in with `rdf deploy --rules`, or run the
  minimal `rdf deploy --lite`.

The always-loaded cost of all of this is measured, not estimated by feel —
`state/rdf-overhead.sh` reports the default / `--rules` / `rdf-lite` boot
figures, and CI guards the published numbers against drift.

## What RDF does NOT do

- **No parallel memory system.** RDF does not re-implement conversational
  recall — native memory already does that, and duplicating it would only
  burn context.
- **No writes to the native memory directory.** Nothing in RDF writes into
  `~/.claude/projects/<slug>/memory/`. RDF's own files live under `~/.rdf/`
  and the project's `.rdf/work-output/`.
- **No pulling MEMORY.md out of native loading.** The project `MEMORY.md`
  stays where native already loads it for free; RDF only keeps it healthy.

## See also

- Design spec: [`docs/specs/2026-07-15-memory-context-design.md`](specs/2026-07-15-memory-context-design.md)
- Context cost breakdown: `state/rdf-overhead.sh` and the Context-cost table
  in the [README](https://github.com/rfxn/rdf#4-usage)
