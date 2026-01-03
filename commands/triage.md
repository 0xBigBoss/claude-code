---
allowed-tools: Bash(linear:*), Task
argument-hint: [--team TEAM] [--codebase PATH] [--state STATE]
description: Interactive Linear issue triage with codebase verification. Lists issues, verifies implementation status via Explore agents, and updates issue states.
---

# Linear Issue Triage

Interactive triage workflow for Linear issues. Syncs issue states with actual implementation status in the codebase.

## Arguments

Parse `$ARGUMENTS` for:
- `--team TEAM` - Team key (default: from Linear CLI config)
- `--codebase PATH` - Default codebase path for verification
- `--state STATE` - Issue state filter: `in_progress` (default), `backlog`, `todo`, or `all`

Arguments: $ARGUMENTS

## Phase 1: Gather Issues

Fetch issues assigned to the current user:

```bash
linear issues list --team TEAM --assignee me --state-type started --include-projects --human-time --all
```

If `--state all` was specified, also fetch backlog and todo:
```bash
linear issues list --team TEAM --assignee me --state-type unstarted --include-projects --human-time --all
```

## Phase 2: Present Summary

Group issues by project and display:
- Issue count per project
- High priority items (P0, P1, P2) highlighted
- Issues without projects (orphans)

Format as a scannable table:
```
| ID | Title | State | Priority | Project | Updated |
```

## Phase 3: Interactive Triage

For each issue (or batch selected by user), offer these actions via AskUserQuestion:

### Verification Options
- **Verify in codebase** - Spawn Explore agent to check implementation
- **Mark done** - Issue is complete
- **Mark canceled** - Issue is no longer needed
- **Move to backlog** - Deprioritize
- **Skip** - No action needed
- **Set blocker** - This issue blocks another

### Codebase Verification

When user selects "Verify in codebase":

1. Ask which codebase to check (use `--codebase` default if provided)
2. Fetch issue details:
   ```bash
   linear issue view ISSUE_ID --fields identifier,title,description,comments --json
   ```
3. Spawn Explore agent with Task tool:
   ```
   subagent_type: Explore
   prompt: |
     Check if Linear issue ISSUE_ID is implemented in CODEBASE_PATH.

     Issue: TITLE
     Description: DESCRIPTION

     Look for:
     - Code implementing this feature/fix
     - Tests covering the functionality
     - Any TODOs or incomplete work

     Report:
     - Implementation status: complete / partial / not started
     - Key files found
     - Evidence summary
   ```
4. Based on findings, propose state change and ask for confirmation

### State Updates

Apply confirmed state changes:
```bash
linear issue update ISSUE_ID --state STATE_NAME --yes
```

Common states:
- `Done` - Implementation complete
- `Canceled` - No longer needed
- `Backlog` - Deprioritized
- `In Progress` - Actively working

### Creating Blockers

When user selects "Set blocker":
1. Ask which issue this one blocks
2. Create the relationship:
   ```bash
   linear issue link ISSUE_ID --blocks OTHER_ID --yes
   ```

### Moving to Project

If issue has no project and user wants to assign one:
1. List available projects:
   ```bash
   linear projects list --team TEAM --json
   ```
2. Ask user to select project
3. Add issue to project:
   ```bash
   linear project add-issue PROJECT_UUID ISSUE_UUID --yes
   ```

## Phase 4: Summary

After processing all issues, display:
- Issues marked done
- Issues canceled
- Issues moved to backlog
- Blocker relationships created
- Project assignments made
- Remaining in-progress count

## Workflow Tips

- Process high-priority issues first
- Batch similar issues (same feature area) for efficiency
- When verification finds partial implementation, ask if user wants to create a follow-up issue
- For orphan issues, suggest appropriate projects based on issue content

## Example Session

```
Triage: 14 in-progress issues for SEND team

By Project:
  Canton Wallet (5): SEND-201, SEND-203, SEND-205, SEND-207, SEND-209
  Localnet (3): SEND-210, SEND-211, SEND-212
  No Project (6): SEND-213, SEND-214, SEND-215, SEND-216, SEND-217, SEND-218

High Priority:
  P1: SEND-201 - Fix wallet connection timeout
  P2: SEND-210 - Update localnet config

Select issues to triage: [all] [by project] [high priority only] [specific IDs]
```
