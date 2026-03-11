# Codex Skill Overrides

This directory contains Codex-only skill directories that override upstream Claude user/plugin skills during `claude-code/scripts/sync-codex.sh`.

Rules:

- One subdirectory per skill name
- Each override is a complete skill directory with its own `SKILL.md`
- Overrides are copied after all upstream sources, so they win in the final Codex runtime tree
- Use this only for skills that need Codex-native wording or workflow changes
