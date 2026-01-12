const std = @import("std");
const dvui = @import("dvui");
const types = @import("core/types.zig");
const direct = @import("render/direct.zig");
pub const NodeStore = types.NodeStore;
pub const SolidNode = types.SolidNode;
pub const Rect = types.Rect;
pub const GizmoRect = types.GizmoRect;
const events_mod = @import("events/mod.zig");
pub const events = events_mod;
pub const EventRing = events_mod.EventRing;
pub const EventKind = events_mod.EventKind;
pub const EventEntry = events_mod.EventEntry;
const layout = @import("layout/mod.zig");
const render_mod = @import("render/mod.zig");

const SolidSnapshotNode = struct {
    id: u32,
    tag: []const u8,
    parent: ?u32 = null,
    text: ?[]const u8 = null,
    src: ?[]const u8 = null,
    className: ?[]const u8 = null,
    rotation: ?f32 = null,
    scaleX: ?f32 = null,
    scaleY: ?f32 = null,
    anchorX: ?f32 = null,
    anchorY: ?f32 = null,
    translateX: ?f32 = null,
    translateY: ?f32 = null,
    opacity: ?f32 = null,
    cornerRadius: ?f32 = null,
    background: ?u32 = null,
    textColor: ?u32 = null,
    clipChildren: ?bool = null,
    scroll: ?bool = null,
    scrollX: ?f32 = null,
    scrollY: ?f32 = null,
    canvasWidth: ?f32 = null,
    canvasHeight: ?f32 = null,
    autoCanvas: ?bool = null,
};

const SolidSnapshot = struct {
    nodes: []const SolidSnapshotNode = &.{},
};

pub fn init() void {
    layout.init();
    render_mod.init();
}

pub fn deinit() void {
    render_mod.deinit();
    layout.deinit();
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

pub fn setSnapshot(store: *types.NodeStore, event_ring: ?*EventRing, json_bytes: []const u8) bool {
    const store_allocator = store.allocator;
    store.deinit();
    if (event_ring) |ring| {
        ring.reset();
    }
    store.init(store_allocator) catch return false;

    var parsed = std.json.parseFromSlice(SolidSnapshot, store_allocator, json_bytes, .{
        .ignore_unknown_fields = true,
    }) catch return false;
    defer parsed.deinit();

    const snapshot = parsed.value;

    for (snapshot.nodes) |node| {
        if (node.id == 0) continue;
        const is_text = std.mem.eql(u8, node.tag, "text");
        if (is_text) {
            store.setTextNode(node.id, node.text orelse "") catch {};
        } else if (std.mem.eql(u8, node.tag, "slot")) {
            store.upsertSlot(node.id) catch {};
        } else {
            store.upsertElement(node.id, node.tag) catch return false;
        }
        if (node.className) |cls| {
            store.setClassName(node.id, cls) catch {};
        }
        if (node.src) |src| {
            store.setImageSource(node.id, src) catch {};
        }
        if (store.node(node.id)) |target| {
            var touched = false;
            if (node.rotation) |value| {
                target.transform.rotation = value;
                touched = true;
            }
            if (node.scaleX) |value| {
                target.transform.scale[0] = value;
                touched = true;
            }
            if (node.scaleY) |value| {
                target.transform.scale[1] = value;
                touched = true;
            }
            if (node.anchorX) |value| {
                target.transform.anchor[0] = value;
                touched = true;
            }
            if (node.anchorY) |value| {
                target.transform.anchor[1] = value;
                touched = true;
            }
            if (node.translateX) |value| {
                target.transform.translation[0] = value;
                touched = true;
            }
            if (node.translateY) |value| {
                target.transform.translation[1] = value;
                touched = true;
            }
            if (node.opacity) |value| {
                target.visual_props.opacity = value;
                touched = true;
            }
            if (node.cornerRadius) |value| {
                target.visual_props.corner_radius = value;
                touched = true;
            }
            if (node.background) |value| {
                target.visual_props.background = .{ .value = value };
                touched = true;
            }
            if (node.textColor) |value| {
                target.visual_props.text_color = .{ .value = value };
                touched = true;
            }
            if (node.clipChildren) |flag| {
                target.visual_props.clip_children = flag;
                touched = true;
            }
            if (node.scroll) |flag| {
                target.scroll.enabled = flag;
                touched = true;
            }
            if (node.scrollX) |value| {
                target.scroll.offset_x = value;
                touched = true;
            }
            if (node.scrollY) |value| {
                target.scroll.offset_y = value;
                touched = true;
            }
            if (node.canvasWidth) |value| {
                target.scroll.canvas_width = value;
                touched = true;
            }
            if (node.canvasHeight) |value| {
                target.scroll.canvas_height = value;
                touched = true;
            }
            if (node.autoCanvas) |flag| {
                target.scroll.auto_canvas = flag;
                touched = true;
            }
            if (touched) {
                store.markNodeChanged(node.id);
            }
        }
    }

    for (snapshot.nodes) |node| {
        if (node.id == 0) continue;
        const parent_id: u32 = node.parent orelse 0;
        store.insert(parent_id, node.id, null) catch {};
    }

    if (store.node(0)) |root_node| {
        return root_node.children.items.len > 0;
    }
    return false;
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
        if (node.layout.rect) |base_rect| {
            node_rect = direct.transformedRect(node, base_rect) orelse base_rect;
        }
        if (node_rect) |rect| {
            if (rectContainsPoint(rect, x_pos, y_pos)) {
                order.* += 1;
                const z_index = node.visual.z_index;
                if (z_index > result.z_index or (z_index == result.z_index and order.* >= result.order)) {
                    result.* = .{
                        .id = node.id,
                        .z_index = z_index,
                        .order = order.*,
                        .rect = rect,
                    };
                }
            }
            if (spec.clip_children orelse false) {
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
