# Claude Code Configuration

Personal configuration for [Claude Code](https://docs.anthropic.com/en/docs/claude-code) providing development guidelines, slash commands, custom agents, and language-specific skills.

## What's Included

```
claude-code/
├── CLAUDE.md                    # Core development guidelines (symlinked to ~/.claude/)
├── commands/                    # Slash commands
│   ├── fix-issue.md             # /fix-issue <id> - locate and fix issues
│   ├── git-commit.md            # /git-commit - conventional commit workflow
│   ├── handoff.md               # /handoff - generate session handoff prompts
│   └── rewrite-history.md       # /rewrite-history - clean up branch commits
├── agents/                      # Custom subagents
│   ├── code-reviewer.md         # Review code for quality and security
│   ├── debugger.md              # Root cause analysis for failures
│   ├── refactorer.md            # Clean refactoring with complete migrations
│   └── test-writer.md           # Write tests that verify correctness
├── .claude/
│   └── skills/                  # Language and tool best practices
│       ├── python-best-practices/
│       ├── typescript-best-practices/
│       ├── react-best-practices/
│       ├── go-best-practices/
│       ├── zig-best-practices/
│       ├── playwright-best-practices/
│       ├── tamagui-best-practices/
│       ├── tilt/
│       ├── web-fetch/
│       ├── axe-ios-simulator/
│       └── zig-docs/
├── scripts/                     # Utility scripts
│   ├── install-symlinks.sh      # Installation helper
│   └── sync-skills-to-codex.sh  # Sync skills to Codex
├── settings/                    # Settings configurations
├── statusline/                  # Statusline configurations
└── analytics/                   # Usage analytics (submodule)
```

## Installation

### Via Stow (Recommended)

This repo is a submodule of a dotfiles repository using GNU Stow:

```bash
cd ~/code/dotfiles
stow -v -R -t ~ claude
```

The `claude` stow package symlinks to this repo's contents.

### Manual Symlinks

```bash
mkdir -p ~/.claude
ln -sf "$(pwd)/CLAUDE.md" ~/.claude/CLAUDE.md
ln -sf "$(pwd)/commands" ~/.claude/commands
ln -sf "$(pwd)/agents" ~/.claude/agents
ln -sf "$(pwd)/.claude/skills" ~/.claude/skills
```

## Commands

Invoke with `/command-name` in Claude Code:

| Command | Description |
|---------|-------------|
| `/fix-issue <id>` | Find and fix an issue by ID with tests and PR description |
| `/git-commit` | Review changes and create conventional commits |
| `/handoff` | Generate a self-contained handoff prompt for another agent |
| `/rewrite-history` | Rewrite branch with clean, narrative commit history |

## Agents

Custom subagents for focused tasks. Claude Code delegates to these automatically when appropriate:

| Agent | Purpose |
|-------|---------|
| `code-reviewer` | Reviews changes for quality, security, and project conventions |
| `debugger` | Investigates failures through root cause analysis |
| `refactorer` | Restructures code with clean breaks and complete migrations |
| `test-writer` | Writes tests that verify correctness without gaming assertions |

## Skills

Language and tool-specific best practices loaded automatically based on file context:

| Context | Skill |
|---------|-------|
| Python (`.py`, `pyproject.toml`) | python-best-practices |
| TypeScript (`.ts`, `.tsx`) | typescript-best-practices |
| React (`.tsx`, `.jsx`, `@react` imports) | react-best-practices |
| Go (`.go`, `go.mod`) | go-best-practices |
| Zig (`.zig`, `build.zig`) | zig-best-practices |
| Playwright (`@playwright/test`) | playwright-best-practices |
| Tamagui (`@tamagui` imports) | tamagui-best-practices |
| Tilt (`Tiltfile`) | tilt |

## Core Principles

The `CLAUDE.md` guidelines emphasize:

- **Type-first development**: Define types before implementing logic; make illegal states unrepresentable
- **Functional style**: Prefer immutability, pure functions, and explicit data flow
- **Minimal changes**: Implement only what's requested; avoid unrequested features or refactoring
- **Error handling**: Handle or return errors at every level; fail loudly with clear messages
- **Test integrity**: Tests verify correctness, not just satisfy assertions
- **Clean refactoring**: Update all callers atomically; delete superseded code completely

## Author

Created by Allen Eubank (Big Boss)

## License

Licensed under the Apache License, Version 2.0. See [LICENSE](LICENSE) for details.
