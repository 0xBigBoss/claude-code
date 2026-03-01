---
description: Start Ralph Reviewed loop in current session
allowed-tools: Bash(git:*), Bash(mkdir:*), Bash(date:*), Bash(cat:*), Write(**/ralph-loop.local.md)
argument-hint: "task description" [--max-iterations N] [--max-reviews N] [--completion-promise TEXT] [--no-review] [--debug]
---

# Start Ralph Reviewed Loop

Initialize an iterative development loop with Codex review gates.

## Parse Arguments

Arguments: $ARGUMENTS

Parse the following from arguments:
- **PROMPT**: Everything before the first `--` flag (the task description)
- **--max-iterations**: Number (default: 50)
- **--max-reviews**: Number (optional, defaults to --max-iterations if not specified)
- **--completion-promise**: String (default: "COMPLETE")
- **--no-review**: Boolean flag (default: false)
- **--debug**: Boolean flag (default: false) - writes debug logs to ~/.claude/ralphs/{session_id}/debug.log

## Setup

1. Get git repository root (state file must be at repo root to survive directory changes):
   ```bash
   git rev-parse --show-toplevel
   ```
   Store this as GIT_ROOT. If not in a git repo, use current directory.

2. Create state directory at repo root:
   ```bash
   mkdir -p {GIT_ROOT}/.claude
   ```

3. Generate timestamp:
   ```bash
   date -u +"%Y-%m-%dT%H:%M:%SZ"
   ```

4. Write the state file to `{GIT_ROOT}/.claude/ralph-loop.local.md`:

```markdown
---
active: true
iteration: 0
max_iterations: {MAX_ITERATIONS}
completion_promise: "{COMPLETION_PROMISE}"
original_prompt: |
  {PROMPT}
timestamp: "{TIMESTAMP}"
review_enabled: {true unless --no-review}
review_count: 0
max_review_cycles: {MAX_REVIEWS}
pending_feedback: null
debug: {true if --debug, else false}
---
```

## Confirmation Output

After creating the state file, output:

```
Ralph Reviewed loop started.

Task: {first 100 chars of PROMPT}...

Configuration:
- Max iterations: {MAX_ITERATIONS}
- Max review cycles: {MAX_REVIEWS}
- Completion promise: {COMPLETION_PROMISE}
- Review enabled: {yes/no}
- Debug: {yes/no} (logs to ~/.claude/ralphs/{session_id}/debug.log)

The stop hook will now intercept exit attempts. When you believe the task is complete, output:

<promise>{COMPLETION_PROMISE}</promise>

Your work will be reviewed by Codex before the loop can end.

---

Beginning work on task...
```

## Completion and Escape

- When the task is done, output `<promise>{COMPLETION_PROMISE}</promise>` — triggers Codex review before the loop ends.
- If genuinely blocked (missing dependency, impossible constraint), document the blocker and output `<promise>BLOCKED</promise>` — terminates the loop without review.

## Begin Working

After setup, immediately begin working on the task described in PROMPT. The stop hook handles iteration logic automatically.
