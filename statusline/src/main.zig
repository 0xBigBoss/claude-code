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

/// Statusline-segment glyphs grouped for grepability
const glyphs = struct {
    // Strategy glyphs — rl loop type indicator
    const ralph = "🔁";
    const review = "🧪";
    const research = "🔬";
    // Review sub-counter (counts confirmed-reject verdicts vs max_review_cycles)
    const counter = "🔍";
    // Verdict / in-flight state glyphs
    const in_flight = "⏳";
    const approve = "✅";
    const reject = "❌";
    // Research metric (★{best_metric_value}) with optional direction arrow
    const metric = "★";
    const arrow_up = "↑";
    const arrow_down = "↓";
    // Terminal-state prefixes — loop is winding down, not actively iterating
    const completion = "🏁"; // completion_claimed: agent claims done, awaiting verdict/user
    const blocked = "🚧"; // blocked_claimed: loop marked blocked, next Stop cleans up
    // Impl worker (rl 1.1): background `rl implement start` job, independent of loop state
    const impl = "🔨";
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

/// Get progress color with discrete thresholds (matching colors.green/yellow/red):
/// 0-50% = green, 50-80% = yellow, 80-100% = red
fn progressColor(current: u32, max: u32) []const u8 {
    if (max == 0) return colors.green;
    const pct = @min(100.0, (@as(f64, @floatFromInt(current)) / @as(f64, @floatFromInt(max))) * 100.0);

    if (pct < 50.0) {
        return colors.green;
    } else if (pct < 80.0) {
        return colors.yellow;
    } else {
        return colors.red;
    }
}

/// rl loop strategy — matches `strategy` field in .rl/state.json v3.
/// Each variant has distinct counter semantics that drive dispatch in `RalphState.format`.
const Strategy = enum {
    ralph,
    review,
    research,
    unknown,

    fn fromString(s: []const u8) Strategy {
        if (std.mem.eql(u8, s, "ralph")) return .ralph;
        if (std.mem.eql(u8, s, "review")) return .review;
        if (std.mem.eql(u8, s, "research")) return .research;
        return .unknown;
    }

    fn glyph(self: Strategy) []const u8 {
        return switch (self) {
            // Legacy fallback: state files without strategy are treated as ralph-style
            .ralph, .unknown => glyphs.ralph,
            .review => glyphs.review,
            .research => glyphs.research,
        };
    }
};

/// Direction for a research-strategy metric (minimize/maximize).
/// Parsed from the `metric_direction` field; drives the ★-arrow glyph.
const MetricDirection = enum {
    none,
    maximize,
    minimize,

    fn fromString(s: []const u8) MetricDirection {
        if (std.mem.eql(u8, s, "maximize")) return .maximize;
        if (std.mem.eql(u8, s, "minimize")) return .minimize;
        return .none;
    }
};

/// Derived verdict state for the rl segment's trailing glyph.
/// Unlike the first-cut design, this is NOT resolved at parse time — it requires
/// both the current git HEAD and optionally a job-file status check, so it's
/// resolved in `format` where those inputs are in scope.
const VerdictState = enum {
    none,
    in_flight,
    approve,
    reject,
};

/// Status of a background job as read from `.rl/jobs/{id}.json`.
/// `missing` covers "file not found", "parse failed", and "unknown status string".
const JobStatus = enum {
    missing,
    queued,
    running,
    completed,
    failed,
    cancelled,

    fn fromString(s: []const u8) JobStatus {
        if (std.mem.eql(u8, s, "queued")) return .queued;
        if (std.mem.eql(u8, s, "running")) return .running;
        if (std.mem.eql(u8, s, "completed")) return .completed;
        if (std.mem.eql(u8, s, "failed")) return .failed;
        if (std.mem.eql(u8, s, "cancelled")) return .cancelled;
        return .missing;
    }
};

/// rl loop state — projected from .rl/state.json v3 (rl 1.0+). Optional fields are
/// null when the state file omits them; defaults match rl's init values where known.
/// See ~/0xbigboss/rl/src/schemas.ts LoopStateV3Schema for the authoritative shape.
///
/// String-valued fields (`review_verdict_sha`, `review_in_flight_job_id`) are stored
/// as fixed-size stack buffers so a RalphState is entirely by-value and carries no
/// allocator lifetime. Max length 64 bytes comfortably fits a git sha (40 hex) and
/// an rl job id ("review-{ms}-{6char}" ~= 28 bytes). Overflowing strings are treated
/// as if the field were absent.
const RalphState = struct {
    active: bool = false,
    strategy: Strategy = .unknown,
    iteration: u32 = 0,
    max_iterations: u32 = 50,
    review_enabled: bool = false,
    review_count: u32 = 0,
    max_review_cycles: u32 = 10,
    // Verdict contract (rl 1.0)
    review_verdict_raw: VerdictRaw = .none,
    review_verdict_sha_buf: [64]u8 = undefined,
    review_verdict_sha_len: u8 = 0,
    review_in_flight_job_id_buf: [64]u8 = undefined,
    review_in_flight_job_id_len: u8 = 0,
    // Research fields
    best_metric_value: ?f64 = null,
    metric_direction: MetricDirection = .none,
    // Terminal-state flags
    completion_claimed: bool = false,
    blocked_claimed: bool = false,
    // Iteration audit (used for loop-age rendering)
    iteration_start_ms: ?i64 = null,
    /// Schema version from the `version` field, if present. Consumers use this for
    /// debug-mode drift detection only; rendering never branches on it.
    version: ?u32 = null,

    fn verdictSha(self: *const RalphState) ?[]const u8 {
        if (self.review_verdict_sha_len == 0) return null;
        return self.review_verdict_sha_buf[0..self.review_verdict_sha_len];
    }

    fn inFlightJobId(self: *const RalphState) ?[]const u8 {
        if (self.review_in_flight_job_id_len == 0) return null;
        return self.review_in_flight_job_id_buf[0..self.review_in_flight_job_id_len];
    }

    /// Format rl loop segment for statusline display (strategy-dispatched).
    /// - `git_head`: output of `git rev-parse HEAD`, or empty for "HEAD unknown"
    /// - `git_root`: workspace root; used to read job files for orphan detection
    /// - `allocator`: scratch allocator for path construction and job-file reads
    /// - `now_ms`: current wall-clock time in milliseconds (monotonic-ish; `std.time.milliTimestamp()`)
    /// Returns true when any output was written.
    fn format(
        self: RalphState,
        writer: anytype,
        allocator: Allocator,
        git_root: []const u8,
        git_head: []const u8,
        now_ms: i64,
    ) !bool {
        if (!self.active) return false;

        // Terminal-state prefix (REQ-SL-062): blocked wins over completion
        if (self.blocked_claimed) {
            try writer.print(" {s}", .{glyphs.blocked});
        } else if (self.completion_claimed) {
            try writer.print(" {s}", .{glyphs.completion});
        }

        // Strategy glyph always leads the counter block
        try writer.print(" {s}", .{self.strategy.glyph()});

        switch (self.strategy) {
            .ralph, .unknown => try self.formatRalphCounters(writer),
            .review => try self.formatReviewCounters(writer),
            .research => try self.formatResearchCounters(writer),
        }

        // Verdict / in-flight glyph (ralph + review only, and only when review_enabled)
        if ((self.strategy == .ralph or self.strategy == .unknown or self.strategy == .review) and self.review_enabled) {
            const verdict_state = self.resolveVerdictState(allocator, git_root, git_head);
            switch (verdict_state) {
                .none => {},
                .in_flight => try writer.print(" {s}", .{glyphs.in_flight}),
                .approve => try writer.print(" {s}", .{glyphs.approve}),
                .reject => try writer.print(" {s}", .{glyphs.reject}),
            }
        }

        // Research metric with optional direction arrow (REQ-SL-064)
        if (self.strategy == .research) {
            if (self.best_metric_value) |v| {
                const arrow: []const u8 = switch (self.metric_direction) {
                    .maximize => glyphs.arrow_up,
                    .minimize => glyphs.arrow_down,
                    .none => "",
                };
                try writer.print(" {s}{s}{d:.3}", .{ glyphs.metric, arrow, v });
            }
        }

        // Loop age from iteration_start_ms (REQ-SL-065)
        if (self.iteration_start_ms) |start_ms| {
            if (now_ms > start_ms) {
                try formatLoopAge(writer, now_ms - start_ms);
            }
        }

        return true;
    }

    /// Ralph layout: iteration/max_iterations as the primary counter, optional review counter.
    /// Rationale: `iteration` is advanced by `ralph.ts:139` on every Stop and `ralph.ts:245` on every
    /// reject, so it's the meaningful "how far through my loop am I" signal the original author intended.
    fn formatRalphCounters(self: RalphState, writer: anytype) !void {
        try writer.print(" {s}{d}/{d}{s}", .{
            progressColor(self.iteration, self.max_iterations),
            self.iteration,
            self.max_iterations,
            colors.reset,
        });
        if (self.review_enabled) {
            try writer.print(" {s} {s}{d}/{d}{s}", .{
                glyphs.counter,
                progressColor(self.review_count, self.max_review_cycles),
                self.review_count,
                self.max_review_cycles,
                colors.reset,
            });
        }
    }

    /// Review layout: review_count/max_review_cycles ONLY. The review strategy's Stop hook
    /// (~/0xbigboss/rl/src/strategies/review.ts) never touches `iteration`, so rendering it
    /// would always read 0 (or whatever init set) — permanent dead signal. Hide it.
    fn formatReviewCounters(self: RalphState, writer: anytype) !void {
        if (self.review_enabled) {
            try writer.print(" {s} {s}{d}/{d}{s}", .{
                glyphs.counter,
                progressColor(self.review_count, self.max_review_cycles),
                self.review_count,
                self.max_review_cycles,
                colors.reset,
            });
        }
    }

    /// Research layout: iteration/max_iterations counts experiments. No review counter
    /// (research loops don't gate on review). Metric and arrow render after counters in `format`.
    fn formatResearchCounters(self: RalphState, writer: anytype) !void {
        try writer.print(" {s}{d}/{d}{s}", .{
            progressColor(self.iteration, self.max_iterations),
            self.iteration,
            self.max_iterations,
            colors.reset,
        });
    }

    /// Resolve the trailing verdict glyph per REQ-SL-063. Mirrors the rl Stop hook's
    /// decision procedure so what the statusline shows matches what the hook will do next.
    ///
    /// Priority:
    ///   1. in_flight_job_id set AND job status is queued/running → .in_flight
    ///      (orphan markers where the job file is missing or terminal fall through)
    ///   2. verdict == approve AND verdict_sha matches HEAD → .approve
    ///   3. verdict == reject AND verdict_sha matches HEAD → .reject
    ///   4. otherwise → .none (stale, orphan, null, or HEAD-unknown all collapse here)
    fn resolveVerdictState(
        self: *const RalphState,
        allocator: Allocator,
        git_root: []const u8,
        git_head: []const u8,
    ) VerdictState {
        if (self.inFlightJobId()) |job_id| {
            const status = readJobStatus(allocator, git_root, job_id);
            if (status == .queued or status == .running) return .in_flight;
            // Orphan marker (missing/completed/failed/cancelled) — fall through
        }

        // Staleness check: we only honor verdicts whose sha matches current HEAD.
        // An empty git_head means `git rev-parse HEAD` failed — fail OPEN and
        // render the stored verdict anyway, since hiding an actionable signal
        // because of a git glitch is worse than showing a potentially stale one.
        const verdict_sha = self.verdictSha() orelse return .none;
        if (git_head.len > 0 and !std.mem.eql(u8, verdict_sha, git_head)) return .none;

        return switch (self.review_verdict_raw) {
            .none => .none,
            .approve => .approve,
            .reject => .reject,
        };
    }
};

/// Raw verdict string parsed from state.json. Kept separate from VerdictState because
/// the displayable state requires cross-checking sha + in-flight job status.
const VerdictRaw = enum { none, approve, reject };

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
/// If highlight_last is true, the last segment is colored green (indicates it's a branch name)
fn formatPathShort(allocator: Allocator, writer: anytype, path: []const u8, highlight_last: bool) !void {
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
        // Print all but last segment, then last segment with optional highlight
        for (segments.items, 0..) |segment, i| {
            try writer.print("/", .{});
            if (i == segments.items.len - 1 and highlight_last) {
                try writer.print("{s}{s}{s}", .{ colors.green, segment, colors.cyan });
            } else {
                try writer.print("{s}", .{segment});
            }
        }
        return;
    }

    if (has_home) try writer.print("~", .{});

    for (segments.items, 0..) |segment, i| {
        try writer.print("/", .{});

        if (i == segments.items.len - 1) {
            // Last segment: full name, optionally highlighted
            if (highlight_last) {
                try writer.print("{s}{s}{s}", .{ colors.green, segment, colors.cyan });
            } else {
                try writer.print("{s}", .{segment});
            }
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

/// Parse a YAML boolean value from a line
fn parseYamlBool(line: []const u8, key: []const u8) ?bool {
    if (!std.mem.startsWith(u8, line, key)) return null;
    const value = std.mem.trim(u8, line[key.len..], " \t");
    if (std.mem.eql(u8, value, "true")) return true;
    if (std.mem.eql(u8, value, "false")) return false;
    return null;
}

/// Parse a YAML integer value from a line
fn parseYamlInt(line: []const u8, key: []const u8) ?u32 {
    if (!std.mem.startsWith(u8, line, key)) return null;
    const value = std.mem.trim(u8, line[key.len..], " \t");
    return std.fmt.parseInt(u32, value, 10) catch null;
}

/// Copy a string slice into a fixed-size stack buffer, returning the bytes written.
/// If the source exceeds the buffer, returns 0 (treated as "absent" by the accessors).
fn copyIntoFixedBuf(dest: []u8, src: []const u8) u8 {
    if (src.len == 0 or src.len > dest.len) return 0;
    @memcpy(dest[0..src.len], src);
    return @intCast(src.len);
}

/// Parse rl loop state from JSON content string.
/// Exposed for testing. Returns default (inactive) RalphState if parsing fails.
/// The returned state is entirely by-value — all string fields are copied into
/// stack buffers on the struct, so the result is safe to use after the allocator
/// is freed.
fn parseRalphStateFromContent(allocator: Allocator, content: []const u8) RalphState {
    var state = RalphState{};

    // Mirror of .rl/state.json v3. See ~/0xbigboss/rl/src/schemas.ts LoopStateV3Schema.
    // All fields optional so unknown/absent keys degrade gracefully (I-6).
    const JsonState = struct {
        version: ?u32 = null,
        strategy: ?[]const u8 = null,
        active: ?bool = null,
        iteration: ?u32 = null,
        max_iterations: ?u32 = null,
        review_enabled: ?bool = null,
        review_count: ?u32 = null,
        max_review_cycles: ?u32 = null,
        review_verdict: ?[]const u8 = null,
        review_verdict_sha: ?[]const u8 = null,
        review_in_flight_job_id: ?[]const u8 = null,
        best_metric_value: ?f64 = null,
        metric_direction: ?[]const u8 = null,
        completion_claimed: ?bool = null,
        blocked_claimed: ?bool = null,
        iteration_start_ms: ?i64 = null,
    };

    const parsed = std.json.parseFromSlice(JsonState, allocator, content, .{
        .ignore_unknown_fields = true,
    }) catch return state;
    defer parsed.deinit();

    const v = parsed.value;
    if (v.version) |ver| state.version = ver;
    if (v.active) |a| state.active = a;
    if (v.iteration) |i| state.iteration = i;
    if (v.max_iterations) |m| state.max_iterations = m;
    if (v.review_enabled) |r| state.review_enabled = r;
    if (v.review_count) |r| state.review_count = r;
    if (v.max_review_cycles) |m| state.max_review_cycles = m;
    if (v.best_metric_value) |b| state.best_metric_value = b;
    if (v.completion_claimed) |c| state.completion_claimed = c;
    if (v.blocked_claimed) |b| state.blocked_claimed = b;
    if (v.iteration_start_ms) |ms| state.iteration_start_ms = ms;
    if (v.strategy) |s| state.strategy = Strategy.fromString(s);
    if (v.metric_direction) |d| state.metric_direction = MetricDirection.fromString(d);

    if (v.review_verdict_sha) |sha| {
        state.review_verdict_sha_len = copyIntoFixedBuf(&state.review_verdict_sha_buf, sha);
    }
    if (v.review_in_flight_job_id) |id| {
        state.review_in_flight_job_id_len = copyIntoFixedBuf(&state.review_in_flight_job_id_buf, id);
    }
    if (v.review_verdict) |verdict| {
        if (std.mem.eql(u8, verdict, "approve")) {
            state.review_verdict_raw = .approve;
        } else if (std.mem.eql(u8, verdict, "reject")) {
            state.review_verdict_raw = .reject;
        }
    }

    return state;
}

/// Parse rl loop state from .rl/state.json at git root.
/// Returns default (inactive) state on any I/O or parse failure.
/// The returned RalphState is by-value and safe to use independently of the allocator.
fn parseRalphState(allocator: Allocator, git_root: []const u8) RalphState {
    const path = std.fmt.allocPrint(allocator, "{s}/.rl/state.json", .{git_root}) catch return RalphState{};
    defer allocator.free(path);

    // 4 KiB cap: observed v3 state.json files are ~600 bytes; 4 KiB gives >6x headroom.
    const file = std.fs.cwd().openFile(path, .{}) catch return RalphState{};
    defer file.close();

    var buf: [4096]u8 = undefined;
    const bytes_read = file.read(&buf) catch return RalphState{};
    if (bytes_read == 0) return RalphState{};

    return parseRalphStateFromContent(allocator, buf[0..bytes_read]);
}

/// Read a background job's status field from `.rl/jobs/{job_id}.json`.
/// Returns `.missing` on any failure (file not found, parse error, unexpected string,
/// oversize file). Used for orphan detection on `review_in_flight_job_id`.
/// Cost: one allocPrint, one openFile, one 4 KiB read, one JSON parse.
fn readJobStatus(allocator: Allocator, git_root: []const u8, job_id: []const u8) JobStatus {
    const path = std.fmt.allocPrint(allocator, "{s}/.rl/jobs/{s}.json", .{ git_root, job_id }) catch return .missing;
    defer allocator.free(path);

    const file = std.fs.cwd().openFile(path, .{}) catch return .missing;
    defer file.close();

    var buf: [4096]u8 = undefined;
    const bytes_read = file.read(&buf) catch return .missing;
    if (bytes_read == 0) return .missing;

    return parseJobStatusFromContent(allocator, buf[0..bytes_read]);
}

/// Exposed for testing. Parses the `status` field from a job JSON blob.
fn parseJobStatusFromContent(allocator: Allocator, content: []const u8) JobStatus {
    const JobFile = struct { status: ?[]const u8 = null };
    const parsed = std.json.parseFromSlice(JobFile, allocator, content, .{
        .ignore_unknown_fields = true,
    }) catch return .missing;
    defer parsed.deinit();

    const status_str = parsed.value.status orelse return .missing;
    return JobStatus.fromString(status_str);
}

/// Run `git rev-parse HEAD` in `dir`. Returns empty string on any failure.
/// Caller receives an allocator-owned slice; free with `allocator.free` or rely on arena.
/// Callers treat empty-string as "HEAD unknown" — the verdict staleness check fails open.
fn getGitHead(allocator: Allocator, dir: []const u8) []const u8 {
    var buf: [256]u8 = undefined;
    var fba = std.heap.FixedBufferAllocator.init(&buf);
    const temp_alloc = fba.allocator();
    const cmd = temp_alloc.dupeZ(u8, "git rev-parse HEAD") catch return "";
    return execCommand(allocator, cmd, dir) catch "";
}

/// Scan `.rl/jobs/` for a currently-running `rl implement` worker. Returns true
/// as soon as any file named `impl-*.json` reports status `queued` or `running`.
///
/// Implementation independent of state.json: `rl implement start` spawns a worker
/// even when no rl loop is initialized, so the impl indicator must render on job
/// presence alone. Iteration is bounded (max 100 entries) to keep the hot path
/// predictable for long-running workspaces with many historical jobs.
///
/// Fail-closed on any filesystem or parse error: treat anything unexpected as
/// "no running impl worker" rather than surfacing a misleading glyph.
fn hasRunningImplJob(allocator: Allocator, git_root: []const u8) bool {
    const dir_path = std.fmt.allocPrint(allocator, "{s}/.rl/jobs", .{git_root}) catch return false;
    defer allocator.free(dir_path);

    var dir = std.fs.cwd().openDir(dir_path, .{ .iterate = true }) catch return false;
    defer dir.close();

    var iter = dir.iterate();
    var scanned: u32 = 0;
    while (iter.next() catch null) |entry| {
        if (scanned >= 100) break; // bounded scan
        scanned += 1;

        if (entry.kind != .file) continue;
        if (!std.mem.startsWith(u8, entry.name, "impl-")) continue;
        if (!std.mem.endsWith(u8, entry.name, ".json")) continue;

        const file = dir.openFile(entry.name, .{}) catch continue;
        defer file.close();

        var buf: [4096]u8 = undefined;
        const bytes_read = file.read(&buf) catch continue;
        if (bytes_read == 0) continue;

        const status = parseJobStatusFromContent(allocator, buf[0..bytes_read]);
        if (status == .queued or status == .running) return true;
    }
    return false;
}

/// Emit the impl-worker indicator (` 🔨`) when at least one `rl implement` worker
/// is running in this workspace. Returns true if anything was written.
fn formatImplWorker(writer: anytype, allocator: Allocator, git_root: []const u8) !bool {
    if (!hasRunningImplJob(allocator, git_root)) return false;
    try writer.print(" {s}", .{glyphs.impl});
    return true;
}

/// Format a loop age (in ms) as a compact ` +{N}{s|m|h|d}` string with color grading.
/// Color thresholds: green <1h, yellow <4h, red ≥4h.
fn formatLoopAge(writer: anytype, age_ms: i64) !void {
    if (age_ms < 0) return;
    const total_s: u64 = @intCast(@divTrunc(age_ms, 1000));

    const color: []const u8 = blk: {
        if (total_s < 60 * 60) break :blk colors.green;
        if (total_s < 4 * 60 * 60) break :blk colors.yellow;
        break :blk colors.red;
    };

    try writer.print(" {s}+", .{color});

    if (total_s < 60) {
        try writer.print("{d}s", .{total_s});
    } else if (total_s < 60 * 60) {
        try writer.print("{d}m", .{total_s / 60});
    } else if (total_s < 24 * 60 * 60) {
        const hours = total_s / 3600;
        const minutes = (total_s % 3600) / 60;
        if (minutes == 0) {
            try writer.print("{d}h", .{hours});
        } else {
            try writer.print("{d}h{d}m", .{ hours, minutes });
        }
    } else {
        try writer.print("{d}d", .{total_s / (24 * 60 * 60)});
    }

    try writer.print("{s}", .{colors.reset});
}

/// Append a single timestamped line to /tmp/statusline-debug.log.
/// Best-effort: all failure modes are swallowed so debug logging never affects rendering.
fn appendDebugLog(comptime fmt: []const u8, args: anytype) void {
    const file = std.fs.cwd().createFile("/tmp/statusline-debug.log", .{ .truncate = false }) catch return;
    defer file.close();
    file.seekFromEnd(0) catch return;
    var file_buffer: [512]u8 = undefined;
    var file_writer = file.writerStreaming(&file_buffer);
    const writer = &file_writer.interface;
    const timestamp = std.time.timestamp();
    writer.print("[{d}] ", .{timestamp}) catch return;
    writer.print(fmt ++ "\n", args) catch return;
    writer.flush() catch return;
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
        // Check git status first to determine if we should highlight the last path segment
        const is_git = isGitRepo(allocator, current_dir.?);
        var branch_matches_path = false;
        var branch: []const u8 = "";
        var owns_branch = false;

        if (is_git) {
            branch = try getGitBranch(allocator, current_dir.?);
            owns_branch = true;
            const last_segment = getLastPathSegment(current_dir.?);
            branch_matches_path = std.mem.eql(u8, branch, last_segment);
        }
        defer if (owns_branch) allocator.free(branch);

        // Format path, highlighting last segment green if it matches branch name
        try formatPathShort(allocator, writer, current_dir.?, branch_matches_path);

        // Handle git status display
        if (is_git) {
            const git_status = try getGitStatus(allocator, current_dir.?);

            // Determine what to show in brackets
            const show_branch = !branch_matches_path and branch.len > 0;
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

                const ralph_state = parseRalphState(allocator, git_root);

                // Debug-mode drift detector (REQ-SL-038): warn when the state file
                // carries a schema version we don't know about. Render still proceeds
                // with legacy defaults — never fail a render on drift.
                if (debug_mode) {
                    if (ralph_state.version) |v| {
                        if (v != 3) {
                            appendDebugLog("rl state schema version {d} != 3 — rendering with legacy defaults", .{v});
                        }
                    }
                }

                // git HEAD for verdict staleness check (REQ-SL-067). Empty on failure → fail-open.
                const git_head = getGitHead(allocator, current_dir.?);
                const now_ms = std.time.milliTimestamp();
                _ = try ralph_state.format(writer, allocator, git_root, git_head, now_ms);

                // Impl-worker indicator (REQ-SL-070). Orthogonal to the rl segment —
                // `rl implement start` spawns a worker even when no loop is active,
                // so this check happens regardless of ralph_state.active.
                _ = try formatImplWorker(writer, allocator, git_root);
            }
        }
    }

    // zmx session indicator
    if (std.posix.getenv("ZMX_SESSION")) |zmx_session| {
        if (zmx_session.len > 0) {
            try writer.print(" {s}zmx:{s}{s}", .{ colors.gray, zmx_session, colors.reset });
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

    try formatPathShort(allocator, writer, "/Users/test/0xbigboss/canton-network/canton-foundation/decentralized-canton-sync/token-standard", false);

    const result = stream.getWritten();
    try std.testing.expect(result.len < 50);
    try std.testing.expect(std.mem.indexOf(u8, result, "token-standard") != null);
}

test "formatPathShort with short path" {
    const allocator = std.testing.allocator;
    var buf: [256]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buf);
    const writer = stream.writer();

    try formatPathShort(allocator, writer, "/home/user/project", false);
    try std.testing.expectEqualStrings("/home/user/project", stream.getWritten());
}

test "formatPathShort with highlighted last segment" {
    const allocator = std.testing.allocator;
    var buf: [256]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buf);
    const writer = stream.writer();

    try formatPathShort(allocator, writer, "/home/user/feature-branch", true);
    const result = stream.getWritten();
    // Should contain green color code before "feature-branch"
    try std.testing.expect(std.mem.indexOf(u8, result, colors.green) != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "feature-branch") != null);
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

test "RalphState default values" {
    const state = RalphState{};
    try std.testing.expect(!state.active);
    try std.testing.expectEqual(@as(u32, 0), state.iteration);
    try std.testing.expectEqual(@as(u32, 50), state.max_iterations);
    try std.testing.expect(!state.review_enabled);
    try std.testing.expectEqual(@as(u32, 0), state.review_count);
    try std.testing.expectEqual(@as(u32, 10), state.max_review_cycles);
}

test "RalphState progressColor thresholds" {
    // 0% = green (0-50% range)
    try std.testing.expectEqualStrings(colors.green, progressColor(0, 100));

    // 49% = still green (0-50% range)
    try std.testing.expectEqualStrings(colors.green, progressColor(49, 100));

    // 50% = yellow (50-80% range)
    try std.testing.expectEqualStrings(colors.yellow, progressColor(50, 100));

    // 79% = still yellow (50-80% range)
    try std.testing.expectEqualStrings(colors.yellow, progressColor(79, 100));

    // 80% = red (80-100% range)
    try std.testing.expectEqualStrings(colors.red, progressColor(80, 100));

    // 100% = red (80-100% range)
    try std.testing.expectEqualStrings(colors.red, progressColor(100, 100));

    // Edge case: max = 0 returns green
    try std.testing.expectEqualStrings(colors.green, progressColor(0, 0));
}

// --- rl segment rendering tests ---
//
// Shared test harness: renderRalphState wraps format() with a stack buffer so test
// cases stay tight. A non-git-repo path and empty git_head are used so the
// orphan-detection + staleness-check code paths run without touching the filesystem.

fn renderRalphState(state: *const RalphState, buf: []u8, now_ms: i64) ![]const u8 {
    var stream = std.io.fixedBufferStream(buf);
    const writer = stream.writer();
    _ = try state.*.format(writer, std.testing.allocator, "/nonexistent-root", "", now_ms);
    return stream.getWritten();
}

test "RalphState format inactive returns false and writes nothing" {
    const state = RalphState{ .active = false };
    var stream_buf: [256]u8 = undefined;
    var stream = std.io.fixedBufferStream(&stream_buf);
    const writer = stream.writer();
    const wrote = try state.format(writer, std.testing.allocator, "/nonexistent", "", 0);
    try std.testing.expect(!wrote);
    try std.testing.expectEqual(@as(usize, 0), stream.getWritten().len);
}

test "Strategy.fromString maps known values" {
    try std.testing.expectEqual(Strategy.ralph, Strategy.fromString("ralph"));
    try std.testing.expectEqual(Strategy.review, Strategy.fromString("review"));
    try std.testing.expectEqual(Strategy.research, Strategy.fromString("research"));
    try std.testing.expectEqual(Strategy.unknown, Strategy.fromString("nonsense"));
    try std.testing.expectEqual(Strategy.unknown, Strategy.fromString(""));
}

test "Strategy glyph mapping" {
    try std.testing.expectEqualStrings(glyphs.ralph, Strategy.ralph.glyph());
    try std.testing.expectEqualStrings(glyphs.review, Strategy.review.glyph());
    try std.testing.expectEqualStrings(glyphs.research, Strategy.research.glyph());
    try std.testing.expectEqualStrings(glyphs.ralph, Strategy.unknown.glyph()); // legacy fallback
}

test "JobStatus.fromString maps known values" {
    try std.testing.expectEqual(JobStatus.queued, JobStatus.fromString("queued"));
    try std.testing.expectEqual(JobStatus.running, JobStatus.fromString("running"));
    try std.testing.expectEqual(JobStatus.completed, JobStatus.fromString("completed"));
    try std.testing.expectEqual(JobStatus.failed, JobStatus.fromString("failed"));
    try std.testing.expectEqual(JobStatus.cancelled, JobStatus.fromString("cancelled"));
    try std.testing.expectEqual(JobStatus.missing, JobStatus.fromString("weird"));
    try std.testing.expectEqual(JobStatus.missing, JobStatus.fromString(""));
}

test "parseJobStatusFromContent with running job" {
    const content =
        \\{"id":"review-123-abc","kind":"review","status":"running","pid":1234}
    ;
    try std.testing.expectEqual(JobStatus.running, parseJobStatusFromContent(std.testing.allocator, content));
}

test "parseJobStatusFromContent with completed job" {
    const content = "{\"status\":\"completed\"}";
    try std.testing.expectEqual(JobStatus.completed, parseJobStatusFromContent(std.testing.allocator, content));
}

test "parseJobStatusFromContent with missing status field" {
    const content = "{\"id\":\"review-123\",\"kind\":\"review\"}";
    try std.testing.expectEqual(JobStatus.missing, parseJobStatusFromContent(std.testing.allocator, content));
}

test "parseJobStatusFromContent with garbage" {
    try std.testing.expectEqual(JobStatus.missing, parseJobStatusFromContent(std.testing.allocator, "not json"));
    try std.testing.expectEqual(JobStatus.missing, parseJobStatusFromContent(std.testing.allocator, ""));
}

test "RalphState ralph iterate branch (ralph.ts:152-160)" {
    // Matches ralph.ts:152 stateUpdates: { iteration: nextIteration, completion_claimed: false }
    var state = RalphState{
        .active = true,
        .strategy = .ralph,
        .iteration = 3,
        .max_iterations = 50,
        .review_enabled = true,
        .review_count = 0,
        .max_review_cycles = 10,
    };
    var buf: [256]u8 = undefined;
    const output = try renderRalphState(&state, &buf, 0);
    try std.testing.expect(std.mem.indexOf(u8, output, glyphs.ralph) != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "3/50") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, glyphs.counter) != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "0/10") != null);
    // No verdict glyph — fresh iterate has no verdict yet
    try std.testing.expect(std.mem.indexOf(u8, output, glyphs.approve) == null);
    try std.testing.expect(std.mem.indexOf(u8, output, glyphs.reject) == null);
}

test "RalphState ralph without review_enabled hides review counter" {
    var state = RalphState{
        .active = true,
        .strategy = .ralph,
        .iteration = 5,
        .max_iterations = 30,
        .review_enabled = false,
    };
    var buf: [256]u8 = undefined;
    const output = try renderRalphState(&state, &buf, 0);
    try std.testing.expect(std.mem.indexOf(u8, output, glyphs.ralph) != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "5/30") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, glyphs.counter) == null);
}

test "RalphState ralph fresh approve verdict (ralph.ts:218-223)" {
    var state = RalphState{
        .active = true,
        .strategy = .ralph,
        .iteration = 5,
        .max_iterations = 30,
        .review_enabled = true,
        .review_count = 1,
        .max_review_cycles = 10,
        .review_verdict_raw = .approve,
        .completion_claimed = true, // ralph.ts branch 4b runs only after completion claim
    };
    state.review_verdict_sha_len = copyIntoFixedBuf(&state.review_verdict_sha_buf, "deadbeef");

    // Using git_head = "deadbeef" so staleness check passes. We can't go through
    // renderRalphState since it hardcodes empty git_head; call format directly.
    var stream_buf: [256]u8 = undefined;
    var stream = std.io.fixedBufferStream(&stream_buf);
    _ = try state.format(stream.writer(), std.testing.allocator, "/nonexistent", "deadbeef", 0);
    const output = stream.getWritten();

    // Completion prefix + strategy glyph + counters + verdict glyph
    try std.testing.expect(std.mem.indexOf(u8, output, glyphs.completion) != null);
    try std.testing.expect(std.mem.indexOf(u8, output, glyphs.ralph) != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "5/30") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "1/10") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, glyphs.approve) != null);
}

test "RalphState ralph reject-iterate branch (ralph.ts:252-265)" {
    // ralph.ts reject branch bumps iteration++, review_count++, and CLEARS the verdict
    // fields. So the statusline should show incremented counters and NO verdict glyph.
    var state = RalphState{
        .active = true,
        .strategy = .ralph,
        .iteration = 6, // was 5, now 6
        .max_iterations = 30,
        .review_enabled = true,
        .review_count = 2, // was 1, now 2
        .max_review_cycles = 10,
        .review_verdict_raw = .none, // cleared by worker
    };
    // review_verdict_sha also cleared
    var buf: [256]u8 = undefined;
    const output = try renderRalphState(&state, &buf, 0);
    try std.testing.expect(std.mem.indexOf(u8, output, "6/30") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "2/10") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, glyphs.reject) == null);
    try std.testing.expect(std.mem.indexOf(u8, output, glyphs.approve) == null);
}

test "RalphState review strategy layout omits iteration counter" {
    // review.ts never mutates state.iteration — displaying it would be misleading.
    var state = RalphState{
        .active = true,
        .strategy = .review,
        .iteration = 0, // permanently 0 in review strategy
        .max_iterations = 30,
        .review_enabled = true,
        .review_count = 3,
        .max_review_cycles = 30,
    };
    var buf: [256]u8 = undefined;
    const output = try renderRalphState(&state, &buf, 0);
    try std.testing.expect(std.mem.indexOf(u8, output, glyphs.review) != null);
    try std.testing.expect(std.mem.indexOf(u8, output, glyphs.counter) != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "3/30") != null);
    // Must NOT contain "0/30" (the iteration counter)
    // Note: review_count is "3/30", max_review_cycles matches max_iterations here — so the
    // only way "0/30" could appear is from a rendered iteration counter.
    try std.testing.expect(std.mem.indexOf(u8, output, "0/30") == null);
}

test "RalphState review queueing-review branch (review.ts:162-173)" {
    // review.ts enqueue branch sets review_in_flight_job_id but does NOT clear the
    // prior verdict. The statusline's in-flight check (via readJobStatus) would try
    // to open a job file that doesn't exist in this test; the orphan path returns
    // `missing` and the staleness check then fails — so no verdict glyph should render.
    var state = RalphState{
        .active = true,
        .strategy = .review,
        .review_enabled = true,
        .review_count = 1,
        .max_review_cycles = 30,
        .review_verdict_raw = .reject, // prior round's reject
    };
    state.review_verdict_sha_len = copyIntoFixedBuf(&state.review_verdict_sha_buf, "abc12345");
    state.review_in_flight_job_id_len = copyIntoFixedBuf(&state.review_in_flight_job_id_buf, "review-123-xyz");
    // git_head matches verdict_sha. The orphan check runs first: the job file under
    // /nonexistent-root/.rl/jobs/ doesn't exist → readJobStatus returns .missing →
    // in_flight branch falls through → staleness check passes → render ❌.
    var stream_buf: [256]u8 = undefined;
    var stream = std.io.fixedBufferStream(&stream_buf);
    _ = try state.format(stream.writer(), std.testing.allocator, "/nonexistent-root", "abc12345", 0);
    const output = stream.getWritten();
    try std.testing.expect(std.mem.indexOf(u8, output, glyphs.reject) != null);
    try std.testing.expect(std.mem.indexOf(u8, output, glyphs.in_flight) == null);
}

test "RalphState review reject-iterate clears verdict (review.ts:148-155)" {
    // After a confirmed reject, the rl hook writes review_count++ AND clears the verdict
    // fields. Next render should show no verdict glyph.
    var state = RalphState{
        .active = true,
        .strategy = .review,
        .review_enabled = true,
        .review_count = 2,
        .max_review_cycles = 30,
        .review_verdict_raw = .none,
    };
    var buf: [256]u8 = undefined;
    const output = try renderRalphState(&state, &buf, 0);
    try std.testing.expect(std.mem.indexOf(u8, output, "2/30") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, glyphs.reject) == null);
    try std.testing.expect(std.mem.indexOf(u8, output, glyphs.approve) == null);
}

test "RalphState review fresh approve with matching HEAD" {
    var state = RalphState{
        .active = true,
        .strategy = .review,
        .review_enabled = true,
        .review_count = 0,
        .max_review_cycles = 30,
        .review_verdict_raw = .approve,
    };
    state.review_verdict_sha_len = copyIntoFixedBuf(&state.review_verdict_sha_buf, "cafebabe");
    var stream_buf: [256]u8 = undefined;
    var stream = std.io.fixedBufferStream(&stream_buf);
    _ = try state.format(stream.writer(), std.testing.allocator, "/nonexistent-root", "cafebabe", 0);
    const output = stream.getWritten();
    try std.testing.expect(std.mem.indexOf(u8, output, glyphs.approve) != null);
}

test "RalphState verdict suppressed when HEAD drifts from verdict_sha (staleness)" {
    var state = RalphState{
        .active = true,
        .strategy = .review,
        .review_enabled = true,
        .review_count = 0,
        .max_review_cycles = 30,
        .review_verdict_raw = .reject,
    };
    state.review_verdict_sha_len = copyIntoFixedBuf(&state.review_verdict_sha_buf, "oldsha1234");
    var stream_buf: [256]u8 = undefined;
    var stream = std.io.fixedBufferStream(&stream_buf);
    // git_head != verdict_sha → stale → suppress verdict glyph
    _ = try state.format(stream.writer(), std.testing.allocator, "/nonexistent-root", "newsha5678", 0);
    const output = stream.getWritten();
    try std.testing.expect(std.mem.indexOf(u8, output, glyphs.reject) == null);
    try std.testing.expect(std.mem.indexOf(u8, output, glyphs.approve) == null);
}

test "RalphState verdict renders when git_head is empty (fail-open on unknown HEAD)" {
    var state = RalphState{
        .active = true,
        .strategy = .review,
        .review_enabled = true,
        .review_verdict_raw = .approve,
    };
    state.review_verdict_sha_len = copyIntoFixedBuf(&state.review_verdict_sha_buf, "somesha");
    var buf: [256]u8 = undefined;
    // renderRalphState passes empty git_head — fail-open means verdict still renders
    const output = try renderRalphState(&state, &buf, 0);
    try std.testing.expect(std.mem.indexOf(u8, output, glyphs.approve) != null);
}

test "RalphState in-flight with orphan job file falls through to verdict" {
    // review_in_flight_job_id set but the job file doesn't exist → orphan → fall through
    // to verdict check. Matching sha → render verdict glyph.
    var state = RalphState{
        .active = true,
        .strategy = .review,
        .review_enabled = true,
        .review_verdict_raw = .approve,
    };
    state.review_verdict_sha_len = copyIntoFixedBuf(&state.review_verdict_sha_buf, "headsha");
    state.review_in_flight_job_id_len = copyIntoFixedBuf(&state.review_in_flight_job_id_buf, "review-orphan-xx");
    var stream_buf: [256]u8 = undefined;
    var stream = std.io.fixedBufferStream(&stream_buf);
    _ = try state.format(stream.writer(), std.testing.allocator, "/nonexistent-root", "headsha", 0);
    const output = stream.getWritten();
    // Orphan → fall through → staleness passes → ✅ renders
    try std.testing.expect(std.mem.indexOf(u8, output, glyphs.approve) != null);
    try std.testing.expect(std.mem.indexOf(u8, output, glyphs.in_flight) == null);
}

test "RalphState terminal-state prefix: blocked_claimed" {
    var state = RalphState{
        .active = true,
        .strategy = .review,
        .review_enabled = true,
        .review_count = 0,
        .max_review_cycles = 30,
        .blocked_claimed = true,
    };
    var buf: [256]u8 = undefined;
    const output = try renderRalphState(&state, &buf, 0);
    try std.testing.expect(std.mem.indexOf(u8, output, glyphs.blocked) != null);
    try std.testing.expect(std.mem.indexOf(u8, output, glyphs.completion) == null);
}

test "RalphState terminal-state prefix: completion_claimed" {
    var state = RalphState{
        .active = true,
        .strategy = .ralph,
        .iteration = 5,
        .max_iterations = 30,
        .completion_claimed = true,
    };
    var buf: [256]u8 = undefined;
    const output = try renderRalphState(&state, &buf, 0);
    try std.testing.expect(std.mem.indexOf(u8, output, glyphs.completion) != null);
    try std.testing.expect(std.mem.indexOf(u8, output, glyphs.blocked) == null);
}

test "RalphState terminal-state prefix: blocked beats completion" {
    var state = RalphState{
        .active = true,
        .strategy = .review,
        .review_enabled = true,
        .completion_claimed = true,
        .blocked_claimed = true,
    };
    var buf: [256]u8 = undefined;
    const output = try renderRalphState(&state, &buf, 0);
    try std.testing.expect(std.mem.indexOf(u8, output, glyphs.blocked) != null);
    try std.testing.expect(std.mem.indexOf(u8, output, glyphs.completion) == null);
}

test "RalphState research strategy without metric (research.ts:125-135)" {
    var state = RalphState{
        .active = true,
        .strategy = .research,
        .iteration = 5,
        .max_iterations = 30,
        // research ignores review fields even if set
        .review_enabled = true,
        .review_count = 3,
        .max_review_cycles = 10,
        .review_verdict_raw = .approve,
    };
    var buf: [256]u8 = undefined;
    const output = try renderRalphState(&state, &buf, 0);
    try std.testing.expect(std.mem.indexOf(u8, output, glyphs.research) != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "5/30") != null);
    // Research hides review counter, verdict glyphs, and (without metric) the star
    try std.testing.expect(std.mem.indexOf(u8, output, glyphs.counter) == null);
    try std.testing.expect(std.mem.indexOf(u8, output, glyphs.approve) == null);
    try std.testing.expect(std.mem.indexOf(u8, output, glyphs.metric) == null);
}

test "RalphState research with maximize metric renders up-arrow" {
    var state = RalphState{
        .active = true,
        .strategy = .research,
        .iteration = 12,
        .max_iterations = 30,
        .best_metric_value = 0.823,
        .metric_direction = .maximize,
    };
    var buf: [256]u8 = undefined;
    const output = try renderRalphState(&state, &buf, 0);
    try std.testing.expect(std.mem.indexOf(u8, output, glyphs.research) != null);
    try std.testing.expect(std.mem.indexOf(u8, output, glyphs.metric) != null);
    try std.testing.expect(std.mem.indexOf(u8, output, glyphs.arrow_up) != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "0.823") != null);
}

test "RalphState research with minimize metric renders down-arrow" {
    var state = RalphState{
        .active = true,
        .strategy = .research,
        .iteration = 8,
        .max_iterations = 30,
        .best_metric_value = 0.045,
        .metric_direction = .minimize,
    };
    var buf: [256]u8 = undefined;
    const output = try renderRalphState(&state, &buf, 0);
    try std.testing.expect(std.mem.indexOf(u8, output, glyphs.arrow_down) != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "0.045") != null);
}

test "RalphState research with unknown direction omits arrow" {
    var state = RalphState{
        .active = true,
        .strategy = .research,
        .best_metric_value = 1.5,
        .metric_direction = .none,
    };
    var buf: [256]u8 = undefined;
    const output = try renderRalphState(&state, &buf, 0);
    try std.testing.expect(std.mem.indexOf(u8, output, glyphs.metric) != null);
    try std.testing.expect(std.mem.indexOf(u8, output, glyphs.arrow_up) == null);
    try std.testing.expect(std.mem.indexOf(u8, output, glyphs.arrow_down) == null);
    try std.testing.expect(std.mem.indexOf(u8, output, "1.500") != null);
}

test "RalphState loop age: seconds" {
    var state = RalphState{
        .active = true,
        .strategy = .ralph,
        .iteration = 1,
        .max_iterations = 30,
        .iteration_start_ms = 1000,
    };
    var buf: [256]u8 = undefined;
    const output = try renderRalphState(&state, &buf, 31000); // 30s later
    try std.testing.expect(std.mem.indexOf(u8, output, "+30s") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, colors.green) != null);
}

test "RalphState loop age: minutes in green range" {
    var state = RalphState{
        .active = true,
        .strategy = .ralph,
        .iteration_start_ms = 0,
    };
    var buf: [256]u8 = undefined;
    const output = try renderRalphState(&state, &buf, 45 * 60 * 1000); // 45m
    try std.testing.expect(std.mem.indexOf(u8, output, "+45m") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, colors.green) != null);
}

test "RalphState loop age: hours in yellow range" {
    var state = RalphState{
        .active = true,
        .strategy = .ralph,
        .iteration_start_ms = 0,
    };
    var buf: [256]u8 = undefined;
    const output = try renderRalphState(&state, &buf, 2 * 60 * 60 * 1000 + 15 * 60 * 1000); // 2h15m
    try std.testing.expect(std.mem.indexOf(u8, output, "+2h15m") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, colors.yellow) != null);
}

test "RalphState loop age: hours with zero-minute suffix" {
    var state = RalphState{
        .active = true,
        .strategy = .ralph,
        .iteration_start_ms = 0,
    };
    var buf: [256]u8 = undefined;
    const output = try renderRalphState(&state, &buf, 3 * 60 * 60 * 1000); // exactly 3h
    try std.testing.expect(std.mem.indexOf(u8, output, "+3h") != null);
    // Should NOT contain "+3h0m"
    try std.testing.expect(std.mem.indexOf(u8, output, "+3h0m") == null);
}

test "RalphState loop age: days in red range" {
    var state = RalphState{
        .active = true,
        .strategy = .ralph,
        .iteration_start_ms = 0,
    };
    var buf: [256]u8 = undefined;
    const output = try renderRalphState(&state, &buf, 3 * 24 * 60 * 60 * 1000); // 3d
    try std.testing.expect(std.mem.indexOf(u8, output, "+3d") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, colors.red) != null);
}

test "RalphState loop age: absent when iteration_start_ms is null" {
    var state = RalphState{
        .active = true,
        .strategy = .ralph,
        .iteration_start_ms = null,
    };
    var buf: [256]u8 = undefined;
    const output = try renderRalphState(&state, &buf, 1_000_000);
    // No "+" prefix followed by digit/h/m/s/d
    try std.testing.expect(std.mem.indexOf(u8, output, "+") == null);
}

test "RalphState loop age: absent when now_ms <= iteration_start_ms" {
    // Clock skew edge case — don't render a negative age.
    var state = RalphState{
        .active = true,
        .strategy = .ralph,
        .iteration_start_ms = 5000,
    };
    var buf: [256]u8 = undefined;
    const output = try renderRalphState(&state, &buf, 3000);
    try std.testing.expect(std.mem.indexOf(u8, output, "+") == null);
}

test "copyIntoFixedBuf overflow returns zero" {
    var buf: [8]u8 = undefined;
    try std.testing.expectEqual(@as(u8, 0), copyIntoFixedBuf(&buf, "this_is_longer_than_eight"));
    try std.testing.expectEqual(@as(u8, 0), copyIntoFixedBuf(&buf, ""));
    try std.testing.expectEqual(@as(u8, 3), copyIntoFixedBuf(&buf, "abc"));
    try std.testing.expectEqualStrings("abc", buf[0..3]);
}

test "RalphState accessors return null for empty buffers" {
    const state = RalphState{};
    try std.testing.expect(state.verdictSha() == null);
    try std.testing.expect(state.inFlightJobId() == null);
}

// --- Impl-worker segment tests ---
//
// These exercise the filesystem-aware helper by constructing real temp directories
// with fake job files. Fixture layout: tmpdir/.rl/jobs/<name>.json

fn makeImplFixture(root: std.fs.Dir, subdir: []const u8) !std.fs.Dir {
    root.makeDir(subdir) catch {};
    var d = try root.openDir(subdir, .{});
    errdefer d.close();
    d.makePath(".rl/jobs") catch {};
    return d;
}

fn writeFixtureJob(fixture: std.fs.Dir, name: []const u8, content: []const u8) !void {
    const path = try std.fmt.allocPrint(std.testing.allocator, ".rl/jobs/{s}", .{name});
    defer std.testing.allocator.free(path);
    const file = try fixture.createFile(path, .{});
    defer file.close();
    try file.writeAll(content);
}

test "hasRunningImplJob returns false when .rl/jobs/ is missing" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const path = try tmp.dir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(path);
    try std.testing.expect(!hasRunningImplJob(std.testing.allocator, path));
}

test "hasRunningImplJob detects running impl job" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.makePath(".rl/jobs");
    try writeFixtureJob(tmp.dir, "impl-packet-abc.json", "{\"kind\":\"implement\",\"status\":\"running\"}");
    const path = try tmp.dir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(path);
    try std.testing.expect(hasRunningImplJob(std.testing.allocator, path));
}

test "hasRunningImplJob detects queued impl job" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.makePath(".rl/jobs");
    try writeFixtureJob(tmp.dir, "impl-queued.json", "{\"status\":\"queued\"}");
    const path = try tmp.dir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(path);
    try std.testing.expect(hasRunningImplJob(std.testing.allocator, path));
}

test "hasRunningImplJob ignores completed impl jobs" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.makePath(".rl/jobs");
    try writeFixtureJob(tmp.dir, "impl-done.json", "{\"status\":\"completed\"}");
    try writeFixtureJob(tmp.dir, "impl-fail.json", "{\"status\":\"failed\"}");
    try writeFixtureJob(tmp.dir, "impl-cancel.json", "{\"status\":\"cancelled\"}");
    const path = try tmp.dir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(path);
    try std.testing.expect(!hasRunningImplJob(std.testing.allocator, path));
}

test "hasRunningImplJob ignores review jobs" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.makePath(".rl/jobs");
    // A running review job should NOT trigger the impl glyph.
    try writeFixtureJob(tmp.dir, "review-123-abc.json", "{\"status\":\"running\"}");
    const path = try tmp.dir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(path);
    try std.testing.expect(!hasRunningImplJob(std.testing.allocator, path));
}

test "hasRunningImplJob short-circuits on first running job" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.makePath(".rl/jobs");
    // Mixed — at least one running impl should return true.
    try writeFixtureJob(tmp.dir, "impl-done-1.json", "{\"status\":\"completed\"}");
    try writeFixtureJob(tmp.dir, "impl-running-2.json", "{\"status\":\"running\"}");
    try writeFixtureJob(tmp.dir, "impl-done-3.json", "{\"status\":\"failed\"}");
    const path = try tmp.dir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(path);
    try std.testing.expect(hasRunningImplJob(std.testing.allocator, path));
}

test "hasRunningImplJob ignores non-json files and non-impl prefixes" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.makePath(".rl/jobs");
    // Files that should be skipped:
    try writeFixtureJob(tmp.dir, "impl-running.txt", "{\"status\":\"running\"}"); // wrong extension
    try writeFixtureJob(tmp.dir, "not-impl.json", "{\"status\":\"running\"}"); // wrong prefix
    const path = try tmp.dir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(path);
    try std.testing.expect(!hasRunningImplJob(std.testing.allocator, path));
}

test "formatImplWorker emits glyph when running job exists" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.makePath(".rl/jobs");
    try writeFixtureJob(tmp.dir, "impl-xyz.json", "{\"status\":\"running\"}");
    const path = try tmp.dir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(path);

    var buf: [128]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buf);
    const wrote = try formatImplWorker(stream.writer(), std.testing.allocator, path);
    try std.testing.expect(wrote);
    try std.testing.expect(std.mem.indexOf(u8, stream.getWritten(), glyphs.impl) != null);
}

test "formatImplWorker writes nothing when no impl workers" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const path = try tmp.dir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(path);

    var buf: [128]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buf);
    const wrote = try formatImplWorker(stream.writer(), std.testing.allocator, path);
    try std.testing.expect(!wrote);
    try std.testing.expectEqual(@as(usize, 0), stream.getWritten().len);
}

test "parseYamlBool function" {
    try std.testing.expectEqual(true, parseYamlBool("active: true", "active:"));
    try std.testing.expectEqual(false, parseYamlBool("active: false", "active:"));
    try std.testing.expect(parseYamlBool("active: maybe", "active:") == null);
    try std.testing.expect(parseYamlBool("other: true", "active:") == null);
    try std.testing.expect(parseYamlBool("review_enabled: true", "review_enabled:") == true);
}

test "parseYamlInt function" {
    try std.testing.expectEqual(@as(u32, 50), parseYamlInt("max_iterations: 50", "max_iterations:").?);
    try std.testing.expectEqual(@as(u32, 0), parseYamlInt("iteration: 0", "iteration:").?);
    try std.testing.expectEqual(@as(u32, 123), parseYamlInt("count: 123", "count:").?);
    try std.testing.expect(parseYamlInt("iteration: abc", "iteration:") == null);
    try std.testing.expect(parseYamlInt("other: 50", "iteration:") == null);
}

test "parseRalphStateFromContent with valid v3 JSON" {
    const allocator = std.testing.allocator;
    const content =
        \\{"version":3,"strategy":"review","active":true,"iteration":5,"max_iterations":30,
        \\"review_enabled":true,"review_count":2,"max_review_cycles":10}
    ;
    const state = parseRalphStateFromContent(allocator, content);
    try std.testing.expect(state.active);
    try std.testing.expectEqual(@as(u32, 5), state.iteration);
    try std.testing.expectEqual(@as(u32, 30), state.max_iterations);
    try std.testing.expect(state.review_enabled);
    try std.testing.expectEqual(@as(u32, 2), state.review_count);
    try std.testing.expectEqual(@as(u32, 10), state.max_review_cycles);
    try std.testing.expectEqual(Strategy.review, state.strategy);
    try std.testing.expectEqual(@as(?u32, 3), state.version);
    try std.testing.expectEqual(VerdictRaw.none, state.review_verdict_raw);
}

test "parseRalphStateFromContent with partial fields falls back to defaults" {
    const allocator = std.testing.allocator;
    const state = parseRalphStateFromContent(allocator, "{\"active\":true,\"iteration\":3}");
    try std.testing.expect(state.active);
    try std.testing.expectEqual(@as(u32, 3), state.iteration);
    try std.testing.expectEqual(@as(u32, 50), state.max_iterations);
    try std.testing.expect(!state.review_enabled);
    try std.testing.expectEqual(Strategy.unknown, state.strategy);
    try std.testing.expectEqual(@as(?u32, null), state.version);
    try std.testing.expectEqual(MetricDirection.none, state.metric_direction);
    try std.testing.expect(!state.completion_claimed);
    try std.testing.expect(!state.blocked_claimed);
    try std.testing.expect(state.verdictSha() == null);
    try std.testing.expect(state.inFlightJobId() == null);
}

test "parseRalphStateFromContent with invalid JSON returns defaults" {
    const state = parseRalphStateFromContent(std.testing.allocator, "# not JSON");
    try std.testing.expect(!state.active);
}

test "parseRalphStateFromContent with empty content returns defaults" {
    const state = parseRalphStateFromContent(std.testing.allocator, "");
    try std.testing.expect(!state.active);
}

test "parseRalphStateFromContent ignores unknown fields" {
    const content =
        \\{"active":true,"iteration":7,"unknown_field":"x","completion_promise":"COMPLETE"}
    ;
    const state = parseRalphStateFromContent(std.testing.allocator, content);
    try std.testing.expect(state.active);
    try std.testing.expectEqual(@as(u32, 7), state.iteration);
}

test "parseRalphStateFromContent parses approve verdict + sha" {
    const content =
        \\{"version":3,"strategy":"review","active":true,
        \\"review_verdict":"approve","review_verdict_sha":"deadbeef",
        \\"review_in_flight_job_id":null}
    ;
    const state = parseRalphStateFromContent(std.testing.allocator, content);
    try std.testing.expectEqual(VerdictRaw.approve, state.review_verdict_raw);
    try std.testing.expect(state.verdictSha() != null);
    try std.testing.expectEqualStrings("deadbeef", state.verdictSha().?);
    try std.testing.expect(state.inFlightJobId() == null);
}

test "parseRalphStateFromContent parses reject verdict" {
    const content =
        \\{"version":3,"active":true,"review_verdict":"reject","review_verdict_sha":"abc"}
    ;
    const state = parseRalphStateFromContent(std.testing.allocator, content);
    try std.testing.expectEqual(VerdictRaw.reject, state.review_verdict_raw);
}

test "parseRalphStateFromContent parses in-flight job id" {
    const content =
        \\{"version":3,"active":true,"review_in_flight_job_id":"review-123-abc"}
    ;
    const state = parseRalphStateFromContent(std.testing.allocator, content);
    try std.testing.expect(state.inFlightJobId() != null);
    try std.testing.expectEqualStrings("review-123-abc", state.inFlightJobId().?);
}

test "parseRalphStateFromContent treats empty in-flight job id as absent" {
    const content = "{\"active\":true,\"review_in_flight_job_id\":\"\"}";
    const state = parseRalphStateFromContent(std.testing.allocator, content);
    try std.testing.expect(state.inFlightJobId() == null);
}

test "parseRalphStateFromContent parses research metric + direction" {
    const content =
        \\{"version":3,"strategy":"research","active":true,"iteration":5,"max_iterations":30,
        \\"metric_name":"accuracy","metric_direction":"maximize","best_metric_value":0.8231}
    ;
    const state = parseRalphStateFromContent(std.testing.allocator, content);
    try std.testing.expectEqual(Strategy.research, state.strategy);
    try std.testing.expect(state.best_metric_value != null);
    try std.testing.expectApproxEqAbs(@as(f64, 0.8231), state.best_metric_value.?, 0.0001);
    try std.testing.expectEqual(MetricDirection.maximize, state.metric_direction);
}

test "parseRalphStateFromContent parses minimize direction" {
    const content = "{\"strategy\":\"research\",\"metric_direction\":\"minimize\"}";
    const state = parseRalphStateFromContent(std.testing.allocator, content);
    try std.testing.expectEqual(MetricDirection.minimize, state.metric_direction);
}

test "parseRalphStateFromContent parses terminal-state flags" {
    const content = "{\"active\":true,\"completion_claimed\":true,\"blocked_claimed\":true}";
    const state = parseRalphStateFromContent(std.testing.allocator, content);
    try std.testing.expect(state.completion_claimed);
    try std.testing.expect(state.blocked_claimed);
}

test "parseRalphStateFromContent parses iteration_start_ms" {
    const content = "{\"active\":true,\"iteration_start_ms\":1776040656906}";
    const state = parseRalphStateFromContent(std.testing.allocator, content);
    try std.testing.expect(state.iteration_start_ms != null);
    try std.testing.expectEqual(@as(i64, 1776040656906), state.iteration_start_ms.?);
}

test "parseRalphStateFromContent captures stale schema version" {
    const content = "{\"version\":2,\"active\":true,\"iteration\":1}";
    const state = parseRalphStateFromContent(std.testing.allocator, content);
    try std.testing.expect(state.active);
    try std.testing.expectEqual(@as(?u32, 2), state.version);
}

test "parseRalphStateFromContent handles real-world state.json shape" {
    // Actual payload observed in ~/0xbigboss/rl/.rl/state.json on 2026-04-13.
    const content =
        \\{"version":3,"strategy":"review","active":true,"iteration":0,"max_iterations":30,
        \\"timestamp":"2026-04-13T01:07:58Z","review_enabled":true,"review_count":0,
        \\"max_review_cycles":30,"debug":false,"review_verdict":"reject",
        \\"review_verdict_sha":"8bc2c48697d39eb0488b64ddd00f7a0a3bcdcd64",
        \\"review_verdict_ts":"2026-04-13T01:09:44.749Z",
        \\"review_verdict_job_id":"review-1776042481651-abccbr",
        \\"review_in_flight_job_id":null,"iteration_start_ms":1776042478932,
        \\"iteration_start_sha":"8bc2c48","blocked_claimed":true}
    ;
    const state = parseRalphStateFromContent(std.testing.allocator, content);
    try std.testing.expect(state.active);
    try std.testing.expectEqual(Strategy.review, state.strategy);
    try std.testing.expectEqual(VerdictRaw.reject, state.review_verdict_raw);
    try std.testing.expect(state.blocked_claimed);
    try std.testing.expect(state.verdictSha() != null);
    try std.testing.expectEqualStrings("8bc2c48697d39eb0488b64ddd00f7a0a3bcdcd64", state.verdictSha().?);
    try std.testing.expect(state.inFlightJobId() == null);
    try std.testing.expect(state.iteration_start_ms != null);
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
