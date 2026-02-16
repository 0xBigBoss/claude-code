# Claude Code Development Repository (Local Notes)

Local operational notes for maintaining this Claude Code config repo.

## Scope

This repo is the source of truth for Claude Code runtime assets (commands, agents, skills, hooks, settings, statusline) that are projected into `~/.claude` and synced to Codex.

## Work From Source Paths

- Edit files in this repository, not in `~/.claude/*`.
- Runtime links are managed by `bin/bin/claude-bootstrap`.
- Generated runtime settings are managed by `bin/bin/claude-settings-merge`.

## Key Paths

- Commands: `claude-code/commands/`
- Agents: `claude-code/agents/`
- Skills: `claude-code/.claude/skills/`
- Hooks and scripts: `claude-code/hooks/`, `claude-code/scripts/`
- Settings baseline: `claude-code/settings/settings.json`

## Canonical Sync/Apply Flow

```bash
# 1) Validate managed links and runtime files
bin/bin/claude-bootstrap --check

# 2) Validate merged settings
bin/bin/claude-settings-merge --check

# 3) Validate Claude->Codex sync (commands + skills)
claude-code/scripts/sync-codex.sh --check

# Apply
bin/bin/claude-bootstrap --fix
bin/bin/claude-settings-merge --fix
claude-code/scripts/sync-codex.sh
```

## When Adding New Assets

- New command: add `*.md` to `claude-code/commands/` and run `sync-codex.sh`.
- New skill: add `claude-code/.claude/skills/<skill-name>/SKILL.md` and run `sync-codex.sh`.
- Plugin/marketplace defaults: update `claude/defaults/plugins.txt` or `claude/defaults/marketplaces.txt` in the parent repo.

## Review Checklist

Before finishing changes, run:

```bash
# From dotfiles repo root
./install.sh --claude --check
bin/bin/claude-bootstrap --check
bin/bin/claude-settings-merge --check
claude-code/scripts/sync-codex.sh --check
```

## Plugin Troubleshooting

If a plugin appears installed but hooks do not run, check orphan markers:

```bash
find ~/.claude/plugins/cache -name ".orphaned_at"
rm ~/.claude/plugins/cache/0xbigboss-plugins/<plugin>/*/.orphaned_at
claude plugin update <plugin-name>
```

## Publishing Plugin Updates

Keep plugin versions in sync in both locations:

1. `claude-code/plugins/<plugin-name>/.claude-plugin/plugin.json`
2. `claude-code/.claude-plugin/marketplace.json`

Then refresh marketplace metadata:

```bash
claude plugin marketplace update 0xbigboss-plugins
```
