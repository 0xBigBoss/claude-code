---
allowed-tools: Bash(git:*), Bash(pwd:*), Bash(cat:*), Write
argument-hint: [optional focus area or additional notes]
description: Generate concise handoff summary with context
---

# Generate Teammate Handoff Prompt

Generate a prompt for handing off work to another AI agent (Codex, Claude Code) for code review and verification. The receiving agent has no context from this session, so the prompt must be self-contained and actionable.

## Git Context

**Working Directory**: !`pwd`

**Branch**: !`git branch --show-current 2>/dev/null || echo "detached/unknown"`

**Uncommitted changes**: !`git diff --stat 2>/dev/null || echo "None"`

**Staged changes**: !`git diff --cached --stat 2>/dev/null || echo "None"`

**Recent commits (last 4 hours)**: !`git log --oneline -5 --since="4 hours ago" 2>/dev/null || echo "None"`

## Session Context

Review the conversation history from this session to understand:
- What task was requested
- What approach was taken
- Any decisions made or tradeoffs discussed
- Known issues or incomplete items

## Additional Focus

$ARGUMENTS

## Task

Write a handoff prompt to `/tmp/handoff-<shortname>.md` where `<shortname>` is derived from the branch name or directory (e.g., `sen-69`, `fix-auth`, `api-refactor`).

The prompt must be standalone and actionable for an agent with zero prior context. Use this structure:

```
You are a senior engineer reviewing a teammate's work. Read, review, verify and test the changes.

## Context
[2-4 sentences: what was done, why, and the approach taken. Be specific enough that a fresh agent understands the scope.]

## Changes
[List key files modified with brief description of each change]

## Verification
[Specific commands to run: tests, linters, build, manual checks. Include expected outcomes.]

## Focus Areas
[What to look for: edge cases, potential issues, areas needing careful review. If user provided focus notes above, incorporate them here.]
```

After writing the file, copy to clipboard: `cat /tmp/handoff-<shortname>.md | pbcopy`

Confirm: "Handoff prompt copied to clipboard. Paste into your next agent session."
