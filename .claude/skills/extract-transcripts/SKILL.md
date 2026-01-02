---
name: extract-transcripts
description: Extract readable transcripts from Claude Code and Codex CLI session JSONL files
---

# Extract Transcripts

Extracts readable markdown transcripts from Claude Code and Codex CLI session JSONL files.

## Scripts

### Claude Code Sessions

```bash
# Extract a single session
python3 ~/.claude/skills/extract-transcripts/extract_transcript.py <session.jsonl>

# With tool calls and thinking blocks
python3 ~/.claude/skills/extract-transcripts/extract_transcript.py <session.jsonl> --include-tools --include-thinking

# Extract all sessions from a directory
python3 ~/.claude/skills/extract-transcripts/extract_transcript.py <directory> --all

# Output to file
python3 ~/.claude/skills/extract-transcripts/extract_transcript.py <session.jsonl> -o output.md

# Summary only (quick overview)
python3 ~/.claude/skills/extract-transcripts/extract_transcript.py <session.jsonl> --summary

# Skip empty/warmup-only sessions
python3 ~/.claude/skills/extract-transcripts/extract_transcript.py <directory> --all --skip-empty
```

**Options:**
- `--include-tools`: Include tool calls and results
- `--include-thinking`: Include Claude's thinking blocks
- `--all`: Process all .jsonl files in directory
- `-o, --output`: Output file path (default: stdout)
- `--summary`: Only output brief summary
- `--skip-empty`: Skip empty and warmup-only sessions
- `--min-messages N`: Minimum messages for --skip-empty (default: 2)

### Codex CLI Sessions

```bash
# Extract a Codex session
python3 ~/.claude/skills/extract-transcripts/extract_codex_transcript.py <session.jsonl>

# Extract from Codex history file
python3 ~/.claude/skills/extract-transcripts/extract_codex_transcript.py ~/.codex/history.jsonl --history
```

## Session File Locations

### Claude Code
- macOS: `~/Library/Application Support/Claude/sessions/`
- Linux: `~/.config/claude/sessions/`

### Codex CLI
- Sessions: `~/.codex/sessions/<session_id>/rollout.jsonl`
- History: `~/.codex/history.jsonl`

## Output Format

Transcripts are formatted as markdown with:
- Session metadata (date, duration, model, working directory, git branch)
- User messages prefixed with `## User`
- Assistant responses prefixed with `## Assistant`
- Tool calls in code blocks (if --include-tools)
- Thinking in blockquotes (if --include-thinking)
- Tool usage summary for Codex sessions
