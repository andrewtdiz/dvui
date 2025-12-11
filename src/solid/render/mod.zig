const std = @import("std");

const dvui = @import("dvui");

const image_loader = @import("../../jsruntime/image_loader.zig");
const jsruntime = @import("../../jsruntime/mod.zig");
const jsc_bridge = @import("../bridge/jsc.zig");
const types = @import("../core/types.zig");
const events = @import("../events/mod.zig");
const layout = @import("../layout/mod.zig");
const style_apply = @import("../style/apply.zig");
const applyVisualToOptions = style_apply.applyVisualToOptions;
const applyClassSpecToVisual = style_apply.applyClassSpecToVisual;
const tailwind = @import("../style/tailwind.zig");
const direct = @import("direct.zig");
const applyTransformToOptions = direct.applyTransformToOptions;
const transformedRect = direct.transformedRect;
const drawTextDirect = direct.drawTextDirect;
const shouldDirectDraw = direct.shouldDirectDraw;
const paint_cache = @import("cache.zig");
const DirtyRegionTracker = paint_cache.DirtyRegionTracker;
const renderCachedOrDirectBackground = paint_cache.renderCachedOrDirectBackground;
const updatePaintCache = paint_cache.updatePaintCache;

const log = std.log.scoped(.solid_bridge);

var gizmo_override_rect: ?types.GizmoRect = null;
var gizmo_rect_pending: ?types.GizmoRect = null;
var logged_tree_dump: bool = false;

pub fn setGizmoRectOverride(rect: ?types.GizmoRect) void {
    gizmo_override_rect = rect;
}

pub fn takeGizmoRectUpdate() ?types.GizmoRect {
    const next = gizmo_rect_pending;
    gizmo_rect_pending = null;
    return next;
}

pub fn render(runtime: ?*jsruntime.JSRuntime, store: *types.NodeStore) bool {
    const root = store.node(0) orelse return false;

    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const scratch = arena.allocator();

    layout.updateLayouts(store);
    var dirty_tracker = DirtyRegionTracker.init(scratch);
    defer dirty_tracker.deinit();

    updatePaintCache(store, &dirty_tracker);

    // Temporary debug: dump the node tree once to verify state.
    if (!logged_tree_dump) {
        logged_tree_dump = true;
        var iter = store.nodes.iterator();
        while (iter.next()) |entry| {
            const node = entry.value_ptr;
            log.info(
                "node {d} kind={s} tag={s} class=\"{s}\" text_len={d} children={d} rect={?}",
                .{
                    node.id,
                    switch (node.kind) {
                        .root => "root",
                        .element => "elem",
                        .text => "text",
                        .slot => "slot",
                    },
                    node.tag,
                    node.class_name,
                    node.text.len,
                    node.children.items.len,
                    node.layout.rect,
                },
            );
        }
    }

    if (root.children.items.len == 0) {
        return false;
    }

    if (dirty_tracker.regions.items.len == 0) {
        const win = dvui.currentWindow();
        const screen_rect = types.Rect{
            .x = 0,
            .y = 0,
            .w = win.rect_pixels.w,
            .h = win.rect_pixels.h,
        };
        dirty_tracker.add(screen_rect);
    }

    for (root.children.items) |child_id| {
        renderNode(runtime, store, child_id, scratch, &dirty_tracker);
    }
    return true;
}

fn renderNode(
    runtime: ?*jsruntime.JSRuntime,
    store: *types.NodeStore,
    node_id: u32,
    allocator: std.mem.Allocator,
    tracker: *DirtyRegionTracker,
) void {
    const node = store.node(node_id) orelse return;
    switch (node.kind) {
        .root => {
            for (node.children.items) |child_id| {
                renderNode(runtime, store, child_id, allocator, tracker);
            }
            node.markRendered();
        },
        .slot => {
            for (node.children.items) |child_id| {
                renderNode(runtime, store, child_id, allocator, tracker);
            }
            node.markRendered();
        },
        .text => renderText(store, node),
        .element => renderElement(runtime, store, node_id, node, allocator, tracker),
    }
}

fn renderElement(
    runtime: ?*jsruntime.JSRuntime,
    store: *types.NodeStore,
    node_id: u32,
    node: *types.SolidNode,
    allocator: std.mem.Allocator,
    tracker: *DirtyRegionTracker,
) void {
    const class_spec = node.prepareClassSpec();
    applyClassSpecToVisual(node, &class_spec);

    if (node.isInteractive()) {
        renderInteractiveElement(runtime, store, node_id, node, allocator, class_spec, tracker);
    } else {
        renderNonInteractiveElement(runtime, store, node_id, node, allocator, class_spec, tracker);
    }
}

fn renderElementBody(
    runtime: ?*jsruntime.JSRuntime,
    store: *types.NodeStore,
    node_id: u32,
    node: *types.SolidNode,
    allocator: std.mem.Allocator,
    class_spec: tailwind.ClassSpec,
    tracker: *DirtyRegionTracker,
) void {
    if (std.mem.eql(u8, node.tag, "div")) {
        renderContainer(runtime, store, node, allocator, class_spec, tracker);
        node.markRendered();
        return;
    }
    if (std.mem.eql(u8, node.tag, "button")) {
        renderButton(runtime, store, node_id, node, allocator, class_spec, tracker);
        node.markRendered();
        return;
    }
    if (std.mem.eql(u8, node.tag, "input")) {
        renderInput(runtime, store, node_id, node, class_spec);
        node.markRendered();
        return;
    }
    if (std.mem.eql(u8, node.tag, "image")) {
        renderImage(runtime, store, node_id, node, class_spec, allocator, tracker);
        node.markRendered();
        return;
    }
    if (std.mem.eql(u8, node.tag, "gizmo")) {
        renderGizmo(runtime, store, node_id, node, class_spec);
        node.markRendered();
        return;
    }
    if (std.mem.eql(u8, node.tag, "p")) {
        renderParagraph(runtime, store, node_id, node, allocator, class_spec, null, tracker);
        node.markRendered();
        return;
    }
    if (std.mem.eql(u8, node.tag, "h1")) {
        renderParagraph(runtime, store, node_id, node, allocator, class_spec, .title, tracker);
        node.markRendered();
        return;
    }
    if (std.mem.eql(u8, node.tag, "h2")) {
        renderParagraph(runtime, store, node_id, node, allocator, class_spec, .title_1, tracker);
        node.markRendered();
        return;
    }
    if (std.mem.eql(u8, node.tag, "h3")) {
        renderParagraph(runtime, store, node_id, node, allocator, class_spec, .title_2, tracker);
        node.markRendered();
        return;
    }
    renderGeneric(runtime, store, node, allocator, tracker);
    node.markRendered();
}

fn renderParagraphDirect(
    runtime: ?*jsruntime.JSRuntime,
    store: *types.NodeStore,
    node_id: u32,
    node: *types.SolidNode,
    allocator: std.mem.Allocator,
    class_spec: tailwind.Spec,
    font_override: ?dvui.Options.FontStyle,
    rect: types.Rect,
    tracker: *DirtyRegionTracker,
) void {
    _ = node_id;
    const bounds = node.paint.painted_rect orelse transformedRect(node, rect) orelse rect;
    var text_buffer: std.ArrayList(u8) = .empty;
    defer text_buffer.deinit(allocator);

    // Draw paragraph background if present (cached geometry when available).
    renderCachedOrDirectBackground(node, rect, allocator, class_spec.background);

    collectText(allocator, store, node, &text_buffer);
    if (text_buffer.items.len > 0) {
        const trimmed = std.mem.trim(u8, text_buffer.items, " \n\r\t");
        if (trimmed.len > 0) {
            var options = dvui.Options{};
            style_apply.applyToOptions(&class_spec, &options);
            if (font_override) |style_name| {
                options.font_style = style_name;
            }
            // Text rendering honors scale/translation via the transformed bounds; rotation is handled for backgrounds only.
            drawTextDirect(bounds, trimmed, node.visual, options.font_style);
        }
    }

    for (node.children.items) |child_id| {
        renderNode(runtime, store, child_id, allocator, tracker);
    }
    node.markRendered();
}

fn renderInteractiveElement(
    runtime: ?*jsruntime.JSRuntime,
    store: *types.NodeStore,
    node_id: u32,
    node: *types.SolidNode,
    allocator: std.mem.Allocator,
    class_spec: tailwind.ClassSpec,
    tracker: *DirtyRegionTracker,
) void {
    // Placeholder: today interactive and non-interactive elements use the same DVUI path.
    // This wrapper marks the split point for routing to DVUI widgets to preserve focus/input.
    renderElementBody(runtime, store, node_id, node, allocator, class_spec, tracker);
}

fn renderNonInteractiveElement(
    runtime: ?*jsruntime.JSRuntime,
    store: *types.NodeStore,
    node_id: u32,
    node: *types.SolidNode,
    allocator: std.mem.Allocator,
    class_spec: tailwind.ClassSpec,
    tracker: *DirtyRegionTracker,
) void {
    if (shouldDirectDraw(node)) {
        renderNonInteractiveDirect(runtime, store, node_id, node, allocator, class_spec, tracker);
        return;
    }
    renderElementBody(runtime, store, node_id, node, allocator, class_spec, tracker);
}

fn renderContainer(
    runtime: ?*jsruntime.JSRuntime,
    store: *types.NodeStore,
    node: *types.SolidNode,
    allocator: std.mem.Allocator,
    class_spec: tailwind.ClassSpec,
    tracker: *DirtyRegionTracker,
) void {
    var options = dvui.Options{
        .name = "solid-div",
        .background = false,
        .expand = .none,
        .id_extra = nodeIdExtra(node.id),
    };
    style_apply.applyToOptions(&class_spec, &options);
    applyVisualToOptions(node, &options);
    applyTransformToOptions(node, &options);

    if (style_apply.isFlex(&class_spec)) {
        const flex_init = style_apply.buildFlexOptions(&class_spec);
        var flexbox_widget = dvui.flexbox(@src(), flex_init, options);
        defer flexbox_widget.deinit();
        renderFlexChildren(runtime, store, node, allocator, &class_spec, tracker);
    } else {
        var box = dvui.box(@src(), .{}, options);
        defer box.deinit();
        for (node.children.items) |child_id| {
            renderNode(runtime, store, child_id, allocator, tracker);
        }
    }
}

fn renderFlexChildren(
    runtime: ?*jsruntime.JSRuntime,
    store: *types.NodeStore,
    node: *types.SolidNode,
    allocator: std.mem.Allocator,
    class_spec: *const tailwind.Spec,
    tracker: *DirtyRegionTracker,
) void {
    const direction = style_apply.flexDirection(class_spec);
    const gap_main = switch (direction) {
        .horizontal => class_spec.gap_col,
        .vertical => class_spec.gap_row,
    } orelse 0;

    var child_index: usize = 0;
    for (node.children.items) |child_id| {
        if (gap_main > 0 and child_index > 0) {
            var margin = dvui.Rect{};
            switch (direction) {
                .horizontal => margin.x = gap_main,
                .vertical => margin.y = gap_main,
            }
            const _child_index: u32 = @intCast(child_index);
            var spacer = dvui.box(
                @src(),
                .{},
                .{ .margin = margin, .background = false, .name = "solid-gap", .id_extra = nodeIdExtra(node.id ^ _child_index) },
            );
            defer spacer.deinit();
            renderNode(runtime, store, child_id, allocator, tracker);
        } else {
            renderNode(runtime, store, child_id, allocator, tracker);
        }
        child_index += 1;
    }
}

fn renderGeneric(
    runtime: ?*jsruntime.JSRuntime,
    store: *types.NodeStore,
    node: *types.SolidNode,
    allocator: std.mem.Allocator,
    tracker: *DirtyRegionTracker,
) void {
    for (node.children.items) |child_id| {
        renderNode(runtime, store, child_id, allocator, tracker);
    }
}

fn renderNonInteractiveDirect(
    runtime: ?*jsruntime.JSRuntime,
    store: *types.NodeStore,
    node_id: u32,
    node: *types.SolidNode,
    allocator: std.mem.Allocator,
    class_spec: tailwind.ClassSpec,
    tracker: *DirtyRegionTracker,
) void {
    const rect = node.layout.rect orelse {
        renderElementBody(runtime, store, node_id, node, allocator, class_spec, tracker);
        return;
    };

    // const bounds = node.paint.painted_rect orelse transformedRect(node, rect) orelse rect;

    if (std.mem.eql(u8, node.tag, "div")) {
        renderCachedOrDirectBackground(node, rect, allocator, class_spec.background);
        for (node.children.items) |child_id| {
            renderNode(runtime, store, child_id, allocator, tracker);
        }
        node.markRendered();
        return;
    }

    if (std.mem.eql(u8, node.tag, "p")) {
        renderParagraphDirect(runtime, store, node_id, node, allocator, class_spec, null, rect, tracker);
        return;
    }
    if (std.mem.eql(u8, node.tag, "h1")) {
        renderParagraphDirect(runtime, store, node_id, node, allocator, class_spec, .title, rect, tracker);
        return;
    }
    if (std.mem.eql(u8, node.tag, "h2")) {
        renderParagraphDirect(runtime, store, node_id, node, allocator, class_spec, .title_1, rect, tracker);
        return;
    }
    if (std.mem.eql(u8, node.tag, "h3")) {
        renderParagraphDirect(runtime, store, node_id, node, allocator, class_spec, .title_2, rect, tracker);
        return;
    }

    // Fallback to DVUI path for tags without a direct draw handler.
    renderElementBody(runtime, store, node_id, node, allocator, class_spec, tracker);
}

fn renderGizmo(
    runtime: ?*jsruntime.JSRuntime,
    store: *types.NodeStore,
    node_id: u32,
    node: *types.SolidNode,
    class_spec: tailwind.Spec,
) void {
    _ = runtime;
    _ = store;
    _ = node_id;
    _ = class_spec;
    applyGizmoProp(node);
}

fn renderParagraph(
    runtime: ?*jsruntime.JSRuntime,
    store: *types.NodeStore,
    node_id: u32,
    node: *types.SolidNode,
    allocator: std.mem.Allocator,
    class_spec: tailwind.Spec,
    font_override: ?dvui.Options.FontStyle,
    tracker: *DirtyRegionTracker,
) void {
    var text_buffer: std.ArrayList(u8) = .empty;
    defer text_buffer.deinit(allocator);

    if (node.layout.rect) |rect| {
        renderCachedOrDirectBackground(node, rect, allocator, class_spec.background);
    }

    collectText(allocator, store, node, &text_buffer);
    if (text_buffer.items.len > 0) {
        const trimmed = std.mem.trim(u8, text_buffer.items, " \n\r\t");
        if (trimmed.len > 0) {
            var options = dvui.Options{
                .id_extra = nodeIdExtra(node_id),
            };
            style_apply.applyToOptions(&class_spec, &options);
            applyVisualToOptions(node, &options);
            applyTransformToOptions(node, &options);
            if (font_override) |style_name| {
                if (options.font_style == null) {
                    options.font_style = style_name;
                }
            }
            dvui.labelNoFmt(@src(), trimmed, .{}, options);
        }
    }

    renderChildElements(runtime, store, node, allocator, tracker);
}

fn applyGizmoProp(node: *types.SolidNode) void {
    const override = gizmo_override_rect;
    const attr_rect = node.gizmoRect();
    const has_new_attr = attr_rect != null and node.lastAppliedGizmoRectSerial() != node.gizmoRectSerial();

    const prop = if (has_new_attr)
        attr_rect.?
    else
        override orelse attr_rect orelse return;

    node.setGizmoRuntimeRect(prop);

    if (has_new_attr) {
        node.markGizmoRectApplied();
        gizmo_rect_pending = prop;
    }
}

fn renderText(store: *types.NodeStore, node: *types.SolidNode) void {
    const trimmed = std.mem.trim(u8, node.text, " \n\r\t");
    if (trimmed.len > 0) {
        var options = dvui.Options{ .id_extra = nodeIdExtra(node.id) };
        if (node.parent) |pid| {
            if (store.node(pid)) |parent| {
                const parent_spec = parent.prepareClassSpec();
                style_apply.applyToOptions(&parent_spec, &options);
            }
        }
        applyVisualToOptions(node, &options);
        applyTransformToOptions(node, &options);
        dvui.labelNoFmt(@src(), trimmed, .{}, options);
    }
    node.markRendered();
}

fn renderButton(
    runtime: ?*jsruntime.JSRuntime,
    store: *types.NodeStore,
    node_id: u32,
    node: *types.SolidNode,
    allocator: std.mem.Allocator,
    class_spec: tailwind.Spec,
    tracker: *DirtyRegionTracker,
) void {
    const text = buildText(store, node, allocator);
    const trimmed = std.mem.trim(u8, text, " \n\r\t");
    const caption = if (trimmed.len == 0) "Button" else trimmed;

    var options = dvui.Options{
        .id_extra = nodeIdExtra(node_id),
        .padding = dvui.Rect.all(6),
    };
    style_apply.applyToOptions(&class_spec, &options);
    applyVisualToOptions(node, &options);
    applyTransformToOptions(node, &options);

    const pressed = dvui.button(@src(), caption, .{}, options);
    if (pressed and node.hasListener("click")) {
        if (runtime) |rt| {
            // Use event ring buffer if available, otherwise fall back to callback
            if (rt.event_ring) |ring| {
                _ = ring.pushClick(node_id);
            } else {
                jsc_bridge.dispatchEvent(rt, node_id, "click", null) catch |err| {
                    log.err("Solid click dispatch failed: {s}", .{@errorName(err)});
                };
            }
        }
    }

    renderChildElements(runtime, store, node, allocator, tracker);
}

fn renderImage(
    runtime: ?*jsruntime.JSRuntime,
    store: *types.NodeStore,
    node_id: u32,
    node: *types.SolidNode,
    class_spec: tailwind.Spec,
    allocator: std.mem.Allocator,
    tracker: *DirtyRegionTracker,
) void {
    const src = node.imageSource();
    if (src.len == 0) {
        log.warn("Solid image node {d} missing src", .{node_id});
        return;
    }

    const resource = image_loader.load(src) catch |err| {
        log.err("Solid image load failed for {s}: {s}", .{ src, @errorName(err) });
        return;
    };

    var options = dvui.Options{
        .name = "solid-image",
        .id_extra = nodeIdExtra(node_id),
    };
    style_apply.applyToOptions(&class_spec, &options);
    applyVisualToOptions(node, &options);
    applyTransformToOptions(node, &options);

    const image_source = image_loader.imageSource(resource);
    _ = dvui.image(@src(), .{ .source = image_source }, options);

    renderChildElements(runtime, store, node, allocator, tracker);
}

fn renderInput(
    runtime: ?*jsruntime.JSRuntime,
    store: *types.NodeStore,
    node_id: u32,
    node: *types.SolidNode,
    class_spec: tailwind.Spec,
) void {
    _ = runtime;
    var options = dvui.Options{
        .name = "solid-input",
        .id_extra = nodeIdExtra(node_id),
        .background = false,
    };
    style_apply.applyToOptions(&class_spec, &options);
    applyVisualToOptions(node, &options);
    applyTransformToOptions(node, &options);

    var state = node.ensureInputState(store.allocator) catch |err| {
        log.err("Solid input state init failed for node {d}: {s}", .{ node_id, @errorName(err) });
        return;
    };

    state.syncBufferFromValue() catch |err| {
        log.err("Solid input buffer sync failed for node {d}: {s}", .{ node_id, @errorName(err) });
        return;
    };

    // UI text entry removed from Zig layer; track length based on buffered state only.
    state.text_len = state.buffer.len;
}

fn renderChildElements(
    runtime: ?*jsruntime.JSRuntime,
    store: *types.NodeStore,
    node: *types.SolidNode,
    allocator: std.mem.Allocator,
    tracker: *DirtyRegionTracker,
) void {
    for (node.children.items) |child_id| {
        const child = store.node(child_id) orelse continue;
        if (child.kind == .text) continue;
        renderNode(runtime, store, child_id, allocator, tracker);
    }
}

fn buildText(
    store: *types.NodeStore,
    node: *const types.SolidNode,
    allocator: std.mem.Allocator,
) []const u8 {
    var list: std.ArrayList(u8) = .empty;
    errdefer list.deinit(allocator);
    collectText(allocator, store, node, &list);
    if (list.items.len == 0) {
        list.deinit(allocator);
        return "";
    }
    const owned = list.toOwnedSlice(allocator) catch {
        list.deinit(allocator);
        return "";
    };
    return owned;
}

fn collectText(
    allocator: std.mem.Allocator,
    store: *types.NodeStore,
    node: *const types.SolidNode,
    into: *std.ArrayList(u8),
) void {
    switch (node.kind) {
        .text => {
            if (node.text.len == 0) return;
            _ = into.appendSlice(allocator, node.text) catch {};
        },
        else => {
            for (node.children.items) |child_id| {
                const child = store.node(child_id) orelse continue;
                collectText(allocator, store, child, into);
            }
        },
    }
}

fn nodeIdExtra(id: u32) usize {
    var hasher = std.hash.Wyhash.init(0);
    hasher.update(std.mem.asBytes(&id));
    return @intCast(hasher.final());
}
