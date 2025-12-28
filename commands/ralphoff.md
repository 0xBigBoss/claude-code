---
allowed-tools: Bash(*), Edit(~/.claude/handoffs/**)
argument-hint: [completion criteria or additional notes]
description: Generate Ralph-loop-ready handoff prompt
---

# Generate Ralph Loop Handoff Prompt

Generate a prompt for handing off work to a Ralph Reviewed loop (`/ralph-reviewed:ralph-loop`). The receiving session runs in an iterative self-improvement loop with Codex review gates until a completion promise is output and approved. The prompt must be self-contained, include clear success criteria, and support automatic verification.

## Git Context

**Working Directory**: !`pwd`

**Repository**: !`basename "$(git rev-parse --show-toplevel 2>/dev/null || pwd)"`

**Branch**: !`git branch --show-current 2>/dev/null || echo "detached/unknown"`

**Uncommitted changes**: !`git diff --stat 2>/dev/null || echo "None"`

**Staged changes**: !`git diff --cached --stat 2>/dev/null || echo "None"`

**Recent commits (last 4 hours)**: !`git log --oneline -5 --since="4 hours ago" 2>/dev/null || echo "None"`

## Session Context

Review the conversation history from this session to understand:
- What task was requested and why
- What approach was taken
- Decisions made or tradeoffs discussed
- Current state: what's done, in progress, or blocked
- What verification exists (tests, linters, type checks, builds)
- Known issues or incomplete items

## Additional Focus / Completion Criteria

$ARGUMENTS

## Task

Write a Ralph-loop context file to `~/.claude/handoffs/ralph-<repo>-<shortname>.md` where `<repo>` is the repository name and `<shortname>` is derived from the branch name (e.g., `ralph-myapp-sen-69.md`).

The context file contains the detailed task description. A simple wrapper command referencing this file is copied to clipboard for direct use with ralph-loop.

### Ralph Loop Prompt Requirements

The output prompt must include:
1. **Clear completion criteria** - What must be true for the task to be "done"
2. **Verification commands** - Tests, builds, linters that prove success/failure
3. **Iteration awareness** - Make Claude know it's in a loop and should review previous work
4. **Completion promise** - A unique marker Claude outputs when done (e.g., `<promise>COMPLETE</promise>`)
5. **Escape conditions** - What to do if stuck after many iterations

### Prompting Guidelines

Apply these when writing the prompt:
- **Be explicit about success criteria** - "Tests pass" not "Tests should work"
- **Use action-oriented language** - "Run `npm test` and fix any failures" not "Make sure tests work"
- **Include verification loop** - "Run verification, if failures exist fix them, repeat"
- **Frame positively** - Say what to do, not what to avoid
- **Use XML tags** for clear section delimitation

### Output Structure

Use this XML-tagged structure optimized for Ralph loops:

```
<task>
[1-2 sentence summary of what to accomplish]
</task>

<context>
[2-4 sentences: what was being worked on, why, approach taken, key decisions made]
</context>

<key_files>
[Files involved with brief descriptions of changes/relevance]
</key_files>

<success_criteria>
[Explicit, verifiable conditions that must ALL be true when complete. Examples:
- All tests in `src/__tests__/` pass
- `npm run build` succeeds with no errors
- Type checking passes (`npm run typecheck`)
- Linter passes (`npm run lint`)]
</success_criteria>

<verification_loop>
Run these commands to verify progress. If any fail, fix the issues and re-verify:

1. [First verification command and what to do if it fails]
2. [Second verification command and what to do if it fails]
3. [Continue until all pass]

When ALL verifications pass, output: <promise>COMPLETE</promise>
</verification_loop>

<if_stuck>
After 15+ iterations without progress:
- Document what's blocking in a `BLOCKED.md` file
- List approaches attempted
- Suggest alternative paths
- Output: <promise>BLOCKED</promise>
</if_stuck>
```

### Output Method

1. Ensure directory exists: `mkdir -p ~/.claude/handoffs`

2. Write the Ralph-loop context file to `~/.claude/handoffs/ralph-<repo>-<shortname>.md` where:
   - `<repo>` is the repository basename
   - `<shortname>` is derived from the branch name (e.g., `ralph-myapp-sen-69.md`)

3. Generate a simple, bash-safe wrapper command. The wrapper prompt must:
   - Reference the context file by path
   - Be a single line with no newlines
   - Avoid special characters that break bash (backticks, unescaped quotes, $)
   - Include the completion promise

4. Copy the **wrapper command** (not the context file) to clipboard

5. Confirm with usage instructions showing the exact command to run:
   ```
   Ralph-loop context saved to ~/.claude/handoffs/<filename>

   Run this command in a new Claude Code session:

   /ralph-reviewed:ralph-loop "Read ~/.claude/handoffs/<filename> and complete the task. Output COMPLETE when done." --completion-promise "COMPLETE" --max-iterations 30
   ```

### Wrapper Command Format

The clipboard should contain ONLY this single-line command (no extra text):

```
/ralph-reviewed:ralph-loop "Read ~/.claude/handoffs/<filename> and complete the task described there. Follow the success criteria and verification loop. Output COMPLETE when all verifications pass, or BLOCKED if stuck after 15 iterations." --completion-promise "COMPLETE" --max-iterations 30
```

Replace `<filename>` with the actual filename (e.g., `ralph-myrepo-feature-x.md`).
