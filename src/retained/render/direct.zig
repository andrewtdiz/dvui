const std = @import("std");
const dvui = @import("dvui");

const apply = @import("../style/apply.zig");
const types = @import("../core/types.zig");
const transitions = @import("transitions.zig");

pub const dvuiColorToPacked = apply.dvuiColorToPacked;
pub const packedColorToDvui = apply.packedColorToDvui;
pub const applyClassSpecToVisual = apply.applyClassSpecToVisual;
pub const applyVisualToOptions = apply.applyVisualToOptions;

pub fn rectToPhysical(rect: types.Rect) dvui.Rect.Physical {
    return .{
        .x = rect.x,
        .y = rect.y,
        .w = rect.w,
        .h = rect.h,
    };
}

pub fn transformedRect(node: *const types.SolidNode, base: ?types.Rect) ?types.Rect {
    const rect = base orelse return null;
    const t = transitions.effectiveTransform(node);
    const ax = rect.x + rect.w * t.anchor[0];
    const ay = rect.y + rect.h * t.anchor[1];
    const cos_r = std.math.cos(t.rotation);
    const sin_r = std.math.sin(t.rotation);
    const sx = t.scale[0];
    const sy = t.scale[1];
    const tx = t.translation[0];
    const ty = t.translation[1];

    const corners = [_][2]f32{
        .{ rect.x, rect.y },
        .{ rect.x + rect.w, rect.y },
        .{ rect.x + rect.w, rect.y + rect.h },
        .{ rect.x, rect.y + rect.h },
    };

    var min_x = std.math.floatMax(f32);
    var min_y = std.math.floatMax(f32);
    var max_x = -std.math.floatMax(f32);
    var max_y = -std.math.floatMax(f32);

    for (corners) |c| {
        const dx = (c[0] - ax) * sx;
        const dy = (c[1] - ay) * sy;
        const rx = dx * cos_r - dy * sin_r;
        const ry = dx * sin_r + dy * cos_r;
        const fx = ax + rx + tx;
        const fy = ay + ry + ty;
        min_x = @min(min_x, fx);
        min_y = @min(min_y, fy);
        max_x = @max(max_x, fx);
        max_y = @max(max_y, fy);
    }

    return types.Rect{
        .x = min_x,
        .y = min_y,
        .w = max_x - min_x,
        .h = max_y - min_y,
    };
}

pub fn applyTransformToOptions(node: *const types.SolidNode, options: *dvui.Options) void {
    if (node.layout.rect) |rect| {
        const t = transitions.effectiveTransform(node);
        const bounds = transformedRect(node, rect) orelse rect;
        const scale = dvui.windowNaturalScale();
        const inv_scale: f32 = if (scale != 0) 1.0 / scale else 1.0;
        options.rect = dvui.Rect{
            .x = bounds.x * inv_scale,
            .y = bounds.y * inv_scale,
            .w = bounds.w * inv_scale,
            .h = bounds.h * inv_scale,
        };
        if (options.rotation == null) {
            options.rotation = t.rotation;
        }
    }
}

pub fn drawRectDirect(
    rect: types.Rect,
    visual: types.VisualProps,
    transform: types.Transform,
    allocator: std.mem.Allocator,
    fallback_bg: ?dvui.Color,
) void {
    const bg = visual.background orelse blk: {
        if (fallback_bg) |c| break :blk dvuiColorToPacked(c);
        return;
    };
    var builder = dvui.Triangles.Builder.init(allocator, 4, 6) catch return;
    defer builder.deinit(allocator);

    const color = packedColorToDvui(bg, visual.opacity);
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

    for (corners) |c| {
        const dx = (c[0] - ax) * sx;
        const dy = (c[1] - ay) * sy;
        const rx = dx * cos_r - dy * sin_r;
        const ry = dx * sin_r + dy * cos_r;
        const fx = ax + rx + tx;
        const fy = ay + ry + ty;
        builder.appendVertex(.{ .pos = .{ .x = fx, .y = fy }, .col = pma });
    }

    builder.appendTriangles(&.{ 0, 1, 2, 0, 2, 3 });

    const tris = builder.build();
    dvui.renderTriangles(tris, null) catch {};
}

pub fn drawTriangleDirect(
    rect: types.Rect,
    visual: types.VisualProps,
    transform: types.Transform,
    allocator: std.mem.Allocator,
    fallback_bg: ?dvui.Color,
) void {
    const bg = visual.background orelse blk: {
        if (fallback_bg) |c| break :blk dvuiColorToPacked(c);
        return;
    };
    var builder = dvui.Triangles.Builder.init(allocator, 3, 3) catch return;
    defer builder.deinit(allocator);

    const color = packedColorToDvui(bg, visual.opacity);
    const pma = dvui.Color.PMA.fromColor(color);

    const ax = rect.x + rect.w * transform.anchor[0];
    const ay = rect.y + rect.h * transform.anchor[1];
    const cos_r = std.math.cos(transform.rotation);
    const sin_r = std.math.sin(transform.rotation);
    const sx = transform.scale[0];
    const sy = transform.scale[1];
    const tx = transform.translation[0];
    const ty = transform.translation[1];

    const points = [_][2]f32{
        .{ rect.x, rect.y + rect.h },
        .{ rect.x + rect.w * 0.5, rect.y },
        .{ rect.x + rect.w, rect.y + rect.h },
    };

    for (points) |p| {
        const dx = (p[0] - ax) * sx;
        const dy = (p[1] - ay) * sy;
        const rx = dx * cos_r - dy * sin_r;
        const ry = dx * sin_r + dy * cos_r;
        const fx = ax + rx + tx;
        const fy = ay + ry + ty;
        builder.appendVertex(.{ .pos = .{ .x = fx, .y = fy }, .col = pma });
    }

    builder.appendTriangles(&.{ 0, 1, 2 });

    const tris = builder.build();
    dvui.renderTriangles(tris, null) catch {};
}

pub fn drawTextDirect(rect: types.Rect, text: []const u8, visual: types.VisualProps, font: dvui.Font) void {
    const trimmed = std.mem.trim(u8, text, " \n\r\t");
    if (trimmed.len == 0) return;

    const color = if (visual.text_color) |tc|
        packedColorToDvui(tc, visual.opacity)
    else
        packedColorToDvui(.{ .value = 0xffffffff }, visual.opacity);

    const phys = rectToPhysical(rect);
    const rs = dvui.RectScale{
        .r = phys,
        .s = dvui.windowNaturalScale(),
    };
    const text_opts = dvui.render.TextOptions{
        .font = font,
        .text = trimmed,
        .rs = rs,
        .color = color,
    };
    dvui.renderText(text_opts) catch {};
}

pub fn shouldDirectDraw(node: *const types.SolidNode) bool {
    if (node.isInteractive()) return false;
    if (node.interactiveChildCount() > 0) return false;
    return std.mem.eql(u8, node.tag, "div") or
        std.mem.eql(u8, node.tag, "p") or
        std.mem.eql(u8, node.tag, "h1") or
        std.mem.eql(u8, node.tag, "h2") or
        std.mem.eql(u8, node.tag, "h3");
}
