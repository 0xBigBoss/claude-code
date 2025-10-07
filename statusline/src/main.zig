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

/// Input structure from Claude Code
const StatuslineInput = struct {
    workspace: ?struct {
        current_dir: ?[]const u8,
    } = null,
    model: ?struct {
        display_name: ?[]const u8,
    } = null,
    session_id: ?[]const u8 = null,
    transcript_path: ?[]const u8 = null,
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

    fn abbreviation(self: ModelType) []const u8 {
        return switch (self) {
            .opus => "Opus",
            .sonnet => "Sonnet",
            .haiku => "Haiku",
            .unknown => "?",
        };
    }
};

/// Context percentage with color coding
const ContextUsage = struct {
    percentage: f64,

    fn color(self: ContextUsage) []const u8 {
        if (self.percentage >= 90.0) return colors.red;
        if (self.percentage >= 70.0) return colors.orange;
        if (self.percentage >= 50.0) return colors.yellow;
        return colors.gray;
    }

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

    fn format(self: GitStatus, writer: anytype) !void {
        if (self.added > 0) try writer.print(" +{d}", .{self.added});
        if (self.modified > 0) try writer.print(" ~{d}", .{self.modified});
        if (self.deleted > 0) try writer.print(" -{d}", .{self.deleted});
        if (self.untracked > 0) try writer.print(" ?{d}", .{self.untracked});
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

/// Calculate context usage percentage from transcript
fn calculateContextUsage(allocator: Allocator, transcript_path: ?[]const u8) !ContextUsage {
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
        latest_usage = @min(100.0, (total * 100.0) / 160000.0);
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

/// Format session duration from transcript timestamps
fn formatSessionDuration(allocator: Allocator, transcript_path: ?[]const u8, writer: anytype) !bool {
    if (transcript_path == null) return false;

    const file = std.fs.cwd().openFile(transcript_path.?, .{}) catch return false;
    defer file.close();

    const content = file.readToEndAlloc(allocator, 10 * 1024 * 1024) catch return false;
    defer allocator.free(content);

    var lines = try std.ArrayList([]const u8).initCapacity(allocator, 0);
    defer lines.deinit(allocator);

    var line_iter = std.mem.splitScalar(u8, content, '\n');
    while (line_iter.next()) |line| {
        if (line.len > 0) try lines.append(allocator, line);
    }

    if (lines.items.len < 2) return false;

    const first_ts = try extractTimestamp(allocator, lines.items[0]);
    const last_ts = try findLastTimestamp(allocator, lines.items);

    if (first_ts == null or last_ts == null) return false;

    const duration_ms = (last_ts.? - first_ts.?) * 1000;
    const hours = @divTrunc(duration_ms, 1000 * 60 * 60);
    const minutes = @divTrunc(@mod(duration_ms, 1000 * 60 * 60), 1000 * 60);

    if (hours > 0) {
        try writer.print("{d}h\u{2009}{d}m", .{ hours, minutes });
    } else if (minutes > 0) {
        try writer.print("{d}m", .{minutes});
    } else {
        try writer.print("<1m", .{});
    }
    return true;
}

/// Extract timestamp from a JSON line
fn extractTimestamp(allocator: Allocator, line: []const u8) !?i64 {
    const parsed = json.parseFromSlice(json.Value, allocator, line, .{}) catch return null;
    defer parsed.deinit();

    if (parsed.value != .object) return null;
    const ts = parsed.value.object.get("timestamp") orelse return null;

    return switch (ts) {
        .integer => |i| i,
        .string => std.time.timestamp(),
        else => null,
    };
}

/// Find the last valid timestamp in lines
fn findLastTimestamp(allocator: Allocator, lines: [][]const u8) !?i64 {
    var i = lines.len;
    while (i > 0) : (i -= 1) {
        if (try extractTimestamp(allocator, lines[i - 1])) |ts| {
            return ts;
        }
    }
    return null;
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

    var short_mode = false;
    var show_pr_status = true;
    var debug_mode = false;

    for (args[1..]) |arg| {
        if (std.mem.eql(u8, arg, "--short")) {
            short_mode = true;
        } else if (std.mem.eql(u8, arg, "--skip-pr-status")) {
            show_pr_status = false;
        } else if (std.mem.eql(u8, arg, "--debug")) {
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

            try writer.print(" {s}{s}[{s}", .{ colors.reset, colors.green, branch });

            if (!git_status.isEmpty()) {
                try git_status.format(writer);
            }

            try writer.print("]{s}", .{colors.reset});
        } else {
            try writer.print("{s}", .{colors.reset});
        }
    }

    // Add model display
    if (input.model) |model| {
        if (model.display_name) |name| {
            const model_type = ModelType.fromName(name);
            const usage = try calculateContextUsage(allocator, input.transcript_path);

            try writer.print(" {s}• {s}", .{ colors.gray, usage.color() });
            try usage.format(writer);
            try writer.print("% {s}{s}", .{ colors.gray, model_type.abbreviation() });

            // Add duration if available
            if (input.transcript_path != null) {
                try writer.print(" • {s}", .{colors.light_gray});
                _ = try formatSessionDuration(allocator, input.transcript_path, writer);
                try writer.print("{s}", .{colors.reset});
            }
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

test "ModelType abbreviations" {
    try std.testing.expectEqualStrings("Opus", ModelType.opus.abbreviation());
    try std.testing.expectEqualStrings("Sonnet", ModelType.sonnet.abbreviation());
    try std.testing.expectEqualStrings("Haiku", ModelType.haiku.abbreviation());
    try std.testing.expectEqualStrings("?", ModelType.unknown.abbreviation());
}

test "ContextUsage color thresholds" {
    const low = ContextUsage{ .percentage = 30.0 };
    const medium = ContextUsage{ .percentage = 60.0 };
    const high = ContextUsage{ .percentage = 80.0 };
    const critical = ContextUsage{ .percentage = 95.0 };

    try std.testing.expectEqualStrings(colors.gray, low.color());
    try std.testing.expectEqualStrings(colors.yellow, medium.color());
    try std.testing.expectEqualStrings(colors.orange, high.color());
    try std.testing.expectEqualStrings(colors.red, critical.color());
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
