const std = @import("std");
const dvui = @import("dvui");

const jsruntime = @import("../mod.zig");
const types = @import("types.zig");
const quickjs_bridge = @import("quickjs.zig");
const tailwind = @import("tailwind.zig");

const log = std.log.scoped(.solid_bridge);

pub fn render(runtime: *jsruntime.JSRuntime, store: *types.NodeStore) void {
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
    runtime: *jsruntime.JSRuntime,
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
    runtime: *jsruntime.JSRuntime,
    store: *types.NodeStore,
    node_id: u32,
    node: *types.SolidNode,
    allocator: std.mem.Allocator,
) void {
    const class_spec = node.prepareClassSpec();
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
    if (std.mem.eql(u8, node.tag, "p")) {
        renderParagraph(runtime, store, node_id, node, allocator, class_spec);
        node.markRendered();
        return;
    }
    renderGeneric(runtime, store, node, allocator);
    node.markRendered();
}

fn renderContainer(
    runtime: *jsruntime.JSRuntime,
    store: *types.NodeStore,
    node: *types.SolidNode,
    allocator: std.mem.Allocator,
    class_spec: tailwind.Spec,
) void {
    var options = dvui.Options{
        .name = "solid-div",
        .padding = dvui.Rect.all(8),
        .background = false,
        .expand = .horizontal,
    };
    tailwind.applyToOptions(&class_spec, &options);

    if (class_spec.is_flex) {
        const flex_init = tailwind.buildFlexOptions(&class_spec);
        var flexbox_widget = dvui.flexbox(@src(), flex_init, options);
        defer flexbox_widget.deinit();
        for (node.children.items) |child_id| {
            renderNode(runtime, store, child_id, allocator);
        }
    } else {
        var box = dvui.box(@src(), .{}, options);
        defer box.deinit();
        for (node.children.items) |child_id| {
            renderNode(runtime, store, child_id, allocator);
        }
    }
}

fn renderGeneric(
    runtime: *jsruntime.JSRuntime,
    store: *types.NodeStore,
    node: *types.SolidNode,
    allocator: std.mem.Allocator,
) void {
    for (node.children.items) |child_id| {
        renderNode(runtime, store, child_id, allocator);
    }
}

fn renderParagraph(
    runtime: *jsruntime.JSRuntime,
    store: *types.NodeStore,
    node_id: u32,
    node: *types.SolidNode,
    allocator: std.mem.Allocator,
    class_spec: tailwind.Spec,
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
            tailwind.applyToOptions(&class_spec, &options);
            dvui.labelNoFmt(@src(), trimmed, .{}, options);
        }
    }

    renderChildElements(runtime, store, node, allocator);
}

fn renderText(node: *types.SolidNode) void {
    const trimmed = std.mem.trim(u8, node.text, " \n\r\t");
    if (trimmed.len > 0) {
        dvui.labelNoFmt(@src(), trimmed, .{}, .{ .id_extra = nodeIdExtra(node.id) });
    }
    node.markRendered();
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
        quickjs_bridge.dispatchEvent(runtime, node_id, "click") catch |err| {
            log.err("Solid click dispatch failed: {s}", .{@errorName(err)});
        };
    }

    renderChildElements(runtime, store, node, allocator);
}

fn renderChildElements(
    runtime: *jsruntime.JSRuntime,
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
