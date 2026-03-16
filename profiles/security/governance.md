# Security Governance

> RDF security profile — methodology and conventions for offensive/defensive
> security assessments across rfxn infrastructure and codebases.
> Requires the core profile.

---

## Assessment Methodology

### Engagement Model

1. **Scope definition** — Explicit target list (repos, infra, configs) with boundaries
2. **Reconnaissance** — Passive enumeration before active probing
3. **Analysis** — Systematic review across defined domains (see below)
4. **Findings** — Structured output with severity, evidence, and remediation
5. **Verification** — Retest after remediation

### Assessment Domains

| Domain | Focus |
|--------|-------|
| Code review | Injection, auth bypass, path traversal, race conditions |
| Configuration | Hardening gaps, default credentials, excessive permissions |
| Infrastructure | Network exposure, service enumeration, privilege escalation |
| Supply chain | Dependency audit, update mechanisms, signature verification |
| Cryptography | TLS configuration, key management, entropy sources |

### Severity Tiers

| Tier | Label | Criteria |
|------|-------|----------|
| P0 | Critical | Active exploitation possible, no authentication required |
| P1 | High | Exploitation possible with low-privilege access |
| P2 | Medium | Exploitation requires specific conditions or chaining |
| P3 | Low | Informational, hardening recommendation, defense-in-depth |

### Finding Format

Every finding must include:

```
## [TIER] Finding Title

**Target:** file/service/config path
**Evidence:** exact reproduction steps or code snippet
**Impact:** what an attacker gains
**Remediation:** specific fix with code/config change
**Verified:** YES/NO (post-remediation retest)
```

### Rules of Engagement

- Never modify production systems without explicit authorization
- Document all tools and commands executed during assessment
- Preserve evidence chains — screenshots, logs, command output
- Report critical findings immediately, do not wait for full assessment
- False positive tracking: maintain `audit-output/false-positives.md` per project

---

## Privilege Escalation Analysis

When assessing privilege escalation paths:

1. Map all SUID/SGID binaries and sudo rules
2. Identify writable paths in privileged execution chains
3. Check for symlink race conditions in temporary file usage
4. Verify service account permissions (principle of least privilege)
5. Document escalation chains with tier classification

---

## Reporting Conventions

- Assessment artifacts stored in `redteam/` directory per project
- Use `sec-eng` agent persona for all assessment work
- Cross-reference findings with project audit pipeline (`/audit-security`)
- Findings promoted to GitHub issues use `type:audit-finding` + `domain:sec` labels
