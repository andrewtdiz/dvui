const dvui = @import("dvui");

const types = @import("../core/types.zig");
const flex = @import("flex.zig");
const measure = @import("measure.zig");
const transitions = @import("../render/transitions.zig");
const tailwind = @import("../style/tailwind.zig");

const use_yoga_layout = false;

var last_screen_size: types.Size = .{};
var last_natural_scale: f32 = 0;
var layout_updated: bool = false;
var layout_force_recompute: bool = false;

pub fn init() void {
    last_screen_size = .{};
    last_natural_scale = 0;
    layout_updated = false;
    layout_force_recompute = false;
}

pub fn deinit() void {
    last_screen_size = .{};
    last_natural_scale = 0;
    layout_updated = false;
    layout_force_recompute = false;
}

pub fn updateLayouts(store: *types.NodeStore) void {
    layout_updated = false;
    layout_force_recompute = false;
    const win = dvui.currentWindow();
    const screen_w = win.rect_pixels.w;
    const screen_h = win.rect_pixels.h;
    const natural_scale = dvui.windowNaturalScale();

    const root_rect = types.Rect{
        .x = 0,
        .y = 0,
        .w = screen_w,
        .h = screen_h,
    };

    const root = store.node(0) orelse return;

    // If screen size changed, invalidate the entire layout tree so descendants recompute.
    const size_changed = last_screen_size.w != screen_w or last_screen_size.h != screen_h;
    const scale_changed = last_natural_scale != natural_scale;
    if (size_changed or scale_changed) {
        invalidateLayoutSubtree(store, root);
        store.markNodeChanged(root.id);
        last_screen_size = .{ .w = screen_w, .h = screen_h };
        last_natural_scale = natural_scale;
    }

    const tree_dirty = root.hasDirtySubtree();
    const layout_dirty = root.needsLayoutUpdate();
    const has_layout_animation = hasActiveLayoutAnimations(store, root);

    if (!size_changed and !scale_changed and !layout_dirty) {
        if (tree_dirty and !has_layout_animation) return;
        const missing_layout = hasMissingLayout(store, root);
        if (!missing_layout and !has_layout_animation) return;
    }

    layout_updated = true;
    layout_force_recompute = has_layout_animation;
    updateLayoutIfDirty(store, root, root_rect);
    layout_force_recompute = false;
}

pub fn didUpdateLayouts() bool {
    return layout_updated;
}

pub fn invalidateLayoutSubtree(store: *types.NodeStore, node: *types.SolidNode) void {
    node.invalidateLayout();
    node.invalidatePaint();
    for (node.children.items) |child_id| {
        if (store.node(child_id)) |child| {
            invalidateLayoutSubtree(store, child);
        }
    }
}

fn updateLayoutIfDirty(store: *types.NodeStore, node: *types.SolidNode, parent_rect: types.Rect) void {
    // Skip hidden elements entirely - they should not take up layout space
    var spec = node.prepareClassSpec();
    tailwind.applyHover(&spec, node.hovered);
    if (spec.hidden) {
        node.layout.rect = types.Rect{}; // Zero rect
        return;
    }

    if (!layout_force_recompute and !node.needsLayoutUpdate()) {
        const layout_rect = node.layout.child_rect orelse node.layout.rect orelse parent_rect;
        for (node.children.items) |child_id| {
            if (store.node(child_id)) |child| {
                updateLayoutIfDirty(store, child, layout_rect);
            }
        }
        return;
    }

    computeNodeLayout(store, node, parent_rect);
}

fn sideValue(value: ?f32) f32 {
    return value orelse 0;
}

pub fn computeNodeLayout(store: *types.NodeStore, node: *types.SolidNode, parent_rect: types.Rect) void {
    const prev_rect = node.layout.rect;
    const prev_child_rect = node.layout.child_rect;
    const prev_scale = node.layout.layout_scale;
    var spec = node.prepareClassSpec();
    tailwind.applyHover(&spec, node.hovered);
    const base_scale = dvui.windowNaturalScale();
    var parent_scale = base_scale;
    if (node.parent) |pid| {
        if (store.node(pid)) |parent| {
            if (parent.layout.layout_scale != 0) {
                parent_scale = parent.layout.layout_scale;
            }
        }
    }
    const local_scale = spec.scale orelse 1.0;
    const node_scale = parent_scale * local_scale;
    node.layout.layout_scale = node_scale;
    const scale = if (node_scale != 0) node_scale else base_scale;
    const parent_w_scaled = parent_rect.w * local_scale;
    const parent_h_scaled = parent_rect.h * local_scale;

    // Skip hidden elements
    if (spec.hidden) {
        node.layout.rect = types.Rect{};
        return;
    }

    var rect: types.Rect = undefined;
    const is_absolute = spec.position != null and spec.position.? == .absolute;

    if (is_absolute) {
        rect = types.Rect{
            .x = parent_rect.x,
            .y = parent_rect.y,
            .w = 0,
            .h = 0,
        };

        const left_offset = sideValue(spec.left) * scale;
        const right_offset = sideValue(spec.right) * scale;
        const top_offset = sideValue(spec.top) * scale;
        const bottom_offset = sideValue(spec.bottom) * scale;

        if (spec.width) |w| {
            switch (w) {
                .full => rect.w = parent_w_scaled,
                .pixels => |px| rect.w = px * scale,
            }
        } else if (spec.left != null and spec.right != null) {
            rect.w = @max(0.0, parent_w_scaled - left_offset - right_offset);
        }

        if (spec.height) |h| {
            switch (h) {
                .full => rect.h = parent_h_scaled,
                .pixels => |px| rect.h = px * scale,
            }
        } else if (spec.top != null and spec.bottom != null) {
            rect.h = @max(0.0, parent_h_scaled - top_offset - bottom_offset);
        }

        if (node.kind == .text) {
            const measured = measure.measureTextCached(store, node);
            if (rect.w == 0) rect.w = measured.w;
            if (rect.h == 0) rect.h = measured.h;
        }
        if (rect.w == 0 or rect.h == 0) {
            const intrinsic = measure.measureNodeSize(store, node, .{ .w = parent_rect.w, .h = parent_rect.h });
            if (rect.w == 0) rect.w = intrinsic.w;
            if (rect.h == 0) rect.h = intrinsic.h;
        }

        if (spec.layout_anchor) |anchor| {
            var anchor_x = parent_rect.x;
            var anchor_y = parent_rect.y;
            if (spec.left != null) {
                anchor_x = parent_rect.x + left_offset;
            } else if (spec.right != null) {
                anchor_x = parent_rect.x + parent_rect.w - right_offset;
            }
            if (spec.top != null) {
                anchor_y = parent_rect.y + top_offset;
            } else if (spec.bottom != null) {
                anchor_y = parent_rect.y + parent_rect.h - bottom_offset;
            }
            rect.x = anchor_x - rect.w * anchor[0];
            rect.y = anchor_y - rect.h * anchor[1];
        } else {
            if (spec.left != null) {
                rect.x = parent_rect.x + left_offset;
            } else if (spec.right != null) {
                rect.x = parent_rect.x + parent_rect.w - right_offset - rect.w;
            }
            if (spec.top != null) {
                rect.y = parent_rect.y + top_offset;
            } else if (spec.bottom != null) {
                rect.y = parent_rect.y + parent_rect.h - bottom_offset - rect.h;
            }
        }
    } else {
        rect = parent_rect;

        const margin_base = types.SideOffsets{
            .left = sideValue(spec.margin.left) * scale,
            .right = sideValue(spec.margin.right) * scale,
            .top = sideValue(spec.margin.top) * scale,
            .bottom = sideValue(spec.margin.bottom) * scale,
        };
        const margin = if (spec.transition.enabled and spec.transition.props.layout) transitions.effectiveMargin(node, margin_base) else margin_base;
        const margin_left = margin.left;
        const margin_right = margin.right;
        const margin_top = margin.top;
        const margin_bottom = margin.bottom;

        rect.x += margin_left;
        rect.y += margin_top;
        rect.w = @max(0.0, parent_w_scaled - (margin_left + margin_right));
        rect.h = @max(0.0, parent_h_scaled - (margin_top + margin_bottom));

        if (spec.width) |w| {
            switch (w) {
                .full => rect.w = @max(0.0, parent_w_scaled - (margin_left + margin_right)),
                .pixels => |px| rect.w = px * scale,
            }
        }
        if (spec.height) |h| {
            switch (h) {
                .full => rect.h = @max(0.0, parent_h_scaled - (margin_top + margin_bottom)),
                .pixels => |px| rect.h = px * scale,
            }
        }

        if (node.kind == .text) {
            const measured = measure.measureTextCached(store, node);
            if (rect.w == 0) rect.w = measured.w;
            if (rect.h == 0) rect.h = measured.h;
        }
        if (rect.w == 0 or rect.h == 0) {
            const intrinsic = measure.measureNodeSize(store, node, .{ .w = rect.w, .h = rect.h });
            if (rect.w == 0) rect.w = intrinsic.w;
            if (rect.h == 0) rect.h = intrinsic.h;
        }
    }

    node.layout.rect = rect;
    node.layout.version = store.currentVersion();

    const padding_base = types.SideOffsets{
        .left = sideValue(spec.padding.left) * scale,
        .right = sideValue(spec.padding.right) * scale,
        .top = sideValue(spec.padding.top) * scale,
        .bottom = sideValue(spec.padding.bottom) * scale,
    };
    const padding = if (spec.transition.enabled and spec.transition.props.layout) transitions.effectivePadding(node, padding_base) else padding_base;
    const pad_left = padding.left;
    const pad_right = padding.right;
    const pad_top = padding.top;
    const pad_bottom = padding.bottom;
    const border_left = sideValue(spec.border.left) * scale;
    const border_right = sideValue(spec.border.right) * scale;
    const border_top = sideValue(spec.border.top) * scale;
    const border_bottom = sideValue(spec.border.bottom) * scale;

    var child_rect = rect;
    child_rect.x += pad_left + border_left;
    child_rect.y += pad_top + border_top;
    child_rect.w = @max(0.0, child_rect.w - (pad_left + pad_right + border_left + border_right));
    child_rect.h = @max(0.0, child_rect.h - (pad_top + pad_bottom + border_top + border_bottom));

    node.layout.child_rect = child_rect;

    if (prev_rect) |prev| {
        const rect_changed = prev.x != rect.x or prev.y != rect.y or prev.w != rect.w or prev.h != rect.h or prev_scale != node.layout.layout_scale;
        const child_changed = if (prev_child_rect) |prev_child| blk: {
            break :blk prev_child.x != child_rect.x or prev_child.y != child_rect.y or prev_child.w != child_rect.w or prev_child.h != child_rect.h;
        } else true;
        if (rect_changed or child_changed) {
            invalidateLayoutSubtree(store, node);
            node.layout.rect = rect;
            node.layout.child_rect = child_rect;
            node.layout.version = store.currentVersion();
        }
    }

    const layout_rect = child_rect;

    if (spec.is_flex) {
        if (use_yoga_layout) {
            const yoga_layout = @import("yoga.zig");
            yoga_layout.layoutFlexChildren(store, node, layout_rect, spec);
        } else {
            flex.layoutFlexChildren(store, node, layout_rect, spec);
        }
    } else {
        for (node.children.items) |child_id| {
            if (store.node(child_id)) |child| {
                updateLayoutIfDirty(store, child, layout_rect);
            }
        }
    }
}

fn offsetLayoutSubtree(store: *types.NodeStore, node: *types.SolidNode, dx: f32, dy: f32, version: u64) void {
    if (node.layout.rect) |rect| {
        node.layout.rect = types.Rect{
            .x = rect.x + dx,
            .y = rect.y + dy,
            .w = rect.w,
            .h = rect.h,
        };
        node.layout.version = version;
        node.invalidatePaint();
    }
    if (node.layout.child_rect) |child_rect| {
        node.layout.child_rect = types.Rect{
            .x = child_rect.x + dx,
            .y = child_rect.y + dy,
            .w = child_rect.w,
            .h = child_rect.h,
        };
    }

    for (node.children.items) |child_id| {
        if (store.node(child_id)) |child| {
            offsetLayoutSubtree(store, child, dx, dy, version);
        }
    }
}

fn applyAnchoredPlacement(store: *types.NodeStore, node: *types.SolidNode, screen: types.Rect) void {
    if (node.anchor_id) |anchor_id| {
        if (anchor_id != node.id) {
            const anchor = store.node(anchor_id) orelse null;
            if (anchor) |anchor_node| {
                const anchor_rect_opt = anchor_node.layout.rect;
                const node_rect_opt = node.layout.rect;
                if (anchor_rect_opt != null and node_rect_opt != null) {
                    const anchor_rect = anchor_rect_opt.?;
                    const node_rect = node_rect_opt.?;
                    const screen_rect = dvui.Rect.Natural.cast(screen);
                    const offset_scale = if (node.layout.layout_scale != 0) node.layout.layout_scale else dvui.windowNaturalScale();
                    const placement = dvui.AnchorPlacement{
                        .side = node.anchor_side,
                        .alignment = node.anchor_align,
                        .offset = node.anchor_offset * offset_scale,
                    };
                    const placed = dvui.placeAnchoredOnScreen(
                        screen_rect,
                        dvui.Rect.Natural.cast(anchor_rect),
                        placement,
                        dvui.Rect.Natural.cast(node_rect),
                    );
                    const dx = placed.x - node_rect.x;
                    const dy = placed.y - node_rect.y;
                    if (dx != 0 or dy != 0) {
                        offsetLayoutSubtree(store, node, dx, dy, store.currentVersion());
                    }
                }
            }
        }
    }

    for (node.children.items) |child_id| {
        if (store.node(child_id)) |child| {
            applyAnchoredPlacement(store, child, screen);
        }
    }
}

fn updateScrollContentSize(store: *types.NodeStore, node: *types.SolidNode, viewport: types.Rect) void {
    var content_w = viewport.w;
    var content_h = viewport.h;
    const allow_x = node.scroll.allowX();
    const allow_y = node.scroll.allowY();
    if (allow_x and node.scroll.canvas_width > 0) {
        content_w = @max(content_w, node.scroll.canvas_width);
    }
    if (allow_y and node.scroll.canvas_height > 0) {
        content_h = @max(content_h, node.scroll.canvas_height);
    }
    if (node.scroll.isAutoCanvas()) {
        const auto_size = computeScrollAutoSize(store, node, viewport);
        if (allow_x) content_w = @max(content_w, auto_size.w);
        if (allow_y) content_h = @max(content_h, auto_size.h);
    }
    node.scroll.content_width = content_w;
    node.scroll.content_height = content_h;
}

fn computeScrollAutoSize(store: *types.NodeStore, node: *types.SolidNode, viewport: types.Rect) types.Size {
    var min_x = viewport.x;
    var min_y = viewport.y;
    var max_x = viewport.x + viewport.w;
    var max_y = viewport.y + viewport.h;
    var saw = false;

    for (node.children.items) |child_id| {
        const child = store.node(child_id) orelse continue;
        const rect_opt = child.layout.rect;
        if (rect_opt) |rect| {
            if (rect.w == 0 and rect.h == 0) continue;
            const dx = if (node.scroll.allowX()) node.scroll.offset_x else 0;
            const dy = if (node.scroll.allowY()) node.scroll.offset_y else 0;
            const x = rect.x + dx;
            const y = rect.y + dy;
            min_x = @min(min_x, x);
            min_y = @min(min_y, y);
            max_x = @max(max_x, x + rect.w);
            max_y = @max(max_y, y + rect.h);
            saw = true;
        }
    }

    if (!saw) {
        return types.Size{ .w = viewport.w, .h = viewport.h };
    }

    return types.Size{
        .w = @max(0.0, max_x - min_x),
        .h = @max(0.0, max_y - min_y),
    };
}

fn hasMissingLayout(store: *types.NodeStore, node: *types.SolidNode) bool {
    if (node.layout.rect == null) return true;
    for (node.children.items) |child_id| {
        if (store.node(child_id)) |child| {
            if (hasMissingLayout(store, child)) return true;
        }
    }
    return false;
}

fn hasActiveLayoutAnimations(store: *types.NodeStore, node: *types.SolidNode) bool {
    if (transitions.hasActiveSpacingAnimation(node)) return true;
    for (node.children.items) |child_id| {
        if (store.node(child_id)) |child| {
            if (hasActiveLayoutAnimations(store, child)) return true;
        }
    }
    return false;
}
