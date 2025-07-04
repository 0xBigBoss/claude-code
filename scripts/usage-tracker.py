#!/usr/bin/env python3
"""
Claude Code Usage Tracker
Logs usage data to SQLite database for analysis
"""

import json
import sqlite3
import sys
import os
from datetime import datetime
from pathlib import Path

# Configuration
DB_PATH = Path.home() / ".claude" / "usage-tracking.db"
LOG_PATH = Path.home() / ".claude" / "usage-logs"

def init_database():
    """Initialize SQLite database with required tables"""
    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()
    
    # Sessions table
    cursor.execute('''
        CREATE TABLE IF NOT EXISTS sessions (
            session_id TEXT PRIMARY KEY,
            project_path TEXT,
            start_time TIMESTAMP,
            end_time TIMESTAMP,
            duration_seconds INTEGER,
            transcript_path TEXT
        )
    ''')
    
    # Tool usage table
    cursor.execute('''
        CREATE TABLE IF NOT EXISTS tool_usage (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            session_id TEXT,
            timestamp TIMESTAMP,
            tool_name TEXT,
            tool_category TEXT,
            input_size INTEGER,
            output_size INTEGER,
            project_path TEXT,
            FOREIGN KEY (session_id) REFERENCES sessions(session_id)
        )
    ''')
    
    # Commands table
    cursor.execute('''
        CREATE TABLE IF NOT EXISTS commands (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            session_id TEXT,
            timestamp TIMESTAMP,
            command TEXT,
            description TEXT,
            project_path TEXT,
            FOREIGN KEY (session_id) REFERENCES sessions(session_id)
        )
    ''')
    
    # Events table for general tracking
    cursor.execute('''
        CREATE TABLE IF NOT EXISTS events (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            session_id TEXT,
            timestamp TIMESTAMP,
            event_type TEXT,
            event_data TEXT,
            project_path TEXT,
            FOREIGN KEY (session_id) REFERENCES sessions(session_id)
        )
    ''')
    
    conn.commit()
    conn.close()

def get_project_path():
    """Get current project path"""
    return os.getcwd()

def categorize_tool(tool_name):
    """Categorize tools for better analysis"""
    categories = {
        'Read': 'file_ops',
        'Write': 'file_ops',
        'Edit': 'file_ops',
        'MultiEdit': 'file_ops',
        'NotebookRead': 'file_ops',
        'NotebookEdit': 'file_ops',
        'Bash': 'shell',
        'Task': 'agent',
        'Glob': 'search',
        'Grep': 'search',
        'LS': 'search',
        'WebFetch': 'web',
        'WebSearch': 'web',
        'TodoRead': 'planning',
        'TodoWrite': 'planning',
        'exit_plan_mode': 'planning'
    }
    
    # Handle MCP tools
    if tool_name.startswith('mcp__'):
        return 'mcp'
    
    return categories.get(tool_name, 'other')

def log_tool_usage(data):
    """Log tool usage to database"""
    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()
    
    tool_input = json.dumps(data.get('tool_input', {}))
    tool_response = json.dumps(data.get('tool_response', {})) if 'tool_response' in data else '{}'
    
    cursor.execute('''
        INSERT INTO tool_usage 
        (session_id, timestamp, tool_name, tool_category, input_size, output_size, project_path)
        VALUES (?, ?, ?, ?, ?, ?, ?)
    ''', (
        data['session_id'],
        datetime.now().isoformat(),
        data['tool_name'],
        categorize_tool(data['tool_name']),
        len(tool_input),
        len(tool_response),
        get_project_path()
    ))
    
    # Special handling for Bash commands
    if data['tool_name'] == 'Bash' and 'tool_input' in data:
        command = data['tool_input'].get('command', '')
        description = data['tool_input'].get('description', '')
        
        cursor.execute('''
            INSERT INTO commands
            (session_id, timestamp, command, description, project_path)
            VALUES (?, ?, ?, ?, ?)
        ''', (
            data['session_id'],
            datetime.now().isoformat(),
            command,
            description,
            get_project_path()
        ))
    
    conn.commit()
    conn.close()

def log_session_event(data, event_type):
    """Log session start/stop events"""
    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()
    
    if event_type == 'start':
        # Check if session already exists
        cursor.execute('SELECT session_id FROM sessions WHERE session_id = ?', (data['session_id'],))
        if not cursor.fetchone():
            cursor.execute('''
                INSERT INTO sessions 
                (session_id, project_path, start_time, transcript_path)
                VALUES (?, ?, ?, ?)
            ''', (
                data['session_id'],
                get_project_path(),
                datetime.now().isoformat(),
                data.get('transcript_path', '')
            ))
    
    elif event_type in ['stop', 'subagent_stop']:
        # Update session end time
        cursor.execute('''
            UPDATE sessions 
            SET end_time = ?, 
                duration_seconds = CAST((julianday(?) - julianday(start_time)) * 86400 AS INTEGER)
            WHERE session_id = ?
        ''', (
            datetime.now().isoformat(),
            datetime.now().isoformat(),
            data['session_id']
        ))
    
    # Log as event
    cursor.execute('''
        INSERT INTO events
        (session_id, timestamp, event_type, event_data, project_path)
        VALUES (?, ?, ?, ?, ?)
    ''', (
        data['session_id'],
        datetime.now().isoformat(),
        event_type,
        json.dumps(data),
        get_project_path()
    ))
    
    conn.commit()
    conn.close()

def main():
    """Main entry point for hook"""
    try:
        # Initialize database if needed
        init_database()
        
        # Read input data
        input_data = json.load(sys.stdin)
        
        # Determine hook type from environment or infer from data
        hook_type = os.environ.get('CLAUDE_HOOK_TYPE', '')
        
        if 'tool_name' in input_data and 'tool_input' in input_data:
            if 'tool_response' in input_data:
                hook_type = 'PostToolUse'
            else:
                hook_type = 'PreToolUse'
        
        # Handle different hook types
        if hook_type in ['PreToolUse', 'PostToolUse']:
            log_tool_usage(input_data)
            log_session_event(input_data, 'start')  # Ensure session exists
        
        elif hook_type == 'Stop':
            log_session_event(input_data, 'stop')
        
        elif hook_type == 'SubagentStop':
            log_session_event(input_data, 'subagent_stop')
        
        elif hook_type == 'Notification':
            # Log notification as event
            conn = sqlite3.connect(DB_PATH)
            cursor = conn.cursor()
            cursor.execute('''
                INSERT INTO events
                (session_id, timestamp, event_type, event_data, project_path)
                VALUES (?, ?, ?, ?, ?)
            ''', (
                input_data['session_id'],
                datetime.now().isoformat(),
                'notification',
                json.dumps(input_data),
                get_project_path()
            ))
            conn.commit()
            conn.close()
        
        # Also write to JSON log for backup
        LOG_PATH.mkdir(parents=True, exist_ok=True)
        log_file = LOG_PATH / f"{datetime.now().strftime('%Y-%m-%d')}.jsonl"
        
        with open(log_file, 'a') as f:
            json.dump({
                'timestamp': datetime.now().isoformat(),
                'hook_type': hook_type,
                'project': get_project_path(),
                'data': input_data
            }, f)
            f.write('\n')
        
    except Exception as e:
        # Don't block Claude Code operation
        print(f"Usage tracking error: {e}", file=sys.stderr)
        sys.exit(0)  # Exit successfully to not block
    
    sys.exit(0)

if __name__ == '__main__':
    main()