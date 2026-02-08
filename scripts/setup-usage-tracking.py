#!/usr/bin/env python3
"""
Setup script for Claude Code usage tracking hooks
Run this to configure all tracking hooks in your settings
"""

import json
import os
import subprocess
from pathlib import Path

def get_local_settings_path():
    """Get user-local settings override path."""
    return Path.home() / ".claude" / "settings.local.json"

def load_settings():
    """Load existing local settings override or create new."""
    settings_path = get_local_settings_path()
    if settings_path.exists():
        with open(settings_path, 'r', encoding='utf-8') as f:
            return json.load(f)
    return {}

def save_settings(settings):
    """Save local settings override."""
    settings_path = get_local_settings_path()
    settings_path.parent.mkdir(parents=True, exist_ok=True)
    
    with open(settings_path, 'w', encoding='utf-8') as f:
        json.dump(settings, f, indent=2)

def merge_hook(settings, event_name, command):
    """Merge one hook command into local settings without clobbering unrelated hooks."""
    if 'hooks' not in settings or not isinstance(settings['hooks'], dict):
        settings['hooks'] = {}

    existing = settings['hooks'].get(event_name, [])
    if not isinstance(existing, list):
        existing = []

    filtered = []
    already_present = False

    for entry in existing:
        if not isinstance(entry, dict):
            filtered.append(entry)
            continue

        hook_list = entry.get('hooks')
        if not isinstance(hook_list, list):
            filtered.append(entry)
            continue

        has_exact = any(
            isinstance(hook, dict)
            and hook.get('type') == 'command'
            and hook.get('command') == command
            for hook in hook_list
        )
        if has_exact:
            already_present = True
            filtered.append(entry)
            continue

        # Replace stale tracker entries for this event, keep everything else.
        has_stale_tracker = any(
            isinstance(hook, dict)
            and hook.get('type') == 'command'
            and 'usage-tracker.py' in str(hook.get('command', ''))
            and f'CLAUDE_HOOK_TYPE={event_name}' in str(hook.get('command', ''))
            for hook in hook_list
        )
        if not has_stale_tracker:
            filtered.append(entry)

    if not already_present:
        filtered.append(
            {
                "matcher": "",
                "hooks": [
                    {
                        "type": "command",
                        "command": command,
                    }
                ],
            }
        )

    settings['hooks'][event_name] = filtered

def run_settings_merge():
    """Regenerate ~/.claude/settings.json from baseline + local overrides."""
    dotfiles_merge = Path(__file__).resolve().parents[2] / "bin" / "bin" / "claude-settings-merge"
    home_merge = Path.home() / "bin" / "claude-settings-merge"

    merge_cmd = None
    for candidate in (home_merge, dotfiles_merge):
        if candidate.exists():
            merge_cmd = candidate
            break

    if merge_cmd is None:
        print("⚠️  claude-settings-merge not found; local overrides saved but ~/.claude/settings.json was not regenerated")
        return

    try:
        subprocess.run([str(merge_cmd), "--fix"], check=True)
        print(f"✅ Regenerated ~/.claude/settings.json via {merge_cmd}")
    except subprocess.CalledProcessError as exc:
        print(f"⚠️  Failed to run {merge_cmd} --fix: {exc}")

def setup_hooks():
    """Configure usage tracking hooks in settings.local.json."""
    settings = load_settings()

    tracker_script = str(Path.home() / ".claude" / "scripts" / "usage-tracker.py")
    
    # PreToolUse hook - Track all tool usage before execution
    merge_hook(settings, "PreToolUse", f"CLAUDE_HOOK_TYPE=PreToolUse python3 {tracker_script}")
    
    # PostToolUse hook - Track tool results
    merge_hook(settings, "PostToolUse", f"CLAUDE_HOOK_TYPE=PostToolUse python3 {tracker_script}")
    
    # Stop hook - Track session end
    merge_hook(settings, "Stop", f"CLAUDE_HOOK_TYPE=Stop python3 {tracker_script}")
    
    # SubagentStop hook - Track subagent completion
    merge_hook(settings, "SubagentStop", f"CLAUDE_HOOK_TYPE=SubagentStop python3 {tracker_script}")
    
    # Notification hook - Track when Claude needs attention
    merge_hook(settings, "Notification", f"CLAUDE_HOOK_TYPE=Notification python3 {tracker_script}")
    
    save_settings(settings)
    print("✅ Usage tracking hooks configured successfully!")
    print(f"Local overrides saved to: {get_local_settings_path()}")
    print("\nHooks configured:")
    print("- PreToolUse: Track all tool invocations")
    print("- PostToolUse: Track tool results")
    print("- Stop: Track session end")
    print("- SubagentStop: Track subagent completion")
    print("- Notification: Track attention requests")
    print("\nRestart Claude Code for changes to take effect.")

def main():
    """Main entry point"""
    try:
        # Ensure scripts directory exists
        scripts_dir = Path.home() / ".claude" / "scripts"
        scripts_dir.mkdir(parents=True, exist_ok=True)
        
        # Make tracker script executable
        tracker_path = scripts_dir / "usage-tracker.py"
        if tracker_path.exists():
            os.chmod(tracker_path, 0o755)
        
        # Setup hooks
        setup_hooks()
        run_settings_merge()
        
    except Exception as e:
        print(f"❌ Error setting up hooks: {e}")
        exit(1)

if __name__ == '__main__':
    main()
