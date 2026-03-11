---
name: writing-plans
description: Use when requirements are clear enough to plan and the work spans multiple steps, files, or verification stages
---

# Writing Plans

## Overview

Turn requirements into an executable plan with concrete files, tests, and verification. A good plan removes guesswork without pretending the implementation is already done.

**Core principle:** Every task should be specific enough that an engineer can execute it without inventing missing requirements.

## When to Use

Use this skill when:
- The task spans multiple files, phases, or checks
- Requirements are stable enough to plan
- The work benefits from a written execution order

Do not use this skill when:
- The change is small enough to track directly in `update_plan`
- Requirements are still ambiguous
- The user asked to implement immediately and the work is trivial

## Before Writing the Plan

1. Read the relevant code, docs, and existing specs.
2. Confirm the scope is one coherent unit of work.
3. Stop and clarify if the plan would depend on guessed requirements.

If the request covers multiple independent changes, split it into separate plans or clearly separated task groups.

## Plan Format

Save the plan where the user asked. If they did not specify a location, use:

`docs/plans/YYYY-MM-DD-<topic>.md`

Start with:

```markdown
# <Topic> Implementation Plan

**Goal:** <one sentence>
**Scope:** <what this plan covers>
**Non-goals:** <what this plan intentionally avoids>
**Risks:** <key technical or rollout risks>
```

Then include:

### Files
- Create: `path/to/new_file`
- Modify: `path/to/existing_file`
- Test: `path/to/test_file`

### Task N: <name>
- Outcome: <what is true when this task is done>
- Steps:
  - Write or update the failing test
  - Run the targeted check and confirm the expected failure
  - Implement the minimal change
  - Re-run targeted verification
  - Run broader regression checks if needed
- Verification:
  - `exact command`
  - expected result
- Dependencies:
  - `Task N-1` or `none`

## Planning Rules

- Use exact file paths.
- Prefer tasks that can be reviewed independently.
- Encode test-first thinking when the task changes runtime behavior.
- Include commands that can actually be run from the repo.
- Keep steps concrete: "add parser for X in `foo.ts`", not "improve parsing".
- Keep unrelated refactors out unless they are required to make the change safe.

## Execution Handoff

If the plan will be executed in the same session:
- Mirror the task list in `update_plan`
- Keep one task `in_progress`
- Revise the plan if implementation reveals real gaps

If the plan has independent sidecar work:
- Use `dispatching-parallel-agents` for bounded, non-overlapping subtasks

## Red Flags

- Plans that rely on tool names from another harness
- Tasks that touch the same files from multiple parallel workers
- Missing verification steps
- Hidden migrations, schema changes, or contract changes buried in generic wording
- Placeholder language like "update as needed" or "handle edge cases"
