---
description: Start a Codex review gate - generates handoff context for the reviewer
allowed-tools: Bash(git:*), Bash(pwd:*), Bash(cat:*), Bash(basename:*), Bash(mkdir:*), Bash(date:*), Write(**/.claude/codex-review.local.md), Read(~/.claude/handoffs/**), Read(**/.claude/codex-review.local.md)
---

# Start Codex Review Gate

Create a review gate that triggers Codex CLI review when you exit.

## Step 0: Check for Existing Gate

**IMPORTANT**: Before creating a new gate, check if one already exists:

```bash
STATE_FILE="$(git rev-parse --show-toplevel 2>/dev/null || pwd)/.claude/codex-review.local.md"
cat "$STATE_FILE" 2>/dev/null || echo "NO_STATE_FILE"
```

**If a state file exists with `active: true`:**

The review gate is already active. Do NOT create a new one - that would reset the review count!

Simply output:
```
Review gate already active. Exiting to trigger next review cycle...
```

Then exit. The stop hook will automatically run Codex and either:
- APPROVE: exit succeeds
- REJECT: you receive feedback and continue working

**Only proceed to Step 1 if no state file exists or `active: false`.**

## Step 1: Generate Review Context

First, invoke the `/handoff` skill with this focus:

> Generate a handoff for a code reviewer who will verify the changes made in this session. Focus on what was changed, why, and how to verify correctness.

The handoff will be written to `~/.claude/handoffs/handoff-<repo>-<shortname>.md` (where `<shortname>` is derived from the branch name).

## Step 2: Create State File

1. **Find the state directory** (git root, or cwd if not in a repo):
   ```bash
   STATE_DIR="$(git rev-parse --show-toplevel 2>/dev/null || pwd)/.claude"
   mkdir -p "$STATE_DIR"
   ```

2. **Read the handoff** you just generated from `~/.claude/handoffs/handoff-<repo>-<shortname>.md`

3. **Get files changed** from git:
   ```bash
   git status --porcelain
   ```

4. **Create the state file** at `{STATE_DIR}/codex-review.local.md`:

```yaml
---
active: true
task_description: |
  [PASTE THE ENTIRE HANDOFF CONTENT HERE - all XML sections]
files_changed: ["file1.ts", "file2.ts"]
review_count: 0
max_review_cycles: 5
review_history: []
timestamp: "[current ISO timestamp]"
debug: false
---

# Codex Review Gate

Review gate active. Run `/codex-reviewer:cancel` to abort.
```

The `task_description` should contain the FULL handoff with all sections:
- `<role>` - reviewer framing
- `<context>` - what was done and why
- `<current_state>` - completion status
- `<key_files>` - files changed with descriptions
- `<next_steps>` - what the reviewer should verify

This gives Codex rich context about the work, not just a summary.

## Step 3: Confirm and Exit

Output a brief summary for the user:

```markdown
## Work Summary

[2-3 bullet points of what was done]

Review gate is now active. Exiting to trigger Codex review...
```

Then exit. The stop hook will:
1. Call Codex CLI with the review prompt (using your handoff as context)
2. If APPROVE: allow exit, clean up state
3. If REJECT: block exit, inject feedback for you to address

## Notes

- Codex review can take 5-20+ minutes depending on complexity
- Max 5 review cycles by default (configurable in state file)
- Use `/codex-reviewer:cancel` to abort the review gate
- Debug logs at `~/.claude/codex/{session_id}/crash.log`
