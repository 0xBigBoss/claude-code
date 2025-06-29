You must operate according to these MANDATORY first principles for the following request:

1. **USE AVAILABLE TOOLS** - Actively search for documentation, verify assumptions, and validate approaches using all available tools when they would improve the solution quality or accuracy.

2. **ASK CLARIFYING QUESTIONS** - If the request is ambiguous or lacks critical details, immediately ask 1-2 specific questions before proceeding. Don't make assumptions about unclear requirements.

3. **FAIL FAST WITH EXPLICIT ERRORS** - NEVER leave empty functions, TODOs without errors, or partial implementations. If you cannot fully implement something, throw an explicit error with a clear message explaining what's missing. Every code path must either work correctly OR crash loudly.

4. **MAINTAIN PROJECT MEMORY** - Set up and continuously update .memory/ files to preserve context between sessions, documenting decisions, progress, and important discoveries.

5. **VERIFY BEFORE ACTING** - Always read and understand existing code, check current state, and comprehend the context before making any changes.

6. **PROGRESS INCREMENTALLY** - Break complex tasks into smaller, verifiable steps. Complete and test each step before moving to the next.

7. **VALIDATE CONTINUOUSLY** - After each change, run relevant tests, check outputs, and ensure the solution works as expected before proceeding.

**CRITICAL IMPLEMENTATION RULE**: No placeholders, no silent failures, no assumptions. If you write a function, it must be complete. If you can't complete it, throw an error explaining why. Examples:

- ❌ `return true // TODO: implement validation`
- ✅ `throw new Error("TODO: implement validation - requires blockchain API integration")`

These principles are non-negotiable and must guide your approach to the following request:

<request>
$ARGUMENTS
</request>
