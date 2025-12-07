---
name: go-best-practices
description: Provides Go code quality patterns for error wrapping with fmt.Errorf, exhaustive switch statements, context.Context usage, and slog structured logging. Must use when reading or writing Go files.
---

# Go Best Practices

## Module Structure

Prefer smaller files within packages: one type or concern per file. Split when a file handles multiple unrelated types or exceeds ~300 lines. Keep tests in `_test.go` files alongside implementation. Package boundaries define the API; internal organization is flexible.

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

## Configuration

- Load config from environment variables at startup; validate required values before use. Missing config should cause immediate exit.
- Define a Config struct as single source of truth; avoid `os.Getenv` scattered throughout code.
- Use sensible defaults for development; require explicit values for production secrets.

### Examples

Typed config struct:
```go
type Config struct {
    Port        int
    DatabaseURL string
    APIKey      string
    Env         string
}

func LoadConfig() (*Config, error) {
    dbURL := os.Getenv("DATABASE_URL")
    if dbURL == "" {
        return nil, fmt.Errorf("DATABASE_URL is required")
    }
    apiKey := os.Getenv("API_KEY")
    if apiKey == "" {
        return nil, fmt.Errorf("API_KEY is required")
    }
    port := 3000
    if p := os.Getenv("PORT"); p != "" {
        var err error
        port, err = strconv.Atoi(p)
        if err != nil {
            return nil, fmt.Errorf("invalid PORT: %w", err)
        }
    }
    return &Config{
        Port:        port,
        DatabaseURL: dbURL,
        APIKey:      apiKey,
        Env:         getEnvOrDefault("ENV", "development"),
    }, nil
}
```
