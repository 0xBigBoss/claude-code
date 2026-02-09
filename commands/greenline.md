---
description: Sequenced tilt bootstrap then e2e test baseline improvement. Runs tiltup workflow, then e2e test loop with categorized fixes and conventional commits. Not for unit-test-only projects or non-tilt dev environments.
argument-hint: [test filter] [--skip-tilt] [--no-commit]
---

# Greenline

Bootstrap dev environment, then improve e2e test baseline through categorized fix iterations.

## Arguments

$ARGUMENTS

- **TEST_FILTER**: grep/filter for test files or names (e.g., `transfer`, `auth.spec.ts`)
- **--skip-tilt**: Skip Phase 1 (tilt already healthy)
- **--no-commit**: Skip committing fixes

## Phase 1: Tilt Bootstrap (skip if `--skip-tilt`)

Follow the `tiltup` skill workflow. Exit when all resources reach `runtime=ok, update=ok`.

If a resource cannot be fixed after 3 iterations, report it and continue to Phase 2 — it may not block e2e tests.

## Phase 2: E2E First Run

1. Discover e2e config and the canonical test command
2. Verify tilt environment is serving
3. Locate spec files for bug verification
4. Run suite (apply TEST_FILTER if provided), record pass/fail baseline

## Phase 3: Categorize and Fix (Loop)

Follow the `e2e` skill taxonomy and fix rules. Fix in priority order: flaky, outdated, bug. Report unverified failures without fixing.

After each logical fix or batch (unless `--no-commit`):
- Run builds, checks, unit tests
- Commit per `git-best-practices` with scope: `fix(e2e): ...` for test fixes, `fix(scope): ...` for bug fixes

Re-run suite after fixes. If failures changed, repeat categorization.

**Exit**: pass count improved from baseline AND no actionable failures remain.

## Phase 4: Report

Combine `tiltup` and `e2e` skill report formats:

```
## Greenline Report

**Tilt**: <healthy|skipped|degraded>
**E2E**: X/Y passed (was A/B on first run)

### Fixed
- CATEGORY: `file:line` — what was fixed

### Remaining
- UNVERIFIED: `file:line` — needs spec or user decision

### Commits
- `hash` type(scope): description
```

## Ralph Integration

For autonomous execution: `/ralph /greenline [args]`
