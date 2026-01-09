---
description: Start a Codex handoff gate - generates handoff context and triggers Codex on exit
argument-hint: [optional focus area or additional notes]
allowed-tools: Bash(git:*), Bash(pwd:*), Bash(cat:*), Bash(head:*), Bash(grep:*), Bash(basename:*), Bash(mkdir:*), Bash(date:*), Write(**/.claude/codex-handoff.local.md), Read(~/.claude/handoffs/**), Read(**/.claude/codex-handoff.local.md)
---

# Start Codex Handoff Gate

Create a handoff gate that triggers Codex CLI when you exit. Codex will process the handoff and its output will be fed back to continue the session.

## Parse Arguments

Arguments: $ARGUMENTS

The entire argument string is the optional focus for the handoff. If empty, the handoff skill will determine appropriate framing based on session context.

## Step 0: Check for Existing Gate

**IMPORTANT**: Before creating a new gate, check if an ACTIVE one already exists:

```bash
# Check current repo and all ancestor superprojects for ACTIVE gate
DIR="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
FOUND_ACTIVE=""
while [ -n "$DIR" ]; do
  STATE_FILE="$DIR/.claude/codex-handoff.local.md"
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

**If an ACTIVE state file exists:**

The handoff gate is already active.

**ALLOWED when gate is active:**
- Regenerate the handoff file (`/handoff`) to capture your latest work

**FORBIDDEN when gate is active:**
- Writing to the state file (`.claude/codex-handoff.local.md`)

After optionally updating the handoff, output:
```
Handoff gate already active. Exiting to trigger Codex...
```

Then exit immediately. The stop hook will call Codex and feed the output back.

**Only proceed to Step 1 if no state file exists or `active: false`.**

## Step 1: Generate Handoff Context

Invoke the `/handoff` skill.

**If custom focus provided (from $ARGUMENTS):**
> Generate a handoff. {custom focus from arguments}

**Default focus (no arguments):**
> Generate a handoff for a teammate who will continue this work. Include context on what was done, current state, and next steps.

The handoff will be written to `~/.claude/handoffs/handoff-<repo>-<shortname>.md`.

---

## MANDATORY: Step 2 - Create State File

**CRITICAL: After the handoff is saved, you MUST continue with this step. The handoff gate is NOT active until the state file exists. Do not stop after the handoff.**

1. **Find the state directory** (git root, or cwd if not in a repo):
   ```bash
   STATE_DIR="$(git rev-parse --show-toplevel 2>/dev/null || pwd)/.claude"
   mkdir -p "$STATE_DIR"
   ```

2. **Create the state file** using the Write tool at `{STATE_DIR}/codex-handoff.local.md`:

```yaml
---
active: true
handoff_path: "~/.claude/handoffs/handoff-<repo>-<shortname>.md"
timestamp: "[current ISO timestamp]"
debug: false
---

# Codex Handoff Gate

Handoff gate active. Run `/codex-handoff:cancel` to abort.
```

**Important:**
- Use the actual handoff path from Step 1

---

## MANDATORY: Step 3 - Confirm and Exit

**CRITICAL: You MUST complete this step. Verify the state file was created, then exit.**

1. **Verify the state file exists**:
   ```bash
   cat "$(git rev-parse --show-toplevel 2>/dev/null || pwd)/.claude/codex-handoff.local.md" | head -5
   ```

2. **Output summary**:
   ```markdown
   ## Work Summary

   [2-3 bullet points of what was done]

   Handoff gate is now active. Exiting to trigger Codex...
   ```

3. **Exit** - The stop hook will:
   - Call Codex CLI with the handoff
   - Capture Codex output
   - Block exit with Codex output as feedback
   - Session resumes with Codex context

## Notes

- Codex processing can take 5-20+ minutes depending on complexity
- This is a one-shot gate - Codex runs once, then gate clears
- Use `/codex-handoff:cancel` to abort the handoff gate
- Debug logs at `~/.claude/codex-handoff/{session_id}/crash.log`
