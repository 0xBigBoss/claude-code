---
description: Generate handoff and start Ralph loop in one command
argument-hint: [completion criteria or additional notes] [--max-iterations N] [--no-review]
---

# Ralph: Handoff + Loop Combined

Chain `/ralphoff` and `/ralph-reviewed:ralph-loop` into a single workflow.

## Parse Arguments

Arguments: $ARGUMENTS

Split arguments into two groups:
- **HANDOFF_ARGS**: Everything before any `--` flags (passed to ralphoff as completion criteria)
- **LOOP_FLAGS**: Any `--max-iterations`, `--max-reviews`, `--no-review`, `--debug` flags (passed to ralph-loop)

Default loop flags if not specified:
- `--max-iterations 30`
- `--completion-promise "COMPLETE"`

## Workflow

### Step 1: Generate Handoff Context

Invoke the `/ralphoff` skill with HANDOFF_ARGS.

This will:
- Analyze the current session context
- Write a context file to `~/.claude/handoffs/ralph-<repo>-<shortname>.md`
- Prepare the task description with success criteria and verification loops

**Important**: After ralphoff completes, note the exact filename it created (e.g., `ralph-myrepo-feature-x.md`).

### Step 2: Start Ralph Loop

Immediately invoke `/ralph-reviewed:ralph-loop` with:
- The task prompt: `Read ~/.claude/handoffs/<filename> and complete the task described there. Follow the success criteria and verification loop. Output COMPLETE when all verifications pass, or BLOCKED if stuck after 15 iterations.`
- The parsed LOOP_FLAGS

Do NOT copy the command to clipboard (skip that part of ralphoff) - we're starting the loop directly.

## Example Usage

```
/ralph                           # Use session context, default settings
/ralph fix all type errors       # With specific completion criteria
/ralph --max-iterations 50       # Override iteration limit
/ralph complete the refactor --no-review --debug  # With criteria and flags
```

## Output

After starting the loop, work begins immediately on the task from the handoff context.
