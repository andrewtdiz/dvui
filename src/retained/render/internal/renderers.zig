const std = @import("std");
const dvui = @import("dvui");

const types = @import("../../core/types.zig");
const events = @import("../../events/mod.zig");
const layout = @import("../../layout/mod.zig");
const text_wrap = @import("../../layout/text_wrap.zig");
const style_apply = @import("../../style/apply.zig");
const tailwind = @import("../../style/tailwind.zig");
const direct = @import("../direct.zig");
const transitions = @import("../transitions.zig");
const image_loader = @import("../image_loader.zig");
const icon_registry = @import("../icon_registry.zig");
const paint_cache = @import("../cache.zig");
const drag_drop = @import("../../events/drag_drop.zig");
const focus = @import("../../events/focus.zig");

const interaction = @import("interaction.zig");
const state = @import("state.zig");
const visual_sync = @import("visual_sync.zig");

const applyVisualToOptions = style_apply.applyVisualToOptions;
const applyVisualPropsToOptions = style_apply.applyVisualPropsToOptions;
const applyClassSpecToVisual = style_apply.applyClassSpecToVisual;

const dvuiColorToPacked = direct.dvuiColorToPacked;
const applyTransformToOptions = direct.applyTransformToOptions;
const transformedRect = direct.transformedRect;
const drawTextDirect = direct.drawTextDirect;
const drawTriangleDirect = direct.drawTriangleDirect;
const shouldDirectDraw = direct.shouldDirectDraw;
const packedColorToDvui = direct.packedColorToDvui;

const DirtyRegionTracker = paint_cache.DirtyRegionTracker;
const renderCachedOrDirectBackground = paint_cache.renderCachedOrDirectBackground;

const nodeIdExtra = state.nodeIdExtra;
const physicalToDvuiRect = state.physicalToDvuiRect;
const scrollContentId = state.scrollContentId;
const isPortalNode = state.isPortalNode;
const sortOrderedNodes = state.sortOrderedNodes;
const OrderedNode = state.OrderedNode;
const allowFocusRegistration = state.allowFocusRegistration;

const applyLayoutScaleToOptions = visual_sync.applyLayoutScaleToOptions;
const applyCursorHint = visual_sync.applyCursorHint;
const nodeHasAccessibilityProps = visual_sync.nodeHasAccessibilityProps;
const applyAccessibilityOptions = visual_sync.applyAccessibilityOptions;
const applyAccessibilityState = visual_sync.applyAccessibilityState;

const clickedExTopmost = interaction.clickedExTopmost;
const clickedTopmost = interaction.clickedTopmost;
const handleScrollInput = interaction.handleScrollInput;
const renderScrollBars = interaction.renderScrollBars;

const log = std.log.scoped(.solid_bridge);

fn applyBorderColorToOptions(node: *const types.SolidNode, visual: types.VisualProps, options: *dvui.Options) void {
    if (!node.transition_state.enabled) return;
    if (!node.transition_state.active_props.colors) return;
    const border_packed = transitions.effectiveBorderColor(node);
    options.color_border = packedColorToDvui(border_packed, visual.opacity);
}

pub fn renderNode(
    event_ring: ?*events.EventRing,
    store: *types.NodeStore,
    node_id: u32,
    allocator: std.mem.Allocator,
    tracker: *DirtyRegionTracker,
) void {
    const node = store.node(node_id) orelse return;
    if (state.render_layer == .base and isPortalNode(node)) {
        return;
    }
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
    var class_spec = node.prepareClassSpec();
    tailwind.applyHover(&class_spec, node.hovered);

    // Skip rendering if element has 'hidden' class
    if (class_spec.hidden) {
        node.markRendered();
        return;
    }

    if (state.input_enabled_state) {
        applyCursorHint(node, &class_spec);
    }
    applyClassSpecToVisual(node, &class_spec);
    // DVUI path fallback: if class provided a background but visual is still null, copy it.
    if (node.visual.background == null) {
        if (class_spec.background) |bg| {
            node.visual.background = dvuiColorToPacked(bg);
        }
    }
    if (!state.logged_render_state) {
        state.logged_render_state = true;
    }

    if (node.isInteractive() or nodeHasAccessibilityProps(node)) {
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
    if (node.scroll.enabled) {
        renderScrollFrame(event_ring, store, node_id, node, allocator, class_spec, tracker);
        return;
    }
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
    if (std.mem.eql(u8, node.tag, "slider")) {
        renderSlider(event_ring, store, node_id, node, class_spec);
        node.markRendered();
        return;
    }
    if (std.mem.eql(u8, node.tag, "image")) {
        renderImage(event_ring, store, node_id, node, class_spec, allocator, tracker);
        node.markRendered();
        return;
    }
    if (std.mem.eql(u8, node.tag, "icon")) {
        renderIcon(event_ring, store, node_id, node, class_spec, allocator, tracker);
        node.markRendered();
        return;
    }
    if (std.mem.eql(u8, node.tag, "gizmo")) {
        renderGizmo(event_ring, store, node_id, node, class_spec);
        node.markRendered();
        return;
    }
    if (std.mem.eql(u8, node.tag, "triangle")) {
        renderTriangle(event_ring, store, node, allocator, class_spec, tracker);
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

fn renderScrollFrame(
    event_ring: ?*events.EventRing,
    store: *types.NodeStore,
    node_id: u32,
    node: *types.SolidNode,
    allocator: std.mem.Allocator,
    class_spec: tailwind.ClassSpec,
    tracker: *DirtyRegionTracker,
) void {
    _ = node_id;
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
    const rect = rect_opt orelse return;

    if (class_spec.background) |bg| {
        if (node.visual.background == null) {
            node.visual.background = dvuiColorToPacked(bg);
        }
    }
    renderCachedOrDirectBackground(node, rect, allocator, class_spec.background);

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

    _ = handleScrollInput(node, hit_rect, &scroll_info, scroll_id);

    renderChildrenOrdered(event_ring, store, node, allocator, tracker, false);

    _ = renderScrollBars(node, rect, &scroll_info, scroll_id);

    if (scroll_info.viewport.x != prev_x or scroll_info.viewport.y != prev_y) {
        node.scroll.offset_x = scroll_info.viewport.x;
        node.scroll.offset_y = scroll_info.viewport.y;
        layout.invalidateLayoutSubtree(store, node);
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
            if (state.paragraph_log_count < 10) {
                state.paragraph_log_count += 1;
            }
            // Text rendering honors scale/translation via the transformed bounds; rotation is handled for backgrounds only.
            // Apply Tailwind padding and horizontal alignment manually for the direct draw path.
            const natural_scale = dvui.windowNaturalScale();
            const layout_scale = if (node.layout.layout_scale != 0) node.layout.layout_scale else natural_scale;
            const pad_left = (class_spec.padding.left orelse 0) * layout_scale;
            const pad_right = (class_spec.padding.right orelse 0) * layout_scale;
            const pad_top = (class_spec.padding.top orelse 0) * layout_scale;
            const pad_bottom = (class_spec.padding.bottom orelse 0) * layout_scale;

            var text_rect = bounds;
            text_rect.x += pad_left;
            text_rect.y += pad_top;
            text_rect.w = @max(0.0, text_rect.w - (pad_left + pad_right));
            text_rect.h = @max(0.0, text_rect.h - (pad_top + pad_bottom));

            var options = dvui.Options{};
            style_apply.applyToOptions(&class_spec, &options);
            if (font_override) |style_name| {
                options.font_style = style_name;
            }
            style_apply.resolveFont(&class_spec, &options);
            const base_font = options.fontGet();
            const font_scale = if (natural_scale != 0) layout_scale / natural_scale else 1.0;
            const draw_font = if (font_scale != 1.0) base_font.resize(base_font.size * font_scale) else base_font;
            text_wrap.computeLineBreaks(
                store.allocator,
                &node.layout.text_layout,
                trimmed,
                base_font,
                text_rect.w,
                layout_scale,
                class_spec.text_wrap,
                class_spec.break_words,
            );
            const text_layout = node.layout.text_layout;
            var line_index: usize = 0;
            while (line_index < text_layout.lines.items.len) : (line_index += 1) {
                const line = text_layout.lines.items[line_index];
                if (line.len == 0) continue;
                const line_text = trimmed[line.start .. line.start + line.len];
                const line_y = text_rect.y + @as(f32, @floatFromInt(line_index)) * text_layout.line_height;
                var line_x = text_rect.x;
                if (class_spec.text_align) |text_align| {
                    switch (text_align) {
                        .center => line_x += (text_rect.w - line.width) / 2.0,
                        .right => line_x += (text_rect.w - line.width),
                        else => {},
                    }
                }
                const line_rect = types.Rect{
                    .x = line_x,
                    .y = line_y,
                    .w = line.width,
                    .h = text_layout.line_height,
                };
                drawTextDirect(line_rect, line_text, transitions.effectiveVisual(node), draw_font, font_scale);
            }
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

    const tab_info = focus.tabIndexForNode(store, node);

    var options = dvui.Options{
        .name = "solid-div",
        .background = false,
        .expand = .none,
        .id_extra = nodeIdExtra(node.id),
    };
    style_apply.applyToOptions(&class_spec, &options);
    style_apply.resolveFont(&class_spec, &options);
    applyLayoutScaleToOptions(node, &options);
    const visual_eff = transitions.effectiveVisual(node);
    applyVisualPropsToOptions(visual_eff, &options);
    applyBorderColorToOptions(node, visual_eff, &options);
    applyTransformToOptions(node, &options);
    applyAccessibilityOptions(node, &options, .generic_container);
    if (node.layout.rect) |rect| {
        options.rect = physicalToDvuiRect(rect);
        options.expand = .none;
    }

    var box = dvui.box(@src(), .{}, options);
    defer box.deinit();
    applyAccessibilityState(node, box.data());

    if (tab_info.focusable and allowFocusRegistration()) {
        dvui.tabIndexSet(box.data().id, tab_info.tab_index);
        focus.registerFocusable(store, node, box.data());
    }

    renderChildrenOrdered(event_ring, store, node, allocator, tracker, false);
    if (state.input_enabled_state) {
        drag_drop.handleDiv(event_ring, store, node, box.data());
    }
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

fn renderTriangle(
    event_ring: ?*events.EventRing,
    store: *types.NodeStore,
    node: *types.SolidNode,
    allocator: std.mem.Allocator,
    class_spec: tailwind.Spec,
    tracker: *DirtyRegionTracker,
) void {
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
    const rect = rect_opt orelse return;
    drawTriangleDirect(rect, transitions.effectiveVisual(node), transitions.effectiveTransform(node), allocator, class_spec.background);
    renderChildElements(event_ring, store, node, allocator, tracker);
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
            const visual_eff = transitions.effectiveVisual(node);
            applyVisualPropsToOptions(visual_eff, &options);
            applyBorderColorToOptions(node, visual_eff, &options);
            applyTransformToOptions(node, &options);
            if (font_override) |style_name| {
                if (options.font_style == null) {
                    options.font_style = style_name;
                }
            }
            style_apply.resolveFont(&class_spec, &options);
            dvui.labelNoFmt(@src(), trimmed, .{}, options);
        }
    }

    renderChildElements(event_ring, store, node, allocator, tracker);
}

fn applyGizmoProp(node: *types.SolidNode) void {
    const override = state.gizmo_override_rect;
    const attr_rect = node.gizmoRect();
    const has_new_attr = attr_rect != null and node.lastAppliedGizmoRectSerial() != node.gizmoRectSerial();

    const prop = if (has_new_attr)
        attr_rect.?
    else
        override orelse attr_rect orelse return;

    node.setGizmoRuntimeRect(prop);

    if (has_new_attr) {
        node.markGizmoRectApplied();
        state.gizmo_rect_pending = prop;
    }
}

fn renderText(store: *types.NodeStore, node: *types.SolidNode) void {
    const trimmed = std.mem.trim(u8, node.text, " \n\r\t");
    if (trimmed.len > 0) {
        var options = dvui.Options{ .id_extra = nodeIdExtra(node.id) };
        if (node.parent) |pid| {
            if (store.node(pid)) |parent| {
                var parent_spec = parent.prepareClassSpec();
                tailwind.applyHover(&parent_spec, parent.hovered);
                style_apply.applyToOptions(&parent_spec, &options);
                style_apply.resolveFont(&parent_spec, &options);
            }
        }
        applyLayoutScaleToOptions(node, &options);
        const visual_eff = transitions.effectiveVisual(node);
        applyVisualPropsToOptions(visual_eff, &options);
        applyBorderColorToOptions(node, visual_eff, &options);
        applyTransformToOptions(node, &options);
        applyAccessibilityOptions(node, &options, null);
        var lw = dvui.LabelWidget.initNoFmt(@src(), trimmed, .{}, options);
        lw.install();
        applyAccessibilityState(node, lw.data());
        lw.draw();
        lw.deinit();
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
    const text = buildText(store, node, allocator);
    const trimmed = std.mem.trim(u8, text, " \n\r\t");
    const caption = if (trimmed.len == 0) "Button" else trimmed;
    if (!state.logged_button_render) {
        state.logged_button_render = true;
    }

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
        .padding = dvui.Rect.all(6),
        // Respect layout positions exactly; DVUI's default button margin would offset the rect.
        .margin = dvui.Rect{},
    };
    const tab_info = focus.tabIndexForNode(store, node);
    const focus_allowed = allowFocusRegistration();
    if (tab_info.focusable and focus_allowed) {
        options.tab_index = tab_info.tab_index;
    }
    style_apply.applyToOptions(&class_spec, &options);
    style_apply.resolveFont(&class_spec, &options);
    applyLayoutScaleToOptions(node, &options);
    const visual_eff = transitions.effectiveVisual(node);
    applyVisualPropsToOptions(visual_eff, &options);
    applyBorderColorToOptions(node, visual_eff, &options);
    applyTransformToOptions(node, &options);
    applyAccessibilityOptions(node, &options, null);
    if (rect_opt) |rect| {
        options.rect = physicalToDvuiRect(rect);
        options.expand = .none;
    }

    if (state.button_debug_count < 5) {
        state.button_debug_count += 1;
    }

    // Use ButtonWidget directly instead of dvui.button() to ensure unique widget IDs.
    // The issue with dvui.button(@src(), ...) is that @src() returns the same source location
    // for every button rendered through this function, causing all buttons to share the same
    // DVUI widget ID. This breaks click detection and event dispatch.
    // By using ButtonWidget directly with id_extra set to a hash of node_id, each button
    // gets a unique ID even though they all originate from the same source location.
    var bw = dvui.ButtonWidget.init(@src(), .{ .draw_focus = false }, options);
    bw.install();
    applyAccessibilityState(node, bw.data());
    if (tab_info.focusable and focus_allowed) {
        focus.registerFocusable(store, node, bw.data());
    }
    if (state.input_enabled_state) {
        bw.hover = false;
        bw.click = clickedTopmost(bw.data(), node_id, .{ .hovered = &bw.hover });
    }
    bw.drawBackground();

    // Draw caption directly (avoid relying on LabelWidget sizing/refresh timing).
    // This fixes cases where button text doesn't appear until a later repaint.
    const content_rs = bw.data().contentRectScale();
    var text_style = options.strip().override(bw.style());
    applyLayoutScaleToOptions(node, &text_style);
    const font = text_style.fontGet();
    const size_nat = font.textSize(caption);
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
        .text = caption,
        .rs = text_rs,
        .color = text_style.color(.text),
        .outline_color = text_style.text_outline_color,
        .outline_thickness = text_style.text_outline_thickness,
    }) catch |err| {
        if (state.button_text_error_log_count < 8) {
            state.button_text_error_log_count += 1;
            log.err("button caption renderText failed node={d}: {s}", .{ node_id, @errorName(err) });
        }
    };

    bw.drawFocus();
    const pressed = if (state.input_enabled_state) bw.clicked() else false;
    bw.deinit();

    if (pressed) {
        log.info("button pressed node={d} has_listener={}", .{ node_id, node.hasListener("click") });
        if (node.hasListener("click")) {
            if (event_ring) |ring| {
                const ok = ring.pushClick(node_id);
                log.info("button dispatched via ring node={d} ok={}", .{ node_id, ok });
            }
        }
    }

    renderChildElements(event_ring, store, node, allocator, tracker);
}

fn renderIcon(
    event_ring: ?*events.EventRing,
    store: *types.NodeStore,
    node_id: u32,
    node: *types.SolidNode,
    class_spec: tailwind.Spec,
    allocator: std.mem.Allocator,
    tracker: *DirtyRegionTracker,
) void {
    const src = node.imageSource();
    const glyph = node.iconGlyph();
    const icon_kind = node.iconKind();
    switch (node.cached_icon) {
        .none => {
            const resolved_path = if (src.len > 0 and glyph.len == 0 and icon_kind != .glyph and (icon_kind != .auto or !icon_registry.hasEntry(src))) blk: {
                if (node.resolved_icon_path.len > 0) break :blk node.resolved_icon_path;
                const resolved = icon_registry.resolveIconPathAlloc(store.allocator, src) catch |err| {
                    if (src.len > 0) {
                        log.err("Solid icon resolve failed for {s}: {s}", .{ src, @errorName(err) });
                    } else {
                        log.err("Solid icon resolve failed for node {d}: {s}", .{ node_id, @errorName(err) });
                    }
                    node.cached_icon = .failed;
                    return;
                };
                node.resolved_icon_path = resolved;
                break :blk resolved;
            } else &.{};

            const resolved = icon_registry.resolveWithPath(icon_kind, src, glyph, resolved_path) catch |err| {
                if (src.len > 0) {
                    log.err("Solid icon load failed for {s}: {s}", .{ src, @errorName(err) });
                } else {
                    log.err("Solid icon load failed for node {d}: {s}", .{ node_id, @errorName(err) });
                }
                node.cached_icon = .failed;
                return;
            };
            node.cached_icon = switch (resolved) {
                .vector => |bytes| .{ .vector = bytes },
                .raster => |resource| .{ .raster = resource },
                .glyph => |text| .{ .glyph = text },
            };
        },
        .failed => return,
        else => {},
    }

    var options = dvui.Options{
        .name = "solid-icon",
        .id_extra = nodeIdExtra(node_id),
    };
    style_apply.applyToOptions(&class_spec, &options);
    style_apply.resolveFont(&class_spec, &options);
    applyLayoutScaleToOptions(node, &options);
    const visual_eff = transitions.effectiveVisual(node);
    applyVisualPropsToOptions(visual_eff, &options);
    applyBorderColorToOptions(node, visual_eff, &options);
    applyTransformToOptions(node, &options);
    applyAccessibilityOptions(node, &options, null);

    switch (node.cached_icon) {
        .vector => |tvg_bytes| {
            const icon_name = if (src.len > 0) src else "solid-icon";
            var iw = dvui.IconWidget.init(@src(), icon_name, tvg_bytes, .{}, options);
            iw.install();
            applyAccessibilityState(node, iw.data());
            iw.draw();
            iw.deinit();
        },
        .raster => |resource| {
            const image_source = image_loader.imageSource(resource);
            var wd = dvui.image(@src(), .{ .source = image_source }, options);
            applyAccessibilityState(node, &wd);
        },
        .glyph => |text| {
            var lw = dvui.LabelWidget.initNoFmt(@src(), text, .{}, options);
            lw.install();
            applyAccessibilityState(node, lw.data());
            lw.draw();
            lw.deinit();
        },
        .none, .failed => return,
    }

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

    const resource = switch (node.cached_image) {
        .resource => |resource| resource,
        .failed => return,
        .none => blk: {
            const resolved_path = if (node.resolved_image_path.len > 0) node.resolved_image_path else blk_path: {
                const resolved = image_loader.resolveImagePathAlloc(store.allocator, src) catch |err| {
                    log.err("Solid image resolve failed for {s}: {s}", .{ src, @errorName(err) });
                    node.cached_image = .failed;
                    return;
                };
                node.resolved_image_path = resolved;
                break :blk_path resolved;
            };

            const loaded = image_loader.loadResolved(resolved_path) catch |err| {
                log.err("Solid image load failed for {s}: {s}", .{ src, @errorName(err) });
                node.cached_image = .failed;
                return;
            };
            node.cached_image = .{ .resource = loaded };
            break :blk loaded;
        },
    };

    var options = dvui.Options{
        .name = "solid-image",
        .id_extra = nodeIdExtra(node_id),
        .role = .image,
    };
    style_apply.applyToOptions(&class_spec, &options);
    style_apply.resolveFont(&class_spec, &options);
    applyLayoutScaleToOptions(node, &options);
    const visual_eff = transitions.effectiveVisual(node);
    applyVisualPropsToOptions(visual_eff, &options);
    applyBorderColorToOptions(node, visual_eff, &options);
    applyTransformToOptions(node, &options);
    applyAccessibilityOptions(node, &options, null);

    const image_source = image_loader.imageSource(resource);
    const tint_base = transitions.effectiveImageTint(node) orelse types.PackedColor{ .value = 0xffffffff };
    const combined_opacity = visual_eff.opacity * transitions.effectiveImageOpacity(node);
    const tint_color = packedColorToDvui(tint_base, combined_opacity);

    var size = dvui.Size{};
    if (options.min_size_content) |msc| {
        size = msc;
    } else {
        size = dvui.imageSize(image_source) catch .{ .w = 10, .h = 10 };
    }

    var wd = dvui.WidgetData.init(@src(), .{}, options.override(.{ .min_size_content = size }));
    wd.register();
    applyAccessibilityState(node, &wd);

    const cr = wd.contentRect();
    const ms = wd.options.min_size_contentGet();

    var too_big = false;
    if (ms.w > cr.w or ms.h > cr.h) {
        too_big = true;
    }

    const expand = wd.options.expandGet();
    const gravity = wd.options.gravityGet();
    var rect = dvui.placeIn(cr, ms, expand, gravity);

    if (too_big and expand != .ratio) {
        if (ms.w > cr.w and !expand.isHorizontal()) {
            rect.w = ms.w;
            rect.x -= gravity.x * (ms.w - cr.w);
        }

        if (ms.h > cr.h and !expand.isVertical()) {
            rect.h = ms.h;
            rect.y -= gravity.y * (ms.h - cr.h);
        }
    }

    wd.rect = rect.outset(wd.options.paddingGet()).outset(wd.options.borderGet()).outset(wd.options.marginGet());

    var render_background: ?dvui.Color = if (wd.options.backgroundGet()) wd.options.color(.fill) else null;
    if (wd.options.rotationGet() == 0.0) {
        wd.borderAndBackground(.{});
        render_background = null;
    } else {
        if (wd.options.borderGet().nonZero()) {
            log.debug("solid image {x} can't render border while rotated", .{wd.id});
        }
    }

    const render_tex_opts = dvui.RenderTextureOptions{
        .rotation = wd.options.rotationGet(),
        .colormod = tint_color,
        .corner_radius = wd.options.corner_radiusGet(),
        .uv = .{ .w = 1, .h = 1 },
        .background_color = render_background,
    };
    const content_rs = wd.contentRectScale();
    dvui.renderImage(image_source, content_rs, render_tex_opts) catch |err| {
        log.err("Solid image render failed for node {d}: {s}", .{ node_id, @errorName(err) });
    };
    wd.minSizeSetAndRefresh();
    wd.minSizeReportToParent();

    renderChildElements(event_ring, store, node, allocator, tracker);
}

fn renderSlider(
    event_ring: ?*events.EventRing,
    store: *types.NodeStore,
    node_id: u32,
    node: *types.SolidNode,
    class_spec: tailwind.Spec,
) void {
    var options = dvui.slider_defaults.override(.{
        .name = "solid-slider",
        .id_extra = nodeIdExtra(node_id),
    });
    style_apply.applyToOptions(&class_spec, &options);
    style_apply.resolveFont(&class_spec, &options);
    applyLayoutScaleToOptions(node, &options);
    const visual_eff = transitions.effectiveVisual(node);
    applyVisualPropsToOptions(visual_eff, &options);
    applyBorderColorToOptions(node, visual_eff, &options);
    applyTransformToOptions(node, &options);
    applyAccessibilityOptions(node, &options, .slider);

    if (node.layout.rect) |rect| {
        options.rect = physicalToDvuiRect(rect);
        options.expand = .none;
    }

    const tab_info = focus.tabIndexForNode(store, node);
    const focus_allowed = allowFocusRegistration();
    if (tab_info.focusable and focus_allowed) {
        options.tab_index = tab_info.tab_index;
    }

    const input_state = node.ensureInputState(store.allocator) catch |err| {
        log.err("Solid slider state init failed for node {d}: {s}", .{ node_id, @errorName(err) });
        return;
    };

    input_state.syncBufferFromValue() catch |err| {
        log.err("Solid slider buffer sync failed for node {d}: {s}", .{ node_id, @errorName(err) });
        return;
    };

    var fraction: f32 = 0;
    const current_text = input_state.currentText();
    if (current_text.len > 0) {
        fraction = std.fmt.parseFloat(f32, current_text) catch 0;
    }
    fraction = @max(0, @min(1, fraction));

    const direction: dvui.enums.Direction = .horizontal;

    var slider_box = dvui.box(@src(), .{ .dir = direction }, options);
    defer slider_box.deinit();
    applyAccessibilityState(node, slider_box.data());
    if (tab_info.focusable and focus_allowed) {
        focus.registerFocusable(store, node, slider_box.data());
    }

    if (slider_box.data().accesskit_node()) |ak_node| {
        dvui.AccessKit.nodeAddAction(ak_node, dvui.AccessKit.Action.focus);
        dvui.AccessKit.nodeAddAction(ak_node, dvui.AccessKit.Action.set_value);
        dvui.AccessKit.nodeSetOrientation(ak_node, dvui.AccessKit.Orientation.horizontal);
        dvui.AccessKit.nodeSetNumericValue(ak_node, fraction);
        dvui.AccessKit.nodeSetMinNumericValue(ak_node, 0);
        dvui.AccessKit.nodeSetMaxNumericValue(ak_node, 1);
    }

    const br = slider_box.data().contentRect();
    const knobsize = @min(br.w, br.h);
    const track = switch (direction) {
        .horizontal => dvui.Rect{ .x = knobsize / 2, .y = br.h / 2 - 2, .w = br.w - knobsize, .h = 4 },
        .vertical => dvui.Rect{ .x = br.w / 2 - 2, .y = knobsize / 2, .w = 4, .h = br.h - knobsize },
    };
    const trackrs = slider_box.widget().screenRectScale(track);
    const rs = slider_box.data().contentRectScale();

    var hovered = false;
    var changed = false;
    var prev_focused = input_state.focused;
    var focused_now = false;

    if (state.input_enabled_state) {
        if (tab_info.focusable and focus_allowed) {
            dvui.tabIndexSet(slider_box.data().id, tab_info.tab_index);
        }

        for (dvui.events()) |*e| {
            if (!dvui.eventMatch(e, .{ .id = slider_box.data().id, .r = rs.r }))
                continue;

            switch (e.evt) {
                .mouse => |me| {
                    var p: ?dvui.Point.Physical = null;
                    if (me.action == .focus) {
                        e.handle(@src(), slider_box.data());
                        dvui.focusWidget(slider_box.data().id, null, e.num);
                    } else if (me.action == .press and me.button.pointer()) {
                        dvui.captureMouse(slider_box.data(), e.num);
                        e.handle(@src(), slider_box.data());
                        p = me.p;
                    } else if (me.action == .release and me.button.pointer()) {
                        dvui.captureMouse(null, e.num);
                        dvui.dragEnd();
                        e.handle(@src(), slider_box.data());
                    } else if (me.action == .motion and dvui.captured(slider_box.data().id)) {
                        e.handle(@src(), slider_box.data());
                        p = me.p;
                    } else if (me.action == .position) {
                        dvui.cursorSet(class_spec.cursor orelse .arrow);
                        hovered = true;
                    }

                    if (p) |pp| {
                        var min_val: f32 = undefined;
                        var max_val: f32 = undefined;
                        switch (direction) {
                            .horizontal => {
                                min_val = trackrs.r.x;
                                max_val = trackrs.r.x + trackrs.r.w;
                            },
                            .vertical => {
                                min_val = 0;
                                max_val = trackrs.r.h;
                            },
                        }

                        if (max_val > min_val) {
                            const v = if (direction == .horizontal) pp.x else (trackrs.r.y + trackrs.r.h - pp.y);
                            fraction = (v - min_val) / (max_val - min_val);
                            fraction = @max(0, @min(1, fraction));
                            changed = true;
                        }
                    }
                },
                .key => |ke| {
                    if (ke.action == .down or ke.action == .repeat) {
                        switch (ke.code) {
                            .left, .down => {
                                e.handle(@src(), slider_box.data());
                                fraction = @max(0, @min(1, fraction - 0.05));
                                changed = true;
                            },
                            .right, .up => {
                                e.handle(@src(), slider_box.data());
                                fraction = @max(0, @min(1, fraction + 0.05));
                                changed = true;
                            },
                            else => {},
                        }
                    }
                },
                .text => |te| {
                    e.handle(@src(), slider_box.data());
                    const value: f32 = std.fmt.parseFloat(f32, te.txt) catch continue;
                    fraction = @max(0, @min(1, value));
                    changed = true;
                },
            }
        }

        focused_now = dvui.focusedWidgetId() == slider_box.data().id;
        input_state.focused = focused_now;
    } else {
        input_state.focused = false;
        prev_focused = false;
    }

    if (state.input_enabled_state) {
        if (event_ring) |ring| {
            if (!prev_focused and focused_now and node.hasListener("focus")) {
                _ = ring.pushFocus(node_id);
            } else if (prev_focused and !focused_now and node.hasListener("blur")) {
                _ = ring.pushBlur(node_id);
            }
        }
    }

    const perc = @max(0, @min(1, fraction));
    if (fraction != perc) {
        fraction = perc;
        changed = true;
    }

    var part = trackrs.r;
    switch (direction) {
        .horizontal => part.w *= perc,
        .vertical => {
            const h = part.h * (1 - perc);
            part.y += h;
            part.h = trackrs.r.h - h;
        },
    }
    if (slider_box.data().visible()) {
        part.fill(options.corner_radiusGet().scale(trackrs.s, dvui.Rect.Physical), .{
            .color = dvui.themeGet().color(.highlight, .fill),
            .fade = 1.0,
        });
    }

    switch (direction) {
        .horizontal => {
            part.x = part.x + part.w;
            part.w = trackrs.r.w - part.w;
        },
        .vertical => {
            part = trackrs.r;
            part.h *= (1 - perc);
        },
    }
    if (slider_box.data().visible()) {
        part.fill(options.corner_radiusGet().scale(trackrs.s, dvui.Rect.Physical), .{
            .color = options.color(.fill),
            .fade = 1.0,
        });
    }

    const knobRect = switch (direction) {
        .horizontal => dvui.Rect{ .x = (br.w - knobsize) * perc, .w = knobsize, .h = knobsize },
        .vertical => dvui.Rect{ .y = (br.h - knobsize) * (1 - perc), .w = knobsize, .h = knobsize },
    };

    const fill_color: dvui.Color = if (dvui.captured(slider_box.data().id))
        options.color(.fill_press)
    else if (hovered)
        options.color(.fill_hover)
    else
        options.color(.fill);

    var knob = dvui.BoxWidget.init(
        @src(),
        .{ .dir = .horizontal },
        .{
            .rect = knobRect,
            .padding = .{},
            .margin = .{},
            .background = true,
            .border = dvui.Rect.all(1),
            .corner_radius = dvui.Rect.all(100),
            .color_fill = fill_color,
        },
    );
    knob.install();
    knob.drawBackground();
    if (slider_box.data().id == dvui.focusedWidgetId()) {
        knob.data().focusBorder();
    }
    knob.deinit();

    if (changed) {
        var value_buffer: [32]u8 = undefined;
        const value_str = std.fmt.bufPrint(&value_buffer, "{d}", .{fraction}) catch "";
        input_state.updateFromText(value_str) catch |err| {
            log.err("Solid slider state update failed for node {d}: {s}", .{ node_id, @errorName(err) });
        };
        store.markNodeChanged(node_id);
        if (event_ring) |ring| {
            if (node.hasListener("input")) {
                _ = ring.pushInput(node_id, value_str);
            }
        }
        dvui.refresh(null, @src(), slider_box.data().id);
    }
}

fn findUtf8Next(text: []const u8, pos: usize) usize {
    const len = text.len;
    const p = @min(pos, len);
    if (p >= len) return len;
    var next = p + 1;
    while (next < len and text[next] & 0xc0 == 0x80) {
        next += 1;
    }
    return next;
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
    style_apply.resolveFont(&class_spec, &options);
    applyLayoutScaleToOptions(node, &options);
    const visual_eff = transitions.effectiveVisual(node);
    applyVisualPropsToOptions(visual_eff, &options);
    applyBorderColorToOptions(node, visual_eff, &options);
    applyTransformToOptions(node, &options);
    applyAccessibilityOptions(node, &options, .text_input);

    const tab_info = focus.tabIndexForNode(store, node);
    const focus_allowed = allowFocusRegistration();

    var input_state = node.ensureInputState(store.allocator) catch |err| {
        log.err("Solid input state init failed for node {d}: {s}", .{ node_id, @errorName(err) });
        return;
    };

    input_state.syncBufferFromValue() catch |err| {
        log.err("Solid input buffer sync failed for node {d}: {s}", .{ node_id, @errorName(err) });
        return;
    };
    // Preserve the actual text length; buffer may retain extra capacity for future edits.
    if (input_state.text_len > input_state.buffer.len) {
        input_state.text_len = input_state.buffer.len;
    }
    if (input_state.buffer.len > input_state.text_len) {
        input_state.buffer[input_state.text_len] = 0;
    }

    var box = dvui.BoxWidget.init(@src(), .{}, options);
    box.install();
    defer box.deinit();

    const wd = box.data();
    applyAccessibilityState(node, wd);
    if (tab_info.focusable and focus_allowed) {
        focus.registerFocusable(store, node, wd);
    }
    var prev_focused = input_state.focused;
    var focused_now = false;
    var text_changed = false;
    var caret_changed = false;
    var enter_pressed = false;

    if (state.input_enabled_state) {
        if (tab_info.focusable and focus_allowed) {
            dvui.tabIndexSet(wd.id, tab_info.tab_index);
        }

        var hovered = false;
        _ = clickedExTopmost(wd, node_id, .{ .hovered = &hovered, .hover_cursor = class_spec.cursor orelse .ibeam });

        focused_now = dvui.focusedWidgetId() == wd.id;
        input_state.focused = focused_now;

        if (focused_now) {
            const rs = wd.contentRectScale();
            const natural = dvui.Rect.Natural.cast(rs.rectFromPhysical(rs.r));
            dvui.wantTextInput(natural);
        }

        for (dvui.events()) |*e| {
            if (!dvui.eventMatch(e, .{ .id = wd.id, .r = wd.borderRectScale().r })) continue;

            switch (e.evt) {
                .text => |te| {
                    if (te.txt.len == 0) break;
                    const insert_at = @min(input_state.caret, input_state.text_len);
                    const new_len = input_state.text_len + te.txt.len;
                    input_state.ensureCapacity(new_len + 1) catch |err| {
                        log.err("Solid input ensureCapacity failed for node {d}: {s}", .{ node_id, @errorName(err) });
                        break;
                    };
                    const tail_len = input_state.text_len - insert_at;
                    if (tail_len > 0) {
                        @memmove(input_state.buffer[insert_at + te.txt.len .. insert_at + te.txt.len + tail_len], input_state.buffer[insert_at .. insert_at + tail_len]);
                    }
                    @memcpy(input_state.buffer[insert_at .. insert_at + te.txt.len], te.txt);
                    if (input_state.buffer.len > new_len) {
                        input_state.buffer[new_len] = 0;
                    }
                    input_state.text_len = new_len;
                    input_state.caret = insert_at + te.txt.len;
                    input_state.updateFromText(input_state.buffer[0..new_len]) catch |err| {
                        log.err("Solid input update failed for node {d}: {s}", .{ node_id, @errorName(err) });
                        break;
                    };
                    store.markNodeChanged(node_id);
                    text_changed = true;
                    e.handle(@src(), wd);
                },
                .key => |ke| {
                    if (ke.action != .down and ke.action != .repeat) break;
                    if (ke.matchBind("char_left")) {
                        if (input_state.caret > 0) {
                            const new_pos = dvui.findUtf8Start(input_state.buffer[0..input_state.text_len], input_state.caret - 1);
                            if (new_pos != input_state.caret) {
                                input_state.caret = new_pos;
                                caret_changed = true;
                            }
                        }
                        e.handle(@src(), wd);
                        break;
                    }
                    if (ke.matchBind("char_right")) {
                        if (input_state.caret < input_state.text_len) {
                            const new_pos = findUtf8Next(input_state.buffer[0..input_state.text_len], input_state.caret);
                            if (new_pos != input_state.caret) {
                                input_state.caret = new_pos;
                                caret_changed = true;
                            }
                        }
                        e.handle(@src(), wd);
                        break;
                    }
                    switch (ke.code) {
                        .backspace => {
                            if (input_state.caret == 0 or input_state.text_len == 0) break;
                            const new_pos = dvui.findUtf8Start(input_state.buffer[0..input_state.text_len], input_state.caret - 1);
                            const tail_len = input_state.text_len - input_state.caret;
                            if (tail_len > 0) {
                                @memmove(input_state.buffer[new_pos .. new_pos + tail_len], input_state.buffer[input_state.caret .. input_state.caret + tail_len]);
                            }
                            const new_len = input_state.text_len - (input_state.caret - new_pos);
                            if (input_state.buffer.len > new_len) {
                                input_state.buffer[new_len] = 0;
                            }
                            input_state.text_len = new_len;
                            input_state.caret = new_pos;
                            input_state.updateFromText(input_state.buffer[0..new_len]) catch |err| {
                                log.err("Solid input backspace update failed for node {d}: {s}", .{ node_id, @errorName(err) });
                                break;
                            };
                            store.markNodeChanged(node_id);
                            text_changed = true;
                            e.handle(@src(), wd);
                        },
                        .enter, .kp_enter => {
                            if (ke.action == .down) {
                                enter_pressed = true;
                                e.handle(@src(), wd);
                            }
                        },
                        else => {},
                    }
                },
                else => {},
            }
        }
        if (caret_changed) {
            store.markNodeChanged(node_id);
        }
    } else {
        input_state.focused = false;
        prev_focused = false;
    }

    box.drawBackground();
    const content_rs = wd.contentRectScale();
    const text_slice = input_state.currentText();
    const font = wd.options.fontGet();
    const visual = transitions.effectiveVisual(node);
    const text_color = if (visual.text_color) |tc|
        direct.packedColorToDvui(tc, visual.opacity)
    else
        direct.packedColorToDvui(.{ .value = 0xffffffff }, visual.opacity);
    const outline_color = wd.options.text_outline_color;
    const outline_thickness = wd.options.text_outline_thickness;

    const prev_clip = dvui.clip(content_rs.r);
    defer dvui.clipSet(prev_clip);

    const text_size = font.textSize(text_slice);
    const text_w = text_size.w * content_rs.s;
    const caret_index = @min(input_state.caret, text_slice.len);
    const caret_prefix = text_slice[0..caret_index];
    const caret_size = font.textSize(caret_prefix);
    const caret_w = caret_size.w * content_rs.s;
    const fallback_h = font.textSize("M").h * content_rs.s;
    const text_h = if (text_slice.len > 0) text_size.h * content_rs.s else fallback_h;
    var text_x = content_rs.r.x;
    var text_y = content_rs.r.y;
    if (text_h < content_rs.r.h) {
        text_y += (content_rs.r.h - text_h) * 0.5;
    }
    if (text_w > content_rs.r.w) {
        const max_scroll = text_w - content_rs.r.w;
        const desired_scroll = @min(@max(caret_w - content_rs.r.w, 0.0), max_scroll);
        text_x -= desired_scroll;
    }

    var text_rs = content_rs;
    text_rs.r.x = text_x;
    text_rs.r.y = text_y;
    text_rs.r.w = text_w;
    text_rs.r.h = text_h;

    if (text_slice.len > 0) {
        dvui.renderText(.{
            .font = font,
            .text = text_slice,
            .rs = text_rs,
            .color = text_color,
            .outline_color = outline_color,
            .outline_thickness = outline_thickness,
        }) catch {};
    }

    if (focused_now) {
        const blink_period_ns: i128 = 1_000_000_000;
        const phase = @mod(dvui.frameTimeNS(), blink_period_ns);
        if (phase < (blink_period_ns / 2)) {
            var caret_rs = content_rs;
            caret_rs.r.x = text_x + caret_w;
            caret_rs.r.y = text_y;
            dvui.renderText(.{
                .font = font,
                .text = "|",
                .rs = caret_rs,
                .color = text_color,
                .outline_color = outline_color,
                .outline_thickness = outline_thickness,
            }) catch {};
        }
    }

    if (state.input_enabled_state) {
        if (event_ring) |ring| {
            if (!prev_focused and focused_now and node.hasListener("focus")) {
                _ = ring.pushFocus(node_id);
            } else if (prev_focused and !focused_now and node.hasListener("blur")) {
                _ = ring.pushBlur(node_id);
            }

            if (text_changed and node.hasListener("input")) {
                const payload = input_state.currentText();
                _ = ring.pushInput(node_id, payload);
            }
            if (enter_pressed and node.hasListener("enter")) {
                const payload = input_state.currentText();
                _ = ring.push(.enter, node_id, payload);
            }
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

pub fn renderChildrenOrdered(
    event_ring: ?*events.EventRing,
    store: *types.NodeStore,
    node: *types.SolidNode,
    allocator: std.mem.Allocator,
    tracker: *DirtyRegionTracker,
    skip_text: bool,
) void {
    if (node.children.items.len == 0) return;

    var prev_clip: ?dvui.Rect.Physical = null;
    if (node.visual.clip_children) {
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

    var ordered: std.ArrayList(OrderedNode) = .empty;
    defer ordered.deinit(allocator);

    for (node.children.items, 0..) |child_id, order_index| {
        const child = store.node(child_id) orelse continue;
        if (skip_text and child.kind == .text) continue;
        const z_index = child.visual.z_index;
        ordered.append(allocator, .{
            .id = child_id,
            .z_index = z_index,
            .order = order_index,
        }) catch {};
    }

    if (ordered.items.len == 0) return;
    sortOrderedNodes(ordered.items);

    for (ordered.items) |entry| {
        renderNode(event_ring, store, entry.id, allocator, tracker);
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
