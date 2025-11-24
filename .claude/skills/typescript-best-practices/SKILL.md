---
name: typescript-best-practices
description: TypeScript code quality patterns for strict typing, exhaustive switch handling, and debug logging. Use when writing, reviewing, or debugging TypeScript code.
---

# TypeScript Best Practices

## Instructions

- Enable `strict` mode; model data with interfaces and types. Strong typing catches bugs at compile time.
- Every code path returns a value or throws; use exhaustive `switch` with `never` checks in default. Unhandled cases become compile errors.
- Propagate errors with context; catching requires re-throwing or returning a meaningful result. Hidden failures delay debugging.
- Handle edge cases explicitly: empty arrays, null/undefined inputs, boundary values. Defensive checks prevent runtime surprises.
- Use `await` for async calls; wrap external calls with contextual error messages. Unhandled rejections crash Node processes.
- Add or update focused tests when changing logic; test behavior, not implementation details.

## Examples

Explicit failure for unimplemented logic:
```ts
export function buildWidget(widgetType: string): never {
  throw new Error(`buildWidget not implemented for type: ${widgetType}`);
}
```

Exhaustive switch with never check:
```ts
type Status = "active" | "inactive";

export function processStatus(status: Status): string {
  switch (status) {
    case "active":
      return "processing";
    case "inactive":
      return "skipped";
    default: {
      const _exhaustive: never = status;
      throw new Error(`unhandled status: ${_exhaustive}`);
    }
  }
}
```

Wrap external calls with context:
```ts
export async function fetchWidget(id: string): Promise<Widget> {
  const response = await fetch(`/api/widgets/${id}`);
  if (!response.ok) {
    throw new Error(`fetch widget ${id} failed: ${response.status}`);
  }
  return response.json();
}
```

Debug logging with namespaced logger:
```ts
import debug from "debug";

const log = debug("myapp:widgets");

export function createWidget(name: string): Widget {
  log("creating widget: %s", name);
  const widget = { id: crypto.randomUUID(), name };
  log("created widget: %s", widget.id);
  return widget;
}
```
