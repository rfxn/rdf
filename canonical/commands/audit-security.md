Domain: security posture of the codebase and installed artifacts.

## Output Schema (prefix: SEC)
See audit-schema.md for full schema. Use prefix SEC, write to ./audit-output/agent13.md.
Format: `### [SEC-NNN] Title` with Severity, File, Evidence, Description, Impact,
Recommendation, Phase fields. Max 30 findings. Evidence must be verbatim in fenced blocks.

Execute:
  grep -rn '\beval\b' files/
  grep -rn '777\|666\|chmod 7\|chmod 6' files/

Assess for:
- External input (network/file/env var) interpolated into commands unquoted
  or unsanitized (command injection)
- Tempfiles in world-writable dirs, predictable names, TOCTOU window
- Log functions capturing passwords or keys verbatim
- Error output exposing internal paths or config to unprivileged users
- Config examples with real-looking credentials
- Allowlist/trust files writable by non-root
- State files with permissions allowing tampering
- Hardcoded credentials or tokens anywhere including test fixtures
- Unnecessary root-scoped operations
- setuid/setgid bits where not required

Include grep output as Evidence.

## Verification (MANDATORY — see audit-schema.md Verification Protocol)
Before reporting any finding, you MUST:
1. For "eval with external input" findings: trace the input source. If the
   input comes from a project-controlled config file (read at startup, not
   from user input at runtime), it is NOT an injection vector — the config
   file is root-owned and the tool runs as root.
2. For "unquoted variable in command" findings: verify the variable can
   actually contain attacker-controlled content. Variables set from config
   files, hardcoded defaults, or internal computation are not injection risks.
3. For "tempfile race" findings: check if mktemp is used. If it is, the race
   window described may not exist. Also check if the temp path is in a
   root-only directory (e.g., /tmp is world-writable, but /var/lib/project/
   is not).
4. For "permissions too open" findings: verify the actual chmod/install
   command in context. A grep hit for "666" in a comment or comparison
   (`if [ "$mode" = "666" ]`) is NOT a permission vulnerability.
5. For "unnecessary root" findings: these projects are system-level security
   tools that REQUIRE root. Don't flag root operations as unnecessary unless
   a specific operation could run unprivileged.
6. Discard findings that don't survive contextual verification. Security
   false positives are particularly harmful — they cause alert fatigue.

End the file with exactly:
  SUMMARY: <N> findings (C:<n> M:<n> m:<n> I:<n>)
  COMPLETION: SEC DONE
Do not return findings in-context.
