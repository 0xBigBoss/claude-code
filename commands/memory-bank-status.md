# Memory Bank Status

Review the current state of memory bank documentation to understand project context and identify gaps.

## Instructions:

1. **Check memory bank structure**:
   - Verify all core memory files exist in `.memory/` directory
   - Confirm files are properly imported in project CLAUDE.md
   - Identify any missing or outdated files

2. **Review ONLY these 6 memory files** (no others should exist):
   - **projectbrief.md** - Project foundation and high-level overview
   - **productContext.md** - Problem context, why project exists, target users
   - **activeContext.md** - Current work focus, recent changes, priorities
   - **progress.md** - Project status, milestones, known issues, blockers
   - **systemPatterns.md** - Architecture decisions, design patterns, conventions
   - **techContext.md** - Technologies, dependencies, development setup

   ⚠️ **WARNING**: Flag any additional memory files as incorrect

3. **Assess memory bank health**:
   - Check file sizes - flag any over 30K characters for condensing
   - Look for outdated information that needs updating
   - Identify gaps in documentation
   - Review if current work is properly reflected
   - Verify no unauthorized memory files exist

4. **Provide status summary**:
   - Overall memory bank completeness
   - Files that need attention or updates
   - Recommendations for maintenance
   - Any structural improvements needed

## Output Format:

Provide a clear status report including:
- Memory bank file inventory (✅ exists, ❌ missing, ⚠️ needs attention, 🚫 unauthorized)
- File size summary (flag any over 30K characters)
- Content freshness assessment
- Recommended actions for improvement
- Alert if any non-standard memory files exist

## Usage:
- Run at start of work sessions to understand current context
- Use when context feels incomplete or outdated
- Essential for diagnosing memory bank issues