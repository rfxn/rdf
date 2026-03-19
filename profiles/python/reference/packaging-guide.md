# Python Packaging Reference

> Reference for Python packaging, dependency management, and distribution.
> Covers pyproject.toml structure, dependency workflows, versioning
> strategy, and distribution formats. Companion to the Python governance
> template.

---

## pyproject.toml Structure

PEP 621 defines `pyproject.toml` as the single source of truth for
project metadata, build configuration, and tool settings.

```toml
[build-system]
requires = ["setuptools>=68.0", "setuptools-scm>=8.0"]
build-backend = "setuptools.backends._legacy:_Backend"

[project]
name = "myproject"
version = "1.2.0"
description = "Brief one-line description of what it does"
readme = "README.md"
license = {text = "MIT"}
requires-python = ">=3.9"
authors = [{name = "Name", email = "name@example.com"}]
classifiers = [
    "Programming Language :: Python :: 3",
    "License :: OSI Approved :: MIT License",
    "Operating System :: OS Independent",
]
dependencies = [
    "requests>=2.28,<3",
    "pydantic>=2.0,<3",
]

[project.optional-dependencies]
dev = [
    "pytest>=7.0",
    "pytest-cov>=4.0",
    "mypy>=1.0",
    "ruff>=0.1",
]
docs = [
    "sphinx>=7.0",
    "sphinx-rtd-theme>=2.0",
]

[project.scripts]
myproject = "myproject.cli:main"

[project.entry-points."myproject.plugins"]
csv = "myproject.plugins.csv:CsvPlugin"
json = "myproject.plugins.json:JsonPlugin"
```

`[project.scripts]` generates console entry points -- preferred over
`scripts` or `bin/` directories. Entry points are the standard way
to expose CLI tools from Python packages.

---

## Dependency Management

### Applications vs Libraries

Applications pin exact versions (lock files committed). Libraries
specify version ranges (no lock files committed -- downstream resolves).

| Aspect | Application | Library |
|--------|-------------|---------|
| Lock file | Committed (`requirements.txt`, `poetry.lock`) | Not committed |
| Version specifiers | `==` or exact pins | `>=`, `~=`, `<` ranges |
| Transitive deps | Fully resolved | Consumer resolves |
| Reproducibility | Exact environment | Compatible environment |

### pip-compile Workflow

`pip-tools` generates deterministic lock files from abstract requirements.

```bash
# requirements.in -- abstract requirements
requests>=2.28
pydantic>=2.0

# Generate lock file with hashes
pip-compile --generate-hashes requirements.in -o requirements.txt

# Install from lock file
pip install -r requirements.txt

# Upgrade a single package
pip-compile --upgrade-package requests requirements.in
```

### Version Specifiers

| Specifier | Meaning | Use when |
|-----------|---------|----------|
| `>=2.0,<3` | Compatible range | Library -- allow minor updates |
| `~=2.0` | Compatible release | Equivalent to `>=2.0,<3` |
| `==2.28.1` | Exact pin | Application lock file |
| `>=2.0` | Minimum only | Avoid -- no upper bound is risky |

Avoid unbounded `>=` in libraries -- a major version bump can break
your code. Always include an upper bound on the major version.

---

## Version Strategy

### Single Source of Truth

Version must be defined in exactly one place. Duplication causes
drift -- `pyproject.toml` says 1.2.0, `__init__.py` says 1.1.0.

Option A -- static in pyproject.toml (preferred for most projects):
```toml
[project]
version = "1.2.0"
```

Option B -- dynamic via setuptools-scm (derived from git tags):
```toml
[project]
dynamic = ["version"]

[tool.setuptools_scm]
```

Option C -- `__version__` with importlib.metadata:
```python
# myproject/__init__.py
from importlib.metadata import version

__version__ = version("myproject")
```

Never maintain version strings in multiple files. If you use
`__version__`, derive it from the installed package metadata.

### Calver vs Semver

| Scheme | Format | Best for |
|--------|--------|----------|
| Semver | MAJOR.MINOR.PATCH | Libraries with public API contracts |
| Calver | YYYY.MM.DD or YYYY.N | Applications, data pipelines, services |

Semver communicates breaking changes via MAJOR bumps. Calver
communicates release cadence. Most libraries should use semver.

---

## Distribution

### Wheel vs Source Distribution

Wheels (`.whl`) are pre-built, install without compilation, and are
the preferred distribution format. Source distributions (`sdist`) are
fallback for platforms without a matching wheel.

```bash
# Build both
python -m build

# Output:
#   dist/myproject-1.2.0-py3-none-any.whl   (wheel)
#   dist/myproject-1.2.0.tar.gz              (sdist)
```

Pure-Python packages produce universal wheels (`py3-none-any`).
Packages with C extensions produce platform-specific wheels.

### py.typed Marker

Ship a `py.typed` marker file so type checkers recognize your package
as typed. This enables consumers to benefit from your inline type
annotations.

```
myproject/
    __init__.py
    py.typed          # empty file -- signals PEP 561 compliance
    models.py
    utils.py
```

Inline annotations in `.py` files are preferred over separate `.pyi`
stub files. Stubs are only necessary for C extensions or third-party
packages you do not control.

### Entry Points for CLI

Entry points are the standard mechanism for CLI tools. They generate
wrapper scripts in the virtualenv's `bin/` directory.

```toml
[project.scripts]
myproject = "myproject.cli:main"
```

```python
# myproject/cli.py
import sys

def main() -> int:
    """Entry point -- returns exit code."""
    # parse args, dispatch commands
    return 0

if __name__ == "__main__":
    sys.exit(main())
```

The `if __name__ == "__main__"` guard allows running the module
directly (`python -m myproject.cli`) as well as via the entry point.

### PyPI Classifiers

Classifiers help users find your package on PyPI. Include at minimum:
development status, license, Python version, and operating system.

```toml
classifiers = [
    "Development Status :: 4 - Beta",
    "License :: OSI Approved :: MIT License",
    "Programming Language :: Python :: 3",
    "Programming Language :: Python :: 3.9",
    "Programming Language :: Python :: 3.10",
    "Programming Language :: Python :: 3.11",
    "Programming Language :: Python :: 3.12",
    "Operating System :: OS Independent",
    "Typing :: Typed",
]
```
