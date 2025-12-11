const std = @import("std");

const types = @import("../core/types.zig");
const tailwind = @import("../style/tailwind.zig");
const measure = @import("measure.zig");

pub fn layoutFlexChildren(store: *types.NodeStore, node: *types.SolidNode, area: types.Rect, spec: tailwind.Spec) void {
    const dir = spec.direction orelse .horizontal;
    const gap_main = switch (dir) {
        .horizontal => spec.gap_col,
        .vertical => spec.gap_row,
    } orelse 0;

    var child_sizes: std.ArrayListUnmanaged(types.Size) = .{};
    defer child_sizes.deinit(std.heap.page_allocator);

    const available_size = types.Size{ .w = area.w, .h = area.h };
    var total_main: f32 = 0;
    var max_cross: f32 = 0;

    for (node.children.items) |child_id| {
        if (store.node(child_id)) |child| {
            // Skip hidden children entirely
            const child_spec = child.prepareClassSpec();
            if (child_spec.hidden) {
                child_sizes.append(std.heap.page_allocator, .{}) catch {};
                continue;
            }
            const child_size = measure.measureNodeSize(store, child, available_size);
            child_sizes.append(std.heap.page_allocator, child_size) catch {};
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
            child_sizes.append(std.heap.page_allocator, .{}) catch {};
        }
    }

    if (child_sizes.items.len > 0) {
        total_main += gap_main * @as(f32, @floatFromInt(child_sizes.items.len - 1));
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

        // Skip hidden children - they get zero rect and don't advance cursor
        const child_spec = child_ptr.prepareClassSpec();
        if (child_spec.hidden) {
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
}

fn computeNodeLayout(store: *types.NodeStore, node: *types.SolidNode, parent_rect: types.Rect) void {
    // Use the entry point from layout/mod.zig. This indirection avoids a circular import.
    const layout = @import("mod.zig");
    layout.computeNodeLayout(store, node, parent_rect);
}
