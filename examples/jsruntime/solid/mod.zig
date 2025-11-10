const std = @import("std");
const jsruntime = @import("../mod.zig");

const alloc = @import("../../alloc.zig");
const types = @import("types.zig");
const quickjs_bridge = @import("quickjs.zig");
const renderer = @import("renderer.zig");

const log = std.log.scoped(.solid_bridge);

var store_initialized = false;
var store: types.NodeStore = undefined;

pub fn render(runtime: *jsruntime.JSRuntime) void {
    if (!store_initialized) {
        const allocator = alloc.allocator();
        store.init(allocator) catch |err| {
            log.err("Solid store init failed: {s}", .{@errorName(err)});
            return;
        };
        store_initialized = true;
    }

    const drain_limit: usize = 8;
    var pass: usize = 0;
    while (pass < drain_limit) : (pass += 1) {
        const applied = quickjs_bridge.syncOps(runtime, &store) catch |err| {
            log.err("Solid bridge sync failed: {s}", .{@errorName(err)});
            return;
        };
        if (!applied) break;
    }
    if (pass == drain_limit) {
        log.warn("Solid bridge drain limit reached; updates may still be pending", .{});
    }

    renderer.render(runtime, &store);
}
