const std = @import("std");
const dvui = @import("dvui");

const types = @import("../../core/types.zig");
const events = @import("../../events/mod.zig");
const tailwind = @import("../../style/tailwind.zig");
const runtime_mod = @import("runtime.zig");

const RenderRuntime = runtime_mod.RenderRuntime;

fn containsId(list: []const u32, id: u32) bool {
    for (list) |value| {
        if (value == id) return true;
    }
    return false;
}

pub fn syncHoverPath(
    runtime: *RenderRuntime,
    event_ring: ?*events.EventRing,
    store: *types.NodeStore,
    allocator: std.mem.Allocator,
    hovered_id: u32,
) bool {
    if (runtime.hovered_cache_allocator == null) {
        runtime.hovered_cache_allocator = store.allocator;
    }
    const cache_alloc = runtime.hovered_cache_allocator.?;
    const prev_items = runtime.hovered_ids.items;

    var next: std.ArrayListUnmanaged(u32) = .{};
    defer next.deinit(allocator);

    var current_id: u32 = hovered_id;
    while (current_id != 0) {
        next.append(allocator, current_id) catch break;
        const node = store.node(current_id) orelse break;
        current_id = node.parent orelse 0;
    }

    var layout_invalidated = false;

    for (prev_items) |id| {
        if (containsId(next.items, id)) continue;
        const node = store.node(id) orelse continue;
        if (!node.hovered) continue;
        node.hovered = false;

        var spec = node.prepareClassSpec();
        const has_leave = node.hasListenerKind(.mouseleave);
        if (event_ring != null and runtime.input_enabled_state and has_leave) {
            _ = event_ring.?.push(.mouseleave, node.id, null);
        }
        if (tailwind.hasHover(&spec)) {
            store.markNodePaintChanged(node.id);
        }
    }

    for (next.items) |id| {
        if (containsId(prev_items, id)) continue;
        const node = store.node(id) orelse continue;
        if (node.hovered) continue;
        node.hovered = true;

        var spec = node.prepareClassSpec();
        const has_enter = node.hasListenerKind(.mouseenter);
        if (event_ring != null and runtime.input_enabled_state and has_enter) {
            _ = event_ring.?.push(.mouseenter, node.id, null);
        }
        if (tailwind.hasHoverLayout(&spec)) {
            node.invalidateLayout();
            store.markNodeChanged(node.id);
            layout_invalidated = true;
        }
        if (tailwind.hasHover(&spec)) {
            store.markNodePaintChanged(node.id);
        }
    }

    runtime.hovered_ids.clearRetainingCapacity();
    runtime.hovered_ids.ensureTotalCapacity(cache_alloc, next.items.len) catch {};
    for (next.items) |id| {
        runtime.hovered_ids.appendAssumeCapacity(id);
    }

    if (runtime.input_enabled_state) {
        var cursor_id: u32 = hovered_id;
        while (cursor_id != 0) {
            const node = store.node(cursor_id) orelse break;
            const spec = node.prepareClassSpec();
            if (spec.cursor) |cursor| {
                if (node.hovered) {
                    dvui.cursorSet(cursor);
                }
                break;
            }
            cursor_id = node.parent orelse 0;
        }
    }

    return layout_invalidated;
}
