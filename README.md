# Claude Code Configuration

A comprehensive configuration system for [Claude Code](https://docs.anthropic.com/en/docs/claude-code) that provides intelligent development workflows, automated memory management, and specialized commands for enhanced AI-assisted coding.

## Features

- **Intelligent Development Workflow**: Implements test-driven development, automated quality checks, and proper branching strategies
- **Project Memory Management**: Automatic context preservation between sessions using `.memory/` files
- **Specialized Commands**: Pre-built commands for memory condensation, first-principles development, and plan implementation
- **Expert Subagents**: Seven specialized AI subagents inspired by programming legends for focused expertise
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
  - `knuth-analyst.md`: Algorithm analysis with mathematical rigor
  - `torvalds-pragmatist.md`: No-nonsense code quality enforcement
  - `hamilton-reliability.md`: Ultra-reliable defensive programming
  - `carmack-optimizer.md`: Performance optimization mastery
  - `hickey-simplifier.md`: Complexity elimination and design
  - `liskov-architect.md`: Abstraction and type hierarchy design
  - `hopper-debugger.md`: Systematic debugging and developer experience

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

The configuration includes seven expert subagents, each inspired by a programming legend:

- **knuth-analyst**: For algorithm analysis requiring mathematical rigor and correctness proofs
- **torvalds-pragmatist**: For code reviews demanding brutal honesty and practical solutions
- **hamilton-reliability**: For mission-critical code requiring ultra-reliable error handling
- **carmack-optimizer**: For performance optimization with evidence-based improvements
- **hickey-simplifier**: For reducing complexity and improving system design
- **liskov-architect**: For proper abstraction design and type hierarchies
- **hopper-debugger**: For systematic debugging and improving developer experience

Each subagent operates with strict anti-hallucination guidelines, requiring concrete evidence and verification for all claims.

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
