---
description: Generate handoff and start Ralph loop in one command
argument-hint: [completion criteria] [--max-iterations N] [--max-reviews N] [--no-review] [--debug]
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
- `--max-reviews 20`

## Workflow

### Step 1: Generate Handoff Context

Invoke the `/ralphoff` skill with HANDOFF_ARGS.

This will:
- Analyze the current session context
- Write a context file to `~/.claude/handoffs/ralph-<repo>-<shortname>-<timestamp>.md`
- Prepare the task description with success criteria and verification loops

**Important**: Note the exact filename created (e.g., `ralph-myrepo-feature-x-20260303-1430.md`).

---

### MANDATORY: Step 2 - Start Ralph Loop

**CRITICAL: After the handoff context is saved, you MUST continue with this step. The Ralph loop is NOT active until you invoke ralph-loop. Do not stop after the handoff.**

Invoke `/ralph-reviewed:ralph-loop` with:
- The task prompt: `Read ~/.claude/handoffs/<filename> and complete the task described there. Work through each step, verify with the "Done when" commands. Run .rl/rl done when all verifications pass, or .rl/rl done --blocked if stuck.`
- The parsed LOOP_FLAGS (or defaults: `--max-iterations 30 --max-reviews 20`)

---

### MANDATORY: Step 3 - Verify Loop Started

**CRITICAL: You MUST complete this step. Verify the loop state file was created.**

1. **Verify the loop is active**:
   ```bash
   .rl/rl status
   ```

2. If status shows active, begin working on the task immediately.

## Example Usage

```
/ralph                                        # Use session context, default settings
/ralph fix all type errors                    # With specific completion criteria
/ralph --max-iterations 50                    # Override iteration limit
/ralph --max-reviews 3                        # Limit review cycles
/ralph complete the refactor --no-review      # Skip Codex reviews
/ralph implement feature --debug              # Enable debug logging
```

## Output

After starting the loop, work begins immediately on the task from the handoff context.
