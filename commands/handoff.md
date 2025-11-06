---
allowed-tools: Bash(git:*), Bash(pwd:*)
argument-hint: [optional focus area or additional notes]
description: Generate concise handoff summary with context
model: sonnet
---

# Handoff Summary

## Current Context

**Working Directory**: !`pwd`

**Git Status**: !`git status -sb`

**Recent Commits**: !`git log --oneline -5 2>/dev/null || echo "Not a git repo"`

**Uncommitted Changes**: !`git diff --stat HEAD 2>/dev/null || echo "No git changes"`

## Your Task

Create ultra-concise handoff. Sacrifice grammar for brevity. Use bullet points, fragments, abbreviations.

**CRITICAL**: Start with one-line summary capturing session essence (8-12 words max).

Focus on:
- **DONE**: Key accomplishments this session (2-3 bullets max)
- **STATE**: Current system state, key files changed
- **NEXT**: Pending work, blockers, decisions needed
- **NOTES**: Critical context or decisions (if any)

$ARGUMENTS

**Output format**:
```
## [One-line critical summary of session]

DONE:
- [accomplishment]
- [accomplishment]

STATE:
- [current state]
- [key changes]

NEXT:
- [pending item]
- [blocker/decision]

NOTES:
- [critical context if any]
```

Keep it under 200 words total. Omit sections if empty.
