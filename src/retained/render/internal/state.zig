const std = @import("std");
const dvui = @import("dvui");

const types = @import("../../core/types.zig");
const direct = @import("../direct.zig");

pub const RenderLayer = enum {
    base,
    overlay,
};

pub const overlay_subwindow_seed: u32 = 0x4f564c59;

pub const OverlayState = struct {
    modal: bool = false,
    hit_rect: ?types.Rect = null,
};

pub const RenderContext = struct {
    origin: dvui.Point.Physical,
    clip: ?types.Rect = null,
    scale: [2]f32 = .{ 1, 1 },
    offset: [2]f32 = .{ 0, 0 },
};

pub fn contextPoint(ctx: RenderContext, point: dvui.Point.Physical) dvui.Point.Physical {
    return .{
        .x = ctx.scale[0] * point.x + ctx.offset[0],
        .y = ctx.scale[1] * point.y + ctx.offset[1],
    };
}

pub fn contextRect(ctx: RenderContext, rect: types.Rect) types.Rect {
    return .{
        .x = ctx.scale[0] * rect.x + ctx.offset[0],
        .y = ctx.scale[1] * rect.y + ctx.offset[1],
        .w = rect.w * ctx.scale[0],
        .h = rect.h * ctx.scale[1],
    };
}

pub fn nodeBoundsInContext(ctx: RenderContext, node: *const types.SolidNode, rect: types.Rect) types.Rect {
    const bounds_layout = direct.transformedRect(node, rect) orelse rect;
    return contextRect(ctx, bounds_layout);
}

pub const ClipState = struct {
    active: bool = false,
    rect: types.Rect = .{},
};

pub const PointerPick = struct {
    id: u32 = 0,
    z_index: i16 = std.math.minInt(i16),
    order: u32 = 0,
};

pub const OrderedNode = struct {
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

pub fn sortOrderedNodes(nodes: []OrderedNode) void {
    if (nodes.len < 2) return;
    std.sort.pdq(OrderedNode, nodes, {}, orderedNodeLessThan);
}

pub fn physicalToDvuiRect(rect: types.Rect) dvui.Rect {
    const scale = dvui.windowNaturalScale();
    const inv_scale: f32 = if (scale != 0) 1.0 / scale else 1.0;
    return dvui.Rect{
        .x = rect.x * inv_scale,
        .y = rect.y * inv_scale,
        .w = rect.w * inv_scale,
        .h = rect.h * inv_scale,
    };
}

pub fn intersectRect(a: types.Rect, b: types.Rect) types.Rect {
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

pub fn unionRect(a: types.Rect, b: types.Rect) types.Rect {
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

pub fn appendRect(target: *?types.Rect, rect: types.Rect) void {
    if (rect.w <= 0 or rect.h <= 0) return;
    if (target.*) |existing| {
        target.* = unionRect(existing, rect);
    } else {
        target.* = rect;
    }
}

pub fn rectContains(rect: types.Rect, point: dvui.Point.Physical) bool {
    if (rect.w <= 0 or rect.h <= 0) return false;
    if (point.x < rect.x or point.y < rect.y) return false;
    if (point.x > rect.x + rect.w or point.y > rect.y + rect.h) return false;
    return true;
}

pub fn isPortalNode(node: *const types.SolidNode) bool {
    return node.kind == .element and std.mem.eql(u8, node.tag, "portal");
}

pub fn overlaySubwindowId() dvui.Id {
    return dvui.Id.extendId(null, @src(), nodeIdExtra(overlay_subwindow_seed));
}

pub fn scrollContentId(node_id: u32) dvui.Id {
    return dvui.Id.extendId(null, @src(), nodeIdExtra(node_id));
}

pub fn nodeIdExtra(id: u32) usize {
    var hasher = std.hash.Wyhash.init(0);
    hasher.update(std.mem.asBytes(&id));
    return @intCast(hasher.final());
}
