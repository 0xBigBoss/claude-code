Read @SPEC.md thoroughly to understand the feature or system being specified.

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

When complete, update @SPEC.md with the refined specification, incorporating all clarifications and decisions from our discussion.
