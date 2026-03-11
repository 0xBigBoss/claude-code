---
argument-hint: <spec-file>
description: Interview to fill gaps in a specification file
---

Load the `spec-best-practices` skill before proceeding.

## Spec File Selection

A spec file path is required. Check the argument provided: $ARGUMENTS

If no argument was provided (empty or blank):
1. Search for existing `SPEC.md` files in the project (root, apps/*, packages/*, src/lib/*/)
2. Present any found files to the user and ask which to use
3. If none found, determine the correct colocated path for a new `SPEC.md` and propose it
4. Do not proceed until a spec file is confirmed

If argument provided:
- If the filename is not `SPEC.md` and is not a supporting file linked from an existing `SPEC.md` TOC, suggest the correct `SPEC.md` path instead
- If the file doesn't exist, ask if you should create it at that path

Once the spec file is confirmed, read it using the Read tool.

## Gap Analysis

Before interviewing, check the spec for required elements from `spec-best-practices`:
- Problem/Solution narrative
- Domain model (types, relationships)
- Requirements with `REQ-{DOMAIN}-{NNN}` IDs
- Invariants
- Non-goals
- Acceptance criteria (checklistable)
- Risk tags (if high-risk items exist)

Note which elements are missing or incomplete. Focus the interview on filling these gaps.

## Interview Process

Interview me using AskUserQuestionTool to fill gaps and clarify ambiguities. Ask about:
- Types, schemas, and data models (what are the core domain types? what invariants do they encode?)
- Technical implementation details and constraints
- UI/UX decisions and user flows
- Edge cases and error handling
- Tradeoffs and alternatives considered
- Integration points and dependencies
- Security, performance, and scalability concerns
- Non-goals and explicit scope boundaries
- Risk classification for high-risk items (schema migrations, auth, public APIs, infra)

<question_quality>
Avoid surface-level questions I've likely already considered. Dig into:
- Second-order effects and unintended consequences
- Assumptions that haven't been validated
- Contradictions or tensions in the spec
- Missing success/failure criteria
- Operational concerns (monitoring, debugging, rollback)
- Invariants that should be explicitly stated
- Scope boundaries that need to be drawn as non-goals
</question_quality>

After each of my answers, reflect on what new questions or concerns arise before continuing. Keep interviewing until you've covered all significant gaps.

When complete, update the spec file with the refined specification, incorporating all clarifications and decisions from our discussion. Ensure all required elements from `spec-best-practices` are present in the final output.
