const std = @import("std");

const luaz = @import("luaz");
const retained = @import("retained");

pub const LogFn = fn (level: u8, msg_ptr: [*]const u8, msg_len: usize) callconv(.c) void;

const PropKey = enum(u32) {
    Text = 1,
    Class = 2,
    Transform = 3,
    Visual = 4,
    Scroll = 5,
    Anchor = 6,
    Image = 7,
    Src = 8,
};

pub const LuaUi = struct {
    store: *retained.NodeStore,
    lua: *luaz.Lua,
    log_cb: ?*const LogFn = null,

    const Self = @This();

    pub fn init(self: *Self, store: *retained.NodeStore, lua: *luaz.Lua, log_cb: ?*const LogFn) !void {
        self.* = .{
            .store = store,
            .lua = lua,
            .log_cb = log_cb,
        };
        try self.registerBindings();
    }

    pub fn deinit(self: *Self) void {
        _ = self;
    }

fn registerBindings(self: *Self) !void {
    const ui_table = self.lua.createTable(.{ .rec = 16 });
    defer ui_table.deinit();

    const kind_fields = @typeInfo(retained.events.EventKind).@"enum".fields;
    const kind_rec: u32 = @intCast(kind_fields.len);
    const kind_table = self.lua.createTable(.{ .rec = kind_rec });
    defer kind_table.deinit();
    inline for (kind_fields) |field| {
        const kind: retained.events.EventKind = @field(retained.events.EventKind, field.name);
        const kind_value: u32 = @intFromEnum(kind);
        try kind_table.set(field.name, kind_value);
    }
    try ui_table.set("EventKind", kind_table);

    const prop_table = self.lua.createTable(.{ .rec = 8 });
    defer prop_table.deinit();
    try prop_table.set("Text", @intFromEnum(PropKey.Text));
    try prop_table.set("Class", @intFromEnum(PropKey.Class));
    try prop_table.set("Transform", @intFromEnum(PropKey.Transform));
    try prop_table.set("Visual", @intFromEnum(PropKey.Visual));
    try prop_table.set("Scroll", @intFromEnum(PropKey.Scroll));
    try prop_table.set("Anchor", @intFromEnum(PropKey.Anchor));
    try prop_table.set("Image", @intFromEnum(PropKey.Image));
    try prop_table.set("Src", @intFromEnum(PropKey.Src));
    try ui_table.set("PropKey", prop_table);

    try ui_table.set("log", luaz.Lua.Capture(self, luaLog));
    try ui_table.set("reset", luaz.Lua.Capture(self, luaReset));
    try ui_table.set("create", luaz.Lua.Capture(self, luaCreate));
    try ui_table.set("remove", luaz.Lua.Capture(self, luaRemove));
    try ui_table.set("insert", luaz.Lua.Capture(self, luaInsert));
    try ui_table.set("patch", luaz.Lua.Capture(self, luaPatch));
    try ui_table.set("set_text", luaz.Lua.Capture(self, luaSetText));
    try ui_table.set("set_input", luaz.Lua.Capture(self, luaSetInput));
    try ui_table.set("set_class", luaz.Lua.Capture(self, luaSetClass));
    try ui_table.set("set_src", luaz.Lua.Capture(self, luaSetSrc));
    try ui_table.set("set_image", luaz.Lua.Capture(self, luaSetImage));
    try ui_table.set("set_visual", luaz.Lua.Capture(self, luaSetVisual));
    try ui_table.set("set_transform", luaz.Lua.Capture(self, luaSetTransform));
    try ui_table.set("set_scroll", luaz.Lua.Capture(self, luaSetScroll));
    try ui_table.set("set_anchor", luaz.Lua.Capture(self, luaSetAnchor));
    try ui_table.set("listen_kind", luaz.Lua.Capture(self, luaListenKind));

    const globals = self.lua.globals();
    try globals.set("ui", ui_table);
}

fn logMessage(self: *Self, level: u8, comptime fmt: []const u8, args: anytype) void {
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

fn parseAnchorSide(value: []const u8) ?retained.AnchorSide {
    if (std.mem.eql(u8, value, "top")) return .top;
    if (std.mem.eql(u8, value, "bottom")) return .bottom;
    if (std.mem.eql(u8, value, "left")) return .left;
    if (std.mem.eql(u8, value, "right")) return .right;
    return null;
}

fn parseAnchorAlign(value: []const u8) ?retained.AnchorAlign {
    if (std.mem.eql(u8, value, "start")) return .start;
    if (std.mem.eql(u8, value, "center")) return .center;
    if (std.mem.eql(u8, value, "end")) return .end;
    return null;
}

fn parseFontRenderMode(value: []const u8) ?retained.FontRenderMode {
    if (std.mem.eql(u8, value, "msdf")) return .msdf;
    if (std.mem.eql(u8, value, "raster")) return .raster;
    return null;
}

fn luaCreate(upv: luaz.Lua.Upvalues(*Self), tag: []const u8, id: u32, parent: ?u32, before: ?u32) !void {
    try upv.value.createNode(tag, id, parent, before);
}

fn luaRemove(upv: luaz.Lua.Upvalues(*Self), id: u32) !void {
    try upv.value.removeNode(id);
}

fn luaInsert(upv: luaz.Lua.Upvalues(*Self), id: u32, parent: ?u32, before: ?u32) !void {
    try upv.value.insertNode(id, parent, before);
}

fn luaPatch(upv: luaz.Lua.Upvalues(*Self), id: u32, args: luaz.Lua.Varargs) !void {
    try upv.value.applyPatch(id, args);
}

fn luaSetText(upv: luaz.Lua.Upvalues(*Self), id: u32, text: []const u8) !void {
    try upv.value.setText(id, text);
}

fn luaSetInput(upv: luaz.Lua.Upvalues(*Self), id: u32, text: []const u8) !void {
    try upv.value.setInput(id, text);
}

fn luaSetClass(upv: luaz.Lua.Upvalues(*Self), id: u32, class_name: []const u8) !void {
    try upv.value.setClass(id, class_name);
}

fn luaSetSrc(upv: luaz.Lua.Upvalues(*Self), id: u32, src: []const u8) !void {
    try upv.value.setSrc(id, src);
}

fn luaSetImage(upv: luaz.Lua.Upvalues(*Self), id: u32, props: luaz.Lua.Table) !void {
    defer props.deinit();
    try upv.value.setImage(id, props);
}

fn luaSetVisual(upv: luaz.Lua.Upvalues(*Self), id: u32, props: luaz.Lua.Table) !void {
    defer props.deinit();
    try upv.value.setVisual(id, props);
}

fn luaSetTransform(upv: luaz.Lua.Upvalues(*Self), id: u32, props: luaz.Lua.Table) !void {
    defer props.deinit();
    try upv.value.setTransform(id, props);
}

fn luaSetScroll(upv: luaz.Lua.Upvalues(*Self), id: u32, props: luaz.Lua.Table) !void {
    defer props.deinit();
    try upv.value.setScroll(id, props);
}

fn luaSetAnchor(upv: luaz.Lua.Upvalues(*Self), id: u32, props: luaz.Lua.Table) !void {
    defer props.deinit();
    try upv.value.setAnchor(id, props);
}

fn luaListenKind(upv: luaz.Lua.Upvalues(*Self), id: u32, kind: u32) !void {
    try upv.value.addListenerKind(id, kind);
}

fn luaLog(upv: luaz.Lua.Upvalues(*Self), msg: []const u8) void {
    upv.value.logMessage(1, "{s}", .{msg});
}

fn luaReset(upv: luaz.Lua.Upvalues(*Self)) void {
    upv.value.resetStore() catch |err| {
        upv.value.logMessage(3, "ui.reset failed: {s}", .{@errorName(err)});
    };
}

fn applyPatch(self: *Self, id: u32, args: luaz.Lua.Varargs) !void {
    if (id == 0) return error.MissingId;
    const count = args.len();
    if (count % 2 != 0) return error.InvalidPatch;
    var index: usize = 0;
    while (index < count) : (index += 2) {
        const key_opt = args.at(u32, index);
        if (key_opt == null) return error.InvalidPatch;
        const key = key_opt.?;
        switch (key) {
            @intFromEnum(PropKey.Text) => {
                const text_opt = args.at([]const u8, index + 1);
                if (text_opt == null) return error.InvalidPatch;
                try self.setText(id, text_opt.?);
            },
            @intFromEnum(PropKey.Class) => {
                const class_opt = args.at([]const u8, index + 1);
                if (class_opt == null) return error.InvalidPatch;
                try self.setClass(id, class_opt.?);
            },
            @intFromEnum(PropKey.Transform) => {
                const value_type = args.typeAt(index + 1) orelse return error.InvalidPatch;
                if (value_type == .nil) continue;
                const props_opt = args.at(luaz.Lua.Table, index + 1);
                if (props_opt == null) return error.InvalidPatch;
                var props = props_opt.?;
                defer props.deinit();
                try self.setTransform(id, props);
            },
            @intFromEnum(PropKey.Visual) => {
                const value_type = args.typeAt(index + 1) orelse return error.InvalidPatch;
                if (value_type == .nil) continue;
                const props_opt = args.at(luaz.Lua.Table, index + 1);
                if (props_opt == null) return error.InvalidPatch;
                var props = props_opt.?;
                defer props.deinit();
                try self.setVisual(id, props);
            },
            @intFromEnum(PropKey.Scroll) => {
                const value_type = args.typeAt(index + 1) orelse return error.InvalidPatch;
                if (value_type == .nil) continue;
                const props_opt = args.at(luaz.Lua.Table, index + 1);
                if (props_opt == null) return error.InvalidPatch;
                var props = props_opt.?;
                defer props.deinit();
                try self.setScroll(id, props);
            },
            @intFromEnum(PropKey.Anchor) => {
                const value_type = args.typeAt(index + 1) orelse return error.InvalidPatch;
                if (value_type == .nil) continue;
                const props_opt = args.at(luaz.Lua.Table, index + 1);
                if (props_opt == null) return error.InvalidPatch;
                var props = props_opt.?;
                defer props.deinit();
                try self.setAnchor(id, props);
            },
            @intFromEnum(PropKey.Image) => {
                const value_type = args.typeAt(index + 1) orelse return error.InvalidPatch;
                if (value_type == .nil) continue;
                const props_opt = args.at(luaz.Lua.Table, index + 1);
                if (props_opt == null) return error.InvalidPatch;
                var props = props_opt.?;
                defer props.deinit();
                try self.setImage(id, props);
            },
            @intFromEnum(PropKey.Src) => {
                const src_opt = args.at([]const u8, index + 1);
                if (src_opt == null) return error.InvalidPatch;
                try self.setSrc(id, src_opt.?);
            },
            else => return error.InvalidPatch,
        }
    }
}

fn resetStore(self: *Self) !void {
    const allocator = self.store.allocator;
    self.store.deinit();
    try self.store.init(allocator);
}

fn createNode(self: *Self, tag: []const u8, id: u32, parent: ?u32, before: ?u32) !void {
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

fn removeNode(self: *Self, id: u32) !void {
    if (id == 0) return error.MissingId;
    self.store.remove(id);
}

fn insertNode(self: *Self, id: u32, parent: ?u32, before: ?u32) !void {
    if (id == 0) return error.MissingId;
    const parent_id = parent orelse return error.MissingParent;
    if (self.store.node(id) == null) return error.MissingChild;
    if (self.store.node(parent_id) == null) return error.MissingParent;
    try self.store.insert(parent_id, id, before);
}

fn setText(self: *Self, id: u32, text: []const u8) !void {
    if (id == 0) return error.MissingId;
    try self.store.setTextNode(id, text);
}

fn setInput(self: *Self, id: u32, text: []const u8) !void {
    if (id == 0) return error.MissingId;
    try self.store.setInputValue(id, text);
}

fn setClass(self: *Self, id: u32, class_name: []const u8) !void {
    if (id == 0) return error.MissingId;
    try self.store.setClassName(id, class_name);
}

fn setSrc(self: *Self, id: u32, src: []const u8) !void {
    if (id == 0) return error.MissingId;
    try self.store.setImageSource(id, src);
}

fn setImage(self: *Self, id: u32, props: luaz.Lua.Table) !void {
    if (id == 0) return error.MissingId;
    const target = self.store.node(id) orelse return error.MissingId;
    if (try readOptionalField([]const u8, props, "src")) |value| {
        if (!std.mem.eql(u8, target.image_src, value)) {
            try self.store.setImageSource(id, value);
        }
    }

    // Optional image-only properties (no-op on stores that don't implement them).
    if (try readOptionalField(u32, props, "tint")) |value| {
        if (@hasDecl(retained.NodeStore, "setImageTint")) {
            if (target.image_tint == null or target.image_tint.?.value != value) {
                try self.store.setImageTint(id, value);
            }
        }
    }
    if (try readOptionalField(f32, props, "opacity")) |value| {
        if (@hasDecl(retained.NodeStore, "setImageOpacity")) {
            if (target.image_opacity != value) {
                try self.store.setImageOpacity(id, value);
            }
        }
    }
}

fn setVisual(self: *Self, id: u32, props: luaz.Lua.Table) !void {
    if (id == 0) return error.MissingId;
    const target = self.store.node(id) orelse return error.MissingId;
    var changed = false;
    if (try readOptionalField(f32, props, "opacity")) |value| {
        if (target.visual_props.opacity != value) {
            target.visual_props.opacity = value;
            changed = true;
        }
    }
    if (try readOptionalField(f32, props, "cornerRadius")) |value| {
        if (target.visual_props.corner_radius != value) {
            target.visual_props.corner_radius = value;
            changed = true;
        }
    }
    if (try readOptionalField(u32, props, "background")) |value| {
        if (target.visual_props.background == null or target.visual_props.background.?.value != value) {
            target.visual_props.background = .{ .value = value };
            changed = true;
        }
    }
    if (try readOptionalField(u32, props, "textColor")) |value| {
        if (target.visual_props.text_color == null or target.visual_props.text_color.?.value != value) {
            target.visual_props.text_color = .{ .value = value };
            changed = true;
        }
    }
    if (try readOptionalField(u32, props, "textOutlineColor")) |value| {
        if (target.visual_props.text_outline_color == null or target.visual_props.text_outline_color.?.value != value) {
            target.visual_props.text_outline_color = .{ .value = value };
            changed = true;
        }
    }
    if (try readOptionalField(f32, props, "textOutlineThickness")) |value| {
        if (target.visual_props.text_outline_thickness != value) {
            target.visual_props.text_outline_thickness = value;
            changed = true;
        }
    }
    if (try readOptionalField([]const u8, props, "fontRenderMode")) |value| {
        if (std.mem.eql(u8, value, "auto")) {
            self.store.setFontRenderMode(id, null);
        } else if (parseFontRenderMode(value)) |mode| {
            self.store.setFontRenderMode(id, mode);
        }
    }
    if (try readOptionalField(bool, props, "clipChildren")) |value| {
        if (target.visual_props.clip_children != value) {
            target.visual_props.clip_children = value;
            changed = true;
        }
    }
    if (changed) {
        self.store.markNodePaintChanged(id);
    }
}

fn setTransform(self: *Self, id: u32, props: luaz.Lua.Table) !void {
    if (id == 0) return error.MissingId;
    const target = self.store.node(id) orelse return error.MissingId;
    var changed = false;
    if (try readOptionalField(f32, props, "scale")) |value| {
        if (target.transform.scale[0] != value or target.transform.scale[1] != value) {
            target.transform.scale = .{ value, value };
            changed = true;
        }
    }
    if (try readOptionalField(f32, props, "rotation")) |value| {
        if (target.transform.rotation != value) {
            target.transform.rotation = value;
            changed = true;
        }
    }
    if (try readOptionalField(f32, props, "scaleX")) |value| {
        if (target.transform.scale[0] != value) {
            target.transform.scale[0] = value;
            changed = true;
        }
    }
    if (try readOptionalField(f32, props, "scaleY")) |value| {
        if (target.transform.scale[1] != value) {
            target.transform.scale[1] = value;
            changed = true;
        }
    }
    if (try readOptionalField(f32, props, "anchorX")) |value| {
        if (target.transform.anchor[0] != value) {
            target.transform.anchor[0] = value;
            changed = true;
        }
    }
    if (try readOptionalField(f32, props, "anchorY")) |value| {
        if (target.transform.anchor[1] != value) {
            target.transform.anchor[1] = value;
            changed = true;
        }
    }
    if (try readOptionalField(f32, props, "translateX")) |value| {
        if (target.transform.translation[0] != value) {
            target.transform.translation[0] = value;
            changed = true;
        }
    }
    if (try readOptionalField(f32, props, "translateY")) |value| {
        if (target.transform.translation[1] != value) {
            target.transform.translation[1] = value;
            changed = true;
        }
    }
    if (changed) {
        self.store.markNodePaintChanged(id);
    }
}

fn setScroll(self: *Self, id: u32, props: luaz.Lua.Table) !void {
    if (id == 0) return error.MissingId;
    const target = self.store.node(id) orelse return error.MissingId;
    var changed = false;
    if (try readOptionalField(bool, props, "enabled")) |value| {
        if (target.scroll.enabled != value) {
            target.scroll.enabled = value;
            changed = true;
        }
    }
    if (try readOptionalField(f32, props, "scrollX")) |value| {
        if (target.scroll.offset_x != value) {
            target.scroll.offset_x = value;
            changed = true;
        }
    }
    if (try readOptionalField(f32, props, "scrollY")) |value| {
        if (target.scroll.offset_y != value) {
            target.scroll.offset_y = value;
            changed = true;
        }
    }
    if (try readOptionalField(f32, props, "canvasWidth")) |value| {
        if (target.scroll.canvas_width != value) {
            target.scroll.canvas_width = value;
            changed = true;
        }
    }
    if (try readOptionalField(f32, props, "canvasHeight")) |value| {
        if (target.scroll.canvas_height != value) {
            target.scroll.canvas_height = value;
            changed = true;
        }
    }
    if (try readOptionalField(bool, props, "autoCanvas")) |value| {
        if (target.scroll.auto_canvas != value) {
            target.scroll.auto_canvas = value;
            changed = true;
        }
    }
    if (changed) {
        self.store.markNodeChanged(id);
    }
}

fn setAnchor(self: *Self, id: u32, props: luaz.Lua.Table) !void {
    if (id == 0) return error.MissingId;
    const target = self.store.node(id) orelse return error.MissingId;
    var changed = false;
    if (try readOptionalField(u32, props, "anchorId")) |value| {
        if (target.anchor_id == null or target.anchor_id.? != value) {
            target.anchor_id = value;
            changed = true;
        }
    }
    if (try readOptionalField([]const u8, props, "side")) |value| {
        if (parseAnchorSide(value)) |side| {
            if (target.anchor_side != side) {
                target.anchor_side = side;
                changed = true;
            }
        }
    }
    if (try readOptionalField([]const u8, props, "align")) |value| {
        if (parseAnchorAlign(value)) |alignment| {
            if (target.anchor_align != alignment) {
                target.anchor_align = alignment;
                changed = true;
            }
        }
    }
    if (try readOptionalField(f32, props, "offset")) |value| {
        if (target.anchor_offset != value) {
            target.anchor_offset = value;
            changed = true;
        }
    }
    if (changed) {
        self.store.markNodeChanged(id);
    }
}

fn addListenerKind(self: *Self, id: u32, kind: u32) !void {
    if (id == 0) return error.MissingId;
    const parsed = retained.events.eventKindFromInt(kind) orelse return error.InvalidEvent;
    try self.store.addListenerKind(id, parsed);
}
};
