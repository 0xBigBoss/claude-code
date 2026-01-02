---
allowed-tools: Bash(git:*), Bash(pwd:*), Bash(cat:*), Bash(pbcopy:*), Bash(basename:*), Bash(mkdir:*), Edit(~/.claude/handoffs/**)
argument-hint: [optional focus area or additional notes]
description: Generate concise handoff summary with context
---

# Generate Teammate Handoff Prompt

Generate a prompt for handing off work to another AI agent (Codex, Claude Code). The receiving agent has no context from this session, so the prompt must be self-contained and actionable. This supports any follow-up: continuation, investigation, review, or exploration.

## Git Context

**Working Directory**: !`pwd`

**Repository**: !`git rev-parse --show-toplevel 2>/dev/null | xargs basename || echo "unknown"`

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
- Open questions or areas of uncertainty
- Known issues or incomplete items

## Additional Focus

$ARGUMENTS

## Task

Write a handoff prompt to `~/.claude/handoffs/handoff-<repo>-<shortname>.md` where `<repo>` is the repository name and `<shortname>` is derived from the branch name (e.g., `handoff-myapp-sen-69.md`, `handoff-api-fix-auth.md`). Copy to clipboard after writing.

The prompt must be standalone and actionable for an agent with zero prior context.

### Prompting Guidelines

Apply these when writing the handoff:
- **Be explicit and detailed** - include context on *why*, not just *what*
- **Use action-oriented language** - direct instructions like "Continue implementing..." not "Can you look at..."
- **Avoid negation** - frame positively (say what to do, not what to avoid)
- **Use XML tags** for clear section delimitation

### Role/Framing

Analyze the session to determine the best framing for the receiving agent:
- If the work needs **review**: use a reviewer role (e.g., "You are a senior engineer reviewing...")
- If the work needs **continuation**: use an implementer framing (e.g., "You are picking up implementation of...")
- If there's an **issue to investigate**: use a debugger framing (e.g., "You are investigating...")
- If **no specific role fits**: use neutral teammate framing (e.g., "You are picking up work from a teammate...")

Choose whichever produces the strongest, most actionable prompt for the situation.

### Output Structure

Use this XML-tagged structure:

```
<role>
[Your chosen framing based on session context - be specific about what the agent should do]
</role>

<context>
[2-4 sentences: what was being worked on, why, approach taken, key decisions made]
</context>

<current_state>
[What's done, what's in progress, what's blocked or uncertain]
</current_state>

<key_files>
[Files involved with brief descriptions of changes/relevance]
</key_files>

<next_steps>
[Action-oriented tasks for the receiving agent. Be specific. Examples:
- "Continue implementing the X feature by adding Y to Z file"
- "Review changes in A, B, C focusing on error handling"
- "Investigate why the build fails when running X command"]
</next_steps>
```

### Output Method

1. Ensure directory exists: `mkdir -p ~/.claude/handoffs`

2. Write the handoff prompt to `~/.claude/handoffs/handoff-<repo>-<shortname>.md` where:
   - `<repo>` is the repository basename
   - `<shortname>` is derived from the branch name (e.g., `handoff-myapp-sen-69.md`, `handoff-api-fix-auth.md`)

3. Copy to clipboard: `cat ~/.claude/handoffs/<filename> | pbcopy`

4. Confirm: "Handoff saved to ~/.claude/handoffs/<filename> and copied to clipboard."
