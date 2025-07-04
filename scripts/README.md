# Claude Code Usage Tracking System

Track and analyze your Claude Code usage across all projects.

## Quick Setup

1. **Install the tracking hooks:**
   ```bash
   python3 ~/.claude/scripts/setup-usage-tracking.py
   ```

2. **Restart Claude Code** for hooks to take effect

3. **View your usage:**
   ```bash
   # Summary statistics
   python3 ~/.claude/scripts/analyze-usage.py --summary
   
   # Last 30 days
   python3 ~/.claude/scripts/analyze-usage.py --summary --days 30
   
   # Command history
   python3 ~/.claude/scripts/analyze-usage.py --commands
   
   # Session details
   python3 ~/.claude/scripts/analyze-usage.py --sessions
   
   # Live dashboard
   python3 ~/.claude/scripts/usage-dashboard.py
   ```

## What Gets Tracked

- **Session Data**: Start/end times, duration, project paths
- **Tool Usage**: Every tool invocation with timestamps
- **Commands**: All Bash commands with descriptions
- **Projects**: Time spent per project
- **Events**: Notifications, stops, subagent activity

## Data Storage

- **SQLite Database**: `~/.claude/usage-tracking.db`
- **JSON Logs**: `~/.claude/usage-logs/YYYY-MM-DD.jsonl`

## Export Data

```bash
python3 ~/.claude/scripts/analyze-usage.py --export my-usage-data.json
```

## Privacy

All data is stored locally on your machine. Nothing is sent externally.

## Customization

Edit `~/.claude/scripts/usage-tracker.py` to:
- Add custom tracking logic
- Filter sensitive data
- Change storage locations
- Add new metrics

## Troubleshooting

1. **Hooks not working?**
   - Check `~/.claude/settings.json` exists
   - Restart Claude Code
   - Run with `--debug` flag

2. **No data showing?**
   - Ensure hooks are installed
   - Check if database exists: `ls ~/.claude/usage-tracking.db`
   - Verify script permissions

3. **Reset tracking:**
   ```bash
   rm ~/.claude/usage-tracking.db
   rm -rf ~/.claude/usage-logs/
   ```