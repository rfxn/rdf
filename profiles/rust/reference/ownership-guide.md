# Rust Ownership & Borrowing Guide

> Decision framework for ownership, borrowing, and lifetime patterns
> in Rust. Covers when to own vs borrow, interior mutability, smart
> pointers, and lifetime elision. Companion to the Rust governance
> template.

---

## When to Own vs Borrow

### Decision Framework

Ask these questions in order:

1. **Does the receiver need to outlive the caller?** Yes -> owned type.
   Spawning a thread or returning data that lives beyond the function
   scope requires ownership transfer.

2. **Does the receiver modify the data?** Yes -> `&mut T` (exclusive
   borrow) or owned `T` (take ownership, return modified value).

3. **Is the data cheap to copy?** (`Copy` types: integers, booleans,
   `char`, fixed-size arrays of `Copy` types) -> pass by value.

4. **Is the function a constructor or builder?** Yes -> take owned types
   for fields that the struct will store.

5. **None of the above?** -> `&T` (shared borrow). This is the default.

### Function Parameter Guidelines

| Scenario | Parameter type | Reason |
|----------|---------------|--------|
| Reading string data | `&str` | Accepts both `String` and `&str` |
| Reading byte data | `&[u8]` | Accepts `Vec<u8>`, `&[u8]`, arrays |
| Reading a path | `&Path` or `impl AsRef<Path>` | Accepts `PathBuf`, `&Path`, `&str` |
| Storing in struct field | `String`, `Vec<T>`, `PathBuf` | Struct owns data |
| Building a collection | `impl IntoIterator<Item = T>` | Accepts any iterable |
| Conditionally owning | `Cow<'_, str>` | Avoids allocation when borrowing suffices |

### Return Type Guidelines

| Scenario | Return type | Reason |
|----------|------------|--------|
| Computed new value | `String`, `Vec<T>` | Caller owns result |
| View into self | `&str`, `&[T]` | Zero-copy access |
| Optional value | `Option<&T>` or `Option<T>` | Borrow when data exists in self |
| May or may not allocate | `Cow<'_, str>` | Borrow when input passes through unchanged |
| Error case | `Result<T, E>` | Always |

---

## Cow<'_, str> for Mixed Owned/Borrowed

`Cow` (clone on write) delays allocation until mutation is needed.
Use it when a function sometimes returns input unchanged and sometimes
produces a new value.

```rust
use std::borrow::Cow;

fn normalize_name(name: &str) -> Cow<'_, str> {
    if name.contains(char::is_uppercase) {
        // Must allocate -- transforming the string
        Cow::Owned(name.to_lowercase())
    } else {
        // No allocation -- returning a view of the input
        Cow::Borrowed(name)
    }
}
```

### When Cow Is Worth It

- The function returns the input unchanged in the common case
- Allocating a new `String` in the common case is a measured bottleneck
- The function is called in a hot loop with mostly-passing input

### When Cow Is Not Worth It

- The function always transforms the input -> just return `String`
- The function is called rarely -> the allocation is not a bottleneck
- The lifetime annotation adds complexity that exceeds the performance
  benefit

---

## Interior Mutability

Interior mutability lets you modify data behind a shared reference
(`&T`). Rust provides several mechanisms with different trade-offs.

### Cell<T> -- Single-Threaded, Copy Types

`Cell<T>` provides interior mutability for `Copy` types. No runtime
overhead beyond the mutability itself. Not thread-safe.

```rust
use std::cell::Cell;

struct Counter {
    count: Cell<u32>,
}

impl Counter {
    fn increment(&self) {
        self.count.set(self.count.get() + 1);
    }
}
```

Use when: single-threaded, the value is `Copy`, and you need to mutate
through `&self`.

### RefCell<T> -- Single-Threaded, Dynamic Borrow Checking

`RefCell<T>` moves borrow checking to runtime. Panics if you violate
the borrowing rules (multiple mutable borrows, or mutable + immutable).

```rust
use std::cell::RefCell;

struct Document {
    content: RefCell<String>,
}

impl Document {
    fn append(&self, text: &str) {
        self.content.borrow_mut().push_str(text);
    }

    fn snapshot(&self) -> String {
        self.content.borrow().clone()
    }
}
```

Use when: single-threaded, the value is not `Copy`, and you cannot
restructure to use `&mut self`.

**Danger:** `borrow()` and `borrow_mut()` panic at runtime if the
borrowing rules are violated. Never hold a `Ref` or `RefMut` across
an `.await` point or a call that may re-enter.

### Mutex<T> -- Multi-Threaded, Blocking

`Mutex<T>` provides mutual exclusion. The lock blocks the calling
thread until it can acquire exclusive access.

```rust
use std::sync::Mutex;

struct SharedState {
    data: Mutex<Vec<String>>,
}

impl SharedState {
    fn add(&self, item: String) {
        let mut guard = self.data.lock().unwrap(); // panics on poison
        guard.push(item);
        // guard dropped here -- lock released
    }
}
```

Use when: multi-threaded, writes are infrequent, and lock hold times
are short.

**Poison:** A mutex is "poisoned" if a thread panics while holding the
lock. `.lock().unwrap()` propagates the panic. Use
`.lock().unwrap_or_else(|e| e.into_inner())` to recover if the data
is still usable.

### RwLock<T> -- Multi-Threaded, Read-Heavy

`RwLock<T>` allows multiple concurrent readers OR one exclusive writer.

```rust
use std::sync::RwLock;

struct Cache {
    entries: RwLock<HashMap<String, String>>,
}

impl Cache {
    fn get(&self, key: &str) -> Option<String> {
        let guard = self.entries.read().unwrap();
        guard.get(key).cloned()
    }

    fn insert(&self, key: String, value: String) {
        let mut guard = self.entries.write().unwrap();
        guard.insert(key, value);
    }
}
```

Use when: multi-threaded, reads vastly outnumber writes, and you
need better read throughput than `Mutex` provides.

### Choosing the Right Mechanism

| Mechanism | Thread-safe | Runtime cost | Panic risk | Best for |
|-----------|------------|-------------|------------|----------|
| `Cell<T>` | No | None | None | Counters, flags (`Copy` types) |
| `RefCell<T>` | No | Borrow tracking | Borrow violation | Graph structures, caches |
| `Mutex<T>` | Yes | Lock contention | Poison | Write-heavy shared state |
| `RwLock<T>` | Yes | Lock contention | Poison | Read-heavy shared state |
| `Atomic*` | Yes | None (lock-free) | None | Counters, flags (primitives) |

---

## Arc vs Rc

### Rc<T> -- Single-Threaded Shared Ownership

`Rc` (reference counted) allows multiple owners of the same data on
a single thread. The data is dropped when the last `Rc` is dropped.

```rust
use std::rc::Rc;

let shared_config = Rc::new(Config::load());
let handle_a = Rc::clone(&shared_config);
let handle_b = Rc::clone(&shared_config);
// Both handles point to the same Config
```

`Rc` is not `Send` -- it cannot cross thread boundaries. Attempting
to send an `Rc` to another thread is a compile error.

### Arc<T> -- Multi-Threaded Shared Ownership

`Arc` (atomically reference counted) is the thread-safe version of
`Rc`. Atomic operations add a small cost per clone/drop.

```rust
use std::sync::Arc;

let shared_state = Arc::new(Mutex::new(AppState::new()));
let state_clone = Arc::clone(&shared_state);

tokio::spawn(async move {
    let mut guard = state_clone.lock().unwrap();
    guard.update();
});
```

### Decision Guide

| Question | Rc | Arc |
|----------|----|----|
| Crosses thread boundaries? | No | Yes |
| Used with `tokio::spawn`? | No | Yes |
| Used with `std::thread::spawn`? | No | Yes |
| Single-threaded application? | Yes | Unnecessary overhead |

Use `Arc<Mutex<T>>` for shared mutable state across threads.
Use `Arc<RwLock<T>>` when reads dominate writes.
Use `Rc<RefCell<T>>` for the single-threaded equivalent.

---

## Lifetime Elision Rules

Rust applies three rules to infer lifetimes. Understanding them
prevents unnecessary explicit annotations.

### Rule 1: Each Input Reference Gets Its Own Lifetime

```rust
fn foo(x: &str, y: &str) -> ...
// becomes
fn foo<'a, 'b>(x: &'a str, y: &'b str) -> ...
```

### Rule 2: Single Input Reference -> Output Gets Same Lifetime

```rust
fn first_word(s: &str) -> &str
// becomes
fn first_word<'a>(s: &'a str) -> &'a str
```

This is why most single-reference functions do not need explicit
lifetime annotations.

### Rule 3: &self or &mut self -> Output Gets Self's Lifetime

```rust
impl MyStruct {
    fn name(&self) -> &str
    // becomes
    fn name<'a>(&'a self) -> &'a str
}
```

Methods that return references tied to `self` never need annotations.

### When Annotations Are Actually Needed

Explicit lifetimes are needed when elision rules cannot determine
the output lifetime:

```rust
// Two input references, one output -- which input does the output
// borrow from? Compiler cannot decide automatically.
fn longest<'a>(x: &'a str, y: &'a str) -> &'a str {
    if x.len() >= y.len() { x } else { y }
}
```

```rust
// Struct that borrows external data
struct Parser<'input> {
    source: &'input str,
    position: usize,
}
```

---

## Common Ownership Patterns for Struct Fields

### Builder Pattern with Owned Fields

```rust
struct ServerConfig {
    host: String,     // owned -- config outlives builder
    port: u16,
    tls_cert: Option<PathBuf>,
}

impl ServerConfig {
    fn new(host: impl Into<String>, port: u16) -> Self {
        Self {
            host: host.into(), // accepts &str or String
            port,
            tls_cert: None,
        }
    }

    fn with_tls(mut self, cert: impl Into<PathBuf>) -> Self {
        self.tls_cert = Some(cert.into());
        self
    }
}
```

Use `impl Into<T>` for constructor parameters to accept both owned
and borrowed values without forcing callers to allocate.

### Newtype Pattern for Validated Data

```rust
struct EmailAddress(String);

impl EmailAddress {
    fn parse(raw: &str) -> Result<Self, ValidationError> {
        if raw.contains('@') && raw.contains('.') {
            Ok(Self(raw.to_string()))
        } else {
            Err(ValidationError::InvalidEmail(raw.to_string()))
        }
    }

    fn as_str(&self) -> &str {
        &self.0
    }
}
```

The newtype owns its data and provides only validated construction.
Downstream code accepts `&EmailAddress` instead of `&str`, making
invalid states unrepresentable.

### Enum with Mixed Ownership

```rust
enum Source {
    File(PathBuf),          // owns the path
    Inline(String),         // owns the content
    Stdin,                  // no data
}

impl Source {
    fn read(&self) -> Result<String, io::Error> {
        match self {
            Source::File(path) => std::fs::read_to_string(path),
            Source::Inline(content) => Ok(content.clone()),
            Source::Stdin => {
                let mut buf = String::new();
                std::io::stdin().read_to_string(&mut buf)?;
                Ok(buf)
            }
        }
    }
}
```

Enum variants own their data. Each variant can hold different types
without lifetime parameters.
