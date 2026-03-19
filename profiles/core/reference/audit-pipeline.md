# Audit Pipeline Reference

> Reference for core profile. Architecture and operation
> of the 3-round audit pipeline.

## Pipeline Architecture

3-round pipeline: agents (parallel) → condense-dedup (parallel) → compile (sequential)

### Round 1: Domain Agents (parallel)

15 domain agents run in parallel, each producing findings:

| Agent | Model | Domain |
|-------|-------|--------|
| audit-regression | opus | Behavioral regressions |
| audit-latent | opus | Latent/dormant bugs |
| audit-security | opus | Security vulnerabilities |
| audit-standards | haiku | Shell coding standards |
| audit-cli | sonnet | CLI interface compliance |
| audit-docs | sonnet | Documentation accuracy |
| audit-config | sonnet | Configuration correctness |
| audit-test-coverage | sonnet | Test coverage gaps |
| audit-test-exec | sonnet | Test execution verification |
| audit-install | sonnet | Installation path correctness |
| audit-build-ci | sonnet | Build/CI pipeline issues |
| audit-upgrade | sonnet | Upgrade path compatibility |
| audit-version | haiku | Version string consistency |
| audit-interfaces | sonnet | Interface contracts |
| audit-modernize | opus | Modernization opportunities |

Per-agent finding cap: 20 (be selective, not comprehensive).

### Round 2: Condense-Dedup (parallel)

Two condense agents run in parallel, each processing half the findings:
- `findings-a.md` — first half of agents
- `findings-b.md` — second half of agents

Dedup is pushed into the condense step (parallel), not a separate pass.

### Round 3: Compile (sequential)

Single compile agent merges `findings-a.md` + `findings-b.md` into `AUDIT.md`.

**AUDIT.md format:**
- 300-line hard cap
- P1 findings: expanded detail
- P2 findings: table format
- P3 findings: grouped summary

## Invocation

```bash
/audit              # Full pipeline
/audit-quick        # Static analysis only (no test execution)
/audit-delta        # Changes since last audit only
```

## Verification

- COMPLETE/PARTIAL/FAILED based on COMPLETION marker
- Mandatory code verification for each finding
- VERIFIED field in finding format
- Severity demotion for unverified findings

## Schema

Finding format, 4-tier severity, and agent registry defined in
`canonical/commands/audit-schema.md`.
