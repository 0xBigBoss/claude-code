# Claude Code Operating Instructions

Follow these instructions in every interaction without exception.

## Core Principles

1. **Work Idiomatically and Safely** - Understand and adopt project conventions, style, architecture before making changes. Prioritize project coherence over abstract "correctness"
2. **Fail Fast with Visible Evidence** - Build simplest implementation/test to validate understanding. Use concrete results (tests, prototypes, code) as communication method rather than discussion
3. **Always Use Available Tools** - Search for documentation, verify assumptions, validate approaches. Essential mechanism for executing evidence-based development
4. **Verify All Changes with Project Tooling** - Run tests, linters, builds to prove changes work. Close feedback loop and ensure quality integration
5. **Maintain Project Memory** - Set up and continuously update `.memory/` files to preserve context between sessions. Support all principles through context preservation

## Development Workflow

ALWAYS follow this workflow:

1. **Branch Creation** - Create feature branches named `claude/<feature-name>` from main/master
2. **Test-Driven Development**
   - Write failing tests FIRST
   - Verify tests fail for the correct reason
   - Implement code to make tests pass
   - Include unit AND integration tests
3. **Quality Checks** - Run tests, linting, type checking, and build validation
4. **Changesets** - Add changesets for public API/behavioral changes using past tense
5. **Commits** - Use conventional commit format (`feat:`, `fix:`, `refactor:`)

## Coding Standards

### Error Handling

NEVER leave empty functions or silent failures. ALWAYS throw explicit errors with descriptive messages.

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

## Project Memory Bank System

### ⚠️ CRITICAL SETUP - MEMORY BANK INITIALIZATION ⚠️

**Transform Claude from a stateless assistant into a persistent development partner**

When starting work on ANY project, you MUST establish a hierarchical memory bank:

1. **Create memory folder and gitignore it:**

```bash
mkdir -p .memory
echo ".memory/" >> .gitignore
```

2. **ADD THESE IMPORTS TO PROJECT CLAUDE.md - NON-NEGOTIABLE:**

```markdown
# Memory Bank Context (Load Order Matters)

@.memory/projectbrief.md
@.memory/productContext.md
@.memory/activeContext.md
@.memory/systemPatterns.md
@.memory/techContext.md
@.memory/progress.md
```

**Skip step 2 = Complete memory loss between sessions**

### Memory Bank Structure (Hierarchical Documentation)

Create and maintain these core files in `.memory/` (files build upon each other):

#### Foundation Layer

- **projectbrief.md** - Project foundation and high-level overview
- **productContext.md** - Why the project exists, problem context, target users

#### Current State Layer

- **activeContext.md** - Current work focus, recent changes, immediate priorities
- **progress.md** - Project status, completed milestones, known issues, blockers

#### Technical Layer

- **systemPatterns.md** - Architecture decisions, design patterns, code conventions
- **techContext.md** - Technologies, dependencies, development setup, tooling

### Memory Bank Principles

1. **Treat every memory reset as documentation opportunity** - After reset, memory bank is the only link to previous work
2. **Encourage organic documentation** - Let documentation emerge naturally during development
3. **Maintain living documentation** - Update after significant changes using "update memory bank" commands
4. **Build hierarchical context** - Files create complete project picture when read in order
5. **Start simple, evolve naturally** - Begin with basic project brief, expand as needed
