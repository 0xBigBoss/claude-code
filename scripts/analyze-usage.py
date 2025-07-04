#!/usr/bin/env python3
"""
Claude Code Usage Analysis Tool
Generates reports from tracked usage data
"""

import sqlite3
import argparse
from datetime import datetime, timedelta
from pathlib import Path
from collections import defaultdict
import json

DB_PATH = Path.home() / ".claude" / "usage-tracking.db"

def format_duration(seconds):
    """Format duration in human-readable form"""
    if seconds is None:
        return "Active"
    
    hours = seconds // 3600
    minutes = (seconds % 3600) // 60
    
    if hours > 0:
        return f"{hours}h {minutes}m"
    else:
        return f"{minutes}m"

def get_summary_stats(days=7):
    """Get summary statistics for the past N days"""
    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()
    
    since_date = (datetime.now() - timedelta(days=days)).isoformat()
    
    # Total sessions and time
    cursor.execute('''
        SELECT 
            COUNT(*) as session_count,
            SUM(duration_seconds) as total_seconds,
            AVG(duration_seconds) as avg_seconds
        FROM sessions
        WHERE start_time >= ?
    ''', (since_date,))
    
    sessions_data = cursor.fetchone()
    
    # Tool usage by category
    cursor.execute('''
        SELECT 
            tool_category,
            COUNT(*) as usage_count
        FROM tool_usage
        WHERE timestamp >= ?
        GROUP BY tool_category
        ORDER BY usage_count DESC
    ''', (since_date,))
    
    tool_categories = cursor.fetchall()
    
    # Most used tools
    cursor.execute('''
        SELECT 
            tool_name,
            COUNT(*) as usage_count
        FROM tool_usage
        WHERE timestamp >= ?
        GROUP BY tool_name
        ORDER BY usage_count DESC
        LIMIT 10
    ''', (since_date,))
    
    top_tools = cursor.fetchall()
    
    # Projects worked on
    cursor.execute('''
        SELECT 
            project_path,
            COUNT(DISTINCT session_id) as session_count,
            SUM(duration_seconds) as total_seconds
        FROM sessions
        WHERE start_time >= ? AND project_path IS NOT NULL
        GROUP BY project_path
        ORDER BY total_seconds DESC
    ''', (since_date,))
    
    projects = cursor.fetchall()
    
    conn.close()
    
    print(f"\n📊 Claude Code Usage Summary (Last {days} days)")
    print("=" * 60)
    
    if sessions_data[0]:
        total_sessions = sessions_data[0]
        total_time = sessions_data[1] or 0
        avg_time = sessions_data[2] or 0
        
        print(f"\n📈 Sessions:")
        print(f"  • Total: {total_sessions}")
        print(f"  • Total Time: {format_duration(total_time)}")
        print(f"  • Average Duration: {format_duration(int(avg_time))}")
    
    if tool_categories:
        print(f"\n🔧 Tool Usage by Category:")
        for category, count in tool_categories:
            print(f"  • {category}: {count} uses")
    
    if top_tools:
        print(f"\n⭐ Top 10 Most Used Tools:")
        for tool, count in top_tools:
            print(f"  • {tool}: {count} uses")
    
    if projects:
        print(f"\n📁 Projects:")
        for project, sessions, seconds in projects:
            project_name = Path(project).name
            print(f"  • {project_name}: {sessions} sessions, {format_duration(seconds)}")

def get_detailed_session_log(session_id=None, last_n=5):
    """Get detailed log of sessions"""
    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()
    
    if session_id:
        # Specific session
        cursor.execute('''
            SELECT * FROM sessions WHERE session_id = ?
        ''', (session_id,))
        sessions = cursor.fetchall()
    else:
        # Last N sessions
        cursor.execute('''
            SELECT * FROM sessions 
            ORDER BY start_time DESC 
            LIMIT ?
        ''', (last_n,))
        sessions = cursor.fetchall()
    
    for session in sessions:
        session_id = session[0]
        project = session[1]
        start = session[2]
        end = session[3]
        duration = session[4]
        
        print(f"\n🔍 Session: {session_id[:8]}...")
        print(f"  Project: {project}")
        print(f"  Started: {start}")
        print(f"  Duration: {format_duration(duration)}")
        
        # Get tool usage for this session
        cursor.execute('''
            SELECT tool_name, COUNT(*) as count
            FROM tool_usage
            WHERE session_id = ?
            GROUP BY tool_name
            ORDER BY count DESC
        ''', (session_id,))
        
        tools = cursor.fetchall()
        if tools:
            print("  Tools used:")
            for tool, count in tools[:5]:  # Top 5
                print(f"    • {tool}: {count}x")
    
    conn.close()

def get_command_history(days=1):
    """Get recent command history"""
    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()
    
    since_date = (datetime.now() - timedelta(days=days)).isoformat()
    
    cursor.execute('''
        SELECT timestamp, command, description, project_path
        FROM commands
        WHERE timestamp >= ?
        ORDER BY timestamp DESC
        LIMIT 50
    ''', (since_date,))
    
    commands = cursor.fetchall()
    
    print(f"\n💻 Recent Commands (Last {days} day{'s' if days > 1 else ''}):")
    print("=" * 60)
    
    for timestamp, command, description, project in commands:
        time_str = datetime.fromisoformat(timestamp).strftime("%H:%M")
        project_name = Path(project).name if project else "Unknown"
        desc_str = f" - {description}" if description else ""
        print(f"[{time_str}] [{project_name}] {command}{desc_str}")
    
    conn.close()

def export_usage_data(output_file):
    """Export all usage data to JSON"""
    conn = sqlite3.connect(DB_PATH)
    
    # Get all data
    data = {
        'sessions': [],
        'tool_usage': [],
        'commands': [],
        'events': []
    }
    
    # Export sessions
    cursor = conn.cursor()
    cursor.execute('SELECT * FROM sessions')
    columns = [desc[0] for desc in cursor.description]
    for row in cursor.fetchall():
        data['sessions'].append(dict(zip(columns, row)))
    
    # Export tool usage
    cursor.execute('SELECT * FROM tool_usage')
    columns = [desc[0] for desc in cursor.description]
    for row in cursor.fetchall():
        data['tool_usage'].append(dict(zip(columns, row)))
    
    # Export commands
    cursor.execute('SELECT * FROM commands')
    columns = [desc[0] for desc in cursor.description]
    for row in cursor.fetchall():
        data['commands'].append(dict(zip(columns, row)))
    
    # Export events
    cursor.execute('SELECT * FROM events')
    columns = [desc[0] for desc in cursor.description]
    for row in cursor.fetchall():
        data['events'].append(dict(zip(columns, row)))
    
    conn.close()
    
    # Write to file
    with open(output_file, 'w') as f:
        json.dump(data, f, indent=2)
    
    print(f"✅ Exported usage data to: {output_file}")

def main():
    parser = argparse.ArgumentParser(description='Analyze Claude Code usage')
    parser.add_argument('--summary', action='store_true', help='Show summary statistics')
    parser.add_argument('--days', type=int, default=7, help='Number of days to analyze')
    parser.add_argument('--sessions', action='store_true', help='Show detailed session log')
    parser.add_argument('--session-id', help='Show specific session details')
    parser.add_argument('--commands', action='store_true', help='Show command history')
    parser.add_argument('--export', help='Export data to JSON file')
    
    args = parser.parse_args()
    
    if not DB_PATH.exists():
        print("❌ No usage data found. Start using Claude Code with tracking enabled.")
        return
    
    if args.export:
        export_usage_data(args.export)
    elif args.session_id:
        get_detailed_session_log(args.session_id)
    elif args.sessions:
        get_detailed_session_log(last_n=10)
    elif args.commands:
        get_command_history(args.days)
    else:
        # Default: show summary
        get_summary_stats(args.days)

if __name__ == '__main__':
    main()