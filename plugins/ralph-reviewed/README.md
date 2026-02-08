# Ralph Reviewed

An iterative development loop with Codex review gates. Fork of [ralph-wiggum](https://github.com/anthropics/claude-plugins-official/tree/main/plugins/ralph-wiggum) with added code review at completion.

## How It Works

```
┌─────────────────────────────────────────────────────────────┐
│                                                             │
│   Claude works ──► Claims done ──► Codex reviews            │
│        ▲                               │                    │
│        │                          ┌────┴────┐               │
│        │                          ▼         ▼               │
│        │                      APPROVE    REJECT             │
│        │                          │         │               │
│        │                        EXIT    feedback            │
│        │                                    │               │
│        └────────────────────────────────────┘               │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

1. Start a loop with a task description
2. Claude works iteratively until it believes the task is complete
3. When Claude outputs the completion promise, Codex reviews the work
4. If approved: loop ends successfully
5. If rejected: Claude receives feedback and continues working
6. After max review cycles, loop ends with final feedback

## Installation

### From Marketplace (Recommended)

```bash
# 1. Add the marketplace
/plugin marketplace add 0xbigboss/plugins

# 2. Install the plugin
/plugin install ralph-reviewed@0xbigboss-plugins
```

Or use the interactive plugin manager:

```bash
/plugin
```

Navigate to the **Discover** tab to browse and install.

### From Local Development

If developing locally or using dotfiles:

```bash
# Add local path as marketplace
/plugin marketplace add ~/code/dotfiles/claude-code/plugins

# Install from local
/plugin install ralph-reviewed@local
```

## Commands

### `/ralph-reviewed:ralph-loop`

Start an iterative loop with review gates.

```bash
/ralph-reviewed:ralph-loop "Your task description" [options]
```

**Options:**

| Flag | Default | Description |
|------|---------|-------------|
| `--max-iterations` | 50 | Max work iterations before auto-stop |
| `--max-reviews` | max-iterations | Max review cycles before force-complete |
| `--completion-promise` | COMPLETE | Phrase that signals completion |
| `--no-review` | false | Disable Codex review gate |
| `--debug` | false | Write debug logs to `/tmp/ralph-reviewed-{session_id}.log` |

**Examples:**

```bash
# Basic usage
/ralph-reviewed:ralph-loop "Build a REST API with CRUD for todos. Include tests. Output COMPLETE when done."

# With options
/ralph-reviewed:ralph-loop "Fix the auth bug in src/auth.ts" \
  --max-iterations 20 \
  --max-reviews 2 \
  --completion-promise "FIXED"

# Without review (original ralph behavior)
/ralph-reviewed:ralph-loop "Refactor the utils module" --no-review
```

### `/ralph-reviewed:cancel-ralph`

Cancel the active loop immediately.

### `/ralph-reviewed:help`

Show help and usage information.

## Writing Good Prompts

### Include Clear Success Criteria

```
Build a user registration API.

Requirements:
- POST /register accepting email and password
- Password hashing with bcrypt
- Email validation (valid format)
- Return 201 with user ID on success
- Return 400 with error message on invalid input
- Tests for all cases

When all tests pass, output <promise>COMPLETE</promise>
```

### Include Verification Steps

```
Fix the authentication middleware bug.

Verification:
1. Run `npm test src/auth.test.ts` - all tests pass
2. Run `npm run lint` - no errors
3. Manual check: login flow works in dev

When verified, output <promise>FIXED</promise>
```

### Set Escape Conditions

The `<promise>BLOCKED</promise>` signal is a built-in escape hatch that terminates the loop immediately without triggering a Codex review. Use it when genuinely stuck:

```
Implement the search feature.

If blocked by external issues (missing deps, pre-existing bugs, etc.):
- Document what's blocking and what you tried
- Output <promise>BLOCKED</promise>
```

Note: BLOCKED terminates the loop without review since there's nothing to review when blocked.

## Review Gate

When Claude outputs the completion promise, Codex CLI is invoked to review:

- **Original task** - What was requested
- **Work summary** - Recent Claude output
- **Git diff** - Code changes made

Codex responds with:
- `<review>APPROVE</review>` - Work meets requirements
- `<review>REJECT</review>` with `<issues>` block - Needs changes

On rejection, Claude receives structured feedback with tagged issues (e.g., `[ISSUE-1] major: description`) and continues working. After `--max-reviews` cycles, the loop ends regardless (to prevent infinite ping-pong).

## Requirements

- **Git repository** - State file is stored at repo root to survive directory changes
- **Bun** - For TypeScript hook execution
- **codex** - Codex CLI for reviews (optional - degrades gracefully if missing)
- **git** - For diff generation and repo root detection

## Configuration

### User Preferences

Configure Codex reviewer behavior via `~/.claude/codex.json`:

```json
{
  "codex": {
    "sandbox": "read-only",
    "approval_policy": "never",
    "bypass_sandbox": false,
    "extra_args": [],
    "timeout_seconds": 1200
  }
}
```

**Options:**

| Key | Values | Default | Description |
|-----|--------|---------|-------------|
| `sandbox` | `read-only`, `workspace-write`, `danger-full-access` | `read-only` | Codex sandbox mode |
| `approval_policy` | `untrusted`, `on-failure`, `on-request`, `never` | `never` | When Codex asks for approval |
| `bypass_sandbox` | `true`, `false` | `false` | Bypass sandbox entirely (overrides sandbox/approval_policy) |
| `extra_args` | string array | `[]` | Additional CLI args passed to Codex (appended last, can override earlier flags) |
| `timeout_seconds` | number | `1200` | Timeout for Codex review call (20 minutes default) |

**Example: Full permissions for tooling (tsc, linters, tests):**

```json
{
  "codex": {
    "bypass_sandbox": true
  }
}
```

This allows Codex to run build tools, linters, and tests during review. Without this, Codex runs in read-only mode and cannot verify tooling-based success criteria.

**Example: Write access without full bypass:**

```json
{
  "codex": {
    "sandbox": "workspace-write",
    "approval_policy": "never"
  }
}
```

### Loop State

State is stored in `.claude/ralph-loop.local.md` at the **git repository root**. This ensures the loop survives directory changes within the repo. The file tracks:

- Current iteration count
- Max iterations
- Completion promise
- Original prompt
- Review count
- Pending feedback

Do not edit this file manually. Use `/ralph-reviewed:cancel-ralph` to stop.

## Differences from ralph-wiggum

| Feature | ralph-wiggum | ralph-reviewed |
|---------|-------------|----------------|
| Review gate | No | Yes (Codex CLI) |
| Max review cycles | N/A | Configurable |
| Feedback injection | No | Yes |
| Graceful degradation | N/A | Yes (if Codex unavailable) |
| Hook language | Bash | TypeScript (Bun) |
| Directory change handling | Breaks | Survives (uses git root) |
| Debug logging | No | Yes (`--debug` flag) |
| BLOCKED escape | No | Yes (terminates without review) |

## Troubleshooting

**Loop won't stop:**
- Use `/ralph-reviewed:cancel-ralph` to force stop
- Verify completion promise matches exactly (case-insensitive)

**State file not found after directory change:**
- Ensure you're in a git repository (`git rev-parse --show-toplevel`)
- State file is at repo root: `{GIT_ROOT}/.claude/ralph-loop.local.md`
- Outside git repos, directory changes will break the loop

**Reviews not happening:**
- Check `codex` CLI is installed: `which codex`
- Check `--no-review` is not set
- Check `.claude/ralph-loop.local.md` has `review_enabled: true`

**Codex can't run tooling (EPERM errors, tsc/lint/test fails):**
- By default, Codex runs in read-only sandbox mode
- Set `"bypass_sandbox": true` in `~/.claude/codex.json`
- See [User Preferences](#user-preferences) for full config options

**Too slow:**
- Reduce `--max-iterations` for faster feedback
- Reduce `--max-reviews` if reviews are redundant

**Review timing out:**
- Default timeout is 1200 seconds (20 minutes)
- Increase via `~/.claude/codex.json`: `"timeout_seconds": 1800`
- Must be less than plugin hook timeout (1800s)

**Debugging:**
- Use `--debug` flag to enable logging
- Session logs: `~/.claude/ralphs/{session_id}/debug.log`
- Crash logs: `~/.claude/ralphs/{session_id}/crash.log`
- Pre-session startup log: `~/.claude/ralphs/startup.log`

## Credits

Based on the [Ralph Wiggum technique](https://ghuntley.com/ralph/) by Geoffrey Huntley and the [official Claude plugin](https://github.com/anthropics/claude-plugins-official/tree/main/plugins/ralph-wiggum).
