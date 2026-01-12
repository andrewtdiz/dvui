const std = @import("std");
const dvui = @import("dvui");

const types = @import("../core/types.zig");

pub fn measureTextCached(node: *types.SolidNode) types.Size {
    const text = node.text;
    const trimmed = std.mem.trim(u8, text, " \n\r\t");
    if (trimmed.len == 0) return .{};

    const scale = dvui.windowNaturalScale();
    const scale_key: u64 = @intFromFloat(scale * 100.0);
    const hash = node.textContentHash() ^ scale_key;

    if (node.layout.text_hash == hash and node.layout.intrinsic_size != null) {
        return node.layout.intrinsic_size.?;
    }

    const font = (dvui.Options{}).fontGet();
    const size = font.textSize(trimmed);
    const result = types.Size{
        .w = size.w * scale,
        .h = size.h * scale,
    };

    node.layout.text_hash = hash;
    node.layout.intrinsic_size = result;

    return result;
}

pub fn measureNodeSize(store: *types.NodeStore, node: *types.SolidNode, parent_available: types.Size) types.Size {
    const spec = node.prepareClassSpec();
    const scale = dvui.windowNaturalScale();
    var size = types.Size{};
    if (spec.width) |w| {
        size.w = switch (w) {
            .full => parent_available.w,
            .pixels => |px| px * scale,
        };
    }
    if (spec.height) |h| {
        size.h = switch (h) {
            .full => parent_available.h,
            .pixels => |px| px * scale,
        };
    }
    if (node.kind == .text) {
        const measured = measureTextCached(node);
        if (size.w == 0) size.w = measured.w;
        if (size.h == 0) size.h = measured.h;
    }
    if ((size.w == 0 or size.h == 0) and node.kind == .element) {
        if (shouldMeasureCombinedText(node)) {
            if (measureCombinedElementText(store, node, spec, scale)) |text_size| {
                if (size.w == 0) size.w = text_size.w;
                if (size.h == 0) size.h = text_size.h;
            }
        }

        if (size.w == 0 or size.h == 0) {
            for (node.children.items) |child_id| {
                if (store.node(child_id)) |child| {
                    if (child.kind == .text) {
                        const text_size = measureTextCached(child);
                        if (size.w == 0) size.w = text_size.w;
                        if (size.h == 0) size.h = text_size.h;
                        break;
                    }
                }
            }
        }
        if (size.w == 0 or size.h == 0) {
            for (node.children.items) |child_id| {
                if (store.node(child_id)) |child| {
                    const child_size = measureNodeSize(store, child, parent_available);
                    if (size.w == 0) size.w = child_size.w;
                    if (size.h == 0) size.h = child_size.h;
                    break;
                }
            }
        }
        const pad_left = sideValue(spec.padding.left) * scale;
        const pad_right = sideValue(spec.padding.right) * scale;
        const pad_top = sideValue(spec.padding.top) * scale;
        const pad_bottom = sideValue(spec.padding.bottom) * scale;
        size.w += pad_left + pad_right;
        size.h += pad_top + pad_bottom;
    }
    return size;
}

fn sideValue(value: ?f32) f32 {
    return value orelse 0;
}

fn shouldMeasureCombinedText(node: *const types.SolidNode) bool {
    if (node.kind != .element) return false;
    return std.mem.eql(u8, node.tag, "p") or
        std.mem.eql(u8, node.tag, "h1") or
        std.mem.eql(u8, node.tag, "h2") or
        std.mem.eql(u8, node.tag, "h3") or
        std.mem.eql(u8, node.tag, "button");
}

fn measureCombinedElementText(
    store: *types.NodeStore,
    node: *const types.SolidNode,
    spec: anytype,
    scale: f32,
) ?types.Size {
    const cw = dvui.currentWindow();
    const lifo = cw.lifo();

    var list: std.ArrayList(u8) = .empty;
    defer list.deinit(lifo);
    collectTextForMeasure(lifo, store, node, &list);
    if (list.items.len == 0) return null;

    const trimmed = std.mem.trim(u8, list.items, " \n\r\t");
    if (trimmed.len == 0) return null;

    var options = dvui.Options{};
    if (spec.font_style) |style| {
        options.font_style = style;
    }
    const font = options.fontGet();
    const nat = font.textSize(trimmed);

    return types.Size{
        .w = nat.w * scale,
        .h = nat.h * scale,
    };
}

fn collectTextForMeasure(
    allocator: std.mem.Allocator,
    store: *types.NodeStore,
    node: *const types.SolidNode,
    into: *std.ArrayList(u8),
) void {
    switch (node.kind) {
        .text => {
            if (node.text.len == 0) return;
            _ = into.appendSlice(allocator, node.text) catch {};
        },
        else => {
            for (node.children.items) |child_id| {
                const child = store.node(child_id) orelse continue;
                collectTextForMeasure(allocator, store, child, into);
            }
        },
    }
}
