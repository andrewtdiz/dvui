const std = @import("std");
const dvui = @import("dvui");

const draw = @import("direct.zig");
const types = @import("../core/types.zig");

pub const DirtyRegionTracker = struct {
    regions: std.ArrayList(types.Rect) = .empty,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) DirtyRegionTracker {
        return .{ .allocator = allocator };
    }

    pub fn deinit(self: *DirtyRegionTracker) void {
        self.regions.deinit(self.allocator);
    }

    pub fn clear(self: *DirtyRegionTracker) void {
        self.regions.clearRetainingCapacity();
    }

    pub fn add(self: *DirtyRegionTracker, rect: types.Rect) void {
        if (rect.w <= 0 or rect.h <= 0) return;
        for (self.regions.items) |*existing| {
            if (rectsIntersect(existing.*, rect)) {
                existing.* = rectUnion(existing.*, rect);
                return;
            }
        }
        _ = self.regions.append(self.allocator, rect) catch {};
    }

    pub fn intersectsAny(self: *const DirtyRegionTracker, rect: types.Rect) bool {
        for (self.regions.items) |dirty| {
            if (rectsIntersect(dirty, rect)) return true;
        }
        return false;
    }
};

fn rectsIntersect(a: types.Rect, b: types.Rect) bool {
    return !(a.x + a.w < b.x or b.x + b.w < a.x or a.y + a.h < b.y or b.y + b.h < a.y);
}

fn rectUnion(a: types.Rect, b: types.Rect) types.Rect {
    const x1 = @min(a.x, b.x);
    const y1 = @min(a.y, b.y);
    const x2 = @max(a.x + a.w, b.x + b.w);
    const y2 = @max(a.y + a.h, b.y + b.h);
    return .{ .x = x1, .y = y1, .w = x2 - x1, .h = y2 - y1 };
}

pub fn renderPaintCache(node: *types.SolidNode) bool {
    if (node.paint.vertices.items.len == 0 or node.paint.indices.items.len == 0) return false;
    const rect = node.paint.painted_rect orelse return false;
    const tris = dvui.Triangles{
        .vertexes = node.paint.vertices.items,
        .indices = node.paint.indices.items,
        .bounds = draw.rectToPhysical(rect),
    };
    dvui.renderTriangles(tris, null) catch {};
    return true;
}

pub fn renderCachedOrDirectBackground(
    node: *types.SolidNode,
    rect: types.Rect,
    allocator: std.mem.Allocator,
    fallback_bg: ?dvui.Color,
) void {
    if (renderPaintCache(node)) return;
    draw.drawRectDirect(rect, node.visual, node.transform, allocator, fallback_bg);
}

pub fn updatePaintCache(store: *types.NodeStore, tracker: *DirtyRegionTracker) void {
    const root = store.node(0) orelse return;
    updatePaintCacheRecursive(store, root, tracker);
}

fn updatePaintCacheRecursive(store: *types.NodeStore, node: *types.SolidNode, tracker: *DirtyRegionTracker) void {
    if (!node.needsPaintUpdate()) {
        for (node.children.items) |child_id| {
            if (store.node(child_id)) |child| {
                updatePaintCacheRecursive(store, child, tracker);
            }
        }
        return;
    }

    regeneratePaintCache(store, node, tracker);

    for (node.children.items) |child_id| {
        if (store.node(child_id)) |child| {
            updatePaintCacheRecursive(store, child, tracker);
        }
    }
}

fn regeneratePaintCache(store: *types.NodeStore, node: *types.SolidNode, tracker: *DirtyRegionTracker) void {
    const allocator = store.allocator;

    const old_rect = node.paint.painted_rect;

    node.paint.vertices.deinit(allocator);
    node.paint.indices.deinit(allocator);
    node.paint.vertices = .empty;
    node.paint.indices = .empty;

    const rect = node.layout.rect;

    if (!shouldCachePaint(node) or rect == null) {
        const bounds = if (rect) |r| draw.transformedRect(node, r) orelse r else null;
        node.paint.painted_rect = bounds;
        if (bounds) |r| tracker.add(r);
        if (old_rect) |r| tracker.add(r);
        node.paint.version = node.subtree_version;
        node.paint.paint_dirty = false;
        return;
    }

    const geom = buildRectGeometry(rect.?, node.visual, node.transform, allocator) catch {
        const bounds = draw.transformedRect(node, rect.?) orelse rect.?;
        node.paint.painted_rect = bounds;
        tracker.add(bounds);
        if (old_rect) |r| tracker.add(r);
        node.paint.version = node.subtree_version;
        node.paint.paint_dirty = false;
        return;
    };

    node.paint.vertices = std.ArrayList(dvui.Vertex).fromOwnedSlice(geom.vertices);
    node.paint.indices = std.ArrayList(u16).fromOwnedSlice(geom.indices);
    node.paint.painted_rect = .{ .x = geom.bounds.x, .y = geom.bounds.y, .w = geom.bounds.w, .h = geom.bounds.h };
    node.paint.version = node.subtree_version;
    node.paint.paint_dirty = false;
    tracker.add(node.paint.painted_rect.?);
    if (old_rect) |r| tracker.add(r);
}

fn buildRectGeometry(
    rect: types.Rect,
    visual: types.VisualProps,
    transform: types.Transform,
    allocator: std.mem.Allocator,
) !struct { vertices: []dvui.Vertex, indices: []u16, bounds: dvui.Rect.Physical } {
    const bg = visual.background orelse return .{
        .vertices = &.{},
        .indices = &.{},
        .bounds = dvui.Rect.Physical{},
    };

    var vertices: std.ArrayList(dvui.Vertex) = .empty;
    errdefer vertices.deinit(allocator);
    var indices: std.ArrayList(u16) = .empty;
    errdefer indices.deinit(allocator);

    const color = draw.packedColorToDvui(bg, visual.opacity);
    const pma = dvui.Color.PMA.fromColor(color);

    const ax = rect.x + rect.w * transform.anchor[0];
    const ay = rect.y + rect.h * transform.anchor[1];
    const cos_r = std.math.cos(transform.rotation);
    const sin_r = std.math.sin(transform.rotation);
    const sx = transform.scale[0];
    const sy = transform.scale[1];
    const tx = transform.translation[0];
    const ty = transform.translation[1];

    const corners = [_][2]f32{
        .{ rect.x, rect.y },
        .{ rect.x + rect.w, rect.y },
        .{ rect.x + rect.w, rect.y + rect.h },
        .{ rect.x, rect.y + rect.h },
    };

    var bounds = dvui.Rect.Physical{
        .x = std.math.floatMax(f32),
        .y = std.math.floatMax(f32),
        .w = -std.math.floatMax(f32),
        .h = -std.math.floatMax(f32),
    };

    for (corners) |c| {
        const dx = (c[0] - ax) * sx;
        const dy = (c[1] - ay) * sy;
        const rx = dx * cos_r - dy * sin_r;
        const ry = dx * sin_r + dy * cos_r;
        const fx = ax + rx + tx;
        const fy = ay + ry + ty;
        bounds.x = @min(bounds.x, fx);
        bounds.y = @min(bounds.y, fy);
        bounds.w = @max(bounds.w, fx);
        bounds.h = @max(bounds.h, fy);
        try vertices.append(allocator, .{ .pos = .{ .x = fx, .y = fy }, .col = pma });
    }

    try indices.appendSlice(allocator, &.{ 0, 1, 2, 0, 2, 3 });

    bounds.w = bounds.w - bounds.x;
    bounds.h = bounds.h - bounds.y;

    return .{
        .vertices = try vertices.toOwnedSlice(allocator),
        .indices = try indices.toOwnedSlice(allocator),
        .bounds = bounds,
    };
}

pub fn shouldCachePaint(node: *const types.SolidNode) bool {
    if (node.kind != .element) return false;
    if (node.isInteractive()) return false;
    if (node.interactiveChildCount() > 0) return false;
    return draw.shouldDirectDraw(node);
}
