const std = @import("std");
const dvui = @import("dvui");

const types = @import("../../core/types.zig");
const events = @import("../../events/mod.zig");
const tailwind = @import("../../style/tailwind.zig");
const direct = @import("../direct.zig");
const paint_cache = @import("../cache.zig");
const renderers = @import("renderers.zig");
const state = @import("state.zig");
const visual_sync = @import("visual_sync.zig");

const isPortalNode = state.isPortalNode;
const appendRect = state.appendRect;
const transformedRect = direct.transformedRect;
const DirtyRegionTracker = paint_cache.DirtyRegionTracker;

pub fn resetPortalCache() void {
    if (state.portal_cache_allocator) |alloc| {
        state.cached_portal_ids.deinit(alloc);
    }
    state.cached_portal_ids = .empty;
    state.portal_cache_allocator = null;
    state.portal_cache_version = 0;
    state.overlay_cache_version = 0;
    state.cached_overlay_state = .{};
}

pub fn ensurePortalCache(store: *types.NodeStore, root: *types.SolidNode) []const u32 {
    if (state.portal_cache_allocator == null) {
        state.portal_cache_allocator = store.allocator;
    }
    if (state.portal_cache_version != root.subtree_version) {
        state.cached_portal_ids.clearRetainingCapacity();
        if (state.portal_cache_allocator) |alloc| {
            collectPortalNodes(alloc, store, root, &state.cached_portal_ids);
        }
        state.portal_cache_version = root.subtree_version;
        state.overlay_cache_version = 0;
    }
    return state.cached_portal_ids.items;
}

pub fn ensureOverlayState(store: *types.NodeStore, portal_ids: []const u32, version: u64) state.OverlayState {
    if (state.overlay_cache_version != version) {
        state.cached_overlay_state = computeOverlayState(store, portal_ids);
        state.overlay_cache_version = version;
    }
    return state.cached_overlay_state;
}

fn collectPortalNodes(
    allocator: std.mem.Allocator,
    store: *types.NodeStore,
    node: *types.SolidNode,
    list: *std.ArrayList(u32),
) void {
    if (isPortalNode(node)) {
        list.append(allocator, node.id) catch {};
        return;
    }
    for (node.children.items) |child_id| {
        const child = store.node(child_id) orelse continue;
        collectPortalNodes(allocator, store, child, list);
    }
}

fn overlaySubtreeHasModal(store: *types.NodeStore, node: *types.SolidNode) bool {
    const spec = node.prepareClassSpec();
    if (spec.hidden) return false;
    if (node.modal) return true;
    for (node.children.items) |child_id| {
        const child = store.node(child_id) orelse continue;
        if (overlaySubtreeHasModal(store, child)) return true;
    }
    return false;
}

fn shouldIncludeOverlayRect(node: *types.SolidNode, spec: tailwind.Spec) bool {
    if (node.modal) return true;
    if (node.isInteractive()) return true;
    if (node.total_interactive > 0) return true;
    if (node.visual_props.background != null) return true;
    if (spec.background != null) return true;
    return false;
}

fn accumulateOverlayHitRect(store: *types.NodeStore, node: *types.SolidNode, rect_opt: *?types.Rect) void {
    const spec = node.prepareClassSpec();
    if (spec.hidden) return;
    if (node.layout.rect) |rect_base| {
        if (shouldIncludeOverlayRect(node, spec)) {
            const rect = transformedRect(node, rect_base) orelse rect_base;
            appendRect(rect_opt, rect);
        }
    }
    for (node.children.items) |child_id| {
        const child = store.node(child_id) orelse continue;
        accumulateOverlayHitRect(store, child, rect_opt);
    }
}

fn computeOverlayState(store: *types.NodeStore, portal_ids: []const u32) state.OverlayState {
    var state_value = state.OverlayState{};
    if (portal_ids.len == 0) return state_value;
    for (portal_ids) |portal_id| {
        const portal = store.node(portal_id) orelse continue;
        const spec = portal.prepareClassSpec();
        if (spec.hidden) continue;
        if (overlaySubtreeHasModal(store, portal)) {
            state_value.modal = true;
        }
        for (portal.children.items) |child_id| {
            const child = store.node(child_id) orelse continue;
            accumulateOverlayHitRect(store, child, &state_value.hit_rect);
        }
    }
    return state_value;
}

pub fn syncVisualLayer(
    event_ring: ?*events.EventRing,
    store: *types.NodeStore,
    root: *types.SolidNode,
    portal_ids: []const u32,
    layer: state.RenderLayer,
    mouse: dvui.Point.Physical,
) void {
    state.render_layer = layer;
    const pointer_allowed = state.allowPointerInput();
    switch (layer) {
        .overlay => {
            for (portal_ids) |portal_id| {
                const portal = store.node(portal_id) orelse continue;
                visual_sync.syncVisualsFromClasses(event_ring, store, portal, .{}, mouse, pointer_allowed);
            }
        },
        .base => {
            for (root.children.items) |child_id| {
                const child = store.node(child_id) orelse continue;
                if (isPortalNode(child)) continue;
                visual_sync.syncVisualsFromClasses(event_ring, store, child, .{}, mouse, pointer_allowed);
            }
        },
    }
}

pub fn renderPortalNodesOrdered(
    event_ring: ?*events.EventRing,
    store: *types.NodeStore,
    portal_ids: []const u32,
    allocator: std.mem.Allocator,
    tracker: *DirtyRegionTracker,
) void {
    if (portal_ids.len == 0) return;
    var ordered: std.ArrayList(state.OrderedNode) = .empty;
    defer ordered.deinit(allocator);

    var any_z = false;
    for (portal_ids, 0..) |portal_id, order_index| {
        const portal = store.node(portal_id) orelse continue;
        const z_index = portal.visual.z_index;
        if (z_index != 0) {
            any_z = true;
        }
        ordered.append(allocator, .{
            .id = portal_id,
            .z_index = z_index,
            .order = order_index,
        }) catch {};
    }

    if (ordered.items.len == 0) return;

    if (any_z) {
        state.sortOrderedNodes(ordered.items);
    }

    for (ordered.items) |entry| {
        renderers.renderNode(event_ring, store, entry.id, allocator, tracker);
    }
}
