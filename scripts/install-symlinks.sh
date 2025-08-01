#!/bin/bash

# Install symlinks for Claude Code scripts, settings, and agents

REPO_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." && pwd )"

echo "Installing symlinks from repository to ~/.claude..."

# Backup existing files if they exist and aren't already symlinks
if [ -e ~/.claude/scripts ] && [ ! -L ~/.claude/scripts ]; then
    echo "Backing up existing ~/.claude/scripts to ~/.claude/scripts.backup"
    mv ~/.claude/scripts ~/.claude/scripts.backup
fi

if [ -e ~/.claude/settings.json ] && [ ! -L ~/.claude/settings.json ]; then
    echo "Backing up existing ~/.claude/settings.json to ~/.claude/settings.json.backup"
    mv ~/.claude/settings.json ~/.claude/settings.json.backup
fi

if [ -e ~/.claude/agents ] && [ ! -L ~/.claude/agents ]; then
    echo "Backing up existing ~/.claude/agents to ~/.claude/agents.backup"
    mv ~/.claude/agents ~/.claude/agents.backup
fi

# Create ~/.claude directory if it doesn't exist
mkdir -p ~/.claude

# Create symlinks
echo "Creating symlink: ~/.claude/scripts -> $REPO_DIR/scripts"
ln -sfn "$REPO_DIR/scripts" ~/.claude/scripts

echo "Creating symlink: ~/.claude/settings.json -> $REPO_DIR/settings/settings.json"
ln -sfn "$REPO_DIR/settings/settings.json" ~/.claude/settings.json

echo "Creating symlink: ~/.claude/agents -> $REPO_DIR/agents"
ln -sfn "$REPO_DIR/agents" ~/.claude/agents

echo "Done! Symlinks installed successfully."
echo ""
echo "To verify the symlinks:"
echo "  ls -la ~/.claude/scripts"
echo "  ls -la ~/.claude/settings.json"
echo "  ls -la ~/.claude/agents"