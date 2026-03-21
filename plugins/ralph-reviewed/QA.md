# Ralph Reviewed QA

End-to-end test of the ralph-reviewed plugin v2.0.0. Run this from a test repo to verify the full loop works — `rl` CLI, stop hook, Codex review gate, feedback cycle.

## Prerequisites

- Test repo at `/tmp/ralph-test` with a broken `math.ts` (see setup below)
- Plugin loaded via `--plugin-dir ~/code/dotfiles/claude-code/plugins/ralph-reviewed`
- `codex` CLI installed and authenticated (for review gate tests)

## Setup

If the test repo doesn't exist, create it:

```bash
rm -rf /tmp/ralph-test && mkdir -p /tmp/ralph-test && cd /tmp/ralph-test && git init -q && echo '# test' > README.md && git add -A && git commit -q -m "init"
cat > /tmp/ralph-test/math.ts <<'EOF'
// TODO: implement add, subtract, multiply, divide
export function add(a: number, b: number): number {
  return 0; // broken
}

export function divide(a: number, b: number): number {
  return a / b; // no zero check
}
EOF
git -C /tmp/ralph-test add -A && git -C /tmp/ralph-test commit -q -m "add broken math module"
```

## Test: Full loop with review

```
/ralph-reviewed:ralph-loop "Fix math.ts: 1) add() should return a+b, 2) add subtract(a,b) and multiply(a,b), 3) divide() needs to throw on division by zero. Commit each fix separately. Use .rl/rl log for each phase." --max-iterations 10 --max-reviews 3
```

### What to verify during the loop

**rl init:**
- [ ] `rl init` is found and runs (check `find` or fallback path)
- [ ] `.rl/state.json` exists with lean schema: `active`, `iteration`, `max_iterations`, `timestamp`, `review_enabled`, `review_count`, `max_review_cycles`, `debug` — no `completion_promise`, `original_prompt`, `pending_feedback`, `review_history`
- [ ] `.rl/prompt.md` exists with the task text
- [ ] `.rl/rl` symlink exists and works (`rl status` returns output)
- [ ] `.rl/` is in `.git/info/exclude`

**Agent work:**
- [ ] Agent uses `.rl/rl log phase` for each phase
- [ ] Agent uses `.rl/rl log commit` after each commit
- [ ] Agent uses `.rl/rl done` to signal completion (not bare `COMPLETE` text)
- [ ] Iteration headers from the stop hook show no denominators (e.g. `Iteration 1` not `Iteration 1/10`)

**Codex review gate (if review enabled):**
- [ ] Stop hook triggers Codex review after `.rl/rl done`
- [ ] Review output saved to `.rl/codex-review-*.txt` (not deleted)
- [ ] If rejected: feedback is plain text, fed back to agent, agent gets another iteration
- [ ] If approved: loop exits cleanly with approval message
- [ ] Reviewer does NOT flag `.rl/` directory, process compliance, or git hygiene
- [ ] Reviewer focuses on code correctness and task requirements

**After loop ends:**
- [ ] `state.json` is deleted (cleanup on approve/max/blocked)
- [ ] `prompt.md`, `log.jsonl`, review outputs persist in `.rl/`
- [ ] `.rl/rl clean` removes the entire `.rl/` directory

### What to watch for (bugs and edge cases)

**rl CLI:**
- Does `rl init` fail if `.rl/` already exists from a previous run?
- Does `rl done` fail if `state.json` is missing?
- Does `rl log` fail if `.rl/` doesn't exist yet?
- Does the `.rl/rl` symlink survive across iterations?

**Stop hook:**
- Does the hook correctly detect `completion_claimed` from fresh state.json re-read?
- Does the hook clear `completion_claimed` on the next iteration write (via `serializeState` which doesn't include the flag)?
- Does the `blocked_claimed` flag work the same way?
- If the agent runs `.rl/rl done` but then the review rejects, does the next iteration NOT think completion is still claimed?
- What happens if max iterations and max reviews are both hit simultaneously?

**Codex review:**
- Does the reviewer actually run `.rl/rl prompt` to read the task?
- Does the reviewer use `cat .rl/log.jsonl` for context?
- Does the reviewer log its own findings via `.rl/rl log decision`?
- Is the review output in `.rl/` (not `/tmp/`)?
- Does the review prompt avoid triggering pedantic behavior (process compliance, delivery flow, git hygiene)?

**Feedback cycle:**
- Is the reviewer's free-text feedback passed through to the agent cleanly?
- Does the agent get the original prompt re-injected on rejection?
- Does the `getLastRejectFeedback` function correctly find the last reject entry in log.jsonl?

## Test: No-review mode

```
/ralph-reviewed:ralph-loop "Fix add() in math.ts to return a+b. Add subtract and multiply. Commit." --max-iterations 5 --no-review
```

- [ ] Loop runs without Codex
- [ ] `.rl/rl done` exits the loop immediately (no review gate)
- [ ] `.rl/rl done --blocked` exits with BLOCKED message

## Test: rl clean

After any test:

```bash
.rl/rl clean
ls .rl/  # should fail — directory gone
```

## Cleanup

```bash
rm -rf /tmp/ralph-test
```
