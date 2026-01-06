---
allowed-tools: Bash(*), Edit(~/.claude/handoffs/**)
argument-hint: [completion criteria] [--max-iterations N] [--max-reviews N] [--no-review] [--debug]
description: Generate Ralph-loop-ready handoff prompt
---

# Generate Ralph Loop Handoff Prompt

Generate a prompt for handing off work to a Ralph Reviewed loop (`/ralph-reviewed:ralph-loop`). The receiving session runs in an iterative self-improvement loop with Codex review gates until a completion promise is output and approved. The prompt must be self-contained, include clear success criteria, and support automatic verification.

## Parse Arguments

Arguments: $ARGUMENTS

Split arguments into two groups:
- **HANDOFF_ARGS**: Everything before any `--` flags (used as completion criteria)
- **LOOP_FLAGS**: Any `--max-iterations`, `--max-reviews`, `--no-review`, `--debug` flags (included in clipboard command)

Default loop flags for clipboard command if not specified:
- `--max-iterations 30`
- `--completion-promise "COMPLETE"`

## Git Context

**Working Directory**: !`pwd`

**Repository**: !`git rev-parse --show-toplevel 2>/dev/null || echo "Not a git repository"`

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

HANDOFF_ARGS (the completion criteria portion of $ARGUMENTS, excluding any `--` flags)

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
6. **State tracking** - Instruction to use TODO.md for cross-iteration memory and VCS visibility

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

<spec>
[OPTIONAL - Include ONLY if a spec, requirements doc, or acceptance criteria exists for this work.
Reference the spec file path and summarize key requirements. Examples:
- "See SPEC.md for full requirements. Key criteria: ..."
- "From issue #123: must support X, Y, Z"
- "Acceptance criteria from ticket: ..."
Omit this section entirely if no spec exists.]
</spec>

<iteration_state>
## State Tracking

Maintain a `TODO.md` file in the working directory as your working memory across iterations.

### TODO.md Format
```markdown
# TODO - [Brief Task Summary]

## Completed
- [x] What was done (iteration N)
- [x] Another completed item (iteration N)

## In Progress
- [ ] Currently working on

## Pending
- [ ] Next task
- [ ] Future task

## Blocked
- [ ] Issue preventing progress (if any)

## Notes
- Key decisions or observations
```

### Each Iteration Workflow
1. Read `TODO.md` for progress from previous iterations
2. Do work
3. Update `TODO.md` (mark completed, add new items discovered)
4. Commit code changes WITH `TODO.md` in the same commit
5. When done, output completion promise

### VCS Tracking
Commit `TODO.md` with each code change for iteration visibility. Never edit `.claude/ralph-loop.local.md` - it is managed by a Claude Code hook and should not be tracked in VCS.
</iteration_state>

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
4. Update TODO.md with current status
5. Commit changes (include TODO.md): `git add -A && git commit -m "..."`

When ALL verifications pass, output: <promise>COMPLETE</promise>
</verification_loop>

<if_stuck>
After 15+ iterations without progress:
- Update TODO.md "Blocked" section with:
  - What's preventing progress
  - Approaches attempted
  - Suggested alternative paths
- Commit the updated TODO.md
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

   /ralph-reviewed:ralph-loop "Read ~/.claude/handoffs/<filename> and complete the task. Output COMPLETE when done." --completion-promise "COMPLETE" <LOOP_FLAGS>
   ```

   Where `<LOOP_FLAGS>` includes any flags from $ARGUMENTS (e.g., `--max-iterations 50 --no-review`) or defaults to `--max-iterations 30`.

### Wrapper Command Format

The clipboard should contain ONLY this single-line command (no extra text):

```
/ralph-reviewed:ralph-loop "Read ~/.claude/handoffs/<filename> and complete the task described there. Follow the success criteria and verification loop. Output COMPLETE when all verifications pass, or BLOCKED if stuck after 15 iterations." --completion-promise "COMPLETE" <LOOP_FLAGS>
```

Replace:
- `<filename>` with the actual filename (e.g., `ralph-myrepo-feature-x.md`)
- `<LOOP_FLAGS>` with the parsed flags from $ARGUMENTS, or defaults (`--max-iterations 30`) if none provided

### Example Commands

```
# Default (30 iterations)
/ralph-reviewed:ralph-loop "Read ~/.claude/handoffs/ralph-myrepo-feature-x.md..." --completion-promise "COMPLETE" --max-iterations 30

# With custom flags from /ralphoff --max-iterations 50 --no-review
/ralph-reviewed:ralph-loop "Read ~/.claude/handoffs/ralph-myrepo-feature-x.md..." --completion-promise "COMPLETE" --max-iterations 50 --no-review

# With --debug flag
/ralph-reviewed:ralph-loop "Read ~/.claude/handoffs/ralph-myrepo-feature-x.md..." --completion-promise "COMPLETE" --max-iterations 30 --debug
```
