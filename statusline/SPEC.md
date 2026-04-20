# Statusline SPEC

Retroactive specification for the Zig statusline renderer in `claude-code/statusline/`. Authored 2026-04-12 from the existing implementation in `src/main.zig` plus rl 1.0 alignment work.

## Problem

Claude Code spawns a status-line process on every render tick. The renderer must:

- Turn a single JSON blob on stdin into a single terminal-formatted line on stdout.
- Be fast enough to feel instantaneous on every agent turn (target: < 50 ms wall).
- Surface the information the operator actually glances at mid-loop: where am I (path + branch), what's the agent doing (model, context gauge, cost, time), and what's the loop doing (rl iteration, review verdict / in-flight state).
- Never crash the rendering pipeline. A bad input, a missing file, or a dead subprocess degrades to a safe fallback (`~`), not a broken prompt.

The rl CLI's 1.10 release added `rl statusline`, a first-class one-line renderer for loop state. The statusline now delegates that segment to the CLI instead of mirroring `.rl/state.json` or `.rl/jobs/*`. This spec retains the older direct-read requirements for traceability, but the active contract is the delegated 1.10+ path.

## Non-goals

- Not a general-purpose prompt engine. The segment set is fixed; configuration lives in code.
- Not a persistent daemon. One process per render; no background polling.
- Not authoritative for any data source. Every data read is best-effort and may return null / empty.
- Not responsible for the rl loop's decision logic. The Stop hook in `rl` owns verdict gating; the statusline only visualizes state.
- No network I/O of any kind.
- No schema migration or repair logic for rl loop state. `rl statusline` owns schema evolution; this renderer only shells out and renders stdout.

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
│  rl loop segment       (from `rl statusline`)        │
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

Historical context only. The statusline no longer parses this schema directly; `rl statusline` owns it.

## Invariants

- **I-1 Single-line output.** Exactly one newline, at the end. No mid-line newlines.
- **I-2 Crash-free.** Any error in any segment must be swallowed into "skip that segment" or, at worst, into the `~\n` fallback. A return code of 0 is always produced (subject to OS limits).
- **I-3 Sub-process budget.** All `git` subprocess calls run against the workspace `current_dir`. No arbitrary shell. No network. Timeouts are implicit (Claude Code kills slow renders).
- **I-4 Read-only.** The statusline never writes to state files, rl files, or the repo. Only writes are to `/tmp/statusline-debug.log` when `--debug` is set.
- **I-5 File reads are bounded.** Every direct file read caps the byte count (512 KiB tail for transcripts). The delegated rl subprocess caps captured stdout at 1 KiB.
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

- **REQ-SL-020** (SUPERSEDED by REQ-SL-080; pre-1.0): Read `{git_root}/.rl/state.json` as JSON (first 4 KiB) into `RalphState`.
- **REQ-SL-021** (SUPERSEDED by REQ-SL-080; pre-1.0): When `state.active == false`, emit nothing.
- **REQ-SL-022** (SUPERSEDED by REQ-SL-080; pre-1.0): Render an iteration counter from mirrored loop state.
- **REQ-SL-023** (SUPERSEDED by REQ-SL-080; pre-1.0): Render a review counter from mirrored loop state when reviews are enabled.
- **REQ-SL-024** (SUPERSEDED by REQ-SL-080; pre-1.0): Read `{git_root}/.claude/codex-review.local.md` for a standalone review segment.

### rl loop segment (rl 1.0 — initial cut, superseded by REQ-SL-060s)

- **REQ-SL-030** (SUPERSEDED by REQ-SL-080): Parse `.rl/state.json` v3 fields needed for the rl segment.
- **REQ-SL-031** (SUPERSEDED by REQ-SL-080): Hide the rl segment when `state.active == false`.
- **REQ-SL-032** (SUPERSEDED by REQ-SL-080): Dispatch the leading glyph from `strategy`.
- **REQ-SL-033** (SUPERSEDED by REQ-SL-080): Render an unconditional iteration counter for ralph + review.
- **REQ-SL-034** (SUPERSEDED by REQ-SL-080): Render a review counter for `ralph` / `review` when `review_enabled == true`.
- **REQ-SL-035** (SUPERSEDED by REQ-SL-080): Render a verdict state glyph from mirrored state.
- **REQ-SL-036** (SUPERSEDED by REQ-SL-080): Render research metrics from mirrored state.
- **REQ-SL-037** (SUPERSEDED by REQ-SL-080): Apply HEAD-staleness behavior inside the statusline.
- **REQ-SL-038** (SUPERSEDED by REQ-SL-080): Parse `state.version` and emit debug drift diagnostics.
- **REQ-SL-039** (SUPERSEDED by REQ-SL-080): Thread an allocator through rl-state JSON parsing helpers.

### rl loop segment (rl 1.1 — strategy-aware, orphan-aware)

- **REQ-SL-060** (SUPERSEDED by REQ-SL-080): Parse additional loop-state fields (`completion_claimed`, `blocked_claimed`, `metric_direction`, `iteration_start_ms`).
- **REQ-SL-061** (SUPERSEDED by REQ-SL-080): Dispatch layout by `strategy`.
- **REQ-SL-062** (SUPERSEDED by REQ-SL-080): Render terminal-state prefixes from mirrored loop flags.
- **REQ-SL-063** (SUPERSEDED by REQ-SL-080): Resolve verdict glyphs by reading `.rl/jobs/*` and comparing `review_verdict_sha` to `git HEAD`.
- **REQ-SL-064** (SUPERSEDED by REQ-SL-080): Render research metrics with direction arrows.
- **REQ-SL-065** (SUPERSEDED by REQ-SL-080): Render loop age from `iteration_start_ms`.
- **REQ-SL-066** (SUPERSEDED by REQ-SL-080): Read `{git_root}/.rl/jobs/{job_id}.json` to derive job state.
- **REQ-SL-067** (SUPERSEDED by REQ-SL-080): Probe `git HEAD` for verdict staleness checks.
- **REQ-SL-068** (SUPERSEDED by REQ-SL-080): Maintain strategy-coupled fixture coverage for mirrored rl logic.
- **REQ-SL-069** (SUPERSEDED by REQ-SL-080): Maintain rl-specific glyph constants in `src/main.zig`.
- **REQ-SL-070** (SUPERSEDED by REQ-SL-080): Detect impl workers by scanning `.rl/jobs/` directly.
- **REQ-SL-071** (SUPERSEDED by REQ-SL-080): Accept workspaces that show an impl glyph without `.rl/state.json`.

### rl loop segment (rl 1.10+ — delegated to rl statusline)

- **REQ-SL-080** (delegation): The rl loop segment is produced by shelling out to `rl statusline --format text --cwd <git_root> [--git-head <sha>]`. The statusline emits the subprocess's stdout verbatim, prefixed by a single space. No parsing, no post-processing, no knowledge of `.rl/state.json` or `.rl/jobs/*` remains in the statusline codebase. Source of truth: `rl` CLI owns the schema, the renderer, and the strategy dispatch. Reference: 0xsend/rl#6.
- **REQ-SL-081** (fail-open): Missing `rl` binary (PATH lookup failure), spawn failure, non-zero exit, or stderr output MUST all collapse to "emit nothing" (invariants I-2, I-7). No crash, no fallback glyph, no log spam outside `--debug` mode.
- **REQ-SL-082** (subprocess budget): The rl segment adds exactly one subprocess call per render. Stdout read is capped at 1 KiB. No additional file reads from `.rl/` remain in `src/main.zig`. The git-root discovery and HEAD probe (already present for the path/branch segment) are reused, not duplicated.
- **REQ-SL-083** (tests): The new rl segment is intentionally left uncovered by design. A fake-PATH integration test would require test-only subprocess environment plumbing larger than the helper itself; the project relies on `zig build`, `zig build test`, and live smoke against the real `rl statusline` contract instead.

### Other segments (captured for traceability)

- **REQ-SL-050**: `ZMX_SESSION` env var, when non-empty, renders as ` zmx:{value}` in gray.
- **REQ-SL-051**: Model segment (`{gauge} {emoji}`) is emitted when `input.model.display_name` is present.
- **REQ-SL-052**: Context usage prefers `context_window.current_usage` (v2.0.70+). Falls back to parsing the transcript's last assistant message (max 100 lines / 512 KiB tail scan). Effective context size is 77.5% of `context_window_size` (22.5% autocompact reserve). Returns 0% when unavailable.
- **REQ-SL-053**: Cost (`${usd}`), duration (`Nh|Nm|<1m`), and lines-changed (`+N/-N` in green/red) render when their source fields are present and non-zero. Rounding rules: `<$1 .2f`, `<$10 .1f`, `≥$10 integer`.
- **REQ-SL-054**: Idle-since indicator (`💤{time}`) reads `~/.claude/.idle-since-{session_id}` (max 32 bytes) and is only shown when the file exists.

## Acceptance criteria

rl 1.0 alignment (first cut — 2026-04-12):

- [x] `SPEC.md` exists colocated at `claude-code/statusline/SPEC.md`.
- [x] `CodexReviewState` struct, parse functions, and tests removed.
- [x] `RalphState` gained `strategy`, `review_verdict`, `review_in_flight_job_id`, `best_metric_value`, `version`.
- [x] `parseRalphStateFromContent` threads the allocator.
- [x] `glyphs` namespace.
- [x] Strategy-aware `format` (REQ-SL-032, REQ-SL-034).
- [x] 50/50 tests passing.

rl 1.1 strategy-aware renderer (this change set — 2026-04-13):

- [ ] `RalphState` gains `completion_claimed`, `blocked_claimed`, `metric_direction`, `iteration_start_ms`, `review_verdict_sha` fields.
- [ ] `glyphs` namespace gains `completion`, `blocked`, `arrow_up`, `arrow_down`.
- [ ] `readJobStatus(allocator, git_root, job_id)` reads `.rl/jobs/{id}.json` and returns the job status string (REQ-SL-066).
- [ ] `getGitHead(allocator, dir)` runs `git rev-parse HEAD` once per render (REQ-SL-067).
- [ ] `RalphState.format` dispatches on strategy per REQ-SL-061; ralph/review/research layouts differ as specified.
- [ ] Terminal-state prefix emitted per REQ-SL-062 (`🚧` blocked, `🏁` completion).
- [ ] Verdict state resolution mirrors rl hook: orphan-aware in-flight + HEAD-sha staleness check (REQ-SL-063).
- [ ] Research metric renders with direction arrow per REQ-SL-064.
- [ ] Loop age renders from `iteration_start_ms` with color grading per REQ-SL-065.
- [ ] Per-strategy fixture tests cover every `stateUpdates` branch listed in REQ-SL-068.
- [ ] `zig build test` passes with at least 60 tests total.
- [ ] Live smoke passes against current `~/0xbigboss/rl` loop and `…/famo-classifier-alignment` loop — rendered segment matches what would be expected given each loop's live `state.json` + HEAD.
- [ ] All existing non-rl tests remain green (no regression to path/git/model/gauge/cost/idle segments).
- [x] Impl-worker visibility (REQ-SL-070): `hasRunningImplJob` scans `.rl/jobs/` for `impl-*.json` with status queued/running; renders `🔨` glyph independently of state.json. Tests cover: missing dir, queued/running/completed/failed/cancelled, review-kind job filter, non-json filter, prefix filter.

rl 1.10+ delegation (this change set — 2026-04-20):

- [x] `src/main.zig` loses RalphState, Strategy, MetricDirection, VerdictState, JobStatus, VerdictRaw + their parse/format helpers.
- [x] `renderRlStatusline` shells out to `rl statusline` with PATH probe and graceful fail-open.
- [x] SPEC REQ-SL-020..024, REQ-SL-030..039, REQ-SL-060..071 marked SUPERSEDED by REQ-SL-080.
- [x] New REQ-SL-080..083 describe the delegated contract.
- [x] `zig build test` passes; line count in `src/main.zig` drops by >= 1000 lines.

## Risk tags

- **LOW — code-only change, read-only.** No schema migration, no auth, no infra. Blast radius is the statusline renderer.
- **LOW — reversible.** Dead code removal is recoverable via git.
- No high-risk tags apply.

## Open items

- The `blocked_claimed` / `completion_claimed` flags from rl 1.0 are not surfaced. If `/rl:done` leaves `active == true` while setting these, the statusline will continue rendering the iteration segment. Revisit if the rl contract actually does this; otherwise treat as a non-goal (the Stop hook clears `active` on done).
- Iteration-runtime indicator (`+Nm` derived from `iteration_start_ms`) is deferred (IMP-7) until concrete "stuck iteration" pain is observed.
