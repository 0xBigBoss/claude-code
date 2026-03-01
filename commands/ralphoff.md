---
allowed-tools: Bash(git:*), Bash(pwd:*), Bash(cat:*), Bash(basename:*), Bash(mkdir:*), Write(~/.claude/handoffs/**), Read(~/.claude/handoffs/**)
argument-hint: [completion criteria] [--max-iterations N] [--max-reviews N] [--no-review] [--debug]
description: Generate Ralph-loop-ready handoff prompt
---

# Generate Ralph Loop Handoff Prompt

Generate a prompt for handing off work to a Ralph Reviewed loop (`/ralph-reviewed:ralph-loop`). The receiving session runs in an iterative self-improvement loop with Codex review gates. The prompt must be self-contained, include clear success criteria, and support automatic verification.

## Parse Arguments

Arguments: $ARGUMENTS

Split arguments into two groups:
- **HANDOFF_ARGS**: Everything before any `--` flags (used as completion criteria)
- **LOOP_FLAGS**: Any `--max-iterations`, `--max-reviews`, `--no-review`, `--debug` flags (passed to ralph-loop)

Default loop flags if not specified:
- `--max-iterations 30`
- `--completion-promise "COMPLETE"`

## Git Context

**Working Directory**: !`pwd`

**Repository**: !`git rev-parse --show-toplevel 2>/dev/null || echo "Not a git repository"`

**Branch**: !`git branch --show-current 2>/dev/null || echo "detached/unknown"`

**Uncommitted changes**: !`git diff --stat 2>/dev/null || echo "None"`

**Staged changes**: !`git diff --cached --stat 2>/dev/null || echo "None"`

**Recent commits (last 4 hours)**: !`git log --oneline -5 --since="4 hours ago" 2>/dev/null || echo "None"`

## Session Context

Review the conversation history from this session to understand:
- What task was requested and why
- What approach was taken
- Decisions made or tradeoffs discussed
- Current state: what's done, in progress, or blocked
- What verification exists (tests, linters, type checks, builds)
- Known issues or incomplete items

## Additional Focus / Completion Criteria

HANDOFF_ARGS (the completion criteria portion of $ARGUMENTS, excluding any `--` flags)

## Task

Write a Ralph-loop context file to `~/.claude/handoffs/ralph-<repo>-<shortname>.md` where `<repo>` is the repository name and `<shortname>` is derived from the branch name (e.g., `ralph-myapp-sen-69.md`).

### Core Principle

**A ralph handoff is just a handoff with verification commands.** Apply the same principles as `/handoff`: describe what to type, be concrete, link don't summarize, keep it short. The ralph-loop runner handles iteration state, TODO.md tracking, BLOCKED escapes, and completion promises — don't duplicate that machinery in the handoff.

### What belongs in the ralph handoff (task-specific)

- What to build/fix/implement — concrete steps with file paths and function names
- How to verify it's done — exact shell commands
- Task-specific gotchas and fallback strategies
- Constraints and scope boundaries

### What does NOT belong (handled by ralph-loop runner)

- TODO.md format or iteration workflow instructions
- Generic "if stuck, document the blocker" guidance
- Completion promise syntax (`<promise>COMPLETE</promise>`)
- State tracking file management
- Generic BLOCKED escape conditions

### Prompting Guidelines

- **Be concrete over comprehensive** — file paths, function names, shell commands, specific values
- **Link, don't summarize** — "See `SPEC.md` for requirements" beats paraphrasing the spec
- **Include constraints** — "Only modify files under `src/`" and "Do NOT modify `packages/core/`"
- **Merge criteria and verification** — don't list success criteria separately from verification commands. One section: "Done when these commands all pass."
- **Front-load the task** — the agent should know what to do after reading the first 10 lines
- **Keep it proportional** — single-phase tasks: 60-100 lines. Multi-phase (3+): up to 200. Over 200 means you're probably summarizing things the agent can read themselves.

### Output Structure

Use plain markdown (not XML tags):

```markdown
# [1-line task summary]

[2-4 sentences: what exists, why, key decisions already made]

## What to do

### 1. [First concrete task]
[Details: file paths, function names, expected behavior, code snippets if helpful]

### 2. [Second concrete task]
[Details]

### 3. [Continue as needed]

## Key files

- `path/to/file.ts` — what it does / why it matters

## Spec

[OPTIONAL — link to spec file, don't repeat its contents]

## Done when

All of these pass:
```bash
command-to-build
command-to-test
command-to-check-scope
```
[Plus any non-command criteria like "E2E tests exist for each waitFor state"]

## Gotchas

[OPTIONAL — things that will trip you up:
- "Build requires `DEVELOPER_DIR=...` prefix"
- "Pre-existing changes in git stash — pop after committing"
Keep to 2-5 bullets. Omit if nothing non-obvious.]

## Constraints

[OPTIONAL — hard boundaries:
- "Only modify files under `apps/gui-swift/`"
- "Do not modify `packages/core/`"
Omit if no special constraints.]

## Fallbacks

[OPTIONAL — task-specific escape hatches for if a phase is genuinely blocked:
- "Phase 6: If native screenshot module won't compile, keep JS-based capture"
- "If sandbox blocks module cache writes, pass `-Xcc -fmodules-cache-path=/tmp/mc`"
Only include if there are known risk areas. Omit for straightforward tasks.]
```

### Anti-Patterns to Avoid

- **Duplicating ralph-loop runner instructions** — TODO.md format, iteration workflow, BLOCKED syntax, completion promise format. The runner handles all of this.
- **Separate success criteria and verification sections** — merge them into "Done when"
- **Generic "if stuck" instructions** — only include task-specific fallback strategies
- **Prose architecture summaries** — link to README or SPEC
- **Over 200 lines** — if it's this long, split into smaller tasks or link to existing docs

### Output Method

1. Ensure directory exists: `mkdir -p ~/.claude/handoffs`

2. Write the Ralph-loop context file to `~/.claude/handoffs/ralph-<repo>-<shortname>.md`

3. Confirm with the path: "Ralph-loop context saved to `~/.claude/handoffs/<filename>`"

### Wrapper Command Format

When using this context file with `/ralph-reviewed:ralph-loop`, the command format is:

```
/ralph-reviewed:ralph-loop "Read ~/.claude/handoffs/<filename> and complete the task described there. Follow the success criteria and verification loop. Output COMPLETE when all verifications pass, or BLOCKED if stuck after 15 iterations." --completion-promise "COMPLETE" <LOOP_FLAGS>
```
