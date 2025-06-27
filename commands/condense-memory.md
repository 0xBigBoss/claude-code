# Condense and Reorganize Engineering Memory

You are tasked with condensing and reorganizing the `.memory/` files to maintain performance while preserving critical context. The engineering log has grown beyond 40k characters and needs intelligent consolidation.

## Instructions:

1. **Read all memory files** in `.memory/`:
   - engineering-log.md
   - architecture-decisions.md
   - patterns-discovered.md
   - issues-solutions.md
   - todo-next-steps.md

2. **Analyze engineering-log.md** and:
   - Extract architectural decisions → Move to architecture-decisions.md
   - Extract discovered patterns → Move to patterns-discovered.md
   - Extract issue/solution pairs → Move to issues-solutions.md
   - Extract pending tasks → Move to todo-next-steps.md

3. **Condense engineering-log.md** by:
   - Keep only the last 2-3 of detailed entries
   - Create a "Historical Summary" section at the top with key milestones
   - Remove redundant information already captured in other files
   - Preserve critical context and decision rationale
   - Target size: Under 15K characters (leaving room for growth)

4. **Deduplicate across files**:
   - Remove duplicate entries
   - Consolidate similar patterns/decisions
   - Update cross-references between files

5. **Maintain continuity**:
   - Ensure no critical information is lost
   - Add timestamps to moved content
   - Create clear section headers
   - Include brief summaries of condensed content

6. **Final validation**:
   - Verify all files are properly formatted
   - Check that total context remains accessible
   - Ensure engineering-log.md is under 15k chars
   - Confirm all TODOs are captured in todo-next-steps.md

## Output Format:

After reorganization, provide a summary showing:
- Original engineering-log.md size
- New engineering-log.md size
- Number of items moved to each file
- Any critical decisions or patterns preserved

Remember: The goal is intelligent compression, not deletion. Preserve project understanding while improving performance.
