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
2. **Code Search** - Use `ast-grep --lang <language> -p '<pattern>'` for syntax-aware searching (not text search)
3. **Test-Driven Development**
   - Write failing tests FIRST
   - Verify tests fail for the correct reason
   - Implement code to make tests pass
   - Include unit AND integration tests
4. **Quality Checks** - Run tests, linting, type checking, and build validation
5. **Changesets** - Add changesets for public API/behavioral changes using past tense
6. **Commits** - Use conventional commit format (`feat:`, `fix:`, `refactor:`)

## Coding Standards

### Error Handling

NEVER leave empty functions or silent failures. ALWAYS throw explicit errors with descriptive messages.

### Logging

Implement conditional logging using project's existing logger or language-appropriate defaults:

- JavaScript: `debuglog` or 'debug' package
- Python: `logging` module
- Java: SLF4J with Logback
- Go: `log/slog`
- Rust: `log` crate with `env_logger`

ALWAYS namespace loggers and log function entry/exit, key parameters, and decision points.

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
