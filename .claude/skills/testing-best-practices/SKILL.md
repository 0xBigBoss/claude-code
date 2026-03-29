---
name: testing-best-practices
description: Use when designing tests, writing test cases, or planning test strategy for a module. Covers unit, integration, and e2e layering.
---

## Test layering policy

### Unit tests

Purpose: verify individual functions and invariants in isolation.

- **Data-driven**: parameterized tables covering happy path, boundary, error, and edge cases.
- **Property-based**: fuzz invariants that must hold across all inputs (e.g., idempotency, sort stability, roundtrip serialization).
- Derive cases from the module's public API surface: input types/constraints, output shape, error modes, invariants.

### Integration / contract tests

Purpose: verify interactions between components and external services.

- **API envelope**: request/response shape, status codes, content types, pagination.
- **Error contract**: error codes, error shapes, rate limiting, retries.
- **Auth and scoping**: token validation, role-based access, tenant isolation.
- **Eventual consistency**: verify convergence within bounded time; poll rather than sleep.
- Reuse auth state across tests where possible; avoid redundant login flows.

### E2E tests

Purpose: verify real user workflows through the full stack.

- No mocks; exercise real services, databases, and APIs.
- Happy-path workflows only; save edge cases for lower layers.
- **State-tolerant**: never assume a clean slate; tolerate and work with prior state.
- **Idempotent**: safe to run repeatedly without cleanup between runs.
- **Flow-oriented**: validate real data paths end-to-end rather than isolated assertions.

## Hard rules

- **Never invent signatures, source locations, or line numbers.** Only reference what you have read from the codebase.
- **No fabricated fixtures.** Derive test data from actual schemas, types, or seed data in the repo.
- **No test-only hacks in product code.** No `if (process.env.TEST)` branches, no test-specific exports, no test backdoors.
- **E2E must not rely on clean slate.** Tests must tolerate pre-existing data, prior test runs, and shared environments.

## Execution guidance

### Preflight checks (before e2e)

1. Verify the target environment is reachable (health endpoint, ping).
2. Confirm required services are running (database, API, auth provider).
3. Validate test user / credentials exist and are functional.
4. Check for leftover state that could cause false failures; log it, do not fail on it.

### Deterministic fixtures

- Use seeded randomness for generated data (seeded faker, deterministic UUIDs).
- Fixtures should be self-contained; avoid cross-test fixture dependencies.
- Prefer factory functions over shared mutable fixture objects.

### Async handling

- Poll with bounded timeout and backoff; never use fixed `sleep`/`waitForTimeout`.
- Set explicit timeout per operation; fail fast with a descriptive message on timeout.
- Bound retry attempts (e.g., max 3 retries with exponential backoff).
- Use framework-native waiting (Playwright `expect`, async assertions) over manual loops.

### Flake handling

- **Single infrastructure retry** per test run; if it fails twice, it is not flake.
- On retry failure, collect diagnostics: screenshots, network logs, service health, timestamps.
- Classify the failure (flaky / outdated / bug) before attempting a fix.
- Never add arbitrary delays or retry loops as a flake "fix."

## API surface discovery

Before generating test cases:
- Read the module source to enumerate exports/public functions.
- Confirm scope from the user request and inspected code context; if ambiguous, state assumptions and proceed conservatively.
- For each function: input types/constraints, output shape, error modes, invariants.
- Probe for state dependencies and ordering constraints between functions.

## Output format

Use markdown. Produce three sections:

**Test Strategy** -- one bullet per layer (unit/integration/e2e) naming the functions/flows and their coverage type.

**Test Matrix** -- table per function: columns `ID | Category | Name | Input | Expected`. Case ID scheme: `{CATEGORY}-{NN}` (HP, BV, ERR, EDGE). Append-only; never renumber.

**Implementation Plan** -- ordered steps: fixtures, unit tests, integration tests, e2e flows, run command.

## CI guidance

### Fast PR smoke lane

- Unit tests + linting + type-check on every PR.
- Subset of integration tests covering critical contracts.
- Target: under 5 minutes.

### Nightly full lane

Full unit + integration + e2e suite with higher property-based iteration counts. Flag tests that pass on retry but failed initially.

## Workflow

1. Spec or code defines the module behavior (types, constraints, API surface).
2. Agent (with this skill) produces test strategy, matrix, and implementation plan.
3. test-writer agent translates the plan to runnable code in the target language's idiom.
4. Developer implements to pass the tests.
5. If implementation reveals missing cases, propose them first; append to spec only when explicitly requested.
