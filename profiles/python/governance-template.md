# Python Governance Template

> Seed template for /r:init. Provides Python best practices for
> merging with codebase scan results. Requires core profile.
> Assumes Python 3.9+ baseline. Project-specific version floors
> detected by /r:init override these defaults.

## Code Conventions

- Type hints on all public function signatures -- no bare `def f(x)`
- `typing.Protocol` over ABC for structural subtyping
- `dataclasses` or `attrs` for data containers, not raw dicts
- `pathlib.Path` over `os.path` for filesystem operations
- f-strings over `.format()` or `%` -- except logging (use lazy `%`)
- Context managers for resource lifecycle (files, connections, locks)
- `__all__` in public modules -- explicit public API surface
- Imports: stdlib -> third-party -> local, one per line, no wildcard

## Anti-Patterns

- Mutable default arguments -- `def f(items=[])` shares state across calls
- Bare `except` / `except Exception` without re-raise or explicit handling
- `isinstance()` chains -- use `singledispatch` or `Protocol`
- Global mutable state -- module-level dicts/lists mutated at runtime
- String concatenation in loops -- use `join()` or list accumulation
- `import *` -- pollutes namespace, breaks static analysis
- Catching and silencing `KeyboardInterrupt` or `SystemExit`
- Deep inheritance hierarchies -- prefer composition
- `os.system()` or `shell=True` in subprocess -- command injection vector
- `pickle`/`marshal` for untrusted data -- arbitrary code execution

## Error Handling

- Custom exceptions inheriting from domain-specific base, not `Exception`
- Never catch-and-ignore -- log or re-raise with context
- Use specific exceptions (`FileNotFoundError`, `ValueError`), not broad
- `contextlib.suppress()` over empty except for intentional ignoring
- Return `Optional[T]` or raise -- never return mixed types without hint
- `logger.exception()` in except blocks (captures traceback automatically)

## Security

- Deserialization: never `pickle.loads()` / `yaml.load()` / `eval()` on
  untrusted data -- use `yaml.safe_load()`, `json.loads()`
- SQL: parameterized queries always -- never f-string or `.format()` into
  query strings, even with ORM raw queries
- SSRF: validate URLs before `requests.get()` -- allowlist schemes and
  hosts, reject private IP ranges (127.0.0.0/8, 10.0.0.0/8, 169.254.0.0/16)
- Path traversal: resolve paths with `.resolve().relative_to()` before
  file operations, reject components containing `..`
- Import hijacking: never add user-controlled paths to `sys.path`
- Secrets: never hardcode, use environment or secrets manager,
  compare with `hmac.compare_digest()` not `==`
- Subprocess: never `shell=True` with user input, use list form

## Testing

- `pytest` as default framework (project-specific override via /r:init)
- Fixtures over `setUp`/`tearDown` -- explicit dependency injection
- `parametrize` for input variants, not copy-paste test functions
- Mock at boundaries (I/O, network, time), not internal functions
- `conftest.py` for shared fixtures -- scoped appropriately (function,
  module, session)
- Coverage: measure, don't chase -- 80% with meaningful tests over
  95% with tautological assertions
- `tmp_path` fixture over manual `tempfile` -- pytest handles cleanup
- No test logic in `__init__.py` -- `conftest.py` only

## Build & Packaging

- `pyproject.toml` as single source of truth (PEP 621)
- Virtual environment always -- never install into system Python
- Lock files (`pip-compile`, `poetry.lock`) committed for applications,
  not for libraries
- Entry points over scripts for CLI tools
- Version: single source in `pyproject.toml` or `__version__` -- not both
- Type stubs: ship `py.typed` marker + inline annotations over `.pyi`
