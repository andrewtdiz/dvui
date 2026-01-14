const std = @import("std");

const dvui = @import("dvui");

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
const packedColorToDvui = direct.packedColorToDvui;
const image_loader = @import("image_loader.zig");
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
var button_debug_count: usize = 0;
var button_text_error_log_count: usize = 0;
var paragraph_log_count: usize = 0;

fn physicalToDvuiRect(rect: types.Rect) dvui.Rect {
    const scale = dvui.windowNaturalScale();
    const inv_scale: f32 = if (scale != 0) 1.0 / scale else 1.0;
    return dvui.Rect{
        .x = rect.x * inv_scale,
        .y = rect.y * inv_scale,
        .w = rect.w * inv_scale,
        .h = rect.h * inv_scale,
    };
}

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
        } else {
            // Ensure a transparent background so downstream render paths always have a fill to work with.
            node.visual.background = .{ .value = 0x00000000 };
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

pub fn render(event_ring: ?*events.EventRing, store: *types.NodeStore) bool {
    const root = store.node(0) orelse return false;

    layout.updateLayouts(store);
    cancelDragIfMissing(event_ring, store);

    // Ensure visual props (especially backgrounds) are applied before caching/dirty decisions.
    syncVisualsFromClasses(store, root);

    var arena = std.heap.ArenaAllocator.init(store.allocator);
    defer arena.deinit();
    const scratch = arena.allocator();
    var dirty_tracker = DirtyRegionTracker.init(scratch);
    defer dirty_tracker.deinit();

    updatePaintCache(store, &dirty_tracker);

    // Temporary debug: dump the node tree once to verify state.
    if (!logged_tree_dump) {
        logged_tree_dump = true;
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

    renderChildrenOrdered(event_ring, store, root, scratch, &dirty_tracker, false);
    return true;
}

fn renderNode(
    event_ring: ?*events.EventRing,
    store: *types.NodeStore,
    node_id: u32,
    allocator: std.mem.Allocator,
    tracker: *DirtyRegionTracker,
) void {
    const node = store.node(node_id) orelse return;
    // log.info("renderNode node={d} kind={any}", .{ node_id, node.kind });
    switch (node.kind) {
        .root => {
            renderChildrenOrdered(event_ring, store, node, allocator, tracker, false);
            node.markRendered();
        },
        .slot => {
            renderChildrenOrdered(event_ring, store, node, allocator, tracker, false);
            node.markRendered();
        },
        .text => renderText(store, node),
        .element => renderElement(event_ring, store, node_id, node, allocator, tracker),
    }
}

fn renderElement(
    event_ring: ?*events.EventRing,
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
    }

    if (node.isInteractive()) {
        renderInteractiveElement(event_ring, store, node_id, node, allocator, class_spec, tracker);
    } else {
        renderNonInteractiveElement(event_ring, store, node_id, node, allocator, class_spec, tracker);
    }
}

fn renderElementBody(
    event_ring: ?*events.EventRing,
    store: *types.NodeStore,
    node_id: u32,
    node: *types.SolidNode,
    allocator: std.mem.Allocator,
    class_spec: tailwind.ClassSpec,
    tracker: *DirtyRegionTracker,
) void {
    if (std.mem.eql(u8, node.tag, "div")) {
        renderContainer(event_ring, store, node, allocator, class_spec, tracker);
        node.markRendered();
        return;
    }
    if (std.mem.eql(u8, node.tag, "button")) {
        renderButton(event_ring, store, node_id, node, allocator, class_spec, tracker);
        node.markRendered();
        return;
    }
    if (std.mem.eql(u8, node.tag, "input")) {
        renderInput(event_ring, store, node_id, node, class_spec);
        node.markRendered();
        return;
    }
    if (std.mem.eql(u8, node.tag, "image")) {
        renderImage(event_ring, store, node_id, node, class_spec, allocator, tracker);
        node.markRendered();
        return;
    }
    if (std.mem.eql(u8, node.tag, "gizmo")) {
        renderGizmo(event_ring, store, node_id, node, class_spec);
        node.markRendered();
        return;
    }
    if (std.mem.eql(u8, node.tag, "p")) {
        renderParagraph(event_ring, store, node_id, node, allocator, class_spec, null, tracker);
        node.markRendered();
        return;
    }
    if (std.mem.eql(u8, node.tag, "h1")) {
        renderParagraph(event_ring, store, node_id, node, allocator, class_spec, .title, tracker);
        node.markRendered();
        return;
    }
    if (std.mem.eql(u8, node.tag, "h2")) {
        renderParagraph(event_ring, store, node_id, node, allocator, class_spec, .title_1, tracker);
        node.markRendered();
        return;
    }
    if (std.mem.eql(u8, node.tag, "h3")) {
        renderParagraph(event_ring, store, node_id, node, allocator, class_spec, .title_2, tracker);
        node.markRendered();
        return;
    }
    renderGeneric(event_ring, store, node, allocator, tracker);
    node.markRendered();
}

fn renderParagraphDirect(
    event_ring: ?*events.EventRing,
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
            if (paragraph_log_count < 10) {
                paragraph_log_count += 1;
            }
            var options = dvui.Options{};
            style_apply.applyToOptions(&class_spec, &options);
            if (font_override) |style_name| {
                if (options.font_style == null) {
                    options.font_style = style_name;
                }
            }
            // Text rendering honors scale/translation via the transformed bounds; rotation is handled for backgrounds only.
            // Apply Tailwind padding and horizontal alignment manually for the direct draw path.
            const scale = dvui.windowNaturalScale();
            const pad_left = (class_spec.padding.left orelse 0) * scale;
            const pad_right = (class_spec.padding.right orelse 0) * scale;
            const pad_top = (class_spec.padding.top orelse 0) * scale;
            const pad_bottom = (class_spec.padding.bottom orelse 0) * scale;

            var text_rect = bounds;
            text_rect.x += pad_left;
            text_rect.y += pad_top;
            text_rect.w = @max(0.0, text_rect.w - (pad_left + pad_right));
            text_rect.h = @max(0.0, text_rect.h - (pad_top + pad_bottom));

            if (class_spec.text_align) |text_align| {
                const font = options.fontGet();
                const size_nat = font.textSize(trimmed);
                const text_w = size_nat.w * scale;
                switch (text_align) {
                    .center => text_rect.x += (text_rect.w - text_w) / 2.0,
                    .right => text_rect.x += (text_rect.w - text_w),
                    else => {},
                }
            }

            drawTextDirect(text_rect, trimmed, node.visual, options.font_style);
        }
    }

    // Paragraph already draws its text nodes; render non-text children (z-index ordered).
    renderChildrenOrdered(event_ring, store, node, allocator, tracker, true);
    node.markRendered();
}

fn renderInteractiveElement(
    event_ring: ?*events.EventRing,
    store: *types.NodeStore,
    node_id: u32,
    node: *types.SolidNode,
    allocator: std.mem.Allocator,
    class_spec: tailwind.ClassSpec,
    tracker: *DirtyRegionTracker,
) void {
    // Placeholder: today interactive and non-interactive elements use the same DVUI path.
    // This wrapper marks the split point for routing to DVUI widgets to preserve focus/input.
    renderElementBody(event_ring, store, node_id, node, allocator, class_spec, tracker);
}

fn renderNonInteractiveElement(
    event_ring: ?*events.EventRing,
    store: *types.NodeStore,
    node_id: u32,
    node: *types.SolidNode,
    allocator: std.mem.Allocator,
    class_spec: tailwind.ClassSpec,
    tracker: *DirtyRegionTracker,
) void {
    // Always draw non-interactive elements directly so backgrounds are guaranteed,
    // then recurse into children. This bypasses DVUI background handling.
    renderNonInteractiveDirect(event_ring, store, node_id, node, allocator, class_spec, tracker);
}

fn renderContainer(
    event_ring: ?*events.EventRing,
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
        // Draw background ourselves so containers always show their fill.
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
    if (node.layout.rect) |rect| {
        options.rect = physicalToDvuiRect(rect);
    }

    var box = dvui.box(@src(), .{}, options);
    defer box.deinit();

    if (node.scroll.enabled) {
        if (node.layout.rect) |rect| {
            handleScrollContainer(event_ring, store, node, rect);
        }
    }

    renderChildrenOrdered(event_ring, store, node, allocator, tracker, false);
    handlePointerDragEvents(event_ring, store, node, box.data());
    node.markRendered();
}

fn renderFlexChildren(
    event_ring: ?*events.EventRing,
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
            renderNode(event_ring, store, child_id, allocator, tracker);
        } else {
            renderNode(event_ring, store, child_id, allocator, tracker);
        }
        child_index += 1;
    }
}

fn renderGeneric(
    event_ring: ?*events.EventRing,
    store: *types.NodeStore,
    node: *types.SolidNode,
    allocator: std.mem.Allocator,
    tracker: *DirtyRegionTracker,
) void {
    renderChildrenOrdered(event_ring, store, node, allocator, tracker, false);
}

fn renderNonInteractiveDirect(
    event_ring: ?*events.EventRing,
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
        renderElementBody(event_ring, store, node_id, node, allocator, class_spec, tracker);
        return;
    };

    // const bounds = node.paint.painted_rect orelse transformedRect(node, rect) orelse rect;

    if (std.mem.eql(u8, node.tag, "div")) {
        renderCachedOrDirectBackground(node, rect, allocator, class_spec.background);
        renderChildrenOrdered(event_ring, store, node, allocator, tracker, false);
        node.markRendered();
        return;
    }

    if (std.mem.eql(u8, node.tag, "p")) {
        renderParagraphDirect(event_ring, store, node_id, node, allocator, class_spec, null, rect, tracker);
        return;
    }
    if (std.mem.eql(u8, node.tag, "h1")) {
        renderParagraphDirect(event_ring, store, node_id, node, allocator, class_spec, .title, rect, tracker);
        return;
    }
    if (std.mem.eql(u8, node.tag, "h2")) {
        renderParagraphDirect(event_ring, store, node_id, node, allocator, class_spec, .title_1, rect, tracker);
        return;
    }
    if (std.mem.eql(u8, node.tag, "h3")) {
        renderParagraphDirect(event_ring, store, node_id, node, allocator, class_spec, .title_2, rect, tracker);
        return;
    }

    // Fallback to DVUI path for tags without a direct draw handler.
    renderElementBody(event_ring, store, node_id, node, allocator, class_spec, tracker);
}

fn renderGizmo(
    event_ring: ?*events.EventRing,
    store: *types.NodeStore,
    node_id: u32,
    node: *types.SolidNode,
    class_spec: tailwind.Spec,
) void {
    _ = event_ring;
    _ = store;
    _ = node_id;
    _ = class_spec;
    applyGizmoProp(node);
}

fn renderParagraph(
    event_ring: ?*events.EventRing,
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

    renderChildElements(event_ring, store, node, allocator, tracker);
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
    event_ring: ?*events.EventRing,
    store: *types.NodeStore,
    node_id: u32,
    node: *types.SolidNode,
    allocator: std.mem.Allocator,
    class_spec: tailwind.Spec,
    tracker: *DirtyRegionTracker,
) void {
    // log.info("renderButton node={d} tag={s}", .{ node_id, node.tag });
    const text = buildText(store, node, allocator);
    const trimmed = std.mem.trim(u8, text, " \n\r\t");
    const has_caption = trimmed.len > 0;

    // Ensure we have a concrete rect; if layout is missing, compute a fallback using the parent rect/screen.
    var rect_opt = node.layout.rect;
    if (rect_opt == null) {
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

    var options = dvui.Options{
        .id_extra = nodeIdExtra(node_id),
        .padding = dvui.Rect{},
        // Respect layout positions exactly; DVUI's default button margin would offset the rect.
        .margin = dvui.Rect{},
    };
    style_apply.applyToOptions(&class_spec, &options);
    applyVisualToOptions(node, &options);
    applyTransformToOptions(node, &options);
    if (rect_opt) |rect| {
        options.rect = physicalToDvuiRect(rect);
    }

    // Use ButtonWidget directly instead of dvui.button() to ensure unique widget IDs.
    // The issue with dvui.button(@src(), ...) is that @src() returns the same source location
    // for every button rendered through this function, causing all buttons to share the same
    // DVUI widget ID. This breaks click detection and event dispatch.
    // By using ButtonWidget directly with id_extra set to a hash of node_id, each button
    // gets a unique ID even though they all originate from the same source location.
    var bw = dvui.ButtonWidget.init(@src(), .{ .draw_focus = false }, options);
    bw.install();
    bw.processEvents();
    bw.drawBackground();

    if (has_caption) {
        // Draw caption directly (avoid relying on LabelWidget sizing/refresh timing).
        // This fixes cases where button text doesn't appear until a later repaint.
        const content_rs = bw.data().contentRectScale();
        const text_style = options.strip().override(bw.style());
        const font = text_style.fontGet();
        const size_nat = font.textSize(trimmed);
        const text_w = size_nat.w * content_rs.s;
        const text_h = size_nat.h * content_rs.s;

        var text_rs = content_rs;
        if (text_w < text_rs.r.w) text_rs.r.x += (text_rs.r.w - text_w) * 0.5;
        if (text_h < text_rs.r.h) text_rs.r.y += (text_rs.r.h - text_h) * 0.5;
        text_rs.r.w = text_w;
        text_rs.r.h = text_h;

        const prev_clip = dvui.clip(content_rs.r);
        defer dvui.clipSet(prev_clip);
        dvui.renderText(.{
            .font = font,
            .text = trimmed,
            .rs = text_rs,
            .color = text_style.color(.text),
        }) catch |err| {
            if (button_text_error_log_count < 8) {
                button_text_error_log_count += 1;
                log.err("button caption renderText failed node={d}: {s}", .{ node_id, @errorName(err) });
            }
        };
    }

    bw.drawFocus();
    const pressed = bw.clicked();
    bw.deinit();

    if (pressed) {
        const has_listener = node.hasListener("click");
        log.info("button pressed node={d} has_listener={}", .{ node_id, has_listener });
        if (has_listener) {
            if (event_ring) |ring| {
                const ok = ring.pushClick(node_id);
                log.info("button dispatched via ring node={d} ok={}", .{ node_id, ok });
            }
        }
    }

    // log.info("renderButton node={d} render children", .{node_id});
    renderChildElements(event_ring, store, node, allocator, tracker);
}

fn renderImage(
    event_ring: ?*events.EventRing,
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

    renderChildElements(event_ring, store, node, allocator, tracker);
}

fn renderInput(
    event_ring: ?*events.EventRing,
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
        const natural = dvui.Rect.Natural.cast(rs.rectFromPhysical(rs.r));
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
    if (text_slice.len > 0) {
        direct.drawTextDirect(text_rect, text_slice, node.visual, wd.options.font_style);
    } else {
        const placeholder = std.mem.trim(u8, node.placeholder, " \n\r\t");
        if (placeholder.len > 0) {
            var placeholder_visual = node.visual;
            const placeholder_color = wd.options.color(.text).opacity(0.5);
            placeholder_visual.text_color = dvuiColorToPacked(placeholder_color);
            direct.drawTextDirect(text_rect, placeholder, placeholder_visual, wd.options.font_style);
        }
    }

    if (event_ring) |ring| {
        if (!prev_focused and focused_now and node.hasListener("focus")) {
            _ = ring.pushFocus(node_id);
        } else if (prev_focused and !focused_now and node.hasListener("blur")) {
            _ = ring.pushBlur(node_id);
        }

        if (text_changed and node.hasListener("input")) {
            const payload = state.currentText();
            _ = ring.pushInput(node_id, payload);
        }
    }
}

fn renderChildElements(
    event_ring: ?*events.EventRing,
    store: *types.NodeStore,
    node: *types.SolidNode,
    allocator: std.mem.Allocator,
    tracker: *DirtyRegionTracker,
) void {
    renderChildrenOrdered(event_ring, store, node, allocator, tracker, true);
}

fn renderChildrenOrdered(
    event_ring: ?*events.EventRing,
    store: *types.NodeStore,
    node: *types.SolidNode,
    allocator: std.mem.Allocator,
    tracker: *DirtyRegionTracker,
    skip_text: bool,
) void {
    if (node.children.items.len == 0) return;

    var prev_clip: ?dvui.Rect.Physical = null;
    if (node.visual.clip_children or node.scroll.enabled) {
        if (node.layout.rect) |rect| {
            const bounds = transformedRect(node, rect) orelse rect;
            const clip_rect = dvui.Rect.Physical{
                .x = bounds.x,
                .y = bounds.y,
                .w = bounds.w,
                .h = bounds.h,
            };
            prev_clip = dvui.clip(clip_rect);
        }
    }
    defer if (prev_clip) |prev| dvui.clipSet(prev);

    var any_z = false;
    for (node.children.items) |child_id| {
        const child = store.node(child_id) orelse continue;
        if (skip_text and child.kind == .text) continue;
        if (child.visual.z_index != 0) any_z = true;
    }

    if (!any_z) {
        for (node.children.items) |child_id| {
            const child = store.node(child_id) orelse continue;
            if (skip_text and child.kind == .text) continue;
            renderNode(event_ring, store, child_id, allocator, tracker);
        }
        return;
    }

    var ordered: std.ArrayList(u32) = .empty;
    defer ordered.deinit(allocator);

    for (node.children.items) |child_id| {
        const child = store.node(child_id) orelse continue;
        if (skip_text and child.kind == .text) continue;
        ordered.append(allocator, child_id) catch {};
    }

    // Stable insertion sort by z_index ascending so higher z renders last/on top.
    var i: usize = 1;
    while (i < ordered.items.len) : (i += 1) {
        const key_id = ordered.items[i];
        const key_node = store.node(key_id);
        const key_z: i16 = if (key_node) |kn| kn.visual.z_index else 0;

        var j: usize = i;
        while (j > 0) {
            const prev_id = ordered.items[j - 1];
            const prev_node = store.node(prev_id);
            const prev_z: i16 = if (prev_node) |pn| pn.visual.z_index else 0;
            if (prev_z <= key_z) break;
            ordered.items[j] = prev_id;
            j -= 1;
        }
        ordered.items[j] = key_id;
    }

    for (ordered.items) |child_id| {
        renderNode(event_ring, store, child_id, allocator, tracker);
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

fn scrollContentId(node_id: u32) dvui.Id {
    return dvui.Id.extendId(null, @src(), nodeIdExtra(node_id));
}

fn handleScrollContainer(
    event_ring: ?*events.EventRing,
    store: *types.NodeStore,
    node: *types.SolidNode,
    rect: types.Rect,
) void {
    const content_w = if (node.scroll.content_width > 0) node.scroll.content_width else rect.w;
    const content_h = if (node.scroll.content_height > 0) node.scroll.content_height else rect.h;

    var scroll_info = dvui.ScrollInfo{
        .vertical = if (content_h > rect.h) .auto else .none,
        .horizontal = if (content_w > rect.w) .auto else .none,
        .virtual_size = .{ .w = content_w, .h = content_h },
        .viewport = .{ .x = node.scroll.offset_x, .y = node.scroll.offset_y, .w = rect.w, .h = rect.h },
    };
    scroll_info.scrollToOffset(.vertical, scroll_info.viewport.y);
    scroll_info.scrollToOffset(.horizontal, scroll_info.viewport.x);

    const scroll_id = scrollContentId(node.id);
    const hit_rect = transformedRect(node, rect) orelse rect;
    const prev_x = node.scroll.offset_x;
    const prev_y = node.scroll.offset_y;

    _ = handleScrollInput(hit_rect, &scroll_info, scroll_id);

    node.scroll.offset_x = scroll_info.viewport.x;
    node.scroll.offset_y = scroll_info.viewport.y;

    if (scroll_info.viewport.x != prev_x or scroll_info.viewport.y != prev_y) {
        store.markNodeChanged(node.id);
        if (event_ring) |ring| {
            if (node.hasListener("scroll")) {
                var detail_buffer: [192]u8 = undefined;
                const detail: []const u8 = std.fmt.bufPrint(
                    &detail_buffer,
                    "{{\"x\":{},\"y\":{},\"viewportW\":{},\"viewportH\":{},\"contentW\":{},\"contentH\":{}}}",
                    .{
                        scroll_info.viewport.x,
                        scroll_info.viewport.y,
                        scroll_info.viewport.w,
                        scroll_info.viewport.h,
                        scroll_info.virtual_size.w,
                        scroll_info.virtual_size.h,
                    },
                ) catch "";
                _ = ring.pushScroll(node.id, detail);
            }
        }
    }
}

fn handleScrollInput(hit_rect: types.Rect, scroll_info: *dvui.ScrollInfo, scroll_id: dvui.Id) bool {
    const rect_phys = direct.rectToPhysical(hit_rect);
    const allow_vertical = scroll_info.scrollMax(.vertical) > 0;
    const allow_horizontal = scroll_info.scrollMax(.horizontal) > 0;
    var changed = false;

    for (dvui.events()) |*e| {
        if (!dvui.eventMatch(e, .{ .id = scroll_id, .r = rect_phys })) continue;

        switch (e.evt) {
            .mouse => |me| {
                switch (me.action) {
                    .wheel_y => |ticks| {
                        if (!allow_vertical) break;
                        scroll_info.scrollByOffset(.vertical, -ticks);
                        changed = true;
                        e.handled = true;
                        dvui.refresh(null, @src(), scroll_id);
                    },
                    .wheel_x => |ticks| {
                        if (!allow_horizontal) break;
                        scroll_info.scrollByOffset(.horizontal, ticks);
                        changed = true;
                        e.handled = true;
                        dvui.refresh(null, @src(), scroll_id);
                    },
                    .press => {
                        if (me.button.touch() and (allow_vertical or allow_horizontal)) {
                            const capture = dvui.CaptureMouse{
                                .id = scroll_id,
                                .rect = rect_phys,
                                .subwindow_id = dvui.subwindowCurrentId(),
                            };
                            dvui.captureMouseCustom(capture, e.num);
                            dvui.dragPreStart(me.p, .{});
                            e.handled = true;
                        }
                    },
                    .release => {
                        if (me.button.touch() and dvui.captured(scroll_id)) {
                            dvui.captureMouseCustom(null, e.num);
                            dvui.dragEnd();
                            e.handled = true;
                        }
                    },
                    .motion => {
                        if (dvui.captured(scroll_id)) {
                            if (dvui.dragging(me.p, null)) |dp| {
                                if (allow_horizontal) {
                                    scroll_info.scrollByOffset(.horizontal, -dp.x);
                                }
                                if (allow_vertical) {
                                    scroll_info.scrollByOffset(.vertical, -dp.y);
                                }
                                changed = true;
                                e.handled = true;
                                dvui.refresh(null, @src(), scroll_id);
                            }
                        }
                    },
                    else => {},
                }
            },
            else => {},
        }
    }

    return changed;
}

const PointerPayload = extern struct {
    x: f32,
    y: f32,
    button: u8,
    modifiers: u8,
    pad: u16,
};

const DragState = struct {
    active: bool = false,
    source_id: u32 = 0,
    button: u8 = 0,
    start: dvui.Point.Physical = .{},
    last: dvui.Point.Physical = .{},
    hover_target: ?u32 = null,
};

var drag_state: DragState = .{};

fn cancelDragIfMissing(event_ring: ?*events.EventRing, store: *types.NodeStore) void {
    if (!drag_state.active) return;
    if (store.node(drag_state.source_id) != null) return;
    if (drag_state.hover_target) |target_id| {
        dispatchDragLeave(event_ring, store, target_id, drag_state.last);
    }
    drag_state = .{};
    dvui.captureMouse(null, 0);
}

fn handlePointerDragEvents(
    event_ring: ?*events.EventRing,
    store: *types.NodeStore,
    node: *types.SolidNode,
    wd: *dvui.WidgetData,
) void {
    if (event_ring == null) return;
    const wants_pointer = node.hasListener("pointerdown") or node.hasListener("pointermove") or node.hasListener("pointerup") or node.hasListener("pointercancel");
    const wants_drag = node.hasListener("dragstart") or node.hasListener("drag") or node.hasListener("dragend");
    if (!wants_pointer and !wants_drag) return;

    const rect = wd.borderRectScale().r;
    for (dvui.events()) |*event| {
        if (!dvui.eventMatch(event, .{ .id = wd.id, .r = rect })) continue;
        switch (event.evt) {
            .mouse => |mouse| handlePointerMouse(event_ring, store, node, wd, event, mouse, wants_pointer, wants_drag),
            else => {},
        }
    }
}

fn handlePointerMouse(
    event_ring: ?*events.EventRing,
    store: *types.NodeStore,
    node: *types.SolidNode,
    wd: *dvui.WidgetData,
    event: *dvui.Event,
    mouse: dvui.Event.Mouse,
    wants_pointer: bool,
    wants_drag: bool,
) void {
    const is_source = drag_state.active and drag_state.source_id == node.id;
    switch (mouse.action) {
        .press => {
            if (!mouse.button.pointer()) return;
            var handled = false;
            if (wants_pointer and node.hasListener("pointerdown")) {
                pushPointerEvent(event_ring, .pointerdown, node.id, mouse);
                handled = true;
            }
            if (!drag_state.active and wants_drag) {
                startDrag(node.id, mouse, wd, event.num);
                if (node.hasListener("dragstart")) {
                    pushPointerEvent(event_ring, .dragstart, node.id, mouse);
                }
                updateHoverTarget(event_ring, store, mouse.p);
                handled = true;
            }
            if (handled) {
                event.handle(@src(), wd);
            }
        },
        .release => {
            if (!mouse.button.pointer()) return;
            var handled = false;
            if (wants_pointer and node.hasListener("pointerup")) {
                pushPointerEvent(event_ring, .pointerup, node.id, mouse);
                handled = true;
            }
            if (is_source) {
                updateHoverTarget(event_ring, store, mouse.p);
                if (drag_state.hover_target) |target_id| {
                    dispatchDrop(event_ring, store, target_id, mouse);
                }
                if (node.hasListener("dragend")) {
                    pushPointerEvent(event_ring, .dragend, node.id, mouse);
                }
                clearHover(event_ring, store, mouse.p);
                drag_state = .{};
                dvui.captureMouse(null, event.num);
                handled = true;
            }
            if (handled) {
                event.handle(@src(), wd);
            }
        },
        .motion => {
            var handled = false;
            if (is_source) {
                drag_state.last = mouse.p;
                if (node.hasListener("pointermove")) {
                    pushPointerEvent(event_ring, .pointermove, node.id, mouse);
                }
                if (node.hasListener("drag")) {
                    pushPointerEvent(event_ring, .drag, node.id, mouse);
                }
                updateHoverTarget(event_ring, store, mouse.p);
                handled = true;
            } else if (wants_pointer and node.hasListener("pointermove")) {
                pushPointerEvent(event_ring, .pointermove, node.id, mouse);
                handled = true;
            }
            if (handled) {
                event.handle(@src(), wd);
            }
        },
        else => {},
    }
}

fn startDrag(node_id: u32, mouse: dvui.Event.Mouse, wd: *dvui.WidgetData, event_num: u16) void {
    drag_state.active = true;
    drag_state.source_id = node_id;
    drag_state.start = mouse.p;
    drag_state.last = mouse.p;
    drag_state.button = mapButton(mouse.button);
    drag_state.hover_target = null;
    dvui.captureMouse(wd, event_num);
}

fn pushPointerEvent(
    event_ring: ?*events.EventRing,
    kind: events.EventKind,
    node_id: u32,
    mouse: dvui.Event.Mouse,
) void {
    if (event_ring) |ring| {
        const payload = pointerPayload(mouse);
        _ = ring.push(kind, node_id, std.mem.asBytes(&payload));
    }
}

fn pointerPayload(mouse: dvui.Event.Mouse) PointerPayload {
    return .{
        .x = mouse.p.x,
        .y = mouse.p.y,
        .button = mapButton(mouse.button),
        .modifiers = modMask(mouse.mod),
        .pad = 0,
    };
}

fn mapButton(button: dvui.enums.Button) u8 {
    return switch (button) {
        .left => 0,
        .middle => 1,
        .right => 2,
        .four => 3,
        .five => 4,
        else => 255,
    };
}

fn modMask(mods: dvui.enums.Mod) u8 {
    var mask: u8 = 0;
    if (mods.shift()) mask |= 1;
    if (mods.control()) mask |= 2;
    if (mods.alt()) mask |= 4;
    if (mods.command()) mask |= 8;
    return mask;
}

fn updateHoverTarget(event_ring: ?*events.EventRing, store: *types.NodeStore, point: dvui.Point.Physical) void {
    const target = findDropTarget(store, point, drag_state.source_id);
    if (target == drag_state.hover_target) return;
    if (drag_state.hover_target) |prev_id| {
        dispatchDragLeave(event_ring, store, prev_id, point);
    }
    if (target) |next_id| {
        dispatchDragEnter(event_ring, store, next_id, point);
    }
    drag_state.hover_target = target;
}

fn clearHover(event_ring: ?*events.EventRing, store: *types.NodeStore, point: dvui.Point.Physical) void {
    if (drag_state.hover_target) |target_id| {
        dispatchDragLeave(event_ring, store, target_id, point);
        drag_state.hover_target = null;
    }
}

fn dispatchDragEnter(event_ring: ?*events.EventRing, store: *types.NodeStore, target_id: u32, point: dvui.Point.Physical) void {
    if (event_ring == null) return;
    const target = store.node(target_id) orelse return;
    if (!target.hasListener("dragenter")) return;
    const mouse = dvui.Event.Mouse{
        .action = .position,
        .button = .none,
        .mod = .none,
        .p = point,
        .floating_win = dvui.subwindowCurrentId(),
    };
    pushPointerEvent(event_ring, .dragenter, target_id, mouse);
}

fn dispatchDragLeave(event_ring: ?*events.EventRing, store: *types.NodeStore, target_id: u32, point: dvui.Point.Physical) void {
    if (event_ring == null) return;
    const target = store.node(target_id) orelse return;
    if (!target.hasListener("dragleave")) return;
    const mouse = dvui.Event.Mouse{
        .action = .position,
        .button = .none,
        .mod = .none,
        .p = point,
        .floating_win = dvui.subwindowCurrentId(),
    };
    pushPointerEvent(event_ring, .dragleave, target_id, mouse);
}

fn dispatchDrop(event_ring: ?*events.EventRing, store: *types.NodeStore, target_id: u32, mouse: dvui.Event.Mouse) void {
    if (event_ring == null) return;
    const target = store.node(target_id) orelse return;
    if (!target.hasListener("drop")) return;
    pushPointerEvent(event_ring, .drop, target_id, mouse);
}

fn findDropTarget(store: *types.NodeStore, point: dvui.Point.Physical, source_id: u32) ?u32 {
    const root = store.node(0) orelse return null;
    var best_id: ?u32 = null;
    var best_z: i16 = std.math.minInt(i16);
    var best_order: u32 = 0;
    var order: u32 = 0;
    scanNode(store, root, point, source_id, &best_id, &best_z, &best_order, &order);
    return best_id;
}

fn scanNode(
    store: *types.NodeStore,
    node: *types.SolidNode,
    point: dvui.Point.Physical,
    source_id: u32,
    best_id: *?u32,
    best_z: *i16,
    best_order: *u32,
    order: *u32,
) void {
    if (node.kind == .element and node.id != source_id and std.mem.eql(u8, node.tag, "div")) {
        const wants_drop = node.hasListener("dragenter") or node.hasListener("dragleave") or node.hasListener("drop");
        if (wants_drop) {
            const spec = node.prepareClassSpec();
            if (!spec.hidden) {
                if (node.layout.rect) |rect| {
                    if (rectContains(rect, point)) {
                        order.* += 1;
                        const z = node.visual.z_index;
                        if (z > best_z.* or (z == best_z.* and order.* >= best_order.*)) {
                            best_z.* = z;
                            best_order.* = order.*;
                            best_id.* = node.id;
                        }
                    }
                }
            }
        }
    }

    for (node.children.items) |child_id| {
        if (store.node(child_id)) |child| {
            scanNode(store, child, point, source_id, best_id, best_z, best_order, order);
        }
    }
}

fn rectContains(rect: types.Rect, point: dvui.Point.Physical) bool {
    return point.x >= rect.x and point.x <= (rect.x + rect.w) and point.y >= rect.y and point.y <= (rect.y + rect.h);
}
