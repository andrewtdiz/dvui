const std = @import("std");
const jsruntime = @import("../mod.zig");

const alloc = @import("../../alloc.zig");
const types = @import("types.zig");
const renderer = @import("renderer.zig");
pub const jsc = @import("jsc.zig");
pub const quickjs = @import("quickjs.zig");

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

    _ = renderer.render(runtime, &store);
}
