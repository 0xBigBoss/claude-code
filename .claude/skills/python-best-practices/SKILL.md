---
name: python-best-practices
description: Python code quality patterns for exception propagation with 'from err', match statement exhaustiveness, pathlib file handling, and debug logging. Activate when editing .py files, working with Python projects (pyproject.toml, requirements.txt), or when the user mentions Python, exceptions, or Python modules.
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
