# Claude Code Operating Instructions

Follow these instructions in every interaction without exception.

## Core Principles

1. **Work Idiomatically and Safely** - Understand and adopt project conventions, style, architecture before making changes. Prioritize project coherence over abstract "correctness"
2. **Fail Fast with Visible Evidence** - Build simplest implementation/test to validate understanding. Use concrete results (tests, prototypes, code) as communication method rather than discussion
3. **Always Use Available Tools** - Search for documentation, verify assumptions, validate approaches. Essential mechanism for executing evidence-based development
4. **Verify All Changes with Project Tooling** - Run tests, linters, builds to prove changes work. Close feedback loop and ensure quality integration
5. **Document Project Context** - Maintain clear documentation of project decisions, patterns, and conventions to support consistent development
6. **COMPLETE ALL IMPLEMENTATIONS** - NEVER leave partial implementations, TODOs without errors, or skip logic. Every function MUST either be fully implemented OR explicitly fail with clear error messages

## Specialized Subagents

Leverage specialized subagents for task-specific expertise:

- **beck-tdd** (PROACTIVE): Test-Driven Development master for implementing specs and requirements through tests
- **knuth-analyst** (PROACTIVE): Complex algorithms, Big O analysis, mathematical correctness
- **hamilton-reliability** (PROACTIVE): Mission-critical code, comprehensive error handling
- **torvalds-pragmatist**: Code quality reviews, performance critiques, design decisions
- **liskov-architect**: Interface design, inheritance hierarchies, type substitutability
- **carmack-optimizer**: Performance optimization with profiler data, cache analysis
- **hickey-simplifier**: Reducing complexity, architectural refactoring, API simplification
- **hopper-debugger**: Systematic debugging, reproduction steps, developer experience

### Advanced Usage Patterns

**Chain subagents for comprehensive analysis:**
> "Use knuth-analyst to verify algorithm correctness, then carmack-optimizer to improve performance"

**Dynamic selection based on context:**
- Implementing from specs? → beck-tdd for test-first development
- Error in production? → hamilton-reliability + hopper-debugger
- Slow performance? → carmack-optimizer after profiling
- Complex inheritance? → liskov-architect + hickey-simplifier
- Code review needed? → torvalds-pragmatist for honest assessment

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

When working in meta-repos (workspace repositories that contain submodules or other repositories):

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

## Screenshot Analysis with Peekaboo CLI

### Overview

Peekaboo is a macOS utility for capturing screenshots and analyzing them with AI vision models. The CLI tool is available in PATH and provides powerful screenshot capture and AI-powered analysis capabilities.

**IMPORTANT**: Prefer Peekaboo CLI analysis instead of directly reading the image files to preserve your context and token usage unless it is absolutely necessary to read the image file directly.

### Basic Usage

#### Capturing Screenshots

```bash
# Capture screenshot of frontmost application
peekaboo image --path screenshot.png

# Capture screenshot of specific application
peekaboo image --app Safari --path safari-screenshot.png

# Capture entire screen
peekaboo image --mode screen --path fullscreen.png

# Capture specific screen (for multi-monitor setups)
peekaboo image --mode screen --screen 0 --path monitor1.png
```

#### Analyzing Screenshots with AI

```bash
# Analyze existing screenshot
peekaboo analyze screenshot.png "What error is shown?"

# Analyze with specific prompt
peekaboo analyze /path/to/image.png "Describe the UI elements visible"

# Capture and analyze in one workflow
peekaboo image --app Terminal --path /tmp/terminal.png && \
  peekaboo analyze /tmp/terminal.png "What commands are visible?"
```

#### Listing Applications and Windows

```bash
# List all applications
peekaboo list

# List with window details
peekaboo list --windows
```

### Claude Code Integration Patterns

When working with screenshots in Claude Code:

1. **UI Bug Investigation**

   ```bash
   # Capture the problematic UI
   peekaboo image --app "MyApp" --path /tmp/bug-screenshot.png

   # Analyze with Claude via Read tool
   # Claude can then view the screenshot using the Read tool
   ```

2. **Error Message Analysis**

   ```bash
   # Capture error dialog
   peekaboo image --path /tmp/error.png

   # Get AI analysis
   peekaboo analyze /tmp/error.png "What is the exact error message and stack trace?"
   ```

3. **UI Testing Verification**

   ```bash
   # Capture test results
   peekaboo image --app "Test Runner" --path /tmp/test-results.png

   # Verify test status
   peekaboo analyze /tmp/test-results.png "Are all tests passing? List any failures."
   ```

### Best Practices

1. **Privacy**: Be mindful of sensitive information in screenshots
2. **AI Prompts**: Be specific in analysis prompts for better results
3. **Performance**: Local AI models (Ollama) provide privacy but may be slower

### Common Workflows

1. **Debug Visual Issues**

   - Capture the problematic UI state
   - Use Read tool to view the screenshot in Claude Code
   - Analyze layout, styling, or rendering issues

2. **Document UI States**

   - Capture different application states
   - Store screenshots with descriptive names
   - Reference in documentation or bug reports

3. **Monitor Long-Running Processes**
   - Periodically capture process status windows
   - Analyze progress or detect errors
   - Automate with shell scripts if needed

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
