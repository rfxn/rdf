# Rust Anti-Patterns Reference

> Deep reference for common Rust anti-patterns, with focus on mistakes
> that AI code generators make frequently. Each section shows the broken
> pattern, explains why it fails, and provides the correct alternative.
> Companion to the Rust governance template.

---

## Excessive .clone() to Silence the Borrow Checker

### Cloning to Avoid Lifetime Reasoning

When the borrow checker complains, the fastest "fix" is `.clone()`.
This compiles but hides design problems and wastes allocations.

Bad:
```rust
fn process_items(items: &[String]) {
    let first = items[0].clone(); // clone to avoid borrow
    let rest = items[1..].to_vec(); // another allocation
    do_work(&first, &rest);
}
```

The function already has a borrow of the data. Cloning it to satisfy
lifetime requirements means the data flow is wrong.

Good:
```rust
fn process_items(items: &[String]) {
    let first = &items[0];
    let rest = &items[1..];
    do_work(first, rest);
}
```

Borrow directly from the slice. If the function signature requires
owned data, reconsider whether ownership transfer is truly needed.

### Cloning Arc/Rc Without Understanding Shared Ownership

Cloning an `Arc` is cheap (reference count bump), but cloning the
inner data defeats the purpose of shared ownership.

Bad:
```rust
fn update_config(config: Arc<Config>) {
    let local_config = (*config).clone(); // clones the inner Config
    process(local_config);
}
```

Good:
```rust
fn update_config(config: Arc<Config>) {
    let config = Arc::clone(&config); // cheap ref count bump
    process(&config);
}
```

Use `Arc::clone(&val)` instead of `val.clone()` to make the intent
explicit -- readers can distinguish ref count bumps from deep copies.

---

## Reaching for unsafe to Bypass the Type System

### unsafe to Dodge Lifetime Errors

When the borrow checker rejects code, `unsafe` makes it compile.
This trades a compile error for undefined behavior.

Bad:
```rust
fn get_longest<'a>(s1: &'a str, s2: &str) -> &'a str {
    if s1.len() >= s2.len() {
        s1
    } else {
        // Compiler rejects this -- s2 doesn't live long enough
        unsafe { std::mem::transmute(s2) } // UB: dangling reference
    }
}
```

The borrow checker is right -- `s2` may not live as long as `'a`.
Transmuting to silence it creates a dangling reference.

Good:
```rust
fn get_longest<'a>(s1: &'a str, s2: &'a str) -> &'a str {
    if s1.len() >= s2.len() {
        s1
    } else {
        s2
    }
}
```

Give both parameters the same lifetime. If they genuinely have
different lifetimes, return an owned `String` instead of a reference.

### unsafe for Interior Mutability

Using `unsafe` to mutate through a shared reference when safe
alternatives exist.

Bad:
```rust
struct Counter {
    value: u32,
}

impl Counter {
    fn increment(&self) {
        unsafe {
            let ptr = &self.value as *const u32 as *mut u32;
            *ptr += 1; // UB: mutating through shared reference
        }
    }
}
```

Good:
```rust
use std::cell::Cell;

struct Counter {
    value: Cell<u32>,
}

impl Counter {
    fn increment(&self) {
        self.value.set(self.value.get() + 1);
    }
}
```

Use `Cell`, `RefCell`, `Mutex`, or `AtomicU32` depending on the
threading model. These are safe abstractions over interior mutability.

---

## Cargo.toml Feature Flag Mistakes

### Using features = ["full"]

Pulling in every feature of a large crate bloats compile times and
binary size with code you never use.

Bad:
```toml
[dependencies]
tokio = { version = "1", features = ["full"] }
serde = { version = "1", features = ["derive"] }
```

Good:
```toml
[dependencies]
tokio = { version = "1", features = ["rt-multi-thread", "net", "macros"] }
serde = { version = "1", features = ["derive"] }
```

List only the features you actually use. Tokio's `"full"` includes
`io-util`, `fs`, `signal`, `process`, and `test-util` -- most
applications use fewer than half.

### feature vs features Typo

`feature` is not a valid key in `Cargo.toml` dependency tables.
Cargo silently ignores it, and the dependency loads with defaults.

Bad:
```toml
[dependencies]
tokio = { version = "1", feature = ["rt", "macros"] }
# ^^^^^^^ silently ignored -- tokio loads with default features only
```

Good:
```toml
[dependencies]
tokio = { version = "1", features = ["rt", "macros"] }
# ^^^^^^^^ correct key
```

This typo is especially common in AI-generated code. The build
succeeds but features are missing, causing confusing runtime errors.

### default-features = false Without Reason

Disabling default features and then re-enabling most of them
individually adds complexity without benefit.

Bad:
```toml
[dependencies]
reqwest = { version = "0.11", default-features = false, features = [
    "json", "rustls-tls", "cookies", "gzip", "brotli"
] }
# This is almost all default features anyway
```

Good:
```toml
[dependencies]
reqwest = { version = "0.11", features = ["json", "cookies"] }
# Default features include rustls-tls, gzip, brotli -- keep them
```

Only disable defaults when you need to swap a specific feature
(e.g., replacing `openssl` with `rustls`).

---

## Lifetime Over-Annotation

### Adding Lifetimes Where Elision Works

Rust's lifetime elision rules handle most cases. Explicit annotations
that match what elision would produce add noise without clarity.

Bad:
```rust
fn first_word<'a>(s: &'a str) -> &'a str {
    s.split_whitespace().next().unwrap_or("")
}
```

Good:
```rust
fn first_word(s: &str) -> &str {
    s.split_whitespace().next().unwrap_or("")
}
```

Elision rule: one input reference, one output reference -- the output
lifetime is inferred from the input. The explicit annotation is
identical to what the compiler infers.

### Lifetimes on Owned Types

Adding lifetime parameters to types that own all their data is a
design error that propagates unnecessary complexity to every user.

Bad:
```rust
struct Config<'a> {
    name: &'a str,    // borrows external data
    port: u16,
}
// Every function using Config now needs a lifetime parameter
```

Good:
```rust
struct Config {
    name: String,     // owns its data
    port: u16,
}
// No lifetime pollution -- Config is self-contained
```

Struct fields should own their data unless there is a measured
performance reason to borrow. Lifetime parameters on structs infect
every function signature that touches them.

---

## Async Runtime Mistakes

### Mixing Async Runtimes

Using tokio types with async-std runtime (or vice versa) causes
deadlocks because runtime-specific types expect their own executor.

Bad:
```rust
// main.rs uses tokio
#[tokio::main]
async fn main() {
    // but this library uses async-std internally
    let data = async_std::fs::read("file.txt").await.unwrap();
    // Might work, might deadlock, depends on runtime internals
}
```

Good:
```rust
#[tokio::main]
async fn main() {
    let data = tokio::fs::read("file.txt").await.unwrap();
}
```

Pick one async runtime for the entire binary. Libraries should be
runtime-agnostic (use `async-trait` or `tower` abstractions).

### Nesting Runtime Creation

Creating a runtime inside code that already runs on a runtime panics
because tokio forbids nested runtimes.

Bad:
```rust
#[tokio::main]
async fn main() {
    let result = compute_sync();
    println!("{}", result);
}

fn compute_sync() -> String {
    let rt = tokio::runtime::Runtime::new().unwrap();
    rt.block_on(async {
        // PANIC: Cannot start a runtime from within a runtime
        fetch_data().await
    })
}
```

Good:
```rust
#[tokio::main]
async fn main() {
    let result = fetch_data().await;
    println!("{}", result);
}
```

Make the function async and propagate `await` up to the runtime
boundary in `main`. There should be exactly one runtime per binary.

### Blocking Inside Async Context

Running CPU-intensive or synchronous I/O on the async executor
thread starves other tasks.

Bad:
```rust
async fn process_file(path: &str) -> Result<String> {
    let data = std::fs::read_to_string(path)?; // blocks executor thread
    let result = expensive_parse(&data); // CPU-bound, blocks executor
    Ok(result)
}
```

Good:
```rust
async fn process_file(path: &str) -> Result<String> {
    let data = tokio::fs::read_to_string(path).await?;
    let result = tokio::task::spawn_blocking(move || {
        expensive_parse(&data)
    }).await?;
    Ok(result)
}
```

Use `tokio::fs` for file I/O and `spawn_blocking` for CPU-bound work.
The async executor stays free to service other tasks.

---

## .unwrap() in Production Code

### Unwrap on User Input

`.unwrap()` panics on `None` or `Err`, crashing the process. On user
input, this is a denial-of-service vulnerability.

Bad:
```rust
fn parse_config(input: &str) -> Config {
    let port: u16 = input.parse().unwrap(); // panics on "abc"
    Config { port }
}
```

Good:
```rust
fn parse_config(input: &str) -> Result<Config, ConfigError> {
    let port: u16 = input.parse()
        .map_err(|_| ConfigError::InvalidPort(input.to_string()))?;
    Ok(Config { port })
}
```

Return `Result` and use `?` for propagation. Reserve `.unwrap()` for
cases where `None`/`Err` is provably impossible (with a comment).

### Unwrap on HashMap::get

Assuming a key exists without checking is a runtime crash waiting
for a missing entry.

Bad:
```rust
let value = map.get("key").unwrap(); // panics if key missing
```

Good:
```rust
let value = map.get("key").unwrap_or(&default_value);
// or
let Some(value) = map.get("key") else {
    return Err(Error::MissingKey("key"));
};
```

Use `.unwrap_or()`, `.unwrap_or_default()`, or pattern matching.

---

## #[deny(warnings)] in Source Code

### Breaking on Compiler Upgrades

`#[deny(warnings)]` in source code means any new compiler warning
added in a Rust update breaks the build.

Bad:
```rust
// lib.rs
#![deny(warnings)]

pub fn add(a: i32, b: i32) -> i32 {
    a + b
}
// Compiles today, breaks tomorrow when rustc 1.XX adds a new lint
```

Good:
```rust
// lib.rs -- no deny(warnings) in source

pub fn add(a: i32, b: i32) -> i32 {
    a + b
}
```

```yaml
# CI configuration
env:
  RUSTFLAGS: "-Dwarnings"
```

Put warning-as-error in CI environment variables, not in source code.
Local development stays warning-tolerant for work-in-progress code.

---

## Outdated Crate Versions from Training Data

### Using Yanked or Deprecated Versions

AI models are trained on code from specific time periods. They may
generate dependency versions that have been yanked for security
vulnerabilities.

Bad:
```toml
[dependencies]
hyper = "0.14"        # old major version
actix-web = "3"       # superseded by v4
```

Good:
```toml
[dependencies]
hyper = "1"            # current stable
actix-web = "4"        # current stable
```

Always verify crate versions on crates.io before using them. Run
`cargo audit` to detect yanked or vulnerable versions.

### Using Removed or Renamed APIs

APIs change between major versions. Code generated for v0.14 of a
crate may not compile against v1.0.

Bad:
```rust
// hyper 0.14 API -- does not exist in hyper 1.x
let client = hyper::Client::new();
let resp = client.get(uri).await?;
```

Good:
```rust
// hyper 1.x API
use hyper_util::client::legacy::Client;
let client = Client::builder(TokioExecutor::new()).build_http();
let resp = client.get(uri).await?;
```

Read the crate's migration guide when the version in your lockfile
differs from what the AI generated. Check the changelog for breaking
changes.

---

## String Type Confusion

### &String Instead of &str

Accepting `&String` in function parameters forces callers to have a
`String`. Accepting `&str` works with both owned and borrowed strings.

Bad:
```rust
fn greet(name: &String) {
    println!("Hello, {}", name);
}

let name = "world"; // &str -- cannot pass to greet without allocation
greet(&name.to_string()); // forced allocation
```

Good:
```rust
fn greet(name: &str) {
    println!("Hello, {}", name);
}

let name = "world";
greet(name); // works directly

let owned = String::from("world");
greet(&owned); // also works via Deref
```

Similarly, prefer `&[T]` over `&Vec<T>` and `&Path` over `&PathBuf`.

### Collecting Into Vec When Iterating

Collecting into a `Vec` just to iterate over it wastes an allocation.
Use iterator adaptors directly.

Bad:
```rust
let names: Vec<String> = users.iter()
    .map(|u| u.name.clone())
    .collect();

for name in &names {
    println!("{}", name);
}
```

Good:
```rust
for name in users.iter().map(|u| &u.name) {
    println!("{}", name);
}
```

Iterators are lazy. Chain `.map()`, `.filter()`, `.take()` without
intermediate allocations. Collect only when you need the final container.
