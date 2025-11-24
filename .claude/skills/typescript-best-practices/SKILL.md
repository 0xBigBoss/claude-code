---
name: typescript-best-practices
description: TypeScript guardrails and examples; use when writing or reviewing TS code to enforce strict typing, exhaustive handling, fail-fast errors/logging.
---

# TypeScript Best Practices

Use when implementing or reviewing TypeScript.

## Instructions
- Use `strict` typing; avoid `any`. Model data with interfaces/types; prefer readonly where possible.
- Fail loudly on unexpected cases; exhaustive `switch` with `default` that throws. No placeholder returns.
- Propagate errors; do not `catch` just to log. If you catch, rethrow or return a meaningful error.
- Handle edge cases: empty arrays, null/undefined inputs, boundary values.
- Async: prefer `await`; avoid fire-and-forget. Wrap external calls with contextual errors.
- Tests: update/add focused tests when changing logic; avoid hard-coded outputs aimed at tests only.

## Examples
- Explicit failure:
```ts
export function buildWidget(widgetType: string): never {
  throw new Error(`TODO: Implement widget_type-specific logic for type: ${widgetType}`);
}
```
- Exhaustive handling:
```ts
type Status = "active" | "inactive";

export function process(status: Status): string {
  switch (status) {
    case "active":
      return "go";
    case "inactive":
      return "stop";
    default:
      const _exhaustiveCheck: never = status;
      throw new Error(`Unhandled status: ${status satisfies never}`);
  }
}
```
- Logging with context:
```ts
import debug from "debug";

const log = debug("my-app:actions");

export async function doAction(action: string) {
  log("Performing action: %s", action);
  // ... implementation ...
  log("Action completed: %s", action);
}
```
