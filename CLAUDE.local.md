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
