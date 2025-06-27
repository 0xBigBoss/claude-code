# Claude Code files

## Installing

1. Save this repo somewhere on your machine.

2. Before installing, backup existing files (if any):

```bash
# Create backup directory
mkdir -p ~/.claude-backup

# Backup existing files if they exist
[ -f ~/.claude/CLAUDE.md ] && cp ~/.claude/CLAUDE.md ~/.claude-backup/
[ -d ~/.claude/commands ] && cp -r ~/.claude/commands ~/.claude-backup/
```

3. Create the .claude directory and symlink the files:

```bash
# Create .claude directory
mkdir -p ~/.claude

# Create symlinks from the current directory
ln -sf "$(pwd)/CLAUDE.md" ~/.claude/CLAUDE.md
ln -sf "$(pwd)/commands" ~/.claude/commands
```
