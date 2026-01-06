# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a high-performance Zig application that provides a custom statusline for Claude Code. The statusline displays the current directory, git branch, file changes, model information, context usage percentage, and session duration in a colorful, compact format.

## Development Commands

### Building and Running

```bash
# Build the project (default: debug mode)
zig build

# Build for release (optimized)
zig build -Doptimize=ReleaseFast

# Build for smallest binary size
zig build -Doptimize=ReleaseSmall

# Run the application directly
zig build run

# Run with debug logging
zig build run -- --debug
```

### Testing

```bash
# Run unit tests
zig build test
```

### Direct Compilation (for maximum performance)

```bash
# Compile with maximum performance optimizations
zig build-exe src/main.zig -O ReleaseFast -fsingle-threaded

# Compile for smallest binary size
zig build-exe src/main.zig -O ReleaseSmall -fsingle-threaded
```

## Architecture

The application is structured as a single-file Zig program with clear separation of concerns:

### Core Components

- **StatuslineInput**: JSON structure for receiving data from Claude Code
- **ModelType**: Enum for detecting and abbreviating model names (Opus, Sonnet, Haiku)
- **ContextUsage**: Manages context percentage calculation with color-coded output
- **GitStatus**: Parses and formats git file status (added, modified, deleted, untracked)
- **RalphState**: Ralph Reviewed loop iteration and review tracking
- **CodexReviewState**: Codex Reviewer standalone review gate tracking

### Key Functions

- `main()`: Entry point that orchestrates the statusline generation
- `execCommand()`: Executes shell commands safely with proper error handling
- `calculateContextUsage()`: Calculates context usage from API-provided token counts
- `formatSessionDuration()`: Formats session duration from API-provided total_duration_ms
- `formatCost()`: Displays session cost in $X.XX format
- `formatLinesChanged()`: Displays lines added/removed in +N/-M format
- `isGitRepo()`, `getGitBranch()`, `getGitStatus()`: Git integration functions

### Performance Optimizations

- Uses ArenaAllocator for efficient memory management (single deallocation)
- Fixed buffer output stream to minimize allocations
- Uses pre-calculated API values instead of parsing transcript files
- Single-threaded compilation option for maximum performance
- Color codes defined as compile-time constants

## Key Design Decisions

### Memory Management
The application uses an ArenaAllocator pattern where all allocations are freed at once when the program exits, eliminating individual memory management overhead.

### Error Handling
Functions return empty/default values on error rather than crashing, ensuring the statusline always provides some output even in error conditions.

### JSON Processing
Uses Zig's built-in JSON parser with proper error handling and type safety through the StatuslineInput struct.

### Performance Focus
The code is optimized for minimal latency with single-threaded execution and release-fast compilation mode recommended for production use.

## Review Session Tracking

The statusline displays review iteration progress from two plugin systems:

### State File Locations

Both state files are stored in `{GIT_ROOT}/.claude/` and use YAML frontmatter format:

| Plugin | State File | Display |
|--------|-----------|---------|
| Ralph Reviewed | `ralph-loop.local.md` | 🔄 iterations, 🔍 reviews |
| Codex Reviewer | `codex-review.local.md` | 🔎 reviews |

### State File Format

**Ralph loop state** (`ralph-loop.local.md`):
```yaml
---
active: true
iteration: 3
max_iterations: 50
review_enabled: true
review_count: 1
max_review_cycles: 10
review_history: [...]
---
```

**Codex review state** (`codex-review.local.md`):
```yaml
---
active: true
review_count: 4
max_review_cycles: 10
review_history: [...]
---
```

### Lookup Commands

To check current review status from the command line:

```bash
# View Ralph loop state
cat "$(git rev-parse --show-toplevel)/.claude/ralph-loop.local.md"

# View Codex review state
cat "$(git rev-parse --show-toplevel)/.claude/codex-review.local.md"

# Quick status check (active + counts)
grep -E '^(active|iteration|review_count):' "$(git rev-parse --show-toplevel)/.claude/"*.local.md
```

### Color Coding

Progress colors use discrete thresholds:
- **Green** (0-50%): Safe range
- **Yellow** (50-80%): Warning range
- **Red** (80-100%): Critical range

For a 5-cycle max: 1-2 = green, 3 = yellow, 4-5 = red.

## Development Notes

- Minimum Zig version: 0.15.1
- No external dependencies
- Cross-platform compatible (POSIX environments)
- ANSI color codes for terminal output
- Reads JSON from stdin, outputs formatted statusline to stdout