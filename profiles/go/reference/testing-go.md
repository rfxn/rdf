# Go Testing Reference

> Deep reference for Go testing conventions and patterns. Covers
> table-driven tests, benchmarking, fuzz testing, integration isolation,
> and test helpers. Companion to the Go governance template.

---

## Table-Driven Tests

Table-driven tests are Go's idiomatic pattern for testing multiple
inputs through the same logic. Define a slice of test cases, loop
with `t.Run` for named subtests.

```go
func TestParsePort(t *testing.T) {
    tests := []struct {
        name    string
        input   string
        want    int
        wantErr bool
    }{
        {name: "valid port", input: "8080", want: 8080},
        {name: "zero", input: "0", want: 0},
        {name: "max valid", input: "65535", want: 65535},
        {name: "negative", input: "-1", wantErr: true},
        {name: "too large", input: "65536", wantErr: true},
        {name: "not a number", input: "abc", wantErr: true},
        {name: "empty string", input: "", wantErr: true},
    }

    for _, tt := range tests {
        t.Run(tt.name, func(t *testing.T) {
            got, err := ParsePort(tt.input)
            if tt.wantErr {
                if err == nil {
                    t.Fatalf("ParsePort(%q) = %d, want error", tt.input, got)
                }
                return
            }
            if err != nil {
                t.Fatalf("ParsePort(%q) unexpected error: %v", tt.input, err)
            }
            if got != tt.want {
                t.Errorf("ParsePort(%q) = %d, want %d", tt.input, got, tt.want)
            }
        })
    }
}
```

### Parallel Subtests

Call `t.Parallel()` inside each subtest for concurrent execution.
In Go versions before 1.22, capture the loop variable to avoid
all subtests sharing the last value.

```go
for _, tt := range tests {
    tt := tt // capture for Go <1.22 -- loop var reuse
    t.Run(tt.name, func(t *testing.T) {
        t.Parallel()
        got := Transform(tt.input)
        if got != tt.want {
            t.Errorf("Transform(%q) = %q, want %q", tt.input, got, tt.want)
        }
    })
}
```

Go 1.22+ changed loop variable semantics so capture is no longer
needed, but including it is harmless and keeps code compatible
with older Go versions.

---

## Benchmarking

### Basic Benchmark Structure

```go
func BenchmarkHash(b *testing.B) {
    data := []byte("benchmark input data for hashing")
    b.ResetTimer() // exclude setup from timing
    b.ReportAllocs()
    for i := 0; i < b.N; i++ {
        sha256.Sum256(data)
    }
}
```

`b.ResetTimer()` discards time spent in setup. `b.ReportAllocs()`
reports memory allocations per iteration.

### Preventing Compiler Optimization

The compiler may eliminate calls whose results are unused. Assign
to a package-level variable to prevent dead code elimination.

```go
var benchResult uint64 // package-level to prevent optimization

func BenchmarkChecksum(b *testing.B) {
    data := make([]byte, 4096)
    b.ResetTimer()
    var r uint64
    for i := 0; i < b.N; i++ {
        r = crc64.Checksum(data, crc64.MakeTable(crc64.ECMA))
    }
    benchResult = r
}
```

### Comparing Benchmarks with benchstat

Run benchmarks before and after a change, then compare:

```bash
go test -bench=BenchmarkHash -count=10 ./... > old.txt
# apply changes
go test -bench=BenchmarkHash -count=10 ./... > new.txt
benchstat old.txt new.txt
```

Use `-count=10` or more for statistical significance. benchstat
reports the difference with confidence intervals.

---

## Fuzz Testing (Go 1.18+)

Fuzz testing generates random inputs to find edge cases that
hand-written tests miss. The fuzzer mutates seed corpus entries
to explore new code paths.

```go
func FuzzParseJSON(f *testing.F) {
    // Seed corpus from known inputs
    f.Add([]byte(`{"name": "alice"}`))
    f.Add([]byte(`{}`))
    f.Add([]byte(`null`))
    f.Add([]byte(``))

    f.Fuzz(func(t *testing.T, data []byte) {
        var result map[string]any
        err := json.Unmarshal(data, &result)
        if err != nil {
            return // invalid input is fine -- just don't panic
        }

        // Round-trip: marshal back and unmarshal again
        out, err := json.Marshal(result)
        if err != nil {
            t.Fatalf("Marshal failed after successful Unmarshal: %v", err)
        }

        var result2 map[string]any
        if err := json.Unmarshal(out, &result2); err != nil {
            t.Fatalf("Round-trip Unmarshal failed: %v", err)
        }
    })
}
```

Run with `go test -fuzz=FuzzParseJSON -fuzztime=30s`. Crashes are
saved in `testdata/fuzz/FuzzParseJSON/` as reproducible test cases.

### Crash Analysis Workflow

1. Fuzzer finds a crash and writes the input to `testdata/fuzz/`
2. `go test` automatically includes saved corpus entries as regression tests
3. Fix the bug, run `go test` -- the corpus entry verifies the fix
4. Commit the corpus entry alongside the fix for permanent regression coverage

---

## Integration Test Isolation

### Build Tags for Separation

Use build tags to separate integration tests from unit tests.
Integration tests only run when explicitly requested.

```go
//go:build integration

package storage_test

import (
    "testing"
)

func TestPostgresInsert(t *testing.T) {
    dsn := os.Getenv("TEST_DATABASE_URL")
    if dsn == "" {
        t.Skip("TEST_DATABASE_URL not set")
    }
    db, err := sql.Open("postgres", dsn)
    if err != nil {
        t.Fatalf("connect: %v", err)
    }
    t.Cleanup(func() { db.Close() })

    // test logic here
}
```

Run with `go test -tags=integration ./...`. Unit tests run with
plain `go test ./...` and skip tagged files entirely.

### httptest for HTTP Tests

```go
func TestHealthEndpoint(t *testing.T) {
    handler := NewRouter()
    srv := httptest.NewServer(handler)
    t.Cleanup(srv.Close)

    resp, err := http.Get(srv.URL + "/health")
    if err != nil {
        t.Fatalf("GET /health: %v", err)
    }
    defer resp.Body.Close()

    if resp.StatusCode != http.StatusOK {
        t.Errorf("status = %d, want %d", resp.StatusCode, http.StatusOK)
    }
}
```

`httptest.NewServer` starts a real HTTP server on a random port.
Use `t.Cleanup` to shut it down after the test finishes.

### t.TempDir for Filesystem Tests

```go
func TestWriteConfig(t *testing.T) {
    dir := t.TempDir() // automatically cleaned up
    path := filepath.Join(dir, "config.json")

    err := WriteConfig(path, &Config{Host: "localhost", Port: 8080})
    if err != nil {
        t.Fatalf("WriteConfig: %v", err)
    }

    data, err := os.ReadFile(path)
    if err != nil {
        t.Fatalf("ReadFile: %v", err)
    }
    if !strings.Contains(string(data), "localhost") {
        t.Errorf("config missing host: %s", data)
    }
}
```

---

## Test Helpers

### t.Helper for Correct Line Reporting

Without `t.Helper()`, test failures report the line inside the
helper function, not the line in the test that called it.

```go
func assertStatusCode(t *testing.T, resp *http.Response, want int) {
    t.Helper()
    if resp.StatusCode != want {
        t.Errorf("status = %d, want %d", resp.StatusCode, want)
    }
}

func TestEndpoints(t *testing.T) {
    resp := doRequest(t, "GET", "/api/users")
    assertStatusCode(t, resp, 200) // failure points here, not inside helper
}
```

### testing.TB for Shared Helpers

Use `testing.TB` when a helper works with both `*testing.T` and
`*testing.B`. This lets benchmark tests reuse the same setup code.

```go
func setupTestDB(tb testing.TB) *sql.DB {
    tb.Helper()
    db, err := sql.Open("sqlite3", ":memory:")
    if err != nil {
        tb.Fatalf("open db: %v", err)
    }
    tb.Cleanup(func() { db.Close() })
    return db
}
```

### Golden Files for Complex Output

Compare function output against files in `testdata/`. Update
golden files with a flag when output intentionally changes.

```go
var update = flag.Bool("update", false, "update golden files")

func TestRenderTemplate(t *testing.T) {
    got := RenderTemplate(sampleData)

    golden := filepath.Join("testdata", t.Name()+".golden")
    if *update {
        os.WriteFile(golden, []byte(got), 0644)
        return
    }

    want, err := os.ReadFile(golden)
    if err != nil {
        t.Fatalf("read golden file: %v", err)
    }
    if got != string(want) {
        t.Errorf("output mismatch:\ngot:\n%s\nwant:\n%s", got, want)
    }
}
```

Run `go test -update` to regenerate golden files after intentional
output changes. Commit the updated files alongside the code change.
