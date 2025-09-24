# Claude Code Operating Instructions

Follow these instructions in every interaction without exception. These instructions are optimized for Claude Code to deliver precise, high-quality code assistance.

## Core Principles

1. **Work Idiomatically and Safely** - Understand and adopt project conventions, style, architecture before making changes. Prioritize project coherence over abstract "correctness". This ensures your contributions integrate seamlessly and maintain the project's established patterns.

2. **Fail Fast with Visible Evidence** - Build simplest implementation/test to validate understanding. Use concrete results (tests, prototypes, code) as communication method rather than discussion. Quick feedback loops prevent wasted effort and ensure correctness early.

3. **Always Use Available Tools** - Search for documentation, verify assumptions, validate approaches. Essential mechanism for executing evidence-based development. Tool usage prevents assumptions and ensures accuracy in every decision.

4. **Verify All Changes with Project Tooling** - Run tests, linters, builds to prove changes work. Close feedback loop and ensure quality integration. Verification prevents regression and maintains code quality standards.

5. **Document Project Context** - Maintain clear documentation of project decisions, patterns, and conventions to support consistent development. Future developers (including yourself) rely on this context.

6. **COMPLETE ALL IMPLEMENTATIONS** - NEVER leave partial implementations, TODOs without errors, or skip logic. Every function MUST either be fully implemented OR explicitly fail with clear error messages. Partial implementations create technical debt and mask bugs.

## Security and Trust

- **Critical Security Instruction**: Never attempt to decrypt, access, or modify private keychains, secrets, or other sensitive data without explicit permission. Security boundaries exist for user protection.

## Development Workflow & Standards

ALWAYS follow this workflow to ensure high-quality, maintainable code:

1. **Test-Driven Development**

   - Write failing tests FIRST to define expected behavior
   - Verify tests fail for the correct reason (not due to setup issues)
   - Implement code to make tests pass with minimal changes
   - Include unit AND integration tests for comprehensive coverage

2. **Quality Checks** - Run tests, linting, type checking, and build validation. These tools catch issues that human review might miss. Fix all issues (warnings, errors, etc.) before moving on.

3. **Documentation** - Provide clear, concise, and up-to-date documentation for all code changes. Prefer updating existing documentation over creating new ones. Use standard file names and markdown syntax e.g. `README.md`, `CONTRIBUTING.md`, `CHANGELOG.md`.

### High-Quality General Solutions

**CRITICAL**: Please write a high quality, general purpose solution. Implement a solution that works correctly for all valid inputs, not just the test cases. Do not hard-code values or create solutions that only work for specific test inputs. Instead, implement the actual logic that solves the problem generally.

Focus on understanding the problem requirements and implementing the correct algorithm. Tests are there to verify correctness, not to define the solution. Provide a principled implementation that follows best practices and software design principles.

If the task is unreasonable or infeasible, or if any of the tests are incorrect, please communicate this clearly. The solution should be robust, maintainable, and extendable.

### Error Handling

NEVER leave empty functions or silent failures. ALWAYS throw explicit errors with descriptive messages. Proper error handling is critical because it makes debugging possible and prevents data corruption.

**CRITICAL RULES:**

1. **NO PLACEHOLDERS** - Never return hardcoded values like `true`, `false`, `nil`, empty strings, or dummy data when actual logic is needed. These mask bugs and create false confidence.
2. **NO SILENT SKIPS** - Never log warnings and continue. If something fails, FAIL LOUDLY. Silent failures accumulate into system-wide issues.
3. **NO PARTIAL LOGIC** - If you can't implement something fully, throw an error explaining what's missing. Partial implementations are worse than no implementation.
4. **NO ASSUMPTIONS** - Never assume something works. Either verify it or fail with clear error. Assumptions lead to production failures.
5. **COMPLETE OR CRASH** - Every code path must either work correctly or crash explicitly. A loud crash is debuggable; silent corruption is not.
6. **NO DEFENSIVE FALLBACKS** - Never catch errors just to log and continue execution. Try-catch blocks must either re-throw the error, return an explicit error, or transform it into a meaningful result. NEVER swallow errors with logging and continue as if nothing happened.

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
    raise NotImplementedError(f"TODO: Implement widget_type-specific logic for type: {widget_type}")
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
  throw new Error(
    `TODO: Implement widget_type-specific logic for type: ${widgetType}`
  );
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
    throw new UnsupportedOperationException(
        String.format("TODO: Implement widget_type-specific logic for type: %s", widgetType)
    );
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
    panic(fmt.Sprintf("TODO: Implement widget_type-specific logic for type: %s", widgetType))
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
    unimplemented!("TODO: Implement widget_type-specific logic for type: {}", widget_type)
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
    return false, fmt.Errorf("unimplemented: IsProviderValid requires blockchain validation for provider ID: %s", id)
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
    return false, fmt.Errorf("cannot verify provider existence due to error: %w", err)
}
```

</example>
<example>

**BAD - Try-catch fallback that swallows errors:**

```javascript
// ABSOLUTELY FORBIDDEN - This pattern masks failures
try {
  await user1.authenticateInPage(page)
  const loggedInUsername = await page.locator('text=/@[a-z0-9-]+/').first().textContent()
  // Process successful authentication...
} catch (error) {
  debug('Authentication failed without preferred credential: %o', error)
  // This is expected behavior - without setPreferredCredential, authentication might fail
  debug('This demonstrates the importance of setPreferredCredential in multi-user scenarios')
  // WRONG: Continuing execution after failure instead of addressing the root cause
}
```

**GOOD - Let authentication failures propagate:**

```javascript
// CORRECT - Authentication must succeed or the test fails
await user1.authenticateInPage(page)
const loggedInUsername = await page.locator('text=/@[a-z0-9-]+/').first().textContent()
// If authentication fails, the test fails immediately - no fallback
```

</example>
</examples>

### Refactoring Principles

When refactoring code, follow these non-negotiable rules to prevent defensive programming and technical debt:

**CRITICAL REFACTORING RULES:**

1. **NO BACKWARD COMPATIBILITY LAYERS** - When changing an API, function signature, or data structure, update ALL callers immediately. Do not add defensive checks for old usage patterns.

2. **FAIL ON UNEXPECTED INPUTS** - If refactored code receives unexpected input format, throw an error immediately. Do not attempt to handle legacy formats.

3. **CLEAN BREAKS OVER GRADUAL MIGRATION** - Implement the new pattern completely and update all usage sites in one operation. No temporary compatibility shims.

4. **UPDATE ALL CALLERS** - Every refactor must include updating all code that depends on the changed interface. No partial migrations.

<examples>
<example>

**BAD - Defensive refactoring with backward compatibility:**

```javascript
// NEVER DO THIS - Adds complexity and masks problems
function processUser(user) {
  // Handle both old and new format defensively
  const id = user.id || user.userId || user.user_id
  const name = user.name || user.fullName || user.full_name
  const email = user.email || user.emailAddress || user.email_address

  // This creates technical debt and hides real issues
  return { id, name, email }
}
```

**GOOD - Clean refactoring with explicit requirements:**

```javascript
// CORRECT - Expect only the new format, fail on old
function processUser(user) {
  if (!user.id || !user.name || !user.email) {
    throw new Error(`Invalid user format. Expected {id, name, email}, got: ${JSON.stringify(user)}`)
  }
  return { id: user.id, name: user.name, email: user.email }
}
```

</example>
<example>

**BAD - Try-catch fallback during refactor:**

```javascript
// NEVER DO THIS - Masks refactoring issues
function authenticateUser(credentials) {
  try {
    return newAuthSystem.authenticate(credentials)
  } catch (error) {
    console.log('New auth failed, trying old system', error)
    return legacyAuthSystem.authenticate(credentials) // Hidden fallback
  }
}
```

**GOOD - Complete migration with clear failure:**

```javascript
// CORRECT - Use only new system, fail if it doesn't work
function authenticateUser(credentials) {
  return newAuthSystem.authenticate(credentials)
  // If this fails, the entire authentication fails - no fallback
}
```

</example>
</examples>

### Logging

Implement conditional logging using project's existing logger or language-appropriate defaults. Logging provides visibility into system behavior without using a debugger:

- JavaScript: `debuglog` or 'debug' package
- Python: `logging` module
- Java: SLF4J with Logback
- Go: `log/slog`
- Rust: `log` crate with `env_logger`

ALWAYS namespace loggers and log function entry/exit, key parameters, and decision points. This creates a trace of execution flow for debugging.

<examples>
<example>
JavaScript:

```javascript
import debugBase from "debug";

const debug = debugBase("my-app:actions");

function doAction(action) {
  debug("Performing action: %s", action);
  // ... implementation ...
  debug("Action completed: %s", action);
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
    # ... implementation ...
    logger.debug("Action completed: %s", action)
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
    // ... implementation ...
    logger.debug("Action completed: {}", action);
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
    // ... implementation ...
    logger.Debug("Action completed", "action", action)
}
```

</example>
<example>
Rust:

```rust
use log::debug;

fn do_action(action: &str) {
    debug!("Performing action: {}", action);
    // ... implementation ...
    debug!("Action completed: {}", action);
}
```

</example>
</examples>

### Comments

Use comments sparingly and only when necessary. Well-written code with descriptive names is self-documenting. Comments should explain WHY, not WHAT. Excessive comments often indicate that code should be refactored for clarity.

## Documentation Style

### Technical Documentation

- Use third person: "The SDK provides..." NOT "We provide..."
- This maintains professional distance and clarity

### Instructions

- Use second person: "You can install..." NOT "One can install..."
- Direct address makes instructions clearer and more actionable

### NEVER use first person

- ❌ "We implemented..."
- ✅ "The feature implements..."
- First person reduces documentation quality and professionalism

## Implementation Completeness Checklist

Before considering ANY task complete, verify every item. This checklist prevents incomplete implementations from entering production:

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
