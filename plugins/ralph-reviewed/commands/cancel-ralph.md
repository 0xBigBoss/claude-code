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
test -f {GIT_ROOT}/.claude/ralph-loop.local.md && echo "found" || echo "not_found"
```

## If Found

1. Extract current iteration for reporting:
   ```bash
   cat {GIT_ROOT}/.claude/ralph-loop.local.md | grep "^iteration:" | cut -d' ' -f2
   ```

2. Extract review count:
   ```bash
   cat {GIT_ROOT}/.claude/ralph-loop.local.md | grep "^review_count:" | cut -d' ' -f2
   ```

3. Delete the state file:
   ```bash
   rm {GIT_ROOT}/.claude/ralph-loop.local.md
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
