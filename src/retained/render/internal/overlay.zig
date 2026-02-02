const std = @import("std");

const dvui = @import("dvui");

const types = @import("../../core/types.zig");
const events = @import("../../events/mod.zig");
const tailwind = @import("../../style/tailwind.zig");
const paint_cache = @import("../cache.zig");
const renderers = @import("renderers.zig");
const state = @import("state.zig");
const transitions = @import("../transitions.zig");
const runtime_mod = @import("runtime.zig");

const isPortalNode = state.isPortalNode;
const appendRect = state.appendRect;
const nodeBoundsInContext = state.nodeBoundsInContext;
const DirtyRegionTracker = paint_cache.DirtyRegionTracker;

const RenderRuntime = runtime_mod.RenderRuntime;

pub fn ensurePortalCache(runtime: *RenderRuntime, store: *types.NodeStore, root: *types.SolidNode) []const u32 {
    if (runtime.portal_cache_allocator == null) {
        runtime.portal_cache_allocator = store.allocator;
    }
    if (runtime.portal_cache_version != root.subtree_version) {
        runtime.cached_portal_ids.clearRetainingCapacity();
        if (runtime.portal_cache_allocator) |alloc| {
            collectPortalNodes(alloc, store, root, &runtime.cached_portal_ids);
        }
        runtime.portal_cache_version = root.subtree_version;
        runtime.overlay_cache_version = 0;
    }
    return runtime.cached_portal_ids.items;
}

pub fn ensureOverlayState(runtime: *RenderRuntime, store: *types.NodeStore, portal_ids: []const u32, version: u64) state.OverlayState {
    const frame_time = dvui.frameTimeNS();
    var hasher = std.hash.Wyhash.init(0);
    hasher.update(std.mem.asBytes(&version));
    hasher.update(std.mem.asBytes(&frame_time));
    const key = hasher.final();

    if (runtime.overlay_cache_version != key) {
        runtime.cached_overlay_state = computeOverlayState(store, portal_ids);
        runtime.overlay_cache_version = key;
    }
    return runtime.cached_overlay_state;
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

fn ctxForChildren(ctx: state.RenderContext, node: *types.SolidNode) state.RenderContext {
    var next = ctx;
    if (node.layout.rect) |rect| {
        const t = transitions.effectiveTransform(node);
        const anchor = .{
            .x = rect.x + rect.w * t.anchor[0],
            .y = rect.y + rect.h * t.anchor[1],
        };
        const offset = .{
            .x = anchor.x + t.translation[0] - t.scale[0] * anchor.x,
            .y = anchor.y + t.translation[1] - t.scale[1] * anchor.y,
        };
        next.scale = .{ ctx.scale[0] * t.scale[0], ctx.scale[1] * t.scale[1] };
        next.offset = .{
            ctx.scale[0] * offset.x + ctx.offset[0],
            ctx.scale[1] * offset.y + ctx.offset[1],
        };
    }
    return next;
}

fn accumulateOverlayHitRect(store: *types.NodeStore, node: *types.SolidNode, rect_opt: *?types.Rect, ctx: state.RenderContext) void {
    const spec = node.prepareClassSpec();
    if (spec.hidden) return;
    if (node.layout.rect) |rect_base| {
        if (shouldIncludeOverlayRect(node, spec)) {
            const rect = nodeBoundsInContext(ctx, node, rect_base);
            appendRect(rect_opt, rect);
        }
    }
    const child_ctx = ctxForChildren(ctx, node);
    for (node.children.items) |child_id| {
        const child = store.node(child_id) orelse continue;
        accumulateOverlayHitRect(store, child, rect_opt, child_ctx);
    }
}

fn computeOverlayState(store: *types.NodeStore, portal_ids: []const u32) state.OverlayState {
    var state_value = state.OverlayState{};
    if (portal_ids.len == 0) return state_value;
    const root_ctx = state.RenderContext{
        .origin = .{ .x = 0, .y = 0 },
        .clip = null,
        .scale = .{ 1, 1 },
        .offset = .{ 0, 0 },
    };
    for (portal_ids) |portal_id| {
        const portal = store.node(portal_id) orelse continue;
        const spec = portal.prepareClassSpec();
        if (spec.hidden) continue;
        if (overlaySubtreeHasModal(store, portal)) {
            state_value.modal = true;
        }
        for (portal.children.items) |child_id| {
            const child = store.node(child_id) orelse continue;
            accumulateOverlayHitRect(store, child, &state_value.hit_rect, root_ctx);
        }
    }
    return state_value;
}

pub fn renderPortalNodesOrdered(
    runtime: *RenderRuntime,
    event_ring: ?*events.EventRing,
    store: *types.NodeStore,
    portal_ids: []const u32,
    allocator: std.mem.Allocator,
    tracker: *DirtyRegionTracker,
    ctx: state.RenderContext,
) void {
    if (portal_ids.len == 0) return;
    var ordered: std.ArrayList(state.OrderedNode) = .empty;
    defer ordered.deinit(allocator);

    var any_z = false;
    for (portal_ids, 0..) |portal_id, order_index| {
        const portal = store.node(portal_id) orelse continue;
        var spec = portal.prepareClassSpec();
        tailwind.applyHover(&spec, portal.hovered);
        const z_index = spec.z_index;
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
        renderers.renderNode(runtime, event_ring, store, entry.id, allocator, tracker, ctx);
    }
}
