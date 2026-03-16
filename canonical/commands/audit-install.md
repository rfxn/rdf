Domain: install/uninstall correctness, path replacement, runtime state.

## Output Schema (prefix: INS)
See audit-schema.md for full schema. Use prefix INS, write to ./audit-output/agent9.md.
Format: `### [INS-NNN] Title` with Severity, File, Evidence, Description, Impact,
Recommendation, Phase fields. Max 30 findings. Evidence must be verbatim in fenced blocks.

Execute:
  grep -rn '/etc/apf\|/etc/bfd\|/usr/local/maldetect' files/ | grep -v internals.conf

Cross-reference every hit against sed substitutions in install.sh. Flag any
literal with no corresponding substitution. Verify idempotency.

Check for:
- Install permissions deviating from: config/rules 640, executables 750 (APF/
  BFD) or 755 (LMD), logs 640, quarantine/state dirs 750
- Uninstall leaving behind files, dirs, cron entries, init/systemd units
- Shared state files not using flock
- Log trimming replacing or truncating files instead of preserving inodes
- Quarantine dir assumed to exist rather than verified before first use
- Tempfiles not using mktemp with template or not cleaned via trap on ERR/EXIT
- Binaries assumed present without command -v verification
- Optional vs required dependencies not clearly distinguished

Include grep output as Evidence.

## Verification (MANDATORY — see audit-schema.md Verification Protocol)
Before reporting any finding, you MUST:
1. For "hardcoded path without sed substitution" findings: check BOTH
   install.sh AND any Makefile or packaging script for the sed pattern.
   Substitution may happen in a different file than install.sh.
2. For "uninstall leaving artifacts" findings: actually read the uninstall
   function/script — artifacts may be conditionally cleaned or intentionally
   preserved (e.g., user config files preserved by design).
3. For "missing flock" findings: verify the state file is actually shared
   across concurrent processes. Single-writer files don't need flock.
4. For "permissions" findings: verify against the project's CLAUDE.md
   permission spec — different projects have different standards (750 vs 755).
5. Discard findings that don't survive contextual verification.

End the file with exactly:
  SUMMARY: <N> findings (C:<n> M:<n> m:<n> I:<n>)
  COMPLETION: INS DONE
Do not return findings in-context.
