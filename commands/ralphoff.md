---
allowed-tools: Bash(git:*), Bash(pwd:*), Bash(cat:*), Bash(pbcopy:*), Bash(basename:*), Bash(mkdir:*), Edit(~/.claude/handoffs/**)
argument-hint: [completion criteria or additional notes]
description: Generate Ralph-loop-ready handoff prompt
---

# Generate Ralph Loop Handoff Prompt

Generate a prompt for handing off work to a Ralph Wiggum loop (`/ralph-wiggum:ralph-loop`). The receiving session runs in an iterative self-improvement loop until a completion promise is output. The prompt must be self-contained, include clear success criteria, and support automatic verification.

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

Write a Ralph-loop handoff prompt to `~/.claude/handoffs/ralph-<repo>-<shortname>.md` where `<repo>` is the repository name and `<shortname>` is derived from the branch name (e.g., `ralph-myapp-sen-69.md`). Copy to clipboard after writing.

The prompt must work with `/ralph-wiggum:ralph-loop` and include everything needed for autonomous iteration.

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

2. Write the Ralph-loop prompt to `~/.claude/handoffs/ralph-<repo>-<shortname>.md` where:
   - `<repo>` is the repository basename
   - `<shortname>` is derived from the branch name (e.g., `ralph-myapp-sen-69.md`)

3. Copy to clipboard: `cat ~/.claude/handoffs/<filename> | pbcopy`

4. Confirm with usage instructions:
   ```
   Ralph-loop prompt saved to ~/.claude/handoffs/<filename> and copied to clipboard.

   To use in a new Claude Code session:
   1. Paste the prompt
   2. Run: /ralph-wiggum:ralph-loop --max-iterations 30 --completion-promise "COMPLETE"
   ```
