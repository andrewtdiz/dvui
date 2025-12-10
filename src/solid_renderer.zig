const std = @import("std");

const dvui = @import("dvui");

const image_loader = @import("jsruntime/image_loader.zig");
const jsruntime = @import("jsruntime/mod.zig");
const tailwind_dvui = @import("jsruntime/solid/dvui_tailwind.zig");
const jsc_bridge = @import("jsruntime/solid/jsc.zig");
const tailwind = @import("jsruntime/solid/tailwind.zig");
const types = @import("jsruntime/solid/types.zig");

const log = std.log.scoped(.solid_bridge);

var gizmo_override_rect: ?types.GizmoRect = null;
var gizmo_rect_pending: ?types.GizmoRect = null;

fn dvuiColorToPacked(color: dvui.Color) types.PackedColor {
    const value: u32 = (@as(u32, color.r) << 24) | (@as(u32, color.g) << 16) | (@as(u32, color.b) << 8) | @as(u32, color.a);
    return .{ .value = value };
}

fn rectToPhysical(rect: types.Rect) dvui.Rect.Physical {
    return .{
        .x = rect.x,
        .y = rect.y,
        .w = rect.w,
        .h = rect.h,
    };
}

fn packedColorToDvui(color: types.PackedColor, opacity: f32) dvui.Color {
    const clamped_opacity = std.math.clamp(opacity, 0.0, 1.0);
    const r: u8 = @intCast((color.value >> 24) & 0xff);
    const g: u8 = @intCast((color.value >> 16) & 0xff);
    const b: u8 = @intCast((color.value >> 8) & 0xff);
    const a_base: u8 = @intCast(color.value & 0xff);
    const final_a: f32 = @as(f32, @floatFromInt(a_base)) / 255.0 * clamped_opacity * 255.0;
    const a: u8 = @intFromFloat(std.math.clamp(final_a, 0.0, 255.0));
    return .{ .r = r, .g = g, .b = b, .a = a };
}

fn applyVisualToOptions(node: *const types.SolidNode, options: *dvui.Options) void {
    const opacity = node.visual.opacity;
    if (node.visual.background) |bg| {
        const color = packedColorToDvui(bg, opacity);
        options.background = true;
        options.color_fill = color;
        options.color_fill_hover = color;
        options.color_fill_press = color;
    }
    if (node.visual.text_color) |tc| {
        const color = packedColorToDvui(tc, opacity);
        options.color_text = color;
        options.color_text_hover = color;
        options.color_text_press = color;
    }
    if (node.visual.corner_radius != 0) {
        options.corner_radius = dvui.Rect.all(node.visual.corner_radius);
    }
}

fn applyClassSpecToVisual(node: *types.SolidNode, spec: *const tailwind.Spec) void {
    if (spec.background) |bg| {
        node.visual.background = dvuiColorToPacked(bg);
    }
    if (spec.text) |tc| {
        node.visual.text_color = dvuiColorToPacked(tc);
    }
    if (spec.corner_radius) |radius| {
        node.visual.corner_radius = radius;
    }
}

fn drawRectDirect(rect: types.Rect, visual: types.VisualProps, allocator: std.mem.Allocator, fallback_bg: ?dvui.Color) void {
    const bg = visual.background orelse blk: {
        if (fallback_bg) |c| break :blk dvuiColorToPacked(c);
        return;
    };
    var builder = dvui.Triangles.Builder.init(allocator, 4, 6) catch return;
    defer builder.deinit(allocator);

    const color = packedColorToDvui(bg, visual.opacity);
    const pma = dvui.Color.PMA.fromColor(color);
    const phys = rectToPhysical(rect);
    builder.appendVertex(.{ .pos = .{ .x = phys.x, .y = phys.y }, .col = pma });
    builder.appendVertex(.{ .pos = .{ .x = phys.x + phys.w, .y = phys.y }, .col = pma });
    builder.appendVertex(.{ .pos = .{ .x = phys.x + phys.w, .y = phys.y + phys.h }, .col = pma });
    builder.appendVertex(.{ .pos = .{ .x = phys.x, .y = phys.y + phys.h }, .col = pma });
    builder.appendTriangles(&.{ 0, 1, 2, 0, 2, 3 });

    const tris = builder.build();
    dvui.renderTriangles(tris, null) catch {};
}

fn drawTextDirect(rect: types.Rect, text: []const u8, visual: types.VisualProps, font_style: ?dvui.Options.FontStyle) void {
    const trimmed = std.mem.trim(u8, text, " \n\r\t");
    if (trimmed.len == 0) return;

    var options = dvui.Options{};
    if (font_style) |style| {
        options.font_style = style;
    }
    const font = options.fontGet();
    const color = if (visual.text_color) |tc|
        packedColorToDvui(tc, visual.opacity)
    else
        packedColorToDvui(.{ .value = 0xffffffff }, visual.opacity);

    const phys = rectToPhysical(rect);
    const rs = dvui.RectScale{
        .r = phys,
        .s = 1.0,
    };
    const text_opts = dvui.render.TextOptions{
        .font = font,
        .text = trimmed,
        .rs = rs,
        .color = color,
    };
    dvui.renderText(text_opts) catch {};
}

fn transformedRect(node: *const types.SolidNode, base: ?types.Rect) ?types.Rect {
    const rect = base orelse return null;
    // Apply basic scale/translation. Rotation remains to be added for direct-draw path.
    const sx = node.transform.scale[0];
    const sy = node.transform.scale[1];
    const tx = node.transform.translation[0];
    const ty = node.transform.translation[1];
    return types.Rect{
        .x = rect.x * sx + tx,
        .y = rect.y * sy + ty,
        .w = rect.w * sx,
        .h = rect.h * sy,
    };
}

fn flushSolidOps(runtime: ?*jsruntime.JSRuntime, store: *types.NodeStore) void {
    const rt = runtime orelse return;
    const drain_limit: usize = 4;
    var pass: usize = 0;
    while (pass < drain_limit) : (pass += 1) {
        const applied = jsc_bridge.syncOps(rt, store) catch |err| {
            log.err("Solid bridge sync failed: {s}", .{@errorName(err)});
            return;
        };
        if (!applied) break;
    }
}

pub fn setGizmoRectOverride(rect: ?types.GizmoRect) void {
    gizmo_override_rect = rect;
}

pub fn takeGizmoRectUpdate() ?types.GizmoRect {
    const next = gizmo_rect_pending;
    gizmo_rect_pending = null;
    return next;
}

fn updateLayouts(store: *types.NodeStore) void {
    const win = dvui.currentWindow();
    const root_rect = types.Rect{
        .x = 0,
        .y = 0,
        .w = win.rect_pixels.w,
        .h = win.rect_pixels.h,
    };
    const root = store.node(0) orelse return;
    layoutNode(store, root, root_rect);
}

fn sideValue(value: ?f32) f32 {
    return value orelse 0;
}

fn layoutNode(store: *types.NodeStore, node: *types.SolidNode, parent_rect: types.Rect) void {
    var rect = parent_rect;
    const spec = node.prepareClassSpec();

    // Apply margins to shrink available rect.
    const margin_left = sideValue(spec.margin.left);
    const margin_right = sideValue(spec.margin.right);
    const margin_top = sideValue(spec.margin.top);
    const margin_bottom = sideValue(spec.margin.bottom);

    rect.x += margin_left;
    rect.y += margin_top;
    rect.w = @max(0.0, rect.w - (margin_left + margin_right));
    rect.h = @max(0.0, rect.h - (margin_top + margin_bottom));

    if (spec.width) |w| {
        switch (w) {
            .full => rect.w = @max(0.0, parent_rect.w - (margin_left + margin_right)),
            .pixels => |px| rect.w = px,
        }
    }
    if (spec.height) |h| {
        switch (h) {
            .full => rect.h = @max(0.0, parent_rect.h - (margin_top + margin_bottom)),
            .pixels => |px| rect.h = px,
        }
    }

    if (node.kind == .text) {
        const measured = measureText(node.text);
        if (rect.w == 0) rect.w = measured.w;
        if (rect.h == 0) rect.h = measured.h;
    }
    if (rect.w == 0 or rect.h == 0) {
        const intrinsic = measureNodeSize(store, node, .{ .w = rect.w, .h = rect.h });
        if (rect.w == 0) rect.w = intrinsic.w;
        if (rect.h == 0) rect.h = intrinsic.h;
    }

    node.layout.rect = rect;
    node.layout.version = store.change_counter;

    // Child rect accounts for padding.
    const pad_left = sideValue(spec.padding.left);
    const pad_right = sideValue(spec.padding.right);
    const pad_top = sideValue(spec.padding.top);
    const pad_bottom = sideValue(spec.padding.bottom);

    var child_rect = rect;
    child_rect.x += pad_left;
    child_rect.y += pad_top;
    child_rect.w = @max(0.0, child_rect.w - (pad_left + pad_right));
    child_rect.h = @max(0.0, child_rect.h - (pad_top + pad_bottom));

    if (spec.is_flex) {
        layoutFlexChildren(store, node, child_rect, spec);
    } else {
        for (node.children.items) |child_id| {
            if (store.node(child_id)) |child| {
                layoutNode(store, child, child_rect);
            }
        }
    }
}

fn measureText(text: []const u8) types.Size {
    const trimmed = std.mem.trim(u8, text, " \n\r\t");
    if (trimmed.len == 0) return .{};
    const font = (dvui.Options{}).fontGet();
    const size = font.textSize(trimmed);
    return .{ .w = size.w, .h = size.h };
}

fn measureNodeSize(store: *types.NodeStore, node: *types.SolidNode, parent_available: types.Size) types.Size {
    const spec = node.prepareClassSpec();
    var size = types.Size{};
    if (spec.width) |w| {
        size.w = switch (w) {
            .full => parent_available.w,
            .pixels => |px| px,
        };
    }
    if (spec.height) |h| {
        size.h = switch (h) {
            .full => parent_available.h,
            .pixels => |px| px,
        };
    }
    if (node.kind == .text) {
        const measured = measureText(node.text);
        if (size.w == 0) size.w = measured.w;
        if (size.h == 0) size.h = measured.h;
    }
    if ((size.w == 0 or size.h == 0) and node.kind == .element) {
        for (node.children.items) |child_id| {
            if (store.node(child_id)) |child| {
                if (child.kind == .text) {
                    const text_size = measureText(child.text);
                    if (size.w == 0) size.w = text_size.w;
                    if (size.h == 0) size.h = text_size.h;
                    break;
                }
            }
        }
        if (size.w == 0 or size.h == 0) {
            // Fallback: measure first child element recursively for intrinsic sizing.
            for (node.children.items) |child_id| {
                if (store.node(child_id)) |child| {
                    const child_size = measureNodeSize(store, child, parent_available);
                    if (size.w == 0) size.w = child_size.w;
                    if (size.h == 0) size.h = child_size.h;
                    break;
                }
            }
        }
        // Add padding to intrinsic size.
        const pad_left = sideValue(spec.padding.left);
        const pad_right = sideValue(spec.padding.right);
        const pad_top = sideValue(spec.padding.top);
        const pad_bottom = sideValue(spec.padding.bottom);
        size.w += pad_left + pad_right;
        size.h += pad_top + pad_bottom;
    }
    return size;
}

fn layoutFlexChildren(store: *types.NodeStore, node: *types.SolidNode, area: types.Rect, spec: tailwind.Spec) void {
    const dir = spec.direction orelse .horizontal;
    const gap_main = switch (dir) {
        .horizontal => spec.gap_col,
        .vertical => spec.gap_row,
    } orelse 0;

    var child_sizes: std.ArrayListUnmanaged(types.Size) = .{};
    defer child_sizes.deinit(std.heap.page_allocator);

    const available_size = types.Size{ .w = area.w, .h = area.h };
    var total_main: f32 = 0;
    var max_cross: f32 = 0;

    for (node.children.items) |child_id| {
        if (store.node(child_id)) |child| {
            const child_size = measureNodeSize(store, child, available_size);
            child_sizes.append(std.heap.page_allocator, child_size) catch {};
            const main = switch (dir) {
                .horizontal => child_size.w,
                .vertical => child_size.h,
            };
            const cross = switch (dir) {
                .horizontal => child_size.h,
                .vertical => child_size.w,
            };
            total_main += main;
            if (cross > max_cross) max_cross = cross;
        } else {
            child_sizes.append(std.heap.page_allocator, .{}) catch {};
        }
    }

    if (child_sizes.items.len > 0) {
        total_main += gap_main * @as(f32, @floatFromInt(child_sizes.items.len - 1));
    }

    const available_main: f32 = switch (dir) {
        .horizontal => area.w,
        .vertical => area.h,
    };
    var cursor: f32 = area.x;
    if (dir == .vertical) cursor = area.y;

    const remaining = available_main - total_main;
    if (remaining > 0) {
        switch (spec.justify orelse .start) {
            .center => cursor += remaining / 2.0,
            .end => cursor += remaining,
            else => {},
        }
    }

    for (node.children.items, 0..) |child_id, idx| {
        const child_size = if (idx < child_sizes.items.len) child_sizes.items[idx] else types.Size{};
        const child_ptr = store.node(child_id) orelse continue;

        var child_rect = types.Rect{};
        switch (dir) {
            .horizontal => {
                child_rect.x = cursor;
                child_rect.y = switch (spec.align_items orelse .start) {
                    .center => area.y + (area.h - child_size.h) / 2.0,
                    .end => area.y + (area.h - child_size.h),
                    else => area.y,
                };
                child_rect.w = child_size.w;
                child_rect.h = child_size.h;
                cursor += child_rect.w + gap_main;
            },
            .vertical => {
                child_rect.x = switch (spec.align_items orelse .start) {
                    .center => area.x + (area.w - child_size.w) / 2.0,
                    .end => area.x + (area.w - child_size.w),
                    else => area.x,
                };
                child_rect.y = cursor;
                child_rect.w = child_size.w;
                child_rect.h = child_size.h;
                cursor += child_rect.h + gap_main;
            },
        }

        layoutNode(store, child_ptr, child_rect);
    }
}

pub fn render(runtime: ?*jsruntime.JSRuntime, store: *types.NodeStore) bool {
    const root = store.node(0) orelse return false;

    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const scratch = arena.allocator();

    updateLayouts(store);

    if (root.children.items.len == 0) {
        return false;
    }

    for (root.children.items) |child_id| {
        renderNode(runtime, store, child_id, scratch);
    }
    return true;
}

fn renderNode(
    runtime: ?*jsruntime.JSRuntime,
    store: *types.NodeStore,
    node_id: u32,
    allocator: std.mem.Allocator,
) void {
    const node = store.node(node_id) orelse return;
    switch (node.kind) {
        .root => {
            for (node.children.items) |child_id| {
                renderNode(runtime, store, child_id, allocator);
            }
            node.markRendered();
        },
        .slot => {
            for (node.children.items) |child_id| {
                renderNode(runtime, store, child_id, allocator);
            }
            node.markRendered();
        },
        .text => renderText(store, node),
        .element => renderElement(runtime, store, node_id, node, allocator),
    }
}

fn renderElement(
    runtime: ?*jsruntime.JSRuntime,
    store: *types.NodeStore,
    node_id: u32,
    node: *types.SolidNode,
    allocator: std.mem.Allocator,
) void {
    // Always render - DVUI is immediate-mode and requires widget creation every frame.
    // The previous dirty-tracking optimization caused the black screen bug.
    const class_spec = node.prepareClassSpec();
    applyClassSpecToVisual(node, &class_spec);
    if (node.isInteractive()) {
        renderInteractiveElement(runtime, store, node_id, node, allocator, class_spec);
    } else {
        renderNonInteractiveElement(runtime, store, node_id, node, allocator, class_spec);
    }
}

fn renderElementBody(
    runtime: ?*jsruntime.JSRuntime,
    store: *types.NodeStore,
    node_id: u32,
    node: *types.SolidNode,
    allocator: std.mem.Allocator,
    class_spec: tailwind.ClassSpec,
) void {
    if (std.mem.eql(u8, node.tag, "div")) {
        renderContainer(runtime, store, node, allocator, class_spec);
        node.markRendered();
        return;
    }
    if (std.mem.eql(u8, node.tag, "button")) {
        renderButton(runtime, store, node_id, node, allocator, class_spec);
        node.markRendered();
        return;
    }
    if (std.mem.eql(u8, node.tag, "input")) {
        renderInput(runtime, store, node_id, node, class_spec);
        node.markRendered();
        return;
    }
    if (std.mem.eql(u8, node.tag, "image")) {
        renderImage(runtime, node_id, node, class_spec);
        node.markRendered();
        return;
    }
    if (std.mem.eql(u8, node.tag, "gizmo")) {
        renderGizmo(runtime, store, node_id, node, class_spec);
        node.markRendered();
        return;
    }
    if (std.mem.eql(u8, node.tag, "p")) {
        renderParagraph(runtime, store, node_id, node, allocator, class_spec, null);
        node.markRendered();
        return;
    }
    if (std.mem.eql(u8, node.tag, "h1")) {
        renderParagraph(runtime, store, node_id, node, allocator, class_spec, .title);
        node.markRendered();
        return;
    }
    if (std.mem.eql(u8, node.tag, "h2")) {
        renderParagraph(runtime, store, node_id, node, allocator, class_spec, .title_1);
        node.markRendered();
        return;
    }
    if (std.mem.eql(u8, node.tag, "h3")) {
        renderParagraph(runtime, store, node_id, node, allocator, class_spec, .title_2);
        node.markRendered();
        return;
    }
    renderGeneric(runtime, store, node, allocator);
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
) void {
    _ = node_id;
    var text_buffer: std.ArrayList(u8) = .empty;
    defer text_buffer.deinit(allocator);

    // Draw paragraph background if present.
    drawRectDirect(rect, node.visual, allocator, class_spec.background);

    collectText(allocator, store, node, &text_buffer);
    if (text_buffer.items.len > 0) {
        const trimmed = std.mem.trim(u8, text_buffer.items, " \n\r\t");
        if (trimmed.len > 0) {
            var options = dvui.Options{};
            tailwind_dvui.applyToOptions(&class_spec, &options);
            if (font_override) |style_name| {
                options.font_style = style_name;
            }
            drawTextDirect(rect, trimmed, node.visual, options.font_style);
        }
    }

    for (node.children.items) |child_id| {
        renderNode(runtime, store, child_id, allocator);
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
) void {
    // Placeholder: today interactive and non-interactive elements use the same DVUI path.
    // This wrapper marks the split point for routing to DVUI widgets to preserve focus/input.
    renderElementBody(runtime, store, node_id, node, allocator, class_spec);
}

fn renderNonInteractiveElement(
    runtime: ?*jsruntime.JSRuntime,
    store: *types.NodeStore,
    node_id: u32,
    node: *types.SolidNode,
    allocator: std.mem.Allocator,
    class_spec: tailwind.ClassSpec,
) void {
    // TEMPORARY: Route all non-interactive elements through DVUI widgets for stability.
    // The direct-draw path (drawRectDirect, drawTextDirect) may be causing crashes.
    // Once DVUI path is verified stable, we can re-enable direct draw for performance.
    renderElementBody(runtime, store, node_id, node, allocator, class_spec);
}

fn renderContainer(
    runtime: ?*jsruntime.JSRuntime,
    store: *types.NodeStore,
    node: *types.SolidNode,
    allocator: std.mem.Allocator,
    class_spec: tailwind.ClassSpec,
) void {
    var options = dvui.Options{
        .name = "solid-div",
        .background = false,
        .expand = .none,
        .id_extra = nodeIdExtra(node.id),
    };
    tailwind_dvui.applyToOptions(&class_spec, &options);
    applyVisualToOptions(node, &options);

    if (tailwind_dvui.isFlex(&class_spec)) {
        const flex_init = tailwind_dvui.buildFlexOptions(&class_spec);
        var flexbox_widget = dvui.flexbox(@src(), flex_init, options);
        defer flexbox_widget.deinit();
        renderFlexChildren(runtime, store, node, allocator, &class_spec);
    } else {
        var box = dvui.box(@src(), .{}, options);
        defer box.deinit();
        for (node.children.items) |child_id| {
            renderNode(runtime, store, child_id, allocator);
        }
    }
}

fn renderFlexChildren(
    runtime: ?*jsruntime.JSRuntime,
    store: *types.NodeStore,
    node: *types.SolidNode,
    allocator: std.mem.Allocator,
    class_spec: *const tailwind.Spec,
) void {
    const direction = tailwind_dvui.flexDirection(class_spec);
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
            renderNode(runtime, store, child_id, allocator);
        } else {
            renderNode(runtime, store, child_id, allocator);
        }
        child_index += 1;
    }
}

fn renderGeneric(
    runtime: ?*jsruntime.JSRuntime,
    store: *types.NodeStore,
    node: *types.SolidNode,
    allocator: std.mem.Allocator,
) void {
    for (node.children.items) |child_id| {
        renderNode(runtime, store, child_id, allocator);
    }
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
) void {
    var text_buffer: std.ArrayList(u8) = .empty;
    defer text_buffer.deinit(allocator);

    collectText(allocator, store, node, &text_buffer);
    if (text_buffer.items.len > 0) {
        const trimmed = std.mem.trim(u8, text_buffer.items, " \n\r\t");
        if (trimmed.len > 0) {
            var options = dvui.Options{
                .id_extra = nodeIdExtra(node_id),
            };
            tailwind_dvui.applyToOptions(&class_spec, &options);
            applyVisualToOptions(node, &options);
            if (font_override) |style_name| {
                if (options.font_style == null) {
                    options.font_style = style_name;
                }
            }
            dvui.labelNoFmt(@src(), trimmed, .{}, options);
        }
    }

    renderChildElements(runtime, store, node, allocator);
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
                tailwind_dvui.applyToOptions(&parent_spec, &options);
            }
        }
        applyVisualToOptions(node, &options);
        if (node.layout.rect) |rect| {
            options.rect = dvui.Rect{
                .x = rect.x,
                .y = rect.y,
                .w = rect.w,
                .h = rect.h,
            };
        }
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
) void {
    const text = buildText(store, node, allocator);
    const trimmed = std.mem.trim(u8, text, " \n\r\t");
    const caption = if (trimmed.len == 0) "Button" else trimmed;

    var options = dvui.Options{
        .id_extra = nodeIdExtra(node_id),
        .padding = dvui.Rect.all(6),
    };
    tailwind_dvui.applyToOptions(&class_spec, &options);
    applyVisualToOptions(node, &options);

    const pressed = dvui.button(@src(), caption, .{}, options);
    if (pressed and node.hasListener("click")) {
        if (runtime) |rt| {
            jsc_bridge.dispatchEvent(rt, node_id, "click", null) catch |err| {
                log.err("Solid click dispatch failed: {s}", .{@errorName(err)});
            };
        }
    }

    renderChildElements(runtime, store, node, allocator);
}

fn renderImage(
    runtime: ?*jsruntime.JSRuntime,
    node_id: u32,
    node: *types.SolidNode,
    class_spec: tailwind.Spec,
) void {
    _ = runtime;
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
    tailwind_dvui.applyToOptions(&class_spec, &options);
    applyVisualToOptions(node, &options);
    if (options.rotation == null) {
        options.rotation = node.transform.rotation;
    }

    const image_source = image_loader.imageSource(resource);
    _ = dvui.image(@src(), .{ .source = image_source }, options);
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
        .background = false,
    };
    tailwind_dvui.applyToOptions(&class_spec, &options);
    applyVisualToOptions(node, &options);

    var state = node.ensureInputState(store.allocator) catch |err| {
        log.err("Solid input state init failed for node {d}: {s}", .{ node_id, @errorName(err) });
        return;
    };

    state.syncBufferFromValue() catch |err| {
        log.err("Solid input buffer sync failed for node {d}: {s}", .{ node_id, @errorName(err) });
        return;
    };

    // TODO: extend init options with placeholder/defaultValue once those attributes are captured.
    const init_opts: dvui.TextEntryWidget.InitOptions = .{
        .text = .{ .buffer_dynamic = .{
            .backing = &state.buffer,
            .allocator = state.allocator,
            .limit = state.limit,
        } },
    };

    var entry = dvui.textEntry(@src(), init_opts, options);
    defer entry.deinit();

    const current_text = entry.getText();
    state.text_len = current_text.len;

    if (entry.text_changed) {
        state.updateFromText(current_text) catch |err| {
            log.err("Solid input value sync failed for node {d}: {s}", .{ node_id, @errorName(err) });
            return;
        };
        if (node.hasListener("input")) {
            if (runtime) |rt| {
                jsc_bridge.dispatchEvent(rt, node_id, "input", current_text) catch |err| {
                    log.err("Solid input dispatch failed: {s}", .{@errorName(err)});
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
) void {
    for (node.children.items) |child_id| {
        const child = store.node(child_id) orelse continue;
        if (child.kind == .text) continue;
        renderNode(runtime, store, child_id, allocator);
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
