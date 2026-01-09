# Cancel Codex Handoff Gate

Cancel an active Codex handoff gate.

## Instructions

1. **Find the state file** at `.claude/codex-handoff.local.md` in the git root (or cwd if not in a repo)

2. **Delete the state file** to deactivate the handoff gate

3. **Confirm cancellation** to the user

## Steps

```bash
# Find base directory (git root or cwd fallback)
BASE_DIR="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"

# Delete state file
rm -f "${BASE_DIR}/.claude/codex-handoff.local.md"
```

## Output

After deleting the state file, confirm:

```
Codex handoff gate cancelled. You can now exit normally without triggering Codex.
```

## Notes

- The next exit will proceed without Codex invocation
- To restart the handoff gate, run `/codex-handoff:handoff` again
