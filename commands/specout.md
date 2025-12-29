---
argument-hint: <spec-file>
description: Interview to fill gaps in a specification file
---

## Spec File Selection

A spec file path is required. Check the argument provided: $ARGUMENTS

If no argument was provided (empty or blank):
1. Search for existing spec files in the project (*.spec.md, *-spec.md, SPEC.md, spec/*.md)
2. Present any found files to the user and ask which to use
3. If none found, interview the user about what they're specifying and propose a filename
4. Do not proceed until a spec file is confirmed

If argument provided but file doesn't exist:
- Ask if you should create it, or if there's a typo in the path

Once the spec file is confirmed, read it using the Read tool.

## Interview Process

Interview me using AskUserQuestionTool to fill gaps and clarify ambiguities. Ask about:
- Types, schemas, and data models (what are the core domain types? what invariants do they encode?)
- Technical implementation details and constraints
- UI/UX decisions and user flows
- Edge cases and error handling
- Tradeoffs and alternatives considered
- Integration points and dependencies
- Security, performance, and scalability concerns

<question_quality>
Avoid surface-level questions I've likely already considered. Dig into:
- Second-order effects and unintended consequences
- Assumptions that haven't been validated
- Contradictions or tensions in the spec
- Missing success/failure criteria
- Operational concerns (monitoring, debugging, rollback)
</question_quality>

After each of my answers, reflect on what new questions or concerns arise before continuing. Keep interviewing until you've covered all significant gaps.

When complete, update the spec file with the refined specification, incorporating all clarifications and decisions from our discussion.
