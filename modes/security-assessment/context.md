# Security Assessment Mode

> Operational mode for offensive/defensive security work. Changes how
> all agents interpret their tasks -- planner brainstorms attack vectors,
> dispatcher applies security-specific gates, reviewer uses OWASP methodology.

## Methodology

Follows a structured assessment engagement:

1. **Scope** -- define target boundaries (repos, services, configs)
2. **Reconnaissance** -- passive enumeration, dependency mapping
3. **Analysis** -- systematic review across security domains
4. **Findings** -- structured output with severity and evidence
5. **Verification** -- retest after remediation

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
- Track false positives per project

## Planner Behavior

- Brainstorm attack vectors, not features
- Research known vulnerability classes for the project's stack
- Enumerate attack surface before proposing assessment plan
- Produce threat model or assessment plan (not implementation plan)
- Default scope context: changes in this mode typically classify as scope:sensitive (security)

## Quality Gate Overrides

All phases in security mode apply Gates 1 + 2 + 3 regardless of
scope classification. The reviewer sentinel always runs with security weighting.

| Override | Effect |
|----------|--------|
| Minimum gates | Gates 1 + 2 + 3 (reviewer always runs) |
| Reviewer weighting | Security pass findings are MUST-FIX (not just SHOULD-FIX) |
| Finding threshold | Any P0/P1 finding blocks phase completion |

## Reviewer Focus

Modified 4-pass sentinel with security emphasis:
1. Anti-slop (standard)
2. Regression (standard)
3. **Security** (ELEVATED -- OWASP methodology, findings are blocking)
4. Performance (standard, but check for DoS vectors)

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
- [ ] Findings formatted with target, evidence, impact, remediation
- [ ] Severity tiers assigned consistently
- [ ] False positives documented with reasoning
- [ ] Critical findings (P0/P1) reported immediately
- [ ] Evidence chains preserved (commands, output, screenshots)
- [ ] Remediation retested where fixes were applied
