# delegate-implementer skill — design

**Date:** 2026-04-11
**Status:** Design approved, ready for planning
**Author:** Opus + Allen (brainstorm session)
**Scope:** v1 of a Claude Code skill that lets Opus delegate bounded implementation tasks to Codex (gpt-5.4) while acting as driver/reviewer. Provider-agnostic shape, Codex-only adapter wired in v1.

## Summary

Today Claude Code runs Opus as the worker inside `rl ralph` loops while Codex serves as the reviewer. On large projects that framing burns Opus tokens on mechanical implementation work that Codex can do well when given a tight instruction packet. This spec defines a skill — `delegate-implementer` — that inverts the relationship for selected milestones: Opus writes a delegation packet, Codex implements it in a detached `codex exec` worker, Opus reads a structured result, and the existing `rl review` gate audits the diff with fresh context. The skill is a proving ground (Approach 1) for a later promotion to a first-class `implement` worker role in `rl-broker` (Approach 2). Event shapes and packet format are designed to lift directly into `rl-broker` when that promotion happens.

## Goals

- **G1** Let Opus delegate a well-scoped milestone to Codex without leaving the Claude Code session, protecting Opus's context by reading only structured results.
- **G2** Give Opus live, low-noise visibility into Codex's progress via agent-emitted phase events, not log parsing.
- **G3** Keep the reviewer (existing `rl review`) blind to delegation origin so the audit remains unbiased.
- **G4** Design the event schema, packet format, and result schema so promotion to an `rl-broker` `implement` worker is a code move, not a format translation.
- **G5** Be provider-agnostic in shape (interface + adapter pattern), wired only for Codex in v1.
- **G6** Respect yolo-mode-by-default while allowing per-packet downgrade.

## Non-Goals

- **NG1** No second provider implementation in v1. Claude and Gemini adapters are stubs documenting the interface.
- **NG2** No changes to `rl-broker`, `rl ralph`, or `.rl/events.jsonl`. The skill runs entirely outside the broker.
- **NG3** No parallel delegations. One packet in flight at a time. Multi-job queueing belongs in the broker promotion.
- **NG4** No automatic retry. Failed delegations are surfaced to Opus, which decides whether to amend and re-dispatch or escalate.
- **NG5** No slash-command entry. Skill is invoked via the Skill tool, typically from inside an active ralph iteration.
- **NG6** No mock provider or recorded-response test harness. Provider behavior is the thing under validation.

## Requirements

### Architecture

- **REQ-DI-001** Three roles must be distinct: Driver (Opus in the Claude Code session), Implementer (Codex via `codex exec`), Reviewer (existing `rl review` worker). The skill coordinates the first two; the existing ralph stop-hook triggers the third unchanged.
- **REQ-DI-002** Implementer runs in a detached background process spawned via `Bash(run_in_background=true)`. Driver never blocks waiting on it.
- **REQ-DI-003** Implementer and Reviewer must never share conversation context. Reviewer receives only the committed diff, not the packet or the implementer's result JSON.
- **REQ-DI-004** The skill owns four on-disk artifacts per job, all under `.rl/`:
  - `.rl/packets/<job_id>.md` — delegation packet (written by Driver)
  - `.rl/results/<job_id>.json` — structured result (written by Implementer)
  - `.rl/impl-log/<job_id>.log` — raw stdout/stderr (not watched by Driver)
  - `.rl/impl-events.jsonl` — lifecycle + progress event stream (watched by Driver)

### Delegation packet

- **REQ-DI-010** Packets are markdown files with YAML frontmatter. The body is prose instructions the Implementer reads; the frontmatter is parsed only by the wrapper.
- **REQ-DI-011** Frontmatter schema is documented in `schemas/packet.schema.json` and exemplified in `references/packet-authoring.md`. Drift between example and schema is a CI failure.
- **REQ-DI-012** Frontmatter required fields: `packet_id`, `created_at`, `provider`, `provider_args`, `spec_refs`, `plan_refs`, `scope`, `acceptance`.
- **REQ-DI-013** `scope` defines three file-pattern lists: `allowed_write`, `read_only_reference`, and an implicit deny-everything-else. The wrapper does not enforce these — the provider's sandbox does, combined with the prose instructions in the body.
- **REQ-DI-014** `provider_args.sandbox` accepts `yolo | workspace-write | read-only`. Skill default is `yolo`.
- **REQ-DI-015** Sandbox precedence from highest to lowest: environment variable `DELEGATE_CODEX_SANDBOX` → packet frontmatter → skill default. Env var is the top of the chain so that a session-level safety downgrade ("this session: no yolo") cannot be silently undone by a packet. Within that ordering, a packet can only restrict further; it can never escalate above the effective env-or-default level. The wrapper computes the effective level as `min(env, packet, default)` where the ordering is `read-only < workspace-write < yolo`, and rejects any packet whose declared level is higher than the env var with a clear error.
- **REQ-DI-016** Packets must include a `## Progress reporting` section with the standard `delegate-emit` call examples. The skill prose generates this section automatically when Opus composes a packet.

### Result schema

- **REQ-DI-020** Result files conform to `schemas/impl-result.schema.json`, enforced at runtime via `codex exec --output-schema`.
- **REQ-DI-021** Required fields: `status` (`complete | partial | blocked`), `summary` (≤800 chars), `files_changed` (array of paths).
- **REQ-DI-022** Optional fields: `commits`, `acceptance` (with per-check status), `blockers`, `handoff_notes` (≤1000 chars).
- **REQ-DI-023** All string fields have maximum length caps. Worst-case result JSON is ~3KB regardless of work volume. This is the Driver's primary context-protection mechanism.
- **REQ-DI-024** `additionalProperties: false` at every object level. The Implementer cannot smuggle extra fields past the schema.
- **REQ-DI-025** The `acceptance` array carries the Implementer's self-reported check results. The Driver is responsible for re-running any checks it considers load-bearing before trusting `status: complete`.

### Wrapper and helper scripts

- **REQ-DI-030** `scripts/delegate-codex-impl.sh` is the single entry point that runs one `codex exec` invocation. Target length ≤50 lines. Exceeding 50 lines is the signal to promote to Approach 2 (broker worker role).
- **REQ-DI-031** Wrapper parses packet frontmatter via `yq`, computes codex flags, sets `DELEGATE_JOB_ID` and prepends the skill's `scripts/` directory to `PATH` before invoking codex, so the Implementer can call `delegate-emit` without knowing install paths.
- **REQ-DI-032** Wrapper strips the YAML frontmatter before piping the packet body to `codex exec` on stdin. The Implementer never sees the frontmatter.
- **REQ-DI-033** Under normal operation the wrapper emits four events total: three lifecycle events in order (`implement-queued`, `implement-spawned`, `implement-started`) followed by exactly one terminal event — either `implement-completed` with a `verdict` field populated from the result file, or `implement-failed` with `error` and `duration_ms`. Progress events (`implement-progress`) are emitted separately by the Implementer via `delegate-emit` and are not counted in the wrapper's event budget.
- **REQ-DI-034** Wrapper has no pidfile, no cancellation handler, no retry logic. Those responsibilities live in the Driver (in-session judgment) or the future broker.
- **REQ-DI-035** `scripts/delegate-emit.sh` is called by the Implementer during execution to emit `implement-progress` events. Target length ≤25 lines.
- **REQ-DI-036** `delegate-emit` validates `--phase` against the allowlist `planning | implementing | testing | finalizing`. Invalid phase is a non-zero exit that the Implementer sees.
- **REQ-DI-037** `delegate-emit` caps `--message` at 120 characters (truncated, not rejected). Enforces INV-DI-10 at write time.
- **REQ-DI-038** `delegate-emit` requires `DELEGATE_JOB_ID` in the environment and fails fast if unset. Standalone invocation (without the wrapper) is impossible.

### Events and Monitor

- **REQ-DI-040** Events go to `.rl/impl-events.jsonl` in the project root, one JSON object per line, each line appended atomically via a single `>>` redirect from `jq -nc`.
- **REQ-DI-041** Event shape is byte-compatible with `rl`'s canonical `RlEvent` discriminated union in `src/events.ts`: each event has `ts` (ISO8601), `type` (discriminator), `job_id`, and type-specific fields. Promotion to Approach 2 is achieved by adding `implement-*` variants to the union and pointing the Wrapper at `.rl/events.jsonl` instead of `.rl/impl-events.jsonl`.
- **REQ-DI-042** Event type vocabulary for v1: `implement-queued`, `implement-spawned`, `implement-started`, `implement-progress`, `implement-completed`, `implement-failed`. No `implement-cancelled` in v1 (no cancellation).
- **REQ-DI-043** Monitor filter subscribed by the Driver matches `implement-(started|progress|completed|failed)`. Queued and spawned events are visible only via file inspection, not pushed to the Driver's notification stream.
- **REQ-DI-044** Monitor `timeout_ms` is 3600000 (60 minutes). This is a catastrophic safety net. Drift detection is a separate in-session judgment rule, not a Monitor capability.

### Progress reporting contract (Implementer-side)

- **REQ-DI-050** The Implementer emits exactly one `delegate-emit` call at each phase transition. Tool-call-level events are explicitly forbidden by the packet instructions.
- **REQ-DI-051** Phase vocabulary is exactly four: `planning`, `implementing`, `testing`, `finalizing`. Any additional granularity must be expressed via the `--message` text, not new phases.
- **REQ-DI-052** The Implementer emits `delegate-emit --phase X` *before* entering phase X, not after completing the previous one. A packet that completes without any progress events is considered malformed from a reporting standpoint (the work may still be valid).

### Drift detection and cancellation (Driver-side)

- **REQ-DI-060** Drift rule: if no `implement-progress` event arrives for 5 consecutive minutes and the job has not terminated, the Driver treats the job as drifted. The rule lives in skill prose, not in the wrapper or Monitor — it is an in-session judgment.
- **REQ-DI-061** On drift detection, the Driver's options are: (a) wait one additional cycle if the last phase was `testing` (long test runs are expected), (b) cancel via `pkill -f "codex exec.*<job_id>"`, or (c) escalate to the human. v1 does not prescribe which of (a)/(b)/(c) is correct — the skill prose describes the tradeoffs and leaves the choice to Opus.
- **REQ-DI-062** There is no automatic cancellation. The Driver must decide.

### Integration with `rl ralph`

- **REQ-DI-070** The skill is invoked from inside an active `rl ralph` iteration, after `.rl/task.md` has been crystallized. It does not initialize its own loop state.
- **REQ-DI-071** Delegation heuristic: delegate when the scope is a self-contained milestone in `PLAN.md` (or `.rl/task.md`) that a fresh-context Codex session can execute from the packet alone. If Opus cannot picture how to write the packet without paragraphs of caveats, the task is not a delegation candidate — Opus implements directly.
- **REQ-DI-072** After the Implementer completes and Opus reads the result, the ralph iteration proceeds normally — stop-hook fires, `rl review` is triggered, the reviewer audits the diff. The skill does not call `rl review` itself.
- **REQ-DI-073** The reviewer must not be told the diff came from a delegated worker. No annotations in commit messages identifying the source, no handoff notes pasted into review context. Audit integrity depends on the reviewer's fresh context.

### Provider interface

- **REQ-DI-080** A provider adapter lives in `references/providers/<name>.md` and must document four things: invocation pattern, sandbox-level mapping, result-contract support (can it honor `--output-schema`?), and dependency check.
- **REQ-DI-081** v1 ships a complete Codex adapter (`codex.md`) and stubs for Claude (`claude.md`) and Gemini (`gemini.md`).
- **REQ-DI-082** A stub adapter documents the template and explicitly states "not yet wired in v1" in its opening line. The wrapper will refuse to run a packet with `provider: claude` or `provider: gemini` with a clear error message.
- **REQ-DI-083** Adding a second provider in a future version requires: (a) filling in the stub `.md` file, (b) adding a provider-specific wrapper script alongside `delegate-codex-impl.sh`, (c) the main wrapper dispatches to the provider-specific script based on the packet's `provider` field. No changes to `delegate-emit`, the event schema, or the result schema are required — those are provider-agnostic by design.

### Dependencies

- **REQ-DI-090** Hard runtime dependencies: `codex` (CLI), `yq`, `jq`, `git`. Missing any of these causes the wrapper to exit non-zero with a clear message before emitting any events.
- **REQ-DI-091** The skill's SKILL.md instructs Opus to verify these dependencies exist at invocation time, before writing the first packet.

## Invariants

- **INV-DI-01** Raw provider stdout, token deltas, reasoning summaries, and tool-call traces MUST NOT appear in `.rl/impl-events.jsonl`. Only structured lifecycle and progress events with bounded message fields. Mirrors rl's `INV-10`.
- **INV-DI-02** Every event file line is one complete JSON object with `ts`, `type`, and `job_id`. Partial lines are never observed (atomic append).
- **INV-DI-03** The Implementer cannot emit events without the wrapper's environment (enforced by `DELEGATE_JOB_ID` check in `delegate-emit`). Rogue event injection from outside a running job is impossible by construction.
- **INV-DI-04** The result JSON cannot exceed ~3KB under normal operation due to per-field caps in the schema. Opus context cost per delegation is bounded.
- **INV-DI-05** The reviewer's context contains no reference to the delegation. Audit integrity is preserved as an invariant of the integration, not a best-effort convention.

## Acceptance Criteria

### Skill artifacts exist and validate

- [ ] `SKILL.md` exists with frontmatter matching the Claude Code skill format, and the description triggers on delegation tasks without false positives on general implementation work
- [ ] `scripts/delegate-codex-impl.sh` is ≤50 lines and passes `shellcheck` with zero warnings
- [ ] `scripts/delegate-emit.sh` is ≤25 lines and passes `shellcheck` with zero warnings
- [ ] `schemas/impl-result.schema.json` compiles with `ajv compile` without errors
- [ ] `schemas/packet.schema.json` validates the example packet in `references/packet-authoring.md`

### Smoke test passes

- [ ] Running the wrapper with a trivial packet (create `/tmp/delegate-smoke.txt` with fixed content) produces a result JSON with `status: complete` and the file path in `files_changed`
- [ ] The same smoke run emits at least one `implement-started`, one `implement-progress`, and one `implement-completed` event in `.rl/impl-events.jsonl`
- [ ] The target file exists with the expected content after the smoke run
- [ ] The wrapper exits 0 on the smoke run

### Unit tests pass

- [ ] `delegate-emit` rejects an invalid `--phase` with non-zero exit and writes no event
- [ ] `delegate-emit` rejects a missing `DELEGATE_JOB_ID` with non-zero exit
- [ ] `delegate-emit` truncates messages over 120 characters cleanly (no partial unicode, no crash)
- [ ] Wrapper rejects a packet whose `provider_args.sandbox` is higher than `DELEGATE_CODEX_SANDBOX` with a clear error and non-zero exit
- [ ] Wrapper exits with a clear error if any of `codex`, `yq`, `jq`, `git` is missing from `PATH`

### Dogfood validation

- [ ] The skill successfully drives the rl-broker `implement` worker extension work as a separate brainstorm → plan → execute cycle, Codex produces a working extension, and the existing `rl review` gate approves the diff. If this succeeds, skill v1 is considered proven. If it fails, the failure mode is the input to a follow-up design cycle — no retro-fixes to v1 itself without that new cycle.

## File Layout

```
<skill-root>/
├── SKILL.md
├── scripts/
│   ├── delegate-codex-impl.sh
│   └── delegate-emit.sh
├── schemas/
│   ├── packet.schema.json
│   └── impl-result.schema.json
└── references/
    ├── event-shape.md
    ├── packet-authoring.md
    ├── drift-detection.md
    └── providers/
        ├── codex.md
        ├── claude.md
        └── gemini.md
```

Runtime artifacts under the project being worked on:

```
<project-root>/.rl/
├── packets/<job_id>.md
├── results/<job_id>.json
├── impl-log/<job_id>.log
├── impl-events.jsonl
└── events.jsonl            # existing rl canonical, untouched
```

## Approach 2 promotion path

When the skill graduates to a first-class broker worker, the mechanical steps are:

1. Add `ImplementQueuedEvent`, `ImplementSpawnedEvent`, `ImplementStartedEvent`, `ImplementProgressEvent`, `ImplementCompletedEvent`, `ImplementFailedEvent`, and optionally `ImplementCancelledEvent` to `RlEvent` in `rl/src/events.ts`. Extend `KNOWN_EVENT_TYPES` accordingly. A new REQ-RL-* entry authorizes the union change.
2. Extend `WorkerQueuedEvent.kind` from `'review'` to `'review' | 'implement'`.
3. Create `rl/src/worker/impl-worker.ts` mirroring `review-worker.ts`, port the wrapper's codex invocation into TypeScript.
4. Add a new CLI command `rl implement <packet-file>` or a `--implementer` flag on `rl ralph`.
5. Point the skill's wrapper at the new broker command; the skill scripts become thin shims during the transition, then are deleted when confidence is high.
6. Event emission moves from `delegate-emit` + wrapper shell to the broker's `emitEvent` TypeScript path. Write destination moves from `.rl/impl-events.jsonl` to `.rl/events.jsonl`. The Driver's Monitor filter updates to target the canonical file.

None of these steps require changing the packet format, result schema, or provider interface. Those are stable from v1 by design.

## Open questions for the implementation plan

These are explicitly deferred to the planning phase and listed here so they don't get lost:

- **OQ-1** Exact `SKILL.md` description text — needs to trigger Opus's delegation reflex without matching every "implement X" request.
- **OQ-2** Exact `shellcheck` configuration (which checks to enable/disable for the wrapper scripts).
- **OQ-3** Whether `delegate-emit` should ship a completion installer that symlinks it into `~/.local/bin` for humans who want to call it directly in test scripts, or whether test scripts should invoke it via its full path.
- **OQ-4** Whether the smoke test runs in CI (needs codex available) or only locally on the maintainer's machine.
- **OQ-5** Where the skill source lives in the dotfiles tree — likely under `claude-code/.claude/skills/delegate-implementer/` following the repo's existing convention, but confirming in the plan.

## Testing Strategy

Four layers, in order of cost:

1. **Shellcheck on every script** (cheap, CI).
2. **JSON Schema compile check** via `ajv` (cheap, CI).
3. **Unit tests on `delegate-emit`** via `bats` or plain bash (cheap, CI).
4. **Wrapper smoke test** running a real `codex exec` invocation against a trivial packet (local-only in v1; needs codex auth).
5. **Dogfood validation** — the skill drives the rl-broker extension build. This is the real signal.

No mock provider. No recorded-response replay. Provider behavior is the thing under validation, and faking it is worse than not testing.

## Security and Safety Considerations

- **S-1** Yolo sandbox mode is the default at the user's explicit request (`rl ralph` context, trusted workspace). This is not a vulnerability — it's a deliberate configuration choice documented in REQ-DI-014.
- **S-2** The wrapper runs inside the user's existing shell and git context. No privilege escalation, no network exposure beyond what `codex exec` itself performs.
- **S-3** `delegate-emit` cannot be tricked into writing malformed events (phase allowlist, message truncation, `DELEGATE_JOB_ID` requirement).
- **S-4** The result schema's `additionalProperties: false` plus per-field length caps prevent the Implementer from exfiltrating large blobs through the result path into Driver context.
- **S-5** The packet body is written to `.rl/packets/<job_id>.md` and is not marked sensitive. Packets may reference spec files but should not include secrets; this is Opus's responsibility when composing them, documented in `references/packet-authoring.md`.
