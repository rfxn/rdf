# Rust Testing Reference

> Deep reference for Rust testing conventions and patterns. Covers
> unit tests, integration tests, property-based testing, snapshot
> testing, and CI pipeline configuration. Companion to the Rust
> governance template.

---

## Unit Tests (#[test] Modules)

Unit tests live inside the source file they test, in a `#[cfg(test)]`
module at the bottom. This module is only compiled during `cargo test`.

```rust
// src/parser.rs

pub fn parse_port(s: &str) -> Result<u16, ParseError> {
    let port: u16 = s.parse().map_err(|_| ParseError::InvalidPort)?;
    if port == 0 {
        return Err(ParseError::PortZero);
    }
    Ok(port)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn valid_port() {
        assert_eq!(parse_port("8080").unwrap(), 8080);
    }

    #[test]
    fn port_zero_rejected() {
        assert!(matches!(parse_port("0"), Err(ParseError::PortZero)));
    }

    #[test]
    fn non_numeric_rejected() {
        assert!(parse_port("abc").is_err());
    }

    #[test]
    fn overflow_rejected() {
        assert!(parse_port("65536").is_err());
    }
}
```

### Conventions

- Use `#[cfg(test)]` on the module, not on individual functions
- `use super::*` to import the parent module's public and private items
- Test names describe the scenario: `valid_port`, `empty_input_rejected`
- Use `assert_eq!` and `assert_ne!` for equality -- they show both
  values on failure. Use `assert!(matches!(...))` for enum variants
- `#[should_panic]` for testing panic behavior:
  `#[should_panic(expected = "index out of bounds")]`
- Keep test functions small -- one assertion per behavior, not one
  function testing ten things

### Testing Private Functions

Unit tests in `#[cfg(test)] mod tests` can access private functions
via `use super::*`. This is intentional -- private functions are
implementation details that unit tests verify.

Do not make functions `pub` solely for testing. If the function is
private, test it from the same module.

---

## Integration Tests (tests/ Directory)

Integration tests live in `tests/` at the crate root. Each file is
compiled as a separate crate that can only access the public API.

```
my-crate/
  src/
    lib.rs
  tests/
    integration_test.rs
    common/
      mod.rs          # shared helpers
```

```rust
// tests/integration_test.rs

use my_crate::Config;

#[test]
fn config_roundtrip() {
    let config = Config::new("localhost", 8080);
    let json = config.to_json().unwrap();
    let restored = Config::from_json(&json).unwrap();
    assert_eq!(config, restored);
}
```

### Shared Test Helpers

Place shared setup code in `tests/common/mod.rs` (not `tests/common.rs`
-- the latter becomes its own test file).

```rust
// tests/common/mod.rs
pub fn setup_test_db() -> TestDb {
    // shared setup logic
}
```

```rust
// tests/integration_test.rs
mod common;

#[test]
fn test_with_db() {
    let db = common::setup_test_db();
    // test using db
}
```

### Binary Crate Testing

Binary crates (`src/main.rs`) cannot be imported by integration tests.
Extract logic into a library crate (`src/lib.rs`) and have `main.rs`
call into it. Integration tests import the library.

```rust
// src/main.rs
fn main() {
    if let Err(e) = my_crate::run() {
        eprintln!("Error: {e}");
        std::process::exit(1);
    }
}

// src/lib.rs
pub fn run() -> Result<(), Error> {
    // application logic
}
```

---

## Property-Based Testing with proptest

proptest generates random inputs to find edge cases that hand-written
tests miss. It shrinks failing inputs to the minimal reproduction.

```toml
[dev-dependencies]
proptest = "1"
```

```rust
use proptest::prelude::*;

proptest! {
    #[test]
    fn parse_roundtrip(port in 1u16..=65535) {
        let s = port.to_string();
        let parsed = parse_port(&s).unwrap();
        prop_assert_eq!(parsed, port);
    }

    #[test]
    fn never_panics_on_arbitrary_input(s in "\\PC*") {
        // Just verify it doesn't panic -- errors are fine
        let _ = parse_port(&s);
    }
}
```

### Strategy Composition

Build complex input generators from simple ones.

```rust
fn arb_config() -> impl Strategy<Value = Config> {
    (
        "[a-z]{1,20}",           // hostname
        1024u16..65535,           // port
        prop::bool::ANY,         // tls enabled
    )
    .prop_map(|(host, port, tls)| Config {
        host: host.to_string(),
        port,
        tls_enabled: tls,
    })
}

proptest! {
    #[test]
    fn config_serialization_roundtrip(config in arb_config()) {
        let json = serde_json::to_string(&config).unwrap();
        let restored: Config = serde_json::from_str(&json).unwrap();
        prop_assert_eq!(config, restored);
    }
}
```

### When to Use Property Tests

- Serialization/deserialization roundtrips
- Parser input -- verify no panics on arbitrary byte sequences
- Mathematical properties (commutativity, associativity, idempotence)
- State machine transitions -- generate sequences of operations
- Sorting, searching, filtering -- verify postconditions hold

---

## Trait Mocking with mockall

mockall generates mock implementations of traits for testing.

```toml
[dev-dependencies]
mockall = "0.13"
```

```rust
use mockall::automock;

#[automock]
trait UserRepository {
    fn find_by_id(&self, id: u64) -> Result<User, DbError>;
    fn save(&self, user: &User) -> Result<(), DbError>;
}

#[cfg(test)]
mod tests {
    use super::*;
    use mockall::predicate::*;

    #[test]
    fn service_returns_user_from_repo() {
        let mut mock_repo = MockUserRepository::new();
        mock_repo
            .expect_find_by_id()
            .with(eq(42))
            .times(1)
            .returning(|_| Ok(User { id: 42, name: "Alice".into() }));

        let service = UserService::new(Box::new(mock_repo));
        let user = service.get_user(42).unwrap();
        assert_eq!(user.name, "Alice");
    }
}
```

### Mocking Boundaries, Not Internals

Mock at the boundary between your code and external systems (database,
HTTP client, filesystem). Do not mock internal functions -- test them
with real implementations.

```
[Handler] -> [Service] -> [MockRepository]
                              ^
                              mock here -- the boundary to external I/O
```

---

## Snapshot Testing with insta

insta captures output as "snapshots" and compares against saved versions.
Changes are reviewed interactively with `cargo insta review`.

```toml
[dev-dependencies]
insta = { version = "1", features = ["yaml"] }
```

```rust
use insta::assert_yaml_snapshot;

#[test]
fn api_response_format() {
    let response = build_response(test_data());
    assert_yaml_snapshot!(response);
}
```

On first run, insta creates a snapshot file in `snapshots/`. On
subsequent runs, it compares output against the saved snapshot.

### Workflow

1. Write test with `assert_snapshot!` or `assert_yaml_snapshot!`
2. Run `cargo test` -- test fails because no snapshot exists yet
3. Run `cargo insta review` -- interactively accept or reject snapshots
4. Commit the snapshot file alongside the test
5. On future runs, output is compared against the committed snapshot

### When to Use Snapshots

- Complex structured output (JSON, YAML, formatted strings)
- Error message formatting
- CLI help text and usage output
- Rendered templates
- Diagnostic output

---

## Cargo Test Configuration

### Running Tests

```bash
# Run all tests (unit + integration)
cargo test

# Run tests matching a pattern
cargo test parse_port

# Run tests in a specific module
cargo test parser::tests

# Run a specific integration test file
cargo test --test integration_test

# Run with output visible (normally captured)
cargo test -- --nocapture

# Run ignored tests (marked with #[ignore])
cargo test -- --ignored
```

### Test Features

Use feature flags to gate tests that require external resources.

```toml
[features]
integration = []

[dev-dependencies]
testcontainers = { version = "0.15", optional = true }
```

```rust
#[test]
#[cfg(feature = "integration")]
fn test_with_postgres() {
    // requires running Postgres
}
```

Run with `cargo test --features integration`.

### Doc Tests

Code blocks in doc comments are compiled and run as tests.

```rust
/// Parses a port number from a string.
///
/// # Examples
///
/// ```
/// use my_crate::parse_port;
///
/// assert_eq!(parse_port("8080").unwrap(), 8080);
/// assert!(parse_port("abc").is_err());
/// ```
pub fn parse_port(s: &str) -> Result<u16, ParseError> {
    // ...
}
```

Doc tests verify that examples in documentation actually compile and
produce the claimed output. They run with `cargo test` by default.

---

## CI Pipeline

### Minimum CI Configuration

```yaml
# .github/workflows/ci.yml
name: CI
on: [push, pull_request]

env:
  RUSTFLAGS: "-Dwarnings"
  CARGO_TERM_COLOR: always

jobs:
  check:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: dtolnay/rust-toolchain@stable
        with:
          components: clippy, rustfmt

      - name: Format check
        run: cargo fmt --all --check

      - name: Clippy
        run: cargo clippy --all-targets --all-features

      - name: Tests
        run: cargo test --all-features

      - name: Security audit
        run: |
          cargo install cargo-audit
          cargo audit
```

### Pipeline Order

1. `cargo fmt --check` -- fast, catches formatting issues immediately
2. `cargo clippy --all-targets --all-features` -- catches lint issues
   before spending time on tests
3. `cargo test --all-features` -- run the full test suite
4. `cargo audit` -- check for known vulnerabilities in dependencies

### MSRV (Minimum Supported Rust Version) Testing

If the project declares an MSRV in `Cargo.toml`, test against it:

```yaml
  msrv:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: dtolnay/rust-toolchain@master
        with:
          toolchain: "1.70" # match rust-version in Cargo.toml
      - run: cargo test
```
