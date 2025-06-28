# Condense and Reorganize Memory Bank

You are tasked with condensing and reorganizing the `.memory/` files to maintain performance while preserving critical context. When memory files exceed 30K characters, they need intelligent consolidation.

## Instructions:

1. **Read ONLY these 6 memory files** in `.memory/` (NEVER create others):
   - projectbrief.md
   - productContext.md
   - activeContext.md
   - progress.md
   - systemPatterns.md
   - techContext.md

   ⚠️ **CRITICAL**: Do NOT create or reference any other memory files.

2. **Identify the largest file(s)** and redistribute content:
   - Move current work details → activeContext.md
   - Move completed work → progress.md
   - Move architectural decisions → systemPatterns.md
   - Move technology changes → techContext.md
   - Keep foundational info in projectbrief.md and productContext.md

3. **Condense oversized files** by:
   - Keep only the last 2-3 detailed entries
   - Create "Historical Summary" sections with key milestones
   - Remove redundant information already captured in other files
   - Preserve critical context and decision rationale
   - **Target size: Under 20K characters** (leaving 10K growth room from 30K limit)

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
   - **Ensure ALL files are under 20K characters**
   - Confirm no unauthorized memory files exist
   - Verify only the 6 standard memory files are present

## Output Format:

After reorganization, provide a summary showing:
- Original file sizes for all files over 30K characters
- New file sizes for all condensed files
- Number of items moved between files
- Any critical decisions or patterns preserved
- Confirmation that only 6 standard memory files exist

Remember: The goal is intelligent compression, not deletion. Preserve project understanding while improving performance.
