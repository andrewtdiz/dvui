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

const SolidOp = struct {
    op: []const u8,
    id: u32 = 0,
    parent: ?u32 = null,
    before: ?u32 = null,
    tag: ?[]const u8 = null,
    text: ?[]const u8 = null,
    className: ?[]const u8 = null,
    eventType: ?[]const u8 = null,
    name: ?[]const u8 = null,
    value: ?[]const u8 = null,
    src: ?[]const u8 = null,
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

const SolidOpBatch = struct {
    ops: []const SolidOp = &.{},
    seq: ?u64 = null,
};

const OpError = error{
    OutOfMemory,
    UnknownOp,
    MissingId,
    MissingParent,
    MissingChild,
    MissingTag,
};

pub fn init() void {
    layout.init();
    render_mod.init();
}

pub fn deinit() void {
    render_mod.deinit();
    layout.deinit();
    deinitRetainedState();
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

pub fn applyOps(store: *types.NodeStore, seq_last: *u64, json_bytes: []const u8) bool {
    const store_allocator = store.allocator;
    var parsed = std.json.parseFromSlice(SolidOpBatch, store_allocator, json_bytes, .{
        .ignore_unknown_fields = true,
    }) catch return false;
    defer parsed.deinit();

    const batch = parsed.value;
    const seq = batch.seq orelse seq_last.* + 1;
    if (seq <= seq_last.*) {
        return false;
    }

    for (batch.ops) |op| {
        applySolidOp(store, op) catch return false;
    }
    seq_last.* = seq;

    const root_node = store.node(0) orelse return false;
    return root_node.children.items.len > 0;
}

fn applyTransformFields(store: *types.NodeStore, id: u32, op: SolidOp) OpError!void {
    const target = store.node(id) orelse return error.MissingId;
    var changed = false;
    if (op.rotation) |value| {
        target.transform.rotation = value;
        changed = true;
    }
    if (op.scaleX) |value| {
        target.transform.scale[0] = value;
        changed = true;
    }
    if (op.scaleY) |value| {
        target.transform.scale[1] = value;
        changed = true;
    }
    if (op.anchorX) |value| {
        target.transform.anchor[0] = value;
        changed = true;
    }
    if (op.anchorY) |value| {
        target.transform.anchor[1] = value;
        changed = true;
    }
    if (op.translateX) |value| {
        target.transform.translation[0] = value;
        changed = true;
    }
    if (op.translateY) |value| {
        target.transform.translation[1] = value;
        changed = true;
    }
    if (changed) {
        store.markNodeChanged(id);
    }
}

fn applyVisualFields(store: *types.NodeStore, id: u32, op: SolidOp) OpError!void {
    const target = store.node(id) orelse return error.MissingId;
    var changed = false;
    if (op.opacity) |value| {
        target.visual_props.opacity = value;
        changed = true;
    }
    if (op.cornerRadius) |value| {
        target.visual_props.corner_radius = value;
        changed = true;
    }
    if (op.background) |color| {
        target.visual_props.background = .{ .value = color };
        changed = true;
    }
    if (op.textColor) |color| {
        target.visual_props.text_color = .{ .value = color };
        changed = true;
    }
    if (op.clipChildren) |flag| {
        target.visual_props.clip_children = flag;
        changed = true;
    }
    if (changed) {
        store.markNodeChanged(id);
    }
}

fn applyScrollFields(store: *types.NodeStore, id: u32, op: SolidOp) OpError!void {
    const target = store.node(id) orelse return error.MissingId;
    var changed = false;
    if (op.scroll) |flag| {
        target.scroll.enabled = flag;
        changed = true;
    }
    if (op.scrollX) |value| {
        target.scroll.offset_x = value;
        changed = true;
    }
    if (op.scrollY) |value| {
        target.scroll.offset_y = value;
        changed = true;
    }
    if (op.canvasWidth) |value| {
        target.scroll.canvas_width = value;
        changed = true;
    }
    if (op.canvasHeight) |value| {
        target.scroll.canvas_height = value;
        changed = true;
    }
    if (op.autoCanvas) |flag| {
        target.scroll.auto_canvas = flag;
        changed = true;
    }
    if (changed) {
        store.markNodeChanged(id);
    }
}

fn applySolidOp(store: *types.NodeStore, op: SolidOp) OpError!void {
    if (op.op.len == 0) return error.UnknownOp;

    if (std.mem.eql(u8, op.op, "create")) {
        const tag = op.tag orelse return error.MissingTag;
        if (std.mem.eql(u8, tag, "text")) {
            try store.setTextNode(op.id, op.text orelse "");
        } else if (std.mem.eql(u8, tag, "slot")) {
            try store.upsertSlot(op.id);
        } else {
            try store.upsertElement(op.id, tag);
        }
        if (op.className) |cls| {
            try store.setClassName(op.id, cls);
        }
        try applyTransformFields(store, op.id, op);
        try applyVisualFields(store, op.id, op);
        try applyScrollFields(store, op.id, op);
        const parent_id: u32 = op.parent orelse 0;
        try store.insert(parent_id, op.id, op.before);
        return;
    }

    if (std.mem.eql(u8, op.op, "remove")) {
        if (op.id == 0) return error.MissingId;
        store.remove(op.id);
        return;
    }

    if (std.mem.eql(u8, op.op, "move") or std.mem.eql(u8, op.op, "insert")) {
        if (op.id == 0) return error.MissingId;
        const parent_id = op.parent orelse return error.MissingParent;
        if (store.node(op.id) == null) return error.MissingChild;
        if (store.node(parent_id) == null) return error.MissingParent;
        try store.insert(parent_id, op.id, op.before);
        return;
    }

    if (std.mem.eql(u8, op.op, "set_text")) {
        if (op.id == 0) return error.MissingId;
        try store.setTextNode(op.id, op.text orelse "");
        return;
    }

    if (std.mem.eql(u8, op.op, "set_class")) {
        if (op.id == 0) return error.MissingId;
        const cls = op.className orelse return error.MissingTag;
        try store.setClassName(op.id, cls);
        return;
    }

    if (std.mem.eql(u8, op.op, "set_transform")) {
        if (op.id == 0) return error.MissingId;
        try applyTransformFields(store, op.id, op);
        return;
    }

    if (std.mem.eql(u8, op.op, "set_visual")) {
        if (op.id == 0) return error.MissingId;
        try applyVisualFields(store, op.id, op);
        return;
    }

    if (std.mem.eql(u8, op.op, "set_scroll")) {
        if (op.id == 0) return error.MissingId;
        try applyScrollFields(store, op.id, op);
        return;
    }

    if (std.mem.eql(u8, op.op, "listen")) {
        if (op.id == 0) return error.MissingId;
        const event_type = op.eventType orelse return error.MissingTag;
        try store.addListener(op.id, event_type);
        return;
    }

    if (std.mem.eql(u8, op.op, "set")) {
        if (op.id == 0) return error.MissingId;
        const prop_name = op.name orelse return error.MissingTag;

        if (std.mem.eql(u8, prop_name, "class") or std.mem.eql(u8, prop_name, "className")) {
            const val = op.value orelse op.className orelse return error.MissingTag;
            try store.setClassName(op.id, val);
            return;
        }
        if (std.mem.eql(u8, prop_name, "src")) {
            const val = op.value orelse op.src orelse return error.MissingTag;
            try store.setImageSource(op.id, val);
            return;
        }
        if (std.mem.eql(u8, prop_name, "value")) {
            const val = op.value orelse return error.MissingTag;
            try store.setInputValue(op.id, val);
            return;
        }
        return;
    }

    return error.UnknownOp;
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

const RectOut = extern struct {
    x: f32,
    y: f32,
    w: f32,
    h: f32,
};

var retained_gpa = std.heap.GeneralPurposeAllocator(.{}){};
var retained_allocator: std.mem.Allocator = undefined;
var retained_allocator_ready: bool = false;
var retained_store: types.NodeStore = undefined;
var retained_store_initialized: bool = false;
var retained_event_ring: EventRing = undefined;
var retained_event_ring_initialized: bool = false;
var retained_seq_last: u64 = 0;

fn retainedAllocator() std.mem.Allocator {
    if (!retained_allocator_ready) {
        retained_allocator = retained_gpa.allocator();
        retained_allocator_ready = true;
    }
    return retained_allocator;
}

fn ensureRetainedStore() ?*types.NodeStore {
    if (retained_store_initialized) return &retained_store;
    const allocator = retainedAllocator();
    retained_store.init(allocator) catch return null;
    retained_store_initialized = true;
    retained_seq_last = 0;
    return &retained_store;
}

fn ensureRetainedEventRing() ?*EventRing {
    if (retained_event_ring_initialized) return &retained_event_ring;
    const allocator = retainedAllocator();
    retained_event_ring = EventRing.init(allocator) catch return null;
    retained_event_ring_initialized = true;
    return &retained_event_ring;
}

fn retainedEventRing() ?*EventRing {
    if (retained_event_ring_initialized) return &retained_event_ring;
    return null;
}

pub fn sharedStore() ?*types.NodeStore {
    return ensureRetainedStore();
}

pub fn sharedEventRing() ?*EventRing {
    return ensureRetainedEventRing();
}

fn writeRectOut(rect: types.Rect, out_ptr: [*]u8, out_len: usize) bool {
    if (out_len < @sizeOf(RectOut)) return false;
    const out = RectOut{
        .x = rect.x,
        .y = rect.y,
        .w = rect.w,
        .h = rect.h,
    };
    const bytes = std.mem.asBytes(&out);
    const dest = out_ptr[0..@sizeOf(RectOut)];
    @memcpy(dest, bytes);
    return true;
}

pub export fn dvui_retained_set_snapshot(json_ptr: [*]const u8, json_len: usize) callconv(.c) void {
    const store = ensureRetainedStore() orelse return;
    const ring = ensureRetainedEventRing();
    retained_seq_last = 0;
    const json_bytes = json_ptr[0..json_len];
    _ = setSnapshot(store, ring, json_bytes);
}

pub export fn dvui_retained_apply_ops(json_ptr: [*]const u8, json_len: usize) callconv(.c) bool {
    const store = ensureRetainedStore() orelse return false;
    const json_bytes = json_ptr[0..json_len];
    return applyOps(store, &retained_seq_last, json_bytes);
}

pub export fn dvui_retained_get_event_ring_header(out_ptr: [*]u8, out_len: usize) callconv(.c) usize {
    const ring = ensureRetainedEventRing() orelse return 0;
    if (out_len < @sizeOf(EventRing.Header)) return 0;
    const header = ring.snapshotHeader();
    const bytes = std.mem.asBytes(&header);
    const dest = out_ptr[0..@sizeOf(EventRing.Header)];
    @memcpy(dest, bytes);
    return @sizeOf(EventRing.Header);
}

pub export fn dvui_retained_get_event_ring_buffer() callconv(.c) ?[*]EventEntry {
    const ring = ensureRetainedEventRing() orelse return null;
    return ring.getBufferPtr();
}

pub export fn dvui_retained_get_event_ring_detail() callconv(.c) ?[*]u8 {
    const ring = ensureRetainedEventRing() orelse return null;
    return ring.getDetailPtr();
}

pub export fn dvui_retained_ack_events(new_read_head: u32) callconv(.c) void {
    const ring = retainedEventRing() orelse return;
    ring.setReadHead(new_read_head);
}

pub export fn dvui_retained_pick_node_at(
    x_pos: f32,
    y_pos: f32,
    out_ptr: [*]u8,
    out_len: usize,
) callconv(.c) u32 {
    const store = ensureRetainedStore() orelse return 0;
    const result = pickNodeAt(store, x_pos, y_pos) orelse return 0;
    _ = writeRectOut(result.rect, out_ptr, out_len);
    return result.id;
}

pub export fn dvui_retained_get_node_rect(node_id: u32, out_ptr: [*]u8, out_len: usize) callconv(.c) bool {
    const store = ensureRetainedStore() orelse return false;
    const rect = getNodeRect(store, node_id) orelse return false;
    return writeRectOut(rect, out_ptr, out_len);
}

fn deinitRetainedState() void {
    if (retained_store_initialized) {
        retained_store.deinit();
        retained_store_initialized = false;
    }
    if (retained_event_ring_initialized) {
        retained_event_ring.deinit();
        retained_event_ring_initialized = false;
    }
    retained_seq_last = 0;
}
