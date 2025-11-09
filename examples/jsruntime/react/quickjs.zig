const std = @import("std");
const quickjs = @import("quickjs");
const dvui = @import("dvui");
const jsruntime = @import("../mod.zig");

const types = @import("types.zig");
const utils = @import("utils.zig");

pub fn buildReactCommandGraph(
    runtime: *jsruntime.JSRuntime,
    nodes: *types.ReactCommandMap,
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

        var command = types.ReactCommand{
            .command_type = node_type,
        };

        if (std.mem.eql(u8, node_type, "text-content")) {
            command.text = try dupOptionalPropertyString(ctx, allocator, command_const, "text");
        } else {
            command.children = try readChildIdList(ctx, allocator, command_const, &referenced_children);
        }

        command.style = try readCommandStyle(ctx, command_const);
        command.flex = try readFlexProps(ctx, allocator, command_const);
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
    ctx: *quickjs.JSContext,
    obj: quickjs.JSValueConst,
) !types.ReactCommandStyle {
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
        .background = try readStyleColor(ctx, style_const, "backgroundColor"),
        .text = try readStyleColor(ctx, style_const, "textColor"),
        .width = try readStyleWidth(ctx, style_const),
    };
}

fn readFlexProps(
    ctx: *quickjs.JSContext,
    allocator: std.mem.Allocator,
    obj: quickjs.JSValueConst,
) !?types.ReactFlexProps {
    const props_prop = "props\x00";
    const props_value = quickjs.JS_GetPropertyStr(ctx, obj, @ptrCast(props_prop.ptr));
    defer quickjs.JS_FreeValue(ctx, props_value);
    const props_const = quickjs.asValueConst(props_value);
    if (quickjs.JS_IsException(props_const)) {
        return error.JsError;
    }
    if (quickjs.JS_IsUndefined(props_const) or quickjs.JS_IsNull(props_const)) {
        return null;
    }
    if (!quickjs.JS_IsObject(props_const)) {
        return error.InvalidRenderTree;
    }

    var result = types.ReactFlexProps{};
    var has_value = false;

    result.direction = try dupOptionalPropertyString(ctx, allocator, props_const, "flexDirection");
    if (result.direction != null) has_value = true;

    result.justify_content = try dupOptionalPropertyString(ctx, allocator, props_const, "justifyContent");
    if (result.justify_content != null) has_value = true;

    result.align_items = try dupOptionalPropertyString(ctx, allocator, props_const, "alignItems");
    if (result.align_items != null) has_value = true;

    result.align_content = try dupOptionalPropertyString(ctx, allocator, props_const, "alignContent");
    if (result.align_content != null) has_value = true;

    if (!has_value) {
        return null;
    }
    return result;
}

fn readStyleColor(
    ctx: *quickjs.JSContext,
    style_obj: quickjs.JSValueConst,
    comptime name: []const u8,
) !?dvui.Color {
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
    return utils.colorFromPacked(_packed);
}

fn readStyleWidth(
    ctx: *quickjs.JSContext,
    style_obj: quickjs.JSValueConst,
) !?types.ReactWidth {
    const prop = "width\x00";
    const value = quickjs.JS_GetPropertyStr(ctx, style_obj, @ptrCast(prop.ptr));
    defer quickjs.JS_FreeValue(ctx, value);
    const value_const = quickjs.asValueConst(value);
    if (quickjs.JS_IsException(value_const)) {
        return error.JsError;
    }
    if (quickjs.JS_IsUndefined(value_const) or quickjs.JS_IsNull(value_const)) {
        return null;
    }
    if (quickjs.JS_IsString(value_const)) {
        var length: usize = 0;
        const ptr = quickjs.JS_ToCStringLen(ctx, &length, value_const) orelse {
            return error.JsError;
        };
        defer quickjs.JS_FreeCString(ctx, ptr);
        const slice = ptr[0..length];
        if (std.mem.eql(u8, slice, "full")) return .full;
        return null;
    }

    var raw: f64 = 0;
    if (quickjs.JS_ToFloat64(ctx, &raw, value_const) != 0) {
        return error.InvalidRenderTree;
    }
    if (raw < 0) {
        return error.InvalidRenderTree;
    }
    const max_allowed: f64 = @floatCast(dvui.max_float_safe);
    const clamped = @min(raw, max_allowed);
    return types.ReactWidth{ .pixels = @floatCast(clamped) };
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
