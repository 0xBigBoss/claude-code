---
name: typescript-best-practices
description: TypeScript code quality patterns for strict typing, exhaustive switch handling, runtime validation with Zod, and debug logging. Activate when editing .ts or .tsx files, working with TypeScript projects (tsconfig.json), or when the user mentions TypeScript, types, interfaces, or Zod schemas. For React/frontend patterns, see typescript-frontend-best-practices.
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

## Runtime Validation with Zod

- Define schemas as single source of truth; infer TypeScript types with `z.infer<>`. Avoid duplicating types and schemas.
- Use `safeParse` for user input where failure is expected; use `parse` at trust boundaries where invalid data is a bug.
- Compose schemas with `.extend()`, `.pick()`, `.omit()`, `.merge()` for DRY definitions.
- Add `.transform()` for data normalization at parse time (trim strings, parse dates).
- Include descriptive error messages; use `.refine()` for custom validation logic.

### Examples

Schema as source of truth with type inference:
```ts
import { z } from "zod";

const UserSchema = z.object({
  id: z.string().uuid(),
  email: z.string().email(),
  name: z.string().min(1),
  createdAt: z.string().transform((s) => new Date(s)),
});

type User = z.infer<typeof UserSchema>;
```

Return parse results to callers (never swallow errors):
```ts
import { z, SafeParseReturnType } from "zod";

export function parseUserInput(raw: unknown): SafeParseReturnType<unknown, User> {
  return UserSchema.safeParse(raw);
}

// Caller handles both success and error:
const result = parseUserInput(formData);
if (!result.success) {
  setErrors(result.error.flatten().fieldErrors);
  return;
}
await submitUser(result.data);
```

Strict parsing at trust boundaries:
```ts
export async function fetchUser(id: string): Promise<User> {
  const response = await fetch(`/api/users/${id}`);
  if (!response.ok) {
    throw new Error(`fetch user ${id} failed: ${response.status}`);
  }
  const data = await response.json();
  return UserSchema.parse(data); // throws if API contract violated
}
```

Schema composition:
```ts
const CreateUserSchema = UserSchema.omit({ id: true, createdAt: true });
const UpdateUserSchema = CreateUserSchema.partial();
const UserWithPostsSchema = UserSchema.extend({
  posts: z.array(PostSchema),
});
```
