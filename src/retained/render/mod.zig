const std = @import("std");

const dvui = @import("dvui");

const types = @import("../core/types.zig");
const events = @import("../events/mod.zig");
const layout = @import("../layout/mod.zig");
const direct = @import("direct.zig");
const image_loader = @import("image_loader.zig");
const icon_registry = @import("icon_registry.zig");
const paint_cache = @import("cache.zig");
const drag_drop = @import("../events/drag_drop.zig");
const focus = @import("../events/focus.zig");
const tailwind = @import("../style/tailwind.zig");

const interaction = @import("internal/interaction.zig");
const hover = @import("internal/hover.zig");
const overlay = @import("internal/overlay.zig");
const renderers = @import("internal/renderers.zig");
const state = @import("internal/state.zig");
const runtime_mod = @import("internal/runtime.zig");

const DirtyRegionTracker = paint_cache.DirtyRegionTracker;
const physicalToDvuiRect = state.physicalToDvuiRect;
const rectContains = state.rectContains;

const RenderRuntime = runtime_mod.RenderRuntime;

var runtime: RenderRuntime = .{};

pub fn init() void {
    runtime.reset();
    drag_drop.init();
    focus.init();
    image_loader.init();
    icon_registry.init();
}

pub fn deinit() void {
    drag_drop.deinit();
    focus.deinit();
    image_loader.deinit();
    icon_registry.deinit();
    runtime.reset();
}

pub fn setGizmoRectOverride(rect: ?types.GizmoRect) void {
    runtime.gizmo_override_rect = rect;
}

pub fn takeGizmoRectUpdate() ?types.GizmoRect {
    const next = runtime.gizmo_rect_pending;
    runtime.gizmo_rect_pending = null;
    return next;
}

fn updateFrameState(runtime_ptr: *RenderRuntime, mouse: dvui.Point.Physical, input_enabled: bool, layer: state.RenderLayer) void {
    runtime_ptr.last_mouse_pt = mouse;
    runtime_ptr.last_input_enabled = input_enabled;
    runtime_ptr.last_hover_layer = layer;
}

pub fn render(event_ring: ?*events.EventRing, store: *types.NodeStore, input_enabled: bool) bool {
    const root = store.node(0) orelse return false;

    runtime.input_enabled_state = input_enabled;
    focus.beginFrame(store);
    layout.updateLayouts(store);
    var layout_did_update = layout.didUpdateLayouts();
    if (runtime.input_enabled_state) {
        drag_drop.cancelIfMissing(event_ring, store);
    }

    var arena = std.heap.ArenaAllocator.init(store.allocator);
    defer arena.deinit();
    const scratch = arena.allocator();

    const portal_ids = overlay.ensurePortalCache(&runtime, store, root);
    const overlay_state = overlay.ensureOverlayState(&runtime, store, portal_ids, root.subtree_version);
    runtime.modal_overlay_active = overlay_state.modal;
    drag_drop.setHitTestContext(portal_ids, overlay_state.modal, overlay_state.hit_rect);

    const current_mouse = dvui.currentWindow().mouse_pt;
    const root_ctx = state.RenderContext{ .origin = .{ .x = 0, .y = 0 }, .clip = null, .scale = .{ 1, 1 }, .offset = .{ 0, 0 } };

    runtime.hover_layer = .base;
    if (portal_ids.len > 0) {
        if (overlay_state.modal) {
            runtime.hover_layer = .overlay;
        } else if (overlay_state.hit_rect) |hit_rect| {
            if (rectContains(hit_rect, current_mouse)) {
                runtime.hover_layer = .overlay;
            }
        }
    }

    runtime.render_layer = .base;

    if (runtime.input_enabled_state) {
        var base_pair: interaction.PickPair = .{};
        var base_order: u32 = 0;
        interaction.scanPickPair(store, root, current_mouse, root_ctx, &base_pair, &base_order, true);
        runtime.pointer_top_base_id = base_pair.interactive.id;

        var overlay_pair: interaction.PickPair = .{};
        var overlay_order: u32 = 0;
        if (portal_ids.len > 0) {
            for (portal_ids) |portal_id| {
                const portal = store.node(portal_id) orelse continue;
                interaction.scanPickPair(store, portal, current_mouse, root_ctx, &overlay_pair, &overlay_order, false);
            }
        }
        runtime.pointer_top_overlay_id = overlay_pair.interactive.id;
        const hovered_id = if (runtime.hover_layer == .overlay) overlay_pair.hover.id else base_pair.hover.id;
        const hover_layout_invalidated = hover.syncHoverPath(&runtime, event_ring, store, scratch, hovered_id);
        if (hover_layout_invalidated) {
            layout.updateLayouts(store);
            if (layout.didUpdateLayouts()) {
                layout_did_update = true;
            }

            base_pair = .{};
            base_order = 0;
            interaction.scanPickPair(store, root, current_mouse, root_ctx, &base_pair, &base_order, true);
            runtime.pointer_top_base_id = base_pair.interactive.id;

            overlay_pair = .{};
            overlay_order = 0;
            if (portal_ids.len > 0) {
                for (portal_ids) |portal_id| {
                    const portal = store.node(portal_id) orelse continue;
                    interaction.scanPickPair(store, portal, current_mouse, root_ctx, &overlay_pair, &overlay_order, false);
                }
            }
            runtime.pointer_top_overlay_id = overlay_pair.interactive.id;
            const hovered_id2 = if (runtime.hover_layer == .overlay) overlay_pair.hover.id else base_pair.hover.id;
            _ = hover.syncHoverPath(&runtime, event_ring, store, scratch, hovered_id2);
        }
    } else {
        runtime.pointer_top_base_id = 0;
        runtime.pointer_top_overlay_id = 0;
        _ = hover.syncHoverPath(&runtime, event_ring, store, scratch, 0);
    }

    var dirty_tracker = DirtyRegionTracker.init(scratch);
    defer dirty_tracker.deinit();

    const current_version = store.currentVersion();
    const needs_paint_cache = layout_did_update or current_version != runtime.last_paint_cache_version;
    if (needs_paint_cache) {
        paint_cache.updatePaintCache(store, &dirty_tracker);
        runtime.last_paint_cache_version = current_version;
    }

    if (root.children.items.len == 0) {
        updateFrameState(&runtime, current_mouse, runtime.input_enabled_state, runtime.hover_layer);
        return false;
    }

    const win = dvui.currentWindow();
    const screen_rect = types.Rect{
        .x = 0,
        .y = 0,
        .w = win.rect_pixels.w,
        .h = win.rect_pixels.h,
    };

    if (dirty_tracker.regions.items.len == 0) {
        dirty_tracker.add(screen_rect);
    }

    runtime.render_layer = .base;
    renderers.renderChildrenOrdered(&runtime, event_ring, store, root, scratch, &dirty_tracker, root_ctx, false);

    if (portal_ids.len > 0) {
        const overlay_id = state.overlaySubwindowId();
        const overlay_rect = if (overlay_state.modal) screen_rect else overlay_state.hit_rect orelse types.Rect{};
        const overlay_rect_phys = direct.rectToPhysical(overlay_rect);
        const overlay_rect_nat = physicalToDvuiRect(overlay_rect);
        const overlay_rect_natural = dvui.Rect.Natural.cast(overlay_rect_nat);
        const overlay_mouse_events = overlay_state.modal or overlay_state.hit_rect != null;
        const overlay_ctx = state.RenderContext{
            .origin = .{ .x = overlay_rect.x, .y = overlay_rect.y },
            .clip = null,
            .scale = .{ 1, 1 },
            .offset = .{ 0, 0 },
        };

        dvui.subwindowAdd(overlay_id, overlay_rect_nat, overlay_rect_phys, overlay_state.modal, null, overlay_mouse_events);
        const prev = dvui.subwindowCurrentSet(overlay_id, overlay_rect_natural);
        defer _ = dvui.subwindowCurrentSet(prev.id, prev.rect);

        runtime.render_layer = .overlay;
        overlay.renderPortalNodesOrdered(&runtime, event_ring, store, portal_ids, scratch, &dirty_tracker, overlay_ctx);
    }

    focus.endFrame(event_ring, store, runtime.input_enabled_state);
    runtime.render_layer = .base;
    updateFrameState(&runtime, current_mouse, runtime.input_enabled_state, runtime.hover_layer);
    return true;
}
