Domain: Makefiles, test Dockerfiles, CI workflow files (.github/ etc.).

## Output Schema (prefix: BCI)
See audit-schema.md for full schema. Use prefix BCI, write to ./audit-output/agent10.md.
Format: `### [BCI-NNN] Title` with Severity, File, Evidence, Description, Impact,
Recommendation, Phase fields. Max 30 findings. Evidence must be verbatim in fenced blocks.

Check for:
- Documented test targets that do not exist or do not do what they claim
- Missing target dependencies or phony target declarations
- Targets silently succeeding on failure conditions
- Docker base images using floating tags (latest, stable) instead of pinned
- Dockerfile variants missing correct dependencies for their OS target
- Privileged flag absent where test suite requires it
- CI OS/target matrix not matching documented support matrix
- Workflow triggers on wrong branches
- Secrets or tokens hardcoded in workflow files
- Stale cache configuration
- Non-zero exits swallowed silently in workflows
- Targets in OS support matrix not run by CI, or CI running undocumented targets

## Verification (MANDATORY — see audit-schema.md Verification Protocol)
Before reporting any finding, you MUST:
1. For "missing target" findings: check both the project Makefile AND the
   included infra Makefile (tests/infra/include/Makefile.tests). Targets may
   be defined in the included file.
2. For "Docker base image not pinned" findings: check if the image is from
   batsman's controlled base images, which are pinned by the submodule tag.
3. For "CI matrix gap" findings: verify against the project's actual target
   OS matrix in CLAUDE.md, not a generic assumption. Not all projects support
   all OSes.
4. For "workflow trigger" findings: check if the project uses the batsman
   reusable workflow — trigger configuration lives there, not in the project.
5. Discard findings that don't survive contextual verification.

End the file with exactly:
  SUMMARY: <N> findings (C:<n> M:<n> m:<n> I:<n>)
  COMPLETION: BCI DONE
Do not return findings in-context.
