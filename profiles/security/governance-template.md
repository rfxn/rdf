# Security Governance Template

> Seed template for /r:init. Provides security assessment conventions
> for merging with codebase scan results. Requires core profile.

## Assessment Methodology

### Engagement Model

1. Scope definition -- explicit target list with boundaries
2. Reconnaissance -- passive enumeration before active probing
3. Analysis -- systematic review across defined domains
4. Findings -- structured output with severity, evidence, remediation
5. Verification -- retest after remediation

### Assessment Domains

| Domain | Focus |
|--------|-------|
| Code review | Injection, auth bypass, path traversal, race conditions |
| Configuration | Hardening gaps, default creds, excessive permissions |
| Infrastructure | Network exposure, service enumeration, privilege escalation |
| Supply chain | Dependency audit, update mechanisms, signature verification |
| Cryptography | TLS configuration, key management, entropy sources |

### Severity Tiers

| Tier | Label | Criteria |
|------|-------|----------|
| P0 | Critical | Active exploitation, no auth required |
| P1 | High | Exploitation with low-privilege access |
| P2 | Medium | Requires specific conditions or chaining |
| P3 | Low | Informational, hardening, defense-in-depth |

### Finding Format

Every finding must include:
- Target: file/service/config path
- Evidence: exact reproduction steps or code snippet
- Impact: what an attacker gains
- Remediation: specific fix with code/config change
- Verified: YES/NO (post-remediation retest)

## Rules of Engagement

- Never modify production systems without explicit authorization
- Document all tools and commands executed
- Preserve evidence chains (screenshots, logs, output)
- Report critical findings immediately
- Track false positives per project

## Privilege Escalation Analysis

1. Map all SUID/SGID binaries and sudo rules
2. Identify writable paths in privileged execution chains
3. Check for symlink race conditions in temporary file usage
4. Verify service account permissions (least privilege)
5. Document escalation chains with tier classification
