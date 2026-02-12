# Claude Code Development Repository (Local Notes)

Local operational notes for maintaining this Claude Code config repo.

## Editing Model

- Edit source files in this repo only.
- Do not edit runtime paths in `~/.claude/*`; re-apply links with `bin/bin/claude-bootstrap --fix`.
- After command/skill changes, sync Codex with `claude-code/scripts/sync-codex.sh`.

## Plugin Troubleshooting

If a plugin appears installed but hooks do not run, check orphan markers:

```bash
find ~/.claude/plugins/cache -name ".orphaned_at"
rm ~/.claude/plugins/cache/0xbigboss-plugins/<plugin>/*/.orphaned_at
claude plugin update <plugin-name>
```

## Publishing Plugin Updates

Keep plugin versions in sync in both locations:

1. `claude-code/plugins/<plugin-name>/.claude-plugin/plugin.json`
2. `claude-code/.claude-plugin/marketplace.json`

Then refresh marketplace metadata:

```bash
claude plugin marketplace update 0xbigboss-plugins
```
