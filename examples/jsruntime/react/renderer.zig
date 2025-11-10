const std = @import("std");
const image_allocator = std.heap.c_allocator;

const dvui = @import("dvui");
const Options = dvui.Options;
const FontStyle = Options.FontStyle;

const jsruntime = @import("../mod.zig");
const style = @import("style.zig");
const types = @import("types.zig");
const utils = @import("utils.zig");

const log = std.log.scoped(.react_bridge);

const ImageResource = struct {
    path: []const u8,
    bytes: []u8,
};

const ImageCache = std.StringHashMap(ImageResource);
var image_cache = ImageCache.init(image_allocator);

const max_image_bytes: usize = 16 * 1024 * 1024;
const image_search_roots = [_][]const u8{
    "examples/resources/assets",
    "examples/resources/js/assets",
    "examples/resources/js",
    "examples",
    "src",
    "",
};

const ImageError = error{
    MissingImageSource,
    ImageNotFound,
    ImageTooLarge,
};

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
        .box, .div => {
            renderContainerNode(runtime, nodes, entry);
            return;
        },
        .FlexBox => {
            renderFlexBoxNode(runtime, nodes, entry);
            return;
        },
        .p => {
            renderLabelNode(runtime, nodes, node_id, entry);
            return;
        },
        .h1 => {
            renderHeadingNode(runtime, nodes, node_id, entry, .title);
            return;
        },
        .h2 => {
            renderHeadingNode(runtime, nodes, node_id, entry, .title_1);
            return;
        },
        .h3 => {
            renderHeadingNode(runtime, nodes, node_id, entry, .title_2);
            return;
        },
        .button => {
            renderButtonNode(runtime, nodes, node_id, entry);
            return;
        },
        .image => {
            renderImageNode(runtime, node_id, entry);
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

fn renderImageNode(
    runtime: *jsruntime.JSRuntime,
    node_id: []const u8,
    entry: types.ReactCommand,
) void {
    _ = runtime;
    const src = entry.image_src orelse {
        log.warn("React image node {s} missing src", .{node_id});
        return;
    };

    const resource = loadImageResource(src) catch |err| {
        log.err("React image load failed for {s}: {s}", .{ src, @errorName(err) });
        return;
    };

    var image_opts = Options{
        .name = entry.command_type,
        .id_extra = utils.nodeIdExtra(node_id),
    };
    style.applyCommandStyle(entry.style, &image_opts);

    const image_source = dvui.ImageSource{
        .imageFile = .{
            .bytes = resource.bytes,
            .name = resource.path,
        },
    };

    _ = dvui.image(@src(), .{ .source = image_source }, image_opts);
}

fn loadImageResource(src: []const u8) !*const ImageResource {
    const canonical = try resolveImagePath(src);
    var keep_path = false;
    defer if (!keep_path) image_allocator.free(canonical);

    if (image_cache.getPtr(canonical)) |existing| {
        return existing;
    }

    const bytes = try readImageFile(canonical);
    errdefer image_allocator.free(bytes);

    const gop = try image_cache.getOrPut(canonical);
    if (gop.found_existing) {
        image_allocator.free(bytes);
        return gop.value_ptr;
    }

    keep_path = true;
    gop.key_ptr.* = canonical;
    gop.value_ptr.* = .{
        .path = canonical,
        .bytes = bytes,
    };
    return gop.value_ptr;
}

fn resolveImagePath(source: []const u8) ![]u8 {
    if (source.len == 0) {
        return error.MissingImageSource;
    }
    if (std.fs.path.isAbsolute(source)) {
        return std.fs.realpathAlloc(image_allocator, source) catch {
            return error.ImageNotFound;
        };
    }

    for (image_search_roots) |root| {
        const candidate = try buildCandidatePath(root, source);
        defer image_allocator.free(candidate);

        const resolved = std.fs.cwd().realpathAlloc(image_allocator, candidate) catch {
            return error.FileNotFound;
        };
        return resolved;
    }

    return error.ImageNotFound;
}

fn buildCandidatePath(base: []const u8, rel: []const u8) ![]u8 {
    if (base.len == 0) {
        return image_allocator.dupe(u8, rel);
    }
    return std.fs.path.join(image_allocator, &.{ base, rel });
}

fn readImageFile(path: []const u8) ![]u8 {
    const file = try std.fs.openFileAbsolute(path, .{ .mode = .read_only });
    defer file.close();

    return try file.readToEndAlloc(image_allocator, max_image_bytes);
}
