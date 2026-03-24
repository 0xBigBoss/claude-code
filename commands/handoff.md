---
allowed-tools: Bash(git:*), Bash(pwd:*), Bash(cat:*), Bash(basename:*), Bash(mkdir:*), Bash(date:*), Write(~/.handoffs/**), Read(~/.handoffs/**)
argument-hint: [optional focus area or additional notes]
description: Generate concise handoff summary with context
---

# Generate Teammate Handoff Prompt

Generate a prompt for handing off work to another AI agent (Codex, Claude Code). The receiving agent has no context from this session, so the prompt must be self-contained and actionable.

## Git Context

**Working Directory**: !`pwd`

**Repository**: !`git rev-parse --show-toplevel 2>/dev/null || echo "Not a git repository"`

**Branch**: !`git branch --show-current 2>/dev/null || echo "N/A"`

**Uncommitted changes**: !`git diff --stat 2>/dev/null || echo "N/A"`

**Staged changes**: !`git diff --cached --stat 2>/dev/null || echo "N/A"`

**Recent commits (last 4 hours)**: !`git log --oneline -5 --since="4 hours ago" 2>/dev/null || echo "N/A"`

## Session Context

Review the conversation history from this session to understand:
- What task was requested and why
- What approach was taken
- Decisions made or tradeoffs discussed
- Current state: what's done, in progress, or blocked
- Known issues or incomplete items

## Additional Focus

$ARGUMENTS

## Task

Write a handoff prompt to `~/.handoffs/handoff-<repo>-<shortname>-<timestamp>.md` where:
- `<repo>` is the repository name (or directory basename if not a git repo)
- `<shortname>` is derived from the branch name, or use `main` if not in a git repo
- `<timestamp>` is the current date/time as `YYYYMMDD-HHMM` (e.g., `20260303-1430`)

Examples: `handoff-myapp-sen-69-20260303-1430.md`, `handoff-api-fix-auth-20260303-0915.md`

The prompt must be standalone and actionable for an agent with zero prior context.

### Core Principle

**Describe what the agent should type, not what process they should follow.** Include file paths, function names, commands, and concrete values. Don't describe architectures the agent can read from the code. Link to specs and docs instead of summarizing them.

### Prompting Guidelines

- **Be concrete over comprehensive** — file paths, function names, shell commands, specific values. Cut anything the agent can learn by reading the code.
- **Link, don't summarize** — "See `apps/gui-swift/SPEC.md` for requirements" beats 20 lines paraphrasing the spec. Only inline details the agent can't find in existing docs.
- **Include constraints** — "Only modify files under `apps/gui-swift/`" and "Do NOT modify `packages/core/`" prevent damage. State them directly.
- **Front-load the task** — the agent should know what to do after reading the first 10 lines.
- **Keep it short** — target 60-100 lines. The best handoffs are the shortest ones. If it's over 120 lines, you're probably summarizing things the agent can read themselves.

### Output Structure

Use plain markdown (not XML tags). Follow this structure:

```markdown
# [1-line task summary — what to do, not what role to play]

[2-4 sentences: what exists, why, key decisions already made]

## What's done

- [Bulleted list of completed work]

## What to do

### 1. [First concrete task]
[Details: file paths, function names, expected behavior, example values]

### 2. [Second concrete task]
[Details]

### 3. [Continue as needed]

## Key files

- `path/to/file.ts` — what it does / why it matters
- `path/to/other.ts` — what it does

## Spec

[OPTIONAL — include only if a spec exists. Link to the file, don't repeat its contents.]

## Verify

[Exact commands to run to confirm the work is done]
```bash
command-to-build
command-to-test
command-to-check-scope
```

## Gotchas

[OPTIONAL — things that will trip you up if you don't know them. Examples:
- "Pre-existing changes in `git stash@{0}` — pop after committing"
- "Tests need `@MainActor` annotation"
- "Build requires `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` prefix"
- "The daemon must be running for interactive testing"
Keep to 2-5 bullet points. Omit if nothing non-obvious.]

## Constraints

[OPTIONAL — hard boundaries. Examples:
- "Only modify files under `apps/gui-swift/`"
- "Do not modify `packages/core/` or `packages/proto/`"
- "macOS-only, Swift 6.2, SwiftPM"
Omit if no special constraints beyond normal development.]
```

### Anti-Patterns to Avoid

- **Prose architecture summaries** — if there's a README or SPEC, link it
- **"Read these files first" as a step** — key files section serves this purpose
- **Role paragraphs** — "You are a senior engineer..." doesn't help; a clear task summary does
- **Repeating spec contents** — link to the spec file instead
- **Process descriptions** — "apply the delivery flow gates" is vague; "write tests for X, then run `swift test`" is concrete
- **Over 120 lines** — if the handoff is this long, split into smaller handoffs or link to existing docs

### Output Method

1. Ensure directory exists: `mkdir -p ~/.handoffs`

2. Write the handoff prompt to `~/.handoffs/handoff-<repo>-<shortname>-<timestamp>.md`

3. Generate the timestamp using: `date +%Y%m%d-%H%M`

4. Confirm with the path: "Handoff saved to `~/.handoffs/<filename>`"
