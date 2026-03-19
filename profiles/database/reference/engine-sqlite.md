# SQLite Patterns

> Engine-specific reference for SQLite. Covers WAL mode, concurrency,
> type affinity, appropriate use cases, and backup strategies.

---

## WAL Mode

Write-Ahead Logging (`PRAGMA journal_mode=WAL`) changes SQLite's
concurrency model from exclusive locking to multi-reader/single-writer.

- **When to enable**: any scenario with concurrent reads, which is
  nearly every multi-threaded or multi-process application. WAL is
  strictly superior to rollback journal for read concurrency.
- **Checkpoint tuning**: `PRAGMA wal_autocheckpoint=N` controls how
  many pages accumulate before automatic checkpoint. Default is 1000
  pages. Increase for write-heavy bursts (reduces checkpoint frequency),
  decrease for bounded WAL file size.
- **Shared-cache mode**: allows multiple connections in the same process
  to share a page cache. Rarely needed -- it introduces table-level
  locking semantics that reduce concurrency. Avoid unless memory
  pressure demands it.
- **WAL file growth**: the WAL file grows until a checkpoint transfers
  pages to the main database. If readers hold long transactions, the
  WAL cannot be truncated. Monitor WAL file size and ensure no
  connection holds a read transaction indefinitely.
- **Persistence**: WAL mode is persistent per database file -- set it
  once, not on every connection. The `-wal` and `-shm` files must
  remain alongside the main database file.

---

## Concurrency

SQLite uses a file-level lock model. Understanding it prevents
`SQLITE_BUSY` errors.

- **One writer at a time**: only one connection can write at any moment.
  Concurrent write attempts return `SQLITE_BUSY` after the busy
  timeout expires.
- **Busy timeout** (`PRAGMA busy_timeout=N`): milliseconds to wait
  before returning `SQLITE_BUSY`. Set to at least 5000ms for
  applications with concurrent writes. Without this pragma, writes
  fail immediately on contention.
- **Connection per thread**: SQLite connections are not thread-safe by
  default. Use one connection per thread, or enable serialized mode
  (`SQLITE_THREADSAFE=1`) and accept the serialization overhead.
- **WAL vs rollback journal**:
  - Rollback: readers block writers, writers block readers
  - WAL: readers never block writers, writers never block readers;
    only concurrent writers contend
- **Long transactions**: holding a read transaction in WAL mode
  prevents the WAL from being checkpointed past that point. Keep
  read transactions short or use snapshot isolation deliberately.

---

## Type Affinity

SQLite uses a dynamic type system with type affinity -- the column's
declared type is a preference, not an enforcement.

- **Affinity rules**: any column can store any type. The declared type
  name determines the affinity (INTEGER, TEXT, BLOB, REAL, NUMERIC)
  via substring matching rules. `VARCHAR(255)` has TEXT affinity;
  `INT` has INTEGER affinity.
- **Common surprises**:
  - Inserting a string into an INTEGER column succeeds silently
  - `SELECT typeof(col)` can return different types for different rows
    in the same column
  - Comparisons between mismatched types follow documented but
    non-obvious rules (NULL < INTEGER < REAL < TEXT < BLOB)
- **Strict tables** (SQLite 3.37+, 2021-11): `CREATE TABLE t(col INT)
  STRICT` enforces type checking at insert time. Use for new tables
  when your minimum SQLite version supports it.
- **Boolean**: SQLite has no native boolean. Integers 0 and 1 are
  conventional. Document the convention and use CHECK constraints:
  `CHECK(active IN (0, 1))`.
- **Date/time**: no native date type. Store as TEXT (ISO 8601), INTEGER
  (Unix timestamp), or REAL (Julian day). Pick one convention per
  project and enforce with CHECK constraints or application validation.

---

## When to Use SQLite

**Appropriate**:
- Embedded applications (desktop, mobile, IoT)
- Testing and development (in-memory mode, zero configuration)
- Single-user or single-server applications
- Read-heavy workloads with moderate writes
- Data sets up to ~1 TB (practical limit, not a hard ceiling)
- Configuration storage, local caches, application state
- Prototyping before committing to a client-server database

**Inappropriate**:
- High write concurrency (multiple servers, many concurrent writers)
- Multi-server deployment (no built-in replication, file locking
  over NFS is unreliable and often corrupt)
- Fine-grained access control (no user/role system)
- Applications requiring row-level locking
- Network-accessible database service (no built-in network protocol)

The decision is not about data size -- it is about concurrency pattern
and deployment topology. A single-server application processing
millions of rows is often fine with SQLite. A two-server deployment
with shared storage is not.

---

## Backup

SQLite databases are single files, but copying the file directly while
the database is in use risks corruption.

- **`.backup` API**: the recommended approach for online backup.
  Creates a consistent snapshot while the database is in use. Available
  via `sqlite3_backup_init()` in C or `.backup` in the CLI.
- **VACUUM INTO** (SQLite 3.27+): creates a new compacted copy of the
  database. Acts as both a backup and a defragmentation operation:
  `VACUUM INTO '/path/to/backup.db'`.
- **File copy**: safe ONLY when no connections are open (including WAL
  readers). For WAL mode, the `-wal` and `-shm` files must be copied
  atomically with the main file, or checkpointed first.
- **Backup patterns for running applications**:
  1. Use `.backup` API from a dedicated connection
  2. Or checkpoint WAL (`PRAGMA wal_checkpoint(TRUNCATE)`), then copy
     the main database file
  3. Schedule backups during low-write periods to minimize contention
- **Testing restores**: periodically restore backups to a separate path
  and run `PRAGMA integrity_check` to verify backup validity
