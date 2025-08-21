---
allowed-tools: Read, Grep, Glob, LS, TodoWrite, Task, Bash
argument-hint: [feature-or-task-description]
description: Comprehensive pre-implementation planning with systematic investigation
model: opus
---

# Deep Planning Mode

**Task**: $ARGUMENTS

## Phase 1: Silent Investigation

First, conduct a thorough, methodical investigation of the codebase to understand:

- **Existing Architecture**: How the current system is structured
- **Related Components**: What parts of the codebase are relevant
- **Code Patterns**: Established conventions and patterns to follow
- **Dependencies**: What libraries, frameworks, or external systems are involved
- **Test Infrastructure**: How testing is currently handled
- **Configuration**: Build systems, environment setup, deployment considerations

_Investigate systematically without making assumptions. Use Read, Grep, Glob, and LS tools extensively._

## Phase 2: Clarifying Questions

After investigation, ask targeted questions to clarify:

- **Requirements Scope**: What exactly needs to be implemented?
- **Success Criteria**: How will we know the implementation is complete?
- **Constraints**: Are there any limitations, performance requirements, or compatibility needs?
- **Integration Points**: How should this connect to existing systems?
- **User Experience**: What should the user interaction look like?
- **Edge Cases**: What unusual scenarios need to be handled?

## Phase 3: Implementation Plan

Create a detailed, structured implementation plan in markdown format:

### 📋 Implementation Plan: [Task Name]

#### Overview

- **Objective**: Clear statement of what will be built
- **Approach**: High-level strategy and methodology
- **Success Metrics**: How success will be measured

#### Architecture & Design

- **Component Structure**: How code will be organized
- **Data Flow**: How information moves through the system
- **API Design**: Interface definitions and contracts
- **Integration Strategy**: How this fits with existing code

#### Detailed Implementation Steps

1. **Setup & Preparation**

   - [ ] Environment configuration
   - [ ] Dependency management
   - [ ] Initial file structure

2. **Core Implementation**

   - [ ] [Specific implementation step 1]
   - [ ] [Specific implementation step 2]
   - [ ] [Continue with granular steps...]

3. **Testing Strategy**

   - [ ] Unit test implementation
   - [ ] Integration testing
   - [ ] End-to-end validation

4. **Documentation & Cleanup**
   - [ ] Code documentation
   - [ ] User documentation updates
   - [ ] Final review and optimization

#### Risk Assessment

- **Technical Risks**: Potential implementation challenges
- **Dependencies**: External factors that could affect timeline
- **Mitigation Strategies**: How to handle identified risks

#### Timeline Estimate

- **Phase 1**: [Time estimate] - [Description]
- **Phase 2**: [Time estimate] - [Description]
- **Total Estimated Time**: [Overall estimate]

## Phase 4: Task Creation

Use TodoWrite to create trackable tasks based on the implementation plan. Break down complex steps into manageable, actionable items that can be completed and verified individually.

_The goal is to create a comprehensive roadmap that eliminates guesswork and ensures systematic, quality implementation._
