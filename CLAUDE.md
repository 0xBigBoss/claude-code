# Claude Code Operating Instructions

Follow these instructions in every interaction without exception. These instructions are optimized for Claude Code to deliver precise, high-quality code assistance.

## Core Principles

1. **Work Idiomatically and Safely** - Understand and adopt project conventions, style, architecture before making changes. Prioritize project coherence over abstract "correctness". This ensures your contributions integrate seamlessly and maintain the project's established patterns.

2. **Fail Fast with Visible Evidence** - Build simplest implementation/test to validate understanding. Use concrete results (tests, prototypes, code) as communication method rather than discussion. Quick feedback loops prevent wasted effort and ensure correctness early.

3. **Always Use Available Tools** - Search for documentation, verify assumptions, validate approaches. Essential mechanism for executing evidence-based development. Tool usage prevents assumptions and ensures accuracy in every decision.

4. **Verify All Changes with Project Tooling** - Run tests, linters, builds to prove changes work. Close feedback loop and ensure quality integration. Verification prevents regression and maintains code quality standards.

5. **Document Project Context** - Maintain clear documentation of project decisions, patterns, and conventions to support consistent development. Future developers (including yourself) rely on this context. Prefer inline documentation (code comments) over external documentation (READMEs, wikis, etc.) when possible.

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

3. **Documentation** - Provide clear, concise, and up-to-date documentation for all code changes. Add inline documentation (code comments) to explain complex logic or non-obvious decisions. Public methods, classes, and APIs require documentation regarding the purpose, inputs, outputs, and any gotchas when working with the functions. Prefer updating existing documentation over creating new ones. Use standard file names and markdown syntax e.g. `README.md`, `CONTRIBUTING.md`, `CHANGELOG.md`.

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
Python:

```python
def build_widget(widget_type):
    raise NotImplementedError(f"TODO: Implement widget_type-specific logic for type: {widget_type}")
```

</example>
<example>
JavaScript:

```javascript
function buildWidget(widgetType) {
  throw new Error(
    `TODO: Implement widget_type-specific logic for type: ${widgetType}`
  );
}
```

</example>
<example>
Java:

```java
public Widget buildWidget(String widgetType) {
    throw new UnsupportedOperationException(
        String.format("TODO: Implement widget_type-specific logic for type: %s", widgetType)
    );
}
```

</example>
<example>
Go:

```go
func buildWidget(widgetType string) *Widget {
    panic(fmt.Sprintf("TODO: Implement widget_type-specific logic for type: %s", widgetType))
}
```

</example>
<example>
Rust:

```rust
fn build_widget(widget_type: &str) -> Widget {
    unimplemented!("TODO: Implement widget_type-specific logic for type: {}", widget_type)
}
```

</example>
</examples>

### Error Handling Patterns

<examples>
<example>
Explicit failure for unimplemented functions:

```go
func IsProviderValid(id string) (bool, error) {
    return false, fmt.Errorf("unimplemented: IsProviderValid requires blockchain validation for provider ID: %s", id)
}
```

</example>
<example>
Fail fast on errors:

```go
if err != nil {
    return fmt.Errorf("provider check failed: %w", err)
}
```

</example>
<example>
Handle all cases in switch statements:

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
Propagate errors explicitly:

```go
if err != nil {
    return false, fmt.Errorf("cannot verify provider existence due to error: %w", err)
}
```

</example>
<example>
Let failures propagate without fallbacks:

```javascript
// Authentication must succeed or the test fails
await user1.authenticateInPage(page);
const loggedInUsername = await page
  .locator("text=/@[a-z0-9-]+/")
  .first()
  .textContent();
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
Clean refactoring with explicit requirements:

```javascript
// Expect only the new format, fail on old
function processUser(user) {
  if (!user.id || !user.name || !user.email) {
    throw new Error(
      `Invalid user format. Expected {id, name, email}, got: ${JSON.stringify(
        user
      )}`
    );
  }
  return { id: user.id, name: user.name, email: user.email };
}
```

</example>
<example>
Complete migration with clear failure:

```javascript
// Use only new system, fail if it doesn't work
function authenticateUser(credentials) {
  return newAuthSystem.authenticate(credentials);
  // If this fails, the entire authentication fails - no fallback
}
```

</example>
</examples>

### Naming and Code Organization

Avoid the **qualifier anti-pattern** (also called "hedging naming") - adding suffixes like `-simple`, `-new`, `-v2`, `-old`, `_backup`, `_tmp` to avoid committing to a change.

**When This Happens:**

- Refactoring but not confident enough to replace the original
- Wanting "both versions just in case"
- In transition but haven't decided which approach wins
- Afraid to delete the old code

**Why It's Problematic:**

1. **Ambiguity** - Which version should users/developers use?
2. **Decay** - Qualifiers lose meaning over time ("new" becomes old, "simple" becomes complex)
3. **Technical Debt** - Both versions need maintenance or the unused one rots
4. **Indecision Smell** - Signals lack of commitment to an approach
5. **Proliferation** - Leads to `foo.sh`, `foo-v2.sh`, `foo-final.sh`, `foo-final-actually.sh`

**Root Cause:** Avoiding a decision. Instead of replacing or properly versioning, parallel implementations are created.

**The Solution:**

- **Commit to one approach** - Choose the better implementation and replace the old one
- **Delete old code** - Trust version control to preserve history
- **Use proper versioning** - If both versions must coexist, use semantic versioning or feature flags
- **Refactor completely** - Follow the refactoring principles above: clean breaks, update all callers

<examples>
<example>
Single source of truth in file structure:

```
src/
  auth.js          # The current, production implementation
```

Trust version control for history:

- Previous versions exist in git history (`git log -- auth.js`)
- Document migration in commit message
- Remove old versions from the codebase

</example>
<example>
Clear, purposeful naming:

```javascript
function calculateSubtotal(items) {
  return items.reduce((sum, item) => sum + item.price, 0);
}

function calculateTotal(items, taxRate, discountCode) {
  const subtotal = calculateSubtotal(items);
  const discount = applyDiscount(subtotal, discountCode);
  const tax = calculateTax(subtotal - discount, taxRate);
  return subtotal - discount + tax;
}
```

</example>
<example>
Use version control for file history:

```
config.yaml  # Current version
# Previous versions in git history
```

</example>
</examples>

**Remember:** Qualifiers in names are code smells indicating indecision. Make the decision, commit to it, and delete the alternative. Version control preserves history - use it.

### Logging

Implement conditional logging using project's existing logger or language-appropriate defaults. Logging provides visibility into system behavior without using a debugger:

- JavaScript: `debug` or `pino` package
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
