# Python Anti-Patterns Reference

> Deep reference for common Python anti-patterns. Each section shows
> the broken pattern, explains why it fails, and provides the correct
> alternative. Companion to the Python governance template.

---

## Mutability Traps

### Mutable Default Arguments

Default argument values are evaluated once at function definition time,
not per call. Mutable defaults are shared across all invocations.

Bad:
```python
def append_item(item, items=[]):
    items.append(item)
    return items

append_item("a")  # ['a']
append_item("b")  # ['a', 'b'] -- previous call's mutation persists
```

The default list object is created once when `def` executes. Every call
that omits `items` shares the same list. This is the single most common
source of mysterious state-sharing bugs in Python.

Good:
```python
def append_item(item, items=None):
    if items is None:
        items = []
    items.append(item)
    return items
```

Use `None` as sentinel and create a new mutable object inside the
function body. This guarantees each call starts with a fresh container.

### Shared Class Attributes

Mutable class-level attributes are shared across all instances.

Bad:
```python
class UserGroup:
    members = []  # shared across ALL instances

    def add(self, name):
        self.members.append(name)

a = UserGroup()
b = UserGroup()
a.add("alice")
print(b.members)  # ['alice'] -- b sees a's mutation
```

Good:
```python
class UserGroup:
    def __init__(self):
        self.members = []  # per-instance

    def add(self, name):
        self.members.append(name)
```

Initialize mutable state in `__init__`, never as class attributes.

### Shallow vs Deep Copy

`copy()` and slice copies only duplicate the outer container. Nested
mutable objects are still shared references.

Bad:
```python
original = [[1, 2], [3, 4]]
shallow = original.copy()
shallow[0].append(5)
print(original)  # [[1, 2, 5], [3, 4]] -- inner list was shared
```

Good:
```python
import copy

original = [[1, 2], [3, 4]]
deep = copy.deepcopy(original)
deep[0].append(5)
print(original)  # [[1, 2], [3, 4]] -- unaffected
```

Use `copy.deepcopy()` when containers hold mutable nested objects.
For flat containers of immutables, `copy()` or slice is sufficient.

---

## Type System Misuse

### Bare Except Clauses

Bare `except` catches everything including `KeyboardInterrupt` and
`SystemExit`, preventing clean shutdown and signal handling.

Bad:
```python
try:
    process_data()
except:
    print("something went wrong")  # swallows Ctrl-C, sys.exit()
```

Good:
```python
try:
    process_data()
except (ValueError, IOError) as exc:
    logger.exception("Processing failed: %s", exc)
    raise
```

Catch specific exceptions. Use `logger.exception()` to capture the
full traceback. Re-raise or handle explicitly -- never silently ignore.

### isinstance Chains vs Protocol

Long `isinstance` chains are fragile, closed to extension, and violate
the open-closed principle.

Bad:
```python
def serialize(obj):
    if isinstance(obj, User):
        return {"name": obj.name}
    elif isinstance(obj, Product):
        return {"sku": obj.sku}
    elif isinstance(obj, Order):
        return {"id": obj.order_id}
    else:
        raise TypeError(f"Cannot serialize {type(obj)}")
```

Good:
```python
from typing import Protocol, Any

class Serializable(Protocol):
    def to_dict(self) -> dict[str, Any]: ...

def serialize(obj: Serializable) -> dict[str, Any]:
    return obj.to_dict()
```

Use `Protocol` for structural subtyping -- any object with a matching
`to_dict` method works, no base class required. Alternatively, use
`functools.singledispatch` for type-based dispatch without chains.

### Mixed Return Types

Returning different types without type hints causes runtime surprises
and defeats static analysis.

Bad:
```python
def find_user(user_id):
    user = db.query(user_id)
    if user:
        return user
    return -1  # sentinel value mixed with domain type
```

Good:
```python
from typing import Optional

def find_user(user_id: int) -> Optional[User]:
    return db.query(user_id)  # returns User or None
```

Return `Optional[T]` or raise an exception. Never mix domain objects
with sentinel values (-1, False, empty string) as return types.

---

## Import Hygiene

### Circular Imports

Circular imports cause `ImportError` or `AttributeError` at runtime
when module A imports from module B which imports from module A.

Bad:
```python
# models.py
from .services import validate_user

class User:
    def save(self):
        validate_user(self)

# services.py
from .models import User  # circular -- models imports services first

def validate_user(user: User):
    ...
```

Good:
```python
# services.py
from __future__ import annotations
from typing import TYPE_CHECKING

if TYPE_CHECKING:
    from .models import User

def validate_user(user: "User") -> None:
    ...
```

Use `TYPE_CHECKING` for import-time-only references. Move runtime
dependencies to function-level imports if necessary. Restructure
modules to break dependency cycles.

### Wildcard Imports

`import *` pollutes the namespace, breaks static analysis, and makes
it impossible to trace where names originate.

Bad:
```python
from os.path import *
from mylib.utils import *

# Which module defined 'join'? os.path.join or mylib.utils.join?
result = join(a, b)
```

Good:
```python
from os.path import join as path_join
from mylib.utils import join as text_join
```

Import specific names. Use `__all__` in your own modules to control
what `import *` would export (but consumers should still avoid it).

### Import Hijacking

Adding user-controlled paths to `sys.path` enables arbitrary code
execution via malicious modules.

Bad:
```python
import sys
sys.path.insert(0, user_provided_path)
import plugin  # loads attacker-controlled plugin.py
```

Good:
```python
import importlib.util

spec = importlib.util.spec_from_file_location(
    "plugin", allowed_plugin_dir / "plugin.py"
)
if spec and spec.loader:
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
```

Use `importlib` with explicit, validated file paths. Never allow
user input to influence `sys.path` or `__import__` arguments.

---

## Async/Await Pitfalls

### Blocking Calls in Async

Synchronous I/O in async functions blocks the entire event loop,
destroying concurrency for all tasks.

Bad:
```python
import asyncio
import requests

async def fetch_data(url: str) -> str:
    response = requests.get(url)  # blocks the event loop
    return response.text
```

Good:
```python
import asyncio
import aiohttp

async def fetch_data(url: str) -> str:
    async with aiohttp.ClientSession() as session:
        async with session.get(url) as response:
            return await response.text()
```

Use async-native libraries (`aiohttp`, `asyncpg`, `aiofiles`). For
unavoidable sync calls, use `asyncio.to_thread()` (3.9+) to run them
in a thread pool without blocking the loop.

### Missing Await

Forgetting `await` on a coroutine returns the coroutine object instead
of executing it. No error is raised -- just silent wrong behavior.

Bad:
```python
async def process():
    result = fetch_data("https://example.com")  # missing await
    print(result)  # <coroutine object fetch_data at 0x...>
```

Good:
```python
async def process():
    result = await fetch_data("https://example.com")
    print(result)  # actual response text
```

Python 3.9+ emits `RuntimeWarning: coroutine was never awaited` if
the coroutine is garbage collected. Enable asyncio debug mode during
development to catch these early: `asyncio.run(main(), debug=True)`.

### Task Cancellation

`asyncio.gather()` with `return_exceptions=False` (default) cancels
remaining tasks on first exception, but does not await their cleanup.

Bad:
```python
results = await asyncio.gather(task_a(), task_b(), task_c())
# if task_a raises, task_b and task_c are cancelled abruptly
```

Good:
```python
results = await asyncio.gather(
    task_a(), task_b(), task_c(),
    return_exceptions=True
)
for result in results:
    if isinstance(result, Exception):
        logger.error("Task failed: %s", result)
```

Use `return_exceptions=True` when you want all tasks to complete
regardless of individual failures. For structured concurrency with
proper cleanup, use `asyncio.TaskGroup` (3.11+).

---

## Common Library Pitfalls

### requests Session Reuse

Creating a new `Session` per request wastes TCP connections and
disables connection pooling.

Bad:
```python
for url in urls:
    response = requests.get(url)  # new connection each time
```

Good:
```python
with requests.Session() as session:
    session.headers.update({"Authorization": f"Bearer {token}"})
    for url in urls:
        response = session.get(url)  # reuses TCP connections
```

A `Session` maintains a connection pool, persists headers and cookies,
and significantly reduces latency for repeated requests to the same
host. Always use a session for multiple requests.

### SQLAlchemy Session Lifecycle

Accessing attributes on detached objects (after session close) raises
`DetachedInstanceError`. Lazy-loaded relationships are the usual cause.

Bad:
```python
def get_user(user_id: int) -> User:
    with Session() as session:
        user = session.get(User, user_id)
    return user  # detached -- accessing user.orders raises

user = get_user(1)
print(user.orders)  # DetachedInstanceError
```

Good:
```python
def get_user_with_orders(user_id: int) -> User:
    with Session() as session:
        user = session.get(User, user_id)
        if user:
            _ = user.orders  # force load while attached
    return user
```

Eager-load relationships before detaching, or keep the session open
for the duration of attribute access. Use `selectinload()` or
`joinedload()` in queries to control loading strategy explicitly.

### logging.basicConfig Only Works Once

`logging.basicConfig()` is a no-op if the root logger already has
handlers. In applications with multiple initialization paths, only
the first call takes effect.

Bad:
```python
# module_a.py
import logging
logging.basicConfig(level=logging.DEBUG)

# module_b.py (imported after module_a)
import logging
logging.basicConfig(level=logging.WARNING)  # silently ignored
```

Good:
```python
# logging_config.py -- single configuration point
import logging

def setup_logging(level: int = logging.INFO) -> None:
    root = logging.getLogger()
    root.setLevel(level)
    if not root.handlers:
        handler = logging.StreamHandler()
        handler.setFormatter(
            logging.Formatter("%(asctime)s %(name)s %(levelname)s %(message)s")
        )
        root.addHandler(handler)
```

Configure logging once at application entry point. Use
`logging.getLogger(__name__)` in modules -- never call `basicConfig`
outside the main entry point.
