---
description: Start a Codex review gate - generates handoff context for the reviewer
argument-hint: [review focus]
allowed-tools: Bash(git:*), Bash(pwd:*), Bash(cat:*), Bash(basename:*), Bash(mkdir:*), Bash(date:*), Write(**/.claude/codex-review.local.md), Read(~/.claude/handoffs/**), Read(**/.claude/codex-review.local.md)
---

# Start Codex Review Gate

Create a review gate that triggers Codex CLI review when you exit.

## Parse Arguments

Arguments: $ARGUMENTS

If arguments are provided, use them as the **review focus**. Otherwise use the default focus.

**Examples:**
- `/codex-reviewer:review` → default focus (verify changes and correctness)
- `/codex-reviewer:review "focus on security vulnerabilities"` → security review
- `/codex-reviewer:review "verify error handling and edge cases"` → error handling review

## Step 0: Check for Existing Gate

**IMPORTANT**: Before creating a new gate, check if one already exists:

```bash
STATE_FILE="$(git rev-parse --show-toplevel 2>/dev/null || pwd)/.claude/codex-review.local.md"
cat "$STATE_FILE" 2>/dev/null || echo "NO_STATE_FILE"
```

**If a state file exists with `active: true`:**

The review gate is already active.

**ALLOWED when gate is active:**
- Regenerate the handoff file (`/handoff`) to capture your latest work
- The handoff file at `~/.claude/handoffs/` can be updated freely

**FORBIDDEN when gate is active:**
- Writing to the state file (`.claude/codex-review.local.md`)
- Updating `review_count`, `review_history`, or `task_description`
- Any `cat >` or `Write` to `codex-review.local.md`

The stop hook owns all state file updates:
- It increments `review_count` after each Codex review
- It appends to `review_history` with Codex's feedback
- It manages the review cycle lifecycle

After updating the handoff (optional), output:
```
Review gate already active. Exiting to trigger next review cycle...
```

Then exit immediately. The stop hook will:
- Run Codex with the task description
- Update state file with review results
- APPROVE: exit succeeds, state file deleted
- REJECT: inject feedback, you continue working

**Only proceed to Step 1 if no state file exists or `active: false`.**

## Step 1: Generate Review Context

First, invoke the `/handoff` skill with the review focus.

**If custom focus provided (from $ARGUMENTS):**
> Generate a handoff for a code reviewer. {custom focus from arguments}

**Default focus (no arguments):**
> Generate a handoff for a code reviewer who will verify the changes made in this session. Focus on what was changed, why, and how to verify correctness.

The handoff will be written to `~/.claude/handoffs/handoff-<repo>-<shortname>.md` (where `<shortname>` is derived from the branch name).

## Step 2: Create State File

1. **Find the state directory** (git root, or cwd if not in a repo):
   ```bash
   STATE_DIR="$(git rev-parse --show-toplevel 2>/dev/null || pwd)/.claude"
   mkdir -p "$STATE_DIR"
   ```

2. **Note the handoff path** you just generated (e.g., `~/.claude/handoffs/handoff-<repo>-<shortname>.md`)

3. **Get files changed** from git:
   ```bash
   git status --porcelain
   ```

4. **Create the state file** at `{STATE_DIR}/codex-review.local.md`:

```yaml
---
active: true
handoff_path: "~/.claude/handoffs/handoff-<repo>-<shortname>.md"
task_description: null
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

**Important:** The `handoff_path` points to your handoff file. The stop hook reads this file at review time, so you can update the handoff between review cycles without touching the state file.

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
