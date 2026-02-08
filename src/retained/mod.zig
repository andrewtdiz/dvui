const std = @import("std");
const dvui = @import("dvui");
const types = @import("core/types.zig");
const direct = @import("render/direct.zig");
const hit_test = @import("hit_test.zig");
const tailwind = @import("style/tailwind.zig");
pub const NodeStore = types.NodeStore;
pub const SolidNode = types.SolidNode;
pub const Rect = types.Rect;
pub const AnchorSide = types.AnchorSide;
pub const AnchorAlign = types.AnchorAlign;
pub const FontRenderMode = tailwind.FontRenderMode;
const events_mod = @import("events/mod.zig");
pub const events = events_mod;
pub const EventRing = events_mod.EventRing;
pub const EventKind = events_mod.EventKind;
pub const EventEntry = events_mod.EventEntry;
pub const FrameTimings = render_mod.FrameTimings;
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

pub const PickStackEntry = struct {
    id: u32,
    z_index: i16,
    order: u32,
    rect: types.Rect,
};

pub const PickStackOptions = struct {
    ignore_min: ?u32 = null,
    ignore_max: ?u32 = null,
    frames_only: bool = false,
    max_results: usize = 0,
};

fn pickStackEntryLessThan(_: void, lhs: PickStackEntry, rhs: PickStackEntry) bool {
    if (lhs.z_index == rhs.z_index) {
        return lhs.order > rhs.order;
    }
    return lhs.z_index > rhs.z_index;
}

pub fn render(event_ring: ?*EventRing, store: *types.NodeStore, input_enabled: bool, timings: ?*FrameTimings) bool {
    return render_mod.render(event_ring, store, input_enabled, timings);
}

pub fn updateLayouts(store: *types.NodeStore) void {
    layout.updateLayouts(store);
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
    const ctx = hit_test.RenderContext{ .origin = .{ .x = 0, .y = 0 }, .clip = null, .scale = .{ 1, 1 }, .offset = .{ 0, 0 } };
    var result = PickResult{};
    var order: u32 = 0;
    const point = dvui.Point.Physical{ .x = x_pos, .y = y_pos };
    var visitor = struct {
        result: *PickResult,

        pub fn count(self: *@This(), node: *types.SolidNode, spec: tailwind.Spec) bool {
            _ = self;
            _ = node;
            _ = spec;
            return true;
        }

        pub fn hit(self: *@This(), node: *types.SolidNode, spec: tailwind.Spec, rect: types.Rect, ord: u32) void {
            const z_index = spec.z_index;
            if (z_index > self.result.z_index or (z_index == self.result.z_index and ord >= self.result.order)) {
                self.result.* = .{ .id = node.id, .z_index = z_index, .order = ord, .rect = rect };
            }
        }
    }{ .result = &result };

    hit_test.scan(store, root, point, ctx, &visitor, &order, .{ .skip_portals = false });
    if (result.id == 0) return null;
    return result;
}

pub fn pickNodeAtRange(store: *types.NodeStore, x_pos: f32, y_pos: f32, ignore_min: u32, ignore_max: u32) ?PickResult {
    if (dvui.current_window != null) {
        layout.updateLayouts(store);
    }
    const root = store.node(0) orelse return null;
    const ctx = hit_test.RenderContext{ .origin = .{ .x = 0, .y = 0 }, .clip = null, .scale = .{ 1, 1 }, .offset = .{ 0, 0 } };
    var result = PickResult{};
    var order: u32 = 0;
    const point = dvui.Point.Physical{ .x = x_pos, .y = y_pos };
    var visitor = struct {
        result: *PickResult,
        ignore_min: u32,
        ignore_max: u32,

        pub fn count(self: *@This(), node: *types.SolidNode, spec: tailwind.Spec) bool {
            _ = self;
            _ = node;
            _ = spec;
            return true;
        }

        pub fn hit(self: *@This(), node: *types.SolidNode, spec: tailwind.Spec, rect: types.Rect, ord: u32) void {
            if (node.id >= self.ignore_min and node.id <= self.ignore_max) return;
            const z_index = spec.z_index;
            if (z_index > self.result.z_index or (z_index == self.result.z_index and ord >= self.result.order)) {
                self.result.* = .{ .id = node.id, .z_index = z_index, .order = ord, .rect = rect };
            }
        }
    }{ .result = &result, .ignore_min = ignore_min, .ignore_max = ignore_max };

    hit_test.scan(store, root, point, ctx, &visitor, &order, .{ .skip_portals = false });
    if (result.id == 0) return null;
    return result;
}

pub fn pickFrameAtRange(store: *types.NodeStore, x_pos: f32, y_pos: f32, ignore_min: u32, ignore_max: u32) ?PickResult {
    if (dvui.current_window != null) {
        layout.updateLayouts(store);
    }
    const root = store.node(0) orelse return null;
    const ctx = hit_test.RenderContext{ .origin = .{ .x = 0, .y = 0 }, .clip = null, .scale = .{ 1, 1 }, .offset = .{ 0, 0 } };
    var result = PickResult{};
    var order: u32 = 0;
    const point = dvui.Point.Physical{ .x = x_pos, .y = y_pos };
    var visitor = struct {
        result: *PickResult,
        ignore_min: u32,
        ignore_max: u32,

        pub fn count(self: *@This(), node: *types.SolidNode, spec: tailwind.Spec) bool {
            _ = self;
            _ = node;
            _ = spec;
            return true;
        }

        pub fn hit(self: *@This(), node: *types.SolidNode, spec: tailwind.Spec, rect: types.Rect, ord: u32) void {
            if (node.id >= self.ignore_min and node.id <= self.ignore_max) return;
            if (!isFrameNode(node)) return;
            const z_index = spec.z_index;
            if (z_index > self.result.z_index or (z_index == self.result.z_index and ord >= self.result.order)) {
                self.result.* = .{ .id = node.id, .z_index = z_index, .order = ord, .rect = rect };
            }
        }
    }{ .result = &result, .ignore_min = ignore_min, .ignore_max = ignore_max };

    hit_test.scan(store, root, point, ctx, &visitor, &order, .{ .skip_portals = false });
    if (result.id == 0) return null;
    return result;
}

pub fn pickFrameAt(store: *types.NodeStore, x_pos: f32, y_pos: f32) ?PickResult {
    if (dvui.current_window != null) {
        layout.updateLayouts(store);
    }
    const root = store.node(0) orelse return null;
    const ctx = hit_test.RenderContext{ .origin = .{ .x = 0, .y = 0 }, .clip = null, .scale = .{ 1, 1 }, .offset = .{ 0, 0 } };
    var result = PickResult{};
    var order: u32 = 0;
    const point = dvui.Point.Physical{ .x = x_pos, .y = y_pos };
    var visitor = struct {
        result: *PickResult,

        pub fn count(self: *@This(), node: *types.SolidNode, spec: tailwind.Spec) bool {
            _ = self;
            _ = node;
            _ = spec;
            return true;
        }

        pub fn hit(self: *@This(), node: *types.SolidNode, spec: tailwind.Spec, rect: types.Rect, ord: u32) void {
            if (!isFrameNode(node)) return;
            const z_index = spec.z_index;
            if (z_index > self.result.z_index or (z_index == self.result.z_index and ord >= self.result.order)) {
                self.result.* = .{ .id = node.id, .z_index = z_index, .order = ord, .rect = rect };
            }
        }
    }{ .result = &result };

    hit_test.scan(store, root, point, ctx, &visitor, &order, .{ .skip_portals = false });
    if (result.id == 0) return null;
    return result;
}

pub fn pickNodeStackAtInto(
    store: *types.NodeStore,
    x_pos: f32,
    y_pos: f32,
    out: *std.ArrayListUnmanaged(PickStackEntry),
    allocator: std.mem.Allocator,
    opts: PickStackOptions,
) void {
    if (dvui.current_window != null) {
        layout.updateLayouts(store);
    }

    out.clearRetainingCapacity();

    const root = store.node(0) orelse return;
    const ctx = hit_test.RenderContext{ .origin = .{ .x = 0, .y = 0 }, .clip = null, .scale = .{ 1, 1 }, .offset = .{ 0, 0 } };
    var order: u32 = 0;
    const point = dvui.Point.Physical{ .x = x_pos, .y = y_pos };

    var visitor = struct {
        out: *std.ArrayListUnmanaged(PickStackEntry),
        allocator: std.mem.Allocator,
        opts: PickStackOptions,

        pub fn count(self: *@This(), node: *types.SolidNode, spec: tailwind.Spec) bool {
            _ = self;
            _ = node;
            _ = spec;
            return true;
        }

        pub fn hit(self: *@This(), node: *types.SolidNode, spec: tailwind.Spec, rect: types.Rect, ord: u32) void {
            if (self.opts.ignore_min) |min_id| {
                if (self.opts.ignore_max) |max_id| {
                    if (node.id >= min_id and node.id <= max_id) return;
                }
            }
            if (self.opts.frames_only and !isFrameNode(node)) return;
            self.out.append(self.allocator, .{ .id = node.id, .z_index = spec.z_index, .order = ord, .rect = rect }) catch {};
        }
    }{ .out = out, .allocator = allocator, .opts = opts };

    hit_test.scan(store, root, point, ctx, &visitor, &order, .{ .skip_portals = false });

    if (out.items.len > 1) {
        std.sort.pdq(PickStackEntry, out.items, {}, pickStackEntryLessThan);
    }

    if (opts.max_results > 0 and out.items.len > opts.max_results) {
        out.items.len = opts.max_results;
    }
}

pub fn pickNodePathAtInto(
    store: *types.NodeStore,
    x_pos: f32,
    y_pos: f32,
    out_ids: *std.ArrayListUnmanaged(u32),
    allocator: std.mem.Allocator,
    opts: PickStackOptions,
) bool {
    out_ids.clearRetainingCapacity();

    const leaf = if (opts.frames_only) blk: {
        if (opts.ignore_min) |min_id| {
            if (opts.ignore_max) |max_id| {
                break :blk pickFrameAtRange(store, x_pos, y_pos, min_id, max_id);
            }
        }
        break :blk pickFrameAt(store, x_pos, y_pos);
    } else blk: {
        if (opts.ignore_min) |min_id| {
            if (opts.ignore_max) |max_id| {
                break :blk pickNodeAtRange(store, x_pos, y_pos, min_id, max_id);
            }
        }
        break :blk pickNodeAt(store, x_pos, y_pos);
    };

    const leaf_id = (leaf orelse return false).id;

    var current_id: u32 = leaf_id;
    while (current_id != 0) {
        out_ids.append(allocator, current_id) catch break;
        const node = store.node(current_id) orelse break;
        current_id = node.parent orelse 0;
    }

    var i: usize = 0;
    var j: usize = out_ids.items.len;
    while (i < j) : (i += 1) {
        j -= 1;
        const tmp = out_ids.items[i];
        out_ids.items[i] = out_ids.items[j];
        out_ids.items[j] = tmp;
    }

    return out_ids.items.len != 0;
}

fn isFrameNode(node: *types.SolidNode) bool {
    if (node.kind != .element) return false;
    const tag = node.tag;
    return std.mem.eql(u8, tag, "div") or std.mem.eql(u8, tag, "frame");
}
