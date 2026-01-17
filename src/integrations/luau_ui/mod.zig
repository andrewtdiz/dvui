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
        const ui_table = self.lua.createTable(.{ .rec = 9 });
        defer ui_table.deinit();

        try ui_table.set("log", luaz.Lua.Capture(self, luaLog));
        try ui_table.set("reset", luaz.Lua.Capture(self, luaReset));
        try ui_table.set("create", luaz.Lua.Capture(self, luaCreate));
        try ui_table.set("remove", luaz.Lua.Capture(self, luaRemove));
        try ui_table.set("insert", luaz.Lua.Capture(self, luaInsert));
        try ui_table.set("set_text", luaz.Lua.Capture(self, luaSetText));
        try ui_table.set("set_class", luaz.Lua.Capture(self, luaSetClass));
        try ui_table.set("set_visual", luaz.Lua.Capture(self, luaSetVisual));
        try ui_table.set("set_transform", luaz.Lua.Capture(self, luaSetTransform));

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

    fn readOptionalField(comptime T: type, table: luaz.Lua.Table, key: []const u8) !?T {
        return table.get(key, T) catch |err| switch (err) {
            error.KeyNotFound => null,
            else => return err,
        };
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

    fn luaSetVisual(upv: luaz.Lua.Upvalues(*LuaUi), id: u32, props: luaz.Lua.Table) !void {
        defer props.deinit();
        try upv.value.setVisual(id, props);
    }

    fn luaSetTransform(upv: luaz.Lua.Upvalues(*LuaUi), id: u32, props: luaz.Lua.Table) !void {
        defer props.deinit();
        try upv.value.setTransform(id, props);
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

    fn setVisual(self: *LuaUi, id: u32, props: luaz.Lua.Table) !void {
        if (id == 0) return error.MissingId;
        const target = self.store.node(id) orelse return error.MissingId;
        var changed = false;
        if (try readOptionalField(f32, props, "opacity")) |value| {
            target.visual.opacity = value;
            changed = true;
        }
        if (try readOptionalField(f32, props, "cornerRadius")) |value| {
            target.visual.corner_radius = value;
            changed = true;
        }
        if (try readOptionalField(u32, props, "background")) |value| {
            target.visual.background = .{ .value = value };
            changed = true;
        }
        if (try readOptionalField(u32, props, "textColor")) |value| {
            target.visual.text_color = .{ .value = value };
            changed = true;
        }
        if (try readOptionalField(bool, props, "clipChildren")) |value| {
            target.visual.clip_children = value;
            changed = true;
        }
        if (changed) {
            self.store.markNodeChanged(id);
        }
    }

    fn setTransform(self: *LuaUi, id: u32, props: luaz.Lua.Table) !void {
        if (id == 0) return error.MissingId;
        const target = self.store.node(id) orelse return error.MissingId;
        var changed = false;
        if (try readOptionalField(f32, props, "rotation")) |value| {
            target.transform.rotation = value;
            changed = true;
        }
        if (try readOptionalField(f32, props, "scaleX")) |value| {
            target.transform.scale[0] = value;
            changed = true;
        }
        if (try readOptionalField(f32, props, "scaleY")) |value| {
            target.transform.scale[1] = value;
            changed = true;
        }
        if (try readOptionalField(f32, props, "anchorX")) |value| {
            target.transform.anchor[0] = value;
            changed = true;
        }
        if (try readOptionalField(f32, props, "anchorY")) |value| {
            target.transform.anchor[1] = value;
            changed = true;
        }
        if (try readOptionalField(f32, props, "translateX")) |value| {
            target.transform.translation[0] = value;
            changed = true;
        }
        if (try readOptionalField(f32, props, "translateY")) |value| {
            target.transform.translation[1] = value;
            changed = true;
        }
        if (changed) {
            self.store.markNodeChanged(id);
        }
    }
};
