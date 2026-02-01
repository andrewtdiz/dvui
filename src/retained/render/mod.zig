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

const interaction = @import("internal/interaction.zig");
const overlay = @import("internal/overlay.zig");
const renderers = @import("internal/renderers.zig");
const state = @import("internal/state.zig");

const DirtyRegionTracker = paint_cache.DirtyRegionTracker;
const physicalToDvuiRect = state.physicalToDvuiRect;
const rectContains = state.rectContains;

pub fn init() void {
    state.gizmo_override_rect = null;
    state.gizmo_rect_pending = null;
    state.logged_tree_dump = false;
    state.logged_render_state = false;
    state.logged_button_render = false;
    state.button_debug_count = 0;
    state.button_text_error_log_count = 0;
    state.paragraph_log_count = 0;
    state.input_enabled_state = true;
    state.render_layer = .base;
    state.hover_layer = .base;
    state.pointer_top_base_id = 0;
    state.pointer_top_overlay_id = 0;
    state.modal_overlay_active = false;
    state.last_mouse_pt = null;
    state.last_input_enabled = null;
    state.last_hover_layer = .base;
    state.hover_layout_invalidated = false;
    overlay.resetPortalCache();
    drag_drop.init();
    focus.init();
    paint_cache.init();
    image_loader.init();
    icon_registry.init();
}

pub fn deinit() void {
    drag_drop.deinit();
    focus.deinit();
    image_loader.deinit();
    icon_registry.deinit();
    paint_cache.deinit();
    overlay.resetPortalCache();
    state.last_mouse_pt = null;
    state.last_input_enabled = null;
    state.last_hover_layer = .base;
    state.hover_layout_invalidated = false;
    state.gizmo_override_rect = null;
    state.gizmo_rect_pending = null;
    state.logged_tree_dump = false;
    state.logged_render_state = false;
    state.logged_button_render = false;
    state.button_debug_count = 0;
    state.button_text_error_log_count = 0;
    state.paragraph_log_count = 0;
    state.input_enabled_state = true;
    state.render_layer = .base;
    state.hover_layer = .base;
    state.pointer_top_base_id = 0;
    state.pointer_top_overlay_id = 0;
    state.modal_overlay_active = false;
}

pub fn setGizmoRectOverride(rect: ?types.GizmoRect) void {
    state.gizmo_override_rect = rect;
}

pub fn takeGizmoRectUpdate() ?types.GizmoRect {
    const next = state.gizmo_rect_pending;
    state.gizmo_rect_pending = null;
    return next;
}

fn updateFrameState(mouse: dvui.Point.Physical, input_enabled: bool, layer: state.RenderLayer) void {
    state.last_mouse_pt = mouse;
    state.last_input_enabled = input_enabled;
    state.last_hover_layer = layer;
}

pub fn render(event_ring: ?*events.EventRing, store: *types.NodeStore, input_enabled: bool) bool {
    const root = store.node(0) orelse return false;

    state.input_enabled_state = input_enabled;
    focus.beginFrame(store);
    state.hover_layout_invalidated = false;
    layout.updateLayouts(store);
    var layout_did_update = layout.didUpdateLayouts();
    if (state.input_enabled_state) {
        drag_drop.cancelIfMissing(event_ring, store);
    }

    var arena = std.heap.ArenaAllocator.init(store.allocator);
    defer arena.deinit();
    const scratch = arena.allocator();

    const portal_ids = overlay.ensurePortalCache(store, root);
    const overlay_state = overlay.ensureOverlayState(store, portal_ids, root.subtree_version);
    state.modal_overlay_active = overlay_state.modal;

    const current_mouse = dvui.currentWindow().mouse_pt;
    const root_ctx = state.RenderContext{ .origin = .{ .x = 0, .y = 0 }, .clip = null, .scale = .{ 1, 1 }, .offset = .{ 0, 0 } };

    state.hover_layer = .base;
    if (portal_ids.len > 0) {
        if (overlay_state.modal) {
            state.hover_layer = .overlay;
        } else if (overlay_state.hit_rect) |hit_rect| {
            if (rectContains(hit_rect, current_mouse)) {
                state.hover_layer = .overlay;
            }
        }
    }

    const tree_dirty = root.hasDirtySubtree();
    const pointer_changed = if (state.input_enabled_state) blk: {
        if (state.last_mouse_pt) |prev_mouse| {
            break :blk prev_mouse.x != current_mouse.x or prev_mouse.y != current_mouse.y;
        }
        break :blk true;
    } else false;
    const input_changed = if (state.last_input_enabled) |prev| prev != input_enabled else true;
    const layer_changed = state.hover_layer != state.last_hover_layer;
    const needs_visual_sync = tree_dirty or layout_did_update or pointer_changed or input_changed or layer_changed;

    if (needs_visual_sync) {
        overlay.syncVisualLayer(event_ring, store, root, portal_ids, .base, current_mouse);
        if (portal_ids.len > 0) {
            overlay.syncVisualLayer(event_ring, store, root, portal_ids, .overlay, current_mouse);
        } else {
            state.render_layer = .base;
        }
        if (state.hover_layout_invalidated) {
            state.hover_layout_invalidated = false;
            layout.updateLayouts(store);
            if (layout.didUpdateLayouts()) {
                layout_did_update = true;
            }
            overlay.syncVisualLayer(event_ring, store, root, portal_ids, .base, current_mouse);
            if (portal_ids.len > 0) {
                overlay.syncVisualLayer(event_ring, store, root, portal_ids, .overlay, current_mouse);
            } else {
                state.render_layer = .base;
            }
        }
    } else {
        state.render_layer = .base;
    }

    if (state.input_enabled_state) {
        state.pointer_top_base_id = interaction.pickInteractiveId(store, root, current_mouse, true, root_ctx);
        var overlay_pick: state.PointerPick = .{};
        var overlay_order: u32 = 0;
        if (portal_ids.len > 0) {
            for (portal_ids) |portal_id| {
                const portal = store.node(portal_id) orelse continue;
                interaction.scanPickInteractive(store, portal, current_mouse, root_ctx, &overlay_pick, &overlay_order, false);
            }
        }
        state.pointer_top_overlay_id = overlay_pick.id;
    } else {
        state.pointer_top_base_id = 0;
        state.pointer_top_overlay_id = 0;
    }

    var dirty_tracker = DirtyRegionTracker.init(scratch);
    defer dirty_tracker.deinit();

    const needs_paint_cache = needs_visual_sync or layout_did_update or root.needsPaintUpdate();
    if (needs_paint_cache) {
        paint_cache.updatePaintCache(store, &dirty_tracker);
    }

    if (!state.logged_tree_dump) {
        state.logged_tree_dump = true;
    }

    if (root.children.items.len == 0) {
        updateFrameState(current_mouse, state.input_enabled_state, state.hover_layer);
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

    state.render_layer = .base;
    renderers.renderChildrenOrdered(event_ring, store, root, scratch, &dirty_tracker, root_ctx, false);

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

        state.render_layer = .overlay;
        overlay.renderPortalNodesOrdered(event_ring, store, portal_ids, scratch, &dirty_tracker, overlay_ctx);
    }

    focus.endFrame(event_ring, store, state.input_enabled_state);
    state.render_layer = .base;
    updateFrameState(current_mouse, state.input_enabled_state, state.hover_layer);
    return true;
}
