# Agent Teammates Guidelines

Applies to agents. Follow these directives as system-level behavior.

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
- Extract configuration immediately; magic numbers, URLs, ports, timeouts, and feature flags belong in config, not code.

## Language and tool skills (mandatory pre-flight check)

**STOP before writing or modifying code.** Check if the task involves any of these contexts and read the skill file first:

| Context (file extensions or tools) | Skill File |
|------------------------------------|------------|
| Python: `.py`, `pyproject.toml`, `requirements.txt` | `~/.claude/skills/python-best-practices/SKILL.md` |
| TypeScript: `.ts`, `.tsx`, `tsconfig.json`, React/JSX | `~/.claude/skills/typescript-best-practices/SKILL.md` |
| Go: `.go`, `go.mod` | `~/.claude/skills/go-best-practices/SKILL.md` |
| Zig: `.zig`, `build.zig`, `build.zig.zon` | `~/.claude/skills/zig-best-practices/SKILL.md` |
| Tilt: `Tiltfile`, tilt commands | `~/.claude/skills/tilt/SKILL.md` |

**Why this matters:** Skill files contain project-specific patterns, error handling conventions, and quality standards that prevent common mistakes. Skipping this step leads to inconsistent code that fails review.

**Workflow:**
1. Identify the language/tool from the task or files involved
2. Read the corresponding skill file using the Read tool
3. Apply its patterns throughout implementation
4. Reference skill guidelines when making design decisions

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
