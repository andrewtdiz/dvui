const std = @import("std");

const dvui = @import("dvui");
const image_loader = @import("jsruntime").image_loader;
const jsruntime = @import("jsruntime");

const jsc_bridge = @import("../bridge/jsc.zig");
const types = @import("../core/types.zig");
const events = @import("../events/mod.zig");
const layout = @import("../layout/mod.zig");
const style_apply = @import("../style/apply.zig");
const applyVisualToOptions = style_apply.applyVisualToOptions;
const applyClassSpecToVisual = style_apply.applyClassSpecToVisual;
const tailwind = @import("../style/tailwind.zig");
const direct = @import("direct.zig");
const dvuiColorToPacked = direct.dvuiColorToPacked;
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
var logged_render_state: bool = false;
var logged_button_render: bool = false;

fn syncVisualsFromClasses(store: *types.NodeStore, node: *types.SolidNode) void {
    const class_spec = node.prepareClassSpec();

    // Skip hidden nodes entirely
    if (class_spec.hidden) {
        return;
    }

    const prev_bg = node.visual.background;
    applyClassSpecToVisual(node, &class_spec);
    if (node.visual.background == null) {
        if (class_spec.background) |bg| {
            node.visual.background = dvuiColorToPacked(bg);
        }
    }
    const bg_changed = blk: {
        if (node.visual.background) |bg| {
            if (prev_bg) |prev| break :blk bg.value != prev.value;
            break :blk true;
        } else {
            break :blk prev_bg != null;
        }
    };
    if (bg_changed) {
        node.invalidatePaint();
    }
    for (node.children.items) |child_id| {
        if (store.node(child_id)) |child| {
            syncVisualsFromClasses(store, child);
        }
    }
}

fn hasPaintDirtySubtree(store: *types.NodeStore, node: *types.SolidNode) bool {
    if (node.paint.paint_dirty) return true;
    for (node.children.items) |child_id| {
        if (store.node(child_id)) |child| {
            if (hasPaintDirtySubtree(store, child)) return true;
        }
    }
    return false;
}

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

    layout.updateLayouts(store);

    // Ensure visual props (especially backgrounds) are applied before caching/dirty decisions.
    syncVisualsFromClasses(store, root);

    // If nothing is dirty, skip layout/paint/caching work.
    if (!root.hasDirtySubtree() and !hasPaintDirtySubtree(store, root)) {
        return true;
    }

    var arena = std.heap.ArenaAllocator.init(store.allocator);
    defer arena.deinit();
    const scratch = arena.allocator();
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
                "node {d} kind={s} tag={s} class=\"{s}\" text_len={d} children={d} rect={?} bg={?}",
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
                    node.visual.background,
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

    // Skip rendering if element has 'hidden' class
    if (class_spec.hidden) {
        node.markRendered();
        return;
    }

    applyClassSpecToVisual(node, &class_spec);
    // DVUI path fallback: if class provided a background but visual is still null, copy it.
    if (node.visual.background == null) {
        if (class_spec.background) |bg| {
            node.visual.background = dvuiColorToPacked(bg);
        }
    }
    if (!logged_render_state) {
        logged_render_state = true;
        log.info(
            "render node {d} tag={s} class=\"{s}\" spec_bg={any} visual_bg={any} rect={any}",
            .{ node.id, node.tag, node.class_name, class_spec.background, node.visual.background, node.layout.rect },
        );
    }

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
        const child = store.node(child_id) orelse continue;
        if (child.kind == .text) continue; // already drawn as part of the paragraph
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
    // Always draw non-interactive elements directly so backgrounds are guaranteed,
    // then recurse into children. This bypasses DVUI background handling.
    renderNonInteractiveDirect(runtime, store, node_id, node, allocator, class_spec, tracker);
}

fn renderContainer(
    runtime: ?*jsruntime.JSRuntime,
    store: *types.NodeStore,
    node: *types.SolidNode,
    allocator: std.mem.Allocator,
    class_spec: tailwind.ClassSpec,
    tracker: *DirtyRegionTracker,
) void {
    // Ensure a background color is present for container nodes.
    if (class_spec.background) |bg| {
        if (node.visual.background == null) {
            node.visual.background = dvuiColorToPacked(bg);
        }
    }

    if (node.layout.rect) |rect| {
        // Draw background ourselves so flex containers still show their fill even when they host interactive children.
        renderCachedOrDirectBackground(node, rect, allocator, class_spec.background);
    }

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
    var rect_opt = node.layout.rect;
    if (rect_opt == null) {
        // Compute a fallback layout on-demand using the parent's rect (or screen) so backgrounds still render.
        const parent_rect = blk: {
            if (node.parent) |pid| {
                if (store.node(pid)) |parent| {
                    if (parent.layout.rect) |pr| break :blk pr;
                }
            }
            const win = dvui.currentWindow();
            break :blk types.Rect{
                .x = 0,
                .y = 0,
                .w = win.rect_pixels.w,
                .h = win.rect_pixels.h,
            };
        };
        layout.computeNodeLayout(store, node, parent_rect);
        rect_opt = node.layout.rect;
    }

    const rect = rect_opt orelse {
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
    if (!logged_button_render) {
        logged_button_render = true;
        log.info(
            "renderButton node={d} caption_len={d} caption=\"{s}\" rect={any} class=\"{s}\"",
            .{ node_id, caption.len, caption, node.layout.rect, node.class_name },
        );
    }

    var options = dvui.Options{
        .id_extra = nodeIdExtra(node_id),
        .padding = dvui.Rect.all(6),
    };
    style_apply.applyToOptions(&class_spec, &options);
    applyVisualToOptions(node, &options);
    applyTransformToOptions(node, &options);

    // Use ButtonWidget directly instead of dvui.button() to ensure unique widget IDs.
    // The issue with dvui.button(@src(), ...) is that @src() returns the same source location
    // for every button rendered through this function, causing all buttons to share the same
    // DVUI widget ID. This breaks click detection and event dispatch.
    // By using ButtonWidget directly with id_extra set to a hash of node_id, each button
    // gets a unique ID even though they all originate from the same source location.
    var bw = dvui.ButtonWidget.init(@src(), .{}, options);
    bw.install();
    bw.processEvents();
    bw.drawBackground();

    // Draw caption with a different id_extra to avoid label ID collision
    const label_id_extra = nodeIdExtra(node_id) +% 0x12345678;
    dvui.labelNoFmt(
        @src(),
        caption,
        .{ .align_x = 0.5, .align_y = 0.5 },
        options.strip().override(bw.style()).override(.{
            .gravity_x = 0.5,
            .gravity_y = 0.5,
            .id_extra = label_id_extra,
        }),
    );

    bw.drawFocus();
    const pressed = bw.clicked();
    bw.deinit();

    if (pressed) {
        log.info("button pressed node={d} has_listener={}", .{ node_id, node.hasListener("click") });
        if (node.hasListener("click")) {
            if (runtime) |rt| {
                // Use event ring buffer if available, otherwise fall back to callback
                if (rt.event_ring) |ring| {
                    const ok = ring.pushClick(node_id);
                    log.info("button dispatched via ring node={d} ok={}", .{ node_id, ok });
                } else {
                    jsc_bridge.dispatchEvent(rt, node_id, "click", null) catch |err| {
                        log.err("Solid click dispatch failed: {s}", .{@errorName(err)});
                    };
                    log.info("button dispatched via callback node={d}", .{node_id});
                }
            } else {
                log.info("button pressed but runtime missing node={d}", .{node_id});
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
    var options = dvui.Options{
        .name = "solid-input",
        .id_extra = nodeIdExtra(node_id),
        .background = true,
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
    // Preserve the actual text length; buffer may retain extra capacity for future edits.
    if (state.text_len > state.buffer.len) {
        state.text_len = state.buffer.len;
    }
    if (state.buffer.len > state.text_len) {
        state.buffer[state.text_len] = 0;
    }

    var box = dvui.BoxWidget.init(@src(), .{}, options);
    box.install();
    defer box.deinit();

    const wd = box.data();
    dvui.tabIndexSet(wd.id, wd.options.tab_index);

    var hovered = false;
    _ = dvui.clickedEx(wd, .{ .hovered = &hovered, .hover_cursor = .ibeam });

    const prev_focused = state.focused;
    const focused_now = dvui.focusedWidgetId() == wd.id;
    state.focused = focused_now;

    if (focused_now) {
        const rs = wd.contentRectScale();
        const natural = rs.rectFromPhysical(rs.r);
        dvui.wantTextInput(natural);
    }

    var text_changed = false;

    for (dvui.events()) |*e| {
        if (!dvui.eventMatch(e, .{ .id = wd.id, .r = wd.borderRectScale().r })) continue;

        switch (e.evt) {
            .text => |te| {
                if (te.txt.len == 0) break;
                const new_len = state.text_len + te.txt.len;
                state.ensureCapacity(new_len + 1) catch |err| {
                    log.err("Solid input ensureCapacity failed for node {d}: {s}", .{ node_id, @errorName(err) });
                    break;
                };
                @memcpy(state.buffer[state.text_len .. state.text_len + te.txt.len], te.txt);
                if (state.buffer.len > new_len) {
                    state.buffer[new_len] = 0;
                }
                state.text_len = new_len;
                state.updateFromText(state.buffer[0..new_len]) catch |err| {
                    log.err("Solid input update failed for node {d}: {s}", .{ node_id, @errorName(err) });
                    break;
                };
                store.markNodeChanged(node_id);
                text_changed = true;
                e.handle(@src(), wd);
            },
            .key => |ke| {
                if (ke.action != .down and ke.action != .repeat) break;
                switch (ke.code) {
                    .backspace => {
                        if (state.text_len == 0) break;
                        const new_len = dvui.findUtf8Start(state.buffer[0..state.text_len], state.text_len);
                        if (state.buffer.len > new_len) {
                            state.buffer[new_len] = 0;
                        }
                        state.text_len = new_len;
                        state.updateFromText(state.buffer[0..new_len]) catch |err| {
                            log.err("Solid input backspace update failed for node {d}: {s}", .{ node_id, @errorName(err) });
                            break;
                        };
                        store.markNodeChanged(node_id);
                        text_changed = true;
                        e.handle(@src(), wd);
                    },
                    else => {},
                }
            },
            else => {},
        }
    }

    box.drawBackground();
    const rs = wd.contentRectScale();
    const text_rect_nat = rs.rectFromPhysical(rs.r);
    const text_rect = types.Rect{
        .x = text_rect_nat.x,
        .y = text_rect_nat.y,
        .w = text_rect_nat.w,
        .h = text_rect_nat.h,
    };
    const text_slice = state.currentText();
    direct.drawTextDirect(text_rect, text_slice, node.visual, wd.options.font_style);

    if (runtime) |rt| {
        if (!prev_focused and focused_now and node.hasListener("focus")) {
            if (rt.event_ring) |ring| {
                _ = ring.pushFocus(node_id);
            } else {
                jsc_bridge.dispatchEvent(rt, node_id, "focus", null) catch |err| {
                    log.err("Solid focus dispatch failed for node {d}: {s}", .{ node_id, @errorName(err) });
                };
            }
        } else if (prev_focused and !focused_now and node.hasListener("blur")) {
            if (rt.event_ring) |ring| {
                _ = ring.pushBlur(node_id);
            } else {
                jsc_bridge.dispatchEvent(rt, node_id, "blur", null) catch |err| {
                    log.err("Solid blur dispatch failed for node {d}: {s}", .{ node_id, @errorName(err) });
                };
            }
        }

        if (text_changed and node.hasListener("input")) {
            const payload = state.currentText();
            if (rt.event_ring) |ring| {
                _ = ring.pushInput(node_id, payload);
            } else {
                jsc_bridge.dispatchEvent(rt, node_id, "input", payload) catch |err| {
                    log.err("Solid input dispatch failed for node {d}: {s}", .{ node_id, @errorName(err) });
                };
            }
        }
    }
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
