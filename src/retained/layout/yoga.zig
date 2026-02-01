const std = @import("std");
const dvui = @import("dvui");

const yoga = @import("yoga-zig");

const types = @import("../core/types.zig");
const tailwind = @import("../style/tailwind.zig");
const measure = @import("measure.zig");

pub fn layoutFlexChildren(store: *types.NodeStore, node: *types.SolidNode, area: types.Rect, spec: tailwind.Spec) void {
    const base_scale = dvui.windowNaturalScale();
    const scale = if (node.layout.layout_scale != 0) node.layout.layout_scale else base_scale;
    const lifo = dvui.currentWindow().lifo();
    const root = yoga.Node.new();
    defer root.freeRecursive();

    root.setDisplay(.Flex);
    root.setFlexDirection(mapDirection(spec.direction orelse .horizontal));
    root.setJustifyContent(mapJustify(spec.justify orelse .start));
    root.setAlignItems(mapAlignItems(spec.align_items orelse .start));
    root.setAlignContent(mapAlignContent(spec.align_content orelse .start));
    root.setWidth(area.w);
    root.setHeight(area.h);

    const gap_col = (spec.gap_col orelse 0) * scale;
    const gap_row = (spec.gap_row orelse 0) * scale;
    if (gap_col != 0) root.setGap(.Column, gap_col);
    if (gap_row != 0) root.setGap(.Row, gap_row);

    var flex_child_ids: std.ArrayListUnmanaged(u32) = .{};
    defer flex_child_ids.deinit(lifo);

    var absolute_child_ids: std.ArrayListUnmanaged(u32) = .{};
    defer absolute_child_ids.deinit(lifo);

    const available = types.Size{ .w = area.w, .h = area.h };

    for (node.children.items) |child_id| {
        const child = store.node(child_id) orelse continue;
        const child_spec = child.prepareClassSpec();
        const child_scale = scale * (child_spec.scale orelse 1.0);
        child.layout.layout_scale = child_scale;

        if (child_spec.hidden) {
            child.layout.rect = types.Rect{};
            continue;
        }

        if (child_spec.position != null and child_spec.position.? == .absolute) {
            absolute_child_ids.append(lifo, child_id) catch {};
            continue;
        }

        const size = measure.measureNodeSize(store, child, available);
        if (child.kind == .text and size.w == 0 and size.h == 0) {
            child.layout.rect = types.Rect{};
            continue;
        }

        const yoga_child = yoga.Node.new();
        yoga_child.setDisplay(.Flex);
        yoga_child.setWidth(size.w);
        yoga_child.setHeight(size.h);
        root.insertChild(yoga_child, root.getChildCount());
        flex_child_ids.append(lifo, child_id) catch {};
    }

    root.calculateLayout(area.w, area.h, null);

    for (flex_child_ids.items, 0..) |child_id, idx| {
        const child = store.node(child_id) orelse continue;
        const yoga_child = root.getChild(idx);
        const child_rect = types.Rect{
            .x = area.x + yoga_child.getComputedLeft(),
            .y = area.y + yoga_child.getComputedTop(),
            .w = yoga_child.getComputedWidth(),
            .h = yoga_child.getComputedHeight(),
        };
        computeNodeLayout(store, child, child_rect);
    }

    for (absolute_child_ids.items) |child_id| {
        const child = store.node(child_id) orelse continue;
        computeNodeLayout(store, child, area);
    }
}

fn computeNodeLayout(store: *types.NodeStore, node: *types.SolidNode, parent_rect: types.Rect) void {
    const layout = @import("mod.zig");
    layout.computeNodeLayout(store, node, parent_rect);
}

fn mapDirection(dir: dvui.enums.Direction) yoga.enums.FlexDirection {
    return switch (dir) {
        .horizontal => .Row,
        .vertical => .Column,
    };
}

fn mapJustify(justify: dvui.FlexBoxWidget.ContentPosition) yoga.enums.Justify {
    return switch (justify) {
        .start => .FlexStart,
        .center => .Center,
        .end => .FlexEnd,
        .between => .SpaceBetween,
        .around => .SpaceAround,
    };
}

fn mapAlignItems(alignItems: dvui.FlexBoxWidget.AlignItems) yoga.enums.Align {
    return switch (alignItems) {
        .start => .FlexStart,
        .center => .Center,
        .end => .FlexEnd,
    };
}

fn mapAlignContent(alignContent: dvui.FlexBoxWidget.AlignContent) yoga.enums.Align {
    return switch (alignContent) {
        .start => .FlexStart,
        .center => .Center,
        .end => .FlexEnd,
    };
}
