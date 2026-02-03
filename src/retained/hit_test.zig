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

                const clip_children = spec.clip_children orelse node.visual_props.clip_children;
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
