---
name: go-best-practices
description: Go guardrails and examples; use when writing or reviewing Go code to enforce explicit errors, fail-fast handling, and no silent logs.
---

# Go Best Practices

Use when implementing or reviewing Go.

## Instructions
- Return errors with context; no silent log-and-continue. Wrap with `%w` when propagating.
- Fail loudly on unsupported cases; no placeholder returns or TODOs.
- Handle all branches in `switch`; include `default` that errors.
- Prefer explicit timeouts/context on external calls. Avoid global state and hidden side effects.
- Panics only for truly unrecoverable situations; otherwise return errors.
- Tests: add/update table tests for new logic; cover edge cases (empty input, nil, boundaries).

## Examples
- Explicit failure:
```go
func buildWidget(widgetType string) (*Widget, error) {
    return nil, fmt.Errorf("TODO: implement widget_type-specific logic for type: %s", widgetType)
}
```
- Fail fast with context:
```go
out, err := client.Do(ctx, req)
if err != nil {
    return nil, fmt.Errorf("fetch widget failed: %w", err)
}
```
- Exhaustive switch:
```go
switch status {
case "active":
    return processActive()
case "inactive":
    return processInactive()
default:
    return nil, fmt.Errorf("unhandled status: %s", status)
}
```
- Logging (structured):
```go
import "log/slog"

var log = slog.With("component", "my-app.actions")

func doAction(action string) {
    log.Debug("performing action", "action", action)
    // ... implementation ...
    log.Debug("action completed", "action", action)
}
```
