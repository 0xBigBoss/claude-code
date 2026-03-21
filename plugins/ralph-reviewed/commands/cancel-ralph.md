---
description: Cancel active Ralph Reviewed loop
allowed-tools: Bash(git:*), Bash(cat:*), Bash(rm:*), Bash(test:*)
---

# Cancel Ralph Reviewed Loop

Stop an active Ralph loop immediately.

## Find State File

Get git repository root (state file is at repo root):
```bash
git rev-parse --show-toplevel 2>/dev/null || pwd
```
Store this as GIT_ROOT.

## Check for Active Loop

```bash
test -f {GIT_ROOT}/.rl/state.json && echo "found" || echo "not_found"
```

## If Found

1. Read state for reporting:
   ```bash
   cat {GIT_ROOT}/.rl/state.json
   ```
   Extract `iteration` and `review_count` from the JSON.

2. Delete the state file:
   ```bash
   rm {GIT_ROOT}/.rl/state.json
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
