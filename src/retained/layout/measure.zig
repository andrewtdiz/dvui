const std = @import("std");
const dvui = @import("dvui");

const types = @import("../core/types.zig");
const tailwind = @import("../style/tailwind.zig");
const style_apply = @import("../style/apply.zig");
const text_wrap = @import("text_wrap.zig");

const default_button_padding: f32 = 6.0;

pub fn measureTextCached(store: *types.NodeStore, node: *types.SolidNode) types.Size {
    const text = node.text;
    const trimmed = std.mem.trim(u8, text, " \n\r\t");
    if (trimmed.len == 0) return .{};

    const base_scale = dvui.windowNaturalScale();
    const scale = if (node.layout.layout_scale != 0) node.layout.layout_scale else base_scale;

    var options = dvui.Options{};
    if (node.parent) |pid| {
        if (store.node(pid)) |parent| {
            var parent_spec = parent.prepareClassSpec();
            style_apply.applyToOptions(dvui.currentWindow(), &parent_spec, &options);
            style_apply.resolveFont(&parent_spec, &options);
        }
    }

    const font = options.fontGet();
    const scale_key: u64 = @intFromFloat(scale * 100.0);
    const font_id: u64 = @intFromEnum(font.id);
    const font_size_key: u64 = @intFromFloat(font.size * 100.0);
    const hash = node.textContentHash() ^ scale_key ^ font_id ^ font_size_key;

    if (node.layout.text_hash == hash and node.layout.intrinsic_size != null) {
        return node.layout.intrinsic_size.?;
    }

    const size = font.textSize(trimmed);
    const height = @max(font.textHeight(), font.lineHeight());
    const result = types.Size{
        .w = size.w * scale,
        .h = height * scale,
    };

    node.layout.text_hash = hash;
    node.layout.intrinsic_size = result;

    return result;
}

pub fn measureNodeSize(store: *types.NodeStore, node: *types.SolidNode, parent_available: types.Size) types.Size {
    var spec = node.prepareClassSpec();
    tailwind.applyHover(&spec, node.hovered);
    const width_explicit = spec.width != null;
    const height_explicit = spec.height != null;
    const base_scale = dvui.windowNaturalScale();
    const scale = if (node.layout.layout_scale != 0) node.layout.layout_scale else base_scale;
    const local_scale = spec.scale orelse 1.0;
    var size = types.Size{};
    if (spec.width) |w| {
        size.w = switch (w) {
            .full => parent_available.w * local_scale,
            .pixels => |px| px * scale,
        };
    }
    if (spec.height) |h| {
        size.h = switch (h) {
            .full => parent_available.h * local_scale,
            .pixels => |px| px * scale,
        };
    }
    if (node.kind == .text) {
        const measured = measureTextCached(store, node);
        if (size.w == 0) size.w = measured.w;
        if (size.h == 0) size.h = measured.h;
    }
    if ((size.w == 0 or size.h == 0) and node.kind == .element) {
        if (shouldMeasureCombinedText(node)) {
            const wrap_width = if (size.w != 0) size.w else 0;
            if (measureCombinedElementText(store, node, spec, scale, wrap_width)) |text_size| {
                if (size.w == 0) size.w = text_size.w;
                if (size.h == 0) size.h = text_size.h;
            }
        }

        if (size.w == 0 or size.h == 0) {
            const dir = spec.direction orelse (if (spec.is_flex) dvui.enums.Direction.horizontal else dvui.enums.Direction.vertical);
            var total_main: f32 = 0;
            var max_cross: f32 = 0;
            var visible_count: usize = 0;

            for (node.children.items) |child_id| {
                const child = store.node(child_id) orelse continue;
                var child_spec = child.prepareClassSpec();
                tailwind.applyHover(&child_spec, child.hovered);
                if (child_spec.hidden) continue;
                if (child_spec.position != null and child_spec.position.? == .absolute) continue;

                const child_scale = scale * (child_spec.scale orelse 1.0);
                child.layout.layout_scale = child_scale;
                const child_size = measureNodeSize(store, child, parent_available);
                const margin_left = sideValue(child_spec.margin.left) * child_scale;
                const margin_right = sideValue(child_spec.margin.right) * child_scale;
                const margin_top = sideValue(child_spec.margin.top) * child_scale;
                const margin_bottom = sideValue(child_spec.margin.bottom) * child_scale;
                const outer_size = types.Size{
                    .w = child_size.w + margin_left + margin_right,
                    .h = child_size.h + margin_top + margin_bottom,
                };
                if (child.kind == .text and child_size.w == 0 and child_size.h == 0) continue;

                visible_count += 1;
                const main = if (dir == .horizontal) outer_size.w else outer_size.h;
                const cross = if (dir == .horizontal) outer_size.h else outer_size.w;
                total_main += main;
                if (cross > max_cross) max_cross = cross;
            }

            if (visible_count > 0) {
                const gap = (if (dir == .horizontal) spec.gap_col else spec.gap_row) orelse 0;
                total_main += gap * scale * @as(f32, @floatFromInt(visible_count - 1));
            }

            if (size.w == 0) size.w = if (dir == .horizontal) total_main else max_cross;
            if (size.h == 0) size.h = if (dir == .horizontal) max_cross else total_main;
        }
        const button_pad = if (std.mem.eql(u8, node.tag, "button")) default_button_padding else 0.0;
        const pad_left = (spec.padding.left orelse button_pad) * scale;
        const pad_right = (spec.padding.right orelse button_pad) * scale;
        const pad_top = (spec.padding.top orelse button_pad) * scale;
        const pad_bottom = (spec.padding.bottom orelse button_pad) * scale;
        const border_left = sideValue(spec.border.left) * scale;
        const border_right = sideValue(spec.border.right) * scale;
        const border_top = sideValue(spec.border.top) * scale;
        const border_bottom = sideValue(spec.border.bottom) * scale;
        if (!width_explicit) {
            size.w += pad_left + pad_right + border_left + border_right;
        }
        if (!height_explicit) {
            size.h += pad_top + pad_bottom + border_top + border_bottom;
        }
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
        std.mem.eql(u8, node.tag, "h3");
}

fn measureCombinedElementText(
    store: *types.NodeStore,
    node: *types.SolidNode,
    spec: tailwind.Spec,
    scale: f32,
    max_width: f32,
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
    tailwind.resolveFont(&spec, &options);
    const font = options.fontGet();
    text_wrap.computeLineBreaks(
        store.allocator,
        &node.layout.text_layout,
        trimmed,
        font,
        max_width,
        scale,
        spec.text_wrap,
        spec.break_words,
    );
    const layout = node.layout.text_layout;
    if (layout.lines.items.len == 0) return null;

    return types.Size{
        .w = layout.max_line_width,
        .h = layout.height,
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
