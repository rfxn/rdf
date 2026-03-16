Run all mandatory pre-commit verification checks for the current project.
Detect the project type from CLAUDE.md or the working directory, then execute
every check listed in the project's Verification section.

## Universal checks (all projects)
```
bash -n <all project shell files>
shellcheck <all project shell files>
grep -rn '\bwhich\b' files/
grep -rn '\begrep\b' files/
grep -rn '`' files/               # backtick usage
grep -rn '\$\[' files/            # deprecated arithmetic
```

## Project-specific checks
Detect project from CWD or CLAUDE.md and add:

**APF** (advanced-policy-firewall):
```
grep -rn '/sbin/ip ' files/
grep -rn '/sbin/iptables' files/
grep -rn '$IP6T ' files/ | grep -v IPT_FLAGS
grep -rn '$IP6T.*0/0' files/
grep -rn '2002-201[0-9]' . | grep -v CHANGELOG
```

**LMD** (linux-malware-detect):
```
grep -rn '/usr/local/maldetect' files/ | grep -v internals.conf
```

**BFD** (brute-force-detection):
```
grep -rn '${[^}]*,,' files/          # bash 4.2+ lowercase
grep -rn 'mapfile -d\|declare -n\|EPOCHSECONDS' files/
grep -rn 'gensub\|strftime\|mktime\|systime\|asort' files/
```

## Output format
For each check, report PASS (zero hits) or FAIL with the matching lines.
Print a summary line: `Validation: <pass>/<total> checks passed`

If all pass: `Ready to commit.`
If any fail: list failures and stop. Do NOT proceed to commit.
