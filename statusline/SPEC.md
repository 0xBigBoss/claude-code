# Statusline SPEC

Retroactive specification for the Zig statusline renderer in `claude-code/statusline/`. Authored 2026-04-12 from the existing implementation in `src/main.zig` plus rl 1.0 alignment work.

## Problem

Claude Code spawns a status-line process on every render tick. The renderer must:

- Turn a single JSON blob on stdin into a single terminal-formatted line on stdout.
- Be fast enough to feel instantaneous on every agent turn (target: < 50 ms wall).
- Surface the information the operator actually glances at mid-loop: where am I (path + branch), what's the agent doing (model, context gauge, cost, time), and what's the loop doing (rl iteration, review verdict / in-flight state).
- Never crash the rendering pipeline. A bad input, a missing file, or a dead subprocess degrades to a safe fallback (`~`), not a broken prompt.

The rl CLI's 1.0 rewrite moved verdict state from a standalone `.claude/codex-review.local.md` file into `.rl/state.json`, introduced strategy-typed loops (`ralph | review | research`), and added async review workers with `review_in_flight_job_id` / `review_verdict` / `review_verdict_sha` fields. The statusline's old segment still reads the pre-1.0 files and no longer reflects what the loop is actually doing. This spec captures both the preserved behavior and the rl 1.0 alignment.

## Non-goals

- Not a general-purpose prompt engine. The segment set is fixed; configuration lives in code.
- Not a persistent daemon. One process per render; no background polling.
- Not authoritative for any data source. Every data read is best-effort and may return null / empty.
- Not responsible for the rl loop's decision logic. The Stop hook in `rl` owns verdict gating; the statusline only visualizes state.
- No network I/O of any kind.
- No schema migration for stale rl state files. Graceful degrade in `--debug` mode; do not try to repair.

## Domain model

```
stdin (JSON StatuslineInput)
      │
      ▼
┌──────────────────────┐       ┌────────────────────────┐
│  parseFromSlice      │ fail  │ fallback: "~\n" to     │
│  (ignore_unknown…)   ├──────▶│ stdout, exit 0         │
└──────┬───────────────┘       └────────────────────────┘
       │ ok
       ▼
┌──────────────────────────────────────────────────────┐
│ Segment pipeline (writes into a 1 KiB output buffer) │
│                                                      │
│  path + branch + git-status                          │
│  rl loop segment       (from .rl/state.json)         │
│  zmx session           (from $ZMX_SESSION)           │
│  model + gauge + usage + cost + duration + lines     │
│  idle-since            (from ~/.claude/.idle-since-*)│
└──────┬───────────────────────────────────────────────┘
       │
       ▼
   stdout (one line)
```

### Key types (source: `src/main.zig`)

- `StatuslineInput` — the stdin contract. Fields are all optional. `context_window.current_usage` (Claude Code v2.0.70+) is the preferred token-count source; transcript parsing is the fallback.
- `ContextUsage` — `{ percentage, total_tokens }`. Renders a 5-char, 40-step eighth-block gauge with an RGB gradient (green → yellow → red).
- `ModelType` — `opus | sonnet | haiku | unknown`. Drives the model glyph (`🎭📜🍃?`).
- `GitStatus` — `{ added, modified, deleted, untracked }`. Parsed from `git status --porcelain`.
- `RalphState` (pre-1.0) — `{ active, iteration, max_iterations, review_enabled, review_count, max_review_cycles }`. Read from `{git_root}/.rl/state.json`.
- `CodexReviewState` (deprecated; removed in rl 1.0 alignment) — YAML frontmatter reader for `{git_root}/.claude/codex-review.local.md`.

### rl 1.0 state schema (source: `~/0xbigboss/rl/SPEC.md:387-418`)

```typescript
interface LoopState {
  version: 3
  strategy: 'ralph' | 'review' | 'research'
  active: boolean
  iteration: number
  max_iterations: number
  timestamp: string

  review_enabled: boolean
  review_count: number
  max_review_cycles: number

  review_verdict: 'approve' | 'reject' | null
  review_verdict_sha: string | null
  review_verdict_ts: string | null
  review_verdict_job_id: string | null
  review_in_flight_job_id: string | null

  metric_name?: string
  metric_direction?: 'minimize' | 'maximize'
  best_metric_value?: number
  best_metric_commit?: string

  completion_claimed?: boolean
  blocked_claimed?: boolean
  debug: boolean
}
```

The statusline reads a subset: everything needed to render one segment, nothing more.

## Invariants

- **I-1 Single-line output.** Exactly one newline, at the end. No mid-line newlines.
- **I-2 Crash-free.** Any error in any segment must be swallowed into "skip that segment" or, at worst, into the `~\n` fallback. A return code of 0 is always produced (subject to OS limits).
- **I-3 Sub-process budget.** All `git` subprocess calls run against the workspace `current_dir`. No arbitrary shell. No network. Timeouts are implicit (Claude Code kills slow renders).
- **I-4 Read-only.** The statusline never writes to state files, rl files, or the repo. Only writes are to `/tmp/statusline-debug.log` when `--debug` is set.
- **I-5 File reads are bounded.** Every file read caps the byte count (4 KiB for `.rl/state.json`, 512 KiB tail for transcripts).
- **I-6 Unknown fields are ignored.** All JSON parses use `ignore_unknown_fields = true`. Schema additions upstream must not break the statusline.
- **I-7 Empty segments are hidden.** A segment that has nothing interesting to say emits zero bytes (not even a leading space).

## Requirements

### Input

- **REQ-SL-001**: The statusline reads one JSON `StatuslineInput` document from stdin. Fields are all optional. Unknown fields are ignored.
- **REQ-SL-002**: If stdin JSON fails to parse, emit `~\n` (cyan) to stdout and exit 0. Log the parse error to `/tmp/statusline-debug.log` when `--debug` is set.
- **REQ-SL-003**: `--debug` command-line flag enables writing the raw input, rendered output, and any diagnostics to `/tmp/statusline-debug.log` (append-only). No other command-line flags exist.

### Workspace segment

- **REQ-SL-010**: When `workspace.current_dir` is missing, emit `~` and skip all workspace-dependent segments (git, rl).
- **REQ-SL-011**: When `current_dir` is present, render the path via `formatPathShort` — home-relative, abbreviating intermediate segments on long paths, last segment full.
- **REQ-SL-012**: When `current_dir` is inside a git repo, detect this via `git rev-parse --is-inside-work-tree` and enable git-dependent segments.
- **REQ-SL-013**: When the git branch equals the last path segment, color the last path segment green and skip the `[branch]` display. Otherwise render `[branch]` (abbreviated via `abbreviateBranch`).
- **REQ-SL-014**: Abbreviation rules for branches: Linear-issue pattern (`PREFIX-NNNN[-suffix]`) truncates to `PREFIX-NNNN`. Other branches get the per-segment `abbreviateSegment` treatment (first letter per hyphen-separated token, `0x`-prefixed tokens keep three chars).
- **REQ-SL-015**: Git status indicators (`+N ~N -N ?N`) render inside the same bracket pair as the branch when any are non-zero.

### rl loop segment (pre-1.0 — captured for baseline)

- **REQ-SL-020** (pre-1.0): Read `{git_root}/.rl/state.json` as JSON (first 4 KiB) into `RalphState` with `ignore_unknown_fields`. On any failure return the default (inactive) state.
- **REQ-SL-021** (pre-1.0): When `state.active == false`, emit nothing.
- **REQ-SL-022** (pre-1.0): When active, emit ` 🔄 {color}{iteration}/{max_iterations}{reset}` where color follows `progressColor` (green <50%, yellow <80%, red ≥80%).
- **REQ-SL-023** (pre-1.0): When `review_enabled`, additionally emit ` 🔍 {color}{review_count}/{max_review_cycles}{reset}` using the same color rule.
- **REQ-SL-024** (deprecated, removed in rl 1.0 alignment): Read `{git_root}/.claude/codex-review.local.md` YAML frontmatter for a standalone `🔎` Codex review segment.

### rl loop segment (rl 1.0 — NEW)

- **REQ-SL-030**: The statusline reads `.rl/state.json` v3 and recognizes the additional fields `strategy`, `review_verdict`, `review_verdict_sha`, `review_verdict_job_id`, `review_in_flight_job_id`, `metric_name`, `metric_direction`, `best_metric_value`. Missing fields default to null/0 and do not break rendering (REQ-SL-001 / I-6).
- **REQ-SL-031**: When `state.active == false`, the rl segment emits nothing regardless of other fields.
- **REQ-SL-032** (strategy glyph): When `state.active == true`, the leading glyph is selected from `strategy`:
  - `ralph` → `🔁`
  - `review` → `🧪`
  - `research` → `🔬`
  - missing/unknown → `🔁` (legacy fallback, matches pre-1.0 default)
- **REQ-SL-033** (iteration counter): For `ralph` and `review` strategies, render ` {glyph} {color}{iteration}/{max_iterations}{reset}` using `progressColor`.
- **REQ-SL-034** (review counter): For `ralph` and `review` strategies, when `review_enabled == true`, additionally render ` 🔍 {color}{review_count}/{max_review_cycles}{reset}`. When `review_enabled == false` the review sub-segment is omitted.
- **REQ-SL-035** (state glyph): For `ralph` and `review` strategies with `review_enabled == true`, a terminal state glyph is appended after the review counter, chosen by precedence:
  1. `review_in_flight_job_id != null` → ` ⏳` (in-flight beats verdict; a running worker invalidates any prior verdict by construction)
  2. `review_verdict == "approve"` → ` ✅`
  3. `review_verdict == "reject"` → ` ❌`
  4. otherwise → nothing
- **REQ-SL-036** (research rendering): For `research` strategy:
  - Render ` 🔬 {color}{iteration}/{max_iterations}{reset}` (same color rule).
  - Review sub-segment and state glyph are hidden (research loops do not gate on reviews).
  - When `best_metric_value != null`, additionally render ` ★{value}` using 3 significant digits. Metric name is omitted to preserve space — the operator's task prompt supplies context.
- **REQ-SL-037** (staleness): Verdict staleness (`review_verdict_sha != HEAD`) is NOT surfaced on the statusline. The rl Stop hook owns that decision; the statusline's goal is a glanceable snapshot of stored state, not a correctness oracle.
- **REQ-SL-038** (schema version): The statusline parses `state.version` and, when `--debug` is set and `version` is present but `!= 3`, appends a single diagnostic line to `/tmp/statusline-debug.log`. No visual indication is emitted (I-7 preserves quiet degradation).
- **REQ-SL-039** (allocator hygiene): `parseRalphStateFromContent` accepts an `Allocator` parameter and uses it for all `std.json.parseFromSlice` allocations. No calls to `std.heap.page_allocator` inside parsing code.

### Other segments (captured for traceability)

- **REQ-SL-050**: `ZMX_SESSION` env var, when non-empty, renders as ` zmx:{value}` in gray.
- **REQ-SL-051**: Model segment (`{gauge} {emoji}`) is emitted when `input.model.display_name` is present.
- **REQ-SL-052**: Context usage prefers `context_window.current_usage` (v2.0.70+). Falls back to parsing the transcript's last assistant message (max 100 lines / 512 KiB tail scan). Effective context size is 77.5% of `context_window_size` (22.5% autocompact reserve). Returns 0% when unavailable.
- **REQ-SL-053**: Cost (`${usd}`), duration (`Nh|Nm|<1m`), and lines-changed (`+N/-N` in green/red) render when their source fields are present and non-zero. Rounding rules: `<$1 .2f`, `<$10 .1f`, `≥$10 integer`.
- **REQ-SL-054**: Idle-since indicator (`💤{time}`) reads `~/.claude/.idle-since-{session_id}` (max 32 bytes) and is only shown when the file exists.

## Acceptance criteria

rl 1.0 alignment (this change set):

- [x] `SPEC.md` exists colocated at `claude-code/statusline/SPEC.md`.
- [ ] `CodexReviewState` struct, `parseCodexReviewState*` functions, and all `CodexReviewState` tests are removed.
- [ ] `RalphState` gains optional `strategy`, `review_verdict`, `review_verdict_sha`, `review_in_flight_job_id`, `best_metric_value` fields, plus any others required for rendering above.
- [ ] `parseRalphStateFromContent(allocator, content)` signature threads the allocator; no `std.heap.page_allocator` in parse path.
- [ ] `glyphs` namespace declared alongside `colors`; strategy, state, and metric glyph literals live there.
- [ ] Strategy-aware `RalphState.format` renders per REQ-SL-032…036.
- [ ] Tests cover: strategy glyph selection; verdict state glyph precedence including in-flight-wins-over-verdict; research metric rendering; research segment hides review counter; schema version debug-log branch; allocator-threading test uses `std.testing.allocator`.
- [ ] `zig build test` passes.
- [ ] `zig build` (default) produces a working binary that renders all three strategies correctly against hand-crafted `.rl/state.json` fixtures.
- [ ] All existing tests remain green (no behavior change to path/git/model/gauge/cost segments).

## Risk tags

- **LOW — code-only change, read-only.** No schema migration, no auth, no infra. Blast radius is the statusline renderer.
- **LOW — reversible.** Dead code removal is recoverable via git.
- No high-risk tags apply.

## Open items

- The `blocked_claimed` / `completion_claimed` flags from rl 1.0 are not surfaced. If `/rl:done` leaves `active == true` while setting these, the statusline will continue rendering the iteration segment. Revisit if the rl contract actually does this; otherwise treat as a non-goal (the Stop hook clears `active` on done).
- Iteration-runtime indicator (`+Nm` derived from `iteration_start_ms`) is deferred (IMP-7) until concrete "stuck iteration" pain is observed.
