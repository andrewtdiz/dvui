const std = @import("std");
const dvui = @import("dvui");

const jsruntime = @import("jsruntime/mod.zig");
const image_loader = @import("jsruntime/image_loader.zig");
const types = @import("types.zig");
const quickjs_bridge = @import("jsc.zig");
const tailwind = @import("tailwind.zig");

const log = std.log.scoped(.solid_bridge);

pub fn render(runtime: *jsruntime.JSRuntime, store: *types.NodeStore) bool {
    const root = store.node(0) orelse return false;

    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const scratch = arena.allocator();

    if (root.children.items.len == 0) {
        log.debug("Solid renderer: root has no children (nodes={d})", .{store.nodes.count()});
        return false;
    }

    log.debug("Solid renderer: rendering root with {d} children", .{root.children.items.len});

    var rendered: bool = false;
    for (root.children.items) |child_id| {
        rendered = renderNode(runtime, store, child_id, scratch) or rendered;
    }
    return rendered;
}

fn renderNode(
    runtime: *jsruntime.JSRuntime,
    store: *types.NodeStore,
    node_id: u32,
    allocator: std.mem.Allocator,
) bool {
    const node = store.node(node_id) orelse return false;
    switch (node.kind) {
        .root => {
            var any = false;
            for (node.children.items) |child_id| {
                any = renderNode(runtime, store, child_id, allocator) or any;
            }
            node.markRendered();
            return any;
        },
        .slot => {
            var any = false;
            for (node.children.items) |child_id| {
                any = renderNode(runtime, store, child_id, allocator) or any;
            }
            node.markRendered();
            return any;
        },
        .text => return renderText(node),
        .element => return renderElement(runtime, store, node_id, node, allocator),
    }
}

fn renderElement(
    runtime: *jsruntime.JSRuntime,
    store: *types.NodeStore,
    node_id: u32,
    node: *types.SolidNode,
    allocator: std.mem.Allocator,
) bool {
    const class_spec = node.prepareClassSpec();
    if (std.mem.eql(u8, node.tag, "div")) {
        const rendered = renderContainer(runtime, store, node, allocator, class_spec);
        node.markRendered();
        return rendered;
    }
    if (std.mem.eql(u8, node.tag, "button")) {
        renderButton(runtime, store, node_id, node, allocator, class_spec);
        node.markRendered();
        return true;
    }
    if (std.mem.eql(u8, node.tag, "input")) {
        renderInput(runtime, store, node_id, node, class_spec);
        node.markRendered();
        return true;
    }
    if (std.mem.eql(u8, node.tag, "image")) {
        renderImage(runtime, node_id, node, class_spec);
        node.markRendered();
        return true;
    }
    if (std.mem.eql(u8, node.tag, "p")) {
        const rendered = renderParagraph(runtime, store, node_id, node, allocator, class_spec, null);
        node.markRendered();
        return rendered;
    }
    if (std.mem.eql(u8, node.tag, "h1")) {
        const rendered = renderParagraph(runtime, store, node_id, node, allocator, class_spec, .title);
        node.markRendered();
        return rendered;
    }
    if (std.mem.eql(u8, node.tag, "h2")) {
        const rendered = renderParagraph(runtime, store, node_id, node, allocator, class_spec, .title_1);
        node.markRendered();
        return rendered;
    }
    if (std.mem.eql(u8, node.tag, "h3")) {
        const rendered = renderParagraph(runtime, store, node_id, node, allocator, class_spec, .title_2);
        node.markRendered();
        return rendered;
    }
    const rendered = renderGeneric(runtime, store, node, allocator);
    node.markRendered();
    return rendered;
}

fn renderContainer(
    runtime: *jsruntime.JSRuntime,
    store: *types.NodeStore,
    node: *types.SolidNode,
    allocator: std.mem.Allocator,
    class_spec: tailwind.Spec,
) bool {
    var options = dvui.Options{
        .name = "solid-div",
        .background = false,
        .expand = .none,
    };
    tailwind.applyToOptions(&class_spec, &options);

    if (class_spec.is_flex) {
        const flex_init = tailwind.buildFlexOptions(&class_spec);
        var flexbox_widget = dvui.flexbox(@src(), flex_init, options);
        defer flexbox_widget.deinit();
        if (!renderCachedSubtree(runtime, store, node, allocator)) {
            return renderFlexChildren(runtime, store, node, allocator, &class_spec) or options.background;
        }
    } else {
        var box = dvui.box(@src(), .{}, options);
        defer box.deinit();
        if (!renderCachedSubtree(runtime, store, node, allocator)) {
            var rendered_child = false;
            for (node.children.items) |child_id| {
                rendered_child = renderNode(runtime, store, child_id, allocator) or rendered_child;
            }
            return rendered_child or options.background;
        }
    }
    return true;
}

fn renderFlexChildren(
    runtime: *jsruntime.JSRuntime,
    store: *types.NodeStore,
    node: *types.SolidNode,
    allocator: std.mem.Allocator,
    class_spec: *const tailwind.Spec,
) bool {
    const direction = class_spec.direction orelse .horizontal;
    const gap_main = switch (direction) {
        .horizontal => class_spec.gap_col,
        .vertical => class_spec.gap_row,
    } orelse 0;

    var child_index: usize = 0;
    var rendered: bool = false;
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
            rendered = renderNode(runtime, store, child_id, allocator) or rendered;
        } else {
            rendered = renderNode(runtime, store, child_id, allocator) or rendered;
        }
        child_index += 1;
    }
    return rendered;
}

fn renderGeneric(
    runtime: *jsruntime.JSRuntime,
    store: *types.NodeStore,
    node: *types.SolidNode,
    allocator: std.mem.Allocator,
) bool {
    if (renderCachedSubtree(runtime, store, node, allocator)) {
        return true;
    }
    var rendered = false;
    for (node.children.items) |child_id| {
        rendered = renderNode(runtime, store, child_id, allocator) or rendered;
    }
    return rendered;
}

fn renderParagraph(
    runtime: *jsruntime.JSRuntime,
    store: *types.NodeStore,
    node_id: u32,
    node: *types.SolidNode,
    allocator: std.mem.Allocator,
    class_spec: tailwind.Spec,
    font_override: ?dvui.Options.FontStyle,
) bool {
    var text_buffer: std.ArrayList(u8) = .empty;
    defer text_buffer.deinit(allocator);

    var rendered: bool = false;
    collectText(allocator, store, node, &text_buffer);
    if (text_buffer.items.len > 0) {
        const trimmed = std.mem.trim(u8, text_buffer.items, " \n\r\t");
        if (trimmed.len > 0) {
            var options = dvui.Options{
                .id_extra = nodeIdExtra(node_id),
            };
            tailwind.applyToOptions(&class_spec, &options);
            if (font_override) |style_name| {
                if (options.font_style == null) {
                    options.font_style = style_name;
                }
            }
            dvui.labelNoFmt(@src(), trimmed, .{}, options);
            rendered = true;
        }
    }

    rendered = renderChildElements(runtime, store, node, allocator) or rendered;
    return rendered;
}

fn renderText(node: *types.SolidNode) bool {
    const trimmed = std.mem.trim(u8, node.text, " \n\r\t");
    if (trimmed.len > 0) {
        dvui.labelNoFmt(@src(), trimmed, .{}, .{ .id_extra = nodeIdExtra(node.id) });
        node.markRendered();
        return true;
    }
    node.markRendered();
    return false;
}

fn renderButton(
    runtime: *jsruntime.JSRuntime,
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
    tailwind.applyToOptions(&class_spec, &options);

    const pressed = dvui.button(@src(), caption, .{}, options);
    if (pressed and node.hasListener("click")) {
        quickjs_bridge.dispatchEvent(runtime, node_id, "click", null) catch |err| {
            log.err("Solid click dispatch failed: {s}", .{@errorName(err)});
        };
    }

    renderChildElements(runtime, store, node, allocator);
}

fn renderImage(
    runtime: *jsruntime.JSRuntime,
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
    tailwind.applyToOptions(&class_spec, &options);

    const image_source = image_loader.imageSource(resource);
    _ = dvui.image(@src(), .{ .source = image_source }, options);
}

fn renderInput(
    runtime: *jsruntime.JSRuntime,
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
    tailwind.applyToOptions(&class_spec, &options);

    if (class_spec.text) |color_value| {
        options.color_text = color_value;
    }

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
            quickjs_bridge.dispatchEvent(runtime, node_id, "input", current_text) catch |err| {
                log.err("Solid input dispatch failed: {s}", .{@errorName(err)});
            };
        }
    }
}

fn renderChildElements(
    runtime: *jsruntime.JSRuntime,
    store: *types.NodeStore,
    node: *types.SolidNode,
    allocator: std.mem.Allocator,
) bool {
    var rendered = false;
    for (node.children.items) |child_id| {
        const child = store.node(child_id) orelse continue;
        if (child.kind == .text) continue;
        rendered = renderNode(runtime, store, child_id, allocator) or rendered;
    }
    return rendered;
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

fn renderCachedSubtree(
    runtime: *jsruntime.JSRuntime,
    store: *types.NodeStore,
    node: *types.SolidNode,
    allocator: std.mem.Allocator,
) bool {
    if (!shouldCacheNode(node)) return false;

    var cache = dvui.cache(
        @src(),
        .{ .invalidate = node.hasDirtySubtree() },
        .{ .id_extra = nodeCacheKey(node.id), .expand = .both },
    );
    defer cache.deinit();

    if (!cache.uncached()) {
        return true;
    }

    for (node.children.items) |child_id| {
        renderNode(runtime, store, child_id, allocator);
    }
    return true;
}

fn shouldCacheNode(node: *types.SolidNode) bool {
    if (node.kind != .element) return false;
    if (node.children.items.len == 0) return false;
    if (node.interactive_self) return false;
    if (node.interactiveChildCount() > 0) return false;
    const spec = node.prepareClassSpec();
    if (spec.is_flex) return false;
    return true;
}
