# Claude Code Operating Instructions

Follow these instructions in every interaction without exception.

## Core Principles

1. **Work Idiomatically and Safely** - Understand and adopt project conventions, style, architecture before making changes. Prioritize project coherence over abstract "correctness"
2. **Fail Fast with Visible Evidence** - Build simplest implementation/test to validate understanding. Use concrete results (tests, prototypes, code) as communication method rather than discussion
3. **Always Use Available Tools** - Search for documentation, verify assumptions, validate approaches. Essential mechanism for executing evidence-based development
4. **Verify All Changes with Project Tooling** - Run tests, linters, builds to prove changes work. Close feedback loop and ensure quality integration
5. **Document Project Context** - Maintain clear documentation of project decisions, patterns, and conventions to support consistent development
6. **COMPLETE ALL IMPLEMENTATIONS** - NEVER leave partial implementations, TODOs without errors, or skip logic. Every function MUST either be fully implemented OR explicitly fail with clear error messages

## Security and Trust

- **Critical Security Instruction**: Never attempt to decrypt, access, or modify private keychains, secrets, or other sensitive data without explicit permission

## Development Workflow & Standards

ALWAYS follow this workflow:

1. **Test-Driven Development**
   - Write failing tests FIRST
   - Verify tests fail for the correct reason
   - Implement code to make tests pass
   - Include unit AND integration tests
2. **Quality Checks** - Run tests, linting, type checking, and build validation

### Git Worktrees

When working with git worktrees:

- **NEVER nest worktrees inside the repository** - Worktrees must not be created as child folders within the repository they belong to
- **ALWAYS create worktrees as siblings** - Place worktrees alongside the main repository with `.worktrees` suffix
- **Naming convention**: For repository `my-awesome-repo`, create worktrees in `my-awesome-repo.worktrees/`

Example structure:

```
parent-directory/
├── my-awesome-repo/           # Main repository
└── my-awesome-repo.worktrees/ # Worktree container
    ├── feature-branch/
    ├── hotfix-branch/
    └── experiment-branch/
```

### Working with Meta-repos and Submodule Worktrees

When working in meta-repos (workspace repositories that contain submodules):

- **Meta-repo as workspace**: It's acceptable to create worktrees inside a meta-repo directory when it's being used as a workspace container
- **Submodule worktrees**: When creating worktrees for submodules that need to be worked on independently (not connected as a submodule), follow the standard sibling pattern
- **Example**: In a meta-repo `canton-foundation/`, you can create `canton-monorepo.worktrees/` inside it for independent work on the `canton-monorepo` submodule

Example meta-repo structure:

```
workspace/                       # Meta-repo (workspace)
├── monorepo/                    # Submodule (connected)
├── monorepo.worktrees/          # Worktrees for independent work
│   ├── feature-x/
│   └── bugfix-y/
└── other-submodule.worktrees/   # Worktrees for independent work
└── other-submodule/             # Submodule (connected)
```

**Key distinction**: When the parent directory is a meta-repo being used as a workspace, creating worktree directories inside it is appropriate and expected

### Error Handling

NEVER leave empty functions or silent failures. ALWAYS throw explicit errors with descriptive messages.

**CRITICAL RULES:**

1. **NO PLACEHOLDERS** - Never return hardcoded values like `true`, `false`, `nil`, empty strings, or dummy data when actual logic is needed
2. **NO SILENT SKIPS** - Never log warnings and continue. If something fails, FAIL LOUDLY
3. **NO PARTIAL LOGIC** - If you can't implement something fully, throw an error explaining what's missing
4. **NO ASSUMPTIONS** - Never assume something works. Either verify it or fail with clear error
5. **COMPLETE OR CRASH** - Every code path must either work correctly or crash explicitly

<examples>
<example>
Python - Instead of:

```python
def build_widget(widget_type):
    # TODO: Implement widget_type-specific logic
```

Use:

```python
def build_widget(widget_type):
    raise NotImplementedError(f"TODO: Implement widget_type-specific logic")
```

</example>
<example>
JavaScript - Instead of:

```javascript
function buildWidget(widgetType) {
  // TODO: Implement widget_type-specific logic
}
```

Use:

```javascript
function buildWidget(widgetType) {
  throw new Error(`TODO: Implement widget_type-specific logic`);
}
```

</example>
<example>
Java - Instead of:

```java
public Widget buildWidget(String widgetType) {
    // TODO: Implement widget_type-specific logic
    return null;
}
```

Use:

```java
public Widget buildWidget(String widgetType) {
    throw new UnsupportedOperationException("TODO: Implement widget_type-specific logic");
}
```

</example>
<example>
Go - Instead of:

```go
func buildWidget(widgetType string) *Widget {
    // TODO: Implement widget_type-specific logic
    return nil
}
```

Use:

```go
func buildWidget(widgetType string) *Widget {
    panic("TODO: Implement widget_type-specific logic")
}
```

</example>
<example>
Rust - Instead of:

```rust
fn build_widget(widget_type: &str) -> Widget {
    // TODO: Implement widget_type-specific logic
    unimplemented!()
}
```

Use:

```rust
fn build_widget(widget_type: &str) -> Widget {
    unimplemented!("TODO: Implement widget_type-specific logic")
}
```

</example>
</examples>

### Common Anti-Patterns to AVOID

<examples>
<example>
**BAD - Placeholder return:**
```go
func IsProviderValid(id string) (bool, error) {
    // TODO: implement validation
    return true, nil  // WRONG: Returns success without logic
}
```

**GOOD - Explicit failure:**

```go
func IsProviderValid(id string) (bool, error) {
    return false, fmt.Errorf("unimplemented: IsProviderValid requires blockchain validation")
}
```

</example>
<example>
**BAD - Silent continuation:**
```go
if err != nil {
    logger.Warn("Failed to check provider", zap.Error(err))
    // Continue anyway...  WRONG: Hides failures
}
```

**GOOD - Fail fast:**

```go
if err != nil {
    return fmt.Errorf("provider check failed: %w", err)
}
```

</example>
<example>
**BAD - Incomplete switch/if:**
```go
switch status {
case "active":
    return processActive()
case "inactive":
    return processInactive()
// Missing default case - WRONG: Silent failure path
}
```

**GOOD - Handle all cases:**

```go
switch status {
case "active":
    return processActive()
case "inactive":
    return processInactive()
default:
    return fmt.Errorf("unhandled status: %s", status)
}
```

</example>
<example>
**BAD - Assuming success:**
```go
// Assume provider exists if we can't check
if err != nil {
    return true  // WRONG: Assumes success on error
}
```

**GOOD - Explicit error:**

```go
if err != nil {
    return false, fmt.Errorf("cannot verify provider: %w", err)
}
```

</example>
</examples>

### Logging

Implement conditional logging using project's existing logger or language-appropriate defaults:

- JavaScript: `debuglog` or 'debug' package
- Python: `logging` module
- Java: SLF4J with Logback
- Go: `log/slog`
- Rust: `log` crate with `env_logger`

ALWAYS namespace loggers and log function entry/exit, key parameters, and decision points.

<examples>
<example>
JavaScript:

```javascript
import debugBase from "debug";

const debug = debugBase("my-app:actions");

function doAction(action) {
  debug("Performing action: %s", action);
}
```

</example>
<example>
Python:

```python
import logging

logger = logging.getLogger("my-app.actions")

def do_action(action):
    logger.debug("Performing action: %s", action)
```

</example>
<example>
Java:

```java
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

private static final Logger logger = LoggerFactory.getLogger("my-app.actions");

public void doAction(String action) {
    logger.debug("Performing action: {}", action);
}
```

</example>
<example>
Go:

```go
import "log/slog"

var logger = slog.With("component", "my-app.actions")

func doAction(action string) {
    logger.Debug("Performing action", "action", action)
}
```

</example>
<example>
Rust:

```rust
use log::debug;

fn do_action(action: &str) {
    debug!("Performing action: {}", action);
}
```

</example>
</examples>

### Comments

Use comments sparingly and only when necessary.

## Documentation Style

### Technical Documentation

- Use third person: "The SDK provides..." NOT "We provide..."

### Instructions

- Use second person: "You can install..." NOT "One can install..."

### NEVER use first person

- ❌ "We implemented..."
- ✅ "The feature implements..."

## Implementation Completeness Checklist

Before considering ANY task complete, verify:

### ✅ Function Implementation

- [ ] Every function has a complete implementation OR explicit error
- [ ] No TODOs without corresponding error throws
- [ ] No placeholder returns (hardcoded true/false/nil)
- [ ] All code paths handled (no missing cases)
- [ ] Error handling for all external calls

### ✅ Error Handling

- [ ] All errors are propagated, not swallowed
- [ ] No silent failures (logging then continuing)
- [ ] Clear error messages explaining what failed
- [ ] Fail fast rather than continuing with bad state

### ✅ Edge Cases

- [ ] Empty inputs handled
- [ ] Nil/null checks where needed
- [ ] All switch/match statements have default cases
- [ ] Boundary conditions tested

### ✅ Integration Points

- [ ] External API calls have error handling
- [ ] Database operations check for failures
- [ ] File operations handle missing files
- [ ] Network calls handle timeouts

### 🚫 NEVER DO THIS

- Return dummy values when real logic needed
- Log errors and continue as if nothing happened
- Leave empty function bodies without errors
- Assume external calls will succeed
- Skip error checking to "simplify" code
- Implement "happy path" only

### 🔥 When in Doubt

If you cannot fully implement something:

1. **STOP** - Don't create partial implementation
2. **THROW** - Use panic/throw/raise with clear message
3. **DOCUMENT** - Explain in error what's needed
4. **FAIL FAST** - Let the system crash rather than corrupt

Remember: **A loud failure is better than silent corruption**
