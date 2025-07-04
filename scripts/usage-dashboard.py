#!/usr/bin/env python3
"""
Claude Code Usage Dashboard
Real-time usage statistics and monitoring
"""

import sqlite3
from datetime import datetime, timedelta
from pathlib import Path
import os
import time

DB_PATH = Path.home() / ".claude" / "usage-tracking.db"

def clear_screen():
    """Clear terminal screen"""
    os.system('clear' if os.name != 'nt' else 'cls')

def get_active_sessions():
    """Get currently active sessions"""
    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()
    
    cursor.execute('''
        SELECT session_id, project_path, start_time
        FROM sessions
        WHERE end_time IS NULL
        ORDER BY start_time DESC
    ''')
    
    active = cursor.fetchall()
    conn.close()
    return active

def get_today_stats():
    """Get statistics for today"""
    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()
    
    today = datetime.now().strftime('%Y-%m-%d')
    
    # Sessions today
    cursor.execute('''
        SELECT COUNT(*), SUM(duration_seconds)
        FROM sessions
        WHERE date(start_time) = date(?)
    ''', (today,))
    
    sessions_count, total_time = cursor.fetchone()
    
    # Tools used today
    cursor.execute('''
        SELECT COUNT(*)
        FROM tool_usage
        WHERE date(timestamp) = date(?)
    ''', (today,))
    
    tools_count = cursor.fetchone()[0]
    
    # Commands today
    cursor.execute('''
        SELECT COUNT(*)
        FROM commands
        WHERE date(timestamp) = date(?)
    ''', (today,))
    
    commands_count = cursor.fetchone()[0]
    
    conn.close()
    
    return {
        'sessions': sessions_count or 0,
        'time': total_time or 0,
        'tools': tools_count or 0,
        'commands': commands_count or 0
    }

def get_project_stats():
    """Get project statistics for the week"""
    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()
    
    week_ago = (datetime.now() - timedelta(days=7)).isoformat()
    
    cursor.execute('''
        SELECT 
            project_path,
            COUNT(DISTINCT session_id) as sessions,
            COUNT(DISTINCT date(timestamp)) as days_active
        FROM tool_usage
        WHERE timestamp >= ?
        GROUP BY project_path
        ORDER BY sessions DESC
        LIMIT 5
    ''', (week_ago,))
    
    projects = cursor.fetchall()
    conn.close()
    
    return projects

def format_time(seconds):
    """Format seconds to readable time"""
    if seconds is None:
        return "0m"
    hours = seconds // 3600
    minutes = (seconds % 3600) // 60
    if hours > 0:
        return f"{hours}h {minutes}m"
    return f"{minutes}m"

def display_dashboard():
    """Display the dashboard"""
    clear_screen()
    
    print("🎯 Claude Code Usage Dashboard")
    print("=" * 60)
    print(f"Last Updated: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
    
    # Active sessions
    active = get_active_sessions()
    print(f"\n🟢 Active Sessions: {len(active)}")
    for session_id, project, start_time in active[:3]:
        project_name = Path(project).name if project else "Unknown"
        start_dt = datetime.fromisoformat(start_time)
        duration = datetime.now() - start_dt
        duration_min = int(duration.total_seconds() / 60)
        print(f"  • {project_name} - {duration_min}m (started {start_dt.strftime('%H:%M')})")
    
    # Today's stats
    today_stats = get_today_stats()
    print(f"\n📊 Today's Activity:")
    print(f"  • Sessions: {today_stats['sessions']}")
    print(f"  • Total Time: {format_time(today_stats['time'])}")
    print(f"  • Tools Used: {today_stats['tools']}")
    print(f"  • Commands Run: {today_stats['commands']}")
    
    # Project activity
    projects = get_project_stats()
    if projects:
        print(f"\n📁 Active Projects (Last 7 Days):")
        for project, sessions, days in projects:
            project_name = Path(project).name if project else "Unknown"
            print(f"  • {project_name}: {sessions} sessions across {days} days")
    
    print(f"\n💡 Tips:")
    print(f"  • Run 'python3 ~/.claude/scripts/analyze-usage.py --summary' for detailed stats")
    print(f"  • Run 'python3 ~/.claude/scripts/analyze-usage.py --commands' for command history")
    print(f"  • Press Ctrl+C to exit dashboard")

def main():
    """Main dashboard loop"""
    try:
        while True:
            display_dashboard()
            time.sleep(30)  # Refresh every 30 seconds
    except KeyboardInterrupt:
        print("\n\n👋 Exiting dashboard...")

if __name__ == '__main__':
    if not DB_PATH.exists():
        print("❌ No usage data found. Set up tracking first with setup-usage-tracking.py")
    else:
        main()