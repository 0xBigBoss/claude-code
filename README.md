# Claude Code Configuration

Personal configuration for [Claude Code](https://docs.anthropic.com/en/docs/claude-code): agent guidelines, slash commands, subagents, language-specific skills, plugins, a Zig statusline, and a settings baseline. Designed to be usable as a standalone repo or as a submodule of a larger dotfiles tree.

## Quick Start

Clone the repo anywhere, then run the installer to symlink runtime assets into `~/.claude/`:

```bash
git clone https://github.com/alleneubank/claude-code.git ~/code/claude-code
cd ~/code/claude-code
./install.sh             # apply symlinks
./install.sh --check     # report drift without changing anything
```

The installer is idempotent. It links:

- `CLAUDE.md` → `~/.claude/CLAUDE.md` (agent guidelines)
- `commands/` → `~/.claude/commands/` (slash commands)
- `agents/` → `~/.claude/agents/` (subagents)
- `.claude/skills/` → `~/.claude/skills/` (best-practices skills)
- `codex.json` → `~/.claude/codex.json` (Codex CLI config for the `codex-reviewer` plugin)

Settings, statusline binary, and plugins are opt-in — see the sections below.

## Repository Layout

```
claude-code/
├── CLAUDE.md                    # Agent guidelines (linked into ~/.claude/CLAUDE.md)
├── codex.json                   # Codex CLI defaults (linked into ~/.claude/codex.json)
├── install.sh                   # Idempotent symlink installer
├── commands/                    # Slash commands
├── agents/                      # Subagents
├── .claude/skills/              # Best-practices skills (auto-load by file context)
├── .claude-plugin/              # Marketplace manifest for the bundled plugins
├── plugins/                     # Source for plugins published via marketplace.json
│   ├── codex-reviewer/          # Codex CLI review gate
│   └── ralph-reviewed/          # Iterative loop with Codex review
├── codex-overrides/skills/      # Codex-only skill overrides applied during sync
├── settings/settings.json       # Settings baseline (copy or merge into ~/.claude/settings.json)
├── statusline/                  # Zig statusline (build separately, see below)
├── hooks/direnv-bash-env        # BASH_ENV shim that loads direnv on subshell cd
├── scripts/                     # Usage tracking, codex sync, plugin version checks
└── analytics/                   # Submodule: claude-code-analytics (transcript analyzer)
```

## Commands

Invoked with `/<name>` in Claude Code. Sources live in `commands/`.

| Command | Description |
|---------|-------------|
| `/commit` | Stage, draft, and create a conventional git commit from the current diff |
| `/fix-issue <id>` | Find and fix an issue end-to-end with tests and a PR description |
| `/greenline` | Tilt bootstrap then iterative e2e baseline improvement with categorized fixes |
| `/handoff` | Generate a self-contained handoff prompt for another agent (writes to `~/.handoffs/`) |
| `/rewrite-history` | Rewrite the current branch with a clean narrative commit history |
| `/specout` | Interview-driven workflow to fill gaps in a `SPEC.md` |
| `/triage` | Interactive Linear issue triage with codebase verification |

## Subagents

Custom subagents in `agents/`. Claude Code delegates automatically when their description matches the task.

| Agent | Purpose |
|-------|---------|
| `code-reviewer` | Reviews changes for quality, security, and project conventions |
| `debugger` | Investigates failures through root cause analysis |
| `refactorer` | Restructures code with clean breaks and complete migrations |
| `test-writer` | Writes tests that verify correctness without gaming assertions |

## Skills

Best-practices skills in `.claude/skills/` are auto-loaded when the file context matches their triggers. The full set:

| Skill | Use when |
|-------|----------|
| `atlas-best-practices` | Editing `atlas.hcl`, schema HCL/SQL, or planning Atlas migrations |
| `axe-ios-simulator` | Driving the iOS Simulator via AXe (screenshots, accessibility, automation) |
| `brief-best-practices` | Creating, reviewing, or updating `BRIEF.md` (the quality law for a surface) |
| `canton-network-repos` | Working with Canton Network participants, Daml, or Splice |
| `e2e` | Running, debugging, or fixing e2e tests |
| `electrobun-best-practices` | Building Electrobun desktop apps |
| `git-best-practices` | Commits, branches, PRs, rewriting history |
| `git-rebase-sync` | Rebasing a feature branch onto its base |
| `git-worktree-tidy` | Pruning stale local branches and worktrees |
| `go-best-practices` | Reading or writing `.go` files |
| `improve` | Surfacing concrete improvements after a task |
| `nix-best-practices` | Editing flakes, overlays, `shell.nix`, `flake.nix` |
| `op-cli` | Reading secrets from 1Password via `op` |
| `orbstack-best-practices` | OrbStack Linux VMs and Docker on macOS |
| `playwright-best-practices` | Writing or modifying Playwright tests |
| `python-best-practices` | Reading or writing Python files |
| `react-best-practices` | Reading or writing React components |
| `spec-best-practices` | Creating, reviewing, or updating `SPEC.md` |
| `tamagui-best-practices` | Working in Tamagui projects |
| `testing-best-practices` | Designing tests and planning test strategy |
| `tilt` | Reading Tilt status, logs, working with Tiltfiles |
| `tiltup` | Bootstrapping Tilt to a healthy state |
| `typescript-best-practices` | Reading or writing TypeScript / JavaScript files |
| `web-fetch` | Fetching web content as clean markdown |
| `zig-best-practices` | Reading or writing Zig files |
| `zmx` | Managing long-lived dev processes via `zmx` |

## Plugins

This repo also doubles as a Claude Code plugin marketplace via `.claude-plugin/marketplace.json`. Two plugins ship from it:

| Plugin | Description |
|--------|-------------|
| `ralph-reviewed` | Iterative Ralph loop with a Codex CLI review gate at completion |
| `codex-reviewer` | Standalone Codex-powered code review gate |

### Install as a marketplace

```bash
# Inside Claude Code:
/plugin marketplace add alleneubank/claude-code
/plugin install ralph-reviewed@0xbigboss-plugins
/plugin install codex-reviewer@0xbigboss-plugins
```

Or install from a local checkout:

```bash
/plugin marketplace add ~/code/claude-code
```

Both plugins read `~/.claude/codex.json` for sandbox/approval/timeout settings — `install.sh` puts a default copy there. See `plugins/ralph-reviewed/README.md` for the full schema.

## Settings Baseline

`settings/settings.json` is an opinionated baseline you can adopt as-is or use as a reference:

- `permissions.allow` pre-approves common read-only and safe-write Bash patterns (git, npm/bun/yarn, zig, go, tilt, kubectl, docker, gh) plus a few skills.
- `extraKnownMarketplaces` declares plugin marketplaces; `enabledPlugins` controls which are turned on.
- `statusLine.command` invokes the Zig statusline binary (see below).
- `env.BASH_ENV` points at `hooks/direnv-bash-env` so subshells reload direnv on `cd`.

This file ships with author-specific marketplace pointers (e.g. private Send/Canton repos) and a hard-coded `BASH_ENV` path. If you adopt it, edit those fields to match your machine. The simplest path is to copy it once and treat `~/.claude/settings.json` as yours:

```bash
cp settings/settings.json ~/.claude/settings.json
```

The author personally generates `~/.claude/settings.json` via a private merge helper in the surrounding dotfiles tree (baseline + `~/.claude/settings.local.json` overrides). That helper is not required to use this repo — direct copy works fine.

## Statusline

A small Zig statusline lives in `statusline/`. It reads JSON on stdin and prints one formatted status line.

```bash
cd statusline
zig build -Doptimize=ReleaseFast
# binary lands at statusline/zig-out/bin/statusline
```

Point Claude Code at it by setting `statusLine.command` in `~/.claude/settings.json` (the baseline already does this). Minimum Zig: `0.16.0`. See `statusline/CLAUDE.md` and `statusline/SPEC.md` for build, runtime contract, and design notes.

## Scripts

`scripts/` contains optional utilities:

| Script | Purpose |
|--------|---------|
| `setup-usage-tracking.py` | Writes hook overrides into `~/.claude/settings.local.json` to log every session/tool/command |
| `usage-tracker.py` | The hook handler that records events to SQLite + JSONL |
| `analyze-usage.py` | Summaries, time-windowed reports, exports |
| `usage-dashboard.py` | Live terminal dashboard over the SQLite store |
| `sync-codex.sh` | Mirrors `commands/` + `.claude/skills/` into `~/.codex/` (prompts + skills), applying `codex-overrides/` on top |
| `check-plugin-versions.sh` | Pre-commit guardrail: plugin source changes must bump `plugin.json` and `marketplace.json` versions in lockstep |
| `install-symlinks.sh` | Older partial symlinker (kept for compatibility; `install.sh` is the canonical entrypoint) |

See `scripts/README.md` for the usage-tracking specifics.

### Codex sync (optional)

If you also use the Codex CLI and want the same skills/commands available there:

```bash
scripts/sync-codex.sh --check   # report drift (exit 0 clean, 2 drift, 1 error)
scripts/sync-codex.sh           # apply
```

Codex skill resolution order during sync:
1. User skills from `.claude/skills/`
2. Plugin skills (with selective drops per `scripts/sync-codex.skill-policy.tsv`)
3. Codex-only overrides from `codex-overrides/skills/` (win on name collision)

## Analytics

`analytics/` is a [submodule](https://github.com/0xbigboss/claude-code-analytics) that analyzes Claude Code transcripts (skill usage, token consumption, tool patterns).

```bash
git submodule update --init analytics
cd analytics && uv sync
uv run cc-analytics skills
```

## Instruction Source of Truth

- Shared agent guidelines live in `CLAUDE.md` at the repo root. The installer links this into `~/.claude/CLAUDE.md`.
- Personal local notes belong in `~/.claude/CLAUDE.local.md` (or this repo's `CLAUDE.local.md`, which is gitignored). Do not move local-only content into the tracked `CLAUDE.md` — it is meant to be shareable.

## Relationship to a Larger Dotfiles Tree

The author keeps this repo as a submodule of a private dotfiles tree. When present, that tree's `codex/codex.json` is preferred by `install.sh` over the in-repo sample, and a private `claude-bootstrap` / `claude-settings-merge` pair manages additional symlinks and the settings merge. Neither is required to use this repo standalone — everything in this README assumes no parent tree.

## Author

Allen Eubank ([@alleneubank](https://github.com/alleneubank))

## License

Licensed under the Apache License, Version 2.0. See [LICENSE](LICENSE).
