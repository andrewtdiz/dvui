const std = @import("std");

/// Lightweight host-side representation of the HTML/JS environment that lives
/// inside the embedded webview.
///
/// The struct does **not** attempt to implement an actual browser runtime.
/// Instead, it keeps track of which HTML template should be loaded inside the
/// platform webview, records the JavaScript snippets that we ask the webview to
/// execute, and exposes a small message channel for JS-to-Zig callbacks.  This
/// allows Zig code to interact with the UI layer without depending on the
/// legacy QuickJS renderer.
pub const JSRuntime = struct {
    allocator: std.mem.Allocator,

    /// Absolute or relative path to the HTML entry point that should be loaded
    /// into the webview.
    index_path: []const u8,
    /// Cached copy of the HTML file so that we can hot‑reload or inspect the
    /// document without repeatedly hitting the filesystem.
    index_cache: ?[]u8 = null,

    /// Stores every JavaScript snippet we have sent to the host.  This doubles
    /// as a convenient debugging aid and as a simple queue for headless tests.
    command_log: std.ArrayListUnmanaged(u8) = .{},

    action_handler: ?ActionCallback = null,

    pub const ActionCallback = struct {
        ctx: ?*anyopaque = null,
        handler: *const fn (ctx: ?*anyopaque, action_name: []const u8, payload_json: []const u8) anyerror!void,
    };

    pub const Error = error{
        ActionHandlerUnavailable,
        InvalidActionEnvelope,
    } || std.mem.Allocator.Error || std.fs.File.OpenError || std.fs.File.ReadError;

    /// Create a runtime that targets `index_path`.  The HTML is only loaded when
    /// `ensureIndexLoaded` is called so that applications can adjust the path
    /// before the webview boots.
    pub fn init(allocator: std.mem.Allocator, index_path: []const u8) JSRuntime {
        return .{
            .allocator = allocator,
            .index_path = index_path,
        };
    }

    pub fn deinit(self: *JSRuntime) void {
        if (self.index_cache) |cache| {
            self.allocator.free(cache);
            self.index_cache = null;
        }
        self.command_log.deinit(self.allocator);
        self.action_handler = null;
    }

    /// Ensure that the index HTML file is cached in memory.
    pub fn ensureIndexLoaded(self: *JSRuntime) Error!void {
        if (self.index_cache != null) return;

        var file = try std.fs.cwd().openFile(self.index_path, .{});
        defer file.close();

        const contents = try file.readToEndAlloc(self.allocator, std.math.maxInt(usize));
        self.index_cache = contents;
    }

    /// Return the cached HTML document if it has been loaded.
    pub fn indexHtml(self: *const JSRuntime) ?[]const u8 {
        return self.index_cache;
    }

    /// Register a callback that will be invoked when the JavaScript layer calls
    /// `window.dvui.native.performAction`.
    pub fn setActionHandler(self: *JSRuntime, cb: ActionCallback) void {
        self.action_handler = cb;
    }

    /// Low level helper used by the backend to execute arbitrary JavaScript
    /// within the webview context.
    pub fn executeJavaScript(self: *JSRuntime, source: []const u8) Error!void {
        try self.command_log.ensureUnusedCapacity(self.allocator, source.len + 1);
        self.command_log.appendSliceAssumeCapacity(source);
        self.command_log.appendAssumeCapacity('\n');
    }

    /// Helper that turns a JSON blob into a `window.dvui.dispatchNativeEvent`
    /// invocation.
    pub fn dispatchNativeEvent(self: *JSRuntime, event_json: []const u8) Error!void {
        var builder = std.ArrayList(u8).init(self.allocator);
        defer builder.deinit();

        try builder.writer().print(
            "window.dvui && window.dvui.dispatchNativeEvent && window.dvui.dispatchNativeEvent({s});",
            .{event_json},
        );
        try self.executeJavaScript(builder.items);
    }

    /// Allow platform-specific code to report that the JavaScript layer sent a
    /// message back to the host.  Messages must be JSON objects that contain an
    /// `action` field (string) and an optional `payload` field (any JSON value).
    pub fn handleMessageFromJs(self: *JSRuntime, message_json: []const u8) Error!void {
        const callback = self.action_handler orelse return Error.ActionHandlerUnavailable;

        var parsed = try std.json.parseFromSlice(std.json.Value, self.allocator, message_json, .{});
        defer parsed.deinit();

        const root = parsed.value;
        const obj = root.object orelse return Error.InvalidActionEnvelope;

        const action_value = obj.get("action") orelse return Error.InvalidActionEnvelope;
        const action_str = switch (action_value.*) {
            .string => |s| s,
            else => return Error.InvalidActionEnvelope,
        };

        const payload_value = obj.get("payload") orelse std.json.Value{ .null = {} };

        const action_name = try self.allocator.dupe(u8, action_str);
        defer self.allocator.free(action_name);

        var payload_buf = std.ArrayList(u8).init(self.allocator);
        defer payload_buf.deinit();
        try std.json.stringify(payload_value, .{}, payload_buf.writer());

        try callback.handler(callback.ctx, action_name, payload_buf.items);
    }

    /// Convenience API useful for diagnostics and tests.
    pub fn drainCommandLog(self: *JSRuntime) []u8 {
        return self.command_log.toOwnedSlice(self.allocator) catch &[_]u8{};
    }
};
