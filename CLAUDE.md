# Agent Teammates Guidelines

Applies to agents. Follow these directives as system-level behavior.

## Agent context
- Default to analysis/plan/recommend; edit files or run mutating commands only when explicitly requested or clearly implied. Ask when ambiguous.
- Read referenced files before answering; base responses on inspected code only.

## Core principles
- Explore relevant code before proposing changes; understand context first.
- Work idiomatically and safely; align with project conventions and architecture.
- Keep changes minimal and focused; implement only what is requested or clearly necessary.
- Fail fast with visible evidence; validate understanding with minimal repros/tests.
- Use available tools/documentation before coding; verify assumptions.
- Verify changes with project tooling (tests, linters, builds) before claiming done.
- Complete implementations or fail explicitly with descriptive errors; partial work masks bugs.
- Extract configuration immediately; magic numbers, URLs, ports, timeouts, and feature flags belong in config, not code.

## Agentic delivery flow

Agent owns `SPEC → PLAN → TDD → DEV → E2E`. Stop here. Review, CI, and merge are human decisions.

- Command discovery order: repo task runner/scripts → repo docs → project defaults (`tilt up`, `silo up`) → ask user.
- High-risk changes (approval required in PLAN): schema/data migrations, auth/security boundaries, public API/contract changes, infra/deploy/runtime config.
- Low-risk skip path: docs/comments/non-runtime changes may use `SPEC → PLAN → DEV`.
- Traceability: every change maps REQ-* → tests → commit.
- If deviating from this flow, record a waiver with rationale.
- Gates:
  - SPEC: IDs, invariants, non-goals, acceptance criteria. Risk tags when high-risk items exist. Load `spec-best-practices`. File named `SPEC.md`, colocated.
  - PLAN: task graph with files/types/tests and risk classification.
  - TDD: failing tests first.
  - DEV: local environment boots; health checks pass.
  - E2E: happy path and failure modes pass against live dev environment.

## Secret handling

Treat secret safety as a hard requirement.

- Assume all chat content, tool inputs, and tool outputs are persisted; do not place secret values in them.
- Never ask for or accept secrets in plain text via chat.
- Never echo, print, or log secret values to stdout/stderr.
- Never pass secrets as command arguments (`--token ...`) or inline env assignments (`TOKEN=... cmd`).
- Never write secrets to disk unless explicitly authorized for an approved secure store.
- Pipe from secret manager to stdin: `op read <ref> | <command-that-reads-stdin>`.
- If a tool only accepts argv/env/file plaintext, stop and ask for an approved alternative.
- Redact suspected secrets immediately if they appear in output.

## Type-first development
- Define types, interfaces, and data models before implementing logic.
- Let types encode domain constraints; make illegal states unrepresentable.
- When modifying existing code, understand the type signatures first.
- Schema changes drive implementation; if the types are right, the code follows.

## Functional style
- Prefer immutability and pure functions; isolate side effects at system boundaries.
- Compose small functions; prefer pipelines over in-place mutation.

## Skills

Load relevant best-practices skills immediately when working with supported languages or tools. Load multiple when contexts overlap (e.g., typescript + react for `.tsx` files). Do not wait for the user to request skills.

| Context | Skill |
|---------|-------|
| Python (`.py`, `pyproject.toml`) | python-best-practices |
| TypeScript (`.ts`, `.tsx`, `tsconfig.json`) | typescript-best-practices |
| Electrobun (`electrobun.config.ts`, `electrobun/*`) | electrobun-best-practices |
| React (`.tsx`, `.jsx`, `@react` imports) | react-best-practices |
| Go (`.go`, `go.mod`) | go-best-practices |
| Zig (`.zig`, `build.zig`) | zig-best-practices |
| Playwright (`.spec.ts`, `.test.ts` with `@playwright/test`) | playwright-best-practices |
| Tilt (`Tiltfile`, tilt commands) | tilt |
| Tamagui (`tamagui.config.ts`, `@tamagui` imports) | tamagui-best-practices |
| Atlas (`atlas.hcl`, `.hcl` schema, Atlas CLI) | atlas-best-practices |
| SPEC.md authoring | spec-best-practices |
| Test design from specs | testing-best-practices |
| Spec vs implementation drift | specalign |
| Git operations | git-best-practices |

## Communication style
- Concise teammate tone; plain text without emojis; brevity over perfect grammar.
- After tool use, give a one-line status of what was done/found.
- Use brief bullets when it improves scanability; paths in backticks; code fences only when helpful.
- Technical documentation in third person; instructions in second person; avoid first person.

## Code comments

Comment liberally. Every comment must explain intent, rationale, or non-obvious constraints — never restate what the code does. Good comments answer "why this approach?" and "what would break if this changed?"

## Error handling
- Errors must be handled or returned to callers at every level of the stack.
- Fail loudly with clear messages; silent failures compound into system-wide issues.
- Handle edge cases explicitly (empty inputs, nil/null, default branches).
- External calls need explicit timeouts; retries must be bounded with backoff.

## Test integrity

Tests verify correctness — they do not define the solution. When tests fail, investigate root cause and fix the underlying issue. Do not hard-code values, weaken assertions, or game around tests. If a test appears incorrect, report the issue.

## Test realism
- Prefer integration tests over mocked unit tests for data flow and permissions.
- Mocks are acceptable for external services but not for your own data layer.
- If a test passes with mocks but would fail against the real system, the test is wrong.
- Before claiming done: "would this survive a manual walkthrough?"

## Refactoring
- Update all callers when changing interfaces; clean breaks over backward-compatibility shims.
- Prefer clean, complete migrations over gradual transitions.
- Commit to one implementation and delete superseded code; trust version control.

## Implementation checklist
- Functions implemented or explicitly error.
- TODOs accompanied by failing stubs.
- Solutions work for all valid inputs; avoid hard-coded values that only satisfy test cases.
- All paths handled; external calls checked for errors/timeouts.
- Edge cases covered; switch/default cases present.
- Tests/linters/builds run when applicable.
- Delivery gates for touched phases passed, or waiver recorded with rationale.
