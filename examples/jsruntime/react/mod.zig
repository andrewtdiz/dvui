const std = @import("std");
const dvui = @import("dvui");
const jsruntime = @import("../mod.zig");

pub const types = @import("types.zig");
pub const renderer = @import("renderer.zig");
pub const quickjs = @import("quickjs.zig");
pub const utils = @import("utils.zig");
pub const style = @import("style.zig");

const log = std.log.scoped(.react_bridge);

pub fn render(runtime: *jsruntime.JSRuntime) void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    const allocator = arena.allocator();

    var nodes = types.ReactCommandMap.init(allocator);
    defer nodes.deinit();
    var root_ids: std.ArrayList([]const u8) = .empty;
    defer root_ids.deinit(allocator);

    quickjs.buildReactCommandGraph(runtime, &nodes, &root_ids, allocator) catch |err| {
        switch (err) {
            error.MissingRenderTree => {},
            else => log.err("React bridge build failed: {s}", .{@errorName(err)}),
        }
        return;
    };

    if (root_ids.items.len == 0) {
        return;
    }

    var root_container = dvui.box(@src(), .{}, .{
        .expand = .both,
        .name = "ReactBridgeRoot",
        .padding = dvui.Rect.all(16),
    });
    defer root_container.deinit();

    for (root_ids.items) |node_id| {
        renderer.renderReactNode(runtime, &nodes, node_id);
    }
}
