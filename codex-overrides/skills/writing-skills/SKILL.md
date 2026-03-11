---
name: writing-skills
description: Use when creating or editing a skill and you need it to be discoverable, concise, and native to the target harness
---

# Writing Skills

## Overview

A skill should capture reusable judgment, not a story about one session.

**Core principle:** Write the minimum instructions that reliably change future agent behavior on the right class of tasks.

## Directory Choice

Choose the source of truth before editing:

- Shared skill source: edit the repo-managed Claude skill, not the generated runtime copy
- Codex-only adaptation: edit the repo-managed Codex override, not the generated runtime copy

In this dotfiles setup, those live under:
- `claude-code/.claude/skills/<skill-name>/`
- `claude-code/codex-overrides/skills/<skill-name>/`

Use a Codex override when the upstream shared skill exists but its workflow or wording does not cleanly fit Codex.

## When to Create a Skill

Create or update a skill when:
- The technique is reusable across tasks
- The agent repeatedly misses the same judgment call
- A short document can prevent recurring mistakes

Do not create a skill for:
- One-off project context
- Purely mechanical rules that should be enforced by code or linting
- Content that belongs in repo instructions instead

## Structure

Each skill directory should stay small:

```text
skill-name/
  SKILL.md
  supporting-file.md   # only when needed
```

Prefer one concise `SKILL.md`. Add supporting files only for heavy reference material.

## Metadata Rules

Frontmatter supports only:
- `name`
- `description`

Description rules:
- Start with `Use when...`
- Describe triggering conditions, not the workflow
- Stay specific enough for discovery
- Avoid harness-specific claims unless the skill is intentionally harness-specific

## Authoring Rules

- Keep the workflow native to the target harness.
- Name real tools and files the agent actually has.
- Prefer concrete triggers over broad abstractions.
- Cut repeated explanations aggressively.
- Include red flags when the failure mode is predictable.

## Testing the Skill

Validate the skill against realistic tasks:

1. Observe baseline behavior on a representative request.
2. Write or revise the skill to address the real failure.
3. Re-run the task and compare behavior.
4. Tighten wording only where the skill still leaves loopholes.

Use subagents for testing only when they add signal. They are optional, not the point.

## Red Flags

- Descriptions that summarize the full workflow
- Instructions referencing tools unavailable in the target harness
- Long examples that restate the same rule
- Skills that duplicate repo-level policy
