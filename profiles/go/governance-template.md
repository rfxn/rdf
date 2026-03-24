# Go Governance Template

> Seed template for /r-init. Provides Go best practices for merging
> with codebase scan results. Requires core profile.
> Assumes Go 1.21+ baseline. Generics (1.18+) and slog (1.21+) assumed.
> Project-specific version floors detected by /r-init override these defaults.

## Code Conventions

- gofmt is non-negotiable -- all code must pass `gofmt` with no diff
- Package names: short, lowercase, singular, no underscores (`user` not `users` or `user_service`)
- Unexported by default -- export with justification, not by habit
- Accept interfaces, return structs -- callers define the interfaces they need
- One package per directory -- no multi-package directories
- Avoid `init()` -- implicit execution order creates hidden dependencies; pass
  dependencies explicitly via constructors or config structs
- Blank identifier (`_`) only with a comment explaining why the value is discarded
- Constructors as `New{Type}()` returning `*Type` -- use `Option` funcs for config

## Anti-Patterns

- `interface{}`/`any` as function parameter -- use generics or a minimal interface
  with the methods you actually call
- Goroutine leak -- every goroutine needs a clear exit path: context cancellation,
  done channel, or bounded lifetime
- Shared mutable state without `sync.Mutex` or `sync.RWMutex` -- data races are
  undefined behavior in Go, not just bugs
- `defer` in loop body -- deferred calls accumulate until the enclosing function
  returns; extract loop body into a helper function
- Ignored error return without comment -- `_ = f()` requires a `// reason` comment
- String concatenation in loops -- use `strings.Builder` for O(n) instead of O(n^2)
- Returning concrete type from interface method -- prevents adding methods without
  breaking implementors; return the interface the caller needs
- Package-level mutable state -- use dependency injection; package vars are shared
  across all goroutines and tests
- Deep package nesting (`pkg/internal/service/v2/handler`) -- flat is better than
  nested; group by domain, not by layer

## Error Handling

- Errors are values -- handle them, don't panic
- Wrap with context: `fmt.Errorf("fetch user %d: %w", id, err)`
- `errors.Is()` / `errors.As()` for comparison -- never `==` except against `nil`
- Sentinel errors (`var ErrNotFound = errors.New(...)`) for expected conditions
  that callers branch on
- Custom error types (implementing `error` interface) for structured error data
  that callers inspect with `errors.As()`
- `panic` only for programmer errors -- impossible state, violated invariants
- Don't log and return -- choose one or the other; logging and returning
  duplicates noise and confuses error ownership

## Concurrency

- Channels for communication between goroutines, mutexes for protecting shared state
- `context.Context` as first parameter on anything that blocks or does I/O
- `context.Background()` only at program entry points (main, top-level handler)
- `sync.WaitGroup` -- call `Add` before launching the goroutine, not inside it
- `errgroup.Group` for error-aware fan-out with first-error cancellation
- `select` with `context.Done()` case in every blocking operation
- Buffer channels only with documented reason and bounded size -- unbuffered
  is the safe default
- `sync.Once` for lazy initialization of expensive resources

## Security

- SQL: `database/sql` with `$1`/`?` parameter placeholders -- never interpolate
  user input into query strings
- HTTP: validate all path params, query params, and headers from `net/http`
  before use; never trust `r.URL.Path` without sanitization
- TLS: set `tls.Config.MinVersion = tls.VersionTLS12`; never set
  `InsecureSkipVerify: true` outside test code
- Secrets: load via `os.Getenv()` at startup, store in a config struct, zero
  after use, never include in log output or error messages
- Deserialization: `json.NewDecoder` with `DisallowUnknownFields()`; enforce
  `http.MaxBytesReader` on request bodies
- Race conditions: `-race` flag in CI always -- `go test -race ./...`
- Command execution: `os/exec` with args slice -- never `sh -c` with
  string interpolation

## Testing

- Table-driven tests as the default pattern
- `t.Helper()` on all test helper functions for correct line reporting
- `t.Parallel()` on independent tests -- capture loop variables in Go <1.22
- Testable examples (`ExampleFoo`) for public API documentation
- `httptest.NewServer` for HTTP integration tests
- `t.TempDir()` for filesystem tests -- automatically cleaned up
- Subtests via `t.Run("case name", func(t *testing.T) {...})`
- `-race` in CI always -- `go test -race ./...`
- Benchmarks: `b.ResetTimer()` after setup, `b.ReportAllocs()`, compare
  with `benchstat`

## Build & Packaging

- Go modules (`go.mod`) for dependency management -- one module per repository
- `go.sum` committed to version control -- provides integrity verification
- `go mod tidy` before every commit -- removes unused dependencies
- Build tags (`//go:build`) for platform-specific or optional code
- `CGO_ENABLED=0` for static binaries -- document why CGO is needed if enabled
- Version injection via ldflags: `-ldflags "-X main.version=$(git describe)"`
- Multi-stage Docker builds: builder stage with Go toolchain, runtime stage
  `FROM scratch` or `distroless` -- never ship the compiler
