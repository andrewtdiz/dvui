const std = @import("std");

const dvui = @import("dvui");

const types = @import("../core/types.zig");
const events = @import("../events/mod.zig");
const layout = @import("../layout/mod.zig");
const text_wrap = @import("../layout/text_wrap.zig");
const style_apply = @import("../style/apply.zig");
const applyVisualToOptions = style_apply.applyVisualToOptions;
const applyClassSpecToVisual = style_apply.applyClassSpecToVisual;
const tailwind = @import("../style/tailwind.zig");
const direct = @import("direct.zig");
const dvuiColorToPacked = direct.dvuiColorToPacked;
const applyTransformToOptions = direct.applyTransformToOptions;
const transformedRect = direct.transformedRect;
const drawTextDirect = direct.drawTextDirect;
const drawTriangleDirect = direct.drawTriangleDirect;
const shouldDirectDraw = direct.shouldDirectDraw;
const packedColorToDvui = direct.packedColorToDvui;
const image_loader = @import("image_loader.zig");
const icon_registry = @import("icon_registry.zig");
const paint_cache = @import("cache.zig");
const DirtyRegionTracker = paint_cache.DirtyRegionTracker;
const renderCachedOrDirectBackground = paint_cache.renderCachedOrDirectBackground;
const updatePaintCache = paint_cache.updatePaintCache;
const drag_drop = @import("../events/drag_drop.zig");
const focus = @import("../events/focus.zig");

const log = std.log.scoped(.solid_bridge);

var gizmo_override_rect: ?types.GizmoRect = null;
var gizmo_rect_pending: ?types.GizmoRect = null;
var logged_tree_dump: bool = false;
var logged_render_state: bool = false;
var logged_button_render: bool = false;
var button_debug_count: usize = 0;
var button_text_error_log_count: usize = 0;
var paragraph_log_count: usize = 0;
var input_enabled_state: bool = true;

const RenderLayer = enum {
    base,
    overlay,
};

const overlay_subwindow_seed: u32 = 0x4f564c59;

var render_layer: RenderLayer = .base;
var hover_layer: RenderLayer = .base;
var modal_overlay_active: bool = false;
var last_mouse_pt: ?dvui.Point.Physical = null;
var last_input_enabled: ?bool = null;
var last_hover_layer: RenderLayer = .base;
var portal_cache_allocator: ?std.mem.Allocator = null;
var portal_cache_version: u64 = 0;
var cached_portal_ids: std.ArrayList(u32) = .empty;

pub fn init() void {
    gizmo_override_rect = null;
    gizmo_rect_pending = null;
    logged_tree_dump = false;
    logged_render_state = false;
    logged_button_render = false;
    button_debug_count = 0;
    button_text_error_log_count = 0;
    paragraph_log_count = 0;
    input_enabled_state = true;
    render_layer = .base;
    hover_layer = .base;
    modal_overlay_active = false;
    last_mouse_pt = null;
    last_input_enabled = null;
    last_hover_layer = .base;
    resetPortalCache();
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
    resetPortalCache();
    last_mouse_pt = null;
    last_input_enabled = null;
    last_hover_layer = .base;
    gizmo_override_rect = null;
    gizmo_rect_pending = null;
    logged_tree_dump = false;
    logged_render_state = false;
    logged_button_render = false;
    button_debug_count = 0;
    button_text_error_log_count = 0;
    paragraph_log_count = 0;
    input_enabled_state = true;
    render_layer = .base;
    hover_layer = .base;
    modal_overlay_active = false;
}

fn physicalToDvuiRect(rect: types.Rect) dvui.Rect {
    const scale = dvui.windowNaturalScale();
    const inv_scale: f32 = if (scale != 0) 1.0 / scale else 1.0;
    return dvui.Rect{
        .x = rect.x * inv_scale,
        .y = rect.y * inv_scale,
        .w = rect.w * inv_scale,
        .h = rect.h * inv_scale,
    };
}

fn applyLayoutScaleToOptions(node: *const types.SolidNode, options: *dvui.Options) void {
    const natural = dvui.windowNaturalScale();
    if (natural == 0) return;
    const layout_scale = node.layout.layout_scale;
    if (layout_scale == 0) return;
    const factor = layout_scale / natural;
    if (factor == 1.0) return;
    if (options.margin) |m| options.margin = m.scale(factor, dvui.Rect);
    if (options.border) |b| options.border = b.scale(factor, dvui.Rect);
    if (options.padding) |p| options.padding = p.scale(factor, dvui.Rect);
    if (options.corner_radius) |c| options.corner_radius = c.scale(factor, dvui.Rect);
    if (options.min_size_content) |ms| options.min_size_content = dvui.Size{ .w = ms.w * factor, .h = ms.h * factor };
    if (options.max_size_content) |mx| options.max_size_content = dvui.Options.MaxSize{ .w = mx.w * factor, .h = mx.h * factor };
    const font = options.fontGet();
    options.font = font.resize(font.size * factor);
}

fn applyCursorHint(node: *const types.SolidNode, class_spec: *const tailwind.Spec) void {
    if (!allowPointerInput()) return;
    if (!node.hovered) return;
    const cursor = class_spec.cursor orelse return;
    dvui.cursorSet(cursor);
}

fn nodeHasAccessibilityProps(node: *const types.SolidNode) bool {
    if (node.access_role != null) return true;
    if (node.access_label.len > 0) return true;
    if (node.access_description.len > 0) return true;
    if (node.access_expanded != null) return true;
    if (node.access_selected != null) return true;
    if (node.access_toggled != null) return true;
    if (node.access_hidden != null) return true;
    if (node.access_disabled != null) return true;
    if (node.access_has_popup != null) return true;
    if (node.access_modal != null) return true;
    return false;
}

fn applyAccessibilityOptions(
    node: *const types.SolidNode,
    options: *dvui.Options,
    fallback_role: ?dvui.AccessKit.Role,
) void {
    if (node.access_role) |role| {
        options.role = role;
    } else if (fallback_role != null and nodeHasAccessibilityProps(node)) {
        options.role = fallback_role.?;
    }
    if (node.access_label.len > 0) {
        options.label = .{ .text = node.access_label };
    }
}

fn applyAccessibilityState(node: *const types.SolidNode, wd: *dvui.WidgetData) void {
    if (wd.accesskit_node()) |ak_node| {
        if (node.access_description.len > 0) {
            const desc = dvui.currentWindow().arena().dupeZ(u8, node.access_description) catch "";
            defer dvui.currentWindow().arena().free(desc);
            dvui.AccessKit.nodeSetDescription(ak_node, desc);
        }
        if (node.access_expanded) |flag| {
            dvui.AccessKit.nodeSetExpanded(ak_node, flag);
        } else {
            dvui.AccessKit.nodeClearExpanded(ak_node);
        }
        if (node.access_selected) |flag| {
            dvui.AccessKit.nodeSetSelected(ak_node, flag);
        } else {
            dvui.AccessKit.nodeClearSelected(ak_node);
        }
        if (node.access_toggled) |state| {
            const toggled = switch (state) {
                .ak_false => dvui.AccessKit.Toggled.ak_false,
                .ak_true => dvui.AccessKit.Toggled.ak_true,
                .mixed => dvui.AccessKit.Toggled.mixed,
            };
            dvui.AccessKit.nodeSetToggled(ak_node, toggled);
        } else {
            dvui.AccessKit.nodeClearToggled(ak_node);
        }
        if (node.access_hidden) |flag| {
            dvui.AccessKit.nodeSetHidden(ak_node, flag);
        } else {
            dvui.AccessKit.nodeClearHidden(ak_node);
        }
        if (node.access_disabled) |flag| {
            dvui.AccessKit.nodeSetDisabled(ak_node, flag);
        } else {
            dvui.AccessKit.nodeClearDisabled(ak_node);
        }
        if (node.access_has_popup) |popup| {
            const popup_value = switch (popup) {
                .menu => dvui.AccessKit.HasPopup.menu,
                .listbox => dvui.AccessKit.HasPopup.listbox,
                .tree => dvui.AccessKit.HasPopup.tree,
                .grid => dvui.AccessKit.HasPopup.grid,
                .dialog => dvui.AccessKit.HasPopup.dialog,
            };
            dvui.AccessKit.nodeSetHasPopup(ak_node, popup_value);
        } else {
            dvui.AccessKit.nodeClearHasPopup(ak_node);
        }
        const modal_flag: ?bool = if (node.access_modal) |flag| flag else if (node.modal) true else null;
        if (modal_flag) |flag| {
            dvui.AccessKit.nodeSetModal(ak_node, flag);
        } else {
            dvui.AccessKit.nodeClearModal(ak_node);
        }
    }
}

const ClipState = struct {
    active: bool = false,
    rect: types.Rect = .{},
};

fn intersectRect(a: types.Rect, b: types.Rect) types.Rect {
    const x0 = @max(a.x, b.x);
    const y0 = @max(a.y, b.y);
    const x1 = @min(a.x + a.w, b.x + b.w);
    const y1 = @min(a.y + a.h, b.y + b.h);
    return types.Rect{
        .x = x0,
        .y = y0,
        .w = @max(0.0, x1 - x0),
        .h = @max(0.0, y1 - y0),
    };
}

fn rectContains(rect: types.Rect, point: dvui.Point.Physical) bool {
    if (rect.w <= 0 or rect.h <= 0) return false;
    if (point.x < rect.x or point.y < rect.y) return false;
    if (point.x > rect.x + rect.w or point.y > rect.y + rect.h) return false;
    return true;
}

fn isPortalNode(node: *const types.SolidNode) bool {
    return node.kind == .element and std.mem.eql(u8, node.tag, "portal");
}

fn allowPointerInput() bool {
    return input_enabled_state and render_layer == hover_layer;
}

fn allowFocusRegistration() bool {
    if (!input_enabled_state) return false;
    if (!modal_overlay_active) return true;
    return render_layer == .overlay;
}

fn overlaySubwindowId() dvui.Id {
    return dvui.Id.extendId(null, @src(), nodeIdExtra(overlay_subwindow_seed));
}

fn scrollContentId(node_id: u32) dvui.Id {
    return dvui.Id.extendId(null, @src(), nodeIdExtra(node_id));
}

const OverlayState = struct {
    modal: bool = false,
    hit_rect: ?types.Rect = null,
};

var cached_overlay_state: OverlayState = .{};
var overlay_cache_version: u64 = 0;

fn resetPortalCache() void {
    if (portal_cache_allocator) |alloc| {
        cached_portal_ids.deinit(alloc);
    }
    cached_portal_ids = .empty;
    portal_cache_allocator = null;
    portal_cache_version = 0;
    overlay_cache_version = 0;
    cached_overlay_state = .{};
}

fn ensurePortalCache(store: *types.NodeStore, root: *types.SolidNode) []const u32 {
    if (portal_cache_allocator == null) {
        portal_cache_allocator = store.allocator;
    }
    if (portal_cache_version != root.subtree_version) {
        cached_portal_ids.clearRetainingCapacity();
        if (portal_cache_allocator) |alloc| {
            collectPortalNodes(alloc, store, root, &cached_portal_ids);
        }
        portal_cache_version = root.subtree_version;
        overlay_cache_version = 0;
    }
    return cached_portal_ids.items;
}

fn ensureOverlayState(store: *types.NodeStore, portal_ids: []const u32, version: u64) OverlayState {
    if (overlay_cache_version != version) {
        cached_overlay_state = computeOverlayState(store, portal_ids);
        overlay_cache_version = version;
    }
    return cached_overlay_state;
}

fn updateFrameState(mouse: dvui.Point.Physical, input_enabled: bool, layer: RenderLayer) void {
    last_mouse_pt = mouse;
    last_input_enabled = input_enabled;
    last_hover_layer = layer;
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

fn unionRect(a: types.Rect, b: types.Rect) types.Rect {
    const x0 = @min(a.x, b.x);
    const y0 = @min(a.y, b.y);
    const x1 = @max(a.x + a.w, b.x + b.w);
    const y1 = @max(a.y + a.h, b.y + b.h);
    return types.Rect{
        .x = x0,
        .y = y0,
        .w = @max(0.0, x1 - x0),
        .h = @max(0.0, y1 - y0),
    };
}

fn appendRect(target: *?types.Rect, rect: types.Rect) void {
    if (rect.w <= 0 or rect.h <= 0) return;
    if (target.*) |existing| {
        target.* = unionRect(existing, rect);
    } else {
        target.* = rect;
    }
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

fn computeOverlayState(store: *types.NodeStore, portal_ids: []const u32) OverlayState {
    var state = OverlayState{};
    if (portal_ids.len == 0) return state;
    for (portal_ids) |portal_id| {
        const portal = store.node(portal_id) orelse continue;
        const spec = portal.prepareClassSpec();
        if (spec.hidden) continue;
        if (overlaySubtreeHasModal(store, portal)) {
            state.modal = true;
        }
        for (portal.children.items) |child_id| {
            const child = store.node(child_id) orelse continue;
            accumulateOverlayHitRect(store, child, &state.hit_rect);
        }
    }
    return state;
}

fn syncVisualLayer(
    event_ring: ?*events.EventRing,
    store: *types.NodeStore,
    root: *types.SolidNode,
    portal_ids: []const u32,
    layer: RenderLayer,
    mouse: dvui.Point.Physical,
) void {
    render_layer = layer;
    const pointer_allowed = allowPointerInput();
    switch (layer) {
        .overlay => {
            for (portal_ids) |portal_id| {
                const portal = store.node(portal_id) orelse continue;
                syncVisualsFromClasses(event_ring, store, portal, .{}, mouse, pointer_allowed);
            }
        },
        .base => {
            for (root.children.items) |child_id| {
                const child = store.node(child_id) orelse continue;
                if (isPortalNode(child)) continue;
                syncVisualsFromClasses(event_ring, store, child, .{}, mouse, pointer_allowed);
            }
        },
    }
}

const OrderedNode = struct {
    id: u32,
    z_index: i16,
    order: usize,
};

fn orderedNodeLessThan(_: void, lhs: OrderedNode, rhs: OrderedNode) bool {
    if (lhs.z_index == rhs.z_index) {
        return lhs.order < rhs.order;
    }
    return lhs.z_index < rhs.z_index;
}

fn sortOrderedNodes(nodes: []OrderedNode) void {
    if (nodes.len < 2) return;
    std.sort.pdq(OrderedNode, nodes, {}, orderedNodeLessThan);
}

fn renderPortalNodesOrdered(
    event_ring: ?*events.EventRing,
    store: *types.NodeStore,
    portal_ids: []const u32,
    allocator: std.mem.Allocator,
    tracker: *DirtyRegionTracker,
) void {
    if (portal_ids.len == 0) return;
    var ordered: std.ArrayList(OrderedNode) = .empty;
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
        sortOrderedNodes(ordered.items);
    }

    for (ordered.items) |entry| {
        renderNode(event_ring, store, entry.id, allocator, tracker);
    }
}

fn handleScrollInput(
    node: *types.SolidNode,
    hit_rect: types.Rect,
    scroll_info: *dvui.ScrollInfo,
    scroll_id: dvui.Id,
) bool {
    _ = node;
    if (!input_enabled_state) return false;
    const rect_phys = direct.rectToPhysical(hit_rect);
    const allow_vertical = scroll_info.scrollMax(.vertical) > 0;
    const allow_horizontal = scroll_info.scrollMax(.horizontal) > 0;
    var changed = false;

    for (dvui.events()) |*e| {
        if (!dvui.eventMatch(e, .{ .id = scroll_id, .r = rect_phys })) continue;

        switch (e.evt) {
            .mouse => |me| {
                switch (me.action) {
                    .wheel_y => |ticks| {
                        if (!allow_vertical) break;
                        scroll_info.scrollByOffset(.vertical, -ticks);
                        changed = true;
                        e.handled = true;
                        dvui.refresh(null, @src(), scroll_id);
                    },
                    .wheel_x => |ticks| {
                        if (!allow_horizontal) break;
                        scroll_info.scrollByOffset(.horizontal, ticks);
                        changed = true;
                        e.handled = true;
                        dvui.refresh(null, @src(), scroll_id);
                    },
                    .press => {
                        if (me.button.touch() and (allow_vertical or allow_horizontal)) {
                            const capture = dvui.CaptureMouse{
                                .id = scroll_id,
                                .rect = rect_phys,
                                .subwindow_id = dvui.subwindowCurrentId(),
                            };
                            dvui.captureMouseCustom(capture, e.num);
                            dvui.dragPreStart(me.p, .{});
                            e.handled = true;
                        }
                    },
                    .release => {
                        if (me.button.touch() and dvui.captured(scroll_id)) {
                            dvui.captureMouseCustom(null, e.num);
                            dvui.dragEnd();
                            e.handled = true;
                        }
                    },
                    .motion => {
                        if (dvui.captured(scroll_id)) {
                            if (dvui.dragging(me.p, null)) |dp| {
                                if (allow_horizontal) {
                                    scroll_info.scrollByOffset(.horizontal, -dp.x);
                                }
                                if (allow_vertical) {
                                    scroll_info.scrollByOffset(.vertical, -dp.y);
                                }
                                changed = true;
                                e.handled = true;
                                dvui.refresh(null, @src(), scroll_id);
                            }
                        }
                    },
                    else => {},
                }
            },
            else => {},
        }
    }

    return changed;
}

fn drawScrollBarStatic(rect: types.Rect, scroll_info: dvui.ScrollInfo, dir: dvui.enums.Direction) void {
    const rect_phys = direct.rectToPhysical(rect);
    if (rect_phys.w <= 0 or rect_phys.h <= 0) return;

    const theme = dvui.themeGet();
    rect_phys.fill(.all(100), .{ .color = theme.border.opacity(0.2), .fade = 1.0 });

    var grab = rect_phys;
    switch (dir) {
        .vertical => {
            const fraction = scroll_info.visibleFraction(.vertical);
            const grab_h = @min(grab.h, @max(20.0, grab.h * fraction));
            grab.h = grab_h;
            grab.y += (rect_phys.h - grab_h) * scroll_info.offsetFraction(.vertical);
        },
        .horizontal => {
            const fraction = scroll_info.visibleFraction(.horizontal);
            const grab_w = @min(grab.w, @max(20.0, grab.w * fraction));
            grab.w = grab_w;
            grab.x += (rect_phys.w - grab_w) * scroll_info.offsetFraction(.horizontal);
        },
    }

    grab.fill(.all(100), .{ .color = theme.text.opacity(0.5), .fade = 1.0 });
}

fn renderScrollBars(
    node: *types.SolidNode,
    viewport: types.Rect,
    scroll_info: *dvui.ScrollInfo,
    scroll_id: dvui.Id,
) bool {
    const thickness = node.scroll.scrollbar_thickness;
    if (thickness <= 0) return false;

    const show_v = scroll_info.scrollMax(.vertical) > 0;
    const show_h = scroll_info.scrollMax(.horizontal) > 0;
    if (!show_v and !show_h) return false;

    const prev_x = scroll_info.viewport.x;
    const prev_y = scroll_info.viewport.y;

    if (show_v) {
        var bar_rect = viewport;
        bar_rect.x = viewport.x + viewport.w - thickness;
        bar_rect.w = thickness;
        if (show_h) {
            bar_rect.h = @max(0.0, bar_rect.h - thickness);
        }
        if (input_enabled_state) {
            const options = dvui.Options{
                .name = "solid-scrollbar",
                .rect = physicalToDvuiRect(bar_rect),
                .background = true,
                .id_extra = nodeIdExtra(node.id ^ 0x9e3779b9),
            };
            var bar = dvui.ScrollBarWidget.init(
                @src(),
                .{ .scroll_info = scroll_info, .direction = .vertical, .focus_id = scroll_id },
                options,
            );
            bar.install();
            const grab = bar.grab();
            grab.draw();
            bar.deinit();
        } else {
            drawScrollBarStatic(bar_rect, scroll_info.*, .vertical);
        }
    }

    if (show_h) {
        var bar_rect = viewport;
        bar_rect.y = viewport.y + viewport.h - thickness;
        bar_rect.h = thickness;
        if (show_v) {
            bar_rect.w = @max(0.0, bar_rect.w - thickness);
        }
        if (input_enabled_state) {
            const options = dvui.Options{
                .name = "solid-scrollbar",
                .rect = physicalToDvuiRect(bar_rect),
                .background = true,
                .id_extra = nodeIdExtra(node.id ^ 0x3c6ef372),
            };
            var bar = dvui.ScrollBarWidget.init(
                @src(),
                .{ .scroll_info = scroll_info, .direction = .horizontal, .focus_id = scroll_id },
                options,
            );
            bar.install();
            const grab = bar.grab();
            grab.draw();
            bar.deinit();
        } else {
            drawScrollBarStatic(bar_rect, scroll_info.*, .horizontal);
        }
    }

    return scroll_info.viewport.x != prev_x or scroll_info.viewport.y != prev_y;
}

fn syncVisualsFromClasses(
    event_ring: ?*events.EventRing,
    store: *types.NodeStore,
    node: *types.SolidNode,
    clip: ClipState,
    mouse: dvui.Point.Physical,
    pointer_allowed: bool,
) void {
    const class_spec_base = node.prepareClassSpec();
    const has_hover = tailwind.hasHover(&class_spec_base);
    const has_mouseenter = node.hasListener("mouseenter");
    const has_mouseleave = node.hasListener("mouseleave");
    const prev_bg = node.visual.background;
    const prev_hovered = node.hovered;

    var rect_opt: ?types.Rect = null;
    if (node.layout.rect) |rect_base| {
        rect_opt = transformedRect(node, rect_base) orelse rect_base;
    }

    const wants_hover = has_hover or has_mouseenter or has_mouseleave or class_spec_base.cursor != null;
    var hovered = false;
    if (pointer_allowed and wants_hover and !class_spec_base.hidden and node.kind == .element) {
        if (rect_opt) |rect| {
            if (rectContains(rect, mouse)) {
                if (!clip.active or rectContains(clip.rect, mouse)) {
                    hovered = true;
                }
            }
        }
    }

    node.hovered = hovered;

    if (class_spec_base.hidden) {
        if (input_enabled_state) {
            if (event_ring) |ring| {
                if (prev_hovered and has_mouseleave) {
                    _ = ring.push(.mouseleave, node.id, null);
                }
            }
        }
        if (prev_hovered and has_hover) {
            node.invalidatePaint();
        }
        return;
    }

    if (input_enabled_state) {
        if (event_ring) |ring| {
            if (prev_hovered != hovered) {
                if (hovered and has_mouseenter) {
                    _ = ring.push(.mouseenter, node.id, null);
                } else if (!hovered and has_mouseleave) {
                    _ = ring.push(.mouseleave, node.id, null);
                }
            }
        }
    }

    node.visual = node.visual_props;
    var class_spec = class_spec_base;
    tailwind.applyHover(&class_spec, hovered);

    applyClassSpecToVisual(node, &class_spec);
    if (node.scroll.enabled) {
        node.visual.clip_children = true;
    }
    if (node.visual.background == null) {
        if (class_spec.background) |bg| {
            node.visual.background = dvuiColorToPacked(bg);
        } else {
            node.visual.background = .{ .value = 0x00000000 };
        }
    }
    const bg_changed = blk: {
        if (node.visual.background) |bg| {
            if (prev_bg) |prev| break :blk bg.value != prev.value;
            break :blk true;
        } else {
            break :blk prev_bg != null;
        }
    };
    if (bg_changed or (prev_hovered != hovered and has_hover)) {
        node.invalidatePaint();
    }

    var next_clip = clip;
    if (node.visual.clip_children) {
        if (rect_opt) |rect| {
            next_clip.active = true;
            next_clip.rect = if (clip.active) intersectRect(clip.rect, rect) else rect;
        }
    }

    for (node.children.items) |child_id| {
        if (store.node(child_id)) |child| {
            if (render_layer == .base and isPortalNode(child)) continue;
            syncVisualsFromClasses(event_ring, store, child, next_clip, mouse, pointer_allowed);
        }
    }
}

fn hasPaintDirtySubtree(store: *types.NodeStore, node: *types.SolidNode) bool {
    if (node.paint.paint_dirty) return true;
    for (node.children.items) |child_id| {
        if (store.node(child_id)) |child| {
            if (hasPaintDirtySubtree(store, child)) return true;
        }
    }
    return false;
}

pub fn setGizmoRectOverride(rect: ?types.GizmoRect) void {
    gizmo_override_rect = rect;
}

pub fn takeGizmoRectUpdate() ?types.GizmoRect {
    const next = gizmo_rect_pending;
    gizmo_rect_pending = null;
    return next;
}

pub fn render(event_ring: ?*events.EventRing, store: *types.NodeStore, input_enabled: bool) bool {
    const root = store.node(0) orelse return false;

    input_enabled_state = input_enabled;
    focus.beginFrame(store);
    layout.updateLayouts(store);
    const layout_did_update = layout.didUpdateLayouts();
    if (input_enabled_state) {
        drag_drop.cancelIfMissing(event_ring, store);
    }

    var arena = std.heap.ArenaAllocator.init(store.allocator);
    defer arena.deinit();
    const scratch = arena.allocator();

    const portal_ids = ensurePortalCache(store, root);
    const overlay_state = ensureOverlayState(store, portal_ids, root.subtree_version);
    modal_overlay_active = overlay_state.modal;

    const current_mouse = dvui.currentWindow().mouse_pt;

    hover_layer = .base;
    if (portal_ids.len > 0) {
        if (overlay_state.modal) {
            hover_layer = .overlay;
        } else if (overlay_state.hit_rect) |hit_rect| {
            if (rectContains(hit_rect, current_mouse)) {
                hover_layer = .overlay;
            }
        }
    }

    const tree_dirty = root.hasDirtySubtree();
    const pointer_changed = if (input_enabled_state) blk: {
        if (last_mouse_pt) |prev_mouse| {
            break :blk prev_mouse.x != current_mouse.x or prev_mouse.y != current_mouse.y;
        }
        break :blk true;
    } else false;
    const input_changed = if (last_input_enabled) |prev| prev != input_enabled else true;
    const layer_changed = hover_layer != last_hover_layer;
    const needs_visual_sync = tree_dirty or layout_did_update or pointer_changed or input_changed or layer_changed;

    if (needs_visual_sync) {
        // Ensure visual props (especially backgrounds) are applied before caching/dirty decisions.
        syncVisualLayer(event_ring, store, root, portal_ids, .base, current_mouse);
        if (portal_ids.len > 0) {
            syncVisualLayer(event_ring, store, root, portal_ids, .overlay, current_mouse);
        } else {
            render_layer = .base;
        }
    } else {
        render_layer = .base;
    }

    var dirty_tracker = DirtyRegionTracker.init(scratch);
    defer dirty_tracker.deinit();

    const needs_paint_cache = needs_visual_sync or root.needsPaintUpdate();
    if (needs_paint_cache) {
        updatePaintCache(store, &dirty_tracker);
    }

    // Temporary debug: dump the node tree once to verify state.
    if (!logged_tree_dump) {
        logged_tree_dump = true;
    }

    if (root.children.items.len == 0) {
        updateFrameState(current_mouse, input_enabled_state, hover_layer);
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

    render_layer = .base;
    renderChildrenOrdered(event_ring, store, root, scratch, &dirty_tracker, false);

    if (portal_ids.len > 0) {
        const overlay_id = overlaySubwindowId();
        const overlay_rect = if (overlay_state.modal) screen_rect else overlay_state.hit_rect orelse types.Rect{};
        const overlay_rect_phys = direct.rectToPhysical(overlay_rect);
        const overlay_rect_nat = physicalToDvuiRect(overlay_rect);
        const overlay_mouse_events = overlay_state.modal or overlay_state.hit_rect != null;

        dvui.subwindowAdd(overlay_id, overlay_rect_nat, overlay_rect_phys, overlay_state.modal, null, overlay_mouse_events);
        const prev = dvui.subwindowCurrentSet(overlay_id, overlay_rect_nat);
        defer dvui.subwindowCurrentSet(prev.id, prev.rect);

        render_layer = .overlay;
        renderPortalNodesOrdered(event_ring, store, portal_ids, scratch, &dirty_tracker);
    }

    focus.endFrame(event_ring, store, input_enabled_state);
    render_layer = .base;
    updateFrameState(current_mouse, input_enabled_state, hover_layer);
    return true;
}

fn renderNode(
    event_ring: ?*events.EventRing,
    store: *types.NodeStore,
    node_id: u32,
    allocator: std.mem.Allocator,
    tracker: *DirtyRegionTracker,
) void {
    const node = store.node(node_id) orelse return;
    if (render_layer == .base and isPortalNode(node)) {
        return;
    }
    switch (node.kind) {
        .root => {
            renderChildrenOrdered(event_ring, store, node, allocator, tracker, false);
            node.markRendered();
        },
        .slot => {
            renderChildrenOrdered(event_ring, store, node, allocator, tracker, false);
            node.markRendered();
        },
        .text => renderText(store, node),
        .element => renderElement(event_ring, store, node_id, node, allocator, tracker),
    }
}

fn renderElement(
    event_ring: ?*events.EventRing,
    store: *types.NodeStore,
    node_id: u32,
    node: *types.SolidNode,
    allocator: std.mem.Allocator,
    tracker: *DirtyRegionTracker,
) void {
    var class_spec = node.prepareClassSpec();
    tailwind.applyHover(&class_spec, node.hovered);

    // Skip rendering if element has 'hidden' class
    if (class_spec.hidden) {
        node.markRendered();
        return;
    }

    if (input_enabled_state) {
        applyCursorHint(node, &class_spec);
    }
    applyClassSpecToVisual(node, &class_spec);
    // DVUI path fallback: if class provided a background but visual is still null, copy it.
    if (node.visual.background == null) {
        if (class_spec.background) |bg| {
            node.visual.background = dvuiColorToPacked(bg);
        }
    }
    if (!logged_render_state) {
        logged_render_state = true;
    }

    if (node.isInteractive() or nodeHasAccessibilityProps(node)) {
        renderInteractiveElement(event_ring, store, node_id, node, allocator, class_spec, tracker);
    } else {
        renderNonInteractiveElement(event_ring, store, node_id, node, allocator, class_spec, tracker);
    }
}

fn renderElementBody(
    event_ring: ?*events.EventRing,
    store: *types.NodeStore,
    node_id: u32,
    node: *types.SolidNode,
    allocator: std.mem.Allocator,
    class_spec: tailwind.ClassSpec,
    tracker: *DirtyRegionTracker,
) void {
    if (node.scroll.enabled) {
        renderScrollFrame(event_ring, store, node_id, node, allocator, class_spec, tracker);
        return;
    }
    if (std.mem.eql(u8, node.tag, "div")) {
        renderContainer(event_ring, store, node, allocator, class_spec, tracker);
        node.markRendered();
        return;
    }
    if (std.mem.eql(u8, node.tag, "button")) {
        renderButton(event_ring, store, node_id, node, allocator, class_spec, tracker);
        node.markRendered();
        return;
    }
    if (std.mem.eql(u8, node.tag, "input")) {
        renderInput(event_ring, store, node_id, node, class_spec);
        node.markRendered();
        return;
    }
    if (std.mem.eql(u8, node.tag, "slider")) {
        renderSlider(event_ring, store, node_id, node, class_spec);
        node.markRendered();
        return;
    }
    if (std.mem.eql(u8, node.tag, "image")) {
        renderImage(event_ring, store, node_id, node, class_spec, allocator, tracker);
        node.markRendered();
        return;
    }
    if (std.mem.eql(u8, node.tag, "icon")) {
        renderIcon(event_ring, store, node_id, node, class_spec, allocator, tracker);
        node.markRendered();
        return;
    }
    if (std.mem.eql(u8, node.tag, "gizmo")) {
        renderGizmo(event_ring, store, node_id, node, class_spec);
        node.markRendered();
        return;
    }
    if (std.mem.eql(u8, node.tag, "triangle")) {
        renderTriangle(event_ring, store, node, allocator, class_spec, tracker);
        node.markRendered();
        return;
    }
    if (std.mem.eql(u8, node.tag, "p")) {
        renderParagraph(event_ring, store, node_id, node, allocator, class_spec, null, tracker);
        node.markRendered();
        return;
    }
    if (std.mem.eql(u8, node.tag, "h1")) {
        renderParagraph(event_ring, store, node_id, node, allocator, class_spec, .title, tracker);
        node.markRendered();
        return;
    }
    if (std.mem.eql(u8, node.tag, "h2")) {
        renderParagraph(event_ring, store, node_id, node, allocator, class_spec, .title_1, tracker);
        node.markRendered();
        return;
    }
    if (std.mem.eql(u8, node.tag, "h3")) {
        renderParagraph(event_ring, store, node_id, node, allocator, class_spec, .title_2, tracker);
        node.markRendered();
        return;
    }
    renderGeneric(event_ring, store, node, allocator, tracker);
    node.markRendered();
}

fn renderScrollFrame(
    event_ring: ?*events.EventRing,
    store: *types.NodeStore,
    node_id: u32,
    node: *types.SolidNode,
    allocator: std.mem.Allocator,
    class_spec: tailwind.ClassSpec,
    tracker: *DirtyRegionTracker,
) void {
    _ = node_id;
    var rect_opt = node.layout.rect;
    if (rect_opt == null) {
        const parent_rect = blk: {
            if (node.parent) |pid| {
                if (store.node(pid)) |parent| {
                    if (parent.layout.rect) |pr| break :blk pr;
                }
            }
            const win = dvui.currentWindow();
            break :blk types.Rect{
                .x = 0,
                .y = 0,
                .w = win.rect_pixels.w,
                .h = win.rect_pixels.h,
            };
        };
        layout.computeNodeLayout(store, node, parent_rect);
        rect_opt = node.layout.rect;
    }
    const rect = rect_opt orelse return;

    if (class_spec.background) |bg| {
        if (node.visual.background == null) {
            node.visual.background = dvuiColorToPacked(bg);
        }
    }
    renderCachedOrDirectBackground(node, rect, allocator, class_spec.background);

    const content_w = if (node.scroll.content_width > 0) node.scroll.content_width else rect.w;
    const content_h = if (node.scroll.content_height > 0) node.scroll.content_height else rect.h;

    var scroll_info = dvui.ScrollInfo{
        .vertical = if (content_h > rect.h) .auto else .none,
        .horizontal = if (content_w > rect.w) .auto else .none,
        .virtual_size = .{ .w = content_w, .h = content_h },
        .viewport = .{ .x = node.scroll.offset_x, .y = node.scroll.offset_y, .w = rect.w, .h = rect.h },
    };
    scroll_info.scrollToOffset(.vertical, scroll_info.viewport.y);
    scroll_info.scrollToOffset(.horizontal, scroll_info.viewport.x);

    const scroll_id = scrollContentId(node.id);
    const hit_rect = transformedRect(node, rect) orelse rect;
    const prev_x = node.scroll.offset_x;
    const prev_y = node.scroll.offset_y;

    _ = handleScrollInput(node, hit_rect, &scroll_info, scroll_id);

    renderChildrenOrdered(event_ring, store, node, allocator, tracker, false);

    _ = renderScrollBars(node, rect, &scroll_info, scroll_id);

    if (scroll_info.viewport.x != prev_x or scroll_info.viewport.y != prev_y) {
        node.scroll.offset_x = scroll_info.viewport.x;
        node.scroll.offset_y = scroll_info.viewport.y;
        layout.invalidateLayoutSubtree(store, node);
        store.markNodeChanged(node.id);

        if (event_ring) |ring| {
            if (node.hasListener("scroll")) {
                var detail_buffer: [192]u8 = undefined;
                const detail: []const u8 = std.fmt.bufPrint(
                    &detail_buffer,
                    "{{\"x\":{},\"y\":{},\"viewportW\":{},\"viewportH\":{},\"contentW\":{},\"contentH\":{}}}",
                    .{
                        scroll_info.viewport.x,
                        scroll_info.viewport.y,
                        scroll_info.viewport.w,
                        scroll_info.viewport.h,
                        scroll_info.virtual_size.w,
                        scroll_info.virtual_size.h,
                    },
                ) catch "";
                _ = ring.pushScroll(node.id, detail);
            }
        }
    }

    node.markRendered();
}

fn renderParagraphDirect(
    event_ring: ?*events.EventRing,
    store: *types.NodeStore,
    node_id: u32,
    node: *types.SolidNode,
    allocator: std.mem.Allocator,
    class_spec: tailwind.Spec,
    font_override: ?dvui.Options.FontStyle,
    rect: types.Rect,
    tracker: *DirtyRegionTracker,
) void {
    _ = node_id;
    const bounds = node.paint.painted_rect orelse transformedRect(node, rect) orelse rect;
    var text_buffer: std.ArrayList(u8) = .empty;
    defer text_buffer.deinit(allocator);

    // Draw paragraph background if present (cached geometry when available).
    renderCachedOrDirectBackground(node, rect, allocator, class_spec.background);

    collectText(allocator, store, node, &text_buffer);
    if (text_buffer.items.len > 0) {
        const trimmed = std.mem.trim(u8, text_buffer.items, " \n\r\t");
        if (trimmed.len > 0) {
            if (paragraph_log_count < 10) {
                paragraph_log_count += 1;
            }
            // Text rendering honors scale/translation via the transformed bounds; rotation is handled for backgrounds only.
            // Apply Tailwind padding and horizontal alignment manually for the direct draw path.
            const natural_scale = dvui.windowNaturalScale();
            const layout_scale = if (node.layout.layout_scale != 0) node.layout.layout_scale else natural_scale;
            const pad_left = (class_spec.padding.left orelse 0) * layout_scale;
            const pad_right = (class_spec.padding.right orelse 0) * layout_scale;
            const pad_top = (class_spec.padding.top orelse 0) * layout_scale;
            const pad_bottom = (class_spec.padding.bottom orelse 0) * layout_scale;

            var text_rect = bounds;
            text_rect.x += pad_left;
            text_rect.y += pad_top;
            text_rect.w = @max(0.0, text_rect.w - (pad_left + pad_right));
            text_rect.h = @max(0.0, text_rect.h - (pad_top + pad_bottom));

            var options = dvui.Options{};
            style_apply.applyToOptions(&class_spec, &options);
            if (font_override) |style_name| {
                options.font_style = style_name;
            }
            style_apply.resolveFont(&class_spec, &options);
            const base_font = options.fontGet();
            const font_scale = if (natural_scale != 0) layout_scale / natural_scale else 1.0;
            const draw_font = if (font_scale != 1.0) base_font.resize(base_font.size * font_scale) else base_font;
            text_wrap.computeLineBreaks(
                store.allocator,
                &node.layout.text_layout,
                trimmed,
                base_font,
                text_rect.w,
                layout_scale,
                class_spec.text_wrap,
                class_spec.break_words,
            );
            const text_layout = node.layout.text_layout;
            var line_index: usize = 0;
            while (line_index < text_layout.lines.items.len) : (line_index += 1) {
                const line = text_layout.lines.items[line_index];
                if (line.len == 0) continue;
                const line_text = trimmed[line.start .. line.start + line.len];
                const line_y = text_rect.y + @as(f32, @floatFromInt(line_index)) * text_layout.line_height;
                var line_x = text_rect.x;
                if (class_spec.text_align) |text_align| {
                    switch (text_align) {
                        .center => line_x += (text_rect.w - line.width) / 2.0,
                        .right => line_x += (text_rect.w - line.width),
                        else => {},
                    }
                }
                const line_rect = types.Rect{
                    .x = line_x,
                    .y = line_y,
                    .w = line.width,
                    .h = text_layout.line_height,
                };
                drawTextDirect(line_rect, line_text, node.visual, draw_font);
            }
        }
    }

    // Paragraph already draws its text nodes; render non-text children (z-index ordered).
    renderChildrenOrdered(event_ring, store, node, allocator, tracker, true);
    node.markRendered();
}

fn renderInteractiveElement(
    event_ring: ?*events.EventRing,
    store: *types.NodeStore,
    node_id: u32,
    node: *types.SolidNode,
    allocator: std.mem.Allocator,
    class_spec: tailwind.ClassSpec,
    tracker: *DirtyRegionTracker,
) void {
    // Placeholder: today interactive and non-interactive elements use the same DVUI path.
    // This wrapper marks the split point for routing to DVUI widgets to preserve focus/input.
    renderElementBody(event_ring, store, node_id, node, allocator, class_spec, tracker);
}

fn renderNonInteractiveElement(
    event_ring: ?*events.EventRing,
    store: *types.NodeStore,
    node_id: u32,
    node: *types.SolidNode,
    allocator: std.mem.Allocator,
    class_spec: tailwind.ClassSpec,
    tracker: *DirtyRegionTracker,
) void {
    // Always draw non-interactive elements directly so backgrounds are guaranteed,
    // then recurse into children. This bypasses DVUI background handling.
    renderNonInteractiveDirect(event_ring, store, node_id, node, allocator, class_spec, tracker);
}

fn renderContainer(
    event_ring: ?*events.EventRing,
    store: *types.NodeStore,
    node: *types.SolidNode,
    allocator: std.mem.Allocator,
    class_spec: tailwind.ClassSpec,
    tracker: *DirtyRegionTracker,
) void {
    // Ensure a background color is present for container nodes.
    if (class_spec.background) |bg| {
        if (node.visual.background == null) {
            node.visual.background = dvuiColorToPacked(bg);
        }
    }

    if (node.layout.rect) |rect| {
        // Draw background ourselves so containers always show their fill.
        renderCachedOrDirectBackground(node, rect, allocator, class_spec.background);
    }

    const tab_info = focus.tabIndexForNode(store, node);

    var options = dvui.Options{
        .name = "solid-div",
        .background = false,
        .expand = .none,
        .id_extra = nodeIdExtra(node.id),
    };
    style_apply.applyToOptions(&class_spec, &options);
    style_apply.resolveFont(&class_spec, &options);
    applyLayoutScaleToOptions(node, &options);
    applyVisualToOptions(node, &options);
    applyTransformToOptions(node, &options);
    applyAccessibilityOptions(node, &options, .generic_container);
    if (node.layout.rect) |rect| {
        options.rect = physicalToDvuiRect(rect);
    }

    var box = dvui.box(@src(), .{}, options);
    defer box.deinit();
    applyAccessibilityState(node, box.data());

    if (tab_info.focusable and allowFocusRegistration()) {
        dvui.tabIndexSet(box.data().id, tab_info.tab_index);
        focus.registerFocusable(store, node, box.data());
    }

    renderChildrenOrdered(event_ring, store, node, allocator, tracker, false);
    if (input_enabled_state) {
        drag_drop.handleDiv(event_ring, store, node, box.data());
    }
    node.markRendered();
}

fn renderFlexChildren(
    event_ring: ?*events.EventRing,
    store: *types.NodeStore,
    node: *types.SolidNode,
    allocator: std.mem.Allocator,
    class_spec: *const tailwind.Spec,
    tracker: *DirtyRegionTracker,
) void {
    const direction = style_apply.flexDirection(class_spec);
    const gap_main = switch (direction) {
        .horizontal => class_spec.gap_col,
        .vertical => class_spec.gap_row,
    } orelse 0;

    var child_index: usize = 0;
    for (node.children.items) |child_id| {
        if (gap_main > 0 and child_index > 0) {
            var margin = dvui.Rect{};
            switch (direction) {
                .horizontal => margin.x = gap_main,
                .vertical => margin.y = gap_main,
            }
            const _child_index: u32 = @intCast(child_index);
            var spacer = dvui.box(
                @src(),
                .{},
                .{ .margin = margin, .background = false, .name = "solid-gap", .id_extra = nodeIdExtra(node.id ^ _child_index) },
            );
            defer spacer.deinit();
            renderNode(event_ring, store, child_id, allocator, tracker);
        } else {
            renderNode(event_ring, store, child_id, allocator, tracker);
        }
        child_index += 1;
    }
}

fn renderGeneric(
    event_ring: ?*events.EventRing,
    store: *types.NodeStore,
    node: *types.SolidNode,
    allocator: std.mem.Allocator,
    tracker: *DirtyRegionTracker,
) void {
    renderChildrenOrdered(event_ring, store, node, allocator, tracker, false);
}

fn renderNonInteractiveDirect(
    event_ring: ?*events.EventRing,
    store: *types.NodeStore,
    node_id: u32,
    node: *types.SolidNode,
    allocator: std.mem.Allocator,
    class_spec: tailwind.ClassSpec,
    tracker: *DirtyRegionTracker,
) void {
    var rect_opt = node.layout.rect;
    if (rect_opt == null) {
        // Compute a fallback layout on-demand using the parent's rect (or screen) so backgrounds still render.
        const parent_rect = blk: {
            if (node.parent) |pid| {
                if (store.node(pid)) |parent| {
                    if (parent.layout.rect) |pr| break :blk pr;
                }
            }
            const win = dvui.currentWindow();
            break :blk types.Rect{
                .x = 0,
                .y = 0,
                .w = win.rect_pixels.w,
                .h = win.rect_pixels.h,
            };
        };
        layout.computeNodeLayout(store, node, parent_rect);
        rect_opt = node.layout.rect;
    }

    const rect = rect_opt orelse {
        renderElementBody(event_ring, store, node_id, node, allocator, class_spec, tracker);
        return;
    };

    // const bounds = node.paint.painted_rect orelse transformedRect(node, rect) orelse rect;

    if (std.mem.eql(u8, node.tag, "div")) {
        renderCachedOrDirectBackground(node, rect, allocator, class_spec.background);
        renderChildrenOrdered(event_ring, store, node, allocator, tracker, false);
        node.markRendered();
        return;
    }

    if (std.mem.eql(u8, node.tag, "p")) {
        renderParagraphDirect(event_ring, store, node_id, node, allocator, class_spec, null, rect, tracker);
        return;
    }
    if (std.mem.eql(u8, node.tag, "h1")) {
        renderParagraphDirect(event_ring, store, node_id, node, allocator, class_spec, .title, rect, tracker);
        return;
    }
    if (std.mem.eql(u8, node.tag, "h2")) {
        renderParagraphDirect(event_ring, store, node_id, node, allocator, class_spec, .title_1, rect, tracker);
        return;
    }
    if (std.mem.eql(u8, node.tag, "h3")) {
        renderParagraphDirect(event_ring, store, node_id, node, allocator, class_spec, .title_2, rect, tracker);
        return;
    }

    // Fallback to DVUI path for tags without a direct draw handler.
    renderElementBody(event_ring, store, node_id, node, allocator, class_spec, tracker);
}

fn renderGizmo(
    event_ring: ?*events.EventRing,
    store: *types.NodeStore,
    node_id: u32,
    node: *types.SolidNode,
    class_spec: tailwind.Spec,
) void {
    _ = event_ring;
    _ = store;
    _ = node_id;
    _ = class_spec;
    applyGizmoProp(node);
}

fn renderTriangle(
    event_ring: ?*events.EventRing,
    store: *types.NodeStore,
    node: *types.SolidNode,
    allocator: std.mem.Allocator,
    class_spec: tailwind.Spec,
    tracker: *DirtyRegionTracker,
) void {
    var rect_opt = node.layout.rect;
    if (rect_opt == null) {
        const parent_rect = blk: {
            if (node.parent) |pid| {
                if (store.node(pid)) |parent| {
                    if (parent.layout.rect) |pr| break :blk pr;
                }
            }
            const win = dvui.currentWindow();
            break :blk types.Rect{
                .x = 0,
                .y = 0,
                .w = win.rect_pixels.w,
                .h = win.rect_pixels.h,
            };
        };
        layout.computeNodeLayout(store, node, parent_rect);
        rect_opt = node.layout.rect;
    }
    const rect = rect_opt orelse return;
    drawTriangleDirect(rect, node.visual, node.transform, allocator, class_spec.background);
    renderChildElements(event_ring, store, node, allocator, tracker);
}

fn renderParagraph(
    event_ring: ?*events.EventRing,
    store: *types.NodeStore,
    node_id: u32,
    node: *types.SolidNode,
    allocator: std.mem.Allocator,
    class_spec: tailwind.Spec,
    font_override: ?dvui.Options.FontStyle,
    tracker: *DirtyRegionTracker,
) void {
    var text_buffer: std.ArrayList(u8) = .empty;
    defer text_buffer.deinit(allocator);

    if (node.layout.rect) |rect| {
        renderCachedOrDirectBackground(node, rect, allocator, class_spec.background);
    }

    collectText(allocator, store, node, &text_buffer);
    if (text_buffer.items.len > 0) {
        const trimmed = std.mem.trim(u8, text_buffer.items, " \n\r\t");
        if (trimmed.len > 0) {
            var options = dvui.Options{
                .id_extra = nodeIdExtra(node_id),
            };
            style_apply.applyToOptions(&class_spec, &options);
            applyVisualToOptions(node, &options);
            applyTransformToOptions(node, &options);
            if (font_override) |style_name| {
                if (options.font_style == null) {
                    options.font_style = style_name;
                }
            }
            style_apply.resolveFont(&class_spec, &options);
            dvui.labelNoFmt(@src(), trimmed, .{}, options);
        }
    }

    renderChildElements(event_ring, store, node, allocator, tracker);
}

fn applyGizmoProp(node: *types.SolidNode) void {
    const override = gizmo_override_rect;
    const attr_rect = node.gizmoRect();
    const has_new_attr = attr_rect != null and node.lastAppliedGizmoRectSerial() != node.gizmoRectSerial();

    const prop = if (has_new_attr)
        attr_rect.?
    else
        override orelse attr_rect orelse return;

    node.setGizmoRuntimeRect(prop);

    if (has_new_attr) {
        node.markGizmoRectApplied();
        gizmo_rect_pending = prop;
    }
}

fn renderText(store: *types.NodeStore, node: *types.SolidNode) void {
    const trimmed = std.mem.trim(u8, node.text, " \n\r\t");
    if (trimmed.len > 0) {
        var options = dvui.Options{ .id_extra = nodeIdExtra(node.id) };
        if (node.parent) |pid| {
            if (store.node(pid)) |parent| {
                var parent_spec = parent.prepareClassSpec();
                tailwind.applyHover(&parent_spec, parent.hovered);
                style_apply.applyToOptions(&parent_spec, &options);
                style_apply.resolveFont(&parent_spec, &options);
            }
        }
        applyLayoutScaleToOptions(node, &options);
        applyVisualToOptions(node, &options);
        applyTransformToOptions(node, &options);
        applyAccessibilityOptions(node, &options, null);
        var lw = dvui.LabelWidget.initNoFmt(@src(), trimmed, .{}, options);
        lw.install();
        applyAccessibilityState(node, lw.data());
        lw.draw();
        lw.deinit();
    }
    node.markRendered();
}

fn renderButton(
    event_ring: ?*events.EventRing,
    store: *types.NodeStore,
    node_id: u32,
    node: *types.SolidNode,
    allocator: std.mem.Allocator,
    class_spec: tailwind.Spec,
    tracker: *DirtyRegionTracker,
) void {
    const text = buildText(store, node, allocator);
    const trimmed = std.mem.trim(u8, text, " \n\r\t");
    const caption = if (trimmed.len == 0) "Button" else trimmed;
    if (!logged_button_render) {
        logged_button_render = true;
    }

    // Ensure we have a concrete rect; if layout is missing, compute a fallback using the parent rect/screen.
    var rect_opt = node.layout.rect;
    if (rect_opt == null) {
        const parent_rect = blk: {
            if (node.parent) |pid| {
                if (store.node(pid)) |parent| {
                    if (parent.layout.rect) |pr| break :blk pr;
                }
            }
            const win = dvui.currentWindow();
            break :blk types.Rect{
                .x = 0,
                .y = 0,
                .w = win.rect_pixels.w,
                .h = win.rect_pixels.h,
            };
        };
        layout.computeNodeLayout(store, node, parent_rect);
        rect_opt = node.layout.rect;
    }

    var options = dvui.Options{
        .id_extra = nodeIdExtra(node_id),
        .padding = dvui.Rect.all(6),
        // Respect layout positions exactly; DVUI's default button margin would offset the rect.
        .margin = dvui.Rect{},
    };
    const tab_info = focus.tabIndexForNode(store, node);
    const focus_allowed = allowFocusRegistration();
    if (tab_info.focusable and focus_allowed) {
        options.tab_index = tab_info.tab_index;
    }
    style_apply.applyToOptions(&class_spec, &options);
    style_apply.resolveFont(&class_spec, &options);
    applyLayoutScaleToOptions(node, &options);
    applyVisualToOptions(node, &options);
    applyTransformToOptions(node, &options);
    applyAccessibilityOptions(node, &options, null);
    if (rect_opt) |rect| {
        options.rect = physicalToDvuiRect(rect);
    }

    if (button_debug_count < 5) {
        button_debug_count += 1;
    }

    // Use ButtonWidget directly instead of dvui.button() to ensure unique widget IDs.
    // The issue with dvui.button(@src(), ...) is that @src() returns the same source location
    // for every button rendered through this function, causing all buttons to share the same
    // DVUI widget ID. This breaks click detection and event dispatch.
    // By using ButtonWidget directly with id_extra set to a hash of node_id, each button
    // gets a unique ID even though they all originate from the same source location.
    var bw = dvui.ButtonWidget.init(@src(), .{ .draw_focus = false }, options);
    bw.install();
    applyAccessibilityState(node, bw.data());
    if (tab_info.focusable and focus_allowed) {
        focus.registerFocusable(store, node, bw.data());
    }
    if (input_enabled_state) {
        bw.processEvents();
    }
    bw.drawBackground();

    // Draw caption directly (avoid relying on LabelWidget sizing/refresh timing).
    // This fixes cases where button text doesn't appear until a later repaint.
    const content_rs = bw.data().contentRectScale();
    var text_style = options.strip().override(bw.style());
    applyLayoutScaleToOptions(node, &text_style);
    const font = text_style.fontGet();
    const size_nat = font.textSize(caption);
    const text_w = size_nat.w * content_rs.s;
    const text_h = size_nat.h * content_rs.s;

    var text_rs = content_rs;
    if (text_w < text_rs.r.w) text_rs.r.x += (text_rs.r.w - text_w) * 0.5;
    if (text_h < text_rs.r.h) text_rs.r.y += (text_rs.r.h - text_h) * 0.5;
    text_rs.r.w = text_w;
    text_rs.r.h = text_h;

    const prev_clip = dvui.clip(content_rs.r);
    defer dvui.clipSet(prev_clip);
    dvui.renderText(.{
        .font = font,
        .text = caption,
        .rs = text_rs,
        .color = text_style.color(.text),
    }) catch |err| {
        if (button_text_error_log_count < 8) {
            button_text_error_log_count += 1;
            log.err("button caption renderText failed node={d}: {s}", .{ node_id, @errorName(err) });
        }
    };

    bw.drawFocus();
    const pressed = if (input_enabled_state) bw.clicked() else false;
    bw.deinit();

    if (pressed) {
        log.info("button pressed node={d} has_listener={}", .{ node_id, node.hasListener("click") });
        if (node.hasListener("click")) {
            if (event_ring) |ring| {
                const ok = ring.pushClick(node_id);
                log.info("button dispatched via ring node={d} ok={}", .{ node_id, ok });
            }
        }
    }

    renderChildElements(event_ring, store, node, allocator, tracker);
}

fn renderIcon(
    event_ring: ?*events.EventRing,
    store: *types.NodeStore,
    node_id: u32,
    node: *types.SolidNode,
    class_spec: tailwind.Spec,
    allocator: std.mem.Allocator,
    tracker: *DirtyRegionTracker,
) void {
    const src = node.imageSource();
    const glyph = node.iconGlyph();
    const resolved = icon_registry.resolve(node.iconKind(), src, glyph) catch |err| {
        if (src.len > 0) {
            log.err("Solid icon load failed for {s}: {s}", .{ src, @errorName(err) });
        } else {
            log.err("Solid icon load failed for node {d}: {s}", .{ node_id, @errorName(err) });
        }
        return;
    };

    var options = dvui.Options{
        .name = "solid-icon",
        .id_extra = nodeIdExtra(node_id),
    };
    style_apply.applyToOptions(&class_spec, &options);
    style_apply.resolveFont(&class_spec, &options);
    applyLayoutScaleToOptions(node, &options);
    applyVisualToOptions(node, &options);
    applyTransformToOptions(node, &options);
    applyAccessibilityOptions(node, &options, null);

    switch (resolved) {
        .vector => |tvg_bytes| {
            const icon_name = if (src.len > 0) src else "solid-icon";
            var iw = dvui.IconWidget.init(@src(), icon_name, tvg_bytes, .{}, options);
            iw.install();
            applyAccessibilityState(node, iw.data());
            iw.draw();
            iw.deinit();
        },
        .raster => |resource| {
            const image_source = image_loader.imageSource(resource);
            var wd = dvui.image(@src(), .{ .source = image_source }, options);
            applyAccessibilityState(node, &wd);
        },
        .glyph => |text| {
            var lw = dvui.LabelWidget.initNoFmt(@src(), text, .{}, options);
            lw.install();
            applyAccessibilityState(node, lw.data());
            lw.draw();
            lw.deinit();
        },
    }

    renderChildElements(event_ring, store, node, allocator, tracker);
}

fn renderImage(
    event_ring: ?*events.EventRing,
    store: *types.NodeStore,
    node_id: u32,
    node: *types.SolidNode,
    class_spec: tailwind.Spec,
    allocator: std.mem.Allocator,
    tracker: *DirtyRegionTracker,
) void {
    const src = node.imageSource();
    if (src.len == 0) {
        log.warn("Solid image node {d} missing src", .{node_id});
        return;
    }

    const resource = image_loader.load(src) catch |err| {
        log.err("Solid image load failed for {s}: {s}", .{ src, @errorName(err) });
        return;
    };

    var options = dvui.Options{
        .name = "solid-image",
        .id_extra = nodeIdExtra(node_id),
    };
    style_apply.applyToOptions(&class_spec, &options);
    style_apply.resolveFont(&class_spec, &options);
    applyLayoutScaleToOptions(node, &options);
    applyVisualToOptions(node, &options);
    applyTransformToOptions(node, &options);
    applyAccessibilityOptions(node, &options, null);

    const image_source = image_loader.imageSource(resource);
    var wd = dvui.image(@src(), .{ .source = image_source }, options);
    applyAccessibilityState(node, &wd);

    renderChildElements(event_ring, store, node, allocator, tracker);
}

fn renderSlider(
    event_ring: ?*events.EventRing,
    store: *types.NodeStore,
    node_id: u32,
    node: *types.SolidNode,
    class_spec: tailwind.Spec,
) void {
    var options = dvui.slider_defaults.override(.{
        .name = "solid-slider",
        .id_extra = nodeIdExtra(node_id),
    });
    style_apply.applyToOptions(&class_spec, &options);
    style_apply.resolveFont(&class_spec, &options);
    applyLayoutScaleToOptions(node, &options);
    applyVisualToOptions(node, &options);
    applyTransformToOptions(node, &options);
    applyAccessibilityOptions(node, &options, .slider);

    if (node.layout.rect) |rect| {
        options.rect = physicalToDvuiRect(rect);
    }

    const tab_info = focus.tabIndexForNode(store, node);
    const focus_allowed = allowFocusRegistration();
    if (tab_info.focusable and focus_allowed) {
        options.tab_index = tab_info.tab_index;
    }

    const state = node.ensureInputState(store.allocator) catch |err| {
        log.err("Solid slider state init failed for node {d}: {s}", .{ node_id, @errorName(err) });
        return;
    };

    state.syncBufferFromValue() catch |err| {
        log.err("Solid slider buffer sync failed for node {d}: {s}", .{ node_id, @errorName(err) });
        return;
    };

    var fraction: f32 = 0;
    const current_text = state.currentText();
    if (current_text.len > 0) {
        fraction = std.fmt.parseFloat(f32, current_text) catch 0;
    }
    fraction = @max(0, @min(1, fraction));

    const direction: dvui.enums.Direction = .horizontal;

    var slider_box = dvui.box(@src(), .{ .dir = direction }, options);
    defer slider_box.deinit();
    applyAccessibilityState(node, slider_box.data());
    if (tab_info.focusable and focus_allowed) {
        focus.registerFocusable(store, node, slider_box.data());
    }

    if (slider_box.data().accesskit_node()) |ak_node| {
        dvui.AccessKit.nodeAddAction(ak_node, dvui.AccessKit.Action.focus);
        dvui.AccessKit.nodeAddAction(ak_node, dvui.AccessKit.Action.set_value);
        dvui.AccessKit.nodeSetOrientation(ak_node, dvui.AccessKit.Orientation.horizontal);
        dvui.AccessKit.nodeSetNumericValue(ak_node, fraction);
        dvui.AccessKit.nodeSetMinNumericValue(ak_node, 0);
        dvui.AccessKit.nodeSetMaxNumericValue(ak_node, 1);
    }

    const br = slider_box.data().contentRect();
    const knobsize = @min(br.w, br.h);
    const track = switch (direction) {
        .horizontal => dvui.Rect{ .x = knobsize / 2, .y = br.h / 2 - 2, .w = br.w - knobsize, .h = 4 },
        .vertical => dvui.Rect{ .x = br.w / 2 - 2, .y = knobsize / 2, .w = 4, .h = br.h - knobsize },
    };
    const trackrs = slider_box.widget().screenRectScale(track);
    const rs = slider_box.data().contentRectScale();

    var hovered = false;
    var changed = false;
    var prev_focused = state.focused;
    var focused_now = false;

    if (input_enabled_state) {
        if (tab_info.focusable and focus_allowed) {
            dvui.tabIndexSet(slider_box.data().id, tab_info.tab_index);
        }

        for (dvui.events()) |*e| {
            if (!dvui.eventMatch(e, .{ .id = slider_box.data().id, .r = rs.r }))
                continue;

            switch (e.evt) {
                .mouse => |me| {
                    var p: ?dvui.Point.Physical = null;
                    if (me.action == .focus) {
                        e.handle(@src(), slider_box.data());
                        dvui.focusWidget(slider_box.data().id, null, e.num);
                    } else if (me.action == .press and me.button.pointer()) {
                        dvui.captureMouse(slider_box.data(), e.num);
                        e.handle(@src(), slider_box.data());
                        p = me.p;
                    } else if (me.action == .release and me.button.pointer()) {
                        dvui.captureMouse(null, e.num);
                        dvui.dragEnd();
                        e.handle(@src(), slider_box.data());
                    } else if (me.action == .motion and dvui.captured(slider_box.data().id)) {
                        e.handle(@src(), slider_box.data());
                        p = me.p;
                    } else if (me.action == .position) {
                        dvui.cursorSet(class_spec.cursor orelse .arrow);
                        hovered = true;
                    }

                    if (p) |pp| {
                        var min_val: f32 = undefined;
                        var max_val: f32 = undefined;
                        switch (direction) {
                            .horizontal => {
                                min_val = trackrs.r.x;
                                max_val = trackrs.r.x + trackrs.r.w;
                            },
                            .vertical => {
                                min_val = 0;
                                max_val = trackrs.r.h;
                            },
                        }

                        if (max_val > min_val) {
                            const v = if (direction == .horizontal) pp.x else (trackrs.r.y + trackrs.r.h - pp.y);
                            fraction = (v - min_val) / (max_val - min_val);
                            fraction = @max(0, @min(1, fraction));
                            changed = true;
                        }
                    }
                },
                .key => |ke| {
                    if (ke.action == .down or ke.action == .repeat) {
                        switch (ke.code) {
                            .left, .down => {
                                e.handle(@src(), slider_box.data());
                                fraction = @max(0, @min(1, fraction - 0.05));
                                changed = true;
                            },
                            .right, .up => {
                                e.handle(@src(), slider_box.data());
                                fraction = @max(0, @min(1, fraction + 0.05));
                                changed = true;
                            },
                            else => {},
                        }
                    }
                },
                .text => |te| {
                    e.handle(@src(), slider_box.data());
                    const value: f32 = std.fmt.parseFloat(f32, te.txt) catch continue;
                    fraction = @max(0, @min(1, value));
                    changed = true;
                },
                else => {},
            }
        }

        focused_now = dvui.focusedWidgetId() == slider_box.data().id;
        state.focused = focused_now;
    } else {
        state.focused = false;
        prev_focused = false;
    }

    if (input_enabled_state) {
        if (event_ring) |ring| {
            if (!prev_focused and focused_now and node.hasListener("focus")) {
                _ = ring.pushFocus(node_id);
            } else if (prev_focused and !focused_now and node.hasListener("blur")) {
                _ = ring.pushBlur(node_id);
            }
        }
    }

    const perc = @max(0, @min(1, fraction));
    if (fraction != perc) {
        fraction = perc;
        changed = true;
    }

    var part = trackrs.r;
    switch (direction) {
        .horizontal => part.w *= perc,
        .vertical => {
            const h = part.h * (1 - perc);
            part.y += h;
            part.h = trackrs.r.h - h;
        },
    }
    if (slider_box.data().visible()) {
        part.fill(options.corner_radiusGet().scale(trackrs.s, dvui.Rect.Physical), .{
            .color = dvui.themeGet().color(.highlight, .fill),
            .fade = 1.0,
        });
    }

    switch (direction) {
        .horizontal => {
            part.x = part.x + part.w;
            part.w = trackrs.r.w - part.w;
        },
        .vertical => {
            part = trackrs.r;
            part.h *= (1 - perc);
        },
    }
    if (slider_box.data().visible()) {
        part.fill(options.corner_radiusGet().scale(trackrs.s, dvui.Rect.Physical), .{
            .color = options.color(.fill),
            .fade = 1.0,
        });
    }

    const knobRect = switch (direction) {
        .horizontal => dvui.Rect{ .x = (br.w - knobsize) * perc, .w = knobsize, .h = knobsize },
        .vertical => dvui.Rect{ .y = (br.h - knobsize) * (1 - perc), .w = knobsize, .h = knobsize },
    };

    const fill_color: dvui.Color = if (dvui.captured(slider_box.data().id))
        options.color(.fill_press)
    else if (hovered)
        options.color(.fill_hover)
    else
        options.color(.fill);

    var knob = dvui.BoxWidget.init(
        @src(),
        .{ .dir = .horizontal },
        .{
            .rect = knobRect,
            .padding = .{},
            .margin = .{},
            .background = true,
            .border = dvui.Rect.all(1),
            .corner_radius = dvui.Rect.all(100),
            .color_fill = fill_color,
        },
    );
    knob.install();
    knob.drawBackground();
    if (slider_box.data().id == dvui.focusedWidgetId()) {
        knob.data().focusBorder();
    }
    knob.deinit();

    if (changed) {
        var value_buffer: [32]u8 = undefined;
        const value_str = std.fmt.bufPrint(&value_buffer, "{d}", .{fraction}) catch "";
        state.updateFromText(value_str) catch |err| {
            log.err("Solid slider state update failed for node {d}: {s}", .{ node_id, @errorName(err) });
        };
        store.markNodeChanged(node_id);
        if (event_ring) |ring| {
            if (node.hasListener("input")) {
                _ = ring.pushInput(node_id, value_str);
            }
        }
        dvui.refresh(null, @src(), slider_box.data().id);
    }
}

fn renderInput(
    event_ring: ?*events.EventRing,
    store: *types.NodeStore,
    node_id: u32,
    node: *types.SolidNode,
    class_spec: tailwind.Spec,
) void {
    var options = dvui.Options{
        .name = "solid-input",
        .id_extra = nodeIdExtra(node_id),
        .background = true,
    };
    style_apply.applyToOptions(&class_spec, &options);
    style_apply.resolveFont(&class_spec, &options);
    applyLayoutScaleToOptions(node, &options);
    applyVisualToOptions(node, &options);
    applyTransformToOptions(node, &options);
    applyAccessibilityOptions(node, &options, .text_input);

    const tab_info = focus.tabIndexForNode(store, node);
    const focus_allowed = allowFocusRegistration();

    var state = node.ensureInputState(store.allocator) catch |err| {
        log.err("Solid input state init failed for node {d}: {s}", .{ node_id, @errorName(err) });
        return;
    };

    state.syncBufferFromValue() catch |err| {
        log.err("Solid input buffer sync failed for node {d}: {s}", .{ node_id, @errorName(err) });
        return;
    };
    // Preserve the actual text length; buffer may retain extra capacity for future edits.
    if (state.text_len > state.buffer.len) {
        state.text_len = state.buffer.len;
    }
    if (state.buffer.len > state.text_len) {
        state.buffer[state.text_len] = 0;
    }

    var box = dvui.BoxWidget.init(@src(), .{}, options);
    box.install();
    defer box.deinit();

    const wd = box.data();
    applyAccessibilityState(node, wd);
    if (tab_info.focusable and focus_allowed) {
        focus.registerFocusable(store, node, wd);
    }
    var prev_focused = state.focused;
    var focused_now = false;
    var text_changed = false;

    if (input_enabled_state) {
        if (tab_info.focusable and focus_allowed) {
            dvui.tabIndexSet(wd.id, tab_info.tab_index);
        }

        var hovered = false;
        _ = dvui.clickedEx(wd, .{ .hovered = &hovered, .hover_cursor = class_spec.cursor orelse .ibeam });

        focused_now = dvui.focusedWidgetId() == wd.id;
        state.focused = focused_now;

        if (focused_now) {
            const rs = wd.contentRectScale();
            const natural = dvui.Rect.Natural.cast(rs.rectFromPhysical(rs.r));
            dvui.wantTextInput(natural);
        }

        for (dvui.events()) |*e| {
            if (!dvui.eventMatch(e, .{ .id = wd.id, .r = wd.borderRectScale().r })) continue;

            switch (e.evt) {
                .text => |te| {
                    if (te.txt.len == 0) break;
                    const new_len = state.text_len + te.txt.len;
                    state.ensureCapacity(new_len + 1) catch |err| {
                        log.err("Solid input ensureCapacity failed for node {d}: {s}", .{ node_id, @errorName(err) });
                        break;
                    };
                    @memcpy(state.buffer[state.text_len .. state.text_len + te.txt.len], te.txt);
                    if (state.buffer.len > new_len) {
                        state.buffer[new_len] = 0;
                    }
                    state.text_len = new_len;
                    state.updateFromText(state.buffer[0..new_len]) catch |err| {
                        log.err("Solid input update failed for node {d}: {s}", .{ node_id, @errorName(err) });
                        break;
                    };
                    store.markNodeChanged(node_id);
                    text_changed = true;
                    e.handle(@src(), wd);
                },
                .key => |ke| {
                    if (ke.action != .down and ke.action != .repeat) break;
                    switch (ke.code) {
                        .backspace => {
                            if (state.text_len == 0) break;
                            const new_len = dvui.findUtf8Start(state.buffer[0..state.text_len], state.text_len);
                            if (state.buffer.len > new_len) {
                                state.buffer[new_len] = 0;
                            }
                            state.text_len = new_len;
                            state.updateFromText(state.buffer[0..new_len]) catch |err| {
                                log.err("Solid input backspace update failed for node {d}: {s}", .{ node_id, @errorName(err) });
                                break;
                            };
                            store.markNodeChanged(node_id);
                            text_changed = true;
                            e.handle(@src(), wd);
                        },
                        else => {},
                    }
                },
                else => {},
            }
        }
    } else {
        state.focused = false;
        prev_focused = false;
    }

    box.drawBackground();
    const rs = wd.contentRectScale();
    const text_rect_nat = rs.rectFromPhysical(rs.r);
    const text_rect = types.Rect{
        .x = text_rect_nat.x,
        .y = text_rect_nat.y,
        .w = text_rect_nat.w,
        .h = text_rect_nat.h,
    };
    const text_slice = state.currentText();
    direct.drawTextDirect(text_rect, text_slice, node.visual, wd.options.fontGet());

    if (input_enabled_state) {
        if (event_ring) |ring| {
            if (!prev_focused and focused_now and node.hasListener("focus")) {
                _ = ring.pushFocus(node_id);
            } else if (prev_focused and !focused_now and node.hasListener("blur")) {
                _ = ring.pushBlur(node_id);
            }

            if (text_changed and node.hasListener("input")) {
                const payload = state.currentText();
                _ = ring.pushInput(node_id, payload);
            }
        }
    }
}

fn renderChildElements(
    event_ring: ?*events.EventRing,
    store: *types.NodeStore,
    node: *types.SolidNode,
    allocator: std.mem.Allocator,
    tracker: *DirtyRegionTracker,
) void {
    renderChildrenOrdered(event_ring, store, node, allocator, tracker, true);
}

fn renderChildrenOrdered(
    event_ring: ?*events.EventRing,
    store: *types.NodeStore,
    node: *types.SolidNode,
    allocator: std.mem.Allocator,
    tracker: *DirtyRegionTracker,
    skip_text: bool,
) void {
    if (node.children.items.len == 0) return;

    var prev_clip: ?dvui.Rect.Physical = null;
    if (node.visual.clip_children) {
        if (node.layout.rect) |rect| {
            const bounds = transformedRect(node, rect) orelse rect;
            const clip_rect = dvui.Rect.Physical{
                .x = bounds.x,
                .y = bounds.y,
                .w = bounds.w,
                .h = bounds.h,
            };
            prev_clip = dvui.clip(clip_rect);
        }
    }
    defer if (prev_clip) |prev| dvui.clipSet(prev);

    var any_z = false;
    for (node.children.items) |child_id| {
        const child = store.node(child_id) orelse continue;
        if (skip_text and child.kind == .text) continue;
        if (child.visual.z_index != 0) any_z = true;
    }

    if (!any_z) {
        for (node.children.items) |child_id| {
            const child = store.node(child_id) orelse continue;
            if (skip_text and child.kind == .text) continue;
            renderNode(event_ring, store, child_id, allocator, tracker);
        }
        return;
    }

    var ordered: std.ArrayList(OrderedNode) = .empty;
    defer ordered.deinit(allocator);

    for (node.children.items, 0..) |child_id, order_index| {
        const child = store.node(child_id) orelse continue;
        if (skip_text and child.kind == .text) continue;
        const z_index = child.visual.z_index;
        ordered.append(allocator, .{
            .id = child_id,
            .z_index = z_index,
            .order = order_index,
        }) catch {};
    }

    if (ordered.items.len == 0) return;
    sortOrderedNodes(ordered.items);

    for (ordered.items) |entry| {
        renderNode(event_ring, store, entry.id, allocator, tracker);
    }
}

fn buildText(
    store: *types.NodeStore,
    node: *const types.SolidNode,
    allocator: std.mem.Allocator,
) []const u8 {
    var list: std.ArrayList(u8) = .empty;
    errdefer list.deinit(allocator);
    collectText(allocator, store, node, &list);
    if (list.items.len == 0) {
        list.deinit(allocator);
        return "";
    }
    const owned = list.toOwnedSlice(allocator) catch {
        list.deinit(allocator);
        return "";
    };
    return owned;
}

fn collectText(
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
                collectText(allocator, store, child, into);
            }
        },
    }
}

fn nodeIdExtra(id: u32) usize {
    var hasher = std.hash.Wyhash.init(0);
    hasher.update(std.mem.asBytes(&id));
    return @intCast(hasher.final());
}
