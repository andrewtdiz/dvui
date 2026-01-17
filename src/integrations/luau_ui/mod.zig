const std = @import("std");

const luaz = @import("luaz");
const solid = @import("solid");

pub const LogFn = fn (level: u8, msg_ptr: [*]const u8, msg_len: usize) callconv(.c) void;

pub const LuaUi = struct {
    store: *solid.NodeStore,
    lua: *luaz.Lua,
    log_cb: ?*const LogFn = null,

    pub fn init(self: *LuaUi, store: *solid.NodeStore, lua: *luaz.Lua, log_cb: ?*const LogFn) !void {
        self.* = .{
            .store = store,
            .lua = lua,
            .log_cb = log_cb,
        };
        try self.registerBindings();
    }

    pub fn deinit(self: *LuaUi) void {
        _ = self;
    }

    fn registerBindings(self: *LuaUi) !void {
        const ui_table = self.lua.createTable(.{ .rec = 2 });
        defer ui_table.deinit();

        try ui_table.set("log", luaz.Lua.Capture(self, luaLog));
        try ui_table.set("reset", luaz.Lua.Capture(self, luaReset));

        const globals = self.lua.globals();
        try globals.set("ui", ui_table);
    }

    fn logMessage(self: *LuaUi, level: u8, comptime fmt: []const u8, args: anytype) void {
        if (self.log_cb) |log_fn| {
            var buffer: [160]u8 = undefined;
            const msg = std.fmt.bufPrint(&buffer, fmt, args) catch return;
            const msg_ptr: [*]const u8 = @ptrCast(msg.ptr);
            log_fn(level, msg_ptr, msg.len);
        }
    }

    fn luaLog(upv: luaz.Lua.Upvalues(*LuaUi), msg: []const u8) void {
        upv.value.logMessage(1, "{s}", .{msg});
    }

    fn luaReset(upv: luaz.Lua.Upvalues(*LuaUi)) void {
        upv.value.resetStore() catch |err| {
            upv.value.logMessage(3, "ui.reset failed: {s}", .{@errorName(err)});
        };
    }

    fn resetStore(self: *LuaUi) !void {
        const allocator = self.store.allocator;
        self.store.deinit();
        try self.store.init(allocator);
    }
};
