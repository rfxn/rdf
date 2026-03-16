Domain: upgrade and migration correctness for users on prior versions.

## Output Schema (prefix: UPG)
See audit-schema.md for full schema. Use prefix UPG, write to ./audit-output/agent11.md.
Format: `### [UPG-NNN] Title` with Severity, File, Evidence, Description, Impact,
Recommendation, Phase fields. Max 30 findings. Evidence must be verbatim in fenced blocks.

Check for:
- Config vars renamed, removed, or default-changed in this release without
  compat.conf mapping (LMD), ${VAR:-default} fallback (APF), or migration doc
- install.sh overwriting user-edited config files on install-over-existing
- State directories not preserved on reinstall
- Cron entries or init scripts duplicated on reinstall
- Removed features/flags/options with no documented migration path or useful
  error when old config is encountered
- New required config options with no default
- Changed defaults with operational impact not prominent in changelog
- Any behavioral change not obvious from changelog entries

## Verification (MANDATORY — see audit-schema.md Verification Protocol)
Before reporting any finding, you MUST:
1. For "missing compat mapping" findings: verify via git diff that the variable
   was actually renamed/removed in THIS release. Don't flag variables that have
   always had the current name.
2. For "config overwritten on reinstall" findings: read install.sh — most
   projects use importconf or similar mechanisms to preserve user config.
   Verify the overwrite actually happens.
3. For "removed feature with no migration" findings: verify the feature was
   actually removed, not just refactored. Check the changelog for migration
   notes before flagging.
4. Discard findings that don't survive contextual verification.

End the file with exactly:
  SUMMARY: <N> findings (C:<n> M:<n> m:<n> I:<n>)
  COMPLETION: UPG DONE
Do not return findings in-context.
