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

    if (spec.is_flex) {
        flex.layoutFlexChildren(store, node, child_rect, spec);
    } else {
        for (node.children.items) |child_id| {
            if (store.node(child_id)) |child| {
                updateLayoutIfDirty(store, child, child_rect);
            }
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
