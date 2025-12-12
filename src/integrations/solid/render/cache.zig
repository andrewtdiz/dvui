const std = @import("std");

const dvui = @import("dvui");

const types = @import("../core/types.zig");
const tailwind = @import("../style/tailwind.zig");
const draw = @import("direct.zig");

const log = std.log.scoped(.solid_bridge);

var paint_clip_debug_count: usize = 0;

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
    // Debug clipped paint order (gated, removed later).
    if (paint_clip_debug_count < 8) {
        const clipr = dvui.clipGet();
        const win = dvui.currentWindow();
        const screen = win.rect_pixels;
        if (clipr.x != 0 or clipr.y != 0 or clipr.w != screen.w or clipr.h != screen.h) {
            paint_clip_debug_count += 1;
            log.info("paint under clip id={d} tag={s} layout={any} painted={any} clip={any}", .{
                node.id,
                node.tag,
                rect,
                node.paint.painted_rect,
                clipr,
            });
        }
    }

    if (renderPaintCache(node)) return;

    const spec = node.prepareClassSpec();
    const scale = dvui.windowNaturalScale();
    const border_left = (spec.border.left orelse 0) * scale;
    const border_right = (spec.border.right orelse 0) * scale;
    const border_top = (spec.border.top orelse 0) * scale;
    const border_bottom = (spec.border.bottom orelse 0) * scale;
    const has_border = border_left > 0 or border_right > 0 or border_top > 0 or border_bottom > 0;

    const corner_radius = spec.corner_radius orelse node.visual.corner_radius;
    const has_rounding = corner_radius != 0;

    if (!has_border and !has_rounding and node.visual.background == null and fallback_bg == null) return;

    if (has_rounding) {
        const radius_phys_val = corner_radius * scale;
        const outer_phys = draw.rectToPhysical(rect);
        const outer_radius = dvui.Rect.Physical.all(radius_phys_val);

        const opacity = node.visual.opacity;
        var bg_color_opt: ?dvui.Color = null;
        if (node.visual.background) |bg_packed| {
            bg_color_opt = draw.packedColorToDvui(bg_packed, opacity);
        } else if (fallback_bg) |bg_color| {
            bg_color_opt = bg_color.opacity(opacity);
        }

        const border_color_base = if (spec.border_color) |bc| bc else (dvui.Options{}).color(.border);
        const border_color = border_color_base.opacity(opacity);

        if (has_border) {
            const uniform = border_left == border_right and border_left == border_top and border_left == border_bottom;
                if (uniform and border_left > 0) {
                    if (bg_color_opt) |bg_color| {
                        outer_phys.fill(outer_radius, .{ .color = bg_color });
                    }
                    const stroke_rect = outer_phys.insetAll(border_left * 0.5);
                    // Normal borders should respect paint order; don't use `.after` which forces overlay.
                    stroke_rect.stroke(outer_radius, .{ .thickness = border_left, .color = border_color });
                } else {
                // Non-uniform borders: fill outer with border color, then inner with background.
                outer_phys.fill(outer_radius, .{ .color = border_color });
                if (bg_color_opt) |bg_color| {
                    const inset_phys = dvui.Rect.Physical{
                        .x = border_left,
                        .y = border_top,
                        .w = border_right,
                        .h = border_bottom,
                    };
                    const inner_phys = outer_phys.inset(inset_phys);
                    const min_border = @min(@min(border_left, border_right), @min(border_top, border_bottom));
                    const inner_radius_val = @max(0.0, radius_phys_val - min_border);
                    const inner_radius = dvui.Rect.Physical.all(inner_radius_val);
                    if (!inner_phys.empty()) {
                        inner_phys.fill(inner_radius, .{ .color = bg_color });
                    }
                }
            }
        } else {
            if (bg_color_opt) |bg_color| {
                outer_phys.fill(outer_radius, .{ .color = bg_color });
            }
        }
        return;
    }

    if (has_border) {
        const geom = buildRectGeometry(rect, node.visual, node.transform, allocator, spec, fallback_bg) catch {
            draw.drawRectDirect(rect, node.visual, node.transform, allocator, fallback_bg);
            return;
        };
        defer allocator.free(geom.vertices);
        defer allocator.free(geom.indices);

        const tris = dvui.Triangles{
            .vertexes = geom.vertices,
            .indices = geom.indices,
            .bounds = geom.bounds,
        };
        dvui.renderTriangles(tris, null) catch {};
        return;
    }

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

    const spec = node.prepareClassSpec();

    // Ensure a background is available even if visual.background was not set before caching.
    var visual = node.visual;
    if (visual.background == null) {
        if (spec.background) |bg| {
            visual.background = draw.dvuiColorToPacked(bg);
            node.visual.background = visual.background;
        }
    }

    if (!shouldCachePaint(node) or rect == null) {
        const bounds = if (rect) |r| draw.transformedRect(node, r) orelse r else null;
        node.paint.painted_rect = bounds;
        if (bounds) |r| tracker.add(r);
        if (old_rect) |r| tracker.add(r);
        node.paint.version = node.subtree_version;
        node.paint.paint_dirty = false;
        return;
    }

    const geom = buildRectGeometry(rect.?, visual, node.transform, allocator, spec, null) catch {
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
    spec: tailwind.Spec,
    fallback_bg: ?dvui.Color,
) !struct { vertices: []dvui.Vertex, indices: []u16, bounds: dvui.Rect.Physical } {
    var vertices: std.ArrayList(dvui.Vertex) = .empty;
    errdefer vertices.deinit(allocator);
    var indices: std.ArrayList(u16) = .empty;
    errdefer indices.deinit(allocator);

    const scale = dvui.windowNaturalScale();
    const border_left = (spec.border.left orelse 0) * scale;
    const border_right = (spec.border.right orelse 0) * scale;
    const border_top = (spec.border.top orelse 0) * scale;
    const border_bottom = (spec.border.bottom orelse 0) * scale;
    const has_border = border_left > 0 or border_right > 0 or border_top > 0 or border_bottom > 0;

    const opacity = visual.opacity;
    var bg_color_opt: ?dvui.Color = null;
    if (visual.background) |bg_packed| {
        bg_color_opt = draw.packedColorToDvui(bg_packed, opacity);
    } else if (fallback_bg) |bg_color| {
        bg_color_opt = bg_color.opacity(opacity);
    }

    const border_color_base = if (spec.border_color) |bc| bc else (dvui.Options{}).color(.border);
    const border_color = border_color_base.opacity(opacity);
    const border_pma = dvui.Color.PMA.fromColor(border_color);

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

    var outer_pos: [4][2]f32 = undefined;
    for (corners, 0..) |c, i| {
        const dx = (c[0] - ax) * sx;
        const dy = (c[1] - ay) * sy;
        const rx = dx * cos_r - dy * sin_r;
        const ry = dx * sin_r + dy * cos_r;
        const fx = ax + rx + tx;
        const fy = ay + ry + ty;
        outer_pos[i] = .{ fx, fy };
        bounds.x = @min(bounds.x, fx);
        bounds.y = @min(bounds.y, fy);
        bounds.w = @max(bounds.w, fx);
        bounds.h = @max(bounds.h, fy);
    }

    var inner_rect = rect;
    var inner_pos: [4][2]f32 = undefined;
    if (has_border) {
        inner_rect.x += border_left;
        inner_rect.y += border_top;
        inner_rect.w = @max(0.0, inner_rect.w - (border_left + border_right));
        inner_rect.h = @max(0.0, inner_rect.h - (border_top + border_bottom));

        const inner_corners = [_][2]f32{
            .{ inner_rect.x, inner_rect.y },
            .{ inner_rect.x + inner_rect.w, inner_rect.y },
            .{ inner_rect.x + inner_rect.w, inner_rect.y + inner_rect.h },
            .{ inner_rect.x, inner_rect.y + inner_rect.h },
        };

        for (inner_corners, 0..) |c, i| {
            const dx = (c[0] - ax) * sx;
            const dy = (c[1] - ay) * sy;
            const rx = dx * cos_r - dy * sin_r;
            const ry = dx * sin_r + dy * cos_r;
            const fx = ax + rx + tx;
            const fy = ay + ry + ty;
            inner_pos[i] = .{ fx, fy };
        }
    }

    if (has_border) {
        for (outer_pos) |p| {
            try vertices.append(allocator, .{ .pos = .{ .x = p[0], .y = p[1] }, .col = border_pma });
        }
        for (inner_pos) |p| {
            try vertices.append(allocator, .{ .pos = .{ .x = p[0], .y = p[1] }, .col = border_pma });
        }

        var i: usize = 0;
        while (i < 4) : (i += 1) {
            const o0: u16 = @intCast(i);
            const o1: u16 = @intCast((i + 1) % 4);
            const in0: u16 = 4 + @as(u16, @intCast(i));
            const in1: u16 = 4 + @as(u16, @intCast((i + 1) % 4));
            try indices.appendSlice(allocator, &.{ o0, o1, in1, o0, in1, in0 });
        }
    }

    if (bg_color_opt) |bg_color| {
        const bg_pma = dvui.Color.PMA.fromColor(bg_color);
        const fill_base: u16 = @intCast(vertices.items.len);
        const fill_pos = if (has_border) inner_pos else outer_pos;
        const has_fill_area = if (has_border) (inner_rect.w > 0 and inner_rect.h > 0) else (rect.w > 0 and rect.h > 0);
        if (has_fill_area) {
            for (fill_pos) |p| {
                try vertices.append(allocator, .{ .pos = .{ .x = p[0], .y = p[1] }, .col = bg_pma });
            }
            try indices.appendSlice(allocator, &.{ fill_base, fill_base + 1, fill_base + 2, fill_base, fill_base + 2, fill_base + 3 });
        }
    }

    if (vertices.items.len == 0 or indices.items.len == 0) {
        return .{
            .vertices = &.{},
            .indices = &.{},
            .bounds = dvui.Rect.Physical{},
        };
    }

    bounds.w = bounds.w - bounds.x;
    bounds.h = bounds.h - bounds.y;

    return .{
        .vertices = try vertices.toOwnedSlice(allocator),
        .indices = try indices.toOwnedSlice(allocator),
        .bounds = bounds,
    };
}

pub fn shouldCachePaint(node: *types.SolidNode) bool {
    if (node.kind != .element) return false;
    if (node.isInteractive()) return false;
    if (node.interactiveChildCount() > 0) return false;
    const spec = node.prepareClassSpec();
    if (spec.corner_radius != null and spec.corner_radius.? != 0) return false;
    return draw.shouldDirectDraw(node);
}
