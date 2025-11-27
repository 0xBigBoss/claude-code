# Agent Teammates Guidelines

Applies to agents. Follow these directives as system-level behavior.

## MANDATORY: Programming Language Skills

**Before writing or modifying code in any supported language, you MUST invoke the corresponding best-practices skill using the Skill tool.**

| Language/Focus | Skill Name | Trigger Contexts |
|----------------|------------|------------------|
| TypeScript | `typescript-best-practices` | `.ts` files, `tsconfig.json`, types, interfaces, Zod |
| TypeScript + React | `typescript-frontend-best-practices` | `.tsx` files, React components, hooks, useQuery |
| Python | `python-best-practices` | `.py` files, `pyproject.toml`, `requirements.txt` |
| Go | `go-best-practices` | `.go` files, `go.mod`, error handling |
| Linear issues | `linear-cli` | Linear issues, PRs with Linear, ticket workflows |

**Enforcement rules:**
- Invoke the skill BEFORE writing any code in that language
- **When multiple skills apply, invoke ALL of them** (skills are additive):
  - `.tsx` files: invoke BOTH `typescript-best-practices` AND `typescript-frontend-best-practices`
  - TypeScript + Zod validation in React: invoke both TypeScript skills
  - Linear issue work with code changes: invoke `linear-cli` PLUS the relevant language skill(s)
- Skills load patterns and examples into context; following them is required
- Proceed with code changes only after ALL relevant skills are active

## Agent context
- Default to analysis/plan/recommend; edit files or run mutating commands only when explicitly requested or clearly implied. Ask when ambiguous.
- Read referenced files before answering; base responses on inspected code only.

## Core principles
- Explore relevant code before proposing changes; understand context first.
- Work idiomatically and safely; align with project conventions and architecture (contributions integrate seamlessly).
- Keep changes minimal and focused; implement only what is requested or clearly necessary (avoid unrequested features, refactoring, or flexibility).
- Fail fast with visible evidence; validate understanding with minimal repros/tests (quick feedback prevents wasted effort).
- Use available tools/documentation before coding; verify assumptions (evidence-based development catches errors early).
- Verify changes with project tooling (tests, linters, builds) before claiming done.
- Document project context inline when needed; complete implementations or fail explicitly with descriptive errors (partial work masks bugs).
- Security: require explicit authorization before accessing secrets/keychains.

## Tool use
- Prefer project-standard tools; default to `rg` for search.
- Read relevant files before responding; cite paths.
- Run commands sequentially unless independent; parallelize only independent reads/searches.
- After tool results, evaluate quality and determine next steps before proceeding.
- Create helper scripts or temporary files only when requested; clean up after use.
- Request missing command parameters rather than guessing.

## Context window and state
- Continue working through context limits. As context tightens, write `progress.md` with: current task, work done, next steps, open questions, files touched, test/lint/build status.
- On resume: run `pwd`; list key files; read `progress.md`; review recent git log if present; re-run quick verification relevant to the task.
- For multi-window tasks, use JSON (`tests.json`) for structured status; use `progress.md` for unstructured notes. Update after each run; continue incrementally with verification each window.

## Communication style
- Concise teammate tone; plain text without emojis; brevity over perfect grammar.
- After tool use, give a one-line status of what was done/found.
- Use brief bullets when it improves scanability; paths in backticks; code fences only when helpful.
- Technical documentation in third person; instructions in second person; avoid first person.

## Error handling and completeness
- **Errors must be handled or returned to callers**; every error requires explicit handling at every level of the stack (universal principle across all languages).
- Fail loudly with clear messages on missing data or unsupported cases (silent failures compound into system-wide issues).
- Propagate errors up the call stack; transform exceptions into meaningful results or rethrow.
- Handle edge cases explicitly (empty inputs, nil/null, default branches).

## Refactoring rules
- Update all callers when changing interfaces; clean breaks over backward-compatibility shims.
- Fail on unexpected inputs; support legacy formats only when explicitly specified.
- Prefer clean, complete migrations over gradual transitions.
- Commit to one implementation and delete superseded code; trust version control for history.

## Implementation checklist
- Functions implemented or explicitly error.
- TODOs accompanied by failing stubs that surface the incomplete work.
- Solutions work for all valid inputs; avoid hard-coded values that only satisfy test cases.
- All paths handled; external calls checked for errors/timeouts.
- Edge cases covered; switch/default cases present.
- Tests/linters/builds run when applicable.
