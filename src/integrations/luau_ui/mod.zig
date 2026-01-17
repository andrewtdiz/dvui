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
        const ui_table = self.lua.createTable(.{ .rec = 7 });
        defer ui_table.deinit();

        try ui_table.set("log", luaz.Lua.Capture(self, luaLog));
        try ui_table.set("reset", luaz.Lua.Capture(self, luaReset));
        try ui_table.set("create", luaz.Lua.Capture(self, luaCreate));
        try ui_table.set("remove", luaz.Lua.Capture(self, luaRemove));
        try ui_table.set("insert", luaz.Lua.Capture(self, luaInsert));
        try ui_table.set("set_text", luaz.Lua.Capture(self, luaSetText));
        try ui_table.set("set_class", luaz.Lua.Capture(self, luaSetClass));

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

    fn luaCreate(upv: luaz.Lua.Upvalues(*LuaUi), tag: []const u8, id: u32, parent: ?u32, before: ?u32) !void {
        try upv.value.createNode(tag, id, parent, before);
    }

    fn luaRemove(upv: luaz.Lua.Upvalues(*LuaUi), id: u32) !void {
        try upv.value.removeNode(id);
    }

    fn luaInsert(upv: luaz.Lua.Upvalues(*LuaUi), id: u32, parent: ?u32, before: ?u32) !void {
        try upv.value.insertNode(id, parent, before);
    }

    fn luaSetText(upv: luaz.Lua.Upvalues(*LuaUi), id: u32, text: []const u8) !void {
        try upv.value.setText(id, text);
    }

    fn luaSetClass(upv: luaz.Lua.Upvalues(*LuaUi), id: u32, class_name: []const u8) !void {
        try upv.value.setClass(id, class_name);
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

    fn createNode(self: *LuaUi, tag: []const u8, id: u32, parent: ?u32, before: ?u32) !void {
        if (std.mem.eql(u8, tag, "text")) {
            try self.store.setTextNode(id, "");
        } else if (std.mem.eql(u8, tag, "slot")) {
            try self.store.upsertSlot(id);
        } else {
            try self.store.upsertElement(id, tag);
        }

        const parent_id: u32 = parent orelse 0;
        try self.store.insert(parent_id, id, before);
    }

    fn removeNode(self: *LuaUi, id: u32) !void {
        if (id == 0) return error.MissingId;
        self.store.remove(id);
    }

    fn insertNode(self: *LuaUi, id: u32, parent: ?u32, before: ?u32) !void {
        if (id == 0) return error.MissingId;
        const parent_id = parent orelse return error.MissingParent;
        if (self.store.node(id) == null) return error.MissingChild;
        if (self.store.node(parent_id) == null) return error.MissingParent;
        try self.store.insert(parent_id, id, before);
    }

    fn setText(self: *LuaUi, id: u32, text: []const u8) !void {
        if (id == 0) return error.MissingId;
        try self.store.setTextNode(id, text);
    }

    fn setClass(self: *LuaUi, id: u32, class_name: []const u8) !void {
        if (id == 0) return error.MissingId;
        try self.store.setClassName(id, class_name);
    }
};
