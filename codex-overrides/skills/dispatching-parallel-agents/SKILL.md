---
name: dispatching-parallel-agents
description: Use when there are multiple independent subtasks that can progress in parallel without overlapping ownership or blocking the next local step
---

# Dispatching Parallel Agents

## Overview

Use Codex subagents to accelerate sidecar work, not to outsource thinking on the critical path.

**Core principle:** Keep the next blocking step local. Delegate bounded work that can run in parallel without shared write ownership.

## When to Use

Use this skill when:
- There are 2 or more independent questions or implementation slices
- One subtask does not need the result of another
- You can assign clear file or responsibility boundaries

Do not use this skill when:
- The next action is blocked on the delegated result
- Multiple agents would need to edit the same files
- The problem is still too unclear to split safely

## Agent Types

- `explorer`: focused codebase questions, read-only analysis, fast context gathering
- `worker`: implementation or fixes with explicit file ownership

## Workflow

1. Decide the immediate local step first.
2. Identify sidecar tasks that are concrete, independent, and useful.
3. Give each agent one clear responsibility.
4. State file ownership for code changes.
5. Continue local work immediately instead of waiting by reflex.
6. Integrate results only after reviewing what changed.

## Good Delegation Units

- "Inspect how config is loaded in `bin/bin/claude-bootstrap` and report the relevant call chain"
- "Add tests for `scripts/sync-codex.sh`; worker owns new test fixture files only"
- "Draft Codex-native replacement text for one skill directory"

## Bad Delegation Units

- "Figure out the whole feature"
- "Fix everything failing"
- Two workers editing the same module tree
- Delegating a task and then idling until it returns

## Prompt Ingredients

Every spawned agent should get:
- The exact goal
- The reason this subtask matters
- Ownership boundaries
- Constraints
- The output you need back

For workers, explicitly say:
- which files or module they own
- that they are not alone in the codebase
- that they must not revert unrelated changes

## Integration Rules

- Prefer a few high-quality agents over many vague ones.
- Do not duplicate delegated work locally.
- Use `wait` only when the result is needed now.
- Close finished agents you no longer need.
- Re-run verification after integrating worker output.

## Red Flags

- Delegating the very next blocker and then stalling
- Overlapping write scopes
- Repeatedly spawning agents to compensate for a vague prompt
- Trusting agent success claims without local verification
- Parallelizing work that is actually one coupled change
