// Credit: https://gist.github.com/steipete/8396e512171d31e934f0013e5651691e
// Compile with: zig build-exe statusline.zig -O ReleaseFast -fsingle-threaded
// For maximum performance, use ReleaseFast and single-threaded mode
// Alternative: -O ReleaseSmall for smaller binary size

const std = @import("std");
const json = std.json;
const Allocator = std.mem.Allocator;

/// ANSI color codes as a namespace
const colors = struct {
    const cyan = "\x1b[36m";
    const green = "\x1b[32m";
    const gray = "\x1b[90m";
    const red = "\x1b[31m";
    const orange = "\x1b[38;5;208m";
    const yellow = "\x1b[33m";
    const light_gray = "\x1b[38;5;245m";
    const reset = "\x1b[0m";
    // Background colors for gauge
    const bg_dark_gray = "\x1b[48;2;60;60;60m"; // Dark gray background for gauge empty space
    const bg_reset = "\x1b[49m"; // Reset background only
};

/// Current context usage token counts - added in v2.0.70
/// Provides accurate per-message token counts for context window calculation
const CurrentUsage = struct {
    input_tokens: ?i64 = null,
    output_tokens: ?i64 = null,
    cache_creation_input_tokens: ?i64 = null,
    cache_read_input_tokens: ?i64 = null,

    /// Calculate total tokens from all fields
    fn totalTokens(self: CurrentUsage) i64 {
        return (self.input_tokens orelse 0) +
            (self.output_tokens orelse 0) +
            (self.cache_creation_input_tokens orelse 0) +
            (self.cache_read_input_tokens orelse 0);
    }
};

/// Input structure from Claude Code (matches latest API)
const StatuslineInput = struct {
    workspace: ?struct {
        current_dir: ?[]const u8 = null,
        project_dir: ?[]const u8 = null,
    } = null,
    model: ?struct {
        id: ?[]const u8 = null,
        display_name: ?[]const u8 = null,
    } = null,
    session_id: ?[]const u8 = null,
    transcript_path: ?[]const u8 = null,
    version: ?[]const u8 = null,
    context_window: ?struct {
        total_input_tokens: ?i64 = null,
        total_output_tokens: ?i64 = null,
        context_window_size: ?i64 = null,
        /// Current context usage - added in v2.0.70
        /// Nested inside context_window, provides per-message token counts
        current_usage: ?CurrentUsage = null,
    } = null,
    cost: ?struct {
        total_cost_usd: ?f64 = null,
        total_duration_ms: ?i64 = null,
        total_api_duration_ms: ?i64 = null,
        total_lines_added: ?i64 = null,
        total_lines_removed: ?i64 = null,
    } = null,
};

/// Model type detection
const ModelType = enum {
    opus,
    sonnet,
    haiku,
    fable,
    unknown,

    fn fromName(name: []const u8) ModelType {
        if (std.mem.indexOf(u8, name, "Opus") != null) return .opus;
        if (std.mem.indexOf(u8, name, "Sonnet") != null) return .sonnet;
        if (std.mem.indexOf(u8, name, "Haiku") != null) return .haiku;
        if (std.mem.indexOf(u8, name, "Fable") != null) return .fable;
        return .unknown;
    }

    /// Emoji representation based on literal meaning
    /// Opus = grand musical work (theater), Sonnet = poem (scroll), Haiku = nature poem (leaf),
    /// Fable = animal moral tale (fox, Aesop's storyteller)
    fn emoji(self: ModelType) []const u8 {
        return switch (self) {
            .opus => "🎭",
            .sonnet => "📜",
            .haiku => "🍃",
            .fable => "🦊",
            .unknown => "?",
        };
    }
};

/// Configuration for gauge display
const GaugeConfig = struct {
    width: u8 = 5, // 5 characters for better granularity
    empty_char: []const u8 = "░",
};

/// Default gauge configuration
const default_gauge_config = GaugeConfig{};

/// Eighth block characters for sub-character precision (8 levels per char)
/// Index 0 = empty, 1-7 = partial, 8 = full
const eighth_blocks = [_][]const u8{
    "░", // 0/8 - empty (use config empty_char in practice)
    "▏", // 1/8
    "▎", // 2/8
    "▍", // 3/8
    "▌", // 4/8
    "▋", // 5/8
    "▊", // 6/8
    "▉", // 7/8
    "█", // 8/8 - full
};

/// Context percentage with color coding and gauge display
const ContextUsage = struct {
    percentage: f64,
    total_tokens: u64 = 0, // For debug display

    /// Calculate RGB color using smooth gradient: green → yellow → red
    /// Returns (r, g, b) tuple for 24-bit true color
    fn gradientColor(self: ContextUsage) struct { r: u8, g: u8, b: u8 } {
        const pct = @min(100.0, @max(0.0, self.percentage));

        if (pct <= 50.0) {
            // Green to Yellow: increase red from 0 to 255
            const t = pct / 50.0;
            return .{
                .r = @intFromFloat(t * 255.0),
                .g = 255,
                .b = 0,
            };
        } else {
            // Yellow to Red: decrease green from 255 to 0
            const t = (pct - 50.0) / 50.0;
            return .{
                .r = 255,
                .g = @intFromFloat((1.0 - t) * 255.0),
                .b = 0,
            };
        }
    }

    /// Format as a high-fidelity color-coded gauge using eighth blocks
    /// 5 chars × 8 levels = 40 discrete steps (2.5% precision)
    /// Uses background color to eliminate gaps between partial and empty blocks
    fn formatGauge(self: ContextUsage, writer: anytype, config: GaugeConfig) !void {
        _ = config; // empty_char not used with background color approach
        const width: u32 = 5; // Fixed width for gauge
        // Total steps = width * 8 (8 levels per character)
        const total_steps: f64 = @as(f64, @floatFromInt(width)) * 8.0;
        const filled_steps = (self.percentage / 100.0) * total_steps;
        const steps: u32 = @intFromFloat(@floor(filled_steps));

        // Get gradient color
        const rgb = self.gradientColor();

        // Set background color for empty space, foreground for filled
        try writer.print("{s}\x1b[38;2;{d};{d};{d}m", .{ colors.bg_dark_gray, rgb.r, rgb.g, rgb.b });

        // Render each character
        for (0..width) |i| {
            const char_start: u32 = @intCast(i * 8);
            const char_end: u32 = char_start + 8;

            if (steps >= char_end) {
                // Fully filled character
                try writer.print("{s}", .{eighth_blocks[8]});
            } else if (steps <= char_start) {
                // Empty character - use space so background shows through
                try writer.print(" ", .{});
            } else {
                // Partially filled - background shows through the empty part
                const partial = steps - char_start;
                try writer.print("{s}", .{eighth_blocks[partial]});
            }
        }

        try writer.print("{s}", .{colors.reset});
    }

    /// Legacy color function for non-gradient uses
    fn color(self: ContextUsage) []const u8 {
        if (self.percentage >= 90.0) return colors.red;
        if (self.percentage >= 70.0) return colors.orange;
        if (self.percentage >= 50.0) return colors.yellow;
        return colors.green;
    }

    /// Format as percentage number (legacy, kept for flexibility)
    fn format(self: ContextUsage, writer: anytype) !void {
        if (self.percentage >= 90.0) {
            try writer.print("{d:.1}", .{self.percentage});
        } else {
            try writer.print("{d}", .{@as(u32, @intFromFloat(@round(self.percentage)))});
        }
    }
};

/// Git file status representation
const GitStatus = struct {
    added: u32 = 0,
    modified: u32 = 0,
    deleted: u32 = 0,
    untracked: u32 = 0,

    fn isEmpty(self: GitStatus) bool {
        return self.added == 0 and self.modified == 0 and
            self.deleted == 0 and self.untracked == 0;
    }

    /// Format git status indicators (no leading space, space-separated)
    fn format(self: GitStatus, writer: anytype) !void {
        var first = true;
        if (self.added > 0) {
            try writer.print("+{d}", .{self.added});
            first = false;
        }
        if (self.modified > 0) {
            if (!first) try writer.print(" ", .{});
            try writer.print("~{d}", .{self.modified});
            first = false;
        }
        if (self.deleted > 0) {
            if (!first) try writer.print(" ", .{});
            try writer.print("-{d}", .{self.deleted});
            first = false;
        }
        if (self.untracked > 0) {
            if (!first) try writer.print(" ", .{});
            try writer.print("?{d}", .{self.untracked});
        }
    }

    fn parse(output: []const u8) GitStatus {
        var status = GitStatus{};
        var lines = std.mem.splitScalar(u8, output, '\n');

        while (lines.next()) |line| {
            if (line.len < 2) continue;
            const code = line[0..2];

            if (code[0] == 'A' or std.mem.eql(u8, code, "M ")) {
                status.added += 1;
            } else if (code[1] == 'M' or std.mem.eql(u8, code, " M")) {
                status.modified += 1;
            } else if (code[0] == 'D' or std.mem.eql(u8, code, " D")) {
                status.deleted += 1;
            } else if (std.mem.eql(u8, code, "??")) {
                status.untracked += 1;
            }
        }

        return status;
    }
};

/// Read all content from a reader (replacement for readAllAlloc in Zig 0.15.1)
fn readAllAlloc(allocator: Allocator, reader: *std.Io.Reader) ![]u8 {
    var aw: std.Io.Writer.Allocating = .init(allocator);
    defer aw.deinit();
    _ = try reader.streamRemaining(&aw.writer);
    return aw.toOwnedSlice();
}

/// Execute a shell command and return trimmed output
fn execCommand(allocator: Allocator, command: [:0]const u8, cwd: ?[]const u8) ![]const u8 {
    const argv = [_][:0]const u8{ "sh", "-c", command };

    var child = std.process.Child.init(&argv, allocator);
    child.stdout_behavior = .Pipe;
    child.stderr_behavior = .Pipe;
    if (cwd) |dir| child.cwd = dir;

    try child.spawn();

    const stdout = child.stdout.?;
    var stdout_buffer: [4096]u8 = undefined;
    var stdout_reader = stdout.readerStreaming(&stdout_buffer);
    const reader = &stdout_reader.interface;
    const raw_output = try readAllAlloc(allocator, reader);
    defer allocator.free(raw_output);

    _ = try child.wait();

    const trimmed = std.mem.trim(u8, raw_output, " \t\n\r");
    return allocator.dupe(u8, trimmed);
}

/// Calculate context usage percentage from API-provided values
/// NOTE: This function is inaccurate - API values are cumulative session totals that
/// don't reflect current context window position. Use calculateContextUsage() instead,
/// which reads actual per-message token counts from the transcript file.
/// Kept for reference/testing only.
fn calculateContextUsageFromApi(input: StatuslineInput) ContextUsage {
    const ctx = input.context_window orelse return ContextUsage{ .percentage = 0.0 };
    const window_size = ctx.context_window_size orelse return ContextUsage{ .percentage = 0.0 };
    if (window_size == 0) return ContextUsage{ .percentage = 0.0 };

    const input_tokens = ctx.total_input_tokens orelse 0;
    const output_tokens = ctx.total_output_tokens orelse 0;
    const total_tokens = input_tokens + output_tokens;

    // Effective context is 77.5% of window (22.5% reserved for autocompact buffer)
    const effective_size: i64 = @intFromFloat(@as(f64, @floatFromInt(window_size)) * 0.775);
    if (effective_size == 0) return ContextUsage{ .percentage = 0.0 };

    // Use modulus to get current position within context window (tokens are cumulative)
    const current_tokens = @mod(total_tokens, effective_size);
    const current: f64 = @floatFromInt(current_tokens);
    const size: f64 = @floatFromInt(effective_size);

    return ContextUsage{ .percentage = (current * 100.0) / size };
}

/// Calculate context usage percentage from transcript file
/// Parses the last assistant message to get current token counts
/// Accounts for 22.5% autocompact buffer in effective context size
fn calculateContextUsage(allocator: Allocator, transcript_path: ?[]const u8, context_window_size: ?i64) !ContextUsage {
    if (transcript_path == null) return ContextUsage{ .percentage = 0.0 };

    var file = std.fs.cwd().openFile(transcript_path.?, .{}) catch {
        return ContextUsage{ .percentage = 0.0 };
    };
    defer file.close();

    // Get file size and seek to read only the last 512KB (enough for ~50 lines of JSON)
    const stat = file.stat() catch return ContextUsage{ .percentage = 0.0 };
    const file_size = stat.size;
    const read_size: u64 = 512 * 1024; // 512KB should be plenty for last 50 lines

    if (file_size > read_size) {
        file.seekTo(file_size - read_size) catch return ContextUsage{ .percentage = 0.0 };
    }

    const content = file.readToEndAlloc(allocator, read_size + 1024) catch {
        return ContextUsage{ .percentage = 0.0 };
    };
    defer allocator.free(content);

    // Find last assistant message with usage data (scan from end)
    var line_iter = std.mem.splitBackwardsScalar(u8, content, '\n');
    var lines_checked: u32 = 0;

    while (line_iter.next()) |line| {
        if (line.len == 0) continue;
        lines_checked += 1;
        if (lines_checked > 100) break; // Only check last 100 lines

        const parsed = json.parseFromSlice(json.Value, allocator, line, .{}) catch continue;
        defer parsed.deinit();

        if (parsed.value != .object) continue;

        const msg = parsed.value.object.get("message") orelse continue;
        if (msg != .object) continue;

        const role = msg.object.get("role") orelse continue;
        if (role != .string or !std.mem.eql(u8, role.string, "assistant")) continue;

        const usage = msg.object.get("usage") orelse continue;
        if (usage != .object) continue;

        const tokens = struct {
            input: f64,
            output: f64,
            cache_read: f64,
            cache_creation: f64,
        }{
            .input = extractTokenCount(usage.object, "input_tokens"),
            .output = extractTokenCount(usage.object, "output_tokens"),
            .cache_read = extractTokenCount(usage.object, "cache_read_input_tokens"),
            .cache_creation = extractTokenCount(usage.object, "cache_creation_input_tokens"),
        };

        const total = tokens.input + tokens.output + tokens.cache_read + tokens.cache_creation;
        // Use API-provided context window size if available, otherwise default to 200k
        const window_size: f64 = if (context_window_size) |size| @floatFromInt(size) else 200000.0;
        // Effective context is 77.5% of window (22.5% reserved for autocompact buffer)
        const effective_size = window_size * 0.775;
        const pct = @min(100.0, (total * 100.0) / effective_size);
        return ContextUsage{ .percentage = pct, .total_tokens = @intFromFloat(total) };
    }

    return ContextUsage{ .percentage = 0.0, .total_tokens = 0 };
}

/// Extract token count from JSON object
fn extractTokenCount(obj: std.json.ObjectMap, field: []const u8) f64 {
    const value = obj.get(field) orelse return 0;
    return switch (value) {
        .integer => |i| @as(f64, @floatFromInt(i)),
        .float => |f| f,
        else => 0,
    };
}

/// Format session duration from API-provided cost.total_duration_ms
/// Rounds to nearest hour when >= 1 hour, otherwise shows minutes
fn formatSessionDuration(input: StatuslineInput, writer: anytype) !bool {
    const cost = input.cost orelse return false;
    const duration_ms = cost.total_duration_ms orelse return false;

    const total_minutes = @divTrunc(duration_ms, 1000 * 60);
    const hours = @divTrunc(total_minutes, 60);
    const minutes = @mod(total_minutes, 60);

    if (hours > 0) {
        // Round to nearest hour
        const rounded_hours = if (minutes >= 30) hours + 1 else hours;
        try writer.print("{d}h", .{rounded_hours});
    } else if (total_minutes > 0) {
        try writer.print("{d}m", .{total_minutes});
    } else {
        try writer.print("<1m", .{});
    }
    return true;
}

/// Format session cost from API-provided cost.total_cost_usd
/// Rounds based on amount: <$1 shows 2 decimals, $1-10 shows 1 decimal, >=$10 rounds to whole
fn formatCost(input: StatuslineInput, writer: anytype) !bool {
    const cost = input.cost orelse return false;
    const usd = cost.total_cost_usd orelse return false;
    if (usd < 0.001) return false; // Skip if negligible

    if (usd < 1.0) {
        try writer.print("${d:.2}", .{usd});
    } else if (usd < 10.0) {
        try writer.print("${d:.1}", .{usd});
    } else {
        try writer.print("${d}", .{@as(u32, @intFromFloat(@round(usd)))});
    }
    return true;
}

/// Format lines changed from API-provided cost.total_lines_added/removed
fn formatLinesChanged(input: StatuslineInput, writer: anytype) !bool {
    const cost = input.cost orelse return false;
    const added = cost.total_lines_added orelse 0;
    const removed = cost.total_lines_removed orelse 0;
    if (added == 0 and removed == 0) return false;
    try writer.print("{s}+{d}{s}/{s}-{d}{s}", .{
        colors.green,
        added,
        colors.reset,
        colors.red,
        removed,
        colors.reset,
    });
    return true;
}

/// Read idle-since file for this session and write the indicator directly.
/// Reads and formats in one call to avoid returning a dangling stack slice.
/// Returns true if indicator was written, false if not idle or file missing.
fn formatIdleSince(writer: anytype, session_id: ?[]const u8) !bool {
    const sid = session_id orelse return false;
    if (sid.len == 0) return false;
    const home = std.posix.getenv("HOME") orelse return false;
    var path_buf: [512]u8 = undefined;
    const path = std.fmt.bufPrint(&path_buf, "{s}/.claude/.idle-since-{s}", .{ home, sid }) catch return false;

    const file = std.fs.cwd().openFile(path, .{}) catch return false;
    defer file.close();

    // File contains a short time string like "14:45\n"
    var buf: [32]u8 = undefined;
    const bytes_read = file.read(&buf) catch return false;
    if (bytes_read == 0) return false;

    const trimmed = std.mem.trim(u8, buf[0..bytes_read], " \t\n\r");
    if (trimmed.len == 0) return false;

    try writer.print(" 💤{s}{s}{s}", .{ colors.light_gray, trimmed, colors.reset });
    return true;
}

/// Get the last segment of a path (e.g., "/foo/bar/baz" -> "baz")
fn getLastPathSegment(path: []const u8) []const u8 {
    if (path.len == 0) return path;

    // Handle trailing slash
    var end = path.len;
    while (end > 0 and path[end - 1] == '/') : (end -= 1) {}
    if (end == 0) return "";

    // Find the last slash before end
    var start = end;
    while (start > 0 and path[start - 1] != '/') : (start -= 1) {}

    return path[start..end];
}

/// How many trailing path segments the branch name covers.
/// 0 means no match: the branch carries information the path does not,
/// so it earns its own bracket display. Non-zero means the path already
/// shows the branch and the bracket can be dropped:
///   - exact leaf: branch "main" in ".../main" -> 1
///   - slash-aware: branch "bb/720-x" in ".../bb/720-x" -> 2
///   - prefix-dropped worktree dir: branch "worktree-prf-x" in ".../prf-x" -> 1
fn branchPathMatch(branch: []const u8, path: []const u8) usize {
    if (branch.len == 0 or path.len == 0) return 0;

    // Walk '/'-separated branch parts and path segments backward in lockstep;
    // a full match means every branch part is mirrored by a trailing segment.
    var b_it = std.mem.splitBackwardsScalar(u8, branch, '/');
    var p_it = std.mem.splitBackwardsScalar(u8, path, '/');
    var matched: usize = 0;
    var full_match = true;
    while (b_it.next()) |b_part| {
        if (b_part.len == 0) {
            full_match = false;
            break;
        }
        // Skip empty path segments from trailing or doubled slashes
        const p_part: ?[]const u8 = while (p_it.next()) |p| {
            if (p.len > 0) break p;
        } else null;
        if (p_part == null or !std.mem.eql(u8, b_part, p_part.?)) {
            full_match = false;
            break;
        }
        matched += 1;
    }
    if (full_match) return matched;

    // Worktree dirs often drop a branch prefix (dir "prf-x" for branch
    // "worktree-prf-x"). Require a separator boundary so leaf "a-leaf"
    // does not match branch "not-a-leaf"-style accidental suffixes.
    const leaf = getLastPathSegment(path);
    if (leaf.len > 0 and branch.len > leaf.len and std.mem.endsWith(u8, branch, leaf)) {
        const sep = branch[branch.len - leaf.len - 1];
        if (sep == '-' or sep == '/' or sep == '_') return 1;
    }

    return 0;
}

/// Abbreviate a git branch name intelligently
/// Detects Linear issue format (e.g., SEND-77-description -> SEND-77)
/// Otherwise uses smart compaction like path segments
fn abbreviateBranch(allocator: Allocator, branch: []const u8) ![]const u8 {
    if (branch.len == 0) return try allocator.dupe(u8, branch);

    // Try to detect Linear issue pattern: PREFIX-NUMBER-...
    // Pattern: [A-Z]+-[0-9]+(-.*)?
    var i: usize = 0;

    // Find uppercase prefix
    while (i < branch.len and branch[i] >= 'A' and branch[i] <= 'Z') : (i += 1) {}

    // Need at least one uppercase letter followed by hyphen
    if (i == 0 or i >= branch.len or branch[i] != '-') {
        return abbreviateSegment(allocator, branch);
    }

    i += 1; // skip the hyphen

    // Find digits
    const num_start = i;
    while (i < branch.len and branch[i] >= '0' and branch[i] <= '9') : (i += 1) {}

    // Need at least one digit
    if (i == num_start) {
        return abbreviateSegment(allocator, branch);
    }

    // Valid if at end of string or followed by hyphen
    if (i == branch.len or branch[i] == '-') {
        // This looks like a Linear issue! Return PREFIX-NUMBER
        return try allocator.dupe(u8, branch[0..i]);
    }

    // Doesn't match pattern, fall back to segment abbreviation
    return abbreviateSegment(allocator, branch);
}

/// Abbreviate a path segment intelligently
fn abbreviateSegment(allocator: Allocator, segment: []const u8) ![]const u8 {
    if (segment.len <= 5) return try allocator.dupe(u8, segment);

    // Check if segment contains separators
    if (std.mem.indexOfAny(u8, segment, "-_") == null) {
        // No separators, just take first few characters for very long names
        if (segment.len > 8) {
            return try allocator.dupe(u8, segment[0..3]);
        } else {
            return try allocator.dupe(u8, segment);
        }
    }

    var result = try std.ArrayList(u8).initCapacity(allocator, 0);

    var parts = std.mem.splitAny(u8, segment, "-_");
    var first = true;

    while (parts.next()) |part| {
        if (part.len == 0) continue;

        if (!first) try result.append(allocator, '-');

        if (part.len >= 3 and std.mem.eql(u8, part[0..2], "0x")) {
            try result.appendSlice(allocator, part[0..3]);
        } else if (part.len <= 3) {
            try result.appendSlice(allocator, part);
        } else {
            try result.append(allocator, part[0]);
        }

        first = false;
    }

    if (result.items.len == 0) {
        result.deinit(allocator);
        return try allocator.dupe(u8, segment);
    }

    return try result.toOwnedSlice(allocator);
}

/// Format path with home directory abbreviation and intelligent shortening
fn formatPath(writer: anytype, path: []const u8) !void {
    const home = std.posix.getenv("HOME") orelse "";
    if (home.len > 0 and std.mem.startsWith(u8, path, home)) {
        try writer.print("~{s}", .{path[home.len..]});
    } else {
        try writer.print("{s}", .{path});
    }
}

/// Worktree plumbing directory names that carry no signal on the status
/// line; runs of dropped segments collapse into a single "…".
const plumbing_segments = [_][]const u8{ ".bare", ".claude", "worktrees", ".worktrees" };

/// At most this many real segments render; deeper paths elide middles into
/// "…". Branch-covered tail segments are never elided.
const max_path_segments = 5;

/// Backstop cap (display chars) for the zmx session name after leaf dedupe
const max_zmx_display = 16;

fn isPlumbingSegment(segment: []const u8) bool {
    for (plumbing_segments) |p| {
        if (std.mem.eql(u8, segment, p)) return true;
    }
    return false;
}

/// Fish-style compaction for non-leaf path segments: one character per
/// '-'/'_'-separated part ("code" -> "c", "claude-code" -> "c-c").
/// Middles are navigation context, not identity, so they crush harder than
/// abbreviateSegment (which branch display still uses). Exceptions that keep
/// segments recognizable: "0x" parts keep three chars (0xb, 0xs), a leading
/// '.'/'_' stays attached to the first letter (.config -> .c, _work -> _w).
fn fishSegment(allocator: Allocator, segment: []const u8) ![]const u8 {
    if (segment.len == 0) return try allocator.dupe(u8, segment);

    var result = try std.ArrayList(u8).initCapacity(allocator, 0);
    errdefer result.deinit(allocator);

    var rest = segment;
    if (segment[0] == '.' or segment[0] == '_') {
        try result.append(allocator, segment[0]);
        rest = segment[1..];
    }

    var parts = std.mem.splitAny(u8, rest, "-_");
    var first = true;
    while (parts.next()) |part| {
        if (part.len == 0) continue;

        if (!first) try result.append(allocator, '-');

        if (part.len >= 3 and std.mem.eql(u8, part[0..2], "0x")) {
            try result.appendSlice(allocator, part[0..3]);
        } else {
            try result.append(allocator, part[0]);
        }

        first = false;
    }

    // Segment was all separators/punctuation; show it rather than nothing
    if (result.items.len == 0 or rest.len == 0) {
        result.deinit(allocator);
        return try allocator.dupe(u8, segment);
    }

    return try result.toOwnedSlice(allocator);
}

/// Format path with intelligent shortening for statusline display.
/// highlight_trailing is the number of trailing segments covered by the git
/// branch (see branchPathMatch); they render full and green since they stand
/// in for the branch display. 0 means no branch match (leaf still renders
/// full, uncolored).
fn formatPathShort(allocator: Allocator, writer: anytype, path: []const u8, highlight_trailing: usize) !void {
    const home = std.posix.getenv("HOME") orelse "";
    var display_path = path;
    var has_home = false;

    if (std.mem.startsWith(u8, path, "~/")) {
        display_path = path[1..]; // Remove the "~" but keep the "/"
        has_home = true;
    } else if (home.len > 0 and std.mem.startsWith(u8, path, home)) {
        display_path = path[home.len..];
        has_home = true;
    }

    var segments = try std.ArrayList([]const u8).initCapacity(allocator, 0);
    defer segments.deinit(allocator);

    var parts = std.mem.splitScalar(u8, display_path, '/');
    while (parts.next()) |part| {
        if (part.len > 0) {
            try segments.append(allocator, part);
        }
    }

    const n = segments.items.len;
    if (has_home) try writer.print("~", .{});
    if (n == 0) return;

    // The tail (branch-covered segments, at minimum the leaf) always renders
    // full and is exempt from plumbing/depth elision.
    const keep_tail = @min(@max(highlight_trailing, 1), n);
    const tail_start = n - keep_tail;

    var keep = try allocator.alloc(bool, n);
    defer allocator.free(keep);
    @memset(keep, true);

    // Short paths render untouched; elision only pays off at depth.
    if (n > 3) {
        for (segments.items[0..tail_start], 0..) |segment, i| {
            if (isPlumbingSegment(segment)) keep[i] = false;
        }

        var kept: usize = 0;
        for (keep) |k| kept += @intFromBool(k);

        // Depth cap: drop middles oldest-first, but never the first segment
        // (anchors where the path lives) or the tail.
        if (kept > max_path_segments) {
            var to_drop = kept - max_path_segments;
            var i: usize = 1;
            while (to_drop > 0 and i < tail_start) : (i += 1) {
                if (keep[i]) {
                    keep[i] = false;
                    to_drop -= 1;
                }
            }
        }
    }

    var elided = false;
    for (segments.items, 0..) |segment, i| {
        if (!keep[i]) {
            // Coalesce consecutive dropped segments into one ellipsis
            if (!elided) try writer.print("/…", .{});
            elided = true;
            continue;
        }
        elided = false;
        try writer.print("/", .{});

        if (i >= tail_start) {
            if (highlight_trailing > 0) {
                try writer.print("{s}{s}{s}", .{ colors.green, segment, colors.cyan });
            } else {
                try writer.print("{s}", .{segment});
            }
        } else if (n <= 3) {
            try writer.print("{s}", .{segment});
        } else {
            const abbreviated = try fishSegment(allocator, segment);
            defer allocator.free(abbreviated);
            try writer.print("{s}", .{abbreviated});
        }
    }
}

/// Strip a leading or trailing occurrence of the directory leaf (plus its
/// joining separator) from a zmx session name. Session names are typically
/// derived from the worktree directory, so the leaf is already on the line.
/// Returns a slice of `session`; empty slice means the whole name was
/// redundant. Middle occurrences are left alone (would need allocation).
fn dedupeZmxSession(session: []const u8, leaf: []const u8) []const u8 {
    if (leaf.len == 0 or session.len < leaf.len) return session;
    if (std.mem.eql(u8, session, leaf)) return session[0..0];

    // Separator boundary required so leaf "send-connect" does not eat into
    // an unrelated session like "send-connector-x"
    if (std.mem.startsWith(u8, session, leaf)) {
        const sep = session[leaf.len];
        if (sep == '-' or sep == '_' or sep == '.' or sep == ':') {
            return session[leaf.len + 1 ..];
        }
    }
    if (std.mem.endsWith(u8, session, leaf)) {
        const sep = session[session.len - leaf.len - 1];
        if (sep == '-' or sep == '_' or sep == '.' or sep == ':') {
            return session[0 .. session.len - leaf.len - 1];
        }
    }
    return session;
}

/// Truncate to at most max_len bytes without splitting a UTF-8 sequence
fn truncateUtf8(s: []const u8, max_len: usize) []const u8 {
    if (s.len <= max_len) return s;
    var end = max_len;
    while (end > 0 and (s[end] & 0xC0) == 0x80) end -= 1;
    return s[0..end];
}

/// Strip the domain from a hostname: everything before the first dot
/// (aem5.local -> aem5, host.lan.example -> host, build-7 -> build-7). Pure so
/// the syscall wrapper below stays trivially testable.
fn shortHostname(full: []const u8) []const u8 {
    const dot = std.mem.indexOfScalar(u8, full, '.') orelse return full;
    return full[0..dot];
}

/// Short hostname for the location prefix, backed by the gethostname(2) syscall
/// (no subprocess cost, fits the low-latency guardrail). Returns "" on failure;
/// callers treat an empty host as "skip the host token". `buf` must outlive the
/// returned slice — it borrows from it.
fn getShortHostname(buf: *[std.posix.HOST_NAME_MAX]u8) []const u8 {
    const full = std.posix.gethostname(buf) catch return "";
    return shortHostname(full);
}

/// Write the shell-prompt-style location prefix `host/session@` that sits in
/// front of the path. Host is cyan (the machine must be unmistakable), the zmx
/// session and the `@` joiner are gray. Pure formatting (no env / syscalls) so
/// it is unit-testable. host=="" skips the host token; session=="" skips the
/// session token (the leaf-dedupe collapsed it); the `/` separator only appears
/// when a host precedes the session. The trailing gray `@` always joins to the
/// path that follows. `truncated` appends an ellipsis to a capped session.
/// Emits nothing when there is neither a host nor a session.
fn writeLocationPrefix(writer: anytype, host: []const u8, session: []const u8, truncated: bool) !void {
    if (host.len == 0 and session.len == 0) return;

    if (host.len > 0) try writer.print("{s}{s}", .{ colors.cyan, host });
    if (session.len > 0) {
        const sep = if (host.len > 0) "/" else "";
        try writer.print("{s}{s}{s}", .{ colors.gray, sep, session });
        if (truncated) try writer.print("…", .{});
    }
    try writer.print("{s}@{s}", .{ colors.gray, colors.reset });
}

/// Resolve host + zmx session and render the location prefix. The zmx session
/// is leaf-deduped against the worktree name already shown on the path (a
/// session that just repeats the leaf collapses to nothing, leaving `host@`)
/// and capped at max_zmx_display.
fn renderLocationPrefix(writer: anytype, current_dir: ?[]const u8) !void {
    var host_buf: [std.posix.HOST_NAME_MAX]u8 = undefined;
    const host = getShortHostname(&host_buf);

    var session: []const u8 = "";
    var truncated = false;
    if (std.posix.getenv("ZMX_SESSION")) |zmx| {
        if (zmx.len > 0) {
            const leaf = if (current_dir) |dir| getLastPathSegment(dir) else "";
            const deduped = dedupeZmxSession(zmx, leaf);
            if (deduped.len > max_zmx_display) {
                session = truncateUtf8(deduped, max_zmx_display - 1);
                truncated = true;
            } else {
                session = deduped;
            }
        }
    }

    try writeLocationPrefix(writer, host, session, truncated);
}

/// Check if directory is a git repository
fn isGitRepo(allocator: Allocator, dir: []const u8) bool {
    var buf: [256]u8 = undefined;
    var fba = std.heap.FixedBufferAllocator.init(&buf);
    const temp_alloc = fba.allocator();

    const cmd = temp_alloc.dupeZ(u8, "git rev-parse --is-inside-work-tree") catch return false;

    const result = execCommand(allocator, cmd, dir) catch return false;
    defer allocator.free(result);

    return std.mem.eql(u8, result, "true");
}

/// Get current git branch name
fn getGitBranch(allocator: Allocator, dir: []const u8) ![]const u8 {
    var buf: [256]u8 = undefined;
    var fba = std.heap.FixedBufferAllocator.init(&buf);
    const temp_alloc = fba.allocator();

    const cmd = try temp_alloc.dupeZ(u8, "git symbolic-ref -q --short HEAD || git describe --tags --exact-match");

    return execCommand(allocator, cmd, dir) catch try allocator.dupe(u8, "");
}

/// Get git status information
fn getGitStatus(allocator: Allocator, dir: []const u8) !GitStatus {
    var buf: [256]u8 = undefined;
    var fba = std.heap.FixedBufferAllocator.init(&buf);
    const temp_alloc = fba.allocator();

    const cmd = try temp_alloc.dupeZ(u8, "git status --porcelain");

    const output = execCommand(allocator, cmd, dir) catch return GitStatus{};
    defer allocator.free(output);

    return GitStatus.parse(output);
}

/// Get git repository root directory
fn getGitRoot(allocator: Allocator, dir: []const u8) !?[]const u8 {
    var buf: [256]u8 = undefined;
    var fba = std.heap.FixedBufferAllocator.init(&buf);
    const temp_alloc = fba.allocator();

    const cmd = temp_alloc.dupeZ(u8, "git rev-parse --show-toplevel") catch return null;

    const result = execCommand(allocator, cmd, dir) catch return null;
    if (result.len == 0) {
        allocator.free(result);
        return null;
    }
    return result;
}

/// Run `git rev-parse HEAD` in `dir`. Returns empty string on any failure.
/// Caller receives an allocator-owned slice; free with `allocator.free` or rely on arena.
/// Callers treat empty-string as "HEAD unknown" and omit `--git-head`.
fn getGitHead(allocator: Allocator, dir: []const u8) []const u8 {
    var buf: [256]u8 = undefined;
    var fba = std.heap.FixedBufferAllocator.init(&buf);
    const temp_alloc = fba.allocator();
    const cmd = temp_alloc.dupeZ(u8, "git rev-parse HEAD") catch return "";
    return execCommand(allocator, cmd, dir) catch "";
}

/// Delegate the rl loop segment to `rl statusline`.
///
/// Covered by live smoke rather than a fake-PATH unit test: adding test-only PATH
/// injection plumbing would create more surface area than this helper itself. The
/// contract is verified against the real `rl` CLI, and the renderer stays fail-open.
fn renderRlStatusline(
    allocator: Allocator,
    writer: anytype,
    git_root: []const u8,
    git_head: []const u8,
) !void {
    var argv_buf: [8][]const u8 = undefined;
    var argc: usize = 0;
    argv_buf[argc] = "rl";
    argc += 1;
    argv_buf[argc] = "statusline";
    argc += 1;
    argv_buf[argc] = "--format";
    argc += 1;
    argv_buf[argc] = "text";
    argc += 1;
    argv_buf[argc] = "--cwd";
    argc += 1;
    argv_buf[argc] = git_root;
    argc += 1;
    if (git_head.len > 0) {
        argv_buf[argc] = "--git-head";
        argc += 1;
        argv_buf[argc] = git_head;
        argc += 1;
    }

    var child = std.process.Child.init(argv_buf[0..argc], allocator);
    child.stdin_behavior = .Ignore;
    child.stdout_behavior = .Pipe;
    child.stderr_behavior = .Ignore;
    child.spawn() catch |err| switch (err) {
        error.FileNotFound => return,
        else => return,
    };
    errdefer _ = child.kill() catch {};

    const stdout = child.stdout orelse {
        _ = child.wait() catch {};
        return;
    };

    var stdout_buf: [1024]u8 = undefined;
    var stdout_len: usize = 0;
    while (stdout_len < stdout_buf.len) {
        const bytes_read = stdout.read(stdout_buf[stdout_len..]) catch break;
        if (bytes_read == 0) break;
        stdout_len += bytes_read;
    }

    if (stdout_len == stdout_buf.len) {
        var discard_buf: [256]u8 = undefined;
        while (true) {
            const bytes_read = stdout.read(&discard_buf) catch break;
            if (bytes_read == 0) break;
        }
    }

    _ = child.wait() catch {};
    if (stdout_len == 0) return;

    try writer.writeByte(' ');
    try writer.writeAll(stdout_buf[0..stdout_len]);
}

pub fn main() !void {
    // Use ArenaAllocator for better performance - free everything at once
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    // Parse command line arguments
    const args = try std.process.argsAlloc(allocator);
    // No need to free - arena handles it

    var debug_mode = false;
    for (args[1..]) |arg| {
        if (std.mem.eql(u8, arg, "--debug")) {
            debug_mode = true;
        }
    }

    // Read and parse JSON input
    var stdin_buffer: [8192]u8 = undefined;
    var stdin_reader = std.fs.File.stdin().readerStreaming(&stdin_buffer);
    const stdin = &stdin_reader.interface;
    const input_json = try readAllAlloc(allocator, stdin);

    // Debug logging
    if (debug_mode) {
        const debug_file = std.fs.cwd().createFile("/tmp/statusline-debug.log", .{ .truncate = false }) catch null;
        if (debug_file) |file| {
            defer file.close();
            file.seekFromEnd(0) catch {};
            const timestamp = std.time.timestamp();
            var file_buffer: [1024]u8 = undefined;
            var file_writer = file.writerStreaming(&file_buffer);
            const debug_writer = &file_writer.interface;
            debug_writer.print("[{d}] Input JSON: {s}\n", .{ timestamp, input_json }) catch {};
            debug_writer.flush() catch {};
        }
    }

    const parsed = json.parseFromSlice(StatuslineInput, allocator, input_json, .{
        .ignore_unknown_fields = true,
    }) catch |err| {
        if (debug_mode) {
            const debug_file = std.fs.cwd().createFile("/tmp/statusline-debug.log", .{ .truncate = false }) catch null;
            if (debug_file) |file| {
                defer file.close();
                file.seekFromEnd(0) catch {};
                const timestamp = std.time.timestamp();
                var file_buffer: [1024]u8 = undefined;
                var file_writer = file.writerStreaming(&file_buffer);
                const debug_writer = &file_writer.interface;
                debug_writer.print("[{d}] Parse error: {any}\n", .{ timestamp, err }) catch {};
                debug_writer.flush() catch {};
            }
        }
        var stdout_buffer: [256]u8 = undefined;
        var stdout_writer_wrapper = std.fs.File.stdout().writer(&stdout_buffer);
        const stdout = &stdout_writer_wrapper.interface;
        stdout.print("{s}~{s}\n", .{ colors.cyan, colors.reset }) catch {};
        stdout.flush() catch {};
        return;
    };

    const input = parsed.value;

    // Use a single buffer for the entire output
    var output_buf: [1024]u8 = undefined;
    var output_stream = std.io.fixedBufferStream(&output_buf);
    const writer = output_stream.writer();

    // Build statusline directly into the buffer

    // Handle workspace directory
    const current_dir = if (input.workspace) |ws| ws.current_dir else null;

    // Shell-prompt-style location prefix `host/session@` in front of the path:
    // host cyan (the machine you must not mistake), zmx session + `@` joiner
    // gray. Folds "which host" and "which zmx session" into the location token.
    try renderLocationPrefix(writer, current_dir);

    // Path renders cyan, continuing from the prefix's reset.
    try writer.print("{s}", .{colors.cyan});
    if (current_dir == null) {
        try writer.print("~{s}", .{colors.reset});
    } else {
        // Check git status first to determine if we should highlight trailing path segments
        const is_git = isGitRepo(allocator, current_dir.?);
        var branch_match: usize = 0;
        var branch: []const u8 = "";
        var owns_branch = false;

        if (is_git) {
            branch = try getGitBranch(allocator, current_dir.?);
            owns_branch = true;
            branch_match = branchPathMatch(branch, current_dir.?);
        }
        defer if (owns_branch) allocator.free(branch);

        // Format path; branch-covered trailing segments render green in place
        // of a bracket display
        try formatPathShort(allocator, writer, current_dir.?, branch_match);

        // Handle git status display
        if (is_git) {
            const git_status = try getGitStatus(allocator, current_dir.?);

            // Determine what to show in brackets
            const show_branch = branch_match == 0 and branch.len > 0;
            const has_status = !git_status.isEmpty();

            // Only show brackets if there's something to display
            if (show_branch or has_status) {
                try writer.print(" {s}{s}[", .{ colors.reset, colors.green });

                if (show_branch) {
                    const abbrev_branch = try abbreviateBranch(allocator, branch);
                    defer allocator.free(abbrev_branch);
                    try writer.print("{s}", .{abbrev_branch});
                }

                if (has_status) {
                    if (show_branch) try writer.print(" ", .{});
                    try git_status.format(writer);
                }

                try writer.print("]{s}", .{colors.reset});
            } else {
                try writer.print("{s}", .{colors.reset});
            }
        } else {
            try writer.print("{s}", .{colors.reset});
        }

        // Add rl loop segment if active (only in git repos)
        if (is_git) {
            if (try getGitRoot(allocator, current_dir.?)) |git_root| {
                defer allocator.free(git_root);
                const git_head = getGitHead(allocator, current_dir.?);
                try renderRlStatusline(allocator, writer, git_root, git_head);
            }
        }
    }

    // Add model display with gauge
    if (input.model) |model| {
        if (model.display_name) |name| {
            const model_type = ModelType.fromName(name);

            // Calculate context usage from current_usage (v2.0.70+) or fall back to transcript parsing
            const usage: ContextUsage = blk: {
                if (input.context_window) |ctx| {
                    if (ctx.current_usage) |cur| {
                        // Use current_usage token counts directly (v2.0.70+)
                        const total_tokens = cur.totalTokens();
                        const window_size: f64 = @floatFromInt(ctx.context_window_size orelse 200000);
                        // Effective context is 77.5% of window (22.5% reserved for autocompact buffer)
                        const effective_size = window_size * 0.775;
                        const pct = @min(100.0, (@as(f64, @floatFromInt(total_tokens)) * 100.0) / effective_size);
                        break :blk ContextUsage{ .percentage = pct, .total_tokens = @intCast(total_tokens) };
                    }
                }
                // Fall back to transcript parsing for older Claude Code versions
                const context_size = if (input.context_window) |ctx| ctx.context_window_size else null;
                break :blk try calculateContextUsage(allocator, input.transcript_path, context_size);
            };

            // Gauge + model emoji (e.g., "██░ 🎭")
            try writer.print(" ", .{});
            try usage.formatGauge(writer, default_gauge_config);
            // Show percentage for debugging
            if (debug_mode) {
                try writer.print(" {s}{d:.1}%", .{ colors.gray, usage.percentage });
            }
            try writer.print(" {s}{s}", .{ model_type.emoji(), colors.gray });

            // Duration (space-separated, no bullets)
            if (input.cost != null and input.cost.?.total_duration_ms != null) {
                try writer.print(" {s}", .{colors.light_gray});
                _ = try formatSessionDuration(input, writer);
            }

            // Cost
            if (input.cost != null and input.cost.?.total_cost_usd != null) {
                const cost_usd = input.cost.?.total_cost_usd.?;
                if (cost_usd >= 0.001) {
                    try writer.print(" {s}", .{colors.light_gray});
                    _ = try formatCost(input, writer);
                }
            }

            // Lines changed
            if (input.cost != null) {
                const added = input.cost.?.total_lines_added orelse 0;
                const removed = input.cost.?.total_lines_removed orelse 0;
                if (added > 0 or removed > 0) {
                    try writer.print(" ", .{});
                    _ = try formatLinesChanged(input, writer);
                }
            }

            try writer.print("{s}", .{colors.reset});
        }
    }

    // Idle-since indicator (visible only when agent is waiting for input)
    _ = try formatIdleSince(writer, input.session_id);

    // Output the complete statusline at once
    const output = output_stream.getWritten();

    // Debug logging
    if (debug_mode) {
        const debug_file = std.fs.cwd().createFile("/tmp/statusline-debug.log", .{ .truncate = false }) catch null;
        if (debug_file) |file| {
            defer file.close();
            file.seekFromEnd(0) catch {};
            const timestamp = std.time.timestamp();
            var file_buffer: [1024]u8 = undefined;
            var file_writer = file.writerStreaming(&file_buffer);
            const debug_writer = &file_writer.interface;
            debug_writer.print("[{d}] Output: {s}\n", .{ timestamp, output }) catch {};
            debug_writer.flush() catch {};
        }
    }

    var stdout_buffer: [256]u8 = undefined;
    var stdout_writer_wrapper = std.fs.File.stdout().writer(&stdout_buffer);
    const stdout = &stdout_writer_wrapper.interface;
    stdout.print("{s}\n", .{output}) catch {};
    stdout.flush() catch {};
}

test "ModelType detects models correctly" {
    try std.testing.expectEqual(ModelType.opus, ModelType.fromName("Claude Opus 4.1"));
    try std.testing.expectEqual(ModelType.opus, ModelType.fromName("Opus"));
    try std.testing.expectEqual(ModelType.sonnet, ModelType.fromName("Claude Sonnet 3.5"));
    try std.testing.expectEqual(ModelType.sonnet, ModelType.fromName("Sonnet"));
    try std.testing.expectEqual(ModelType.haiku, ModelType.fromName("Claude Haiku"));
    try std.testing.expectEqual(ModelType.haiku, ModelType.fromName("Haiku"));
    try std.testing.expectEqual(ModelType.fable, ModelType.fromName("Fable 5"));
    try std.testing.expectEqual(ModelType.fable, ModelType.fromName("Fable"));
    try std.testing.expectEqual(ModelType.unknown, ModelType.fromName("GPT-4"));
}

test "ModelType emoji representations" {
    try std.testing.expectEqualStrings("🎭", ModelType.opus.emoji());
    try std.testing.expectEqualStrings("📜", ModelType.sonnet.emoji());
    try std.testing.expectEqualStrings("🍃", ModelType.haiku.emoji());
    try std.testing.expectEqualStrings("🦊", ModelType.fable.emoji());
    try std.testing.expectEqualStrings("?", ModelType.unknown.emoji());
}

test "ContextUsage color thresholds" {
    const low = ContextUsage{ .percentage = 30.0 };
    const medium = ContextUsage{ .percentage = 60.0 };
    const high = ContextUsage{ .percentage = 80.0 };
    const critical = ContextUsage{ .percentage = 95.0 };

    try std.testing.expectEqualStrings(colors.green, low.color());
    try std.testing.expectEqualStrings(colors.yellow, medium.color());
    try std.testing.expectEqualStrings(colors.orange, high.color());
    try std.testing.expectEqualStrings(colors.red, critical.color());
}

test "ContextUsage gradient color" {
    // 0% = pure green
    const zero = ContextUsage{ .percentage = 0.0 };
    const green = zero.gradientColor();
    try std.testing.expectEqual(@as(u8, 0), green.r);
    try std.testing.expectEqual(@as(u8, 255), green.g);
    try std.testing.expectEqual(@as(u8, 0), green.b);

    // 50% = yellow
    const half = ContextUsage{ .percentage = 50.0 };
    const yellow = half.gradientColor();
    try std.testing.expectEqual(@as(u8, 255), yellow.r);
    try std.testing.expectEqual(@as(u8, 255), yellow.g);
    try std.testing.expectEqual(@as(u8, 0), yellow.b);

    // 100% = red
    const full = ContextUsage{ .percentage = 100.0 };
    const red = full.gradientColor();
    try std.testing.expectEqual(@as(u8, 255), red.r);
    try std.testing.expectEqual(@as(u8, 0), red.g);
    try std.testing.expectEqual(@as(u8, 0), red.b);

    // 75% = orange-ish (halfway between yellow and red)
    const three_quarter = ContextUsage{ .percentage = 75.0 };
    const orange = three_quarter.gradientColor();
    try std.testing.expectEqual(@as(u8, 255), orange.r);
    try std.testing.expectEqual(@as(u8, 127), orange.g); // 255 * 0.5
    try std.testing.expectEqual(@as(u8, 0), orange.b);
}

test "GitStatus parsing" {
    const git_output = " M file1.txt\nA  file2.txt\n D file3.txt\n?? file4.txt\n";
    const status = GitStatus.parse(git_output);

    try std.testing.expectEqual(@as(u32, 1), status.added);
    try std.testing.expectEqual(@as(u32, 1), status.modified);
    try std.testing.expectEqual(@as(u32, 1), status.deleted);
    try std.testing.expectEqual(@as(u32, 1), status.untracked);
    try std.testing.expect(!status.isEmpty());
}

test "GitStatus empty" {
    const empty_status = GitStatus{};
    try std.testing.expect(empty_status.isEmpty());
}

test "formatPath basic functionality" {
    var buf: [256]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buf);
    const writer = stream.writer();

    try formatPath(writer, "/tmp/test/project");
    try std.testing.expectEqualStrings("/tmp/test/project", stream.getWritten());
}

test "JSON parsing with fixture data" {
    const allocator = std.testing.allocator;

    const opus_json =
        \\{
        \\  "hook_event_name": "Status",
        \\  "session_id": "test123",
        \\  "model": {
        \\    "id": "claude-opus-4-1",
        \\    "display_name": "Opus"
        \\  },
        \\  "workspace": {
        \\    "current_dir": "/Users/allen/test"
        \\  }
        \\}
    ;

    const parsed = try json.parseFromSlice(StatuslineInput, allocator, opus_json, .{
        .ignore_unknown_fields = true,
    });
    defer parsed.deinit();

    try std.testing.expectEqualStrings("Opus", parsed.value.model.?.display_name.?);
    try std.testing.expectEqualStrings("/Users/allen/test", parsed.value.workspace.?.current_dir.?);
    try std.testing.expectEqualStrings("test123", parsed.value.session_id.?);
}

test "JSON parsing with minimal data" {
    const allocator = std.testing.allocator;

    const minimal_json =
        \\{
        \\  "workspace": {
        \\    "current_dir": "/tmp"
        \\  }
        \\}
    ;

    const parsed = try json.parseFromSlice(StatuslineInput, allocator, minimal_json, .{
        .ignore_unknown_fields = true,
    });
    defer parsed.deinit();

    try std.testing.expectEqualStrings("/tmp", parsed.value.workspace.?.current_dir.?);
    try std.testing.expect(parsed.value.model == null);
    try std.testing.expect(parsed.value.session_id == null);
}

test "abbreviateSegment function" {
    const allocator = std.testing.allocator;

    {
        const result = try abbreviateSegment(allocator, "0xbigboss");
        defer allocator.free(result);
        try std.testing.expectEqualStrings("0xb", result);
    }

    {
        const result = try abbreviateSegment(allocator, "canton-network");
        defer allocator.free(result);
        try std.testing.expectEqualStrings("c-n", result);
    }

    {
        const result = try abbreviateSegment(allocator, "decentralized-canton-sync");
        defer allocator.free(result);
        try std.testing.expectEqualStrings("d-c-s", result);
    }

    {
        const result = try abbreviateSegment(allocator, "short");
        defer allocator.free(result);
        try std.testing.expectEqualStrings("short", result);
    }

    {
        const result = try abbreviateSegment(allocator, "api");
        defer allocator.free(result);
        try std.testing.expectEqualStrings("api", result);
    }
}

test "abbreviateBranch with Linear issue format" {
    const allocator = std.testing.allocator;

    // Linear issue: SEND-77-description -> SEND-77
    {
        const result = try abbreviateBranch(allocator, "SEND-77-dapp-api-controller");
        defer allocator.free(result);
        try std.testing.expectEqualStrings("SEND-77", result);
    }

    // Linear issue: ENG-1234-some-feature -> ENG-1234
    {
        const result = try abbreviateBranch(allocator, "ENG-1234-some-feature");
        defer allocator.free(result);
        try std.testing.expectEqualStrings("ENG-1234", result);
    }

    // Just the issue number, no description
    {
        const result = try abbreviateBranch(allocator, "PROJ-42");
        defer allocator.free(result);
        try std.testing.expectEqualStrings("PROJ-42", result);
    }

    // Not a Linear issue - falls back to segment abbreviation
    {
        const result = try abbreviateBranch(allocator, "feature-branch-name");
        defer allocator.free(result);
        try std.testing.expectEqualStrings("f-b-n", result);
    }

    // Main/master branches stay as-is
    {
        const result = try abbreviateBranch(allocator, "main");
        defer allocator.free(result);
        try std.testing.expectEqualStrings("main", result);
    }

    // Lowercase prefix - not Linear format, falls back to segment abbreviation
    // Short segments (<=3 chars) stay as-is
    {
        const result = try abbreviateBranch(allocator, "fix-123-bug");
        defer allocator.free(result);
        try std.testing.expectEqualStrings("fix-123-bug", result);
    }

    // Longer segments get abbreviated
    {
        const result = try abbreviateBranch(allocator, "feature-authentication-flow");
        defer allocator.free(result);
        try std.testing.expectEqualStrings("f-a-f", result);
    }
}

test "getLastPathSegment function" {
    // Basic path
    try std.testing.expectEqualStrings("project", getLastPathSegment("/home/user/project"));

    // Path with trailing slash
    try std.testing.expectEqualStrings("project", getLastPathSegment("/home/user/project/"));

    // Single segment
    try std.testing.expectEqualStrings("project", getLastPathSegment("project"));

    // Root
    try std.testing.expectEqualStrings("", getLastPathSegment("/"));

    // Empty
    try std.testing.expectEqualStrings("", getLastPathSegment(""));
}

test "formatPathShort with long path" {
    const allocator = std.testing.allocator;
    var buf: [256]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buf);
    const writer = stream.writer();

    try formatPathShort(allocator, writer, "/Users/test/0xbigboss/canton-network/canton-foundation/decentralized-canton-sync/token-standard", 0);

    const result = stream.getWritten();
    try std.testing.expect(result.len < 50);
    try std.testing.expect(std.mem.indexOf(u8, result, "token-standard") != null);
}

test "formatPathShort with short path" {
    const allocator = std.testing.allocator;
    var buf: [256]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buf);
    const writer = stream.writer();

    try formatPathShort(allocator, writer, "/home/user/project", 0);
    try std.testing.expectEqualStrings("/home/user/project", stream.getWritten());
}

test "formatPathShort with highlighted last segment" {
    const allocator = std.testing.allocator;
    var buf: [256]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buf);
    const writer = stream.writer();

    try formatPathShort(allocator, writer, "/home/user/feature-branch", 1);
    const result = stream.getWritten();
    // Should contain green color code before "feature-branch"
    try std.testing.expect(std.mem.indexOf(u8, result, colors.green) != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "feature-branch") != null);
}

test "formatPathShort drops worktree plumbing segments" {
    const allocator = std.testing.allocator;
    var buf: [256]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buf);
    const writer = stream.writer();

    // Real layout: <repo>.worktrees/.bare/.claude/worktrees/<leaf>
    // The .bare/.claude/worktrees run coalesces into a single ellipsis
    try formatPathShort(allocator, writer, "/Users/test/0xsend/canton-monorepo.worktrees/.bare/.claude/worktrees/prf-onboarding-hardening", 0);
    try std.testing.expectEqualStrings("/U/t/0xs/c-m/…/prf-onboarding-hardening", stream.getWritten());
}

test "formatPathShort caps segment depth" {
    const allocator = std.testing.allocator;
    var buf: [256]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buf);
    const writer = stream.writer();

    // 7 real segments, no plumbing: middles drop oldest-first to the cap,
    // keeping the first segment as anchor
    try formatPathShort(allocator, writer, "/Users/test/0xbigboss/canton-network/canton-foundation/decentralized-canton-sync/token-standard", 0);
    try std.testing.expectEqualStrings("/U/…/c-n/c-f/d-c-s/token-standard", stream.getWritten());
}

test "formatPathShort highlights branch-covered tail segments" {
    const allocator = std.testing.allocator;
    var buf: [256]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buf);
    const writer = stream.writer();

    // Branch "bb/720-testnet-enablement" covers the last two segments; both
    // render full and green (no abbreviation of the branch display)
    try formatPathShort(allocator, writer, "/Users/test/canton-data-api.worktrees/bb/720-testnet-enablement", 2);
    const result = stream.getWritten();
    const expected = "/U/t/c-d-a/" ++ colors.green ++ "bb" ++ colors.cyan ++ "/" ++ colors.green ++ "720-testnet-enablement" ++ colors.cyan;
    try std.testing.expectEqualStrings(expected, result);
}

test "formatPathShort fish-style middles" {
    const allocator = std.testing.allocator;
    var buf: [256]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buf);
    const writer = stream.writer();

    // Deep paths crush every middle to one char per part; leaf stays full
    try formatPathShort(allocator, writer, "/0xbigboss/0xsend/some-repo/sub/leaf-dir", 0);
    try std.testing.expectEqualStrings("/0xb/0xs/s-r/s/leaf-dir", stream.getWritten());
}

test "fishSegment function" {
    const allocator = std.testing.allocator;

    {
        const result = try fishSegment(allocator, "code");
        defer allocator.free(result);
        try std.testing.expectEqualStrings("c", result);
    }

    {
        const result = try fishSegment(allocator, "claude-code");
        defer allocator.free(result);
        try std.testing.expectEqualStrings("c-c", result);
    }

    // 0x prefix keeps three chars for recognizability
    {
        const result = try fishSegment(allocator, "0xbigboss");
        defer allocator.free(result);
        try std.testing.expectEqualStrings("0xb", result);
    }

    {
        const result = try fishSegment(allocator, "0xsend");
        defer allocator.free(result);
        try std.testing.expectEqualStrings("0xs", result);
    }

    // Leading punctuation stays attached to the first letter
    {
        const result = try fishSegment(allocator, "_work");
        defer allocator.free(result);
        try std.testing.expectEqualStrings("_w", result);
    }

    {
        const result = try fishSegment(allocator, ".config");
        defer allocator.free(result);
        try std.testing.expectEqualStrings(".c", result);
    }

    // Dot is not a separator: suffix noise like ".worktrees" drops away
    {
        const result = try fishSegment(allocator, "canton-monorepo.worktrees");
        defer allocator.free(result);
        try std.testing.expectEqualStrings("c-m", result);
    }

    // Degenerate all-separator segment passes through rather than vanishing
    {
        const result = try fishSegment(allocator, "_");
        defer allocator.free(result);
        try std.testing.expectEqualStrings("_", result);
    }
}

test "branchPathMatch" {
    // Exact leaf match
    try std.testing.expectEqual(@as(usize, 1), branchPathMatch("main", "/home/user/main"));

    // Slash-aware: branch covers trailing segments
    try std.testing.expectEqual(@as(usize, 2), branchPathMatch("bb/720-testnet-enablement", "/u/r/bb/720-testnet-enablement"));

    // Prefix-dropped worktree dir: branch ends with leaf at '-' boundary
    try std.testing.expectEqual(@as(usize, 1), branchPathMatch("worktree-prf-onboarding-hardening", "/u/r/prf-onboarding-hardening"));

    // No match: unrelated branch
    try std.testing.expectEqual(@as(usize, 0), branchPathMatch("main", "/u/r/send-connect"));

    // No match: slash parts diverge
    try std.testing.expectEqual(@as(usize, 0), branchPathMatch("feature/x", "/u/feature/y"));

    // Suffix without separator boundary is not a match
    try std.testing.expectEqual(@as(usize, 0), branchPathMatch("xprf-onboarding", "/u/prf-onboarding"));

    // Trailing slash on path is tolerated
    try std.testing.expectEqual(@as(usize, 1), branchPathMatch("main", "/home/user/main/"));

    // Empty inputs
    try std.testing.expectEqual(@as(usize, 0), branchPathMatch("", "/u/r/x"));
    try std.testing.expectEqual(@as(usize, 0), branchPathMatch("main", ""));
}

test "dedupeZmxSession" {
    // Leaf at end: keep the prefix
    try std.testing.expectEqualStrings("cm", dedupeZmxSession("cm-prf-onboarding-hardening", "prf-onboarding-hardening"));

    // Leaf at start: keep the unique tail (disambiguates multiple sessions)
    try std.testing.expectEqualStrings("dbe1-0", dedupeZmxSession("send-connect-dbe1-0", "send-connect"));

    // Whole name is the leaf: nothing left
    try std.testing.expectEqualStrings("", dedupeZmxSession("send-connect", "send-connect"));

    // Boundary required: "send-connector" must not match leaf "send-connect"
    try std.testing.expectEqualStrings("send-connector-x", dedupeZmxSession("send-connector-x", "send-connect"));

    // Unrelated session name passes through
    try std.testing.expectEqualStrings("other-session", dedupeZmxSession("other-session", "send-connect"));

    // Empty leaf passes through
    try std.testing.expectEqualStrings("any-session", dedupeZmxSession("any-session", ""));
}

test "truncateUtf8" {
    try std.testing.expectEqualStrings("short", truncateUtf8("short", 16));
    try std.testing.expectEqualStrings("exactly-16-chars", truncateUtf8("exactly-16-chars", 16));
    try std.testing.expectEqualStrings("abcde", truncateUtf8("abcdefgh", 5));
    // Multibyte: "héllo" is h(1) é(2) l l o — cutting at byte 2 would split é
    try std.testing.expectEqualStrings("h", truncateUtf8("héllo", 2));
}

test "shortHostname strips domain" {
    try std.testing.expectEqualStrings("aem5", shortHostname("aem5.local"));
    try std.testing.expectEqualStrings("host", shortHostname("host.lan.example.com"));
    // No dot: passes through unchanged
    try std.testing.expectEqualStrings("build-7", shortHostname("build-7"));
    try std.testing.expectEqualStrings("", shortHostname(""));
    // Leading dot: nothing before it
    try std.testing.expectEqualStrings("", shortHostname(".local"));
}

test "writeLocationPrefix" {
    var buf: [256]u8 = undefined;

    // host + session: host cyan, /session and @ gray, path-bound reset
    {
        var stream = std.io.fixedBufferStream(&buf);
        try writeLocationPrefix(stream.writer(), "aem5", "sox-1", false);
        try std.testing.expectEqualStrings(
            colors.cyan ++ "aem5" ++ colors.gray ++ "/sox-1" ++ colors.gray ++ "@" ++ colors.reset,
            stream.getWritten(),
        );
    }

    // host only (session collapsed by leaf-dedupe): host@ with no slash
    {
        var stream = std.io.fixedBufferStream(&buf);
        try writeLocationPrefix(stream.writer(), "aem5", "", false);
        try std.testing.expectEqualStrings(
            colors.cyan ++ "aem5" ++ colors.gray ++ "@" ++ colors.reset,
            stream.getWritten(),
        );
    }

    // session only (hostname unavailable): no leading slash before the session
    {
        var stream = std.io.fixedBufferStream(&buf);
        try writeLocationPrefix(stream.writer(), "", "sox-1", false);
        try std.testing.expectEqualStrings(
            colors.gray ++ "sox-1" ++ colors.gray ++ "@" ++ colors.reset,
            stream.getWritten(),
        );
    }

    // truncated session gets a trailing ellipsis (no extra color reissue)
    {
        var stream = std.io.fixedBufferStream(&buf);
        try writeLocationPrefix(stream.writer(), "aem5", "verylongsession", true);
        try std.testing.expectEqualStrings(
            colors.cyan ++ "aem5" ++ colors.gray ++ "/verylongsession" ++ "…" ++ colors.gray ++ "@" ++ colors.reset,
            stream.getWritten(),
        );
    }

    // neither host nor session: emits nothing
    {
        var stream = std.io.fixedBufferStream(&buf);
        try writeLocationPrefix(stream.writer(), "", "", false);
        try std.testing.expectEqualStrings("", stream.getWritten());
    }
}

test "calculateContextUsageFromApi with API values" {
    // NOTE: This function exists but is currently unused due to bug in Claude Code API
    // See: https://github.com/anthropics/claude-code/issues/13783
    // Effective context = 200000 * 0.775 = 155000
    // Test with 50% usage: 77500 % 155000 = 77500, 77500/155000 = 50%
    const input_50 = StatuslineInput{
        .context_window = .{
            .total_input_tokens = 40000,
            .total_output_tokens = 37500,
            .context_window_size = 200000,
        },
    };
    const usage_50 = calculateContextUsageFromApi(input_50);
    try std.testing.expectEqual(@as(f64, 50.0), usage_50.percentage);

    // Test modulus wrap: 232500 tokens (1.5x effective) should also be 50%
    // 232500 % 155000 = 77500, 77500/155000 = 50%
    const input_wrap = StatuslineInput{
        .context_window = .{
            .total_input_tokens = 120000,
            .total_output_tokens = 112500,
            .context_window_size = 200000,
        },
    };
    const usage_wrap = calculateContextUsageFromApi(input_wrap);
    try std.testing.expectEqual(@as(f64, 50.0), usage_wrap.percentage);

    // Test with missing context_window
    const input_empty = StatuslineInput{};
    const usage_empty = calculateContextUsageFromApi(input_empty);
    try std.testing.expectEqual(@as(f64, 0.0), usage_empty.percentage);

    // Test with zero context window size
    const input_zero = StatuslineInput{
        .context_window = .{
            .total_input_tokens = 1000,
            .total_output_tokens = 1000,
            .context_window_size = 0,
        },
    };
    const usage_zero = calculateContextUsageFromApi(input_zero);
    try std.testing.expectEqual(@as(f64, 0.0), usage_zero.percentage);
}

test "calculateContextUsage returns zero with no transcript" {
    const allocator = std.testing.allocator;
    const usage = try calculateContextUsage(allocator, null, 200000);
    try std.testing.expectEqual(@as(f64, 0.0), usage.percentage);
}

test "formatCost function with rounding" {
    var buf: [64]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buf);
    const writer = stream.writer();

    // Test < $1: shows 2 decimals
    const input_low = StatuslineInput{
        .cost = .{ .total_cost_usd = 0.45 },
    };
    _ = try formatCost(input_low, writer);
    try std.testing.expectEqualStrings("$0.45", stream.getWritten());

    // Test $1-$10: shows 1 decimal
    stream.reset();
    const input_mid = StatuslineInput{
        .cost = .{ .total_cost_usd = 5.67 },
    };
    _ = try formatCost(input_mid, writer);
    try std.testing.expectEqualStrings("$5.7", stream.getWritten());

    // Test >= $10: rounds to whole dollars
    stream.reset();
    const input_high = StatuslineInput{
        .cost = .{ .total_cost_usd = 54.16 },
    };
    _ = try formatCost(input_high, writer);
    try std.testing.expectEqualStrings("$54", stream.getWritten());

    // Test negligible cost returns false
    stream.reset();
    const input_negligible = StatuslineInput{
        .cost = .{ .total_cost_usd = 0.0001 },
    };
    const result_negligible = try formatCost(input_negligible, writer);
    try std.testing.expect(!result_negligible);

    // Test no cost returns false
    stream.reset();
    const input_no_cost = StatuslineInput{};
    const result_no_cost = try formatCost(input_no_cost, writer);
    try std.testing.expect(!result_no_cost);
}

test "formatLinesChanged function" {
    var buf: [128]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buf);
    const writer = stream.writer();

    // Test with both added and removed
    const input_both = StatuslineInput{
        .cost = .{
            .total_lines_added = 150,
            .total_lines_removed = 25,
        },
    };
    const result = try formatLinesChanged(input_both, writer);
    try std.testing.expect(result);
    // Should contain +150 and -25 with color codes
    const output = stream.getWritten();
    try std.testing.expect(std.mem.indexOf(u8, output, "+150") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "-25") != null);

    // Test with zeros
    stream.reset();
    const input_zeros = StatuslineInput{
        .cost = .{
            .total_lines_added = 0,
            .total_lines_removed = 0,
        },
    };
    const result_zeros = try formatLinesChanged(input_zeros, writer);
    try std.testing.expect(!result_zeros);

    // Test with no cost
    stream.reset();
    const input_no_cost = StatuslineInput{};
    const result_no_cost = try formatLinesChanged(input_no_cost, writer);
    try std.testing.expect(!result_no_cost);
}

test "JSON parsing with full API structure" {
    const allocator = std.testing.allocator;

    const full_json =
        \\{
        \\  "hook_event_name": "Status",
        \\  "session_id": "abc123",
        \\  "model": {
        \\    "id": "claude-opus-4-1",
        \\    "display_name": "Opus"
        \\  },
        \\  "workspace": {
        \\    "current_dir": "/test/project",
        \\    "project_dir": "/test"
        \\  },
        \\  "version": "1.0.80",
        \\  "context_window": {
        \\    "total_input_tokens": 15234,
        \\    "total_output_tokens": 4521,
        \\    "context_window_size": 200000
        \\  },
        \\  "cost": {
        \\    "total_cost_usd": 0.01234,
        \\    "total_duration_ms": 45000,
        \\    "total_api_duration_ms": 2300,
        \\    "total_lines_added": 156,
        \\    "total_lines_removed": 23
        \\  }
        \\}
    ;

    const parsed = try json.parseFromSlice(StatuslineInput, allocator, full_json, .{
        .ignore_unknown_fields = true,
    });
    defer parsed.deinit();

    // Check model
    try std.testing.expectEqualStrings("Opus", parsed.value.model.?.display_name.?);
    try std.testing.expectEqualStrings("claude-opus-4-1", parsed.value.model.?.id.?);

    // Check workspace
    try std.testing.expectEqualStrings("/test/project", parsed.value.workspace.?.current_dir.?);
    try std.testing.expectEqualStrings("/test", parsed.value.workspace.?.project_dir.?);

    // Check context_window
    try std.testing.expectEqual(@as(i64, 15234), parsed.value.context_window.?.total_input_tokens.?);
    try std.testing.expectEqual(@as(i64, 4521), parsed.value.context_window.?.total_output_tokens.?);
    try std.testing.expectEqual(@as(i64, 200000), parsed.value.context_window.?.context_window_size.?);

    // Check cost
    try std.testing.expect(parsed.value.cost.?.total_cost_usd.? > 0.01);
    try std.testing.expectEqual(@as(i64, 45000), parsed.value.cost.?.total_duration_ms.?);
    try std.testing.expectEqual(@as(i64, 156), parsed.value.cost.?.total_lines_added.?);
    try std.testing.expectEqual(@as(i64, 23), parsed.value.cost.?.total_lines_removed.?);
}

test "JSON parsing with current_usage field (v2.0.70+)" {
    const allocator = std.testing.allocator;

    const json_with_usage =
        \\{
        \\  "hook_event_name": "Status",
        \\  "session_id": "abc123",
        \\  "model": {
        \\    "id": "claude-opus-4-1",
        \\    "display_name": "Opus"
        \\  },
        \\  "workspace": {
        \\    "current_dir": "/test/project"
        \\  },
        \\  "context_window": {
        \\    "context_window_size": 200000,
        \\    "current_usage": {
        \\      "input_tokens": 100,
        \\      "output_tokens": 50,
        \\      "cache_creation_input_tokens": 500,
        \\      "cache_read_input_tokens": 67000
        \\    }
        \\  },
        \\  "version": "2.0.70"
        \\}
    ;

    const parsed = try json.parseFromSlice(StatuslineInput, allocator, json_with_usage, .{
        .ignore_unknown_fields = true,
    });
    defer parsed.deinit();

    // Check current_usage is parsed correctly
    try std.testing.expect(parsed.value.context_window != null);
    try std.testing.expect(parsed.value.context_window.?.current_usage != null);

    const cur = parsed.value.context_window.?.current_usage.?;
    try std.testing.expectEqual(@as(i64, 100), cur.input_tokens.?);
    try std.testing.expectEqual(@as(i64, 50), cur.output_tokens.?);
    try std.testing.expectEqual(@as(i64, 500), cur.cache_creation_input_tokens.?);
    try std.testing.expectEqual(@as(i64, 67000), cur.cache_read_input_tokens.?);

    // Total should be 67650
    try std.testing.expectEqual(@as(i64, 67650), cur.totalTokens());

    // Verify percentage calculation: 67650 / (200000 * 0.775) = 43.6%
    const window_size: f64 = 200000.0;
    const effective_size = window_size * 0.775;
    const pct = (@as(f64, @floatFromInt(cur.totalTokens())) * 100.0) / effective_size;
    try std.testing.expectApproxEqAbs(@as(f64, 43.6), pct, 0.1);
}

test "current_usage field fallback when missing" {
    const allocator = std.testing.allocator;

    // JSON without current_usage (older Claude Code versions)
    const json_without_usage =
        \\{
        \\  "model": {
        \\    "display_name": "Opus"
        \\  },
        \\  "workspace": {
        \\    "current_dir": "/test"
        \\  },
        \\  "context_window": {
        \\    "context_window_size": 200000
        \\  },
        \\  "version": "1.0.80"
        \\}
    ;

    const parsed = try json.parseFromSlice(StatuslineInput, allocator, json_without_usage, .{
        .ignore_unknown_fields = true,
    });
    defer parsed.deinit();

    // current_usage should be null for older versions
    try std.testing.expect(parsed.value.context_window != null);
    try std.testing.expect(parsed.value.context_window.?.current_usage == null);
}

test "formatIdleSince returns false without session_id" {
    var buf: [128]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buf);
    const writer = stream.writer();

    const result_null = try formatIdleSince(writer, null);
    try std.testing.expect(!result_null);
    try std.testing.expectEqual(@as(usize, 0), stream.getWritten().len);

    const result_empty = try formatIdleSince(writer, "");
    try std.testing.expect(!result_empty);
    try std.testing.expectEqual(@as(usize, 0), stream.getWritten().len);
}

test "formatIdleSince returns false for missing file" {
    var buf: [128]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buf);
    const writer = stream.writer();

    // Nonexistent session ID -> file won't exist -> returns false
    const result = try formatIdleSince(writer, "nonexistent-session-id-12345");
    try std.testing.expect(!result);
    try std.testing.expectEqual(@as(usize, 0), stream.getWritten().len);
}
