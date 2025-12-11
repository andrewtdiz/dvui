const std = @import("std");
const jsruntime = @import("../mod.zig");

const alloc = @import("../../alloc.zig");
const solid = @import("../../solid/mod.zig");

const log = std.log.scoped(.solid_bridge);

var store_initialized = false;
var store: solid.NodeStore = undefined;

pub const jsc = solid.bridge_jsc;

pub fn render(runtime: *jsruntime.JSRuntime) void {
    if (!store_initialized) {
        const allocator = alloc.allocator();
        store.init(allocator) catch |err| {
            log.err("Solid store init failed: {s}", .{@errorName(err)});
            return;
        };
        store_initialized = true;
    }

    _ = solid.render(runtime, &store);
}
