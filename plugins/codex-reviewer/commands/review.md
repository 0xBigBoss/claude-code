---
description: Start a Codex review gate - generates handoff context for the reviewer
argument-hint: ["review focus"] [--max-cycles N]
allowed-tools: Bash(git:*), Bash(pwd:*), Bash(cat:*), Bash(head:*), Bash(grep:*), Bash(basename:*), Bash(mkdir:*), Bash(date:*), Write(**/.claude/codex-review.local.md), Read(~/.claude/handoffs/**), Read(**/.claude/codex-review.local.md)
---

# Start Codex Review Gate

Create a review gate that triggers Codex CLI review when you exit.

## Parse Arguments

Arguments: $ARGUMENTS

Parse the following from arguments:
- **FOCUS**: Everything before the first `--` flag (the review focus)
- **--max-cycles**: Number (default: 10) - maximum review cycles before auto-approve

**Parsing rules:**
1. Text before any `--` flags is the review focus
2. Extract `--max-cycles N` if present (N must be a positive integer)
3. If no focus text provided, use the default focus

**Examples:**
- `/codex-reviewer:review` → default focus, max 10 cycles
- `/codex-reviewer:review "focus on security vulnerabilities"` → security review, max 10 cycles
- `/codex-reviewer:review --max-cycles 3` → default focus, max 3 cycles
- `/codex-reviewer:review "verify error handling" --max-cycles 10` → error handling review, max 10 cycles

## Step 0: Check for Existing Gate

**IMPORTANT**: Before creating a new gate, check if an ACTIVE one already exists. The stop hook checks the current repo AND walks up through all parent superprojects, looking for the first ACTIVE gate. An inactive file does not block - continue checking parents:

```bash
# Check current repo and all ancestor superprojects for ACTIVE gate
DIR="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
FOUND_ACTIVE=""
while [ -n "$DIR" ]; do
  STATE_FILE="$DIR/.claude/codex-review.local.md"
  if [ -f "$STATE_FILE" ] && grep -q "active: true" "$STATE_FILE"; then
    echo "Found ACTIVE state file at: $STATE_FILE"
    cat "$STATE_FILE"
    FOUND_ACTIVE="true"
    break
  fi
  # Check for parent superproject
  PARENT="$(git -C "$DIR" rev-parse --show-superproject-working-tree 2>/dev/null)"
  [ -z "$PARENT" ] && break
  DIR="$PARENT"
done
[ -z "$FOUND_ACTIVE" ] && echo "NO_ACTIVE_STATE_FILE"
```

**If an ACTIVE state file exists (in current repo OR any ancestor):**

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

Invoke the `/handoff` skill with the review focus.

**If custom focus provided (from $ARGUMENTS):**
> Generate a handoff for a code reviewer. {custom focus from arguments}

**Default focus (no arguments):**
> Generate a handoff for a code reviewer who will verify the changes made in this session. Focus on what was changed, why, and how to verify correctness.

The handoff will be written to `~/.claude/handoffs/handoff-<repo>-<shortname>.md`.

---

## MANDATORY: Step 2 - Create State File

**CRITICAL: After the handoff is saved, you MUST continue with this step. The review gate is NOT active until the state file exists. Do not stop after the handoff.**

1. **Find the state directory** (git root, or cwd if not in a repo):
   ```bash
   STATE_DIR="$(git rev-parse --show-toplevel 2>/dev/null || pwd)/.claude"
   mkdir -p "$STATE_DIR"
   ```

2. **Get files changed** from git:
   ```bash
   git status --porcelain
   ```

3. **Create the state file** using the Write tool at `{STATE_DIR}/codex-review.local.md`:

```yaml
---
active: true
handoff_path: "~/.claude/handoffs/handoff-<repo>-<shortname>.md"
task_description: null
files_changed: ["file1.ts", "file2.ts"]
review_count: 0
max_review_cycles: <parsed value or 10>
review_history: []
timestamp: "[current ISO timestamp]"
debug: false
---

# Codex Review Gate

Review gate active. Run `/codex-reviewer:cancel` to abort.
```

**Important:**
- Use the actual handoff path from Step 1
- Use the `--max-cycles` value if provided, otherwise default to 10
- The stop hook reads `handoff_path` at review time

---

## MANDATORY: Step 3 - Confirm and Exit

**CRITICAL: You MUST complete this step. Verify the state file was created, then exit.**

1. **Verify the state file exists**:
   ```bash
   cat "$(git rev-parse --show-toplevel 2>/dev/null || pwd)/.claude/codex-review.local.md" | head -5
   ```

2. **Output summary**:
   ```markdown
   ## Work Summary

   [2-3 bullet points of what was done]

   Review gate is now active. Exiting to trigger Codex review...
   ```

3. **Exit** - The stop hook will:
   - Call Codex CLI with the review prompt (using your handoff as context)
   - If APPROVE: allow exit, clean up state
   - If REJECT: block exit, inject feedback for you to address

## Notes

- Codex review can take 5-20+ minutes depending on complexity
- Max 10 review cycles by default; use `--max-cycles N` to customize
- Use `/codex-reviewer:cancel` to abort the review gate
- Debug logs at `~/.claude/codex/{session_id}/crash.log`
