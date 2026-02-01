const std = @import("std");
const dvui = @import("dvui");
const types = @import("core/types.zig");
const direct = @import("render/direct.zig");
const tailwind = @import("style/tailwind.zig");
pub const NodeStore = types.NodeStore;
pub const SolidNode = types.SolidNode;
pub const Rect = types.Rect;
pub const GizmoRect = types.GizmoRect;
pub const AnchorSide = types.AnchorSide;
pub const AnchorAlign = types.AnchorAlign;
pub const FontRenderMode = tailwind.FontRenderMode;
const events_mod = @import("events/mod.zig");
pub const events = events_mod;
pub const EventRing = events_mod.EventRing;
pub const EventKind = events_mod.EventKind;
pub const EventEntry = events_mod.EventEntry;
const layout = @import("layout/mod.zig");
const render_mod = @import("render/mod.zig");

pub fn init() void {
    tailwind.init();
    layout.init();
    render_mod.init();
}

pub fn deinit() void {
    render_mod.deinit();
    layout.deinit();
    tailwind.deinit();
}

pub const PickResult = struct {
    id: u32 = 0,
    z_index: i16 = std.math.minInt(i16),
    order: u32 = 0,
    rect: types.Rect = .{},
};

pub fn render(event_ring: ?*EventRing, store: *types.NodeStore, input_enabled: bool) bool {
    return render_mod.render(event_ring, store, input_enabled);
}

pub fn updateLayouts(store: *types.NodeStore) void {
    layout.updateLayouts(store);
}

pub fn setGizmoRectOverride(rect: ?types.GizmoRect) void {
    render_mod.setGizmoRectOverride(rect);
}

pub fn takeGizmoRectUpdate() ?types.GizmoRect {
    return render_mod.takeGizmoRectUpdate();
}

pub fn getNodeRect(store: *types.NodeStore, node_id: u32) ?types.Rect {
    if (dvui.current_window != null) {
        layout.updateLayouts(store);
    }
    const node = store.node(node_id) orelse return null;
    const spec = node.prepareClassSpec();
    if (spec.hidden) return null;
    const base_rect = node.layout.rect orelse return null;
    return direct.transformedRect(node, base_rect) orelse base_rect;
}

pub fn pickNodeAt(store: *types.NodeStore, x_pos: f32, y_pos: f32) ?PickResult {
    if (dvui.current_window != null) {
        layout.updateLayouts(store);
    }
    const root = store.node(0) orelse return null;
    var result = PickResult{};
    var order: u32 = 0;
    scanPickNode(store, root, x_pos, y_pos, null, &result, &order);
    if (result.id == 0) return null;
    return result;
}

pub fn pickNodeAtRange(store: *types.NodeStore, x_pos: f32, y_pos: f32, ignore_min: u32, ignore_max: u32) ?PickResult {
    if (dvui.current_window != null) {
        layout.updateLayouts(store);
    }
    const root = store.node(0) orelse return null;
    var result = PickResult{};
    var order: u32 = 0;
    scanPickNodeRange(store, root, x_pos, y_pos, null, &result, &order, ignore_min, ignore_max);
    if (result.id == 0) return null;
    return result;
}

fn scanPickNodeRange(
    store: *types.NodeStore,
    node: *types.SolidNode,
    x_pos: f32,
    y_pos: f32,
    clip_rect: ?types.Rect,
    result: *PickResult,
    order: *u32,
    ignore_min: u32,
    ignore_max: u32,
) void {
    if (clip_rect) |clip| {
        if (!rectContainsPoint(clip, x_pos, y_pos)) return;
    }

    var next_clip = clip_rect;
    var node_rect: ?types.Rect = null;
    if (node.kind == .element) {
        const spec = node.prepareClassSpec();
        if (spec.hidden) return;
        const opacity = spec.opacity orelse node.visual_props.opacity;
        if (opacity <= 0) return;
        if (node.layout.rect) |base_rect| {
            node_rect = direct.transformedRect(node, base_rect) orelse base_rect;
        }
        if (node_rect) |rect| {
            if (rectContainsPoint(rect, x_pos, y_pos)) {
                order.* += 1;
                const ignored = node.id >= ignore_min and node.id <= ignore_max;
                if (!ignored) {
                    const z_index = spec.z_index;
                    if (z_index > result.z_index or (z_index == result.z_index and order.* >= result.order)) {
                        result.* = .{
                            .id = node.id,
                            .z_index = z_index,
                            .order = order.*,
                            .rect = rect,
                        };
                    }
                }
            }
            const clip_children = spec.clip_children orelse node.visual_props.clip_children;
            const scroll_enabled = node.scroll.enabled or spec.scroll_x or spec.scroll_y;
            if (clip_children or scroll_enabled) {
                if (next_clip) |clip| {
                    next_clip = intersectRect(clip, rect);
                    if (next_clip == null) return;
                } else {
                    next_clip = rect;
                }
            }
        }
    }

    for (node.children.items) |child_id| {
        if (store.node(child_id)) |child| {
            scanPickNodeRange(store, child, x_pos, y_pos, next_clip, result, order, ignore_min, ignore_max);
        }
    }
}

fn scanPickFrameNodeRange(
    store: *types.NodeStore,
    node: *types.SolidNode,
    x_pos: f32,
    y_pos: f32,
    clip_rect: ?types.Rect,
    result: *PickResult,
    order: *u32,
    ignore_min: u32,
    ignore_max: u32,
) void {
    if (clip_rect) |clip| {
        if (!rectContainsPoint(clip, x_pos, y_pos)) return;
    }

    var next_clip = clip_rect;
    var node_rect: ?types.Rect = null;
    if (node.kind == .element) {
        const spec = node.prepareClassSpec();
        if (spec.hidden) return;
        const opacity = spec.opacity orelse node.visual_props.opacity;
        if (opacity <= 0) return;
        if (node.layout.rect) |base_rect| {
            node_rect = direct.transformedRect(node, base_rect) orelse base_rect;
        }
        if (node_rect) |rect| {
            if (rectContainsPoint(rect, x_pos, y_pos)) {
                order.* += 1;
                const ignored = node.id >= ignore_min and node.id <= ignore_max;
                if (!ignored and isFrameNode(node)) {
                    const z_index = spec.z_index;
                    if (z_index > result.z_index or (z_index == result.z_index and order.* >= result.order)) {
                        result.* = .{
                            .id = node.id,
                            .z_index = z_index,
                            .order = order.*,
                            .rect = rect,
                        };
                    }
                }
            }
            const clip_children = spec.clip_children orelse node.visual_props.clip_children;
            const scroll_enabled = node.scroll.enabled or spec.scroll_x or spec.scroll_y;
            if (clip_children or scroll_enabled) {
                if (next_clip) |clip| {
                    next_clip = intersectRect(clip, rect);
                    if (next_clip == null) return;
                } else {
                    next_clip = rect;
                }
            }
        }
    }

    for (node.children.items) |child_id| {
        if (store.node(child_id)) |child| {
            scanPickFrameNodeRange(store, child, x_pos, y_pos, next_clip, result, order, ignore_min, ignore_max);
        }
    }
}

pub fn pickFrameAtRange(store: *types.NodeStore, x_pos: f32, y_pos: f32, ignore_min: u32, ignore_max: u32) ?PickResult {
    if (dvui.current_window != null) {
        layout.updateLayouts(store);
    }
    const root = store.node(0) orelse return null;
    var result = PickResult{};
    var order: u32 = 0;
    scanPickFrameNodeRange(store, root, x_pos, y_pos, null, &result, &order, ignore_min, ignore_max);
    if (result.id == 0) return null;
    return result;
}

pub fn pickFrameAt(store: *types.NodeStore, x_pos: f32, y_pos: f32) ?PickResult {
    if (dvui.current_window != null) {
        layout.updateLayouts(store);
    }
    const root = store.node(0) orelse return null;
    var result = PickResult{};
    var order: u32 = 0;
    scanPickFrameNode(store, root, x_pos, y_pos, null, &result, &order);
    if (result.id == 0) return null;
    return result;
}

fn scanPickNode(
    store: *types.NodeStore,
    node: *types.SolidNode,
    x_pos: f32,
    y_pos: f32,
    clip_rect: ?types.Rect,
    result: *PickResult,
    order: *u32,
) void {
    if (clip_rect) |clip| {
        if (!rectContainsPoint(clip, x_pos, y_pos)) return;
    }

    var next_clip = clip_rect;
    var node_rect: ?types.Rect = null;
    if (node.kind == .element) {
        const spec = node.prepareClassSpec();
        if (spec.hidden) return;
        const opacity = spec.opacity orelse node.visual_props.opacity;
        if (opacity <= 0) return;
        if (node.layout.rect) |base_rect| {
            node_rect = direct.transformedRect(node, base_rect) orelse base_rect;
        }
        if (node_rect) |rect| {
            if (rectContainsPoint(rect, x_pos, y_pos)) {
                order.* += 1;
                const z_index = spec.z_index;
                if (z_index > result.z_index or (z_index == result.z_index and order.* >= result.order)) {
                    result.* = .{
                        .id = node.id,
                        .z_index = z_index,
                        .order = order.*,
                        .rect = rect,
                    };
                }
            }
            const clip_children = spec.clip_children orelse node.visual_props.clip_children;
            const scroll_enabled = node.scroll.enabled or spec.scroll_x or spec.scroll_y;
            if (clip_children or scroll_enabled) {
                if (next_clip) |clip| {
                    next_clip = intersectRect(clip, rect);
                    if (next_clip == null) return;
                } else {
                    next_clip = rect;
                }
            }
        }
    }

    for (node.children.items) |child_id| {
        if (store.node(child_id)) |child| {
            scanPickNode(store, child, x_pos, y_pos, next_clip, result, order);
        }
    }
}

fn scanPickFrameNode(
    store: *types.NodeStore,
    node: *types.SolidNode,
    x_pos: f32,
    y_pos: f32,
    clip_rect: ?types.Rect,
    result: *PickResult,
    order: *u32,
) void {
    if (clip_rect) |clip| {
        if (!rectContainsPoint(clip, x_pos, y_pos)) return;
    }

    var next_clip = clip_rect;
    var node_rect: ?types.Rect = null;
    if (node.kind == .element) {
        const spec = node.prepareClassSpec();
        if (spec.hidden) return;
        const opacity = spec.opacity orelse node.visual_props.opacity;
        if (opacity <= 0) return;
        if (node.layout.rect) |base_rect| {
            node_rect = direct.transformedRect(node, base_rect) orelse base_rect;
        }
        if (node_rect) |rect| {
            if (rectContainsPoint(rect, x_pos, y_pos)) {
                order.* += 1;
                if (isFrameNode(node)) {
                    const z_index = spec.z_index;
                    if (z_index > result.z_index or (z_index == result.z_index and order.* >= result.order)) {
                        result.* = .{
                            .id = node.id,
                            .z_index = z_index,
                            .order = order.*,
                            .rect = rect,
                        };
                    }
                }
            }
            const clip_children = spec.clip_children orelse node.visual_props.clip_children;
            const scroll_enabled = node.scroll.enabled or spec.scroll_x or spec.scroll_y;
            if (clip_children or scroll_enabled) {
                if (next_clip) |clip| {
                    next_clip = intersectRect(clip, rect);
                    if (next_clip == null) return;
                } else {
                    next_clip = rect;
                }
            }
        }
    }

    for (node.children.items) |child_id| {
        if (store.node(child_id)) |child| {
            scanPickFrameNode(store, child, x_pos, y_pos, next_clip, result, order);
        }
    }
}

fn isFrameNode(node: *types.SolidNode) bool {
    if (node.kind != .element) return false;
    const tag = node.tag;
    return std.mem.eql(u8, tag, "div") or std.mem.eql(u8, tag, "frame");
}

fn rectContainsPoint(rect: types.Rect, x_pos: f32, y_pos: f32) bool {
    return x_pos >= rect.x and x_pos <= (rect.x + rect.w) and y_pos >= rect.y and y_pos <= (rect.y + rect.h);
}

fn intersectRect(rect_a: types.Rect, rect_b: types.Rect) ?types.Rect {
    const min_x = @max(rect_a.x, rect_b.x);
    const min_y = @max(rect_a.y, rect_b.y);
    const max_x = @min(rect_a.x + rect_a.w, rect_b.x + rect_b.w);
    const max_y = @min(rect_a.y + rect_a.h, rect_b.y + rect_b.h);
    if (max_x <= min_x or max_y <= min_y) return null;
    return types.Rect{
        .x = min_x,
        .y = min_y,
        .w = max_x - min_x,
        .h = max_y - min_y,
    };
}
