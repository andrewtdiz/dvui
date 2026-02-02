const std = @import("std");

const dvui = @import("dvui");

const types = @import("../core/types.zig");
const tailwind = @import("../style/tailwind.zig");
const draw = @import("direct.zig");
const transitions = @import("transitions.zig");
const derive = @import("internal/derive.zig");
const state = @import("internal/state.zig");

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

fn applyContextToVertexPos(ctx: state.RenderContext, pos: dvui.Point.Physical) dvui.Point.Physical {
    return .{
        .x = ctx.scale[0] * pos.x + ctx.offset[0],
        .y = ctx.scale[1] * pos.y + ctx.offset[1],
    };
}

fn applyContextToVertices(ctx: state.RenderContext, vertices: []dvui.Vertex) void {
    for (vertices) |*v| {
        v.pos = applyContextToVertexPos(ctx, v.pos);
    }
}

pub fn renderPaintCache(node: *types.SolidNode, ctx: state.RenderContext, allocator: std.mem.Allocator) bool {
    if (node.needsPaintUpdate()) return false;
    if (node.paint.vertices.items.len == 0 or node.paint.indices.items.len == 0) return false;
    const bounds_layout = node.paint.painted_bounds_layout orelse return false;
    if (ctx.scale[0] == 1 and ctx.scale[1] == 1 and ctx.offset[0] == 0 and ctx.offset[1] == 0) {
        const win = dvui.currentWindow();
        if (!win.render_target.offset.nonZero()) {
            const tris = dvui.Triangles{
                .vertexes = node.paint.vertices.items,
                .indices = node.paint.indices.items,
                .bounds = draw.rectToPhysical(bounds_layout),
            };
            dvui.renderTriangles(tris, null) catch {};
            return true;
        }
    }
    const vertices = allocator.alloc(dvui.Vertex, node.paint.vertices.items.len) catch return false;
    defer allocator.free(vertices);
    @memcpy(vertices, node.paint.vertices.items);
    applyContextToVertices(ctx, vertices);
    const bounds_ctx = state.contextRect(ctx, bounds_layout);
    const tris = dvui.Triangles{
        .vertexes = vertices,
        .indices = node.paint.indices.items,
        .bounds = draw.rectToPhysical(bounds_ctx),
    };
    dvui.renderTriangles(tris, null) catch {};
    return true;
}

pub fn renderCachedOrDirectBackground(
    node: *types.SolidNode,
    rect_layout: types.Rect,
    ctx: state.RenderContext,
    allocator: std.mem.Allocator,
    fallback_bg: ?dvui.Color,
) void {
    if (renderPaintCache(node, ctx, allocator)) return;

    var spec = node.prepareClassSpec();
    tailwind.applyHover(&spec, node.hovered);
    const base_scale = dvui.windowNaturalScale();
    const scale = if (node.layout.layout_scale != 0) node.layout.layout_scale else base_scale;
    const border_left = (spec.border.left orelse 0) * scale;
    const border_right = (spec.border.right orelse 0) * scale;
    const border_top = (spec.border.top orelse 0) * scale;
    const border_bottom = (spec.border.bottom orelse 0) * scale;
    const has_border = border_left > 0 or border_right > 0 or border_top > 0 or border_bottom > 0;

    const visual_eff = transitions.effectiveVisual(node);
    const transform_eff = transitions.effectiveTransform(node);
    const border_color_packed = transitions.effectiveBorderColor(node);

    const corner_radius = spec.corner_radius orelse visual_eff.corner_radius;
    const has_rounding = corner_radius != 0;

    if (!has_border and !has_rounding and visual_eff.background == null and fallback_bg == null) return;

    if (has_rounding) {
        const ctx_scale_x = @abs(ctx.scale[0]);
        const ctx_scale_y = @abs(ctx.scale[1]);
        const transform_scale = @min(@abs(transform_eff.scale[0]), @abs(transform_eff.scale[1]));
        const radius_phys_val = corner_radius * scale * transform_scale * @min(ctx_scale_x, ctx_scale_y);
        const rounded_rect = if (transform_eff.rotation == 0 and (transform_eff.scale[0] != 1 or transform_eff.scale[1] != 1 or transform_eff.translation[0] != 0 or transform_eff.translation[1] != 0))
            draw.transformedRect(node, rect_layout) orelse rect_layout
        else
            rect_layout;
        const rounded_ctx = state.contextRect(ctx, rounded_rect);
        const outer_phys = draw.rectToPhysical(rounded_ctx);
        const outer_radius = dvui.Rect.Physical.all(radius_phys_val);
        const fade: f32 = 2.0;

        const opacity = visual_eff.opacity;
        var bg_color_opt: ?dvui.Color = null;
        if (visual_eff.background) |bg_packed| {
            bg_color_opt = draw.packedColorToDvui(bg_packed, opacity);
        } else if (fallback_bg) |bg_color| {
            bg_color_opt = bg_color.opacity(opacity);
        }

        const border_color = draw.packedColorToDvui(border_color_packed, opacity);

        if (has_border) {
            const border_left_ctx = border_left * ctx_scale_x * @abs(transform_eff.scale[0]);
            const border_right_ctx = border_right * ctx_scale_x * @abs(transform_eff.scale[0]);
            const border_top_ctx = border_top * ctx_scale_y * @abs(transform_eff.scale[1]);
            const border_bottom_ctx = border_bottom * ctx_scale_y * @abs(transform_eff.scale[1]);
            const uniform = border_left_ctx == border_right_ctx and border_left_ctx == border_top_ctx and border_left_ctx == border_bottom_ctx;
            if (uniform and border_left_ctx > 0) {
                if (bg_color_opt) |bg_color| {
                    outer_phys.fill(outer_radius, .{ .color = bg_color, .fade = fade });
                }
                const stroke_rect = outer_phys.insetAll(border_left_ctx * 0.5);
                // Normal borders should respect paint order; don't use `.after` which forces overlay.
                stroke_rect.stroke(outer_radius, .{ .thickness = border_left_ctx, .color = border_color });
            } else {
                // Non-uniform borders: fill outer with border color, then inner with background.
                outer_phys.fill(outer_radius, .{ .color = border_color, .fade = fade });
                if (bg_color_opt) |bg_color| {
                    const inset_phys = dvui.Rect.Physical{
                        .x = border_left_ctx,
                        .y = border_top_ctx,
                        .w = border_right_ctx,
                        .h = border_bottom_ctx,
                    };
                    const inner_phys = outer_phys.inset(inset_phys);
                    const min_border = @min(@min(border_left_ctx, border_right_ctx), @min(border_top_ctx, border_bottom_ctx));
                    const inner_radius_val = @max(0.0, radius_phys_val - min_border);
                    const inner_radius = dvui.Rect.Physical.all(inner_radius_val);
                    if (!inner_phys.empty()) {
                        inner_phys.fill(inner_radius, .{ .color = bg_color, .fade = fade });
                    }
                }
            }
        } else {
            if (bg_color_opt) |bg_color| {
                outer_phys.fill(outer_radius, .{ .color = bg_color, .fade = fade });
            }
        }
        return;
    }

    var vertices: std.ArrayList(dvui.Vertex) = .empty;
    defer vertices.deinit(allocator);
    var indices: std.ArrayList(u16) = .empty;
    defer indices.deinit(allocator);

    const bounds_layout = buildRectGeometryInto(&vertices, &indices, rect_layout, scale, visual_eff, transform_eff, allocator, border_color_packed, spec, fallback_bg) catch return;
    if (vertices.items.len == 0 or indices.items.len == 0) return;

    applyContextToVertices(ctx, vertices.items);
    const bounds_ctx = state.contextRect(ctx, .{ .x = bounds_layout.x, .y = bounds_layout.y, .w = bounds_layout.w, .h = bounds_layout.h });

    const tris = dvui.Triangles{
        .vertexes = vertices.items,
        .indices = indices.items,
        .bounds = draw.rectToPhysical(bounds_ctx),
    };
    dvui.renderTriangles(tris, null) catch {};
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

    const old_rect = node.paint.painted_bounds_layout;

    node.paint.vertices.clearRetainingCapacity();
    node.paint.indices.clearRetainingCapacity();

    const rect = node.layout.rect;

    const spec = derive.apply(node);
    const base_scale = dvui.windowNaturalScale();
    const scale = if (node.layout.layout_scale != 0) node.layout.layout_scale else base_scale;

    const visual_eff = transitions.effectiveVisual(node);
    const transform_eff = transitions.effectiveTransform(node);
    const border_color_packed = transitions.effectiveBorderColor(node);
    const version = @max(node.version, node.layout.version);

    if (!shouldCachePaint(node, spec) or rect == null) {
        const bounds = if (rect) |r| draw.transformedRect(node, r) orelse r else null;
        node.paint.painted_bounds_layout = bounds;
        if (bounds) |r| tracker.add(r);
        if (old_rect) |r| tracker.add(r);
        node.paint.version = version;
        node.paint.paint_dirty = false;
        return;
    }

    const bounds = buildRectGeometryInto(&node.paint.vertices, &node.paint.indices, rect.?, scale, visual_eff, transform_eff, allocator, border_color_packed, spec, null) catch {
        const bounds = draw.transformedRect(node, rect.?) orelse rect.?;
        node.paint.painted_bounds_layout = bounds;
        tracker.add(bounds);
        if (old_rect) |r| tracker.add(r);
        node.paint.version = version;
        node.paint.paint_dirty = false;
        return;
    };

    node.paint.painted_bounds_layout = .{ .x = bounds.x, .y = bounds.y, .w = bounds.w, .h = bounds.h };
    node.paint.version = version;
    node.paint.paint_dirty = false;
    tracker.add(node.paint.painted_bounds_layout.?);
    if (old_rect) |r| tracker.add(r);
}

fn buildRectGeometryInto(
    vertices: *std.ArrayList(dvui.Vertex),
    indices: *std.ArrayList(u16),
    rect: types.Rect,
    scale: f32,
    visual: types.VisualProps,
    transform: types.Transform,
    allocator: std.mem.Allocator,
    border_color_packed: types.PackedColor,
    spec: tailwind.Spec,
    fallback_bg: ?dvui.Color,
) !dvui.Rect.Physical {
    vertices.clearRetainingCapacity();
    indices.clearRetainingCapacity();

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

    const border_color = draw.packedColorToDvui(border_color_packed, opacity);
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

    const fill_pos = if (has_border) inner_pos else outer_pos;
    const has_fill_area = if (has_border) (inner_rect.w > 0 and inner_rect.h > 0) else (rect.w > 0 and rect.h > 0);

    const fill_needed: usize = if (bg_color_opt != null and has_fill_area) @as(usize, 4) else 0;
    const border_needed: usize = if (has_border) @as(usize, 8) else 0;
    const vertices_needed = border_needed + fill_needed;

    const indices_needed: usize = (if (has_border) @as(usize, 24) else 0) + (if (fill_needed != 0) @as(usize, 6) else 0);
    if (vertices_needed == 0 or indices_needed == 0) {
        return dvui.Rect.Physical{};
    }

    try vertices.ensureTotalCapacity(allocator, vertices_needed);
    try indices.ensureTotalCapacity(allocator, indices_needed);

    if (has_border) {
        for (outer_pos) |p| {
            vertices.appendAssumeCapacity(.{ .pos = .{ .x = p[0], .y = p[1] }, .col = border_pma });
        }
        for (inner_pos) |p| {
            vertices.appendAssumeCapacity(.{ .pos = .{ .x = p[0], .y = p[1] }, .col = border_pma });
        }

        var i: usize = 0;
        while (i < 4) : (i += 1) {
            const o0: u16 = @intCast(i);
            const o1: u16 = @intCast((i + 1) % 4);
            const in0: u16 = 4 + @as(u16, @intCast(i));
            const in1: u16 = 4 + @as(u16, @intCast((i + 1) % 4));
            indices.appendSliceAssumeCapacity(&.{ o0, o1, in1, o0, in1, in0 });
        }
    }

    if (fill_needed != 0 and bg_color_opt != null) {
        const bg_color = bg_color_opt.?;
        const bg_pma = dvui.Color.PMA.fromColor(bg_color);
        const fill_base: u16 = @intCast(vertices.items.len);
        for (fill_pos) |p| {
            vertices.appendAssumeCapacity(.{ .pos = .{ .x = p[0], .y = p[1] }, .col = bg_pma });
        }
        indices.appendSliceAssumeCapacity(&.{ fill_base, fill_base + 1, fill_base + 2, fill_base, fill_base + 2, fill_base + 3 });
    }

    if (vertices.items.len == 0 or indices.items.len == 0) {
        vertices.clearRetainingCapacity();
        indices.clearRetainingCapacity();
        return dvui.Rect.Physical{};
    }

    bounds.w = bounds.w - bounds.x;
    bounds.h = bounds.h - bounds.y;

    return bounds;
}

fn buildRectGeometry(
    rect: types.Rect,
    scale: f32,
    visual: types.VisualProps,
    transform: types.Transform,
    allocator: std.mem.Allocator,
    border_color_packed: types.PackedColor,
    spec: tailwind.Spec,
    fallback_bg: ?dvui.Color,
) !struct { vertices: []dvui.Vertex, indices: []u16, bounds: dvui.Rect.Physical } {
    var vertices: std.ArrayList(dvui.Vertex) = .empty;
    errdefer vertices.deinit(allocator);
    var indices: std.ArrayList(u16) = .empty;
    errdefer indices.deinit(allocator);

    const bounds = try buildRectGeometryInto(&vertices, &indices, rect, scale, visual, transform, allocator, border_color_packed, spec, fallback_bg);

    return .{
        .vertices = try vertices.toOwnedSlice(allocator),
        .indices = try indices.toOwnedSlice(allocator),
        .bounds = bounds,
    };
}

pub fn shouldCachePaint(node: *types.SolidNode, spec: tailwind.Spec) bool {
    if (node.kind != .element) return false;
    if (node.isInteractive()) return false;
    if (node.interactiveChildCount() > 0) return false;
    if (spec.transition.enabled) return false;
    if (spec.corner_radius != null and spec.corner_radius.? != 0) return false;
    return draw.shouldDirectDraw(node);
}
