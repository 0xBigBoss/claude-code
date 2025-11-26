---
name: typescript-frontend-best-practices
description: React patterns, React Query data fetching, hooks, and component architecture. Use when writing, reviewing, or debugging React/TypeScript frontend code. See also: typescript-best-practices for Zod schemas and type patterns.
---

# TypeScript Frontend Best Practices

## React Component Patterns

- Prefer function components with explicit prop types; avoid `any` in component interfaces.
- Colocate related state; lift state only when sharing between siblings is needed.
- Use composition over prop drilling; children and render props patterns reduce coupling.
- Keep components small; extract when reused or when logic obscures the template.

## Hooks Best Practices

- Custom hooks share stateful logic, not state itself; each call returns independent state.
- Name functions `useX` only if they call other hooks; regular utilities don't need the prefix.
- Keep hooks focused on single responsibility; compose multiple small hooks over one large hook.
- Wrap event handler props with `useEffectEvent` to exclude them from effect dependencies.

## Effects vs Event Handlers

- Effects synchronize with external systems (subscriptions, timers, DOM); event handlers respond to user actions.
- Derive state during render; avoid effects for data transformation or state synchronization.
- Use `useMemo` for expensive calculations, not effects; effects cause extra render cycles.
- Never suppress the dependency linter; fix the underlying issue or use `useEffectEvent` for non-reactive logic.

### When to Use Effects

- Subscribing to external data sources (WebSocket, browser APIs)
- Setting up and cleaning up event listeners
- Syncing with third-party libraries that aren't React-aware
- Fetching data on mount (though prefer React Query)

### When NOT to Use Effects

- Transforming data for rendering (calculate during render)
- Handling user events (use event handlers)
- Resetting state when props change (use `key` prop or calculate during render)
- Chaining state updates (consolidate in event handler)

## React Query Patterns

- One query key pattern per resource; colocate key factories with API functions.
- Structure keys hierarchically: `['users', userId]`, `['users', 'list', { status, page }]`.
- Mutations invalidate related queries via `onSuccess`; use `queryClient.invalidateQueries`.
- Set `staleTime` per query based on data freshness needs; zero is aggressive, tune up for stable data.
- Handle loading/error/success states explicitly; don't render stale data as if it were fresh.

### Examples

Query with Zod validation:
```tsx
const userKeys = {
  all: ['users'] as const,
  detail: (id: string) => [...userKeys.all, id] as const,
  list: (filters: UserFilters) => [...userKeys.all, 'list', filters] as const,
};

export function useUser(id: string) {
  return useQuery({
    queryKey: userKeys.detail(id),
    queryFn: async () => {
      const res = await fetch(`/api/users/${id}`);
      if (!res.ok) throw new Error(`fetch user failed: ${res.status}`);
      return UserSchema.parse(await res.json());
    },
    staleTime: 5 * 60 * 1000, // 5 minutes
  });
}
```

Mutation with cache invalidation:
```tsx
export function useUpdateUser() {
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: async ({ id, data }: { id: string; data: UpdateUser }) => {
      const res = await fetch(`/api/users/${id}`, {
        method: 'PATCH',
        body: JSON.stringify(data),
      });
      if (!res.ok) throw new Error(`update user failed: ${res.status}`);
      return UserSchema.parse(await res.json());
    },
    onSuccess: (user) => {
      queryClient.invalidateQueries({ queryKey: userKeys.all });
      queryClient.setQueryData(userKeys.detail(user.id), user);
    },
  });
}
```

## Progressive UI States

Handle all query and mutation states explicitly. UIs must show the correct state at each phase: initial → pending → success/error.

### Query State Handling

```tsx
function UserProfile({ userId }: { userId: string }) {
  const { data: user, isPending, isError, error, isFetching } = useUser(userId);

  if (isPending) {
    return <Skeleton />;  // Initial load
  }

  if (isError) {
    return <ErrorMessage error={error} />;
  }

  return (
    <div>
      {isFetching && <RefreshIndicator />}  {/* Background refetch */}
      <UserCard user={user} />
    </div>
  );
}
```

### Mutation State Handling

```tsx
function UpdateUserForm({ user }: { user: User }) {
  const updateUser = useUpdateUser();

  const handleSubmit = (data: UpdateUser) => {
    updateUser.mutate(
      { id: user.id, data },
      {
        onError: (error) => toast.error(`Update failed: ${error.message}`),
        onSuccess: () => toast.success('User updated'),
      }
    );
  };

  return (
    <form onSubmit={handleSubmit}>
      {/* form fields */}
      <button type="submit" disabled={updateUser.isPending}>
        {updateUser.isPending ? 'Saving...' : 'Save'}
      </button>
      {updateUser.isError && (
        <p className="error">{updateUser.error.message}</p>
      )}
    </form>
  );
}
```

## React Context for App State

- Use Context for truly global state (auth, theme, locale); avoid for frequently changing data.
- Split contexts by concern; a single "AppContext" forces unnecessary re-renders.
- Provide sensible defaults or throw in consumer if context is required.
- Colocate Provider near usage; not everything belongs at the root.

### Example

```tsx
interface AuthContextValue {
  user: User | null;
  login: (credentials: Credentials) => Promise<void>;
  logout: () => void;
}

const AuthContext = createContext<AuthContextValue | null>(null);

export function useAuth(): AuthContextValue {
  const ctx = useContext(AuthContext);
  if (!ctx) throw new Error("useAuth must be used within AuthProvider");
  return ctx;
}

export function AuthProvider({ children }: { children: ReactNode }) {
  const [user, setUser] = useState<User | null>(null);

  const login = async (credentials: Credentials) => {
    const user = await authService.login(credentials);
    setUser(user);
  };

  const logout = () => {
    authService.logout();
    setUser(null);
  };

  return (
    <AuthContext.Provider value={{ user, login, logout }}>
      {children}
    </AuthContext.Provider>
  );
}
```

## Component Architecture

- Separate container components (data fetching, state) from presentational components (pure UI).
- Presentational components receive data via props; they don't call hooks like `useQuery`.
- Container components orchestrate data and pass it down; they contain minimal JSX.
- Test presentational components with props; test containers with mocked queries.
