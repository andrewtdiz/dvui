//! Utilities for rendering the QuickJS-backed React snapshot inside dvui.

const std = @import("std");
const quickjs = @import("quickjs");
const jsruntime = @import("mod.zig");

const log = std.log.scoped(.react_bridge);

pub fn render(comptime Dvui: type, runtime: *jsruntime.JSRuntime) void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    const allocator = arena.allocator();

    var nodes = ReactCommandMap(Dvui).init(allocator);
    defer nodes.deinit();
    var root_ids: std.ArrayList([]const u8) = .empty;
    defer root_ids.deinit(allocator);

    buildReactCommandGraph(Dvui, runtime, &nodes, &root_ids, allocator) catch |err| {
        switch (err) {
            error.MissingRenderTree => {},
            else => log.err("React bridge build failed: {s}", .{@errorName(err)}),
        }
        return;
    };

    if (root_ids.items.len == 0) {
        return;
    }

    var root_container = Dvui.box(@src(), .{}, .{
        .expand = .both,
        .name = "ReactBridgeRoot",
        .padding = .{ .x = 16, .y = 16 },
    });
    defer root_container.deinit();

    for (root_ids.items) |node_id| {
        renderReactNode(Dvui, runtime, &nodes, node_id);
    }
}

fn ReactCommandStyle(comptime Dvui: type) type {
    return struct {
        background: ?Dvui.Color = null,
        text: ?Dvui.Color = null,
    };
}

fn ReactCommand(comptime Dvui: type) type {
    return struct {
        command_type: []const u8,
        text: ?[]const u8 = null,
        text_content: ?[]const u8 = null,
        children: []const []const u8 = &.{},
        on_click_id: ?[]const u8 = null,
        style: ReactCommandStyle(Dvui) = .{},
    };
}

fn ReactCommandMap(comptime Dvui: type) type {
    return std.StringHashMap(ReactCommand(Dvui));
}

fn renderReactNode(
    comptime Dvui: type,
    runtime: *jsruntime.JSRuntime,
    nodes: *const ReactCommandMap(Dvui),
    node_id: []const u8,
) void {
    const entry = nodes.get(node_id) orelse return;
    if (std.mem.eql(u8, entry.command_type, "box")) {
        var box_options = Dvui.Options{
            .name = "ReactBox",
            .background = true,
            .padding = .{ .x = 8, .y = 8 },
        };

        if (entry.style.background) |color| {
            box_options.color_fill = color;
            box_options.background = true;
        }

        var box_widget = Dvui.box(@src(), .{}, box_options);
        defer box_widget.deinit();
        for (entry.children) |child_id| {
            renderReactNode(Dvui, runtime, nodes, child_id);
        }
        return;
    }

    if (std.mem.eql(u8, entry.command_type, "label")) {
        renderLabelNode(Dvui, runtime, nodes, node_id, entry);
        return;
    }

    if (std.mem.eql(u8, entry.command_type, "button")) {
        renderButtonNode(Dvui, runtime, nodes, node_id, entry);
        return;
    }

    if (std.mem.eql(u8, entry.command_type, "text-content")) {
        const content = entry.text orelse "";
        var tl = Dvui.textLayout(@src(), .{}, .{ .expand = .horizontal, .background = false });
        tl.addText(content, .{});
        tl.deinit();
        return;
    }

    for (entry.children) |child_id| {
        renderReactNode(Dvui, runtime, nodes, child_id);
    }
}

fn renderLabelNode(
    comptime Dvui: type,
    runtime: *jsruntime.JSRuntime,
    nodes: *const ReactCommandMap(Dvui),
    node_id: []const u8,
    entry: ReactCommand(Dvui),
) void {
    const content = entry.text_content orelse resolveCommandText(nodes, entry.children);

    var label_opts = Dvui.Options{};
    label_opts.id_extra = nodeIdExtra(node_id);
    if (entry.style.text) |color| {
        label_opts.color_text = color;
    }

    Dvui.labelNoFmt(@src(), content, .{}, label_opts);

    for (entry.children) |child_id| {
        const child_entry = nodes.get(child_id) orelse continue;
        if (std.mem.eql(u8, child_entry.command_type, "text-content")) continue;
        renderReactNode(Dvui, runtime, nodes, child_id);
    }
}

fn renderButtonNode(
    comptime Dvui: type,
    runtime: *jsruntime.JSRuntime,
    nodes: *const ReactCommandMap(Dvui),
    node_id: []const u8,
    entry: ReactCommand(Dvui),
) void {
    const caption = entry.text_content orelse resolveCommandText(nodes, entry.children);

    var button_opts = Dvui.Options{};
    button_opts.id_extra = nodeIdExtra(node_id);
    if (entry.style.background) |color| {
        button_opts.color_fill = color;
        button_opts.background = true;
    }
    if (entry.style.text) |color| {
        button_opts.color_text = color;
    }

    const pressed = Dvui.button(@src(), caption, .{}, button_opts);
    if (pressed) {
        if (entry.on_click_id) |listener_id| {
            runtime.invokeListener(listener_id) catch |err| {
                log.err("React onClick failed: {s}", .{@errorName(err)});
            };
        }
    }

    for (entry.children) |child_id| {
        const child_entry = nodes.get(child_id) orelse continue;
        if (std.mem.eql(u8, child_entry.command_type, "text-content")) continue;
        renderReactNode(Dvui, runtime, nodes, child_id);
    }
}

fn resolveCommandText(nodes: anytype, child_ids: []const []const u8) []const u8 {
    for (child_ids) |child_id| {
        const child = nodes.get(child_id) orelse continue;
        if (!std.mem.eql(u8, child.command_type, "text-content")) continue;
        if (child.text) |text| {
            return text;
        }
    }
    return "";
}

fn nodeIdExtra(node_id: []const u8) usize {
    const hash: u64 = std.hash.Wyhash.hash(0, node_id);
    return @intCast(hash & std.math.maxInt(usize));
}

fn buildReactCommandGraph(
    comptime Dvui: type,
    runtime: *jsruntime.JSRuntime,
    nodes: *ReactCommandMap(Dvui),
    root_ids: *std.ArrayList([]const u8),
    allocator: std.mem.Allocator,
) !void {
    const ctx = try runtime.acquireContext();

    const global = quickjs.JS_GetGlobalObject(ctx);
    defer quickjs.JS_FreeValue(ctx, global);
    const global_const = quickjs.asValueConst(global);

    const app_name = "dvuiApp\x00";
    const app_value = quickjs.JS_GetPropertyStr(ctx, global_const, @ptrCast(app_name.ptr));
    defer quickjs.JS_FreeValue(ctx, app_value);
    const app_const = quickjs.asValueConst(app_value);
    if (quickjs.JS_IsException(app_const)) {
        runtime.warnLastException("dvuiApp.lookup");
        return error.JsError;
    }
    if (!quickjs.JS_IsObject(app_const)) {
        return error.MissingRenderTree;
    }

    const commands_prop = "commands\x00";
    const commands_value = quickjs.JS_GetPropertyStr(ctx, app_const, @ptrCast(commands_prop.ptr));
    defer quickjs.JS_FreeValue(ctx, commands_value);
    const commands_const = quickjs.asValueConst(commands_value);
    if (quickjs.JS_IsException(commands_const)) {
        runtime.warnLastException("dvuiApp.commands.lookup");
        return error.JsError;
    }
    if (!quickjs.JS_IsArray(commands_const)) {
        return error.MissingRenderTree;
    }

    const command_length = try jsArrayLength(ctx, commands_const);
    if (command_length == 0) {
        return;
    }

    var referenced_children = std.StringHashMap(void).init(allocator);
    defer referenced_children.deinit();

    var index_buf: [32]u8 = undefined;
    var idx: usize = 0;
    while (idx < command_length) : (idx += 1) {
        const command_value = try jsArrayGet(ctx, commands_const, idx, &index_buf);
        defer quickjs.JS_FreeValue(ctx, command_value);
        const command_const = quickjs.asValueConst(command_value);
        if (!quickjs.JS_IsObject(command_const)) continue;

        const id = try dupPropertyString(ctx, allocator, command_const, "id");
        const node_type = try dupPropertyString(ctx, allocator, command_const, "type");

        var command = ReactCommand(Dvui){
            .command_type = node_type,
        };

        if (std.mem.eql(u8, node_type, "text-content")) {
            command.text = try dupOptionalPropertyString(ctx, allocator, command_const, "text");
        } else {
            command.children = try readChildIdList(ctx, allocator, command_const, &referenced_children);
        }

        command.style = try readCommandStyle(Dvui, ctx, command_const);
        command.text_content = try dupOptionalPropertyString(ctx, allocator, command_const, "textContent");
        command.on_click_id = try dupOptionalPropertyString(ctx, allocator, command_const, "onClickId");

        try nodes.put(id, command);
    }

    if (try extractRootIdsFromJs(ctx, app_const, allocator, root_ids)) {
        return;
    }

    var iter = nodes.iterator();
    while (iter.next()) |entry| {
        if (!referenced_children.contains(entry.key_ptr.*)) {
            try root_ids.append(allocator, entry.key_ptr.*);
        }
    }
}

fn jsArrayLength(ctx: *quickjs.JSContext, array_const: quickjs.JSValueConst) !usize {
    const length_prop = "length\x00";
    const length_value = quickjs.JS_GetPropertyStr(ctx, array_const, @ptrCast(length_prop.ptr));
    defer quickjs.JS_FreeValue(ctx, length_value);
    const length_const = quickjs.asValueConst(length_value);
    if (quickjs.JS_IsException(length_const)) {
        return error.JsError;
    }
    var raw: f64 = 0;
    if (quickjs.JS_ToFloat64(ctx, &raw, length_const) < 0) {
        return error.JsError;
    }
    if (raw <= 0) return 0;
    const floored = std.math.floor(raw);
    const max_len = @as(f64, @floatFromInt(std.math.maxInt(usize)));
    const clamped = if (floored > max_len) max_len else floored;
    return @intFromFloat(clamped);
}

fn jsArrayGet(
    ctx: *quickjs.JSContext,
    array_const: quickjs.JSValueConst,
    index: usize,
    buffer: *[32]u8,
) !quickjs.JSValue {
    const index_str = try std.fmt.bufPrintZ(buffer, "{d}", .{index});
    const ptr: [*c]const u8 = @ptrCast(index_str.ptr);
    const value = quickjs.JS_GetPropertyStr(ctx, array_const, ptr);
    const value_const = quickjs.asValueConst(value);
    if (quickjs.JS_IsException(value_const)) {
        quickjs.JS_FreeValue(ctx, value);
        return error.JsError;
    }
    return value;
}

fn dupPropertyString(
    ctx: *quickjs.JSContext,
    allocator: std.mem.Allocator,
    obj: quickjs.JSValueConst,
    comptime name: []const u8,
) ![]const u8 {
    const prop = name ++ "\x00";
    const value = quickjs.JS_GetPropertyStr(ctx, obj, @ptrCast(prop.ptr));
    defer quickjs.JS_FreeValue(ctx, value);
    const value_const = quickjs.asValueConst(value);
    if (quickjs.JS_IsException(value_const)) {
        return error.JsError;
    }
    if (!quickjs.JS_IsString(value_const)) {
        return error.InvalidRenderTree;
    }
    return try dupJsStringValue(ctx, allocator, value_const);
}

fn dupOptionalPropertyString(
    ctx: *quickjs.JSContext,
    allocator: std.mem.Allocator,
    obj: quickjs.JSValueConst,
    comptime name: []const u8,
) !?[]const u8 {
    const prop = name ++ "\x00";
    const value = quickjs.JS_GetPropertyStr(ctx, obj, @ptrCast(prop.ptr));
    defer quickjs.JS_FreeValue(ctx, value);
    const value_const = quickjs.asValueConst(value);
    if (quickjs.JS_IsException(value_const)) {
        return error.JsError;
    }
    if (quickjs.JS_IsUndefined(value_const) or quickjs.JS_IsNull(value_const)) {
        return null;
    }
    if (!quickjs.JS_IsString(value_const)) {
        return error.InvalidRenderTree;
    }
    return try dupJsStringValue(ctx, allocator, value_const);
}

fn readCommandStyle(
    comptime Dvui: type,
    ctx: *quickjs.JSContext,
    obj: quickjs.JSValueConst,
) !ReactCommandStyle(Dvui) {
    const style_prop = "style\x00";
    const style_value = quickjs.JS_GetPropertyStr(ctx, obj, @ptrCast(style_prop.ptr));
    defer quickjs.JS_FreeValue(ctx, style_value);
    const style_const = quickjs.asValueConst(style_value);
    if (quickjs.JS_IsException(style_const)) {
        return error.JsError;
    }
    if (quickjs.JS_IsUndefined(style_const) or quickjs.JS_IsNull(style_const)) {
        return .{};
    }
    if (!quickjs.JS_IsObject(style_const)) {
        return error.InvalidRenderTree;
    }

    return .{
        .background = try readStyleColor(Dvui, ctx, style_const, "backgroundColor"),
        .text = try readStyleColor(Dvui, ctx, style_const, "textColor"),
    };
}

fn readStyleColor(
    comptime Dvui: type,
    ctx: *quickjs.JSContext,
    style_obj: quickjs.JSValueConst,
    comptime name: []const u8,
) !?Dvui.Color {
    const prop = name ++ "\x00";
    const value = quickjs.JS_GetPropertyStr(ctx, style_obj, @ptrCast(prop.ptr));
    defer quickjs.JS_FreeValue(ctx, value);
    const value_const = quickjs.asValueConst(value);
    if (quickjs.JS_IsException(value_const)) {
        return error.JsError;
    }
    if (quickjs.JS_IsUndefined(value_const) or quickjs.JS_IsNull(value_const)) {
        return null;
    }

    var _packed: u32 = 0;
    if (quickjs.JS_ToUint32(ctx, &_packed, value_const) != 0) {
        return error.InvalidRenderTree;
    }
    return colorFromPacked(Dvui, _packed);
}

fn dupJsStringValue(
    ctx: *quickjs.JSContext,
    allocator: std.mem.Allocator,
    value: quickjs.JSValueConst,
) ![]const u8 {
    var length: usize = 0;
    const ptr = quickjs.JS_ToCStringLen(ctx, &length, value) orelse {
        return error.JsError;
    };
    defer quickjs.JS_FreeCString(ctx, ptr);
    const slice = ptr[0..length];
    const copy = try allocator.alloc(u8, slice.len);
    @memcpy(copy, slice);
    return copy;
}

fn readChildIdList(
    ctx: *quickjs.JSContext,
    allocator: std.mem.Allocator,
    obj: quickjs.JSValueConst,
    referenced_children: *std.StringHashMap(void),
) ![]const []const u8 {
    const children_prop = "children\x00";
    const children_value = quickjs.JS_GetPropertyStr(ctx, obj, @ptrCast(children_prop.ptr));
    defer quickjs.JS_FreeValue(ctx, children_value);
    const children_const = quickjs.asValueConst(children_value);
    if (quickjs.JS_IsException(children_const)) {
        return error.JsError;
    }
    if (quickjs.JS_IsUndefined(children_const) or quickjs.JS_IsNull(children_const)) {
        return &.{};
    }
    if (!quickjs.JS_IsArray(children_const)) {
        return error.InvalidRenderTree;
    }

    const len = try jsArrayLength(ctx, children_const);
    if (len == 0) return &.{};

    const list = try allocator.alloc([]const u8, len);
    var idx_buf: [32]u8 = undefined;
    var i: usize = 0;
    while (i < len) : (i += 1) {
        const child_value = try jsArrayGet(ctx, children_const, i, &idx_buf);
        defer quickjs.JS_FreeValue(ctx, child_value);
        const child_const = quickjs.asValueConst(child_value);
        const child_id = try dupJsStringValue(ctx, allocator, child_const);
        list[i] = child_id;
        try referenced_children.put(child_id, {});
    }
    return list;
}

fn extractRootIdsFromJs(
    ctx: *quickjs.JSContext,
    app_const: quickjs.JSValueConst,
    allocator: std.mem.Allocator,
    root_ids: *std.ArrayList([]const u8),
) !bool {
    const roots_prop = "rootIds\x00";
    const roots_value = quickjs.JS_GetPropertyStr(ctx, app_const, @ptrCast(roots_prop.ptr));
    defer quickjs.JS_FreeValue(ctx, roots_value);
    const roots_const = quickjs.asValueConst(roots_value);
    if (quickjs.JS_IsException(roots_const)) {
        return error.JsError;
    }
    if (quickjs.JS_IsUndefined(roots_const) or quickjs.JS_IsNull(roots_const)) {
        return false;
    }
    if (!quickjs.JS_IsArray(roots_const)) {
        return false;
    }

    const len = try jsArrayLength(ctx, roots_const);
    if (len == 0) {
        return true;
    }

    var idx_buf: [32]u8 = undefined;
    var i: usize = 0;
    while (i < len) : (i += 1) {
        const root_value = try jsArrayGet(ctx, roots_const, i, &idx_buf);
        defer quickjs.JS_FreeValue(ctx, root_value);
        const root_const = quickjs.asValueConst(root_value);
        if (!quickjs.JS_IsString(root_const)) {
            return error.InvalidRenderTree;
        }
        const copy = try dupJsStringValue(ctx, allocator, root_const);
        try root_ids.append(allocator, copy);
    }

    return true;
}

fn colorFromPacked(comptime Dvui: type, value: u32) Dvui.Color {
    const r: u8 = @intCast((value >> 24) & 0xff);
    const g: u8 = @intCast((value >> 16) & 0xff);
    const b: u8 = @intCast((value >> 8) & 0xff);
    const a: u8 = @intCast(value & 0xff);
    return Dvui.Color{ .r = r, .g = g, .b = b, .a = a };
}
