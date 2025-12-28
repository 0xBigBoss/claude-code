---
description: Cancel active Ralph Reviewed loop
allowed-tools: Bash(cat:*), Bash(rm:*), Bash(test:*)
---

# Cancel Ralph Reviewed Loop

Stop an active Ralph loop immediately.

## Check for Active Loop

```bash
test -f .claude/ralph-loop.local.md && echo "found" || echo "not_found"
```

## If Found

1. Extract current iteration for reporting:
   ```bash
   cat .claude/ralph-loop.local.md | grep "^iteration:" | cut -d' ' -f2
   ```

2. Extract review count:
   ```bash
   cat .claude/ralph-loop.local.md | grep "^review_count:" | cut -d' ' -f2
   ```

3. Delete the state file:
   ```bash
   rm .claude/ralph-loop.local.md
   ```

4. Report:
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
