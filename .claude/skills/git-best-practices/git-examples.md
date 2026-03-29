# Git Examples Reference

## Commit Message Examples

<examples>

<example name="simple-fix">
Single-line fix, no body needed:

```
fix(shell): restore Alt+F terminal navigation
```
</example>

<example name="scoped-with-body">
Non-obvious fix with body explaining root cause:

```
fix(shell): use HOMEBREW_PREFIX to avoid path_helper breaking plugins in login shells

macOS path_helper reorders PATH in login shells, putting /usr/local/bin
before /opt/homebrew/bin. This caused `brew --prefix` to resolve the stale
Intel Homebrew, so fzf, zsh-autosuggestions, and zsh-syntax-highlighting
all silently failed to load in Ghostty (which spawns login shells).

Use the HOMEBREW_PREFIX env var (set by brew shellenv in .zshenv) instead
of calling `brew --prefix` — it survives path_helper and is faster.
```
</example>

<example name="multi-part-feature">
Feature with bullet-list body for multi-part changes:

```
feat(install): add claude bootstrap runtime management

- migrate Claude defaults to declarative files under claude/defaults
- add claude-bootstrap check/fix/uninstall with backup-first migration
- stop stowing full claude/codex runtime trees and tighten drift checks
```
</example>

<example name="ticket-linked">
Monorepo commit with ticket reference in branch and scope:

```
fix(pool-party): handle stale settlement state on reconnect

PoolSettlement contract stays in pending state when the participant
disconnects mid-settlement. Check settlement timestamp and expire
stale entries on reconnect.

Fixes SEND-718
```
</example>

<example name="submodule-bump">
Submodule update with downstream commit info:

```
chore(submodule): update claude-code

Bump claude-code to 88d0c75 (feat(skills): add tiltup, specalign, and e2e skills).
```

For trivial bumps, `bump` or `bump claude-code submodule` is acceptable.
</example>

<example name="breaking-change">
Breaking change using `!` suffix:

```
refactor(api)!: change auth endpoint response format

The /auth/token endpoint now returns { access_token, expires_in }
instead of { token, expiry }. All clients must update their parsers.
```
</example>

</examples>

## Branch Discovery Fallback

Use when `gh` is unavailable or the repo has no remote:

```bash
# Infer default branch from local refs
git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/origin/@@'

# Last resort: check local branches and fail loudly if unknown
if git rev-parse --verify main >/dev/null 2>&1; then
  echo main
elif git rev-parse --verify master >/dev/null 2>&1; then
  echo master
else
  echo "ERROR: unable to determine default branch (main/master not found)." >&2
  exit 1
fi
```
