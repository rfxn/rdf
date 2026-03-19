# MySQL Patterns

> Engine-specific reference for MySQL / MariaDB. Covers InnoDB tuning,
> replication, character sets, query optimization, and stored procedures.

---

## InnoDB Tuning

InnoDB is the default and recommended storage engine. Key parameters:

- **Buffer pool** (`innodb_buffer_pool_size`): set to 70-80% of
  available RAM on dedicated database servers. This is the single most
  impactful tuning parameter -- it caches data and indexes in memory.
- **Log file size** (`innodb_log_file_size`): larger log files improve
  write throughput but increase crash recovery time. 1-2 GB is typical
  for write-heavy workloads. On MySQL 8.0.30+, use
  `innodb_redo_log_capacity` instead.
- **Flush method** (`innodb_flush_method`): use `O_DIRECT` on Linux to
  bypass the OS page cache (avoids double-buffering since InnoDB has
  its own buffer pool).
- **File-per-table** (`innodb_file_per_table=ON`): default since 5.6.
  Each table gets its own tablespace file -- enables per-table space
  reclamation after large deletes and simplifies backup.
- **Flush log at commit** (`innodb_flush_log_at_trx_commit`): 1 =
  durable (ACID compliant), 2 = flush to OS cache (1 second data loss
  window), 0 = flush to log buffer only. Use 1 for production unless
  you accept data loss for throughput.

---

## Replication

- **Binary log format** (`binlog_format`): ROW-based preferred -- it
  replicates the actual row changes, avoiding non-deterministic
  statement pitfalls (NOW(), LIMIT without ORDER BY, triggers).
  STATEMENT saves bandwidth but breaks on non-deterministic queries.
  MIXED auto-switches but is unpredictable.
- **GTID** (`gtid_mode=ON`): Global Transaction Identifiers provide
  a consistent replication position across topology changes. Required
  for reliable failover and multi-source replication.
- **Lag monitoring**: `Seconds_Behind_Master` is unreliable (measures
  relay log position, not actual data consistency). Use `pt-heartbeat`
  from Percona Toolkit for accurate lag measurement.
- **Split-brain prevention**: use `rpl_semi_sync_master_enabled` for
  semi-synchronous replication (at least one replica acknowledges
  before commit returns). For stronger guarantees, use Group
  Replication or an orchestration layer (Orchestrator, ProxySQL).
- **Read replicas**: route read queries to replicas only when your
  application tolerates replication lag -- session-critical reads
  must hit the primary.

---

## Character Sets and Collation

- **utf8mb4, not utf8**: MySQL's `utf8` is a 3-byte subset that cannot
  store 4-byte characters (emoji, some CJK, mathematical symbols).
  Always use `utf8mb4` for full Unicode support. This applies to
  database, table, column, and connection character sets.
- **Collation selection**:
  - `utf8mb4_unicode_ci`: broad compatibility, follows Unicode
    standard, available in all MySQL versions
  - `utf8mb4_0900_ai_ci`: MySQL 8.0+ default, faster, Unicode 9.0
    rules. Not available in 5.7 or MariaDB (use `unicode_ci`).
- **Migration from latin1**: common in legacy databases. Convert
  column-by-column: `ALTER TABLE t MODIFY col VARCHAR(255) CHARACTER SET
  utf8mb4 COLLATE utf8mb4_unicode_ci`. Test for data truncation
  (3-byte latin1 to 4-byte utf8mb4 can exceed column byte limits).
- **Connection charset**: ensure the client connection matches the
  database (`SET NAMES utf8mb4` or connector configuration). Mismatched
  connection charset silently corrupts multi-byte characters.

---

## Query Optimization

- **Optimizer hints** (MySQL 8.0+): `/*+ NO_INDEX(t idx_name) */`,
  `/*+ JOIN_ORDER(t1, t2) */` -- prefer hints over `FORCE INDEX` as
  they are version-aware and ignored gracefully by older parsers.
- **Index hints** (legacy): `USE INDEX (idx_name)`, `FORCE INDEX
  (idx_name)`, `IGNORE INDEX (idx_name)`. Use sparingly -- they bypass
  the optimizer and must be revisited when data distribution changes.
- **Covering indexes**: include all columns referenced in the query so
  the engine can satisfy it from the index alone (Extra: `Using index`
  in EXPLAIN). Reduces I/O significantly for read-heavy queries.
- **Query cache**: deprecated in MySQL 5.7.20, removed in 8.0. Do not
  rely on it -- use application-level caching (Redis, Memcached).
- **Prepared statements**: reduce parse overhead for repeated queries
  and provide injection protection. Server-side prepared statements
  bypass the query cache (moot since 8.0).

---

## Stored Procedures

When appropriate:
- Complex business logic that benefits from proximity to data (bulk
  transformations, multi-step calculations with intermediate results)
- Enforcing data integrity rules too complex for constraints
- Reducing network round-trips for multi-statement operations

Security:
- `DEFINER` (default): executes with the privileges of the user who
  created the procedure. Verify the definer account still exists and
  has appropriate privileges after user cleanup.
- `INVOKER` (`SQL SECURITY INVOKER`): executes with caller's privileges.
  Preferred for general-purpose procedures -- follows least privilege.

Testing challenges: stored procedures are difficult to unit test in
isolation. Strategies:
- Test via integration tests that call the procedure and verify results
- Keep procedures focused -- one operation per procedure
- Avoid business logic in procedures when the application layer has
  better testing infrastructure
- Version procedures in migration files alongside schema changes
