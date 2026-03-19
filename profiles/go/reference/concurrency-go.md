# Go Concurrency Reference

> Deep reference for Go concurrency patterns. Covers channels, context
> propagation, sync primitives, deadlock shapes, and errgroup. Companion
> to the Go governance template.

---

## Channel Patterns

### Fan-Out / Fan-In

Multiple workers consume from a single input channel. A single
collector aggregates results. Useful for embarrassingly parallel
workloads.

```go
func fanOut(ctx context.Context, urls []string, workers int) []Result {
    jobs := make(chan string, len(urls))
    results := make(chan Result, len(urls))

    // Launch workers
    var wg sync.WaitGroup
    for i := 0; i < workers; i++ {
        wg.Add(1)
        go func() {
            defer wg.Done()
            for url := range jobs {
                select {
                case <-ctx.Done():
                    return
                case results <- fetch(url):
                }
            }
        }()
    }

    // Send jobs
    for _, url := range urls {
        jobs <- url
    }
    close(jobs)

    // Close results when all workers finish
    go func() {
        wg.Wait()
        close(results)
    }()

    // Collect
    var out []Result
    for r := range results {
        out = append(out, r)
    }
    return out
}
```

### Pipeline

Stages connected by channels. Each stage runs in its own goroutine,
processing items and passing them downstream.

```go
func generate(ctx context.Context, nums ...int) <-chan int {
    out := make(chan int)
    go func() {
        defer close(out)
        for _, n := range nums {
            select {
            case out <- n:
            case <-ctx.Done():
                return
            }
        }
    }()
    return out
}

func square(ctx context.Context, in <-chan int) <-chan int {
    out := make(chan int)
    go func() {
        defer close(out)
        for n := range in {
            select {
            case out <- n * n:
            case <-ctx.Done():
                return
            }
        }
    }()
    return out
}

func filter(ctx context.Context, in <-chan int, max int) <-chan int {
    out := make(chan int)
    go func() {
        defer close(out)
        for n := range in {
            if n <= max {
                select {
                case out <- n:
                case <-ctx.Done():
                    return
                }
            }
        }
    }()
    return out
}

// Usage: filter(ctx, square(ctx, generate(ctx, 1, 2, 3, 4, 5)), 16)
```

Every stage checks `ctx.Done()` so cancellation propagates through
the entire pipeline without goroutine leaks.

### Rate Limiter

A `time.Ticker` controls the rate at which work is dispatched.

```go
func rateLimited(ctx context.Context, items []string, rps int) {
    ticker := time.NewTicker(time.Second / time.Duration(rps))
    defer ticker.Stop()

    for _, item := range items {
        select {
        case <-ticker.C:
            process(item)
        case <-ctx.Done():
            return
        }
    }
}
```

### Semaphore via Buffered Channel

A buffered channel acts as a counting semaphore, limiting concurrent
access to a resource.

```go
func bounded(ctx context.Context, urls []string, maxConcurrent int) []Result {
    sem := make(chan struct{}, maxConcurrent)
    var (
        mu      sync.Mutex
        results []Result
    )

    var wg sync.WaitGroup
    for _, url := range urls {
        wg.Add(1)
        go func(u string) {
            defer wg.Done()
            select {
            case sem <- struct{}{}: // acquire
                defer func() { <-sem }() // release
            case <-ctx.Done():
                return
            }
            r := fetch(u)
            mu.Lock()
            results = append(results, r)
            mu.Unlock()
        }(url)
    }
    wg.Wait()
    return results
}
```

---

## Context Propagation

### Where Context Originates

`context.Background()` should appear only at program boundaries:
`main()`, top-level HTTP handlers, and test functions.

```go
func main() {
    ctx, cancel := signal.NotifyContext(context.Background(), os.Interrupt)
    defer cancel()

    if err := run(ctx); err != nil {
        log.Fatal(err)
    }
}
```

### WithCancel for Cancellation

Use `WithCancel` when a parent needs to signal children to stop.

```go
func superviseTasks(ctx context.Context, tasks []Task) error {
    ctx, cancel := context.WithCancel(ctx)
    defer cancel() // cancel all children when supervisor returns

    errCh := make(chan error, len(tasks))
    for _, task := range tasks {
        go func(t Task) {
            errCh <- t.Run(ctx)
        }(task)
    }

    for range tasks {
        if err := <-errCh; err != nil {
            cancel() // signal remaining tasks to stop
            return err
        }
    }
    return nil
}
```

### WithTimeout for Deadlines

Use `WithTimeout` for operations that must complete within a time bound.

```go
func fetchWithTimeout(url string) ([]byte, error) {
    ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
    defer cancel()

    req, err := http.NewRequestWithContext(ctx, "GET", url, nil)
    if err != nil {
        return nil, fmt.Errorf("create request: %w", err)
    }

    resp, err := http.DefaultClient.Do(req)
    if err != nil {
        return nil, fmt.Errorf("fetch %s: %w", url, err)
    }
    defer resp.Body.Close()

    return io.ReadAll(resp.Body)
}
```

### WithValue -- Sparingly

`context.WithValue` is for request-scoped data (trace IDs, auth
tokens), not for passing function dependencies.

```go
type ctxKey string

const requestIDKey ctxKey = "request_id"

func WithRequestID(ctx context.Context, id string) context.Context {
    return context.WithValue(ctx, requestIDKey, id)
}

func RequestID(ctx context.Context) string {
    id, _ := ctx.Value(requestIDKey).(string)
    return id
}
```

Use unexported typed keys to avoid collisions across packages.
Never use `string` or `int` directly as context keys.

---

## Sync Primitives Decision Tree

| Need | Primitive | Notes |
|------|-----------|-------|
| Protect shared state | `sync.Mutex` | Simple read-write; lock, mutate, unlock |
| Read-heavy shared state | `sync.RWMutex` | Multiple concurrent readers, exclusive writer |
| Communication between goroutines | Channel | Transfer ownership of data |
| Single counter or flag | `atomic.Int64` / `atomic.Bool` | No lock contention for simple values |
| One-time initialization | `sync.Once` | Guaranteed single execution, even under races |
| Temporary object reuse | `sync.Pool` | Reduces GC pressure; objects may be reclaimed |
| Wait for N goroutines | `sync.WaitGroup` | `Add` before launch, `Done` in defer, `Wait` to block |

### sync.Mutex Example

```go
type SafeCounter struct {
    mu    sync.Mutex
    count int
}

func (c *SafeCounter) Inc() {
    c.mu.Lock()
    defer c.mu.Unlock()
    c.count++
}

func (c *SafeCounter) Value() int {
    c.mu.Lock()
    defer c.mu.Unlock()
    return c.count
}
```

### sync.RWMutex for Read-Heavy Workloads

```go
type Cache struct {
    mu    sync.RWMutex
    items map[string]string
}

func (c *Cache) Get(key string) (string, bool) {
    c.mu.RLock()
    defer c.mu.RUnlock()
    v, ok := c.items[key]
    return v, ok
}

func (c *Cache) Set(key, value string) {
    c.mu.Lock()
    defer c.mu.Unlock()
    c.items[key] = value
}
```

Multiple goroutines can read concurrently. Writes take an exclusive
lock, blocking all readers and other writers.

---

## Common Deadlock Shapes

### Circular Channel Dependency

Two goroutines each wait on the other's channel.

```go
// DEADLOCK: A sends to chB, B sends to chA -- both block
chA := make(chan int)
chB := make(chan int)

go func() { chA <- 1; fmt.Println(<-chB) }()
go func() { chB <- 2; fmt.Println(<-chA) }()
```

Fix by buffering one channel or restructuring so sends don't
depend on receives from the other goroutine.

### Inconsistent Mutex Lock Ordering

Two goroutines lock mutexes in different orders.

```go
// DEADLOCK: goroutine 1 holds muA, wants muB
//           goroutine 2 holds muB, wants muA
go func() {
    muA.Lock()
    muB.Lock() // blocks -- goroutine 2 holds muB
    // ...
    muB.Unlock()
    muA.Unlock()
}()

go func() {
    muB.Lock()
    muA.Lock() // blocks -- goroutine 1 holds muA
    // ...
    muA.Unlock()
    muB.Unlock()
}()
```

Fix by always acquiring locks in the same order across all
goroutines. Document the ordering in a comment.

### Goroutine Waiting on Itself

Sending on an unbuffered channel in the same goroutine blocks
forever because there is no concurrent receiver.

```go
// DEADLOCK: send blocks waiting for receiver, but
// the receiver code is after the send
ch := make(chan int)
ch <- 42 // blocks forever
fmt.Println(<-ch)
```

Fix by using a buffered channel (`make(chan int, 1)`) or
launching the send or receive in a separate goroutine.

---

## errgroup Patterns

### Basic Fan-Out with First-Error Cancellation

`errgroup.Group` launches goroutines and returns the first
non-nil error. The associated context is cancelled on error.

```go
func fetchAll(ctx context.Context, urls []string) ([]string, error) {
    g, ctx := errgroup.WithContext(ctx)
    results := make([]string, len(urls))

    for i, url := range urls {
        i, url := i, url // capture for Go <1.22
        g.Go(func() error {
            body, err := fetchURL(ctx, url)
            if err != nil {
                return fmt.Errorf("fetch %s: %w", url, err)
            }
            results[i] = body // safe -- each goroutine writes its own index
            return nil
        })
    }

    if err := g.Wait(); err != nil {
        return nil, err
    }
    return results, nil
}
```

Each goroutine writes to its own index in the results slice, so
no mutex is needed. The `errgroup` context cancels on first error,
causing remaining fetches to abort via context-aware HTTP clients.

### SetLimit for Bounded Concurrency

`SetLimit` restricts how many goroutines run simultaneously.
Calls to `g.Go` block when the limit is reached.

```go
func processAll(ctx context.Context, items []Item) error {
    g, ctx := errgroup.WithContext(ctx)
    g.SetLimit(10) // at most 10 concurrent goroutines

    for _, item := range items {
        item := item // capture for Go <1.22
        g.Go(func() error {
            return process(ctx, item)
        })
    }

    return g.Wait()
}
```

### Collecting Results with Mutex

When results cannot be pre-indexed (variable-length output),
use a mutex to protect the shared collection.

```go
func search(ctx context.Context, queries []string) ([]Match, error) {
    g, ctx := errgroup.WithContext(ctx)

    var (
        mu      sync.Mutex
        matches []Match
    )

    for _, q := range queries {
        q := q // capture for Go <1.22
        g.Go(func() error {
            found, err := runQuery(ctx, q)
            if err != nil {
                return fmt.Errorf("query %q: %w", q, err)
            }
            mu.Lock()
            matches = append(matches, found...)
            mu.Unlock()
            return nil
        })
    }

    if err := g.Wait(); err != nil {
        return nil, err
    }
    return matches, nil
}
```

Lock only around the shared append, not the entire goroutine body.
Keep the critical section as small as possible.
