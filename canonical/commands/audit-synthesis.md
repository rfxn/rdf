**DEPRECATED** — This agent has been replaced by the reformed pipeline.

Synthesis is now handled by the compile agent (audit-compile.md) which merges
two pre-deduplicated finding lists and writes AUDIT.md directly.

The old pipeline (condense → dedup → synthesis) has been replaced by:
  condense-dedup (parallel, includes intra-group dedup) → compile (lightweight merge)

See audit-schema.md Pipeline Architecture for the current flow.
