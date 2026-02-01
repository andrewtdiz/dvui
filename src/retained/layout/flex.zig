const std = @import("std");
const dvui = @import("dvui");

const types = @import("../core/types.zig");
const tailwind = @import("../style/tailwind.zig");
const measure = @import("measure.zig");

pub fn layoutFlexChildren(store: *types.NodeStore, node: *types.SolidNode, area: types.Rect, spec: tailwind.Spec) void {
    const base_scale = dvui.windowNaturalScale();
    const scale = if (node.layout.layout_scale != 0) node.layout.layout_scale else base_scale;
    const lifo = dvui.currentWindow().lifo();
    const dir = spec.direction orelse .horizontal;
    const gap_main_unscaled = switch (dir) {
        .horizontal => spec.gap_col,
        .vertical => spec.gap_row,
    } orelse 0;
    const gap_main = gap_main_unscaled * scale;

    var child_sizes: std.ArrayListUnmanaged(types.Size) = .{};
    defer child_sizes.deinit(lifo);

    // Track which children participate in flex layout. Solid's universal renderer
    // inserts empty text nodes as control-flow anchors (e.g. <Show/> when false).
    // These should not count as flex items or gaps.
    var visible_mask: std.ArrayListUnmanaged(bool) = .{};
    defer visible_mask.deinit(lifo);
    var visible_count: usize = 0;

    // Absolute-positioned children are laid out relative to the flex container
    // but do not participate in flex flow or gaps.
    var absolute_children: std.ArrayListUnmanaged(u32) = .{};
    defer absolute_children.deinit(lifo);

    const available_size = types.Size{ .w = area.w, .h = area.h };
    var total_main: f32 = 0;
    var max_cross: f32 = 0;

    for (node.children.items) |child_id| {
        if (store.node(child_id)) |child| {
            // Skip hidden children entirely
            const child_spec = child.prepareClassSpec();
            const child_scale = scale * (child_spec.scale orelse 1.0);
            child.layout.layout_scale = child_scale;
            if (child_spec.hidden) {
                child_sizes.append(lifo, .{}) catch {};
                visible_mask.append(lifo, false) catch {};
                continue;
            }

            if (child_spec.position != null and child_spec.position.? == .absolute) {
                child_sizes.append(lifo, .{}) catch {};
                visible_mask.append(lifo, false) catch {};
                absolute_children.append(lifo, child_id) catch {};
                continue;
            }

            const child_size = measure.measureNodeSize(store, child, available_size);
            child_sizes.append(lifo, child_size) catch {};

            const is_empty_text = child.kind == .text and child_size.w == 0 and child_size.h == 0;
            if (is_empty_text) {
                visible_mask.append(lifo, false) catch {};
                continue;
            }
            visible_mask.append(lifo, true) catch {};
            visible_count += 1;

            const main = switch (dir) {
                .horizontal => child_size.w,
                .vertical => child_size.h,
            };
            const cross = switch (dir) {
                .horizontal => child_size.h,
                .vertical => child_size.w,
            };
            total_main += main;
            if (cross > max_cross) max_cross = cross;
        } else {
            child_sizes.append(lifo, .{}) catch {};
            visible_mask.append(lifo, false) catch {};
        }
    }

    if (visible_count > 0) {
        total_main += gap_main * @as(f32, @floatFromInt(visible_count - 1));
    }

    const available_main: f32 = switch (dir) {
        .horizontal => area.w,
        .vertical => area.h,
    };
    var cursor: f32 = area.x;
    if (dir == .vertical) cursor = area.y;

    const remaining = available_main - total_main;
    if (remaining > 0) {
        switch (spec.justify orelse .start) {
            .center => cursor += remaining / 2.0,
            .end => cursor += remaining,
            else => {},
        }
    }

    for (node.children.items, 0..) |child_id, idx| {
        const child_size = if (idx < child_sizes.items.len) child_sizes.items[idx] else types.Size{};
        const child_ptr = store.node(child_id) orelse continue;

        const is_visible = if (idx < visible_mask.items.len) visible_mask.items[idx] else false;
        if (!is_visible) {
            const child_spec = child_ptr.prepareClassSpec();
            if (child_spec.hidden) {
                child_ptr.layout.rect = types.Rect{};
                continue;
            }
            if (child_spec.position != null and child_spec.position.? == .absolute) {
                // Absolute children are laid out after flex flow.
                continue;
            }
            // Hidden or empty text anchor: zero rect and no gap contribution.
            child_ptr.layout.rect = types.Rect{};
            continue;
        }

        var child_rect = types.Rect{};
        const alignment = spec.align_items orelse .start;
        switch (dir) {
            .horizontal => {
                child_rect.x = cursor;
                child_rect.y = switch (alignment) {
                    .center => area.y + (area.h - child_size.h) / 2.0,
                    .end => area.y + (area.h - child_size.h),
                    else => area.y,
                };
                child_rect.w = child_size.w;
                child_rect.h = child_size.h;
                cursor += child_rect.w + gap_main;
            },
            .vertical => {
                child_rect.x = switch (alignment) {
                    .center => area.x + (area.w - child_size.w) / 2.0,
                    .end => area.x + (area.w - child_size.w),
                    else => area.x,
                };
                child_rect.y = cursor;
                child_rect.w = child_size.w;
                child_rect.h = child_size.h;
                cursor += child_rect.h + gap_main;
            },
        }

        @call(.auto, computeNodeLayout, .{ store, child_ptr, child_rect });
    }

    for (absolute_children.items) |child_id| {
        const child_ptr = store.node(child_id) orelse continue;
        @call(.auto, computeNodeLayout, .{ store, child_ptr, area });
    }
}

fn computeNodeLayout(store: *types.NodeStore, node: *types.SolidNode, parent_rect: types.Rect) void {
    // Use the entry point from layout/mod.zig. This indirection avoids a circular import.
    const layout = @import("mod.zig");
    layout.computeNodeLayout(store, node, parent_rect);
}
