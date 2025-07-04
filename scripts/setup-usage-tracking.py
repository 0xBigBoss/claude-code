#!/usr/bin/env python3
"""
Setup script for Claude Code usage tracking hooks
Run this to configure all tracking hooks in your settings
"""

import json
import os
from pathlib import Path

def get_settings_path():
    """Get user settings path"""
    return Path.home() / ".claude" / "settings.json"

def load_settings():
    """Load existing settings or create new"""
    settings_path = get_settings_path()
    if settings_path.exists():
        with open(settings_path, 'r') as f:
            return json.load(f)
    return {}

def save_settings(settings):
    """Save settings to file"""
    settings_path = get_settings_path()
    settings_path.parent.mkdir(parents=True, exist_ok=True)
    
    with open(settings_path, 'w') as f:
        json.dump(settings, f, indent=2)

def setup_hooks():
    """Configure all usage tracking hooks"""
    settings = load_settings()
    
    # Initialize hooks section if not exists
    if 'hooks' not in settings:
        settings['hooks'] = {}
    
    tracker_script = str(Path.home() / ".claude" / "scripts" / "usage-tracker.py")
    
    # PreToolUse hook - Track all tool usage before execution
    settings['hooks']['PreToolUse'] = [
        {
            "matcher": "",  # Empty matcher = all tools
            "hooks": [
                {
                    "type": "command",
                    "command": f"CLAUDE_HOOK_TYPE=PreToolUse python3 {tracker_script}"
                }
            ]
        }
    ]
    
    # PostToolUse hook - Track tool results
    settings['hooks']['PostToolUse'] = [
        {
            "matcher": "",  # Empty matcher = all tools
            "hooks": [
                {
                    "type": "command",
                    "command": f"CLAUDE_HOOK_TYPE=PostToolUse python3 {tracker_script}"
                }
            ]
        }
    ]
    
    # Stop hook - Track session end
    settings['hooks']['Stop'] = [
        {
            "matcher": "",
            "hooks": [
                {
                    "type": "command",
                    "command": f"CLAUDE_HOOK_TYPE=Stop python3 {tracker_script}"
                }
            ]
        }
    ]
    
    # SubagentStop hook - Track subagent completion
    settings['hooks']['SubagentStop'] = [
        {
            "matcher": "",
            "hooks": [
                {
                    "type": "command",
                    "command": f"CLAUDE_HOOK_TYPE=SubagentStop python3 {tracker_script}"
                }
            ]
        }
    ]
    
    # Notification hook - Track when Claude needs attention
    settings['hooks']['Notification'] = [
        {
            "matcher": "",
            "hooks": [
                {
                    "type": "command",
                    "command": f"CLAUDE_HOOK_TYPE=Notification python3 {tracker_script}"
                }
            ]
        }
    ]
    
    save_settings(settings)
    print("✅ Usage tracking hooks configured successfully!")
    print(f"Settings saved to: {get_settings_path()}")
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
        
    except Exception as e:
        print(f"❌ Error setting up hooks: {e}")
        exit(1)

if __name__ == '__main__':
    main()