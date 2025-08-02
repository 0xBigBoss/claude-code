# Claude Code Configuration

A comprehensive configuration system for [Claude Code](https://docs.anthropic.com/en/docs/claude-code) that provides intelligent development workflows, automated memory management, and specialized commands for enhanced AI-assisted coding.

## Features

- **Intelligent Development Workflow**: Implements test-driven development, automated quality checks, and proper branching strategies
- **Project Memory Management**: Automatic context preservation between sessions using `.memory/` files
- **Specialized Commands**: Pre-built commands for memory condensation, first-principles development, and plan implementation
- **Expert Subagents**: Eleven specialized AI subagents inspired by programming legends for focused expertise
- **Quality Assurance**: Built-in support for linting, type checking, and testing workflows
- **Documentation Standards**: Consistent technical writing guidelines

## What's Included

- **CLAUDE.md**: Core operating instructions and development principles
- **commands/**: Specialized command templates
  - `condense-memory.md`: Memory management and reorganization
  - `first-principles.md`: First-principles development approach
  - `implement-plan.md`: Plan execution framework
  - `refine-plan.md`: Plan refinement and validation
- **agents/**: Specialized subagents inspired by programming legends
  - `thompson-explorer.md`: Systematic codebase exploration and discovery
  - `beck-tdd.md`: Test-Driven Development mastery
  - `knuth-analyst.md`: Algorithm analysis with mathematical rigor
  - `torvalds-pragmatist.md`: No-nonsense code quality enforcement
  - `hamilton-reliability.md`: Ultra-reliable defensive programming
  - `carmack-optimizer.md`: Performance optimization mastery
  - `hickey-simplifier.md`: Complexity elimination and design
  - `liskov-architect.md`: Abstraction and type hierarchy design
  - `hopper-debugger.md`: Systematic debugging and developer experience
  - `dijkstra-qa.md`: Uncompromising quality assurance
  - `bernstein-auditor.md`: Security vulnerability analysis and defensive hardening

## Installation

1. **Clone or download** this repository to your local machine.

2. **Backup existing configuration** (if any):

```bash
# Create backup directory
mkdir -p ~/.claude-backup

# Backup existing files if they exist
[ -f ~/.claude/CLAUDE.md ] && cp ~/.claude/CLAUDE.md ~/.claude-backup/
[ -d ~/.claude/commands ] && cp -r ~/.claude/commands ~/.claude-backup/
```

3. **Install the configuration**:

```bash
# Create .claude directory
mkdir -p ~/.claude

# Option 1: Use the install script (recommended)
./scripts/install-symlinks.sh

# Option 2: Create symlinks manually
ln -sf "$(pwd)/CLAUDE.md" ~/.claude/CLAUDE.md
ln -sf "$(pwd)/commands" ~/.claude/commands
ln -sf "$(pwd)/agents" ~/.claude/agents
```

## Usage

Once installed, Claude Code will automatically load these configurations. The system will:

- Apply development best practices to all coding tasks
- Set up project memory management in new projects
- Provide access to specialized commands via the command system
- Enforce quality standards and testing workflows

### Key Workflows

1. **Project Setup**: Automatically creates `.memory/` folder and imports for context preservation
2. **Development**: Follows TDD principles with automated quality checks
3. **Memory Management**: Uses the `condense-memory` command when context grows too large
4. **Plan Execution**: Leverage `implement-plan` and `refine-plan` for complex projects

### Specialized Subagents

The configuration includes eleven expert subagents, each inspired by a programming legend:

- 🔐 **bernstein-auditor**: Security paranoia king who thinks every line of code is sus until proven otherwise. Makes your apps harder to hack than Fort Knox.
- 🕵️ **thompson-explorer**: Old school detective who greps everything because "code don't lie but documentation do." Maps codebases like an archaeologist.
- 🧪 **beck-tdd**: Test-first zealot who writes tests before code because YOLO isn't a development strategy. Makes code bulletproof through discipline.
- 🧮 **knuth-analyst**: Math genius who proves algorithms are correct with actual math instead of vibes. Complexity analysis gives them life.
- 🚀 **hamilton-reliability**: Astronaut-grade engineer who codes like lives depend on it (because they did). Zero tolerance for "it works on my machine."
- 😤 **torvalds-pragmatist**: No-BS code reviewer who roasts bad code harder than Twitter roasts celebrities. "Talk is cheap, show me the code."
- 🏗️ **liskov-architect**: Type system perfectionist who makes inheritance hierarchies so clean they spark joy. Substitutability is their religion.
- ⚡ **carmack-optimizer**: Performance wizard who makes code faster than a TikTok trend going viral. Every microsecond matters, no cap.
- ✨ **hickey-simplifier**: Complexity assassin who deletes code like Marie Kondo organizes closets. Simple is the ultimate flex.
- 🐛 **hopper-debugger**: Bug hunter who finds issues like they're hunting Easter eggs. Makes error messages actually helpful instead of cryptic.
- ✅ **dijkstra-qa**: Quality control perfectionist who treats lint warnings like personal attacks. Zero tolerance for messy code.
- 🗑️ **moore-minimalist**: Digital Marie Kondo who deletes code that doesn't spark joy. "The best code is no code" hits different when they say it.

Each agent is ready to drop in and fix your code instead of just talking about it! They operate with strict anti-hallucination guidelines, requiring concrete evidence and verification for all claims.

### SDLC Subagent Flow

For comprehensive software development lifecycle coverage, chain subagents in this sequence:

1. **thompson-explorer** → Explore and understand the codebase
2. **beck-tdd** → Write tests and implement features
3. **knuth-analyst** → Verify algorithmic correctness
4. **dijkstra-qa** → Ensure quality standards
5. **hamilton-reliability** → Add defensive programming and error handling
6. **bernstein-auditor** → Security review and vulnerability analysis

This flow ensures thorough understanding, proper implementation, uncompromising quality, and security hardening.

## Configuration Details

### Core Principles

- Always use available tools for verification
- Ask clarifying questions for ambiguous requests
- Maintain project memory between sessions
- Follow test-driven development practices
- Implement proper error handling and logging

### Memory Management

The system automatically sets up persistent memory using:

- `engineering-log.md`: Chronological work journal
- `architecture-decisions.md`: Design choices and rationale
- `patterns-discovered.md`: Discovered code patterns
- `issues-solutions.md`: Problems and solutions
- `todo-next-steps.md`: Pending tasks

## Contributing

Contributions are welcome! Please ensure any modifications:

1. Follow the established documentation style (third person for technical docs, second person for instructions)
2. Include proper error handling and logging
3. Add appropriate tests and validation
4. Update memory files for significant changes

## Author

Created by Allen Eubank (Big Boss)

## License

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
