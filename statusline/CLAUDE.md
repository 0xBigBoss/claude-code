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

# Run with specific arguments
zig build run -- --short
zig build run -- --skip-pr-status
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

### Key Functions

- `main()`: Entry point that orchestrates the statusline generation
- `execCommand()`: Executes shell commands safely with proper error handling
- `calculateContextUsage()`: Processes transcript files to determine context usage percentage
- `formatSessionDuration()`: Calculates session length from transcript timestamps
- `isGitRepo()`, `getGitBranch()`, `getGitStatus()`: Git integration functions

### Performance Optimizations

- Uses ArenaAllocator for efficient memory management (single deallocation)
- Fixed buffer output stream to minimize allocations
- Processes only last 50 lines of transcript for context calculation
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

## Development Notes

- Minimum Zig version: 0.14.1
- No external dependencies
- Cross-platform compatible (POSIX environments)
- ANSI color codes for terminal output
- Reads JSON from stdin, outputs formatted statusline to stdout