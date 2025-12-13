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
    unknown,

    fn fromName(name: []const u8) ModelType {
        if (std.mem.indexOf(u8, name, "Opus") != null) return .opus;
        if (std.mem.indexOf(u8, name, "Sonnet") != null) return .sonnet;
        if (std.mem.indexOf(u8, name, "Haiku") != null) return .haiku;
        return .unknown;
    }

    /// Emoji representation based on literal meaning
    /// Opus = grand musical work (theater), Sonnet = poem (scroll), Haiku = nature poem (leaf)
    fn emoji(self: ModelType) []const u8 {
        return switch (self) {
            .opus => "🎭",
            .sonnet => "📜",
            .haiku => "🍃",
            .unknown => "?",
        };
    }
};

/// Configuration for gauge display - designed for easy future customization
const GaugeConfig = struct {
    width: u8 = 3,
    filled_char: []const u8 = "█",
    empty_char: []const u8 = "░",
    // Future options: partial_char for finer granularity, custom thresholds, etc.
};

/// Default gauge configuration
const default_gauge_config = GaugeConfig{};

/// Context percentage with color coding and gauge display
const ContextUsage = struct {
    percentage: f64,

    fn color(self: ContextUsage) []const u8 {
        if (self.percentage >= 90.0) return colors.red;
        if (self.percentage >= 70.0) return colors.orange;
        if (self.percentage >= 50.0) return colors.yellow;
        return colors.green;
    }

    /// Calculate number of filled blocks for gauge display
    fn filledBlocks(self: ContextUsage, config: GaugeConfig) u8 {
        const width_f: f64 = @floatFromInt(config.width);
        const blocks = (self.percentage / 100.0) * width_f;
        return @min(config.width, @as(u8, @intFromFloat(@round(blocks))));
    }

    /// Format as a color-coded gauge (e.g., "██░")
    fn formatGauge(self: ContextUsage, writer: anytype, config: GaugeConfig) !void {
        const filled = self.filledBlocks(config);
        const clr = self.color();

        try writer.print("{s}", .{clr});
        for (0..config.width) |i| {
            if (i < filled) {
                try writer.print("{s}", .{config.filled_char});
            } else {
                try writer.print("{s}", .{config.empty_char});
            }
        }
        try writer.print("{s}", .{colors.reset});
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
/// NOTE: Currently broken - context_window values are cumulative session totals, not current usage
/// See: https://github.com/anthropics/claude-code/issues/13783
/// Uses modulus to find current position since tokens are cumulative across compacts
/// Effective context is 77.5% of window (22.5% reserved for autocompact buffer)
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

    const file = std.fs.cwd().openFile(transcript_path.?, .{}) catch {
        return ContextUsage{ .percentage = 0.0 };
    };
    defer file.close();

    const content = file.readToEndAlloc(allocator, 10 * 1024 * 1024) catch {
        return ContextUsage{ .percentage = 0.0 };
    };
    defer allocator.free(content);

    // Process only last 50 lines for performance
    var lines = try std.ArrayList([]const u8).initCapacity(allocator, 0);
    defer lines.deinit(allocator);

    var line_iter = std.mem.splitScalar(u8, content, '\n');
    while (line_iter.next()) |line| {
        if (line.len > 0) try lines.append(allocator, line);
    }

    const start_idx = if (lines.items.len > 50) lines.items.len - 50 else 0;
    var latest_usage: ?f64 = null;

    for (lines.items[start_idx..]) |line| {
        if (line.len == 0) continue;

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
        latest_usage = @min(100.0, (total * 100.0) / effective_size);
    }

    return ContextUsage{ .percentage = latest_usage orelse 0.0 };
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

/// Format path with intelligent shortening for statusline display
fn formatPathShort(allocator: Allocator, writer: anytype, path: []const u8) !void {
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
    
    if (segments.items.len <= 3) {
        if (has_home) try writer.print("~", .{});
        try writer.print("{s}", .{display_path});
        return;
    }
    
    if (has_home) try writer.print("~", .{});
    
    for (segments.items, 0..) |segment, i| {
        try writer.print("/", .{});
        
        if (i == segments.items.len - 1) {
            try writer.print("{s}", .{segment});
        } else if (i == 0 and segment.len <= 10) {
            try writer.print("{s}", .{segment});
        } else {
            const abbreviated = try abbreviateSegment(allocator, segment);
            defer allocator.free(abbreviated);
            try writer.print("{s}", .{abbreviated});
        }
    }
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
    try writer.print("{s}", .{colors.cyan});

    // Handle workspace directory
    const current_dir = if (input.workspace) |ws| ws.current_dir else null;
    if (current_dir == null) {
        try writer.print("~{s}", .{colors.reset});
    } else {
        try formatPathShort(allocator, writer, current_dir.?);

        // Check git status
        if (isGitRepo(allocator, current_dir.?)) {
            const branch = try getGitBranch(allocator, current_dir.?);
            defer allocator.free(branch);

            const git_status = try getGitStatus(allocator, current_dir.?);

            // Skip branch name if it matches the last path segment (avoid redundancy)
            const last_segment = getLastPathSegment(current_dir.?);
            const branch_matches_path = std.mem.eql(u8, branch, last_segment);

            try writer.print(" {s}{s}[", .{ colors.reset, colors.green });

            var has_content = false;
            if (!branch_matches_path and branch.len > 0) {
                const abbrev_branch = try abbreviateBranch(allocator, branch);
                defer allocator.free(abbrev_branch);
                try writer.print("{s}", .{abbrev_branch});
                has_content = true;
            }

            if (!git_status.isEmpty()) {
                if (has_content) try writer.print(" ", .{});
                try git_status.format(writer);
            }

            try writer.print("]{s}", .{colors.reset});
        } else {
            try writer.print("{s}", .{colors.reset});
        }
    }

    // Add model display with gauge
    if (input.model) |model| {
        if (model.display_name) |name| {
            const model_type = ModelType.fromName(name);
            const context_size = if (input.context_window) |ctx| ctx.context_window_size else null;
            const usage = try calculateContextUsage(allocator, input.transcript_path, context_size);

            // Gauge + model emoji (e.g., "██░ 🎭")
            try writer.print(" ", .{});
            try usage.formatGauge(writer, default_gauge_config);
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
    try std.testing.expectEqual(ModelType.unknown, ModelType.fromName("GPT-4"));
}

test "ModelType emoji representations" {
    try std.testing.expectEqualStrings("🎭", ModelType.opus.emoji());
    try std.testing.expectEqualStrings("📜", ModelType.sonnet.emoji());
    try std.testing.expectEqualStrings("🍃", ModelType.haiku.emoji());
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

test "ContextUsage gauge formatting" {
    const config = GaugeConfig{};

    // 0% = no blocks filled
    const empty = ContextUsage{ .percentage = 0.0 };
    try std.testing.expectEqual(@as(u8, 0), empty.filledBlocks(config));

    // 50% = 1.5 blocks, rounds to 2
    const half = ContextUsage{ .percentage = 50.0 };
    try std.testing.expectEqual(@as(u8, 2), half.filledBlocks(config));

    // 100% = 3 blocks
    const full = ContextUsage{ .percentage = 100.0 };
    try std.testing.expectEqual(@as(u8, 3), full.filledBlocks(config));

    // 17% = 0.5 blocks, rounds to 1
    const low = ContextUsage{ .percentage = 17.0 };
    try std.testing.expectEqual(@as(u8, 1), low.filledBlocks(config));

    // 83% = 2.5 blocks, rounds to 3
    const high = ContextUsage{ .percentage = 83.0 };
    try std.testing.expectEqual(@as(u8, 2), high.filledBlocks(config));
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
    
    try formatPathShort(allocator, writer, "/Users/test/0xbigboss/canton-network/canton-foundation/decentralized-canton-sync/token-standard");
    
    const result = stream.getWritten();
    try std.testing.expect(result.len < 50);
    try std.testing.expect(std.mem.endsWith(u8, result, "token-standard"));
}

test "formatPathShort with short path" {
    const allocator = std.testing.allocator;
    var buf: [256]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buf);
    const writer = stream.writer();

    try formatPathShort(allocator, writer, "/home/user/project");
    try std.testing.expectEqualStrings("/home/user/project", stream.getWritten());
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
