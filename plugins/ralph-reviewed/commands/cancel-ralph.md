---
description: Cancel active Ralph Reviewed loop
allowed-tools: Bash(rl:*), Bash(.rl/rl:*), Bash(git:*), Bash(rm:*), Bash(test:*)
---

# Cancel Ralph Reviewed Loop

Stop an active Ralph loop immediately.

## Check for Active Loop

```bash
rl status --json 2>/dev/null || .rl/rl status --json 2>/dev/null || echo '{"error": "no loop"}'
```

## If Active

1. Note the iteration and review count from the status output.

2. Delete the state file to end the loop:
   ```bash
   rm "$(git rev-parse --show-toplevel 2>/dev/null || pwd)/.rl/state.json"
   ```

3. Report:
   ```
   Cancelled Ralph Reviewed loop.
   - Was at iteration: {N}
   - Review cycles used: {M}

   You can now exit normally.
   ```

## If Not Found

Report:
```
No active Ralph loop found.
```
