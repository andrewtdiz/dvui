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
const focus = @import("../../events/focus.zig");

const interaction = @import("interaction.zig");
const state = @import("state.zig");
const derive = @import("derive.zig");
const visual_sync = @import("visual_sync.zig");
const runtime_mod = @import("runtime.zig");

const applyVisualToOptions = style_apply.applyVisualToOptions;
const applyVisualPropsToOptions = style_apply.applyVisualPropsToOptions;
const applyClassSpecToVisual = style_apply.applyClassSpecToVisual;

const dvuiColorToPacked = direct.dvuiColorToPacked;
const drawTextDirect = direct.drawTextDirect;
const drawTriangleDirect = direct.drawTriangleDirect;
const shouldDirectDraw = direct.shouldDirectDraw;
const packedColorToDvui = direct.packedColorToDvui;

const DirtyRegionTracker = paint_cache.DirtyRegionTracker;
const renderCachedOrDirectBackground = paint_cache.renderCachedOrDirectBackground;

const nodeIdExtra = state.nodeIdExtra;
const physicalToDvuiRect = state.physicalToDvuiRect;
const sortOrderedNodes = state.sortOrderedNodes;
const OrderedNode = state.OrderedNode;
const RenderContext = state.RenderContext;
const intersectRect = state.intersectRect;
const contextPoint = state.contextPoint;
const nodeBoundsInContext = state.nodeBoundsInContext;

const applyLayoutScaleToOptions = visual_sync.applyLayoutScaleToOptions;
const nodeHasAccessibilityProps = visual_sync.nodeHasAccessibilityProps;
const applyAccessibilityOptions = visual_sync.applyAccessibilityOptions;
const applyAccessibilityState = visual_sync.applyAccessibilityState;

const clickedExTopmost = interaction.clickedExTopmost;
const clickedTopmost = interaction.clickedTopmost;

const log = std.log.scoped(.retained);

const RenderRuntime = runtime_mod.RenderRuntime;

fn rectsIntersect(a: types.Rect, b: types.Rect) bool {
    return !(a.x + a.w < b.x or b.x + b.w < a.x or a.y + a.h < b.y or b.y + b.h < a.y);
}

fn pointerEventAllowed(runtime: *const RenderRuntime, node_id: u32, widget_id: dvui.Id, e: *dvui.Event) bool {
    switch (e.evt) {
        .mouse => {
            if (e.target_widgetId) |target| {
                return target == widget_id;
            }
            return runtime.pointerTargetId() == node_id;
        },
        else => return true,
    }
}

fn mapPointerButton(button: dvui.enums.Button) u8 {
    return switch (button) {
        .left => 0,
        .middle => 1,
        .right => 2,
        .four => 3,
        .five => 4,
        else => 255,
    };
}

fn pointerModMask(mods: dvui.enums.Mod) u8 {
    var mask: u8 = 0;
    if (mods.shift()) mask |= 1;
    if (mods.control()) mask |= 2;
    if (mods.alt()) mask |= 4;
    if (mods.command()) mask |= 8;
    return mask;
}

fn pushPointerEvent(event_ring: ?*events.EventRing, kind: events.EventKind, node_id: u32, mouse: dvui.Event.Mouse) void {
    if (event_ring) |ring| {
        const payload = events.PointerPayload{
            .x = mouse.p.x,
            .y = mouse.p.y,
            .button = mapPointerButton(mouse.button),
            .modifiers = pointerModMask(mouse.mod),
        };
        _ = ring.push(kind, node_id, std.mem.asBytes(&payload));
    }
}

fn applyBorderColorToOptions(node: *const types.SolidNode, visual: types.VisualProps, options: *dvui.Options) void {
    if (!node.transition_state.enabled) return;
    if (!node.transition_state.active_props.colors) return;
    const border_packed = transitions.effectiveBorderColor(node);
    options.color_border = packedColorToDvui(border_packed, visual.opacity);
}

fn scaleRectXY(r: dvui.Rect, sx: f32, sy: f32) dvui.Rect {
    return .{ .x = r.x * sx, .y = r.y * sy, .w = r.w * sx, .h = r.h * sy };
}

const TransformScale = struct { sx: f32, sy: f32, uniform: f32 };

fn effectiveNodeScale(ctx: RenderContext, node: *const types.SolidNode) TransformScale {
    const t = transitions.effectiveTransform(node);
    const sx = @abs(ctx.scale[0] * t.scale[0]);
    const sy = @abs(ctx.scale[1] * t.scale[1]);
    return .{ .sx = sx, .sy = sy, .uniform = @min(sx, sy) };
}

fn shouldSkipTinyScaledNode(ctx: RenderContext, node: *const types.SolidNode, scale: TransformScale) bool {
    if (scale.sx >= 1.0 and scale.sy >= 1.0) return false;
    if (node.layout.rect) |rect| {
        const bounds = nodeBoundsInContext(ctx, node, rect);
        if (scale.sx < 1.0 and @abs(bounds.w) < 1.0) return true;
        if (scale.sy < 1.0 and @abs(bounds.h) < 1.0) return true;
    }
    return false;
}

fn applyTransformScaleToOptions(scale: TransformScale, options: *dvui.Options) void {
    if (scale.sx == 1.0 and scale.sy == 1.0) return;
    if (options.margin) |m| options.margin = scaleRectXY(m, scale.sx, scale.sy);
    if (options.border) |b| options.border = scaleRectXY(b, scale.sx, scale.sy);
    if (options.padding) |p| options.padding = scaleRectXY(p, scale.sx, scale.sy);
    if (options.corner_radius) |c| options.corner_radius = c.scale(scale.uniform, dvui.Rect);
    if (options.min_size_content) |ms| options.min_size_content = dvui.Size{ .w = ms.w * scale.sx, .h = ms.h * scale.sy };
    if (options.max_size_content) |mx| options.max_size_content = dvui.Options.MaxSize{ .w = mx.w * scale.sx, .h = mx.h * scale.sy };
    if (options.text_outline_thickness) |v| options.text_outline_thickness = v * scale.uniform;
    const font = options.fontGet();
    options.font = font.resize(font.size * scale.uniform);
}

fn rectToParentLocal(rect: types.Rect, parent_origin: dvui.Point.Physical) types.Rect {
    return .{
        .x = rect.x - parent_origin.x,
        .y = rect.y - parent_origin.y,
        .w = rect.w,
        .h = rect.h,
    };
}

fn isContainerTag(tag: []const u8) bool {
    return std.mem.eql(u8, tag, "div") or std.mem.eql(u8, tag, "scroll") or std.mem.eql(u8, tag, "scrollframe");
}

const ScrollSession = struct {
    viewport: types.Rect,
    scroll_id: dvui.Id,
    info: dvui.ScrollInfo,
};

fn beginScrollSession(runtime: *const RenderRuntime, node: *types.SolidNode, viewport_opt: ?types.Rect) ?ScrollSession {
    if (viewport_opt == null) return null;
    if (!node.scroll.isEnabled()) return null;

    const viewport = viewport_opt.?;
    const allow_x = node.scroll.allowX();
    const allow_y = node.scroll.allowY();
    const virtual_w = if (allow_x) @max(node.scroll.content_width, viewport.w) else viewport.w;
    const virtual_h = if (allow_y) @max(node.scroll.content_height, viewport.h) else viewport.h;
    var info: dvui.ScrollInfo = .{
        .horizontal = if (allow_x) .given else .none,
        .vertical = if (allow_y) .given else .none,
        .virtual_size = .{ .w = virtual_w, .h = virtual_h },
        .viewport = .{
            .x = if (allow_x) node.scroll.offset_x else 0,
            .y = if (allow_y) node.scroll.offset_y else 0,
            .w = viewport.w,
            .h = viewport.h,
        },
    };
    if (allow_x) info.scrollToOffset(.horizontal, info.viewport.x);
    if (allow_y) info.scrollToOffset(.vertical, info.viewport.y);

    const scroll_id = state.scrollContentId(node.id);
    _ = interaction.handleScrollInput(runtime, node, viewport, &info, scroll_id);
    return .{
        .viewport = viewport,
        .scroll_id = scroll_id,
        .info = info,
    };
}

fn commitScrollSession(store: *types.NodeStore, node: *types.SolidNode, session: *const ScrollSession) bool {
    if (!node.scroll.isEnabled()) return false;

    const prev_x = node.scroll.offset_x;
    const prev_y = node.scroll.offset_y;
    const next_x = if (node.scroll.allowX()) session.info.viewport.x else prev_x;
    const next_y = if (node.scroll.allowY()) session.info.viewport.y else prev_y;

    if (next_x == prev_x and next_y == prev_y) return false;

    node.scroll.offset_x = next_x;
    node.scroll.offset_y = next_y;
    layout.applyScrollOffsetDelta(store, node, next_x - prev_x, next_y - prev_y);
    store.markNodePaintChanged(node.id);
    return true;
}

fn ctxForChildren(parent_ctx: RenderContext, node: *types.SolidNode, use_origin: bool) RenderContext {
    var next = parent_ctx;
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
        next.scale = .{ parent_ctx.scale[0] * t.scale[0], parent_ctx.scale[1] * t.scale[1] };
        next.offset = .{
            parent_ctx.scale[0] * offset.x + parent_ctx.offset[0],
            parent_ctx.scale[1] * offset.y + parent_ctx.offset[1],
        };
    }
    if (use_origin) {
        if (node.layout.child_rect) |child_rect| {
            next.origin = contextPoint(next, .{ .x = child_rect.x, .y = child_rect.y });
        }
    }
    if (node.visual.clip_children) {
        if (node.layout.rect) |rect| {
            const bounds = nodeBoundsInContext(parent_ctx, node, rect);
            if (next.clip) |clip| {
                next.clip = intersectRect(clip, bounds);
            } else {
                next.clip = bounds;
            }
        }
    }
    return next;
}

pub fn renderNode(
    runtime: *RenderRuntime,
    event_ring: ?*events.EventRing,
    store: *types.NodeStore,
    node_id: u32,
    allocator: std.mem.Allocator,
    tracker: *DirtyRegionTracker,
    ctx: RenderContext,
) void {
    const node = store.node(node_id) orelse return;
    if (node.kind != .element and dvui.snapToPixels()) {
        const scale = effectiveNodeScale(ctx, node);
        if (scale.sx != 1.0 or scale.sy != 1.0) {
            const old_snap = dvui.snapToPixelsSet(false);
            defer _ = dvui.snapToPixelsSet(old_snap);
        }
    }
    if (ctx.clip) |clip| {
        if (node.layout.rect) |rect_base| {
            const bounds = nodeBoundsInContext(ctx, node, rect_base);
            if (!rectsIntersect(bounds, clip)) {
                return;
            }
        }
    }
    switch (node.kind) {
        .root => {
            const child_ctx = ctxForChildren(ctx, node, false);
            renderChildrenOrdered(runtime, event_ring, store, node, allocator, tracker, child_ctx, false);
            node.markRendered();
        },
        .slot => {
            const child_ctx = ctxForChildren(ctx, node, false);
            renderChildrenOrdered(runtime, event_ring, store, node, allocator, tracker, child_ctx, false);
            node.markRendered();
        },
        .text => renderText(runtime, store, node, ctx),
        .element => renderElement(runtime, event_ring, store, node_id, node, allocator, tracker, ctx),
    }
}

fn renderElement(
    runtime: *RenderRuntime,
    event_ring: ?*events.EventRing,
    store: *types.NodeStore,
    node_id: u32,
    node: *types.SolidNode,
    allocator: std.mem.Allocator,
    tracker: *DirtyRegionTracker,
    ctx: RenderContext,
) void {
    const win = dvui.currentWindow();
    var class_spec = derive.apply(win, node);

    // Skip rendering if element has 'hidden' class
    if (class_spec.hidden) {
        node.markRendered();
        return;
    }

    if (class_spec.transition.enabled or node.transition_state.enabled) {
        transitions.updateNode(win, store, node, &class_spec);
    }

    const scale = effectiveNodeScale(ctx, node);
    if (shouldSkipTinyScaledNode(ctx, node, scale)) {
        node.markRendered();
        return;
    }

    if (dvui.snapToPixels()) {
        if (scale.sx != 1.0 or scale.sy != 1.0) {
            const old_snap = dvui.snapToPixelsSet(false);
            defer _ = dvui.snapToPixelsSet(old_snap);
        }
    }

    if (node.isInteractive() or nodeHasAccessibilityProps(node)) {
        renderInteractiveElement(runtime, event_ring, store, node_id, node, allocator, class_spec, tracker, ctx);
    } else {
        renderNonInteractiveElement(runtime, event_ring, store, node_id, node, allocator, class_spec, tracker, ctx);
    }
}

fn renderElementBody(
    runtime: *RenderRuntime,
    event_ring: ?*events.EventRing,
    store: *types.NodeStore,
    node_id: u32,
    node: *types.SolidNode,
    allocator: std.mem.Allocator,
    class_spec: tailwind.ClassSpec,
    tracker: *DirtyRegionTracker,
    ctx: RenderContext,
) void {
    if (isContainerTag(node.tag)) {
        renderContainer(runtime, event_ring, store, node, allocator, class_spec, tracker, ctx);
        node.markRendered();
        return;
    }
    if (std.mem.eql(u8, node.tag, "button")) {
        renderButton(runtime, event_ring, store, node_id, node, allocator, class_spec, tracker, ctx);
        node.markRendered();
        return;
    }
    if (std.mem.eql(u8, node.tag, "input")) {
        renderInput(runtime, event_ring, store, node_id, node, class_spec, ctx);
        node.markRendered();
        return;
    }
    if (std.mem.eql(u8, node.tag, "slider")) {
        renderSlider(runtime, event_ring, store, node_id, node, class_spec, ctx);
        node.markRendered();
        return;
    }
    if (std.mem.eql(u8, node.tag, "image")) {
        renderImage(runtime, event_ring, store, node_id, node, class_spec, allocator, tracker, ctx);
        node.markRendered();
        return;
    }
    if (std.mem.eql(u8, node.tag, "icon")) {
        renderIcon(runtime, event_ring, store, node_id, node, class_spec, allocator, tracker, ctx);
        node.markRendered();
        return;
    }
    if (std.mem.eql(u8, node.tag, "p")) {
        renderParagraph(runtime, event_ring, store, node_id, node, allocator, class_spec, null, tracker, ctx);
        node.markRendered();
        return;
    }
    if (std.mem.eql(u8, node.tag, "h1")) {
        renderParagraph(runtime, event_ring, store, node_id, node, allocator, class_spec, .title, tracker, ctx);
        node.markRendered();
        return;
    }
    if (std.mem.eql(u8, node.tag, "h2")) {
        renderParagraph(runtime, event_ring, store, node_id, node, allocator, class_spec, .title_1, tracker, ctx);
        node.markRendered();
        return;
    }
    if (std.mem.eql(u8, node.tag, "h3")) {
        renderParagraph(runtime, event_ring, store, node_id, node, allocator, class_spec, .title_2, tracker, ctx);
        node.markRendered();
        return;
    }
    renderGeneric(runtime, event_ring, store, node, allocator, class_spec, tracker, ctx);
    node.markRendered();
}

fn renderInteractiveElement(
    runtime: *RenderRuntime,
    event_ring: ?*events.EventRing,
    store: *types.NodeStore,
    node_id: u32,
    node: *types.SolidNode,
    allocator: std.mem.Allocator,
    class_spec: tailwind.ClassSpec,
    tracker: *DirtyRegionTracker,
    ctx: RenderContext,
) void {
    // Placeholder: today interactive and non-interactive elements use the same DVUI path.
    // This wrapper marks the split point for routing to DVUI widgets to preserve focus/input.
    renderElementBody(runtime, event_ring, store, node_id, node, allocator, class_spec, tracker, ctx);
}

fn renderNonInteractiveElement(
    runtime: *RenderRuntime,
    event_ring: ?*events.EventRing,
    store: *types.NodeStore,
    node_id: u32,
    node: *types.SolidNode,
    allocator: std.mem.Allocator,
    class_spec: tailwind.ClassSpec,
    tracker: *DirtyRegionTracker,
    ctx: RenderContext,
) void {
    if (shouldDirectDraw(node)) {
        renderNonInteractiveDirect(runtime, event_ring, store, node_id, node, allocator, class_spec, tracker, ctx);
        return;
    }

    renderElementBody(runtime, event_ring, store, node_id, node, allocator, class_spec, tracker, ctx);
}

fn renderContainer(
    runtime: *RenderRuntime,
    event_ring: ?*events.EventRing,
    store: *types.NodeStore,
    node: *types.SolidNode,
    allocator: std.mem.Allocator,
    class_spec: tailwind.ClassSpec,
    tracker: *DirtyRegionTracker,
    ctx: RenderContext,
) void {
    renderContainerNormal(runtime, event_ring, store, node, allocator, class_spec, tracker, ctx);
}

fn renderContainerNormal(
    runtime: *RenderRuntime,
    event_ring: ?*events.EventRing,
    store: *types.NodeStore,
    node: *types.SolidNode,
    allocator: std.mem.Allocator,
    class_spec: tailwind.ClassSpec,
    tracker: *DirtyRegionTracker,
    ctx: RenderContext,
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
    // Ensure a background color is present for container nodes.
    if (class_spec.background) |bg_ref| {
        const bg = tailwind.resolveColor(dvui.currentWindow(), bg_ref);
        if (node.visual.background == null) {
            node.visual.background = dvuiColorToPacked(bg);
        }
    }

    var viewport_opt: ?types.Rect = null;
    if (rect_opt) |rect| {
        // Draw background ourselves so containers always show their fill.
        var bg_start_ns: i128 = 0;
        if (runtime.timings != null) {
            bg_start_ns = std.time.nanoTimestamp();
        }
        renderCachedOrDirectBackground(node, rect, ctx, allocator, tailwind.resolveColorOpt(dvui.currentWindow(), class_spec.background));
        if (runtime.timings) |timings| {
            timings.draw_bg_ns += std.time.nanoTimestamp() - bg_start_ns;
        }
        viewport_opt = node.layout.child_rect orelse rect;
    }

    const tab_info = focus.tabIndexForNode(store, node);

    var options = dvui.Options{
        .name = "solid-div",
        .background = false,
        .expand = .none,
        .id_extra = nodeIdExtra(node.id),
    };
    const scale = effectiveNodeScale(ctx, node);
    style_apply.applyToOptions(dvui.currentWindow(), &class_spec, &options);
    style_apply.resolveFont(&class_spec, &options);
    options.margin = dvui.Rect{};
    options.background = false;
    const visual_eff = transitions.effectiveVisual(node);
    applyVisualPropsToOptions(visual_eff, &options);
    applyBorderColorToOptions(node, visual_eff, &options);
    applyLayoutScaleToOptions(node, &options);
    applyTransformScaleToOptions(scale, &options);
    applyAccessibilityOptions(node, &options, .generic_container);
    if (rect_opt) |rect| {
        const bounds = nodeBoundsInContext(ctx, node, rect);
        options.rect = physicalToDvuiRect(rectToParentLocal(bounds, ctx.origin));
        options.expand = .none;
        if (options.rotation == null) {
            options.rotation = transitions.effectiveTransform(node).rotation;
        }
    }

    var box = dvui.BoxWidget.init(@src(), .{}, options);
    box.install();
    defer box.deinit();
    applyAccessibilityState(node, box.data());

    if (tab_info.focusable and runtime.allowFocusRegistration()) {
        dvui.tabIndexSet(box.data().id, tab_info.tab_index);
        focus.registerFocusable(store, node, box.data());
    }

    if (runtime.input_enabled_state) {
        if (node.hasListenerKind(.pointerdown) or node.hasListenerKind(.pointerup)) {
            const rect = box.data().borderRectScale().r;
            for (dvui.events()) |*event| {
                if (!pointerEventAllowed(runtime, node.id, box.data().id, event)) continue;
                if (!dvui.eventMatch(event, .{ .id = box.data().id, .r = rect })) continue;
                switch (event.evt) {
                    .mouse => |mouse| switch (mouse.action) {
                        .press => {
                            if (mouse.button.pointer() and node.hasListenerKind(.pointerdown)) {
                                pushPointerEvent(event_ring, .pointerdown, node.id, mouse);
                            }
                        },
                        .release => {
                            if (mouse.button.pointer() and node.hasListenerKind(.pointerup)) {
                                pushPointerEvent(event_ring, .pointerup, node.id, mouse);
                            }
                        },
                        else => {},
                    },
                    else => {},
                }
            }
        }
    }

    var scroll_session = beginScrollSession(runtime, node, viewport_opt);
    if (scroll_session) |*session| {
        _ = commitScrollSession(store, node, session);
    }

    const child_ctx = ctxForChildren(ctx, node, true);
    renderChildrenOrdered(runtime, event_ring, store, node, allocator, tracker, child_ctx, false);

    if (scroll_session) |*session| {
        _ = interaction.renderScrollBars(runtime, node, session.viewport, &session.info, session.scroll_id, scale.uniform);
        _ = commitScrollSession(store, node, session);
    }

    node.markRendered();
}

fn renderFlexChildren(
    runtime: *RenderRuntime,
    event_ring: ?*events.EventRing,
    store: *types.NodeStore,
    node: *types.SolidNode,
    allocator: std.mem.Allocator,
    class_spec: *const tailwind.Spec,
    tracker: *DirtyRegionTracker,
    ctx: RenderContext,
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
            const spacer_rect = spacer.data().contentRectScale().r;
            const spacer_ctx = RenderContext{
                .origin = .{ .x = spacer_rect.x, .y = spacer_rect.y },
                .clip = ctx.clip,
                .scale = ctx.scale,
                .offset = ctx.offset,
            };
            renderNode(runtime, event_ring, store, child_id, allocator, tracker, spacer_ctx);
        } else {
            renderNode(runtime, event_ring, store, child_id, allocator, tracker, ctx);
        }
        child_index += 1;
    }
}

fn renderGeneric(
    runtime: *RenderRuntime,
    event_ring: ?*events.EventRing,
    store: *types.NodeStore,
    node: *types.SolidNode,
    allocator: std.mem.Allocator,
    class_spec: tailwind.ClassSpec,
    tracker: *DirtyRegionTracker,
    ctx: RenderContext,
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

    var options = dvui.Options{
        .name = "solid-generic",
        .background = false,
        .expand = .none,
        .id_extra = nodeIdExtra(node.id),
    };
    const scale = effectiveNodeScale(ctx, node);
    style_apply.applyToOptions(dvui.currentWindow(), &class_spec, &options);
    options.margin = dvui.Rect{};
    options.background = false;
    applyLayoutScaleToOptions(node, &options);
    applyTransformScaleToOptions(scale, &options);
    if (rect_opt) |rect| {
        const bounds = nodeBoundsInContext(ctx, node, rect);
        options.rect = physicalToDvuiRect(rectToParentLocal(bounds, ctx.origin));
        options.expand = .none;
        if (options.rotation == null) {
            options.rotation = transitions.effectiveTransform(node).rotation;
        }
    }

    var box = dvui.BoxWidget.init(@src(), .{}, options);
    box.install();
    defer box.deinit();

    const child_ctx = ctxForChildren(ctx, node, true);
    renderChildrenOrdered(runtime, event_ring, store, node, allocator, tracker, child_ctx, false);
}

fn renderNonInteractiveDirect(
    runtime: *RenderRuntime,
    event_ring: ?*events.EventRing,
    store: *types.NodeStore,
    node_id: u32,
    node: *types.SolidNode,
    allocator: std.mem.Allocator,
    class_spec: tailwind.ClassSpec,
    tracker: *DirtyRegionTracker,
    ctx: RenderContext,
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
        renderElementBody(runtime, event_ring, store, node_id, node, allocator, class_spec, tracker, ctx);
        return;
    };

    if (std.mem.eql(u8, node.tag, "div")) {
        var bg_start_ns: i128 = 0;
        if (runtime.timings != null) {
            bg_start_ns = std.time.nanoTimestamp();
        }
        renderCachedOrDirectBackground(node, rect, ctx, allocator, tailwind.resolveColorOpt(dvui.currentWindow(), class_spec.background));
        if (runtime.timings) |timings| {
            timings.draw_bg_ns += std.time.nanoTimestamp() - bg_start_ns;
        }
        const child_ctx = ctxForChildren(ctx, node, false);
        renderChildrenOrdered(runtime, event_ring, store, node, allocator, tracker, child_ctx, false);
        node.markRendered();
        return;
    }

    // Fallback to DVUI path for tags without a direct draw handler.
    renderElementBody(runtime, event_ring, store, node_id, node, allocator, class_spec, tracker, ctx);
}

fn renderParagraph(
    runtime: *RenderRuntime,
    event_ring: ?*events.EventRing,
    store: *types.NodeStore,
    node_id: u32,
    node: *types.SolidNode,
    allocator: std.mem.Allocator,
    class_spec: tailwind.Spec,
    font_override: ?dvui.Options.FontStyle,
    tracker: *DirtyRegionTracker,
    ctx: RenderContext,
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

    const rect = rect_opt orelse {
        renderChildElements(runtime, event_ring, store, node, allocator, tracker, ctx);
        return;
    };

    var bg_start_ns: i128 = 0;
    if (runtime.timings != null) {
        bg_start_ns = std.time.nanoTimestamp();
    }
    renderCachedOrDirectBackground(node, rect, ctx, allocator, tailwind.resolveColorOpt(dvui.currentWindow(), class_spec.background));
    if (runtime.timings) |timings| {
        timings.draw_bg_ns += std.time.nanoTimestamp() - bg_start_ns;
    }

    var scope_options = dvui.Options{
        .name = "solid-paragraph",
        .background = false,
        .expand = .none,
        .id_extra = nodeIdExtra(node_id),
    };
    const scope_scale = effectiveNodeScale(ctx, node);
    style_apply.applyToOptions(dvui.currentWindow(), &class_spec, &scope_options);
    scope_options.margin = dvui.Rect{};
    scope_options.background = false;
    applyLayoutScaleToOptions(node, &scope_options);
    applyTransformScaleToOptions(scope_scale, &scope_options);
    {
        const bounds = nodeBoundsInContext(ctx, node, rect);
        scope_options.rect = physicalToDvuiRect(rectToParentLocal(bounds, ctx.origin));
        scope_options.expand = .none;
        if (scope_options.rotation == null) {
            scope_options.rotation = transitions.effectiveTransform(node).rotation;
        }
    }

    var scope_box = dvui.BoxWidget.init(@src(), .{}, scope_options);
    scope_box.install();
    defer scope_box.deinit();

    var text_buffer: std.ArrayList(u8) = .empty;
    defer text_buffer.deinit(allocator);

    collectText(allocator, store, node, &text_buffer);
    const trimmed = std.mem.trim(u8, text_buffer.items, " \n\r\t");
    if (trimmed.len == 0) {
        const child_ctx = ctxForChildren(ctx, node, true);
        renderChildrenOrdered(runtime, event_ring, store, node, allocator, tracker, child_ctx, true);
        return;
    }

    const content_rect = node.layout.child_rect orelse rect;
    const bounds = nodeBoundsInContext(ctx, node, content_rect);
    const natural_scale = dvui.windowNaturalScale();
    const layout_scale = if (node.layout.layout_scale != 0) node.layout.layout_scale else natural_scale;
    const t = transitions.effectiveTransform(node);
    const scale_x = @abs(ctx.scale[0] * t.scale[0]);
    const scale_y = @abs(ctx.scale[1] * t.scale[1]);
    const scale_uniform = @min(scale_x, scale_y);
    const effective_scale = layout_scale * scale_uniform;

    var options = dvui.Options{ .id_extra = nodeIdExtra(node_id) };
    style_apply.applyToOptions(dvui.currentWindow(), &class_spec, &options);
    if (font_override) |style_name| {
        options.font_style = style_name;
    }
    style_apply.resolveFont(&class_spec, &options);
    const base_font = options.fontGet();
    const font_scale = if (natural_scale != 0) effective_scale / natural_scale else 1.0;
    const draw_font = if (font_scale != 1.0) base_font.resize(base_font.size * font_scale) else base_font;

    text_wrap.computeLineBreaks(
        store.allocator,
        &node.layout.text_layout,
        trimmed,
        base_font,
        bounds.w,
        effective_scale,
        class_spec.text_wrap,
        class_spec.break_words,
    );
    const text_layout = node.layout.text_layout;
    const visual_eff = transitions.effectiveVisual(node);
    var text_start_ns: i128 = 0;
    if (runtime.timings != null) {
        text_start_ns = std.time.nanoTimestamp();
    }
    var line_index: usize = 0;
    while (line_index < text_layout.lines.items.len) : (line_index += 1) {
        const line = text_layout.lines.items[line_index];
        if (line.len == 0) continue;
        const line_text = trimmed[line.start .. line.start + line.len];
        const line_y = bounds.y + @as(f32, @floatFromInt(line_index)) * text_layout.line_height;
        var line_x = bounds.x;
        if (class_spec.text_align) |text_align| {
            switch (text_align) {
                .center => line_x += (bounds.w - line.width) / 2.0,
                .right => line_x += (bounds.w - line.width),
                else => {},
            }
        }
        const line_rect = types.Rect{
            .x = line_x,
            .y = line_y,
            .w = line.width,
            .h = text_layout.line_height,
        };
        drawTextDirect(line_rect, line_text, visual_eff, draw_font, font_scale);
    }
    if (runtime.timings) |timings| {
        timings.draw_text_ns += std.time.nanoTimestamp() - text_start_ns;
    }

    const child_ctx = ctxForChildren(ctx, node, true);
    renderChildrenOrdered(runtime, event_ring, store, node, allocator, tracker, child_ctx, true);
}

fn renderText(runtime: *RenderRuntime, store: *types.NodeStore, node: *types.SolidNode, ctx: RenderContext) void {
    const win = dvui.currentWindow();
    _ = derive.apply(win, node);
    const scale = effectiveNodeScale(ctx, node);
    if (shouldSkipTinyScaledNode(ctx, node, scale)) {
        node.markRendered();
        return;
    }
    const trimmed = std.mem.trim(u8, node.text, " \n\r\t");
    if (trimmed.len > 0) {
        var options = dvui.Options{ .id_extra = nodeIdExtra(node.id) };
        if (node.parent) |pid| {
            if (store.node(pid)) |parent| {
                var parent_spec = parent.prepareClassSpec();
                tailwind.applyHover(&parent_spec, parent.hovered);
                style_apply.applyToOptions(win, &parent_spec, &options);
                style_apply.resolveFont(&parent_spec, &options);
            }
        }
        options.margin = dvui.Rect{};
        options.border = dvui.Rect{};
        options.padding = dvui.Rect{};
        const visual_eff = transitions.effectiveVisual(node);
        applyVisualPropsToOptions(visual_eff, &options);
        applyBorderColorToOptions(node, visual_eff, &options);
        applyLayoutScaleToOptions(node, &options);
        applyTransformScaleToOptions(scale, &options);
        if (node.layout.rect) |rect| {
            const bounds = nodeBoundsInContext(ctx, node, rect);
            options.rect = physicalToDvuiRect(rectToParentLocal(bounds, ctx.origin));
            options.expand = .none;
            if (options.rotation == null) {
                options.rotation = transitions.effectiveTransform(node).rotation;
            }
        }
        applyAccessibilityOptions(node, &options, null);
        var lw = dvui.LabelWidget.initNoFmt(@src(), trimmed, .{}, options);
        lw.install();
        applyAccessibilityState(node, lw.data());
        var text_start_ns: i128 = 0;
        if (runtime.timings != null) {
            text_start_ns = std.time.nanoTimestamp();
        }
        lw.draw();
        if (runtime.timings) |timings| {
            timings.draw_text_ns += std.time.nanoTimestamp() - text_start_ns;
        }
        lw.deinit();
    }
    node.markRendered();
}

fn renderButton(
    runtime: *RenderRuntime,
    event_ring: ?*events.EventRing,
    store: *types.NodeStore,
    node_id: u32,
    node: *types.SolidNode,
    allocator: std.mem.Allocator,
    class_spec: tailwind.Spec,
    tracker: *DirtyRegionTracker,
    ctx: RenderContext,
) void {
    const text = buildText(store, node, allocator);
    const trimmed = std.mem.trim(u8, text, " \n\r\t");

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

    const scale = effectiveNodeScale(ctx, node);

    var options_base = dvui.Options{
        .id_extra = nodeIdExtra(node_id),
        .padding = dvui.Rect.all(6),
        // Respect layout positions exactly; DVUI's default button margin would offset the rect.
        .margin = dvui.Rect{},
    };
    const tab_info = focus.tabIndexForNode(store, node);
    const focus_allowed = runtime.allowFocusRegistration();
    if (tab_info.focusable and focus_allowed) {
        options_base.tab_index = tab_info.tab_index;
    }
    const visual_eff = transitions.effectiveVisual(node);
    style_apply.applyToOptions(dvui.currentWindow(), &class_spec, &options_base);
    options_base.margin = dvui.Rect{};
    style_apply.resolveFont(&class_spec, &options_base);
    applyVisualPropsToOptions(visual_eff, &options_base);
    applyBorderColorToOptions(node, visual_eff, &options_base);
    applyAccessibilityOptions(node, &options_base, null);
    if (rect_opt) |rect| {
        const bounds = nodeBoundsInContext(ctx, node, rect);
        options_base.rect = physicalToDvuiRect(rectToParentLocal(bounds, ctx.origin));
        options_base.expand = .none;
        if (options_base.rotation == null) {
            options_base.rotation = transitions.effectiveTransform(node).rotation;
        }
    }

    var options = options_base;
    applyLayoutScaleToOptions(node, &options);
    applyTransformScaleToOptions(scale, &options);

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
    if (runtime.input_enabled_state) {
        if (node.hasListenerKind(.pointerdown) or node.hasListenerKind(.pointerup)) {
            const rect = bw.data().borderRectScale().r;
            for (dvui.events()) |*event| {
                if (!pointerEventAllowed(runtime, node_id, bw.data().id, event)) continue;
                if (!dvui.eventMatch(event, .{ .id = bw.data().id, .r = rect })) continue;
                switch (event.evt) {
                    .mouse => |mouse| switch (mouse.action) {
                        .press => {
                            if (mouse.button.pointer() and node.hasListenerKind(.pointerdown)) {
                                pushPointerEvent(event_ring, .pointerdown, node_id, mouse);
                            }
                        },
                        .release => {
                            if (mouse.button.pointer() and node.hasListenerKind(.pointerup)) {
                                pushPointerEvent(event_ring, .pointerup, node_id, mouse);
                            }
                        },
                        else => {},
                    },
                    else => {},
                }
            }
        }
        bw.hover = false;
        bw.click = clickedTopmost(runtime, bw.data(), node_id, .{ .hovered = &bw.hover });
    }
    var bg_start_ns: i128 = 0;
    if (runtime.timings != null) {
        bg_start_ns = std.time.nanoTimestamp();
    }
    bw.drawBackground();
    if (runtime.timings) |timings| {
        timings.draw_bg_ns += std.time.nanoTimestamp() - bg_start_ns;
    }

    if (trimmed.len != 0) {
        const content_rs = bw.data().contentRectScale();
        const text_style = bw.style();
        const font = text_style.fontGet();
        const size_nat = font.textSize(trimmed);
        const text_w = size_nat.w * content_rs.s;
        const text_h = size_nat.h * content_rs.s;

        var text_rs = content_rs;
        if (text_w < text_rs.r.w) text_rs.r.x += (text_rs.r.w - text_w) * 0.5;
        if (text_h < text_rs.r.h) text_rs.r.y += (text_rs.r.h - text_h) * 0.5;
        text_rs.r.w = text_w;
        text_rs.r.h = text_h;

        {
            const prev_clip = dvui.clip(content_rs.r);
            defer dvui.clipSet(prev_clip);
            var text_start_ns: i128 = 0;
            if (runtime.timings != null) {
                text_start_ns = std.time.nanoTimestamp();
            }
            dvui.renderText(.{
                .font = font,
                .text = trimmed,
                .rs = text_rs,
                .color = text_style.color(.text),
                .outline_color = text_style.text_outline_color,
                .outline_thickness = text_style.text_outline_thickness,
            }) catch |err| {
                if (runtime.button_text_error_log_count < 8) {
                    runtime.button_text_error_log_count += 1;
                    log.err("button caption renderText failed node={d}: {s}", .{ node_id, @errorName(err) });
                }
            };
            if (runtime.timings) |timings| {
                timings.draw_text_ns += std.time.nanoTimestamp() - text_start_ns;
            }
        }
    }

    var focus_bg_start_ns: i128 = 0;
    if (runtime.timings != null) {
        focus_bg_start_ns = std.time.nanoTimestamp();
    }
    bw.drawFocus();
    if (runtime.timings) |timings| {
        timings.draw_bg_ns += std.time.nanoTimestamp() - focus_bg_start_ns;
    }
    const pressed = if (runtime.input_enabled_state) bw.clicked() else false;
    bw.deinit();

    if (pressed) {
        log.info("button pressed node={d} has_listener={}", .{ node_id, node.hasListenerKind(.click) });
        if (node.hasListenerKind(.click)) {
            if (event_ring) |ring| {
                const ok = ring.pushClick(node_id);
                log.info("button dispatched via ring node={d} ok={}", .{ node_id, ok });
            }
        }
    }

    renderChildElements(runtime, event_ring, store, node, allocator, tracker, ctx);
}

fn renderIcon(
    runtime: *RenderRuntime,
    event_ring: ?*events.EventRing,
    store: *types.NodeStore,
    node_id: u32,
    node: *types.SolidNode,
    class_spec: tailwind.Spec,
    allocator: std.mem.Allocator,
    tracker: *DirtyRegionTracker,
    ctx: RenderContext,
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
    const scale = effectiveNodeScale(ctx, node);
    style_apply.applyToOptions(dvui.currentWindow(), &class_spec, &options);
    options.margin = dvui.Rect{};
    style_apply.resolveFont(&class_spec, &options);
    const visual_eff = transitions.effectiveVisual(node);
    applyVisualPropsToOptions(visual_eff, &options);
    applyBorderColorToOptions(node, visual_eff, &options);
    applyLayoutScaleToOptions(node, &options);
    applyTransformScaleToOptions(scale, &options);
    applyAccessibilityOptions(node, &options, null);
    if (node.layout.rect) |rect| {
        const bounds = nodeBoundsInContext(ctx, node, rect);
        options.rect = physicalToDvuiRect(rectToParentLocal(bounds, ctx.origin));
        options.expand = .none;
        if (options.rotation == null) {
            options.rotation = transitions.effectiveTransform(node).rotation;
        }
    }

    switch (node.cached_icon) {
        .vector => |tvg_bytes| {
            const icon_name = if (src.len > 0) src else "solid-icon";
            var iw = dvui.IconWidget.init(@src(), icon_name, tvg_bytes, .{}, options);
            iw.install();
            applyAccessibilityState(node, iw.data());
            var icon_start_ns: i128 = 0;
            if (runtime.timings != null) {
                icon_start_ns = std.time.nanoTimestamp();
            }
            iw.draw();
            if (runtime.timings) |timings| {
                timings.draw_icon_ns += std.time.nanoTimestamp() - icon_start_ns;
            }
            iw.deinit();
        },
        .raster => |resource| {
            const image_source = image_loader.imageSource(resource);
            var icon_start_ns: i128 = 0;
            if (runtime.timings != null) {
                icon_start_ns = std.time.nanoTimestamp();
            }
            var wd = dvui.image(@src(), .{ .source = image_source }, options);
            applyAccessibilityState(node, &wd);
            if (runtime.timings) |timings| {
                timings.draw_icon_ns += std.time.nanoTimestamp() - icon_start_ns;
            }
        },
        .glyph => |text| {
            var lw = dvui.LabelWidget.initNoFmt(@src(), text, .{}, options);
            lw.install();
            applyAccessibilityState(node, lw.data());
            var text_start_ns: i128 = 0;
            if (runtime.timings != null) {
                text_start_ns = std.time.nanoTimestamp();
            }
            lw.draw();
            if (runtime.timings) |timings| {
                timings.draw_text_ns += std.time.nanoTimestamp() - text_start_ns;
            }
            lw.deinit();
        },
        .none, .failed => return,
    }

    renderChildElements(runtime, event_ring, store, node, allocator, tracker, ctx);
}

fn renderImage(
    runtime: *RenderRuntime,
    event_ring: ?*events.EventRing,
    store: *types.NodeStore,
    node_id: u32,
    node: *types.SolidNode,
    class_spec: tailwind.Spec,
    allocator: std.mem.Allocator,
    tracker: *DirtyRegionTracker,
    ctx: RenderContext,
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
    const scale = effectiveNodeScale(ctx, node);
    style_apply.applyToOptions(dvui.currentWindow(), &class_spec, &options);
    options.margin = dvui.Rect{};
    style_apply.resolveFont(&class_spec, &options);
    const visual_eff = transitions.effectiveVisual(node);
    applyVisualPropsToOptions(visual_eff, &options);
    applyBorderColorToOptions(node, visual_eff, &options);
    applyLayoutScaleToOptions(node, &options);
    applyTransformScaleToOptions(scale, &options);
    applyAccessibilityOptions(node, &options, null);
    if (node.layout.rect) |rect| {
        const bounds = nodeBoundsInContext(ctx, node, rect);
        options.rect = physicalToDvuiRect(rectToParentLocal(bounds, ctx.origin));
        options.expand = .none;
        if (options.rotation == null) {
            options.rotation = transitions.effectiveTransform(node).rotation;
        }
    }

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
        var bg_start_ns: i128 = 0;
        if (runtime.timings != null) {
            bg_start_ns = std.time.nanoTimestamp();
        }
        wd.borderAndBackground(.{});
        if (runtime.timings) |timings| {
            timings.draw_bg_ns += std.time.nanoTimestamp() - bg_start_ns;
        }
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
    var image_start_ns: i128 = 0;
    if (runtime.timings != null) {
        image_start_ns = std.time.nanoTimestamp();
    }
    dvui.renderImage(image_source, content_rs, render_tex_opts) catch |err| {
        log.err("Solid image render failed for node {d}: {s}", .{ node_id, @errorName(err) });
    };
    if (runtime.timings) |timings| {
        timings.draw_image_ns += std.time.nanoTimestamp() - image_start_ns;
    }
    wd.minSizeSetAndRefresh();
    wd.minSizeReportToParent();

    renderChildElements(runtime, event_ring, store, node, allocator, tracker, ctx);
}

fn renderSlider(
    runtime: *RenderRuntime,
    event_ring: ?*events.EventRing,
    store: *types.NodeStore,
    node_id: u32,
    node: *types.SolidNode,
    class_spec: tailwind.Spec,
    ctx: RenderContext,
) void {
    var options = dvui.slider_defaults.override(.{
        .name = "solid-slider",
        .id_extra = nodeIdExtra(node_id),
    });
    const scale = effectiveNodeScale(ctx, node);
    style_apply.applyToOptions(dvui.currentWindow(), &class_spec, &options);
    options.margin = dvui.Rect{};
    style_apply.resolveFont(&class_spec, &options);
    const visual_eff = transitions.effectiveVisual(node);
    applyVisualPropsToOptions(visual_eff, &options);
    applyBorderColorToOptions(node, visual_eff, &options);
    applyLayoutScaleToOptions(node, &options);
    applyTransformScaleToOptions(scale, &options);
    applyAccessibilityOptions(node, &options, .slider);
    if (node.layout.rect) |rect| {
        const bounds = nodeBoundsInContext(ctx, node, rect);
        options.rect = physicalToDvuiRect(rectToParentLocal(bounds, ctx.origin));
        options.expand = .none;
        if (options.rotation == null) {
            options.rotation = transitions.effectiveTransform(node).rotation;
        }
    }

    const tab_info = focus.tabIndexForNode(store, node);
    const focus_allowed = runtime.allowFocusRegistration();
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

    if (runtime.input_enabled_state) {
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

    if (runtime.input_enabled_state) {
        if (event_ring) |ring| {
            if (!prev_focused and focused_now and node.hasListenerKind(.focus)) {
                _ = ring.pushFocus(node_id);
            } else if (prev_focused and !focused_now and node.hasListenerKind(.blur)) {
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
            if (node.hasListenerKind(.input)) {
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
    runtime: *RenderRuntime,
    event_ring: ?*events.EventRing,
    store: *types.NodeStore,
    node_id: u32,
    node: *types.SolidNode,
    class_spec: tailwind.Spec,
    ctx: RenderContext,
) void {
    var options = dvui.Options{
        .name = "solid-input",
        .id_extra = nodeIdExtra(node_id),
        .background = true,
    };
    const scale = effectiveNodeScale(ctx, node);
    style_apply.applyToOptions(dvui.currentWindow(), &class_spec, &options);
    options.margin = dvui.Rect{};
    style_apply.resolveFont(&class_spec, &options);
    const visual_eff = transitions.effectiveVisual(node);
    applyVisualPropsToOptions(visual_eff, &options);
    applyBorderColorToOptions(node, visual_eff, &options);
    applyLayoutScaleToOptions(node, &options);
    applyTransformScaleToOptions(scale, &options);
    applyAccessibilityOptions(node, &options, .text_input);
    if (node.layout.rect) |rect| {
        const bounds = nodeBoundsInContext(ctx, node, rect);
        options.rect = physicalToDvuiRect(rectToParentLocal(bounds, ctx.origin));
        options.expand = .none;
        if (options.rotation == null) {
            options.rotation = transitions.effectiveTransform(node).rotation;
        }
    }

    const tab_info = focus.tabIndexForNode(store, node);
    const focus_allowed = runtime.allowFocusRegistration();

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

    if (runtime.input_enabled_state) {
        if (tab_info.focusable and focus_allowed) {
            dvui.tabIndexSet(wd.id, tab_info.tab_index);
        }

        var hovered = false;
        _ = clickedExTopmost(runtime, wd, node_id, .{ .hovered = &hovered, .hover_cursor = class_spec.cursor orelse .ibeam });

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

    if (runtime.input_enabled_state) {
        if (event_ring) |ring| {
            if (!prev_focused and focused_now and node.hasListenerKind(.focus)) {
                _ = ring.pushFocus(node_id);
            } else if (prev_focused and !focused_now and node.hasListenerKind(.blur)) {
                _ = ring.pushBlur(node_id);
            }

            if (text_changed and node.hasListenerKind(.input)) {
                const payload = input_state.currentText();
                _ = ring.pushInput(node_id, payload);
            }
            if (enter_pressed and node.hasListenerKind(.enter)) {
                const payload = input_state.currentText();
                _ = ring.push(.enter, node_id, payload);
            }
        }
    }
}

fn renderChildElements(
    runtime: *RenderRuntime,
    event_ring: ?*events.EventRing,
    store: *types.NodeStore,
    node: *types.SolidNode,
    allocator: std.mem.Allocator,
    tracker: *DirtyRegionTracker,
    ctx: RenderContext,
) void {
    const child_ctx = ctxForChildren(ctx, node, false);
    renderChildrenOrdered(runtime, event_ring, store, node, allocator, tracker, child_ctx, true);
}

pub fn renderChildrenOrdered(
    runtime: *RenderRuntime,
    event_ring: ?*events.EventRing,
    store: *types.NodeStore,
    node: *types.SolidNode,
    allocator: std.mem.Allocator,
    tracker: *DirtyRegionTracker,
    ctx: RenderContext,
    skip_text: bool,
) void {
    if (node.children.items.len == 0) return;

    var prev_clip: ?dvui.Rect.Physical = null;
    if (node.visual.clip_children) {
        if (ctx.clip) |clip| {
            prev_clip = dvui.clip(.{ .x = clip.x, .y = clip.y, .w = clip.w, .h = clip.h });
        }
    }
    defer if (prev_clip) |prev| dvui.clipSet(prev);

    var any_z = false;
    for (node.children.items) |child_id| {
        const child = store.node(child_id) orelse continue;
        if (skip_text and child.kind == .text) continue;
        var child_spec = child.prepareClassSpec();
        tailwind.applyHover(&child_spec, child.hovered);
        if (child_spec.z_index != 0) any_z = true;
    }

    if (!any_z) {
        for (node.children.items) |child_id| {
            const child = store.node(child_id) orelse continue;
            if (skip_text and child.kind == .text) continue;
            renderNode(runtime, event_ring, store, child_id, allocator, tracker, ctx);
        }
        return;
    }

    var ordered: std.ArrayList(OrderedNode) = .empty;
    defer ordered.deinit(allocator);

    for (node.children.items, 0..) |child_id, order_index| {
        const child = store.node(child_id) orelse continue;
        if (skip_text and child.kind == .text) continue;
        var child_spec = child.prepareClassSpec();
        tailwind.applyHover(&child_spec, child.hovered);
        const z_index = child_spec.z_index;
        ordered.append(allocator, .{
            .id = child_id,
            .z_index = z_index,
            .order = order_index,
        }) catch {};
    }

    if (ordered.items.len == 0) return;
    sortOrderedNodes(ordered.items);

    for (ordered.items) |entry| {
        renderNode(runtime, event_ring, store, entry.id, allocator, tracker, ctx);
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

test "applyTransformScaleToOptions scales font and metrics" {
    var options = dvui.Options{
        .padding = dvui.Rect{ .x = 2, .y = 3, .w = 4, .h = 5 },
        .corner_radius = dvui.Rect.all(6),
        .text_outline_thickness = 2,
        .font = dvui.Font{ .size = 10, .id = dvui.Font.default_font_id },
    };

    applyTransformScaleToOptions(.{ .sx = 2, .sy = 3, .uniform = 2 }, &options);

    try std.testing.expectEqual(dvui.Rect{ .x = 4, .y = 9, .w = 8, .h = 15 }, options.padding.?);
    try std.testing.expectEqual(dvui.Rect.all(12), options.corner_radius.?);
    try std.testing.expectEqual(@as(f32, 4), options.text_outline_thickness.?);
    try std.testing.expectEqual(@as(f32, 20), options.font.?.size);
}

test "commitScrollSession updates offset and shifts child layout" {
    var store: types.NodeStore = undefined;
    try store.init(std.testing.allocator);
    defer store.deinit();

    try store.upsertElement(1, "div");
    try store.insert(0, 1, null);
    try store.upsertElement(2, "div");
    try store.insert(1, 2, null);

    const scroll_node = store.node(1) orelse return error.TestUnexpectedResult;
    const child_node = store.node(2) orelse return error.TestUnexpectedResult;

    scroll_node.scroll.class_enabled = true;
    scroll_node.scroll.class_x = false;
    scroll_node.scroll.class_y = true;
    scroll_node.scroll.offset_y = 0;
    child_node.layout.rect = .{ .x = 20, .y = 40, .w = 80, .h = 30 };
    child_node.layout.child_rect = .{ .x = 24, .y = 44, .w = 72, .h = 22 };

    var session = ScrollSession{
        .viewport = .{ .x = 0, .y = 0, .w = 120, .h = 90 },
        .scroll_id = undefined,
        .info = .{
            .horizontal = .none,
            .vertical = .given,
            .virtual_size = .{ .w = 120, .h = 280 },
            .viewport = .{ .x = 0, .y = 28, .w = 120, .h = 90 },
        },
    };

    try std.testing.expect(commitScrollSession(&store, scroll_node, &session));
    try std.testing.expectApproxEqAbs(@as(f32, 28), scroll_node.scroll.offset_y, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 12), child_node.layout.rect.?.y, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 16), child_node.layout.child_rect.?.y, 0.001);
    try std.testing.expect(!commitScrollSession(&store, scroll_node, &session));
}
