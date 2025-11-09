const std = @import("std");
const dvui = @import("dvui");
const jsruntime = @import("../mod.zig");

const types = @import("types.zig");
const utils = @import("utils.zig");
const style = @import("style.zig");

const Options = dvui.Options;
const FontStyle = Options.FontStyle;

const log = std.log.scoped(.react_bridge);

pub fn renderReactNode(
    runtime: *jsruntime.JSRuntime,
    nodes: *const types.ReactCommandMap,
    node_id: []const u8,
) void {
    const entry = nodes.get(node_id) orelse return;
    const cmd_type = std.meta.stringToEnum(types.CommandType, entry.command_type) orelse {
        for (entry.children) |child_id| {
            renderReactNode(runtime, nodes, child_id);
        }
        return;
    };

    switch (cmd_type) {
        .@"box", .@"div" => {
            renderContainerNode(runtime, nodes, entry);
            return;
        },
        .@"FlexBox" => {
            renderFlexBoxNode(runtime, nodes, entry);
            return;
        },
        .@"p" => {
            renderLabelNode(runtime, nodes, node_id, entry);
            return;
        },
        .@"h1" => {
            renderHeadingNode(runtime, nodes, node_id, entry, .title);
            return;
        },
        .@"h2" => {
            renderHeadingNode(runtime, nodes, node_id, entry, .title_1);
            return;
        },
        .@"h3" => {
            renderHeadingNode(runtime, nodes, node_id, entry, .title_2);
            return;
        },
        .@"button" => {
            renderButtonNode(runtime, nodes, node_id, entry);
            return;
        },
        .@"text-content" => {
            const content = entry.text orelse "";
            var tl = dvui.textLayout(@src(), .{}, .{ .expand = .horizontal, .background = false });
            tl.addText(content, .{});
            tl.deinit();
            return;
        },
    }
}

fn renderLabelNode(
    runtime: *jsruntime.JSRuntime,
    nodes: *const types.ReactCommandMap,
    node_id: []const u8,
    entry: types.ReactCommand,
) void {
    renderTextualNode(runtime, nodes, node_id, entry, null);
}

fn renderHeadingNode(
    runtime: *jsruntime.JSRuntime,
    nodes: *const types.ReactCommandMap,
    node_id: []const u8,
    entry: types.ReactCommand,
    font_style: FontStyle,
) void {
    renderTextualNode(runtime, nodes, node_id, entry, font_style);
}

fn renderButtonNode(
    runtime: *jsruntime.JSRuntime,
    nodes: *const types.ReactCommandMap,
    node_id: []const u8,
    entry: types.ReactCommand,
) void {
    const caption = entry.text_content orelse utils.resolveCommandText(nodes, entry.children);

    var button_opts = Options{
        .id_extra = utils.nodeIdExtra(node_id),
    };
    style.applyCommandStyle(entry.style, &button_opts);

    const pressed = dvui.button(@src(), caption, .{}, button_opts);
    if (pressed) {
        if (entry.on_click_id) |listener_id| {
            runtime.invokeListener(listener_id) catch |err| {
                log.err("React onClick failed: {s}", .{@errorName(err)});
            };
        }
    }

    for (entry.children) |child_id| {
        const child_entry = nodes.get(child_id) orelse continue;
        if (std.mem.eql(u8, child_entry.command_type, "text-content")) continue;
        renderReactNode(runtime, nodes, child_id);
    }
}

fn renderContainerNode(
    runtime: *jsruntime.JSRuntime,
    nodes: *const types.ReactCommandMap,
    entry: types.ReactCommand,
) void {
    const box_options = utils.initContainerOptions(entry);

    var box_widget = dvui.box(@src(), .{}, box_options);
    defer box_widget.deinit();
    for (entry.children) |child_id| {
        renderReactNode(runtime, nodes, child_id);
    }
}

fn renderFlexBoxNode(
    runtime: *jsruntime.JSRuntime,
    nodes: *const types.ReactCommandMap,
    entry: types.ReactCommand,
) void {
    const flex_options = utils.initContainerOptions(entry);
    const flex_init = utils.buildFlexInitOptions(entry);

    var flex_widget = dvui.flexbox(@src(), flex_init, flex_options);
    defer flex_widget.deinit();

    for (entry.children) |child_id| {
        renderReactNode(runtime, nodes, child_id);
    }
}

fn renderTextualNode(
    runtime: *jsruntime.JSRuntime,
    nodes: *const types.ReactCommandMap,
    node_id: []const u8,
    entry: types.ReactCommand,
    font_style: ?FontStyle,
) void {
    const content = entry.text_content orelse utils.resolveCommandText(nodes, entry.children);

    var label_opts = Options{
        .id_extra = utils.nodeIdExtra(node_id),
    };
    if (font_style) |style_name| {
        label_opts.font_style = style_name;
    }
    style.applyCommandStyle(entry.style, &label_opts);

    dvui.labelNoFmt(@src(), content, .{}, label_opts);

    for (entry.children) |child_id| {
        const child_entry = nodes.get(child_id) orelse continue;
        if (std.mem.eql(u8, child_entry.command_type, "text-content")) continue;
        renderReactNode(runtime, nodes, child_id);
    }
}
