Domain: shell coding standards and portability. Execute all checks.

## Output Schema (prefix: STD)
See audit-schema.md for full schema. Use prefix STD, write to ./audit-output/agent3.md.
Format: `### [STD-NNN] Title` with Severity, File, Evidence, Description, Impact,
Recommendation, Phase fields. Max 30 findings. Evidence must be verbatim in fenced blocks.

Run each grep and write every hit to output. A zero-result is a passing check —
record it as PASS. Do not infer from reading alone.

grep -rn '`' files/
grep -rn '\$\[' files/
grep -rn '\begrep\b' files/
grep -rn '\bwhich\b' files/
grep -rn '\$RANDOM\|\$\$' files/
grep -rn 'for .* in \$(cat' files/
grep -rn '/sbin/ip \|/sbin/iptables\|/sbin/ip6' files/
grep -rn '/usr/local/maldetect\|/etc/apf\|/etc/bfd' files/ | grep -v internals.conf
grep -rn '\beval\b' files/
grep -rn 'Copyright\|copyright' files/ conf.* install.sh 2>/dev/null

Shebang audit: LMD must use #!/usr/bin/env bash, APF/BFD must use #!/bin/bash.

BFD Bash 4.1 floor:
grep -rn '\${[^}]*,,' files/
grep -rn 'mapfile -d\|declare -n\|EPOCHSECONDS' files/

BFD AWK mawk-only:
grep -rn 'gensub\|strftime\|mktime\|systime\|asort' files/ 2>/dev/null

Cross-OS: systemd assumptions without runtime detection, nc without variant
detection, TLS assumptions on CentOS 6 / Ubuntu 12.04 targets.

Include grep output verbatim as Evidence.

## Verification (MANDATORY — see audit-schema.md Verification Protocol)
Before reporting any grep hit as a finding, you MUST:
1. Read the surrounding context of EVERY grep hit — a hit inside a comment,
   heredoc, string literal, or disabled code block is NOT a violation.
2. For backtick hits: check if inside a comment, documentation string, or
   heredoc (common in help text). Only flag backticks used as command substitution.
3. For hardcoded path hits: check install.sh for a corresponding sed replacement.
   If the path is replaced at install time, it is NOT a violation — discard it.
4. For `eval` hits: read the full context. Eval with a controlled, validated
   input is an intentional pattern — only flag if external/untrusted input
   reaches eval without sanitization.
5. For copyright hits: compare against the project's CLAUDE.md stated format
   before flagging — the project may use a different but intentional format.
6. Report PASS checks normally, but do NOT inflate findings with grep hits
   that fail contextual verification. Discard false positives silently.

End the file with exactly:
  SUMMARY: <N> findings (C:<n> M:<n> m:<n> I:<n>)
  COMPLETION: STD DONE
Do not return findings in-context.
