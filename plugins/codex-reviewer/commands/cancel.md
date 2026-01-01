# Cancel Codex Review Gate

Cancel an active Codex review gate.

## Instructions

1. **Find the state file** at `.claude/codex-review.local.md` in the git root (or cwd if not in a repo)

2. **Delete the state file** to deactivate the review gate

3. **Confirm cancellation** to the user

## Steps

```bash
# Find base directory (git root or cwd fallback)
BASE_DIR="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"

# Delete state file
rm -f "${BASE_DIR}/.claude/codex-review.local.md"
```

## Output

After deleting the state file, confirm:

```
Codex review gate cancelled. You can now exit normally without triggering a review.
```

## Notes

- The next exit will proceed without Codex review
- To restart the review gate, run `/codex-reviewer:review` again
