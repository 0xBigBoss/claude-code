---
name: zmx
description: Patterns for running long-lived processes in zmx. Use when starting dev servers, watchers, tilt, or any process expected to outlive the conversation.
---

# zmx Process Management

## Session Rules

These are **hard requirements**, not suggestions:

- **MUST** check `zmx list --short` before creating sessions to avoid duplicates
- **MUST** derive session name from `git rev-parse --show-toplevel`, never hardcode
- **MUST** use `zmx run` to send commands without attaching (agent-friendly)
- **MUST** use separate sessions with a common prefix for multiple processes in one project
- **NEVER** attach to sessions from agent context — use `zmx run` and `zmx history` only

One project = one session prefix. Multiple processes = multiple sessions sharing the prefix.

## Session Naming Convention

Derive session prefix from the project:

```bash
PROJECT=$(basename "$(git rev-parse --show-toplevel 2>/dev/null)" || basename "$PWD")
```

For multiple processes in one project, use prefixed session names:
- `myapp-server`
- `myapp-tests`
- `myapp-tilt`

## Starting Processes

### Single Process

```bash
PROJECT=$(basename "$(git rev-parse --show-toplevel 2>/dev/null)" || basename "$PWD")
SESSION="${PROJECT}-main"

if zmx list --short 2>/dev/null | grep -q "^${SESSION}$"; then
  echo "Session $SESSION already exists"
else
  zmx run "$SESSION" '<command>'
  echo "Started $SESSION"
fi
```

### Multiple Processes

```bash
PROJECT=$(basename "$(git rev-parse --show-toplevel 2>/dev/null)" || basename "$PWD")

# Start each process in its own session (idempotent)
for name_cmd in "server:npm run dev" "tests:npm run test:watch" "logs:tail -f logs/app.log"; do
  name="${name_cmd%%:*}"
  cmd="${name_cmd#*:}"
  SESSION="${PROJECT}-${name}"
  if ! zmx list --short 2>/dev/null | grep -q "^${SESSION}$"; then
    zmx run "$SESSION" "$cmd"
    echo "Started $SESSION"
  else
    echo "Session $SESSION already exists"
  fi
done
```

### Sending Commands to an Existing Session

```bash
# Run a command in a session (creates session if needed)
zmx run "$SESSION" 'cat README.md'

# Pipe command via stdin
echo "ls -lah" | zmx r "$SESSION"
```

## Monitoring Output

```bash
PROJECT=$(basename "$(git rev-parse --show-toplevel 2>/dev/null)" || basename "$PWD")

# Full scrollback from a session
zmx history "${PROJECT}-server"

# Last 50 lines
zmx history "${PROJECT}-server" | tail -50

# Check for errors
zmx history "${PROJECT}-server" | rg -i "error|fail|exception"

# Check for ready indicators
zmx history "${PROJECT}-server" | rg -i "listening|ready|started"
```

## Waiting for Completion

```bash
# Block until a session's task finishes
zmx wait "${PROJECT}-tests"

# Wait for multiple sessions
zmx wait "${PROJECT}-build" "${PROJECT}-lint"
```

## Lifecycle Management

```bash
PROJECT=$(basename "$(git rev-parse --show-toplevel 2>/dev/null)" || basename "$PWD")

# List all sessions
zmx list

# List session names only
zmx list --short

# Kill a specific session
zmx kill "${PROJECT}-server"

# Kill all project sessions
zmx list --short 2>/dev/null | grep "^${PROJECT}-" | while read -r s; do
  zmx kill "$s"
done
```

## Isolation Rules

- **Never** kill sessions not matching current project prefix
- **Always** derive session name from git root or pwd
- **Always** verify session name before kill operations
- Other Claude Code instances may have their own sessions running

## When to Use zmx

| Scenario | Use zmx? |
|----------|----------|
| `tilt up` | Yes, always |
| Dev server (`npm run dev`, `rails s`) | Yes |
| File watcher (`npm run watch`) | Yes |
| Test watcher (`npm run test:watch`) | Yes |
| Database server | Yes |
| One-shot build (`npm run build`) | No |
| Quick command (<10s) | No |
| Need stdout directly in conversation | No |

## Checking Session Status

```bash
PROJECT=$(basename "$(git rev-parse --show-toplevel 2>/dev/null)" || basename "$PWD")

# Check session exists
zmx list --short 2>/dev/null | grep -q "^${PROJECT}-tilt$" && echo "session exists" || echo "no session"

# List all project sessions
zmx list --short 2>/dev/null | grep "^${PROJECT}-"
```

## Common Patterns

### Start dev server if not running

```bash
PROJECT=$(basename "$(git rev-parse --show-toplevel 2>/dev/null)" || basename "$PWD")
SESSION="${PROJECT}-server"

if zmx list --short 2>/dev/null | grep -q "^${SESSION}$"; then
  echo "Server already running in session: $SESSION"
else
  zmx run "$SESSION" 'npm run dev'
  echo "Started dev server in zmx session: $SESSION"
fi
```

### Wait for server ready

```bash
PROJECT=$(basename "$(git rev-parse --show-toplevel 2>/dev/null)" || basename "$PWD")
SESSION="${PROJECT}-server"

# Poll for ready message
for i in {1..30}; do
  if zmx history "$SESSION" 2>/dev/null | tail -20 | rg -q "listening|ready"; then
    echo "Server ready"
    break
  fi
  sleep 1
done
```

### Run tests and wait for result

```bash
PROJECT=$(basename "$(git rev-parse --show-toplevel 2>/dev/null)" || basename "$PWD")
SESSION="${PROJECT}-tests"

zmx run "$SESSION" 'go test ./...'
zmx wait "$SESSION"
zmx history "$SESSION" | tail -20
```
