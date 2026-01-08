# Claude Code Development Repository

Development workspace for Claude Code configuration: skills, commands, hooks, and scripts.

## Directory Structure

- `commands/` - User-level slash commands
- `.claude/skills/` - Best-practices skills
- `.claude-plugin/` - Plugin development workspace
- `hooks/` - Claude Code hooks
- `scripts/` - Helper scripts
- `agents/` - Custom agent definitions
- `plugins/` - Plugin configurations
- `settings/` - Settings templates
- `analytics/` - Usage analytics tools
- `statusline/` - Statusline components

## Stow Integration

Symlinked via `dotfiles/claude/.claude/`:
- `commands`, `agents`, `scripts`, `hooks`, `skills` symlink here
- Changes are immediately available after editing

To add a new top-level directory:
```bash
cd ~/code/dotfiles/claude/.claude
ln -s ../../claude-code/new-directory new-directory
cd ~/code/dotfiles && stow -R claude
```

## Adding Content

**Commands**: Add `.md` file to `commands/`
**Skills**: Add directory with `SKILL.md` to `.claude/skills/`

## Symlink Warning

Never edit files via `~/.claude/` paths - use source paths in this repo.
Editing symlinked paths destroys the symlink.

If accidentally destroyed:
```bash
cd ~/code/dotfiles/claude/.claude
rm broken-symlink
ln -s ../../claude-code/target target
```

## Plugin Troubleshooting

When plugins fail to load (e.g., after Claude Code updates change the manifest schema), they may be marked as orphaned rather than removed. Symptoms:
- Plugin shows in `/plugin` list but hooks don't trigger
- `/doctor` shows plugin errors

Fix orphaned plugins:
```bash
# Check for orphan markers
find ~/.claude/plugins/cache -name ".orphaned_at"

# Remove markers for specific plugin
rm ~/.claude/plugins/cache/0xbigboss-plugins/<plugin>/*/.orphaned_at

# Or force reinstall
claude plugin update <plugin-name>
```

## Publishing Plugin Updates

Plugin versions must be updated in **two places** to stay in sync:

1. **Individual plugin manifest**: `plugins/<plugin-name>/.claude-plugin/plugin.json`
2. **Marketplace index**: `.claude-plugin/marketplace.json`

The marketplace UI reads versions from `marketplace.json`, while installation uses individual `plugin.json` files. If these diverge, the marketplace shows stale versions even though installations get the correct version.

**When bumping a version:**
```bash
# Update both files, then refresh the marketplace
claude plugin marketplace update 0xbigboss-plugins
```
