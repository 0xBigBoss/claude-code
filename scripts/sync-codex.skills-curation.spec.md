# Codex Skill Curation Spec

## Overview

`sync-codex.sh` syncs Claude-owned commands and skills into the Codex runtime tree. For commands, a direct copy is correct. For skills, a direct copy is only correct when the source skill's workflow matches Codex's actual tool and collaboration model.

This spec defines how Codex skill sync is curated without mutating upstream Claude plugin content. The goal is to keep Codex's synced skill set useful and accurate while preserving a clean upgrade path for upstream Claude skills.

## Problem

The current sync pipeline copies every discovered Claude user skill and plugin skill into `codex/.codex/skills`. That creates three classes of problems:

1. Some skills encode durable engineering discipline and work in both harnesses.
2. Some skills encode Claude-specific control-plane concepts such as `Skill`, `Task`, `TodoWrite`, or Claude-specific reviewer flows.
3. Some skills are worth keeping in Codex only after a Codex-native rewrite.

Blind copying causes Codex to receive instructions that describe tools or workflows it does not actually provide.

## Goals

- `REQ-1`: Allow Codex skill sync to exclude specific upstream plugin skills that are not suitable for Codex.
- `REQ-2`: Allow Codex to replace synced upstream skills with checked-in Codex-only overrides.
- `REQ-3`: Keep curation logic colocated with `sync-codex.sh` so behavior is discoverable and reviewable.
- `REQ-4`: Preserve current behavior for commands and for skills that are not explicitly curated.
- `REQ-5`: Keep the sync idempotent and compatible with `--check`, `--dry-run`, and prune workflows.

## Non-Goals

- `NONGOAL-1`: Rewriting every existing Claude skill in this change.
- `NONGOAL-2`: Changing Claude runtime behavior or upstream plugin contents.
- `NONGOAL-3`: Building a generalized policy engine for every possible source type.

## Invariants

- `INV-1`: Upstream plugin caches remain read-only inputs.
- `INV-2`: Codex-only overrides are source-controlled in this repo and applied after all upstream copies.
- `INV-3`: A skill omitted by policy is treated as intentionally unmanaged for Codex sync.
- `INV-4`: Hidden directories and preserved unmanaged skills continue to be skipped during prune.

## Design

### 1. Policy File

Add a colocated policy file next to `sync-codex.sh`:

`claude-code/scripts/sync-codex.skill-policy.tsv`

Format:

```text
# plugin<TAB>skill<TAB>mode<TAB>note
superpowers	using-superpowers	drop	Claude harness bootstrap; not valid in Codex
```

Rules:

- `plugin` matches the plugin key from `installed_plugins.json`
- `skill` is the skill directory name
- `mode` is currently `drop`
- `note` is optional human-readable rationale

If a plugin skill has a `drop` entry, the sync script does not copy it into Codex.

### 2. Codex Override Directory

Add a checked-in override source tree:

`claude-code/codex-overrides/skills/<skill-name>/`

Rules:

- Each override is a complete skill directory containing `SKILL.md` and any supporting files.
- Overrides are copied after user skills and plugin skills.
- An override may replace a dropped upstream skill or a pass-through skill.

This keeps Codex-specific adaptations explicit and reviewable without forking upstream plugin source.

### 3. Sync Order

Codex skill sync runs in this order:

1. Sync repo-owned Claude user skills
2. Sync plugin skills, skipping policy-dropped entries
3. Sync Codex overrides last
4. Prune stale managed skills

The last writer wins. This ensures Codex-only overrides take precedence.

### 4. Initial Curation Scope

This spec only curates the `superpowers` plugin skills that were found to be mismatched with Codex.

Initial policy:

- Keep as upstream pass-through:
  - `test-driven-development`
  - `verification-before-completion`
  - `systematic-debugging`
  - `finishing-a-development-branch`
  - `using-git-worktrees`
- Drop until Codex-native rewrites exist:
  - `using-superpowers`
  - `brainstorming`
  - `writing-plans`
  - `executing-plans`
  - `dispatching-parallel-agents`
  - `subagent-driven-development`
  - `requesting-code-review`
  - `receiving-code-review`
  - `writing-skills`

Other plugin skills remain unchanged by this spec.

### 5. Operational Model

This change is intentionally staged:

1. Stop syncing mismatched skills into Codex
2. Add Codex-native overrides incrementally for the skills that are worth keeping
3. Re-enable those skills in practice by adding override directories, not by editing upstream plugin caches

## Risks

- `RISK-1`: A dropped skill may still be useful in some Codex workflows. Mitigation: reintroduce it only via a reviewed Codex override.
- `RISK-2`: An override may drift from upstream semantics. Mitigation: keep overrides small and scoped to explicitly curated skills.
- `RISK-3`: The sync script may prune currently-synced skills that are no longer managed. Mitigation: this is expected and should be called out in verification.

## Acceptance Criteria

- `AC-1`: `sync-codex.sh` reads the colocated skill policy file when syncing plugin skills.
- `AC-2`: Policy-dropped `superpowers` skills are not copied into `codex/.codex/skills`.
- `AC-3`: If a skill exists in `claude-code/codex-overrides/skills/<name>`, that directory wins in the final Codex output.
- `AC-4`: `--check` and normal sync both respect the same curation behavior.
- `AC-5`: Repo documentation mentions the curation/override mechanism.

## Verification

- Run `claude-code/scripts/sync-codex.sh --check` before applying changes to understand drift.
- Run `claude-code/scripts/sync-codex.sh` after implementation to materialize the curated Codex skill set.
- Inspect `codex/.codex/skills` to confirm dropped `superpowers` skills are absent and preserved/local skills remain intact.
