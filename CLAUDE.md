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
| Tilt: `Tiltfile`, tilt commands | tilt |
| Tilt bootstrap: `tilt up`, Tiltfile errors, dev env startup | tiltup |
| tmux: long-lived processes, dev servers, `tilt up`, watchers | tmux |
| Tamagui: `tamagui.config.ts`, `@tamagui` imports | tamagui-best-practices |
| Canton Network: `.daml`, `daml.yaml`, Canton/Splice repos, LF versions | canton-network-repos |
| Atlas: `atlas.hcl`, `.hcl` schema files, Atlas CLI commands | atlas-best-practices |
| Spec files: `*.spec.md`, `SPEC.md`, `spec/*.md`, test design | testing-best-practices |
| Spec alignment: spec file + implementation in context | specalign |
| E2E tests: `*.spec.ts` runs, test failures, flaky tests | e2e |
| Git: commits, branches, PRs, history rewriting | git-best-practices |

### Multi-skill combinations

Load all applicable skills together when contexts overlap:
- **TypeScript + React**: All React components (`.tsx`, `.jsx`) - always load both skills together
- **TypeScript + React + Playwright**: React component E2E tests with `@playwright/test`
- **TypeScript + React + Tamagui**: React Native/web components with `@tamagui` imports
- **TypeScript + Playwright**: Non-React test files with `@playwright/test` imports
- **Python + Tilt**: Python services in a Tilt-managed dev environment
- **Go + Tilt**: Go services in a Tilt-managed dev environment
- **testing-best-practices + [language]**: Load testing skill alongside the project's language skill when designing tests from specs
- **tilt + tmux**: Always load both when running `tilt up` or any long-lived process in tmux
- **tilt + tiltup**: Always load both when starting tilt or fixing Tiltfile errors
- **specalign + testing-best-practices**: Load both when a spec file and its implementation are in context
- **e2e + playwright-best-practices**: Load both when running or fixing Playwright e2e tests
- **e2e + specalign**: Load both when e2e failures may indicate spec drift
- **git-best-practices + /git-commit**: Load skill when using the git-commit command or making any commits
- **git-best-practices + /rewrite-history**: Load skill when rewriting branch history before PR

### When to invoke skills

Invoke skills proactively:
- Reading code: understand expected patterns before analyzing
- Writing or modifying code: apply correct conventions during implementation
- Reviewing or debugging: identify violations against established patterns
- Exploring unfamiliar code: load the language skill to interpret idioms correctly

Skills provide error handling conventions, code quality patterns, type-first development guidance, and review standards specific to each language or tool.

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

## Idempotency and resilience
- Check state before changes; skip if already correct; prefer declarative over imperative.
- External calls need explicit timeouts; retries must be bounded with backoff.

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
