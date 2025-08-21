---
allowed-tools: Read, Grep, Glob, LS, TodoWrite
argument-hint: [task-description]
description: Create detailed context summary for continuing work on a task
model: opus
---

# New Task Context Creation

Create a comprehensive context summary for the task: "$ARGUMENTS"

**IMPORTANT**: This command is for context documentation only. Do NOT continue working on the task or implement any solutions. The user will copy this summary and paste it into a new Claude Code session to continue the work.

## Instructions

Generate a detailed summary that captures:

### Current Work Context
- **Task Description**: What you're working on
- **Current Status**: Where you left off
- **Key Technical Concepts**: Important technologies, frameworks, or patterns involved
- **Relevant Files**: List of files you've been working with or need to examine
- **Code Snippets**: Important code blocks or configurations

### Problem-Solving Progress
- **Understanding Achieved**: What you've learned about the problem
- **Approaches Tried**: Solutions attempted and their outcomes
- **Blockers Encountered**: Any obstacles or challenges faced
- **Research Findings**: Key insights from documentation or investigation

### Next Steps
- **Immediate Tasks**: What needs to be done next
- **Dependencies**: Any prerequisites or requirements
- **Testing Strategy**: How to validate the solution
- **Alternative Approaches**: Other options to consider

### Implementation Notes
- **Architecture Decisions**: Important design choices made
- **Code Patterns**: Specific patterns or conventions to follow
- **Configuration Details**: Environment setup or configuration requirements
- **Integration Points**: How this work connects to other system components

## Output Format

Present the context summary in a clear, structured format that can be easily copied and pasted into a new Claude Code session. Include all relevant details but keep the summary concise and actionable.

**Remember**: Do not implement or continue coding after generating this summary. The purpose is to create a handoff document for the next session.