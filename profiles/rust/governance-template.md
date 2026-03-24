# Rust Governance Template

> Seed template for /r-init. Merged with codebase scan results during
> governance generation. Not copied verbatim -- scan data overrides
> where conflicts exist.

## Ownership & Borrowing

- Prefer owned types (`String`, `Vec<T>`, `PathBuf`) unless profiling
  shows that borrowing is necessary for performance
- Never fight the borrow checker with `.clone()` everywhere -- excessive
  cloning is a design smell. Restructure data flow instead
- Never reach for `unsafe` to bypass borrow or lifetime errors -- if the
  borrow checker rejects it, the design needs to change
- Use `Cow<'_, str>` when a function sometimes owns and sometimes borrows
- Prefer `&str` over `&String` in function parameters -- accepts both
  `String` and `&str` callers
- Struct fields that own their data: use owned types. Struct fields that
  reference external data: use explicit lifetimes with documented reasoning
- When clone is genuinely needed, add a comment explaining why shared
  ownership or borrowing was not feasible

## Error Handling

- Libraries: use `thiserror` for typed error enums with `#[error(...)]`
  derive messages
- Applications: use `anyhow` for ergonomic error propagation with
  context via `.context("...")`
- Never `.unwrap()` or `.expect()` in production code paths -- these
  panic on failure. Use `?` for propagation or explicit match arms
- `.unwrap()` is acceptable only in tests and provably-infallible cases
  with a `// SAFETY:` comment explaining why it cannot fail
- Propagate errors with `?` operator -- do not write explicit match arms
  just to re-wrap the error identically
- Map errors at API boundaries: convert internal error types to public
  error types at the crate boundary, not deep inside business logic
- Never use `Box<dyn Error>` in library APIs -- callers lose the ability
  to match on specific error variants

## Unsafe Discipline

- Every `unsafe` block requires a `// SAFETY:` comment documenting
  the invariant that makes it sound
- Never use `unsafe` to bypass the borrow checker -- it means the design
  is wrong, not that you need to escape the type system
- `unsafe` is appropriate for: FFI boundaries, performance-critical code
  with proven bottleneck, and low-level memory operations with documented
  invariants
- Minimize the scope of `unsafe` blocks -- wrap unsafe operations in safe
  abstractions with validated preconditions
- Audit every `unsafe` block during code review -- it is the reviewer's
  responsibility to verify the SAFETY comment is accurate
- Never transmute between types without identical memory layouts -- use
  `#[repr(C)]` or `#[repr(transparent)]` to guarantee layout

## Cargo Conventions

- Use explicit feature flags -- never depend on `features = ["full"]`
  meta-features (they pull in everything and bloat compile times)
- `feature` vs `features` in `Cargo.toml` -- only `features` is valid;
  `feature` is silently ignored and the dependency loads with defaults
- Use workspace-level dependency management (`[workspace.dependencies]`)
  for multi-crate projects
- Pin dependencies to exact versions in applications (`=1.2.3`); use
  semver ranges in libraries
- Run `cargo update` regularly and review `Cargo.lock` changes
- Check `cargo audit` for known vulnerabilities in dependencies
- Avoid `path` dependencies in published crates -- use version
  requirements with `version` key alongside `path` for dev convenience

## Async Runtime

- One async runtime per binary crate -- mixing tokio and async-std in
  the same binary causes deadlocks and subtle runtime conflicts
- Never nest runtime creation (`Runtime::new()` inside `#[tokio::main]`)
  -- this panics or deadlocks
- Declare the runtime at the application boundary (`main.rs`), not in
  library code -- libraries should be runtime-agnostic
- Use `tokio::spawn` for concurrent tasks, not `std::thread::spawn` for
  async work
- `block_on` from synchronous code is acceptable only at the top-level
  entry point -- never inside an async context
- Prefer `tokio::select!` over manual future polling
- Cancel safety: document whether async functions are cancel-safe and
  use `tokio::pin!` when needed

## Testing

- `cargo test` runs all unit and integration tests -- use as the primary
  test command
- `cargo clippy` in CI with `RUSTFLAGS="-Dwarnings"` -- treat all
  warnings as errors in CI, not in local development
- `cargo fmt --check` in CI -- reject unformatted code
- Integration tests go in `tests/` directory (separate compilation unit)
- Unit tests in `#[cfg(test)] mod tests` at the bottom of each source file
- Use `#[should_panic]` for tests that verify panic behavior
- Use `assert_eq!` and `assert_ne!` over plain `assert!` for better
  failure messages showing both values
- Test both happy paths and error paths -- error handling is where most
  production bugs hide

## Linting

- Use `#[deny(clippy::all)]` in CI configuration (RUSTFLAGS), not in
  source code -- source-level denies break when clippy adds new lints
- Never use `#[deny(warnings)]` in source -- compiler upgrades add new
  warnings, breaking previously-compiling code
- `#[allow(...)]` requires an inline comment explaining why the lint
  does not apply to this specific case
- Enable `clippy::pedantic` in CI for new projects -- suppress specific
  lints that conflict with project conventions
- `#[must_use]` on functions that return values callers should not ignore

## Security

- No `unsafe` without a documented invariant in a `// SAFETY:` comment
- Validate all deserialized data (serde) before use -- deserialization
  succeeds on syntactically valid input regardless of semantic validity
- Check for yanked crates: `cargo audit` in CI pipeline
- Use `secrecy::Secret<T>` for sensitive values -- prevents accidental
  logging via `Debug`/`Display` implementations
- Pin `serde` feature flags explicitly -- `serde_derive` is a proc macro
  with full build-time code execution
- Never store secrets in `Cargo.toml` or hardcode them in source
- Use `zeroize` for sensitive data that must be cleared from memory
- Validate untrusted input at the boundary: parse it into validated types
  (newtype pattern) and pass only the validated type downstream
