---
name: data-driven-testing
description: Data-driven test case design from spec files. Guides API surface discovery, test case table generation, and DDT→TDD workflow. Use when working with spec files or designing tests for a module.
---

## When to activate

Engage this methodology when:
- A spec file exists (`*.spec.md`, `SPEC.md`, `spec/*.md`)
- User asks about test design, test cases, or TDD
- Working on a new module with a defined public API
- After `/specout` completes

## Mutation policy

- Default behavior: generate/analyze test case JSON and translate to runnable tests.
- Do not edit spec files unless the user explicitly requests spec maintenance.
- When requested to update specs, use append-only edits for new cases and keep unrelated formatting untouched.
- When this skill conflicts with system/project rules, follow system/project rules.

## API surface discovery

Before generating cases, identify what to test:
- Read the module source to enumerate exports/public functions
- Confirm scope from user request and inspected code context; if ambiguous, state assumptions and proceed with a conservative scope
- For each function, identify: input types/constraints, output shape, error modes, invariants
- Probe for state dependencies and ordering constraints between functions
- Decide granularity from request context: unit-level (individual functions) vs integration-level (function compositions)

## Test case format — canonical JSON

One pretty-printed JSON block per function under `## Test Cases`. JSON is strict, comment-free, and universally parseable. Pretty-printing keeps it reviewable; fixed key ordering keeps diffs clean.

````markdown
## Test Cases

### `functionName`

```json
{
  "function": "functionName",
  "signature": "(param1: Type, param2: Type) -> ReturnType",
  "source": "src/module.ts:42",
  "invariants": [
    "Output is always non-negative",
    "If input is sorted, output is sorted"
  ],
  "fixtures": {
    "valid_user": { "name": "Alice", "age": 30, "role": "admin" }
  },
  "cases": [
    {
      "id": "HP-01",
      "category": "happy_path",
      "name": "basic uppercase",
      "input": { "param1": "hello", "param2": 5 },
      "expected": "HELLO"
    },
    {
      "id": "BV-01",
      "category": "boundary",
      "name": "single char",
      "input": { "param1": "a", "param2": 1 },
      "expected": "A"
    },
    {
      "id": "ERR-01",
      "category": "error",
      "name": "null input",
      "input": { "param1": null, "param2": 5 },
      "expected_error": { "code": "INVALID_ARGUMENT", "message_contains": "param1 must not be null" }
    },
    {
      "id": "EDGE-01",
      "category": "edge",
      "name": "unicode combining chars",
      "input": { "param1": "café", "param2": 5 },
      "expected": "CAFÉ"
    }
  ]
}
```
````

**Key ordering** (fixed for clean diffs):
- Top-level: `function`, `signature`, `source`, `invariants`, `fixtures`, `cases`
- Each case: `id`, `category`, `name`, `input`, `expected` or `expected_error`

**Case ID scheme**: `{CATEGORY}-{NN}` — stable, append-only.
- `HP-NN` = happy path
- `BV-NN` = boundary value
- `ERR-NN` = error case
- `EDGE-NN` = edge case
- Never renumber or reorder existing cases; only append new ones

**`expected_error` format**: Spec-level, not language-specific. Uses `code` (semantic error code) and optional `message_contains` (substring match). The test-writer maps these to language-appropriate assertions (e.g. `expect(...).toThrow()`, `pytest.raises()` with `match=`, Go `errors.Is()`).

**Format rules**:
- One JSON block per function — each is self-contained
- `fixtures` block at the top for reusable compound objects; cases reference by key name
- `expected` or `expected_error` — never both on the same case
- Invariants listed per-function, verified across all cases in that block

## Categories to cover per function

- **Happy path** — normal valid inputs, expected successful outputs
- **Boundary values** — min/max ranges, empty, single-element, at-limit
- **Error cases** — invalid types, out-of-range, missing required fields
- **Edge cases** — null/nil, unicode, very large inputs, concurrent access
- **Invariants** — properties that hold across ALL cases (listed once, verified across all)

## Output placement

- Default: output `## Test Cases` JSON blocks in agent output only (no file edits)
- If user explicitly requests spec maintenance for a small spec: append `## Test Cases` inline in the spec file (for example `SPEC.md`)
- If user explicitly requests spec maintenance for a large spec: create or update companion `<name>.test-spec.md` alongside the spec
- Preserve unrelated content and formatting when editing spec artifacts

## DDT → TDD workflow

1. `/specout` defines the module spec (types, behavior, constraints)
2. Agent (with this skill) produces test case JSON from the spec
3. test-writer agent translates JSON to runnable code in the target language's DDT idiom
4. Developer implements to pass the tests
5. If implementation reveals missing cases, propose them first; append them to the spec's JSON only when explicitly requested — the spec owns the cases
