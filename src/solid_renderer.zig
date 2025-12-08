const std = @import("std");

const dvui = @import("dvui");

const image_loader = @import("jsruntime/image_loader.zig");
const jsruntime = @import("jsruntime/mod.zig");
const jsc_bridge = @import("jsruntime/solid/jsc.zig");
const tailwind = @import("jsruntime/solid/tailwind.zig");
const tailwind_dvui = @import("jsruntime/solid/dvui_tailwind.zig");
const types = @import("jsruntime/solid/types.zig");

const log = std.log.scoped(.solid_bridge);

var gizmo_override_rect: ?types.GizmoRect = null;
var gizmo_rect_pending: ?types.GizmoRect = null;

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

pub fn render(runtime: ?*jsruntime.JSRuntime, store: *types.NodeStore) void {
    const root = store.node(0) orelse return;

    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const scratch = arena.allocator();

    if (root.children.items.len == 0) {
        log.debug("Solid renderer: root has no children", .{});
        return;
    }

    for (root.children.items) |child_id| {
        renderNode(runtime, store, child_id, scratch);
    }
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
        .text => renderText(node),
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
    if (!node.hasDirtySubtree() and node.total_interactive == 0) {
        node.markRendered();
        return;
    }
    const class_spec = node.prepareClassSpec();
    if (canCacheNode(node, &class_spec)) {
        var cache = dvui.cache(
            @src(),
            .{ .invalidate = node.hasDirtySubtree() },
            .{ .id_extra = nodeCacheKey(node.id), .expand = .both },
        );
        defer cache.deinit();
        if (!cache.uncached()) {
            node.markRendered();
            return;
        }
        renderElementBody(runtime, store, node_id, node, allocator, class_spec);
        return;
    }
    renderElementBody(runtime, store, node_id, node, allocator, class_spec);
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

fn canCacheNode(node: *types.SolidNode, class_spec: *const tailwind.ClassSpec) bool {
    if (node.kind != .element) return false;
    if (node.children.items.len == 0) return false;
    if (node.total_interactive > 0) return false;
    if (tailwind_dvui.isFlex(class_spec)) return false;
    return true;
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
    };
    tailwind_dvui.applyToOptions(&class_spec, &options);

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

fn renderText(node: *types.SolidNode) void {
    const trimmed = std.mem.trim(u8, node.text, " \n\r\t");
    if (trimmed.len > 0) {
        dvui.labelNoFmt(@src(), trimmed, .{}, .{ .id_extra = nodeIdExtra(node.id) });
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

fn nodeCacheKey(id: u32) usize {
    const salt: u32 = 0x9e3779b1;
    return nodeIdExtra(id ^ salt);
}
