**DEPRECATED** — This agent has been replaced by the reformed pipeline.

Deduplication now happens inside the condense-dedup agents (audit-condense.md)
during Round 2, and final compilation happens in audit-compile.md during Round 3.

The old pipeline (condense → dedup → synthesis) has been replaced by:
  condense-dedup (parallel, includes intra-group dedup) → compile (lightweight merge)

See audit-schema.md Pipeline Architecture for the current flow.
