---
argument-hint: "[optional eta or focus]"
description: Use when the user signals they're stepping away (brb, afk, heading out) — keep working autonomously, skip anything that needs interactive approval, handoff when done or blocked.
disable-model-invocation: true
---

# BRB Mode

The user is stepping away and **cannot approve interactive prompts** (1Password, SSH agent, Touch ID, sudo, browser dialogs). Keep working autonomously, then leave a `/handoff` so they can pick up when back.

Treat this as a standing behavioral mode for the rest of the session. Exit the mode when the user sends any new message, unless they explicitly extend it ("still afk, keep going"). A new prompt is the signal they're back.

The rules below apply to **every** tool invocation in this session — bash commands, MCP tool calls, sub-agent delegations, browser automation. Do not silently exempt a category just because it isn't enumerated.

## Extra context from the user

$ARGUMENTS

## Rules while AFK

### Keep doing
- Edit files, read files, grep, run tests, run builds, run typecheckers
- `git add`, `git status`, `git diff`, `git log`, `git branch`
- `git commit` — the user does not sign commits, so this won't prompt. Make multiple small commits at natural checkpoints; easier to review later.
- `gh pr view`, `gh pr diff`, `gh issue view`, `gh run view`, anything `gh` read-only (uses HTTPS token, no SSH)
- `gh pr create`, `gh pr comment`, `gh issue comment` — fine, HTTPS token-based
- Background tasks that don't need approval
- Sub-agents (Explore, code-reviewer, etc.) — **subagents start in a fresh context and won't see this skill**. When delegating during /brb, prepend the AFK constraint to the delegation prompt, e.g.: `User is AFK. Do not run any command that requires 1Password / SSH agent / Touch ID / sudo approval. If you hit one, note it and stop.`

### Do NOT do
Any command that triggers 1Password / SSH agent / Touch ID / interactive prompt. Skip these proactively — don't attempt and time out.

- `git push`, `git push --force` — SSH agent approval
- `git fetch`, `git pull` — SSH agent approval (remotes are SSH)
- `op read`, `op item get`, `op signin`, anything `op` that touches a vault
- `ssh-add`, `ssh <host>` for new connections needing keys
- `gh auth login`, `gh auth refresh`, `gh auth setup-git`
- `npm login`, `npm publish`, `yarn publish`, `cargo publish`
- `sudo <anything>` if the sudo timestamp isn't already cached
- Browser dialogs / `alert()` / `confirm()` via Claude-in-Chrome — these freeze the session
- Any new MCP `authenticate` flow

### If something needs approval anyway
Don't retry. Note it in the handoff queue and move on if other work is available. If approval-blocked work is the *only* remaining task, halt and write the handoff now.

### If you need a secret that's normally in 1Password
Don't fetch it. Note in the handoff that the next step needs `<secret name>` and how to retrieve it (e.g., `op read "op://Private/foo/credential"`).

## Definition of done

Keep working until one of:
1. **All local checks pass and only the push remains** — preferred outcome. Stage and commit everything; the handoff lists the exact `git push` to run.
2. **A decision blocker** — ambiguous requirement, two viable approaches, missing context only the user has.
3. **All work is blocked behind an approval gate** that you've already deferred.

Do not stop early just because the queue is "mostly" done. AFK is a chance to work the queue.

## Wrapping up

When you hit a stopping point:

1. Make sure all work is committed locally. Don't leave large uncommitted diffs — the user can `git push` everything at once when back.
2. Invoke `/handoff` with focus set to: `AFK session — what's done, what's deferred behind approval gates, what (if anything) needs a decision`
3. After `/handoff` writes the file, post a short chat summary: number of unpushed commits, the exact `git push` line, and any deferred-approval items.

<example>
Handoff saved to ~/.handoffs/handoff-myapp-feat-xyz-20260523-1830.md

3 unpushed commits on `feat/xyz`. When back:
  git push

Deferred (needed approval):
  - `op read "op://Private/stripe/api-key"` for the integration test
  - `gh auth refresh` (token expires today per gh status)
</example>
