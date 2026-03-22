---
description: Start Ralph Reviewed loop in current session
allowed-tools: Bash(rl:*), Bash(.rl/rl:*), Bash(bun:*), Bash(git:*), Bash(cat:*), Bash(command:*), Bash(mkdir:*)
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

1. Ensure the `rl` CLI is installed. If not on PATH, build from source:
   ```bash
   command -v rl >/dev/null 2>&1 || (
     echo "Installing rl CLI..." &&
     git clone https://github.com/0xbigboss/rl /tmp/rl-build 2>/dev/null &&
     cd /tmp/rl-build &&
     bun install --frozen-lockfile &&
     mkdir -p ~/.local/bin &&
     bun build src/cli.ts --compile --outfile ~/.local/bin/rl &&
     rm -rf /tmp/rl-build &&
     echo "rl installed to ~/.local/bin/rl"
   )
   ```
   Verify it's available:
   ```bash
   rl --version
   ```

2. Initialize the loop (creates `.rl/` with state.json, prompt.md, and `.rl/rl` wrapper):
   ```bash
   rl init "{PROMPT}" --max-iterations {MAX_ITERATIONS} --max-reviews {MAX_REVIEWS} {--no-review if set} {--debug if set}
   ```

3. Verify setup:
   ```bash
   .rl/rl status
   ```

All subsequent `rl` calls use `.rl/rl` (wrapper created by init).

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
