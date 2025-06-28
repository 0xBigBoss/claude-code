# Update Memory Bank

Update relevant memory bank files after significant changes to maintain project context and preserve development history.

## Instructions:

1. **Assess current work** by reviewing recent changes:
   - Review git status and recent commits
   - Identify what has been modified or completed
   - Determine which memory files need updates

2. **Update ONLY these 6 Memory Bank files** (NEVER create new files):
   - **activeContext.md** - Current work focus, recent changes, immediate priorities
   - **progress.md** - Project status, completed milestones, known issues, blockers
   - **systemPatterns.md** - New architecture decisions, design patterns, code conventions
   - **techContext.md** - Technology changes, dependencies, development setup updates
   - **projectbrief.md** - Major project scope or direction changes (rare)
   - **productContext.md** - Problem context or user need changes (rare)

   ⚠️ **CRITICAL**: Do NOT create any other memory files. Use only these 6 files.

3. **Document key information**:
   - What was completed and how
   - Any architectural decisions made
   - New patterns or conventions established
   - Issues encountered and solutions found
   - Updated priorities or next steps

4. **Maintain file organization**:
   - Keep information in appropriate files based on hierarchy
   - Avoid duplication across files
   - Update cross-references between files
   - Preserve chronological context where relevant
   - Keep each file under 30K characters for optimal performance
   - If files approach 30K characters, use `/project:condense-memory` command

## Usage:
- Run after completing features, fixing bugs, or making architectural changes
- Use before ending work sessions to capture context
- Essential before memory resets to preserve continuity

Remember: The memory bank is your persistent development partner's knowledge base.