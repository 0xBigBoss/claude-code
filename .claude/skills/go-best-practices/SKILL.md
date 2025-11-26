---
name: go-best-practices
description: Provides Go code quality patterns for error wrapping with fmt.Errorf, exhaustive switch statements, context.Context usage, and slog structured logging. Activates when editing .go files, working with Go modules (go.mod), or when the user mentions Go, Golang, error handling, or Go packages.
---

# Go Best Practices

## Instructions

- Return errors with context using `fmt.Errorf` and `%w` for wrapping. This preserves the error chain for debugging.
- Every function returns a value or an error; unimplemented paths return descriptive errors. Explicit failures are debuggable.
- Handle all branches in `switch` statements; include a `default` case that returns an error. Exhaustive handling prevents silent bugs.
- Pass `context.Context` to external calls with explicit timeouts. Runaway requests cause cascading failures.
- Reserve `panic` for truly unrecoverable situations; prefer returning errors. Panics crash the program.
- Add or update table-driven tests for new logic; cover edge cases (empty input, nil, boundaries).

## Examples

Explicit failure for unimplemented logic:
```go
func buildWidget(widgetType string) (*Widget, error) {
    return nil, fmt.Errorf("buildWidget not implemented for type: %s", widgetType)
}
```

Wrap errors with context to preserve the chain:
```go
out, err := client.Do(ctx, req)
if err != nil {
    return nil, fmt.Errorf("fetch widget failed: %w", err)
}
return out, nil
```

Exhaustive switch with default error:
```go
func processStatus(status string) (string, error) {
    switch status {
    case "active":
        return "processing", nil
    case "inactive":
        return "skipped", nil
    default:
        return "", fmt.Errorf("unhandled status: %s", status)
    }
}
```

Structured logging with slog:
```go
import "log/slog"

var log = slog.With("component", "widgets")

func createWidget(name string) (*Widget, error) {
    log.Debug("creating widget", "name", name)
    widget := &Widget{Name: name}
    log.Debug("created widget", "id", widget.ID)
    return widget, nil
}
```
