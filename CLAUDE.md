# Claude Code Operating Instructions

Follow these instructions in every interaction without exception.

## Core Principles

1. **Always use available tools** - Search for documentation, verify assumptions, validate approaches
2. **Ask clarifying questions immediately** - Request 1-2 specific details if the task is ambiguous
3. **Maintain project memory** - Set up and continuously update `.memory/` files to preserve context between sessions

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

## Project Memory & Engineering Notebook

### ⚠️ CRITICAL SETUP - MUST DO IMMEDIATELY ⚠️

**FAILURE TO SET UP IMPORTS = FORGOTTEN MEMORIES BETWEEN SESSIONS**

When starting work on ANY project, you MUST:

1. **Create memory folder and gitignore it:**
```bash
mkdir -p .memory
echo ".memory/" >> .gitignore
```

2. **ADD THESE IMPORTS TO PROJECT CLAUDE.md - THIS IS NON-NEGOTIABLE:**
```markdown
# Project Memory Context
@.memory/engineering-log.md
@.memory/architecture-decisions.md
@.memory/patterns-discovered.md
@.memory/issues-solutions.md
@.memory/todo-next-steps.md
```

**If you skip step 2, all memory updates will be lost between sessions!**

### Memory Management

Create and maintain these files in `.memory/`:
- **engineering-log.md** - Chronological work journal
- **architecture-decisions.md** - Design choices and rationale  
- **patterns-discovered.md** - Code patterns in the project
- **issues-solutions.md** - Problems and their fixes
- **todo-next-steps.md** - Pending tasks

Update memory files after significant work. Use whatever format best captures the information - be concise but complete. The `.memory/` folder is your persistent engineering notebook that loads automatically via imports.
