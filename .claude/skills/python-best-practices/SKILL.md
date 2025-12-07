---
name: python-best-practices
description: Provides Python code quality patterns for exception propagation with 'from err', match statement exhaustiveness, pathlib file handling, and debug logging. Must use when reading or writing Python files.
---

# Python Best Practices

## Instructions

- Raise descriptive exceptions for unsupported cases; every code path returns a value or raises. This makes failures debuggable and prevents silent corruption.
- Propagate exceptions with context using `from err`; catching requires re-raising or returning a meaningful result. Swallowed exceptions hide root causes.
- Handle edge cases explicitly: empty inputs, `None`, boundary values. Include `else` clauses in conditionals where appropriate.
- Use context managers for I/O; prefer `pathlib` and explicit encodings. Resource leaks cause production issues.
- Add or adjust unit tests when touching logic; prefer minimal repros that isolate the failure.

## Examples

Explicit failure for unimplemented logic:
```python
def build_widget(widget_type: str) -> Widget:
    raise NotImplementedError(f"build_widget not implemented for type: {widget_type}")
```

Propagate with context to preserve the original traceback:
```python
try:
    data = json.loads(raw)
except json.JSONDecodeError as err:
    raise ValueError(f"invalid JSON payload: {err}") from err
```

Exhaustive match with explicit default:
```python
def process_status(status: str) -> str:
    match status:
        case "active":
            return "processing"
        case "inactive":
            return "skipped"
        case _:
            raise ValueError(f"unhandled status: {status}")
```

Debug-level tracing with namespaced logger:
```python
import logging

logger = logging.getLogger("myapp.widgets")

def create_widget(name: str) -> Widget:
    logger.debug("creating widget: %s", name)
    widget = Widget(name=name)
    logger.debug("created widget id=%s", widget.id)
    return widget
```

## Configuration

- Load config from environment variables at startup; validate required values before use. Missing config should fail immediately.
- Define a config dataclass or Pydantic model as single source of truth; avoid `os.getenv` scattered throughout code.
- Use sensible defaults for development; require explicit values for production secrets.

### Examples

Typed config with dataclass:
```python
import os
from dataclasses import dataclass

@dataclass(frozen=True)
class Config:
    port: int = 3000
    database_url: str = ""
    api_key: str = ""
    env: str = "development"

    @classmethod
    def from_env(cls) -> "Config":
        database_url = os.environ.get("DATABASE_URL", "")
        if not database_url:
            raise ValueError("DATABASE_URL is required")
        return cls(
            port=int(os.environ.get("PORT", "3000")),
            database_url=database_url,
            api_key=os.environ["API_KEY"],  # required, will raise if missing
            env=os.environ.get("ENV", "development"),
        )

config = Config.from_env()
```
