---
description: Start Ralph Reviewed loop in current session
allowed-tools: Bash(rl:*), Bash(.rl/rl:*), Bash(bunx:*), Bash(npx:*), Bash(git:*), Bash(cat:*), Bash(command:*)
argument-hint: "task description" [--max-iterations N] [--max-reviews N] [--no-review] [--debug]
---

# Start Ralph Reviewed Loop

Initialize an iterative development loop with Codex review gates.

## Parse Arguments

Arguments: $ARGUMENTS

Parse the following from arguments:
- **PROMPT**: Everything before the first `--` flag (the task description)
- **--max-iterations**: Number (default: 30)
- **--max-reviews**: Number (optional, defaults to --max-iterations if not specified)
- **--no-review**: Boolean flag (default: false)
- **--debug**: Boolean flag (default: false)

## Setup

1. Locate the `rl` CLI — check if installed globally, fall back to bunx:
   ```bash
   command -v rl >/dev/null 2>&1 && echo "rl" || echo "bunx @0xbigboss/rl"
   ```
   Store the result as RL_CMD.

2. Initialize the loop (creates `.rl/` with state.json, prompt.md, and `.rl/rl` symlink):
   ```bash
   {RL_CMD} init "{PROMPT}" --max-iterations {MAX_ITERATIONS} --max-reviews {MAX_REVIEWS} {--no-review if set} {--debug if set}
   ```

3. Verify setup:
   ```bash
   .rl/rl status
   ```

All subsequent `rl` calls use `.rl/rl` (symlink created by init).

## Completion and Escape

- **Done:** run `.rl/rl done` — triggers Codex review on next stop.
- **Blocked:** run `.rl/rl done --blocked` — terminates without review.

## Working Guidelines

**Pacing.** Each iteration should produce thoughtful work. Researching, loading skills, and studying patterns IS productive — don't rush to `.rl/rl done`.

**Churn breaker.** If a reviewer flags the same area twice, your next iteration must be research — load skills, read docs, study the codebase. No code fix until you understand why the previous fix was wrong.

**Depth before breadth.** Complete each phase fully before starting the next.

**Skill loading.** Check `.claude/skills/` for relevant skills before writing code.

**Live verification.** Before claiming completion: run e2e/integration tests if they exist, boot the dev environment if available, or note the gap. Passing unit tests with a broken application is not done.

**Log progress** with `.rl/rl`:
- `.rl/rl log phase "starting migration"` — new phase
- `.rl/rl log commit <sha> "summary"` — after commits
- `.rl/rl log decision "chose X because..."` — design decisions
- `.rl/rl log summary "status update"` — every ~5 iterations

---

Begin working on the task. The stop hook handles iteration logic automatically.
