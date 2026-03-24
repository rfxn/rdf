# Database Governance Template

> Seed template for /r-init. Provides database engineering best
> practices for merging with codebase scan results. Engine-agnostic
> core with engine-specific reference docs. Requires core profile.

## Schema Design

- Every table has a primary key -- surrogate (auto-increment or UUID)
  preferred over natural keys unless the domain demands it
- Foreign keys enforced at the database level -- application-only FK
  enforcement is a data integrity bug waiting for a concurrent write
- NOT NULL by default -- nullable columns require a documented reason
  (partial data, legacy compat, optional relationship)
- Naming: snake_case for tables, columns, indexes, and constraints;
  choose consistent singular or plural convention per project and
  enforce it everywhere
- Timestamps: `created_at` and `updated_at` on every table, stored in
  UTC using `timestamptz` (Postgres) or equivalent timezone-aware type
- Enums: CHECK constraints or native enum types -- never magic strings
  with meaning implied only in application code
- Soft vs hard delete: document the choice per table; soft delete
  requires a `deleted_at` column, unique constraint adjustments, and
  query filters on every read path
- Denormalization: document WHY with the sync mechanism that keeps
  denormalized copies consistent -- undocumented denormalization is
  future data corruption

## Migration Safety

- Forward-only in production -- never edit or reorder applied migrations
- Every migration must be reversible OR documented as irreversible with
  a recovery plan (backup + restore procedure)
- Additive steps: add column -> backfill -> add constraint -> drop old;
  never rename, change type, and add NOT NULL in a single migration
- Large table operations: estimate lock duration before executing,
  use concurrent index creation where supported, batch backfills with
  progress tracking
- Migration committed with consuming code -- never merge a migration
  that references columns the application does not yet use (or vice
  versa)
- Test against production-scale volume -- a migration that takes 200ms
  on 1000 rows may hold a lock for 20 minutes on 10M rows
- Zero-downtime patterns: expand-contract, dual-write with feature
  flags, shadow columns; pick the pattern and document it
- Never DROP a column or table without verifying zero application
  references -- grep application code, ORM mappings, and raw queries

## Query Discipline

- Parameterized queries always -- string interpolation into SQL is
  injection regardless of escaping; ORMs are not immune when using
  raw query methods
- SELECT only needed columns -- no `SELECT *` in application code
  (schema changes silently change result shape, increases I/O and
  memory)
- EXPLAIN ANALYZE before optimizing -- measure the plan, don't guess
- N+1 detection: a loop containing a query is suspect; use JOINs,
  subqueries, or batch fetches instead
- Keyset pagination over OFFSET -- OFFSET re-scans skipped rows;
  keyset (`WHERE id > $last_seen ORDER BY id LIMIT N`) is O(1)
- Explicit transaction boundaries with the shortest possible duration;
  never hold a transaction open across network calls, user input, or
  external API requests
- Connection pooling: bounded pool size, connect and idle timeouts,
  health checks on checkout -- unbounded pools cause connection
  exhaustion under load
- Batch operations: INSERT ... ON CONFLICT, RETURNING clause, multi-row
  INSERT -- one round-trip per batch, not per row

## Indexing Strategy

- Primary key index is automatic -- do not create a duplicate index
- Foreign key columns indexed unless the table is tiny (< 1000 rows) --
  unindexed FKs cause sequential scans on JOIN and CASCADE DELETE
- Composite indexes: leftmost prefix rule applies -- an index on
  (a, b, c) supports queries on (a), (a, b), and (a, b, c) but not
  (b) or (c) alone
- Partial indexes for filtered queries -- `WHERE active = true` on a
  table that is 90% inactive reduces index size by 10x
- Expression indexes for computed lookups -- `LOWER(email)` index for
  case-insensitive search avoids full table scans
- Monitor unused indexes -- every index costs write performance; drop
  indexes with zero scans over a meaningful observation period
- Covering indexes (INCLUDE clause) to satisfy queries from the index
  alone without heap lookups

## Security

- SQL injection: parameterized queries only -- escaping is insufficient
  (character set mismatches bypass it), ORMs are not immune when raw
  query interfaces are used
- Least privilege: application role has only the permissions it needs --
  never connect as superuser; separate roles for migration (DDL) and
  runtime (DML)
- Connection strings: never in source code, environment variables or
  secrets manager; TLS required for all remote connections
- Row-level security for multi-tenant data -- application WHERE clauses
  are not a security boundary (one missed filter = data leak)
- Backup encryption: at-rest and in-transit; test restore procedure
  regularly (untested backups are not backups)
- Audit logging: record WHO changed WHAT and WHEN for sensitive tables;
  use database-level triggers or CDC, not application logging alone

## Error Handling

- Constraint violations: catch at the application layer and translate
  to domain-specific errors -- never expose raw database error messages
  to end users (leaks schema information)
- Deadlocks: retry with exponential backoff; prevent by acquiring locks
  in a consistent global ordering across all code paths
- Connection failures: distinguish transient (retry with backoff) from
  permanent (alert and fail fast) -- connection pool libraries usually
  handle this, but verify the configuration
- Data integrity: validate at the application boundary AND enforce with
  database constraints -- either alone is insufficient (app-only misses
  concurrent writes, DB-only gives poor error messages)

## Testing

- Integration tests against a real database instance, not mocks --
  schema drift between mock behavior and real engine is a bug class
  that mocks actively hide
- Dedicated test database per suite run -- never shared across parallel
  suites, never production
- Migration chain test: apply the full migration chain to an empty
  database and verify the resulting schema matches expectations
- Deterministic fixtures, not production snapshots -- production data
  has PII, inconsistent states, and unbounded size
- Performance baselines: capture query plans in CI and alert on plan
  regressions (sequential scan replacing index scan, sort spill to
  disk)
