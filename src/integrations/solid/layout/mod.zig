const std = @import("std");
const dvui = @import("dvui");

const types = @import("../core/types.zig");
const flex = @import("flex.zig");
const measure = @import("measure.zig");

var last_screen_size: types.Size = .{};
var last_natural_scale: f32 = 0;

pub fn updateLayouts(store: *types.NodeStore) void {
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

    const missing_layout = hasMissingLayout(store, root);

    // If screen size changed, invalidate the entire layout tree so descendants recompute.
    const size_changed = last_screen_size.w != screen_w or last_screen_size.h != screen_h;
    const scale_changed = last_natural_scale != natural_scale;
    if (size_changed or scale_changed) {
        invalidateLayoutSubtree(store, root);
        store.markNodeChanged(root.id);
        last_screen_size = .{ .w = screen_w, .h = screen_h };
        last_natural_scale = natural_scale;
    }

    // Skip work when nothing is dirty and the screen size is stable.
    if (!size_changed and !scale_changed and !root.hasDirtySubtree() and !missing_layout) {
        return;
    }

    updateLayoutIfDirty(store, root, root_rect);
    applyAnchoredPlacement(store, root, root_rect);
}

fn invalidateLayoutSubtree(store: *types.NodeStore, node: *types.SolidNode) void {
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
    const spec = node.prepareClassSpec();
    if (spec.hidden) {
        node.layout.rect = types.Rect{}; // Zero rect
        return;
    }

    if (!node.needsLayoutUpdate()) {
        const child_rect = node.layout.rect orelse parent_rect;
        for (node.children.items) |child_id| {
            if (store.node(child_id)) |child| {
                updateLayoutIfDirty(store, child, child_rect);
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
    const spec = node.prepareClassSpec();
    const scale = dvui.windowNaturalScale();

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
                .full => rect.w = parent_rect.w,
                .pixels => |px| rect.w = px * scale,
            }
        } else if (spec.left != null and spec.right != null) {
            rect.w = @max(0.0, parent_rect.w - left_offset - right_offset);
        }

        if (spec.height) |h| {
            switch (h) {
                .full => rect.h = parent_rect.h,
                .pixels => |px| rect.h = px * scale,
            }
        } else if (spec.top != null and spec.bottom != null) {
            rect.h = @max(0.0, parent_rect.h - top_offset - bottom_offset);
        }

        if (node.kind == .text) {
            const measured = measure.measureTextCached(node);
            if (rect.w == 0) rect.w = measured.w;
            if (rect.h == 0) rect.h = measured.h;
        }
        if (rect.w == 0 or rect.h == 0) {
            const intrinsic = measure.measureNodeSize(store, node, .{ .w = parent_rect.w, .h = parent_rect.h });
            if (rect.w == 0) rect.w = intrinsic.w;
            if (rect.h == 0) rect.h = intrinsic.h;
        }

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
    } else {
        const is_inline = spec.is_inline or (node.kind == .element and (std.mem.eql(u8, node.tag, "button") or std.mem.eql(u8, node.tag, "span") or std.mem.eql(u8, node.tag, "a")));

        if (is_inline) {
            rect = types.Rect{
                .x = parent_rect.x,
                .y = parent_rect.y,
                .w = 0,
                .h = 0,
            };
        } else {
            rect = parent_rect;
        }

        const margin_left = sideValue(spec.margin.left) * scale;
        const margin_right = sideValue(spec.margin.right) * scale;
        const margin_top = sideValue(spec.margin.top) * scale;
        const margin_bottom = sideValue(spec.margin.bottom) * scale;

        rect.x += margin_left;
        rect.y += margin_top;
        rect.w = @max(0.0, rect.w - (margin_left + margin_right));
        rect.h = @max(0.0, rect.h - (margin_top + margin_bottom));

        if (spec.width) |w| {
            switch (w) {
                .full => rect.w = @max(0.0, parent_rect.w - (margin_left + margin_right)),
                .pixels => |px| rect.w = px * scale,
            }
        }
        if (spec.height) |h| {
            switch (h) {
                .full => rect.h = @max(0.0, parent_rect.h - (margin_top + margin_bottom)),
                .pixels => |px| rect.h = px * scale,
            }
        }

        if (node.kind == .text) {
            const measured = measure.measureTextCached(node);
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

    if (prev_rect) |prev| {
        if (prev.x != rect.x or prev.y != rect.y or prev.w != rect.w or prev.h != rect.h) {
            invalidateLayoutSubtree(store, node);
            node.layout.rect = rect;
            node.layout.version = store.currentVersion();
        }
    }

    const pad_left = sideValue(spec.padding.left) * scale;
    const pad_right = sideValue(spec.padding.right) * scale;
    const pad_top = sideValue(spec.padding.top) * scale;
    const pad_bottom = sideValue(spec.padding.bottom) * scale;

    var child_rect = rect;
    child_rect.x += pad_left;
    child_rect.y += pad_top;
    child_rect.w = @max(0.0, child_rect.w - (pad_left + pad_right));
    child_rect.h = @max(0.0, child_rect.h - (pad_top + pad_bottom));

    var layout_rect = child_rect;
    if (node.scroll.enabled) {
        var content_w = child_rect.w;
        var content_h = child_rect.h;
        if (node.scroll.canvas_width > 0) {
            content_w = @max(content_w, node.scroll.canvas_width);
        }
        if (node.scroll.canvas_height > 0) {
            content_h = @max(content_h, node.scroll.canvas_height);
        }
        layout_rect.w = content_w;
        layout_rect.h = content_h;
        layout_rect.x -= node.scroll.offset_x;
        layout_rect.y -= node.scroll.offset_y;
    }

    if (spec.is_flex) {
        flex.layoutFlexChildren(store, node, layout_rect, spec);
    } else {
        for (node.children.items) |child_id| {
            if (store.node(child_id)) |child| {
                updateLayoutIfDirty(store, child, layout_rect);
            }
        }
    }

    if (node.scroll.enabled) {
        updateScrollContentSize(store, node, child_rect);
    }
}

fn updateScrollContentSize(store: *types.NodeStore, node: *types.SolidNode, viewport: types.Rect) void {
    var content_w = viewport.w;
    var content_h = viewport.h;
    if (node.scroll.canvas_width > 0) {
        content_w = @max(content_w, node.scroll.canvas_width);
    }
    if (node.scroll.canvas_height > 0) {
        content_h = @max(content_h, node.scroll.canvas_height);
    }
    if (node.scroll.auto_canvas) {
        const auto_size = computeScrollAutoSize(store, node, viewport);
        content_w = @max(content_w, auto_size.w);
        content_h = @max(content_h, auto_size.h);
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
            const x = rect.x + node.scroll.offset_x;
            const y = rect.y + node.scroll.offset_y;
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
                    const offset_scale = dvui.windowNaturalScale();
                    const placement = dvui.AnchorPlacement{
                        .side = node.anchor_side,
                        .alignment = node.anchor_align,
                        .offset = node.anchor_offset * offset_scale,
                    };
                    const placed = dvui.placeAnchoredOnScreen(
                        dvui.Rect.Natural.cast(screen),
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

fn hasMissingLayout(store: *types.NodeStore, node: *types.SolidNode) bool {
    if (node.layout.rect == null) return true;
    for (node.children.items) |child_id| {
        if (store.node(child_id)) |child| {
            if (hasMissingLayout(store, child)) return true;
        }
    }
    return false;
}
