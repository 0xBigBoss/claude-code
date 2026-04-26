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
bin/bin/claude-settings-merge --diff   # show what --fix would change

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
- Plugin and marketplace state: update `claude-code/settings/settings.json`. `enabledPlugins` controls which plugins are turned on, `extraKnownMarketplaces` declares where to fetch them, and `install.sh --claude` derives its idempotent install loop from that file.

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

**Any change to plugin source files requires a version bump.** Lefthook pre-commit and pre-push hooks enforce this automatically via `claude-code/scripts/check-plugin-versions.sh`.

### Version bump checklist

1. Bump `version` in `claude-code/plugins/<name>/.claude-plugin/plugin.json`
2. Bump `version` for the same plugin in `claude-code/.claude-plugin/marketplace.json`
3. Both versions must match — the hook fails on mismatch
4. Stage `plugin.json` alongside your source changes — the hook warns if source files changed without it

### After committing

Refresh the local marketplace so the runtime picks up the new version:

```bash
claude plugin marketplace update 0xbigboss-plugins
```

### Manual check

```bash
claude-code/scripts/check-plugin-versions.sh
```
