# Migration Mode

> Operational mode for version upgrades, platform migrations, and data
> migrations. Changes how agents approach work -- planner builds
> compatibility matrices, dispatcher enforces rollback safety, reviewer
> checks backward compatibility.

## Methodology

Follows a structured migration assessment:

1. **Inventory** -- catalog current state (versions, dependencies, data formats)
2. **Compatibility** -- build matrix of source vs target compatibility
3. **Plan** -- define migration path with rollback points
4. **Execute** -- incremental migration with verification at each step
5. **Verify** -- end-to-end validation in target state
6. **Rollback test** -- verify rollback path works before declaring complete

Migration types:
- Version upgrade (dependency, runtime, framework)
- Platform migration (OS, cloud provider, container runtime)
- Data migration (schema changes, format conversions, storage backends)
- API migration (endpoint changes, protocol upgrades, contract changes)

## Planner Behavior

- Build compatibility matrix before proposing migration path
- Identify breaking changes with evidence (changelogs, release notes)
- Plan for rollback at every step
- Research migration guides for the specific upgrade path
- Default scope context: changes in this mode typically classify as scope:sensitive (data migration) or scope:cross-cutting

## Quality Gate Overrides

Migration mode applies all 4 gates by default and adds rollback
verification.

| Override | Effect |
|----------|--------|
| Minimum gates | All 4 gates (self-report + QA + reviewer + UAT) |
| UAT scope | Must test both forward migration AND rollback |
| Reviewer focus | Backward compatibility findings are MUST-FIX |
| Data integrity | QA must verify data integrity before and after |

## Reviewer Focus

Modified 4-pass sentinel with migration emphasis:
1. Anti-slop (standard)
2. **Regression** (ELEVATED -- backward compatibility is critical)
3. Security (standard -- migration paths are attack surfaces)
4. Performance (standard -- verify no degradation post-migration)

## Compatibility Matrix Format

Document compatibility for each component:

| Component | Current | Target | Breaking Changes | Migration Path |
|-----------|---------|--------|-----------------|----------------|
| {name} | {version} | {version} | {list or "none"} | {steps} |

## Rollback Protocol

Every migration phase must define:
- Rollback trigger conditions (what failures trigger rollback)
- Rollback steps (exact commands or procedures)
- Data recovery procedure (if data was modified)
- Verification after rollback (confirm clean state)

## Checklist

Before completing a migration phase:
- [ ] Compatibility matrix documented
- [ ] Forward migration tested and verified
- [ ] Rollback procedure tested and verified
- [ ] Data integrity verified (before, after, and after rollback)
- [ ] No backward compatibility regressions
- [ ] Dependent systems notified of changes
- [ ] Migration runbook updated with actual findings
