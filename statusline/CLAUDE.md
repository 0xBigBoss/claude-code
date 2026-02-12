# CLAUDE.md

Guidance for the Zig statusline project in `claude-code/statusline/`.

## Purpose

Build a fast single-line status renderer for Claude Code. Input comes from JSON on stdin; output is one formatted status line on stdout.

## Build and Test

```bash
# From claude-code/statusline
zig build
zig build run
zig build run -- --debug
zig build test

# Optimized build
zig build -Doptimize=ReleaseFast
```

## Runtime Contract

- Reads `StatuslineInput` JSON from stdin.
- Ignores unknown JSON fields (`ignore_unknown_fields = true`).
- On parse failure, prints minimal fallback (`~`) instead of crashing.
- Optional debug mode appends diagnostics to `/tmp/statusline-debug.log`.

## Data Sources

- Git metadata is read from the current workspace directory.
- Review gate state files are read from:
  - `{git_root}/.claude/ralph-loop.local.md`
  - `{git_root}/.claude/codex-review.local.md`

## Guardrails

- Preserve low-latency behavior; avoid expensive shell/process work.
- Keep graceful-degradation behavior: missing data should hide segments, not fail the whole line.
- Update or add tests in `src/main.zig` when changing parsing/formatting behavior.

## Environment

- Minimum Zig version: `0.15.1`
- No external runtime dependencies beyond POSIX shell tooling already used by the code.
