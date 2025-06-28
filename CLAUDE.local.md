# Claude Code Memory & Commands Development Repository

## Repository Purpose

This repository is dedicated to developing, maintaining, and improving Claude Code memory files and slash commands that are symlinked to the user's home directory. When Claude Code reads this CLAUDE.local.md file, it indicates that development work is being performed on the memory and command system itself.

## What This Repository Contains

- **Memory Files**: CLAUDE.md files and related memory system components
- **Slash Commands**: Custom command definitions stored in `.claude/commands/`
- **Development Tools**: Scripts and utilities for managing Claude Code configurations
- **Templates**: Reusable patterns for memory files and commands

## Memory Files System

### Key Concepts from Documentation

> "CLAUDE.md is a special file that Claude Code automatically pulls into context when starting a conversation. This makes it an ideal place for documenting repository etiquette (e.g., branch naming, merge vs. rebase), developer environment setup (e.g., pyenv use, which compilers work), and other project-specific information."

### Memory File Loading Behavior

- **Recursive Reading**: Claude Code reads memories recursively, starting from the current working directory and moving up to (but not including) the root directory
- **Import System**: CLAUDE.md files can import additional files using `@path/to/import` syntax with a maximum depth of 5 hops
- **Automatic Context**: All memory files are automatically loaded into Claude Code's context when launched

### Best Practices for Memory Files

1. **Be Specific**: "Use 2-space indentation" is better than "Format code properly"
2. **Use Structure**: Format each memory as a bullet point and group related memories under descriptive markdown headings
3. **Keep it Concise**: Memory files become part of Claude's prompts, so they should be refined like any frequently used prompt
4. **Iterate and Refine**: Experiment to determine what produces the best instruction following from the model

## Slash Commands System

### Command Organization

- **Project-specific commands**: Stored in `.claude/commands/` directory
- **Personal commands**: Stored in `~/.claude/commands/` directory
- **MCP Integration**: MCP servers can expose prompts as slash commands

### Command Features

- **Arguments**: Use `$ARGUMENTS` keyword to pass parameters from command invocation
- **Bash Execution**: Execute bash commands before the slash command runs using the `!` prefix
- **File References**: Include file contents using the `@` prefix to reference files
- **Namespacing**: Commands support namespacing through directory structures

### Example Command Creation

```bash
echo "Fix issue #$ARGUMENTS following our coding standards" > .claude/commands/fix-issue.md
```

Usage: `/project:fix-issue 123`

## Development Workflow for This Repository

When working on this repository:

1. **Memory Files**: Test changes by running Claude Code and verifying memory loading behavior
2. **Slash Commands**: Validate command syntax and functionality before deployment
3. **Symlink Management**: Ensure proper symlink creation to user's home directory
4. **Documentation**: Update this file when adding new patterns or approaches

## Key Documentation References

- **Memory Management**: https://docs.anthropic.com/en/docs/claude-code/memory
- **Slash Commands**: https://docs.anthropic.com/en/docs/claude-code/slash-commands
- **CLI Reference**: https://docs.anthropic.com/en/docs/claude-code/cli-reference
- **Best Practices**: https://www.anthropic.com/engineering/claude-code-best-practices

## Memory File Import Examples

### Import System Usage
```markdown
# Project Context
@README for project overview and @package.json for available npm commands

# Additional Instructions - git workflow
@docs/git-instructions.md

# Individual Preferences
@~/.claude/my-project-instructions.md
```

## Important Notes

- Changes made in this repository affect the global Claude Code configuration when symlinked
- Memory files are loaded recursively and automatically by Claude Code
- Slash commands become available across all projects when placed in `~/.claude/commands/`
- This repository serves as both development workspace and deployment source for Claude Code configurations