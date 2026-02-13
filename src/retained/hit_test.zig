const dvui = @import("dvui");

const types = @import("core/types.zig");
const state = @import("render/internal/state.zig");
const transitions = @import("render/transitions.zig");

pub const RenderContext = state.RenderContext;
pub const rectContains = state.rectContains;

pub const HitTestOptions = struct {
    skip_portals: bool = false,
};

pub fn scan(
    store: *types.NodeStore,
    node: *types.SolidNode,
    point: dvui.Point.Physical,
    ctx: RenderContext,
    visitor: anytype,
    order: *u32,
    opts: HitTestOptions,
) void {
    if (opts.skip_portals and state.isPortalNode(node)) return;

    if (ctx.clip) |clip| {
        if (!state.rectContains(clip, point)) return;
    }

    var next_ctx = ctx;

    if (node.kind == .element) {
        const spec = node.prepareClassSpec();
        if (spec.hidden) return;

        if ((spec.opacity orelse node.visual_props.opacity) > 0) {
            if (node.layout.rect) |base_rect| {
                const rect = state.nodeBoundsInContext(ctx, node, base_rect);
                if (state.rectContains(rect, point)) {
                    var ord = order.*;
                    if (visitor.count(node, spec)) {
                        order.* += 1;
                        ord = order.*;
                    }
                    visitor.hit(node, spec, rect, ord);
                }

                const clip_children = (spec.clip_children orelse node.visual_props.clip_children) or spec.scroll_x or spec.scroll_y or node.scroll.isEnabled();
                if (clip_children) {
                    if (next_ctx.clip) |clip| {
                        next_ctx.clip = state.intersectRect(clip, rect);
                    } else {
                        next_ctx.clip = rect;
                    }
                }
            }
        }

        if (node.layout.rect) |rect| {
            const t = transitions.effectiveTransform(node);
            const anchor = dvui.Point.Physical{
                .x = rect.x + rect.w * t.anchor[0],
                .y = rect.y + rect.h * t.anchor[1],
            };
            const offset = dvui.Point.Physical{
                .x = anchor.x + t.translation[0] - t.scale[0] * anchor.x,
                .y = anchor.y + t.translation[1] - t.scale[1] * anchor.y,
            };
            next_ctx.scale = .{ ctx.scale[0] * t.scale[0], ctx.scale[1] * t.scale[1] };
            next_ctx.offset = .{
                ctx.scale[0] * offset.x + ctx.offset[0],
                ctx.scale[1] * offset.y + ctx.offset[1],
            };
        }
    }

    for (node.children.items) |child_id| {
        if (store.node(child_id)) |child| {
            scan(store, child, point, next_ctx, visitor, order, opts);
        }
    }
}

test "overflow-y-scroll clips descendants during hit testing" {
    const std = @import("std");
    var store: types.NodeStore = undefined;
    try store.init(std.testing.allocator);
    defer store.deinit();

    try store.upsertElement(1, "div");
    try store.insert(0, 1, null);
    try store.setClassName(1, "overflow-y-scroll");

    try store.upsertElement(2, "div");
    try store.insert(1, 2, null);

    const scroll_node = store.node(1) orelse return error.TestUnexpectedResult;
    const child_node = store.node(2) orelse return error.TestUnexpectedResult;

    scroll_node.layout.rect = .{ .x = 0, .y = 0, .w = 100, .h = 100 };
    child_node.layout.rect = .{ .x = 0, .y = 120, .w = 80, .h = 60 };

    var hit_child = false;
    var visitor = struct {
        hit_child: *bool,

        pub fn count(self: *@This(), node: *types.SolidNode, spec: anytype) bool {
            _ = self;
            _ = node;
            _ = spec;
            return true;
        }

        pub fn hit(self: *@This(), node: *types.SolidNode, spec: anytype, rect: types.Rect, ord: u32) void {
            _ = spec;
            _ = rect;
            _ = ord;
            if (node.id == 2) {
                self.hit_child.* = true;
            }
        }
    }{ .hit_child = &hit_child };

    const root = store.node(0) orelse return error.TestUnexpectedResult;
    const point = dvui.Point.Physical{ .x = 10, .y = 130 };
    const ctx = RenderContext{ .origin = .{ .x = 0, .y = 0 }, .clip = null, .scale = .{ 1, 1 }, .offset = .{ 0, 0 } };
    var order: u32 = 0;
    scan(&store, root, point, ctx, &visitor, &order, .{ .skip_portals = false });

    try std.testing.expect(!hit_child);
}
