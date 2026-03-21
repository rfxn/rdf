# Security Assessment Mode

> Operational mode for offensive/defensive security work. Changes how
> all agents interpret their tasks -- planner brainstorms attack vectors,
> dispatcher applies security-specific gates, reviewer uses OWASP methodology.

## Methodology

Follows a structured assessment engagement:

1. **Scope** -- define target boundaries (repos, services, configs)
2. **Reconnaissance** -- passive enumeration, dependency mapping
3. **Analysis** -- broad scan across security domains; produces candidates
4. **Triage** -- verify each candidate against actual code; classify as confirmed, false-positive, or needs-investigation
5. **Findings** -- structured output with severity and evidence (confirmed only)
6. **Verification** -- retest after remediation

Assessment domains:
- Code review (injection, auth bypass, path traversal, race conditions)
- Configuration (hardening gaps, default creds, permissions)
- Infrastructure (network exposure, privilege escalation)
- Supply chain (dependencies, update mechanisms, signatures)
- Cryptography (TLS, key management, entropy)

## Rules of Engagement

- Never modify production systems without explicit authorization
- Document all tools and commands executed
- Preserve evidence chains (screenshots, logs, output)
- Report critical findings immediately
- Track false positives per project -- false positive rate is a quality metric

## Verification Discipline

Every candidate from the analysis phase MUST be verified before
becoming a finding. Pattern matches are candidates, not findings.

**Two-pass assessment:**

| Pass | Purpose | Output |
|------|---------|--------|
| Scan pass | Fast, pattern-based sweep across domains | Candidate list with location and category |
| Verify pass | Read actual code paths, trace source→sink, check preconditions | Confirmed findings or documented false positives |

**Code-path verification** -- Read the actual code path from input to
sink. A claimed injection is not a finding until you confirm the input
reaches the sink without sanitization. Check for:
- Upstream input validation or sanitization
- Authorization gates between source and sink
- Framework-provided protections (parameterized queries, auto-escaping)
- Type constraints that prevent exploitation

**Precondition check** -- Document what conditions must be true for
exploitation. If preconditions require impossible or implausible states
in the deployment context, downgrade to P3 or discard with reasoning.

**False positive documentation** -- When discarding a candidate, record:
- What pattern triggered the candidate
- What code-path evidence disproved it
- Whether the pattern should be tuned for future scans

This builds project-specific knowledge that accelerates future assessments
and reduces noise over time.

## Planner Behavior

- Brainstorm attack vectors, not features
- Research known vulnerability classes for the project's stack
- Enumerate attack surface before proposing assessment plan
- Produce threat model or assessment plan (not implementation plan)
- Plan scan pass AND verify pass -- never plan scan-only phases
- Default scope context: changes in this mode typically classify as scope:sensitive (security)

## Quality Gate Overrides

All phases in security mode apply Gates 1 + 2 + 3 regardless of
scope classification. The reviewer sentinel always runs with security weighting.

| Override | Effect |
|----------|--------|
| Minimum gates | Gates 1 + 2 + 3 (reviewer always runs) |
| Reviewer weighting | Security pass findings are MUST-FIX (not just SHOULD-FIX) |
| Finding threshold | Any P0/P1 finding blocks phase completion |
| Evidence requirement | Findings without code-path trace are returned for verification |

## Reviewer Focus

Modified 4-pass sentinel with security emphasis:
1. Anti-slop (standard)
2. Regression (standard)
3. **Security** (ELEVATED -- OWASP methodology, findings are blocking)
4. Performance (standard, but check for DoS vectors)

Reviewer additionally checks:
- Every finding includes a source→sink trace or equivalent evidence
- No pattern-match-only candidates reported as confirmed findings
- False positive reasoning is specific, not hand-waved

## Engineer Behavior

- Never report a vulnerability without reading the code path from source to sink
- Pattern matches ("uses eval", "calls exec", "no CSRF token") are candidates -- investigate before reporting
- Check for upstream sanitization, authorization gates, and input validation before escalating
- When dispatching parallel recon agents, verify ALL claims against actual code before writing findings
- A finding without a reproducible proof-of-concept or a confirmed code-path trace is a candidate, not a finding
- Prefer depth over breadth -- 5 verified findings beat 20 unverified candidates

## Severity Schema

| Tier | Label | Criteria |
|------|-------|----------|
| P0 | Critical | Active exploitation, no auth required |
| P1 | High | Exploitation with low-privilege access |
| P2 | Medium | Requires specific conditions or chaining |
| P3 | Low | Informational, hardening, defense-in-depth |

## Privilege Escalation Analysis

1. Map all SUID/SGID binaries and sudo rules
2. Identify writable paths in privileged execution chains
3. Check for symlink race conditions in temporary file usage
4. Verify service account permissions (least privilege)
5. Document escalation chains with tier classification

## Checklist

Before completing an assessment phase:
- [ ] All assessment domains covered for the defined scope
- [ ] Analysis candidates verified against actual code (not just pattern matches)
- [ ] Each finding includes code-path trace (source→sink with gaps identified)
- [ ] Preconditions for exploitation documented per finding
- [ ] Severity tiers assigned consistently with evidence justification
- [ ] False positives documented with specific dismissal reasoning
- [ ] Critical findings (P0/P1) reported immediately
- [ ] Evidence chains preserved (commands, output, screenshots)
- [ ] Remediation retested where fixes were applied
