Domain: inter-tool integration contracts and recurring failure patterns.

## Output Schema (prefix: INT)
See audit-schema.md for full schema. Use prefix INT, write to ./audit-output/agent14.md.
Format: `### [INT-NNN] Title` with Severity, File, Evidence, Description, Impact,
Recommendation, Phase fields. Max 30 findings. Evidence must be verbatim in fenced blocks.

Integration contracts: BFD→APF trigger formats, LMD system state interactions,
shared config conventions, shared path structures. For each integration point:
- Is the contract intact after recent changes?
- Does a change in one tool's output break a consuming tool's parser?
- Are shared conventions consistent across the project family?
- Are there undocumented integration assumptions?

Recurring patterns — execute:
  git shortlog -sn --all
  git log --all --oneline --diff-filter=M -- <identify high-churn files>
  grep -rn 'TODO\|FIXME\|HACK\|XXX' files/

Identify: files touched repeatedly (structural instability), same fix class in
multiple commits (systemic gap), FIXMEs surviving multiple versions.

Performance hygiene: $(command) inside tight loops where one invocation would
suffice, redundant repeated file reads, grep/find applied repeatedly to same
tree, operations scaling poorly with input size.

## Verification (MANDATORY — see audit-schema.md Verification Protocol)
Before reporting any finding, you MUST:
1. For "integration contract broken" findings: read BOTH sides of the
   contract — the producer and the consumer. Verify the format mismatch is
   real, not an artifact of reading only one side.
2. For "high churn = structural instability" findings: check if the churn
   is from active development (normal for a release cycle) vs repeated
   fixes to the same issue (actual instability signal). Only report the
   latter.
3. For "performance" findings: verify the code path is actually hot (called
   frequently or with large input). A subshell in a function called once
   at startup is NOT a performance issue.
4. For "FIXME surviving multiple versions" findings: check if the FIXME
   describes a real deficiency or is aspirational ("FIXME: could be faster").
   Only flag if it indicates an actual bug or missing functionality.
5. Discard findings that don't survive contextual verification.

End the file with exactly:
  SUMMARY: <N> findings (C:<n> M:<n> m:<n> I:<n>)
  COMPLETION: INT DONE
Do not return findings in-context.
