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
- **LOOP_FLAGS**: Any `--max-iterations`, `--max-reviews`, `--completion-promise`, `--no-review`, `--debug` flags (passed to ralph-loop)

Default loop flags if not specified:
- `--max-iterations 15`
- `--max-reviews 10`
- `--completion-promise "COMPLETE"`

## Workflow

### Step 1: Generate Handoff Context

Invoke the `/ralphoff` skill with HANDOFF_ARGS.

This will:
- Analyze the current session context
- Write a context file to `~/.claude/handoffs/ralph-<repo>-<shortname>.md`
- Prepare the task description with success criteria and verification loops

**Important**: Note the exact filename created (e.g., `ralph-myrepo-feature-x.md`).

---

### MANDATORY: Step 2 - Start Ralph Loop

**CRITICAL: After the handoff context is saved, you MUST continue with this step. The Ralph loop is NOT active until you invoke ralph-loop. Do not stop after the handoff.**

Invoke `/ralph-reviewed:ralph-loop` with:
- The task prompt: `Read ~/.claude/handoffs/<filename> and complete the task described there. Follow the success criteria and verification loop. Output COMPLETE when all verifications pass, or BLOCKED if stuck after 15 iterations.`
- The parsed LOOP_FLAGS (or defaults: `--max-iterations 15 --max-reviews 10 --completion-promise "COMPLETE"`)

---

### MANDATORY: Step 3 - Verify Loop Started

**CRITICAL: You MUST complete this step. Verify the loop state file was created.**

1. **Verify the state file exists**:
   ```bash
   cat "$(git rev-parse --show-toplevel 2>/dev/null || pwd)/.claude/ralph-loop.local.md" | head -5
   ```

2. If the state file exists, the loop is active. Begin working on the task immediately.

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
