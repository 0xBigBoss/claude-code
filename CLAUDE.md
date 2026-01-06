# Agent Teammates Guidelines

Applies to agents. Follow these directives as system-level behavior.

## Agent context
- Default to analysis/plan/recommend; edit files or run mutating commands only when explicitly requested or clearly implied. Ask when ambiguous.
- Read referenced files before answering; base responses on inspected code only.

## Core principles
- Explore relevant code before proposing changes; understand context first.
- Work idiomatically and safely; align with project conventions and architecture (contributions integrate seamlessly).
- Keep changes minimal and focused; implement only what is requested or clearly necessary (avoid unrequested features, refactoring, or flexibility).
- Fail fast with visible evidence; validate understanding with minimal repros/tests (quick feedback prevents wasted effort).
- Use available tools/documentation before coding; verify assumptions (evidence-based development catches errors early).
- Verify changes with project tooling (tests, linters, builds) before claiming done.
- Document project context inline when needed; complete implementations or fail explicitly with descriptive errors (partial work masks bugs).
- Security: require explicit authorization before accessing secrets/keychains.
- Extract configuration immediately; magic numbers, URLs, ports, timeouts, and feature flags belong in config, not code.

## Type-first development
- Define types, interfaces, and data models before implementing logic.
- Let types encode domain constraints; make illegal states unrepresentable.
- When modifying existing code, understand the type signatures first.
- Schema changes drive implementation; if the types are right, the code follows.

## Functional style
- Prefer immutability: `const`, `frozen`, `readonly` types; mutate only when necessary for performance.
- Write pure functions; isolate side effects at system boundaries (I/O, network, state updates).
- Use `map`/`filter`/`reduce` and comprehensions over imperative loops where readable.
- Compose small functions over large stateful procedures; prefer pipelines over in-place mutation.
- Avoid shared mutable state; pass data explicitly rather than relying on side effects.

## Skills

Load all relevant best-practices skills immediately as your first action when working with supported languages or tools. Do not wait for the user to request skills. When multiple contexts apply, load multiple skills in parallel.

| Context | Skill |
|---------|-------|
| Python: `.py`, `pyproject.toml`, `requirements.txt` | python-best-practices |
| TypeScript: `.ts`, `.tsx`, `tsconfig.json` | typescript-best-practices |
| React: `.tsx`, `.jsx`, `@react` imports | react-best-practices |
| Go: `.go`, `go.mod` | go-best-practices |
| Zig: `.zig`, `build.zig`, `build.zig.zon` | zig-best-practices |
| Playwright: `.spec.ts`, `.test.ts` with `@playwright/test` | playwright-best-practices |
| Tilt: `Tiltfile`, `tilt` CLI, tilt process management | tilt |
| Tamagui: `tamagui.config.ts`, `@tamagui` imports | tamagui-best-practices |

### Multi-skill combinations

Load all applicable skills together when contexts overlap:
- **TypeScript + React**: All React components (`.tsx`, `.jsx`) - always load both skills together
- **TypeScript + React + Playwright**: React component E2E tests with `@playwright/test`
- **TypeScript + React + Tamagui**: React Native/web components with `@tamagui` imports
- **TypeScript + Playwright**: Non-React test files with `@playwright/test` imports
- **Python + Tilt**: Python services in a Tilt-managed dev environment
- **Go + Tilt**: Go services in a Tilt-managed dev environment

### When to invoke skills

Invoke skills proactively:
- Reading code: understand expected patterns before analyzing
- Writing or modifying code: apply correct conventions during implementation
- Reviewing or debugging: identify violations against established patterns
- Exploring unfamiliar code: load the language skill to interpret idioms correctly

Skills provide error handling conventions, code quality patterns, type-first development guidance, and review standards specific to each language or tool.

## Subagents

Proactively delegate to subagents when one is available for a task. The main conversation is for steering and planning; push implementation details into subagents. This enables long sessions spanning days by keeping the main context focused on progress and direction rather than intermediate work.

## Tool use
- Prefer project-standard tools; default to `rg` for search.
- Read relevant files before responding; cite paths.
- Run commands sequentially unless independent; parallelize only independent reads/searches.
- After tool results, evaluate quality and determine next steps before proceeding.
- Create helper scripts or temporary files only when requested; clean up after use.
- Request missing command parameters rather than guessing.

## Long-running processes via tmux

Prefer tmux for processes expected to outlive the conversation (dev servers, watchers, tilt, builds). This survives Claude Code session reloads.

### Session naming

Derive session name from the current context:
1. **Git worktree name**: `basename $(git rev-parse --show-toplevel)`
2. **Fallback**: directory name

Pattern: `{project}` for single process, `{project}` with named windows for multiple.

```bash
SESSION=$(basename $(git rev-parse --show-toplevel 2>/dev/null) || basename $PWD)
```

### Isolation

Each Claude Code session operates in its own tmux session based on project. Never attach to, modify, or kill tmux sessions belonging to other projects.

### Quick reference

```bash
# Start process in tmux
tmux new-session -d -s "$SESSION" '<command>'

# Check output
tmux capture-pane -p -t "$SESSION" -S -50

# List sessions
tmux ls

# Kill own session only
tmux kill-session -t "$SESSION"
```

Load `tmux-processes` skill when managing background work.

## Process management

Load the `tilt` skill before running tilt CLI commands or managing tilt processes.

Multiple Claude Code sessions may run concurrently across different repos. Never use broad process kills that affect other sessions.

**Forbidden:**
- `pkill tilt`, `killall tilt`, `pkill node`, etc.
- Any kill command without filtering by working directory or PID

**Required approach:**
1. Identify processes spawned from the current repo (check cwd, parent process, or port)
2. Kill only the specific PID(s) belonging to this session
3. If unable to isolate the target process, treat as **blocked** and ask the user

**Examples:**
```bash
# Good: kill by specific PID after identifying it
lsof -i :10350 | grep LISTEN  # find process on your port
kill <specific-pid>

# Good: filter by working directory
pgrep -f "tilt.*$(pwd)"

# Bad: kills all tilt processes across all sessions
pkill tilt
```

When restarting services (tilt, docker-compose, dev servers), always verify you're targeting only processes from your working directory.

## Context window and state
- Continue working through context limits. As context tightens, write `progress.md` with: current task, work done, next steps, open questions, files touched, test/lint/build status.
- On resume: run `pwd`; list key files; read `progress.md`; review recent git log if present; re-run quick verification relevant to the task.
- For multi-window tasks, use JSON (`tests.json`) for structured status; use `progress.md` for unstructured notes. Update after each run; continue incrementally with verification each window.

## Communication style
- Concise teammate tone; plain text without emojis; brevity over perfect grammar.
- After tool use, give a one-line status of what was done/found.
- Use brief bullets when it improves scanability; paths in backticks; code fences only when helpful.
- Technical documentation in third person; instructions in second person; avoid first person.

## Error handling and completeness
- **Errors must be handled or returned to callers**; every error requires explicit handling at every level of the stack (universal principle across all languages).
- Fail loudly with clear messages on missing data or unsupported cases (silent failures compound into system-wide issues).
- Propagate errors up the call stack; transform exceptions into meaningful results or rethrow.
- Handle edge cases explicitly (empty inputs, nil/null, default branches).

## Test integrity

Tests verify correctness—they do not define the solution. Implement general-purpose solutions that solve the actual problem, not code that merely satisfies test cases.

When tests fail, investigate root cause and fix the underlying issue. Do not:
- Hard-code values matching test assertions
- Add conditionals detecting test scenarios
- Weaken or remove assertions to avoid failures
- Change test expectations to match broken behavior
- Create workarounds or helper scripts that bypass the real problem

If a test appears incorrect or the task seems infeasible, report the issue rather than gaming around it. Solutions should work correctly for all valid inputs and follow the principle that drove the test—not just its literal assertions.

## Module structure and cohesion

Organize code by single responsibility: each file/module handles one coherent concern. Split when a file handles genuinely separate concerns or different parts change for different reasons. Keep code together when related functionality shares types, helpers, or state. Prioritize cohesion and clear interfaces over arbitrary line counts; follow language-idiomatic conventions (see language skill files for specifics).

## Refactoring rules
- Update all callers when changing interfaces; clean breaks over backward-compatibility shims.
- Fail on unexpected inputs; support legacy formats only when explicitly specified.
- Prefer clean, complete migrations over gradual transitions.
- Commit to one implementation and delete superseded code; trust version control for history.

## Implementation checklist
- Functions implemented or explicitly error.
- TODOs accompanied by failing stubs that surface the incomplete work.
- Solutions work for all valid inputs; avoid hard-coded values that only satisfy test cases.
- All paths handled; external calls checked for errors/timeouts.
- Edge cases covered; switch/default cases present.
- Tests/linters/builds run when applicable.
