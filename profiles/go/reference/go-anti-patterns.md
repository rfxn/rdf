# Go Anti-Patterns Reference

> Deep reference for common Go anti-patterns. Each section shows
> the broken pattern, explains why it fails, and provides the correct
> alternative. Companion to the Go governance template.

---

## Goroutine Leaks

### Blocked Channel Send with No Receiver

A goroutine sending on a channel that nobody reads will block forever.
The goroutine stays in memory until the process exits.

Bad:
```go
func process(ctx context.Context) {
    ch := make(chan int)
    go func() {
        result := expensiveComputation()
        ch <- result // blocks forever if caller returns early
    }()

    select {
    case <-ctx.Done():
        return // goroutine above is now leaked
    case v := <-ch:
        fmt.Println(v)
    }
}
```

The goroutine has no way to learn that the caller gave up. It stays
blocked on the send indefinitely.

Good:
```go
func process(ctx context.Context) {
    ch := make(chan int, 1) // buffer of 1 lets sender complete without receiver
    go func() {
        result := expensiveComputation()
        select {
        case ch <- result:
        case <-ctx.Done():
        }
    }()

    select {
    case <-ctx.Done():
        return
    case v := <-ch:
        fmt.Println(v)
    }
}
```

Buffer the channel or give the sender a `select` on context cancellation.
Both ensure the goroutine can exit.

### Missing Context Cancellation in Long-Running Goroutine

A goroutine that loops without checking context will run until the
process exits, even after the work is no longer needed.

Bad:
```go
func poll(url string) <-chan int {
    ch := make(chan int)
    go func() {
        for {
            status := checkHealth(url)
            ch <- status
            time.Sleep(5 * time.Second) // runs forever
        }
    }()
    return ch
}
```

Good:
```go
func poll(ctx context.Context, url string) <-chan int {
    ch := make(chan int)
    go func() {
        defer close(ch)
        ticker := time.NewTicker(5 * time.Second)
        defer ticker.Stop()
        for {
            status := checkHealth(url)
            select {
            case ch <- status:
            case <-ctx.Done():
                return
            }
            select {
            case <-ticker.C:
            case <-ctx.Done():
                return
            }
        }
    }()
    return ch
}
```

Every loop iteration checks `ctx.Done()`. The caller cancels the
context when polling is no longer needed.

### time.After in Select Loop

`time.After` creates a new timer channel on every iteration. Previous
timers are not garbage collected until they fire, leaking memory.

Bad:
```go
for {
    select {
    case msg := <-ch:
        process(msg)
    case <-time.After(30 * time.Second): // new timer every iteration
        fmt.Println("idle timeout")
        return
    }
}
```

Good:
```go
timer := time.NewTimer(30 * time.Second)
defer timer.Stop()
for {
    select {
    case msg := <-ch:
        process(msg)
        if !timer.Stop() {
            <-timer.C
        }
        timer.Reset(30 * time.Second)
    case <-timer.C:
        fmt.Println("idle timeout")
        return
    }
}
```

Create one `time.NewTimer`, reuse it with `Reset`. Drain the channel
before resetting to avoid stale fires.

---

## Interface Pollution

### Accepting Concrete Types When Interface Would Do

Functions that accept concrete types are tightly coupled and hard to test.

Bad:
```go
func SaveReport(db *sql.DB, report Report) error {
    _, err := db.Exec("INSERT INTO reports ...", report.Title)
    return err
}
```

Good:
```go
type Executor interface {
    Exec(query string, args ...any) (sql.Result, error)
}

func SaveReport(db Executor, report Report) error {
    _, err := db.Exec("INSERT INTO reports ...", report.Title)
    return err
}
```

Define the interface where it is consumed, not where it is implemented.
This lets tests pass a mock without importing the production database.

### Returning Interfaces Instead of Structs

Returning an interface prevents callers from accessing methods added
later, and hides the concrete type unnecessarily.

Bad:
```go
type Store interface {
    Get(id string) (Item, error)
}

func NewStore(dsn string) Store { // returns interface
    return &pgStore{dsn: dsn}
}
```

Good:
```go
func NewStore(dsn string) *PGStore { // returns concrete
    return &PGStore{dsn: dsn}
}
```

Return the concrete type. Callers that need abstraction define their
own interfaces with only the methods they use.

### Defining Interfaces in the Implementation Package

Interfaces defined alongside their implementation serve no abstraction
purpose -- they just duplicate the method set.

Bad:
```go
// package storage
type UserStore interface {
    Get(id int) (*User, error)
    Save(u *User) error
}

type pgUserStore struct{ db *sql.DB }
// implements UserStore
```

Good:
```go
// package handler -- the consumer defines what it needs
type UserGetter interface {
    Get(id int) (*User, error)
}

func NewHandler(users UserGetter) *Handler {
    return &Handler{users: users}
}
```

The consumer package defines the minimal interface it requires.
This is Go's implicit interface satisfaction at work.

---

## Error Handling Mistakes

### Log and Return

Logging an error and then returning it causes duplicate noise in
logs and confuses ownership -- who is responsible for handling it?

Bad:
```go
func fetchUser(id int) (*User, error) {
    user, err := db.QueryUser(id)
    if err != nil {
        log.Printf("failed to fetch user %d: %v", id, err)
        return nil, fmt.Errorf("fetch user %d: %w", id, err)
    }
    return user, nil
}
```

Good:
```go
func fetchUser(id int) (*User, error) {
    user, err := db.QueryUser(id)
    if err != nil {
        return nil, fmt.Errorf("fetch user %d: %w", id, err)
    }
    return user, nil
}
```

Return the wrapped error. Let the top-level caller (HTTP handler,
main) decide whether to log. Each layer adds context via wrapping.

### Bare Errors Without Context

Errors without wrapping lose the call chain, making debugging a
guessing game.

Bad:
```go
func loadConfig(path string) (*Config, error) {
    data, err := os.ReadFile(path)
    if err != nil {
        return nil, err // caller sees "open /etc/app.conf: no such file"
    }
    var cfg Config
    if err := json.Unmarshal(data, &cfg); err != nil {
        return nil, err // caller sees "invalid character..." with no context
    }
    return &cfg, nil
}
```

Good:
```go
func loadConfig(path string) (*Config, error) {
    data, err := os.ReadFile(path)
    if err != nil {
        return nil, fmt.Errorf("load config %s: %w", path, err)
    }
    var cfg Config
    if err := json.Unmarshal(data, &cfg); err != nil {
        return nil, fmt.Errorf("parse config %s: %w", path, err)
    }
    return &cfg, nil
}
```

Wrap every error with the operation and key parameters. Use `%w` so
callers can use `errors.Is()` and `errors.As()`.

---

## Over-Abstraction

### Unnecessary Interfaces for Single Implementations

An interface with exactly one implementation adds indirection without
flexibility. Wait until you have two concrete types or a testing need.

Bad:
```go
type UserService interface {
    Create(u User) error
}

type userServiceImpl struct{ db *sql.DB }

func (s *userServiceImpl) Create(u User) error { ... }
```

Good:
```go
type UserService struct{ db *sql.DB }

func (s *UserService) Create(u User) error { ... }
```

Use a concrete struct. If a test needs to stub it, the test package
defines a one-method interface. The concrete type satisfies it
implicitly.

### Premature Generics

Generics add complexity. Using them when only one type is involved
makes code harder to read for no benefit.

Bad:
```go
func Map[T any, U any](items []T, fn func(T) U) []U {
    result := make([]U, len(items))
    for i, item := range items {
        result[i] = fn(item)
    }
    return result
}

// called only as: Map[string, int](names, len)
```

Good:
```go
func nameLengths(names []string) []int {
    result := make([]int, len(names))
    for i, name := range names {
        result[i] = len(name)
    }
    return result
}
```

Write concrete code first. Introduce generics when you have two or
more concrete versions of the same algorithm.

---

## Standard Library Misuse

### http.DefaultClient Has No Timeout

`http.DefaultClient` has zero timeout -- requests can hang indefinitely,
leaking goroutines and connections.

Bad:
```go
resp, err := http.Get("https://api.example.com/data")
```

Good:
```go
client := &http.Client{
    Timeout: 10 * time.Second,
}
resp, err := client.Get("https://api.example.com/data")
```

Always create a client with an explicit `Timeout`. For production
code, also configure `Transport` with `MaxIdleConns` and
`IdleConnTimeout`.

### json.Unmarshal into any

Unmarshaling into `any`/`interface{}` produces `map[string]interface{}`
with `float64` for all numbers. Type safety is completely lost.

Bad:
```go
var data any
if err := json.Unmarshal(body, &data); err != nil {
    return err
}
m := data.(map[string]interface{}) // type assertion, panics on wrong shape
name := m["name"].(string)         // another panic risk
```

Good:
```go
type Response struct {
    Name  string `json:"name"`
    Count int    `json:"count"`
}

var resp Response
if err := json.Unmarshal(body, &resp); err != nil {
    return fmt.Errorf("parse response: %w", err)
}
// resp.Name and resp.Count are typed
```

Always unmarshal into a defined struct. Use `json.Decoder` with
`DisallowUnknownFields()` for strict parsing.

### strings.Replace vs strings.ReplaceAll

`strings.Replace` with `n=-1` works but obscures intent.
`strings.ReplaceAll` (Go 1.12+) is explicit.

Bad:
```go
clean := strings.Replace(input, "\r\n", "\n", -1)
```

Good:
```go
clean := strings.ReplaceAll(input, "\r\n", "\n")
```

Use `strings.ReplaceAll` when replacing all occurrences.
Reserve `strings.Replace` for cases where `n` is a specific
positive count.
