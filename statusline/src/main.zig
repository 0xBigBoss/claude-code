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

/// Execute a shell command and return trimmed output
fn execCommand(allocator: Allocator, command: [:0]const u8, cwd: ?[]const u8) ![]const u8 {
    const argv = [_][:0]const u8{ "sh", "-c", command };

    var child = std.process.Child.init(&argv, allocator);
    child.stdout_behavior = .Pipe;
    child.stderr_behavior = .Pipe;
    if (cwd) |dir| child.cwd = dir;

    try child.spawn();

    const stdout = child.stdout.?;
    const raw_output = try stdout.reader().readAllAlloc(allocator, 1024 * 1024);
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
    var lines = std.ArrayList([]const u8).init(allocator);
    defer lines.deinit();

    var line_iter = std.mem.splitScalar(u8, content, '\n');
    while (line_iter.next()) |line| {
        if (line.len > 0) try lines.append(line);
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

    var lines = std.ArrayList([]const u8).init(allocator);
    defer lines.deinit();

    var line_iter = std.mem.splitScalar(u8, content, '\n');
    while (line_iter.next()) |line| {
        if (line.len > 0) try lines.append(line);
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

/// Format path with home directory abbreviation (writes directly to writer)
fn formatPath(writer: anytype, path: []const u8) !void {
    const home = std.posix.getenv("HOME") orelse "";
    if (home.len > 0 and std.mem.startsWith(u8, path, home)) {
        try writer.print("~{s}", .{path[home.len..]});
    } else {
        try writer.print("{s}", .{path});
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

    const cmd = try temp_alloc.dupeZ(u8, "git branch --show-current");

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

    for (args[1..]) |arg| {
        if (std.mem.eql(u8, arg, "--short")) {
            short_mode = true;
        } else if (std.mem.eql(u8, arg, "--skip-pr-status")) {
            show_pr_status = false;
        }
    }

    // Read and parse JSON input
    const stdin = std.io.getStdIn().reader();
    const input_json = try stdin.readAllAlloc(allocator, 1024 * 1024);

    const parsed = json.parseFromSlice(StatuslineInput, allocator, input_json, .{}) catch {
        const stdout = std.io.getStdOut().writer();
        stdout.print("{s}~{s}", .{ colors.cyan, colors.reset }) catch {};
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
        try formatPath(writer, current_dir.?);

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
    const stdout = std.io.getStdOut().writer();
    stdout.print("{s}\n", .{output}) catch {};
}
