# PostgreSQL Patterns

> Engine-specific reference for PostgreSQL. Covers advisory locks,
> LISTEN/NOTIFY, partitioning, monitoring, maintenance, extensions,
> and JSONB usage patterns.

---

## Advisory Locks

PostgreSQL provides application-level locks via `pg_advisory_lock()` and
`pg_try_advisory_lock()`. Two scoping modes:

- **Session-scoped** (`pg_advisory_lock`): held until explicit unlock or
  session disconnect. Use for cross-transaction coordination (e.g.,
  migration coordination, singleton job scheduling).
- **Transaction-scoped** (`pg_advisory_xact_lock`): released at
  transaction end. Use for within-transaction deduplication.

`pg_try_advisory_lock()` returns false instead of blocking -- use for
job deduplication where skip-if-running is the desired behavior.

Lock keys are bigint or (int, int) pairs. Establish a project-wide
key allocation scheme to prevent collisions between subsystems.

---

## LISTEN / NOTIFY

Lightweight pub/sub built into the connection protocol. No persistence,
no acknowledgment -- fire-and-forget.

- Payload limit: 8000 bytes per notification. Send identifiers, not
  full payloads -- `NOTIFY new_order, '{"id": 12345}'`.
- Connection pooling: PgBouncer in transaction mode drops LISTEN
  registrations between checkouts. Either use session mode for
  listeners or move to a dedicated non-pooled connection.
- Fan-out: all connections LISTENing on a channel receive every NOTIFY.
  For work queues, use `SELECT ... FOR UPDATE SKIP LOCKED` instead.
- Polling comparison: LISTEN/NOTIFY avoids polling latency and DB load.
  Prefer it for low-volume event signaling (< 1000/sec). For high
  throughput, use a dedicated message broker.

---

## Partitioning

Declarative partitioning (PostgreSQL 10+) splits a table into child
partitions managed by the planner.

- **Range**: time-series data (`created_at`), sequential IDs. Most
  common choice for append-heavy workloads.
- **List**: categorical data (region, status, tenant_id). Good for
  known, finite value sets.
- **Hash**: even distribution when no natural range or list exists.
  Rarely used in practice.

Partition pruning: the WHERE clause must reference the partition key
directly -- joins, functions, or subqueries on the key may prevent
pruning and scan all partitions.

Maintenance patterns:
- Detach/attach for bulk loads: load into standalone table, then
  `ALTER TABLE ... ATTACH PARTITION` -- avoids locking the parent.
- `pg_partman` extension automates partition creation and retention
  for time-based schemes.
- Pre-create future partitions -- inserts into a non-existent
  partition raise an error, not an automatic creation.

---

## Monitoring (pg_stat)

Key system views for operational awareness:

- `pg_stat_user_tables`: compare `seq_scan` vs `idx_scan` per table.
  High seq_scan count on large tables indicates missing indexes.
- `pg_stat_activity`: identify long-running queries (`state = 'active'`
  with high `now() - query_start`), idle-in-transaction sessions
  (hold locks, block vacuum), and blocked processes (`wait_event_type`).
- `pg_stat_statements` (extension): aggregated query statistics --
  total time, calls, mean time. Sort by `total_exec_time` to find the
  queries consuming the most resources.
- `pg_stat_bgwriter`: checkpoint frequency and buffer allocation.
  High `buffers_backend` relative to `buffers_checkpoint` suggests
  `shared_buffers` or checkpoint interval tuning is needed.

---

## VACUUM and Maintenance

PostgreSQL MVCC requires periodic cleanup of dead tuples.

- Autovacuum tuning: `autovacuum_vacuum_scale_factor` (default 0.2)
  triggers at 20% dead rows. For large tables, reduce to 0.01-0.05
  and set an absolute `autovacuum_vacuum_threshold`.
- Bloat detection: `pgstattuple` extension provides `dead_tuple_percent`.
  Tables with > 20% bloat need manual VACUUM FULL or `pg_repack`.
- `REINDEX CONCURRENTLY` (PostgreSQL 12+): rebuilds indexes without
  blocking writes -- use instead of `REINDEX` on production tables.
- `pg_repack`: extension for zero-downtime table and index
  reorganization without ACCESS EXCLUSIVE lock.
- Transaction ID wraparound: monitor `age(datfrozenxid)` -- approaching
  2 billion triggers forced autovacuum that blocks writes. Aggressive
  autovacuum settings on high-churn tables prevent this.

---

## Extensions

Governance: maintain an approved extension list per project. Every
extension must pass a security review before enabling -- extensions
run with superuser privileges inside the database.

Pin extension versions in migration scripts (`CREATE EXTENSION ... VERSION '1.6'`)
to prevent unexpected behavior changes on upgrade.

Common extensions:
- `pg_trgm`: trigram-based similarity search and LIKE/ILIKE index support
- `uuid-ossp` or `pgcrypto`: UUID generation (`gen_random_uuid()` in
  pgcrypto, native in PostgreSQL 13+)
- `pgcrypto`: hashing, encryption, random bytes
- `PostGIS`: spatial data types and geospatial queries
- `pg_stat_statements`: query performance statistics (see Monitoring)
- `btree_gist` / `btree_gin`: enable non-default operator classes for
  exclusion constraints and GIN/GiST indexes on scalar types

---

## JSONB Patterns

When to use: semi-structured data, varying schema across rows, rapid
iteration on shape before committing to columns. Not a replacement for
proper schema design -- use columns for data you query, filter, or
join on regularly.

Indexing:
- GIN index for containment queries (`@>`, `?`, `?|`, `?&`) --
  `CREATE INDEX ON t USING gin (data)`
- B-tree on specific paths for equality/range --
  `CREATE INDEX ON t ((data->>'status'))`
- GIN with `jsonb_path_ops` for smaller, faster containment-only index

Query patterns:
- Extract text: `data->>'key'` (returns text, allows comparison)
- Extract JSON: `data->'key'` (returns jsonb, allows chaining)
- Containment: `data @> '{"status": "active"}'::jsonb`
- Path queries (PostgreSQL 12+): `jsonb_path_query(data, '$.items[*].price ? (@ > 100)')`

Anti-patterns:
- JSONB for everything -- if every row has the same shape, use columns
- No schema validation -- use CHECK constraints or application-level
  validation to prevent data rot
- Indexing every path -- GIN index covers containment; add path-specific
  indexes only for proven hot queries
