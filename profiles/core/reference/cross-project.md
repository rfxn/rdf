# Cross-Project Coordination Reference

> Reference for core profile. Patterns for managing
> shared libraries and consumer updates across the rfxn ecosystem.

## Library Integration Pattern

When a shared library releases a new version:

1. Develop and test in the canonical library project
2. Tag release in library repo
3. Update submodule pins in each consumer project
4. Run consumer test suites to verify integration
5. Commit submodule updates in each consumer

## Consumer Projects

| Library | Consumers |
|---------|-----------|
| tlog_lib | APF, BFD, LMD |
| alert_lib | APF, BFD, LMD |
| elog_lib | APF, BFD, LMD |
| pkg_lib | APF, BFD, LMD |
| geoip_lib | BFD |
| batsman | APF, BFD, LMD, tlog_lib, alert_lib, elog_lib, pkg_lib, geoip_lib, Sigforge |

## Cross-Project Testing

When a change spans multiple projects:
- Test each project independently first
- Then test integration (consumer with updated library)
- Use `rdf state` to verify all projects are clean before push
- Commit in dependency order: library first, then consumers

## Concurrency

- **Intra-project:** not worth it (~89% phase pairs share files)
- **Cross-project:** the real win — use batch mode for consumer integrations
