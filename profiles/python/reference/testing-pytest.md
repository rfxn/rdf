# pytest Testing Reference

> Deep reference for pytest conventions and patterns. Covers fixtures,
> parametrize, conftest architecture, mocking strategy, and coverage
> discipline. Companion to the Python governance template.

---

## Fixture Patterns

Fixtures provide explicit dependency injection for tests. Scope controls
how often the fixture is created: `function` (default, per-test),
`module` (once per file), `session` (once per run).

```python
import pytest
from pathlib import Path

@pytest.fixture
def sample_config(tmp_path: Path) -> Path:
    """Per-test fixture -- fresh config file each time."""
    config = tmp_path / "config.toml"
    config.write_text('[server]\nhost = "localhost"\nport = 8080\n')
    return config

@pytest.fixture(scope="module")
def db_connection():
    """Module-scoped -- one connection shared across all tests in file."""
    conn = create_test_database()
    yield conn
    conn.close()  # cleanup runs after all tests in the module
```

Yield fixtures separate setup from teardown. Code after `yield` runs
during cleanup, even if the test fails. Prefer yield over `addfinalizer`.

### Factory Fixtures

When tests need multiple instances with varying parameters, use a
factory fixture instead of multiple separate fixtures.

```python
@pytest.fixture
def make_user():
    """Factory fixture -- caller controls parameters."""
    created = []

    def _make(name: str = "test", role: str = "viewer") -> User:
        user = User(name=name, role=role)
        created.append(user)
        return user

    yield _make
    for user in created:
        user.delete()  # cleanup all created users

def test_admin_access(make_user):
    admin = make_user(name="alice", role="admin")
    viewer = make_user(name="bob", role="viewer")
    assert admin.can_access("/admin")
    assert not viewer.can_access("/admin")
```

### Autouse Fixtures

Autouse fixtures run for every test in their scope without being
explicitly requested. Use sparingly -- implicit behavior is harder
to debug.

```python
@pytest.fixture(autouse=True)
def reset_environment(monkeypatch):
    """Clear environment for every test -- no leakage between tests."""
    monkeypatch.delenv("API_KEY", raising=False)
    monkeypatch.delenv("DATABASE_URL", raising=False)
```

### The request Object

The `request` fixture provides test metadata -- useful for fixtures
that need to know their scope or the requesting test.

```python
@pytest.fixture
def temp_dir(request, tmp_path: Path) -> Path:
    """Named temp directory using the test function name."""
    test_dir = tmp_path / request.node.name
    test_dir.mkdir()
    return test_dir
```

---

## Parametrize Patterns

`@pytest.mark.parametrize` runs a test with multiple input sets,
generating a separate test case for each combination.

```python
@pytest.mark.parametrize("input_val,expected", [
    ("hello", "HELLO"),
    ("world", "WORLD"),
    ("", ""),
    ("123", "123"),
])
def test_uppercase(input_val: str, expected: str):
    assert input_val.upper() == expected
```

### Readable IDs

Use `ids` to label test cases in output instead of relying on
auto-generated parameter strings.

```python
@pytest.mark.parametrize("path,status", [
    ("/", 200),
    ("/health", 200),
    ("/missing", 404),
    ("/admin", 403),
], ids=["root", "health-check", "not-found", "forbidden"])
def test_route_status(client, path: str, status: int):
    response = client.get(path)
    assert response.status_code == status
```

### Multiple Parametrize Decorators

Stacking decorators produces the cartesian product of all parameters.

```python
@pytest.mark.parametrize("method", ["GET", "POST"])
@pytest.mark.parametrize("path", ["/api/v1", "/api/v2"])
def test_cors_headers(client, method: str, path: str):
    # runs 4 times: GET+v1, GET+v2, POST+v1, POST+v2
    response = client.open(path, method=method)
    assert "Access-Control-Allow-Origin" in response.headers
```

### Indirect Fixtures

Pass parametrize values through a fixture for transformation.

```python
@pytest.fixture
def db_engine(request):
    """Create engine from parametrized connection string."""
    return create_engine(request.param)

@pytest.mark.parametrize("db_engine", [
    "sqlite:///:memory:",
    "postgresql://localhost/test",
], indirect=True)
def test_migration(db_engine):
    run_migrations(db_engine)
    assert db_engine.table_names() == ["users", "orders"]
```

---

## Conftest Architecture

`conftest.py` files provide fixtures and hooks to tests in their
directory and all subdirectories. pytest loads them automatically --
no import required.

```
tests/
    conftest.py          # root -- session fixtures, shared helpers
    unit/
        conftest.py      # unit-specific fixtures
        test_models.py
    integration/
        conftest.py      # integration-specific (db, http client)
        test_api.py
```

Root conftest holds session-scoped fixtures (database setup, app
factory). Package conftest holds fixtures specific to that test
category. Do not put test functions in conftest -- only fixtures,
hooks, and helpers.

### Plugin Loading

conftest.py is also where pytest plugins are configured:

```python
# tests/conftest.py

def pytest_collection_modifyitems(items):
    """Automatically mark tests in integration/ as slow."""
    for item in items:
        if "integration" in str(item.fspath):
            item.add_marker(pytest.mark.slow)
```

---

## Mocking Strategy

Mock at system boundaries (I/O, network, clock, random), not internal
functions. Over-mocking creates tests that pass regardless of
implementation correctness.

### monkeypatch vs unittest.mock

`monkeypatch` is pytest-native and scoped to the test automatically.
`unittest.mock.patch` requires explicit scope management but offers
richer assertion capabilities.

```python
def test_read_config(monkeypatch, tmp_path):
    """monkeypatch -- simple attribute/env replacement."""
    config_file = tmp_path / "config.json"
    config_file.write_text('{"debug": true}')
    monkeypatch.setenv("CONFIG_PATH", str(config_file))

    config = load_config()
    assert config["debug"] is True

from unittest.mock import patch, MagicMock

def test_api_call():
    """unittest.mock -- when you need call assertions."""
    mock_response = MagicMock()
    mock_response.status_code = 200
    mock_response.json.return_value = {"id": 1}

    with patch("myapp.client.requests.get", return_value=mock_response) as mock_get:
        result = fetch_user(1)
        mock_get.assert_called_once_with(
            "https://api.example.com/users/1",
            timeout=30,
        )
    assert result == {"id": 1}
```

### Patch Scope

`patch` targets the name where it is looked up, not where it is
defined. This is the most common mock mistake.

```python
# myapp/service.py
from myapp.client import fetch_data  # imported into service namespace

# Bad: patches the original, but service.py already imported the name
with patch("myapp.client.fetch_data"):
    service.process()  # uses the original, unpatched function

# Good: patch where it is looked up
with patch("myapp.service.fetch_data"):
    service.process()  # uses the mock
```

---

## Coverage

Measure coverage to find untested paths, not as a goal to maximize.
High coverage with tautological tests provides false confidence.

### Meaningful vs Tautological Tests

Bad:
```python
def test_init():
    obj = MyClass()
    assert obj is not None  # tautological -- __init__ always returns
```

Good:
```python
def test_init_sets_defaults():
    obj = MyClass()
    assert obj.status == "pending"
    assert obj.retries == 0
    assert obj.created_at is not None
```

Assert observable behavior and state, not mere existence.

### Branch Coverage

Line coverage misses untested branches. Enable branch coverage to
catch partially-tested conditionals.

```ini
# pyproject.toml
[tool.coverage.run]
branch = true

[tool.coverage.report]
exclude_lines = [
    "pragma: no cover",
    "if TYPE_CHECKING:",
    "if __name__ == .__main__.",
]
```

### pragma: no cover Discipline

Use `# pragma: no cover` only for code that genuinely cannot be tested
in the current environment -- never to inflate coverage numbers.

Valid uses:
```python
if sys.platform == "win32":  # pragma: no cover
    # platform-specific code untestable in CI
    ...

if TYPE_CHECKING:  # pragma: no cover
    # type-only imports, never executed at runtime
    from .models import User
```

Invalid use -- hiding testable code to reach a coverage target:
```python
def handle_error(exc: Exception) -> None:  # pragma: no cover  # BAD
    logger.error("Failed: %s", exc)
    sys.exit(1)
```
