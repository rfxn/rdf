# NoSQL Patterns

> Decision framework and engine-specific patterns for non-relational
> databases. Covers when to choose which model, MongoDB document
> patterns, Redis data structure usage, and common anti-patterns.

---

## Decision Framework

Choose the data model based on access patterns, not hype. Every model
has trade-offs -- there is no universal "faster" or "more scalable"
option.

| Model | Choose When | Avoid When |
|-------|------------|------------|
| Relational | ACID required, complex joins, strict schema, reporting | Schema changes hourly, deeply nested 1:1 mapped documents |
| Document | Flexible schema, nested data, rapid iteration, read-heavy with known access patterns | Heavy cross-document joins, strict consistency across collections |
| Key-value | Caching, sessions, counters, feature flags, rate limiting | Complex queries, relationships, range scans on values |
| Graph | Relationship-heavy queries (social networks, fraud detection, dependency trees) | Simple CRUD, tabular data, write-heavy with few traversals |
| Time-series | Metrics, logs, IoT sensor data, append-heavy with time-range queries | Random access by non-time key, frequent updates to historical data |
| Wide-column | Write-heavy, known query patterns, horizontal scaling (Cassandra, HBase) | Ad-hoc queries, strong consistency, small data sets |

When uncertain, start relational. Migrating from relational to
document is straightforward; migrating the other direction is painful
because document stores hide implicit relationships.

---

## MongoDB Patterns

### Schema Design

MongoDB schema design is driven by access patterns, not normalization.

- **Embed for 1:few** (address in user document, line items in order):
  atomic updates, single read, no joins required. Embed when the
  child data is always accessed with the parent.
- **Reference for 1:many** (comments on a post, orders for a customer):
  use ObjectId references when the child collection grows unboundedly
  or is accessed independently. Embedding unbounded arrays causes
  document growth beyond the 16 MB limit.
- **Denormalize for read performance**: store frequently-read fields
  from referenced documents (e.g., author name in article). Accept
  the write-time cost of keeping copies in sync.

### Indexing

- **Compound indexes**: field order matters -- query predicates first,
  sort fields next, range fields last (ESR rule: Equality, Sort, Range)
- **Multikey indexes**: automatic on array fields. Be aware that a
  compound index can have at most one array field.
- **Text indexes**: `{ "$text": { "$search": "term" } }` for basic
  full-text search. For production search, consider a dedicated search
  engine (Elasticsearch, Atlas Search).

### Aggregation Pipeline

- Pipeline stages execute sequentially -- place `$match` and `$project`
  early to reduce documents flowing through later stages
- `$lookup` is a left outer join -- use sparingly; if you need it
  frequently, the schema may benefit from embedding
- `$facet` runs multiple pipelines in parallel on the same input --
  useful for dashboards with multiple aggregations

---

## Redis Patterns

### Data Structure Selection

Redis is a data structure server, not a simple key-value store.
Choosing the right structure eliminates application-side complexity.

| Structure | Use For | Example |
|-----------|---------|---------|
| String | Simple values, counters, distributed locks | Session token, rate limit counter |
| Hash | Object with named fields | User profile, configuration map |
| List | Ordered sequence, queues | Job queue (LPUSH/BRPOP), recent activity feed |
| Set | Unique membership, intersections | Tags, online users, mutual friends |
| Sorted set | Ranked data, range queries by score | Leaderboard, priority queue, time-windowed events |
| Stream | Append-only log, consumer groups | Event sourcing, reliable message queue |

### TTL Discipline

- **Always set TTL on cache keys** -- keys without expiration
  accumulate until memory exhaustion triggers eviction
- Use `EXPIRE` or `SET ... EX` at write time, not as an afterthought
- Monitor `evicted_keys` in INFO stats -- non-zero evictions with
  `maxmemory-policy` active means the cache is undersized
- For session storage: TTL matches session timeout; refresh on access

### Persistence Modes

- **RDB** (snapshots): periodic point-in-time snapshots. Low overhead,
  but data loss window equals snapshot interval. Good for caches.
- **AOF** (append-only file): logs every write operation. `appendfsync
  everysec` balances durability and performance (1 second data loss
  window). `appendfsync always` for zero loss at significant
  throughput cost.
- **RDB + AOF**: use both for maximum safety -- AOF for durability,
  RDB for faster restart.
- **No persistence**: valid for pure caching -- fastest, but data lost
  on restart.

### Pub/Sub

- Fire-and-forget: messages are not stored -- if no subscriber is
  listening, the message is lost
- Not reliable messaging: use Streams with consumer groups for
  at-least-once delivery
- Connection dedicated: a subscribed connection cannot run other
  commands -- maintain separate connections for pub/sub and data access

---

## Anti-Patterns

### Redis as Primary Data Store

Redis persistence (RDB/AOF) does not provide the durability guarantees
of a proper database. Snapshot gaps lose data, AOF rewrite can lose
the last second of writes, and replication is asynchronous by default.
Use Redis for caching and ephemeral state -- keep the source of truth
in a durable database.

### Schema-on-Read Without Validation

Document stores (MongoDB, CouchDB) allow any shape. Without validation
rules (`jsonSchema` in MongoDB, application-level checks), data rots
over time -- missing fields, inconsistent types, deprecated formats.
Add validation at write time even when the schema is flexible.

### Unbounded Collections

- Redis lists/sets without size limits grow until memory exhaustion.
  Use `LTRIM` after `LPUSH` for bounded lists, or sorted sets with
  score-based cleanup.
- MongoDB arrays without size limits hit the 16 MB document limit.
  Use the bucket pattern (fixed-size sub-documents) for time-series
  or use references when the array is unbounded.
- Missing TTLs on cache keys, temporary data, and session records.
  Every ephemeral key needs an expiration policy.

### Large Values in Redis

Redis is optimized for small values (< 100 KB). Storing multi-megabyte
blobs degrades performance:
- Large values block the single-threaded event loop during serialization
- They fragment memory, increasing RSS beyond the logical data size
- Network transfer time increases, raising latency for all clients

Store large objects in object storage or a database and keep only
references (URLs, keys) in Redis.
