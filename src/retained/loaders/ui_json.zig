const std = @import("std");

const types = @import("../core/types.zig");
const events = @import("../events/mod.zig");

const UiLayout = struct {
    x: f32,
    y: f32,
    width: f32,
    height: f32,
};

const UiAnchorHorizontal = enum {
    left,
    center,
    right,
};

const UiAnchorVertical = enum {
    top,
    center,
    bottom,
};

const UiAnchor = struct {
    horizontal: UiAnchorHorizontal,
    vertical: UiAnchorVertical,
};

pub fn setSnapshotFromUiJsonValue(
    store: *types.NodeStore,
    ring: ?*events.EventRing,
    ui_value: std.json.Value,
    root_w: f32,
    root_h: f32,
) bool {
    if (!std.math.isFinite(root_w) or !std.math.isFinite(root_h)) return false;
    if (root_w <= 0 or root_h <= 0) return false;
    if (ui_value != .object) return false;
    const elements_val = ui_value.object.get("elements") orelse return false;
    if (elements_val != .object) return false;

    const allocator = store.allocator;
    store.deinit();
    store.init(allocator) catch return false;
    if (ring) |r| {
        r.reset();
    }

    var next_id: u32 = 1;
    const root_layout = UiLayout{ .x = 0, .y = 0, .width = root_w, .height = root_h };
    applyUiElements(store, elements_val.object, root_layout, 0, "", &next_id);
    return true;
}

fn applyUiElements(
    store: *types.NodeStore,
    elements_obj: std.json.ObjectMap,
    parent_layout: UiLayout,
    parent_id: u32,
    parent_path: []const u8,
    next_id: *u32,
) void {
    var it = elements_obj.iterator();
    while (it.next()) |entry| {
        const element_key = entry.key_ptr.*;
        const element_val = entry.value_ptr.*;
        applyUiElement(store, element_key, parent_path, element_val, parent_layout, parent_id, next_id);
    }
}

fn applyUiElement(
    store: *types.NodeStore,
    element_key: []const u8,
    parent_path: []const u8,
    element_val: std.json.Value,
    parent_layout: UiLayout,
    parent_id: u32,
    next_id: *u32,
) void {
    if (element_val != .object) return;
    const obj = element_val.object;
    const allocator = store.allocator;

    var raw_tag: []const u8 = "div";
    var is_text_element = false;
    if (obj.get("type")) |type_val| {
        if (type_val == .string) {
            raw_tag = parseUiTag(type_val.string);
            is_text_element = std.mem.eql(u8, raw_tag, "text");
        }
    }

    const layout = readUiLayout(obj, parent_layout);

    var owned_full_path: ?[]u8 = null;
    const full_path = blk: {
        if (parent_path.len == 0) break :blk element_key;
        const joined = std.fmt.allocPrint(allocator, "{s}.{s}", .{ parent_path, element_key }) catch return;
        owned_full_path = joined;
        break :blk joined;
    };
    defer if (owned_full_path) |buf| allocator.free(buf);

    const base_class_name = std.fmt.allocPrint(
        allocator,
        "absolute left-[{}] top-[{}] w-[{}] h-[{}]",
        .{ layout.x, layout.y, layout.width, layout.height },
    ) catch return;
    defer allocator.free(base_class_name);

    const key_token = std.fmt.allocPrint(allocator, "ui-key-{s}", .{element_key}) catch return;
    defer allocator.free(key_token);

    const path_token = std.fmt.allocPrint(allocator, "ui-path-{s}", .{full_path}) catch return;
    defer allocator.free(path_token);

    var class_tokens: std.ArrayList([]const u8) = .empty;
    defer class_tokens.deinit(allocator);
    class_tokens.append(allocator, base_class_name) catch return;
    class_tokens.append(allocator, key_token) catch return;
    class_tokens.append(allocator, path_token) catch return;

    if (fontFamilyToken(obj)) |token| {
        class_tokens.append(allocator, token) catch {};
    }
    appendFontWeightToken(obj, &class_tokens, allocator);
    appendFontItalicToken(obj, &class_tokens, allocator);
    appendFontRenderToken(obj, &class_tokens, allocator);

    var class_name = std.mem.join(allocator, " ", class_tokens.items) catch return;
    defer allocator.free(class_name);

    const font_size_value = readUiFontSize(obj);
    if (font_size_value) |size| {
        const token = fontSizeToken(size);
        const combined = std.fmt.allocPrint(allocator, "{s} {s}", .{ class_name, token }) catch return;
        allocator.free(class_name);
        class_name = combined;
    }

    const id = next_id.*;
    next_id.* +%= 1;

    const tag = if (is_text_element) "p" else raw_tag;
    store.upsertElement(id, tag) catch return;
    store.insert(parent_id, id, null) catch {};
    store.setClassName(id, class_name) catch {};

    if (obj.get("color")) |color_val| {
        if (readColor(color_val)) |packed_value| {
            if (store.node(id)) |node| {
                var changed = false;
                if (is_text_element) {
                    node.visual_props.text_color = .{ .value = packed_value };
                    changed = true;
                } else {
                    node.visual_props.background = .{ .value = packed_value };
                    changed = true;
                }
                if (changed) {
                    node.invalidatePaint();
                    store.markNodeChanged(id);
                }
            }
        }
    }

    if (obj.get("src")) |src_val| {
        if (src_val == .string) {
            store.setImageSource(id, src_val.string) catch {};
        }
    }

    const input_value = blk: {
        if (obj.get("value")) |value_val| {
            if (value_val == .string) break :blk value_val.string;
        }
        if (std.mem.eql(u8, raw_tag, "input")) {
            if (obj.get("text")) |text_val| {
                if (text_val == .string) break :blk text_val.string;
            }
        }
        break :blk null;
    };
    if (input_value) |value| {
        store.setInputValue(id, value) catch {};
    }

    if (is_text_element) {
        const text_id: u32 = 0x80000000 | id;
        const content = blk: {
            if (obj.get("text")) |text_val| {
                if (text_val == .string) break :blk text_val.string;
            }
            break :blk "";
        };
        store.setTextNode(text_id, content) catch {};
        store.insert(id, text_id, null) catch {};
    }

    if (obj.get("children")) |children_val| {
        if (children_val == .object) {
            applyUiElements(store, children_val.object, layout, id, full_path, next_id);
        }
    }
}

fn readUiLayout(obj: std.json.ObjectMap, parent_layout: UiLayout) UiLayout {
    var layout: UiLayout = .{ .x = 0, .y = 0, .width = 0, .height = 0 };
    if (obj.get("size")) |size_val| {
        if (readSizeObject(size_val)) |size| {
            layout.width = size[0];
            layout.height = size[1];
        }
    }
    const anchor = readUiAnchor(obj);
    const pos = readUiPosition(obj, parent_layout);
    const local_x = switch (anchor.horizontal) {
        .left => pos[0],
        .center => (parent_layout.width * 0.5) - (layout.width * 0.5) + pos[0],
        .right => parent_layout.width - layout.width - pos[0],
    };
    const local_y = switch (anchor.vertical) {
        .top => pos[1],
        .center => (parent_layout.height * 0.5) - (layout.height * 0.5) + pos[1],
        .bottom => parent_layout.height - layout.height - pos[1],
    };
    layout.x = local_x;
    layout.y = local_y;
    return layout;
}

fn readUiAnchor(obj: std.json.ObjectMap) UiAnchor {
    const anchor = UiAnchor{ .horizontal = .left, .vertical = .top };
    const anchor_val = obj.get("anchor") orelse return anchor;
    if (anchor_val != .string) return anchor;
    const name = anchor_val.string;
    if (std.mem.eql(u8, name, "top_left")) return anchor;
    if (std.mem.eql(u8, name, "top_center")) return .{ .horizontal = .center, .vertical = .top };
    if (std.mem.eql(u8, name, "top_right")) return .{ .horizontal = .right, .vertical = .top };
    if (std.mem.eql(u8, name, "center_left")) return .{ .horizontal = .left, .vertical = .center };
    if (std.mem.eql(u8, name, "center")) return .{ .horizontal = .center, .vertical = .center };
    if (std.mem.eql(u8, name, "center_right")) return .{ .horizontal = .right, .vertical = .center };
    if (std.mem.eql(u8, name, "bottom_left")) return .{ .horizontal = .left, .vertical = .bottom };
    if (std.mem.eql(u8, name, "bottom_center")) return .{ .horizontal = .center, .vertical = .bottom };
    if (std.mem.eql(u8, name, "bottom_right")) return .{ .horizontal = .right, .vertical = .bottom };
    return anchor;
}

fn readUiPosition(obj: std.json.ObjectMap, parent_layout: UiLayout) [2]f32 {
    var pos: [2]f32 = .{ 0, 0 };
    const pos_val = obj.get("position") orelse return pos;
    if (pos_val != .object) return pos;
    const pos_obj = pos_val.object;
    if (pos_obj.get("x")) |x_val| {
        pos[0] = resolveUiAxisValue(x_val, parent_layout.width);
    }
    if (pos_obj.get("y")) |y_val| {
        pos[1] = resolveUiAxisValue(y_val, parent_layout.height);
    }
    return pos;
}

fn resolveUiAxisValue(value: std.json.Value, axis_size: f32) f32 {
    return switch (value) {
        .integer => |val| @floatFromInt(val),
        .float => |val| @floatCast(val),
        .string => |val| parseUiAxisString(val, axis_size),
        else => 0,
    };
}

fn parseUiAxisString(value: []const u8, axis_size: f32) f32 {
    if (std.mem.endsWith(u8, value, "px")) {
        if (value.len <= 2) return 0;
        const number = std.fmt.parseFloat(f32, value[0 .. value.len - 2]) catch return 0;
        return number;
    }
    if (std.mem.endsWith(u8, value, "%")) {
        if (value.len <= 1) return 0;
        const number = std.fmt.parseFloat(f32, value[0 .. value.len - 1]) catch return 0;
        return axis_size * (number / 100.0);
    }
    return 0;
}

fn readSizeObject(value: std.json.Value) ?[2]f32 {
    if (value != .object) return null;
    const obj = value.object;
    const width_val = obj.get("width") orelse return null;
    const height_val = obj.get("height") orelse return null;
    const width = readF32(width_val) orelse return null;
    const height = readF32(height_val) orelse return null;
    return .{ width, height };
}

fn parseUiTag(value: []const u8) []const u8 {
    if (std.mem.eql(u8, value, "text")) return "text";
    if (std.mem.eql(u8, value, "button")) return "button";
    if (std.mem.eql(u8, value, "image")) return "image";
    if (std.mem.eql(u8, value, "input")) return "input";
    return "div";
}

fn readF32(value: std.json.Value) ?f32 {
    return switch (value) {
        .integer => |val| @floatFromInt(val),
        .float => |val| @floatCast(val),
        else => null,
    };
}

fn readColorChannel(value: std.json.Value) ?u32 {
    const raw = readF32(value) orelse return null;
    var clamped = raw;
    if (clamped < 0) clamped = 0;
    if (clamped > 255) clamped = 255;
    return @intFromFloat(clamped);
}

fn readColor(value: std.json.Value) ?u32 {
    if (value != .object) return null;
    const obj = value.object;
    const r_val = obj.get("r") orelse return null;
    const g_val = obj.get("g") orelse return null;
    const b_val = obj.get("b") orelse return null;
    const a_val = obj.get("a") orelse return null;
    const r = readColorChannel(r_val) orelse return null;
    const g = readColorChannel(g_val) orelse return null;
    const b = readColorChannel(b_val) orelse return null;
    const a = readColorChannel(a_val) orelse return null;
    return (r << 24) | (g << 16) | (b << 8) | a;
}

fn readUiFontSize(obj: std.json.ObjectMap) ?f32 {
    if (obj.get("fontSizing")) |font_val| {
        if (readF32(font_val)) |value| return value;
    }
    if (obj.get("fontSize")) |font_val| {
        if (readF32(font_val)) |value| return value;
    }
    return null;
}

fn fontFamilyToken(obj: std.json.ObjectMap) ?[]const u8 {
    if (obj.get("fontFamily")) |family_val| {
        if (family_val == .string) {
            if (std.mem.eql(u8, family_val.string, "ui")) return "font-ui";
            if (std.mem.eql(u8, family_val.string, "mono")) return "font-mono";
            if (std.mem.eql(u8, family_val.string, "game")) return "font-game";
            if (std.mem.eql(u8, family_val.string, "dyslexic")) return "font-dyslexic";
        }
    }
    return null;
}

fn appendFontWeightToken(obj: std.json.ObjectMap, tokens: *std.ArrayList([]const u8), allocator: std.mem.Allocator) void {
    if (obj.get("fontWeight")) |weight_val| {
        if (weight_val == .string) {
            if (std.mem.eql(u8, weight_val.string, "light")) tokens.append(allocator, "font-light") catch {};
            if (std.mem.eql(u8, weight_val.string, "medium")) tokens.append(allocator, "font-medium") catch {};
            if (std.mem.eql(u8, weight_val.string, "semibold")) tokens.append(allocator, "font-semibold") catch {};
            if (std.mem.eql(u8, weight_val.string, "bold")) tokens.append(allocator, "font-bold") catch {};
        }
    }
}

fn appendFontItalicToken(obj: std.json.ObjectMap, tokens: *std.ArrayList([]const u8), allocator: std.mem.Allocator) void {
    const family_token = fontFamilyToken(obj);
    if (obj.get("fontItalic")) |italic_val| {
        if (italic_val == .bool) {
            const allowed = if (family_token) |token| !std.mem.eql(u8, token, "font-game") else true;
            if (allowed and italic_val.bool) {
                tokens.append(allocator, "italic") catch {};
            }
        }
    }
}

fn appendFontRenderToken(obj: std.json.ObjectMap, tokens: *std.ArrayList([]const u8), allocator: std.mem.Allocator) void {
    if (obj.get("fontRenderMode")) |render_val| {
        if (render_val == .string) {
            if (std.mem.eql(u8, render_val.string, "msdf")) tokens.append(allocator, "font-render-msdf") catch {};
            if (std.mem.eql(u8, render_val.string, "raster")) tokens.append(allocator, "font-render-raster") catch {};
        }
    }
}

fn fontSizeToken(size: f32) []const u8 {
    if (size <= 12.0) return "text-xs";
    if (size <= 14.0) return "text-sm";
    if (size <= 16.0) return "text-base";
    if (size <= 20.0) return "text-lg";
    if (size <= 24.0) return "text-xl";
    if (size <= 28.0) return "text-2xl";
    return "text-3xl";
}
