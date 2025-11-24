---
name: python-best-practices
description: Python guardrails and examples; use when writing or reviewing Python code for fail-fast, explicit errors/logging, edge cases.
---

# Python Best Practices

Use when implementing or reviewing Python code.

## Instructions
- Fail loudly on unsupported cases; raise descriptive exceptions. No TODOs or placeholder returns.
- Do not swallow exceptions; let them propagate or wrap with context. No log-and-continue fallbacks.
- Handle edge cases: empty inputs, `None`, boundary values; include default branches.
- Use context managers for I/O; prefer `pathlib` and explicit encodings.
- Keep functions total: every branch returns or raises. Avoid silent mutation.
- Tests: add/adjust unit tests when touching logic; prefer minimal repros for failures.

## Examples
- Explicit failure:
```python
def build_widget(widget_type):
    raise NotImplementedError(f"TODO: Implement widget_type-specific logic for type: {widget_type}")
```
- Propagate with context:
```python
try:
    data = json.loads(raw)
except json.JSONDecodeError as err:
    raise ValueError(f"invalid JSON payload: {err}") from err
```
- Logging (debug-level tracing):
```python
import logging

logger = logging.getLogger("my-app.actions")

def do_action(action):
    logger.debug("Performing action: %s", action)
    # ... implementation ...
    logger.debug("Action completed: %s", action)
```
