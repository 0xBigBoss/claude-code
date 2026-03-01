---
description: Explain Ralph Reviewed and available commands
---

# Ralph Reviewed - Help

Ralph Reviewed is an iterative development loop with Codex review gates.

## How It Works

1. You start a loop with `/ralph-reviewed:ralph-loop "your task"`
2. Claude works on the task iteratively
3. When Claude claims completion, Codex reviews the work
4. If approved: loop ends
5. If rejected: Claude gets feedback and continues

## Commands

### `/ralph-reviewed:ralph-loop`

Start an iterative loop with review gates.

**Usage:**
```
/ralph-reviewed:ralph-loop "Your task description" [options]
```

**Options:**
- `--max-iterations <n>` - Max work iterations before auto-stop (default: 50)
- `--max-reviews <n>` - Max review cycles before force-complete (default: --max-iterations)
- `--completion-promise <text>` - Phrase that signals completion (default: COMPLETE)
- `--no-review` - Disable Codex review gate

**Examples:**
```
/ralph-reviewed:ralph-loop "Build a REST API with CRUD for todos. Include tests." --completion-promise "COMPLETE" --max-iterations 30

/ralph-reviewed:ralph-loop "Fix the authentication bug in src/auth.ts. Tests must pass." --max-reviews 2
```

### `/ralph-reviewed:cancel-ralph`

Cancel the active loop immediately.

### `/ralph-reviewed:help`

Show this help message.

## Troubleshooting

**Loop won't stop:**
- Use `/ralph-reviewed:cancel-ralph` to force stop
- Check that your completion promise matches exactly

**Codex not reviewing:**
- Ensure `codex` CLI is installed and authenticated
- Check that `--no-review` is not set

**Too many review cycles:**
- After max reviews, loop completes with a warning
- Reduce scope or clarify requirements in the task
