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

### rl loop segment (rl 1.0 — initial cut, superseded by REQ-SL-060s)

These requirements shipped with the first rl 1.0 alignment commit and are retained for traceability. REQ-SL-033, REQ-SL-035, REQ-SL-036, and REQ-SL-037 are superseded by the strategy-aware design in the next section. REQ-SL-030…032, 034, 038, 039 carry forward unchanged.

- **REQ-SL-030**: The statusline reads `.rl/state.json` v3 and recognizes the additional fields `strategy`, `review_verdict`, `review_verdict_sha`, `review_verdict_job_id`, `review_in_flight_job_id`, `metric_name`, `metric_direction`, `best_metric_value`. Missing fields default to null/0 and do not break rendering (REQ-SL-001 / I-6).
- **REQ-SL-031**: When `state.active == false`, the rl segment emits nothing regardless of other fields.
- **REQ-SL-032** (strategy glyph): When `state.active == true`, the leading glyph is selected from `strategy`:
  - `ralph` → `🔁`
  - `review` → `🧪`
  - `research` → `🔬`
  - missing/unknown → `🔁` (legacy fallback, matches pre-1.0 default)
- **REQ-SL-033** (SUPERSEDED by REQ-SL-061): Unconditional iteration counter for ralph + review.
- **REQ-SL-034** (review counter): For `ralph` and `review` strategies, when `review_enabled == true`, render ` 🔍 {color}{review_count}/{max_review_cycles}{reset}` using `progressColor`. When `review_enabled == false` the review sub-segment is omitted.
- **REQ-SL-035** (SUPERSEDED by REQ-SL-063): Verdict state glyph precedence without orphan detection or staleness.
- **REQ-SL-036** (SUPERSEDED by REQ-SL-064): Research rendering without metric direction arrow.
- **REQ-SL-037** (SUPERSEDED by REQ-SL-063): Staleness hidden from statusline. Reversed because stale verdicts silently lied about the state of HEAD (observed in `~/0xbigboss/rl` and `…/famo-classifier-alignment` on 2026-04-13).
- **REQ-SL-038** (schema version): The statusline parses `state.version` and, when `--debug` is set and `version` is present but `!= 3`, appends a single diagnostic line to `/tmp/statusline-debug.log`. No visual indication is emitted (I-7 preserves quiet degradation).
- **REQ-SL-039** (allocator hygiene): `parseRalphStateFromContent` accepts an `Allocator` parameter and uses it for all `std.json.parseFromSlice` allocations. No calls to `std.heap.page_allocator` inside parsing code.

### rl loop segment (rl 1.1 — strategy-aware, orphan-aware)

Authored 2026-04-13 after reading the rl 1.1.0 strategy decision functions in `~/0xbigboss/rl/src/strategies/{ralph,review,research}.ts`. Grounded in the observation that `iteration` / `review_count` / `iteration_start_*` have different semantics per strategy, and that the statusline must mirror rl's own decision logic to stay meaningful. Field schema verified unchanged in 1.1 (`schemas.ts:74-110`) — 1.1 only adds the impl-worker track which does not appear in `state.json`.

#### Counter semantics — truth table derived from rl source

| Strategy | `iteration` mutated by hook? | `review_count` mutated? | `iteration_start_*` mutated? |
|---|---|---|---|
| `ralph` | yes: every Stop (`ralph.ts:139`) + every confirmed reject (`ralph.ts:245`) | yes: confirmed reject only (`ralph.ts:256`) | no — `emitIterationEnd` is declared (`shared.ts:803`) but never called anywhere in the source tree |
| `review` | **no** — no branch of `review.ts:decide` touches `iteration` | yes: confirmed reject only (`review.ts:150`) | no — same |
| `research` | yes: every Stop (`research.ts:114`, `research.ts:130`) | n/a | no — same |

Consequence: `iteration_start_ms` encodes "rl init time", not "current iteration start". The statusline treats it as **loop age**.

#### Requirements

- **REQ-SL-060** (fields parsed): The statusline additionally parses `completion_claimed`, `blocked_claimed`, `metric_direction`, `iteration_start_ms`. All are optional; parse failures return defaults and never break rendering.

- **REQ-SL-061** (strategy-dispatched layout): The rl segment dispatches on `strategy`:

  | Strategy | Layout |
  |---|---|
  | `ralph` / unknown | `[prefix]? 🔁 {iter_counter} {review_counter}? {verdict_state}? {age}?` |
  | `review` | `[prefix]? 🧪 🔍 {review_counter} {verdict_state}? {age}?` (no iteration counter — `iteration` is never touched by the review hook, so displaying it is permanently misleading) |
  | `research` | `[prefix]? 🔬 {iter_counter} {metric}? {age}?` (no review counter or verdict glyph — research loops do not gate on reviews) |

  Where:
  - `iter_counter` = ` {progressColor}{iteration}/{max_iterations}{reset}`
  - `review_counter` = ` {progressColor}{review_count}/{max_review_cycles}{reset}` (ralph: preceded by ` 🔍 ` glyph; review: glyph already leads the layout)
  - `progressColor` is unchanged: green <50%, yellow <80%, red ≥80%.

- **REQ-SL-062** (terminal-state prefix): When the loop is in a waiting/winding-down state, a terminal-prefix glyph is emitted before the strategy glyph. Precedence: `blocked_claimed > completion_claimed`.

  | Condition | Prefix | Meaning |
  |---|---|---|
  | `blocked_claimed == true` | ` 🚧` | Loop marked blocked; next Stop will cleanup. This catches the "`active: true` + `blocked_claimed: true`" anomaly observed in `~/0xbigboss/rl/.rl/state.json` on 2026-04-13. |
  | `completion_claimed == true` | ` 🏁` | Agent has claimed completion. For ralph: waiting for verdict. For research: waiting for user's `rl done --keep/--discard`. |
  | neither | *no prefix* | Normal running state. |

- **REQ-SL-063** (verdict state glyph — orphan-aware + staleness-aware): For `ralph` and `review` strategies with `review_enabled == true`, a single trailing verdict glyph is emitted AFTER the review counter, resolved at parse time by the following decision procedure (mirrors `ralph.ts:185-200` / `review.ts:86-98`):

  ```
  resolveVerdictState(state, git_head):
    if state.review_in_flight_job_id is non-null:
      job_status = readJobStatus(git_root, review_in_flight_job_id)
      if job_status in {"queued", "running"}:
        return ⏳   # worker actually running
      # else: orphan marker — fall through as if null
    if state.review_verdict == "approve"
       and state.review_verdict_sha != null
       and state.review_verdict_sha == git_head:
      return ✅
    if state.review_verdict == "reject"
       and state.review_verdict_sha != null
       and state.review_verdict_sha == git_head:
      return ❌
    return blank
  ```

  This collapses "no verdict", "stale verdict", and "orphaned in-flight marker" into the same blank-glyph bucket — all three mean "no verdict you can trust for your current HEAD". The orphan branch prevents the false-positive ⏳ we hit on 2026-04-13 when the stop hook wrote an in-flight id but the worker never spawned.

  Reading the job file costs one bounded file open + small JSON parse; `git rev-parse HEAD` costs one subprocess call already amortized against the existing git calls in the path/branch segment.

- **REQ-SL-064** (research metric with direction arrow): For `research` strategy, when `best_metric_value != null`, render ` ★{arrow}{value}` where `arrow` is `↑` if `metric_direction == "maximize"`, `↓` if `metric_direction == "minimize"`, empty string otherwise. `value` uses 3 decimal places (`{d:.3}`). Metric name is omitted — the operator's task prompt already establishes what metric is being optimized.

- **REQ-SL-065** (loop age): When `iteration_start_ms` is present and the loop is active, render ` +{age}` after the metric/verdict segment, where `age` is the wall-clock delta from `iteration_start_ms` to now, formatted compactly:

  - `<60s` → `{N}s`
  - `<60m` → `{N}m`
  - `<24h` → `{N}h` or `{N}h{M}m` when `M > 0`
  - `≥24h` → `{N}d` (rounded down)

  Color graded by age: green `<1h`, yellow `1h–4h`, red `≥4h`. Rationale: `iteration_start_ms` is only written at `rl init` in 1.1 (the per-iteration advance path is dead code), so this signal represents "loop age since init" — a "this loop has been open a long time" indicator for spotting forgotten or stuck loops.

- **REQ-SL-066** (job-file reader): `readJobStatus(allocator, git_root, job_id)` reads `{git_root}/.rl/jobs/{job_id}.json`, caps the read at 4 KiB, parses `status` from the top-level object. Returns one of `queued | running | completed | failed | cancelled | missing`. File not found, parse failure, or an unexpected status string all map to `missing` — the caller treats `missing` identically to a terminal status (orphan marker).

- **REQ-SL-067** (git HEAD reader): `getGitHead(allocator, dir)` runs `git rev-parse HEAD` in `dir` and returns the trimmed sha. Any failure returns an empty string; callers treat empty as "HEAD unknown" and the staleness check fails open (verdict glyph is NOT suppressed on an unknowable HEAD — we'd rather show a potentially stale ✅/❌ than hide an actionable signal due to a git glitch).

- **REQ-SL-068** (strategy coupling as contract): Because the statusline mirrors the rl hook's decision logic, test fixtures must cover the exact state shapes produced by each `stateUpdates` block in the rl 1.1 strategy files:

  | rl source | State shape | Expected render |
  |---|---|---|
  | `ralph.ts:152-160` (iterate) | iteration++, completion_claimed=false | ` 🔁 N/max` |
  | `ralph.ts:218-223` (approve) | verdict=approve, sha=HEAD | ` 🏁 🔁 N/max 🔍 K/cap ✅ +age` (if completion_claimed was set in the transition) |
  | `ralph.ts:252-265` (reject) | iteration++, review_count++, verdict cleared | ` 🔁 (N+1)/max 🔍 (K+1)/cap` (no verdict glyph — worker cleared it) |
  | `ralph.ts:187-194` (in-flight) | review_in_flight_job_id set, job running | ` 🔁 N/max 🔍 K/cap ⏳` |
  | `review.ts:162-173` (enqueue) | review_in_flight_job_id set, job running | ` 🧪 🔍 K/cap ⏳` |
  | `review.ts:144-158` (reject-iterate) | review_count++, verdict cleared | ` 🧪 🔍 (K+1)/cap` (no verdict glyph) |
  | `research.ts:125-135` (iterate) | iteration++ | ` 🔬 N/max (★±value)? +age` |
  | `research.ts:79-87` (blocked) | blocked_claimed=true | ` 🚧 🔬 N/max …` |

  When rl adds a new branch or changes an existing `stateUpdates` block, the corresponding fixture must be updated. That turns the implicit coupling into an explicit contract.

- **REQ-SL-069** (glyph namespace additions): `glyphs` gains `completion` (`🏁`), `blocked` (`🚧`), `arrow_up` (`↑`), `arrow_down` (`↓`). Existing glyphs unchanged.

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

## Risk tags

- **LOW — code-only change, read-only.** No schema migration, no auth, no infra. Blast radius is the statusline renderer.
- **LOW — reversible.** Dead code removal is recoverable via git.
- No high-risk tags apply.

## Open items

- The `blocked_claimed` / `completion_claimed` flags from rl 1.0 are not surfaced. If `/rl:done` leaves `active == true` while setting these, the statusline will continue rendering the iteration segment. Revisit if the rl contract actually does this; otherwise treat as a non-goal (the Stop hook clears `active` on done).
- Iteration-runtime indicator (`+Nm` derived from `iteration_start_ms`) is deferred (IMP-7) until concrete "stuck iteration" pain is observed.
