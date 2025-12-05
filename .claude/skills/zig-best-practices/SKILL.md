---
name: zig-best-practices
description: Provides Zig code quality patterns for error handling with error unions, memory management with allocators and defer/errdefer, exhaustive switch statements, and testing with leak detection. Activates when editing .zig files, working with Zig projects (build.zig, build.zig.zon), or when the user mentions Zig, error unions, allocators, or comptime.
---

# Zig Best Practices

## Instructions

- Return errors with context using error unions (`!T`); every function returns a value or an error. Explicit error sets document failure modes.
- Use `errdefer` for cleanup on error paths; use `defer` for unconditional cleanup. This prevents resource leaks without try-finally boilerplate.
- Handle all branches in `switch` statements; include an `else` clause that returns an error or uses `unreachable` for truly impossible cases.
- Pass allocators explicitly to functions requiring dynamic memory; prefer `std.testing.allocator` in tests for leak detection.
- Prefer `const` over `var`; prefer slices over raw pointers for bounds safety. Immutability signals intent and enables optimizations.
- Avoid `anytype`; prefer explicit `comptime T: type` parameters. Explicit types document intent and produce clearer error messages.
- Use `std.log.scoped` for namespaced logging; define a module-level `log` constant for consistent scope across the file.
- Add or update tests for new logic; use `std.testing.allocator` to catch memory leaks automatically.

## Examples

Explicit failure for unimplemented logic:
```zig
fn buildWidget(widget_type: []const u8) !Widget {
    return error.NotImplemented;
}
```

Propagate errors with try:
```zig
fn readConfig(path: []const u8) !Config {
    const file = try std.fs.cwd().openFile(path, .{});
    defer file.close();
    const contents = try file.readToEndAlloc(allocator, max_size);
    return parseConfig(contents);
}
```

Resource cleanup with errdefer:
```zig
fn createResource(allocator: std.mem.Allocator) !*Resource {
    const resource = try allocator.create(Resource);
    errdefer allocator.destroy(resource);

    resource.* = try initializeResource();
    return resource;
}
```

Exhaustive switch with explicit default:
```zig
fn processStatus(status: Status) ![]const u8 {
    return switch (status) {
        .active => "processing",
        .inactive => "skipped",
        _ => error.UnhandledStatus,
    };
}
```

Testing with memory leak detection:
```zig
const std = @import("std");

test "widget creation" {
    const allocator = std.testing.allocator;
    var list: std.ArrayListUnmanaged(u32) = .empty;
    defer list.deinit(allocator);

    try list.append(allocator, 42);
    try std.testing.expectEqual(1, list.items.len);
}
```

## Memory Management

- Pass allocators explicitly; never use global state for allocation. Functions declare their allocation needs in parameters.
- Use `defer` immediately after acquiring a resource. Place cleanup logic next to acquisition for clarity.
- Prefer arena allocators for temporary allocations; they free everything at once when the arena is destroyed.
- Use `std.testing.allocator` in tests; it reports leaks with stack traces showing allocation origins.

### Examples

Allocator as explicit parameter:
```zig
fn processData(allocator: std.mem.Allocator, input: []const u8) ![]u8 {
    const result = try allocator.alloc(u8, input.len * 2);
    errdefer allocator.free(result);

    // process input into result
    return result;
}
```

Arena allocator for batch operations:
```zig
fn processBatch(items: []const Item) !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    for (items) |item| {
        const processed = try processItem(allocator, item);
        try outputResult(processed);
    }
    // All allocations freed when arena deinits
}
```

## Logging

- Use `std.log.scoped` to create namespaced loggers; each module should define its own scoped logger for filtering.
- Define a module-level `const log` at the top of the file; use it consistently throughout the module.
- Use appropriate log levels: `err` for failures, `warn` for suspicious conditions, `info` for state changes, `debug` for tracing.

### Examples

Scoped logger for a module:
```zig
const std = @import("std");
const log = std.log.scoped(.widgets);

pub fn createWidget(name: []const u8) !Widget {
    log.debug("creating widget: {s}", .{name});
    const widget = try allocateWidget(name);
    log.debug("created widget id={d}", .{widget.id});
    return widget;
}

pub fn deleteWidget(id: u32) void {
    log.info("deleting widget id={d}", .{id});
    // cleanup
}
```

Multiple scopes in a codebase:
```zig
// In src/db.zig
const log = std.log.scoped(.db);

// In src/http.zig
const log = std.log.scoped(.http);

// In src/auth.zig
const log = std.log.scoped(.auth);
```

## Comptime Patterns

- Use `comptime` parameters for generic functions; type information is available at compile time with zero runtime cost.
- Prefer compile-time validation over runtime checks when possible. Catch errors during compilation rather than in production.
- Use `@compileError` for invalid configurations that should fail the build.

### Examples

Generic function with comptime type:
```zig
fn max(comptime T: type, a: T, b: T) T {
    return if (a > b) a else b;
}
```

Compile-time validation:
```zig
fn createBuffer(comptime size: usize) [size]u8 {
    if (size == 0) {
        @compileError("buffer size must be greater than 0");
    }
    return [_]u8{0} ** size;
}
```

## Avoiding anytype

- Prefer `comptime T: type` over `anytype`; explicit type parameters document expected constraints and produce clearer errors.
- Use `anytype` only when the function genuinely accepts any type (like `std.debug.print`) or for callbacks/closures.
- When using `anytype`, add a doc comment describing the expected interface or constraints.

### Examples

Prefer explicit comptime type (good):
```zig
fn sum(comptime T: type, items: []const T) T {
    var total: T = 0;
    for (items) |item| {
        total += item;
    }
    return total;
}
```

Avoid anytype when type is known (bad):
```zig
// Unclear what types are valid; error messages will be confusing
fn sum(items: anytype) @TypeOf(items[0]) {
    // ...
}
```

Acceptable anytype for callbacks:
```zig
/// Calls `callback` for each item. Callback must accept (T) and return void.
fn forEach(comptime T: type, items: []const T, callback: anytype) void {
    for (items) |item| {
        callback(item);
    }
}
```

Using @TypeOf when anytype is necessary:
```zig
fn debugPrint(value: anytype) void {
    const T = @TypeOf(value);
    if (@typeInfo(T) == .Pointer) {
        std.debug.print("ptr: {*}\n", .{value});
    } else {
        std.debug.print("val: {}\n", .{value});
    }
}
```

## Error Handling Patterns

- Define specific error sets for functions; avoid `anyerror` when possible. Specific errors document failure modes.
- Use `catch` with a block for error recovery or logging; use `catch unreachable` only when errors are truly impossible.
- Merge error sets with `||` when combining operations that can fail in different ways.

### Examples

Specific error set:
```zig
const ConfigError = error{
    FileNotFound,
    ParseError,
    InvalidFormat,
};

fn loadConfig(path: []const u8) ConfigError!Config {
    // implementation
}
```

Error handling with catch block:
```zig
const value = operation() catch |err| {
    std.log.err("operation failed: {}", .{err});
    return error.OperationFailed;
};
```

## Optionals

- Use `orelse` to provide default values for optionals; use `.?` only when null is a program error.
- Prefer `if (optional) |value|` pattern for safe unwrapping with access to the value.

### Examples

Safe optional handling:
```zig
fn findWidget(id: u32) ?*Widget {
    // lookup implementation
}

fn processWidget(id: u32) !void {
    const widget = findWidget(id) orelse return error.WidgetNotFound;
    try widget.process();
}
```

Optional with if unwrapping:
```zig
if (maybeValue) |value| {
    try processValue(value);
} else {
    std.log.warn("no value present", .{});
}
```

## Advanced Patterns

These patterns demonstrate Zig's more powerful features. Use as reference when needed.

### Generic Data Structures

Return a type from a function to create reusable generic containers:
```zig
pub fn Queue(comptime Child: type) type {
    return struct {
        const Self = @This();
        const Node = struct {
            data: Child,
            next: ?*Node,
        };

        allocator: std.mem.Allocator,
        start: ?*Node,
        end: ?*Node,

        pub fn init(allocator: std.mem.Allocator) Self {
            return Self{ .allocator = allocator, .start = null, .end = null };
        }

        pub fn enqueue(self: *Self, value: Child) !void {
            const node = try self.allocator.create(Node);
            node.* = .{ .data = value, .next = null };
            if (self.end) |end| end.next = node else self.start = node;
            self.end = node;
        }

        pub fn dequeue(self: *Self) ?Child {
            const start = self.start orelse return null;
            defer self.allocator.destroy(start);
            if (start.next) |next| self.start = next else {
                self.start = null;
                self.end = null;
            }
            return start.data;
        }
    };
}
```

### GeneralPurposeAllocator for Leak Detection

Use GPA in debug builds to catch memory leaks with stack traces:
```zig
pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer std.debug.assert(gpa.deinit() == .ok);
    const allocator = gpa.allocator();

    // Use allocator; leaks will be reported on deinit
}
```

### C Interoperability

Import C headers directly with `@cImport`:
```zig
const ray = @cImport({
    @cInclude("raylib.h");
});

pub fn main() void {
    ray.InitWindow(800, 450, "window title");
    defer ray.CloseWindow();

    ray.SetTargetFPS(60);
    while (!ray.WindowShouldClose()) {
        ray.BeginDrawing();
        defer ray.EndDrawing();
        ray.ClearBackground(ray.RAYWHITE);
    }
}
```

### Extern Functions (System APIs)

Call platform APIs without bindings:
```zig
const win = @import("std").os.windows;

extern "user32" fn MessageBoxA(
    ?win.HWND,
    [*:0]const u8,
    [*:0]const u8,
    u32,
) callconv(.winapi) i32;
```

### C Callbacks with Zig

Pass Zig functions to C libraries using `callconv(.C)`:
```zig
fn writeCallback(
    data: *anyopaque,
    size: c_uint,
    nmemb: c_uint,
    user_data: *anyopaque,
) callconv(.C) c_uint {
    const buffer: *std.ArrayList(u8) = @alignCast(@ptrCast(user_data));
    const typed_data: [*]u8 = @ptrCast(data);
    buffer.appendSlice(typed_data[0 .. nmemb * size]) catch return 0;
    return nmemb * size;
}
```

## References

- Language Reference: https://ziglang.org/documentation/0.15.2/
- Standard Library: https://ziglang.org/documentation/0.15.2/std/
- Code Samples: https://ziglang.org/learn/samples/
- Zig Guide: https://zig.guide/
