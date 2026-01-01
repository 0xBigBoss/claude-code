# Start Codex Review Gate

Create a review gate that triggers Codex CLI review when you exit.

## Instructions

1. **Ensure `.claude/` directory exists** at the git root (or cwd if not in a repo):
   ```bash
   mkdir -p "$(git rev-parse --show-toplevel 2>/dev/null || pwd)/.claude"
   ```

2. **Create the state file** at `.claude/codex-review.local.md`

3. **State file format:**
```yaml
---
active: true
task_description: |
  [Summarize the task/work completed - extract from conversation context]
files_changed: ["file1.ts", "file2.ts"]
review_count: 0
max_review_cycles: 5
review_history: []
timestamp: "[current ISO timestamp]"
debug: false
---

# Codex Review Gate

Review gate active. Run `/codex-reviewer:cancel` to abort.
```

4. **Populate task_description** from:
   - The original user request
   - Summary of work completed
   - Success criteria if mentioned

5. **Populate files_changed** with files you modified (check git status)

6. **Output a summary** of work completed for the user

7. **Exit** to trigger the review gate - the stop hook will intercept and call Codex

## Example

```markdown
## Work Summary

I've implemented the user authentication feature:
- Created `src/auth/jwt.ts` with token generation
- Added `src/middleware/auth.ts` for route protection
- Updated `src/routes/user.ts` with login/logout endpoints

Review gate is now active. Exiting to trigger Codex review...
```

Then exit. The stop hook will:
1. Call Codex CLI with the review prompt
2. If APPROVE: allow exit, clean up state
3. If REJECT: block exit, inject feedback for you to address

## Notes

- Codex review can take 5-20+ minutes depending on complexity
- Max 5 review cycles by default (configurable in state file)
- Use `/codex-reviewer:cancel` to abort the review gate
- Debug logs at `~/.claude/codex/{session_id}/crash.log`
