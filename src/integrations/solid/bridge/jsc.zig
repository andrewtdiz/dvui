const std = @import("std");

const jsruntime = @import("jsruntime");

const types = @import("../core/types.zig");

// Bun / JavaScriptCore bridge stub replacing the old QuickJS integration.

pub fn syncOps(_: *jsruntime.JSRuntime, _: *types.NodeStore) !bool {
    return false;
}

pub fn dispatchEvent(
    runtime: *jsruntime.JSRuntime,
    node_id: u32,
    name: []const u8,
    payload: ?[]const u8,
) !void {
    const cb = runtime.event_cb orelse return;

    var id_bytes: [4]u8 = undefined;
    std.mem.writeInt(u32, id_bytes[0..], node_id, .little);

    // Pack node id followed by optional payload into a single buffer for the JS host.
    if (payload) |data| {
        const total: usize = 4 + data.len;
        var buffer = try runtime.allocator.alloc(u8, total);
        defer runtime.allocator.free(buffer);
        @memcpy(buffer[0..4], &id_bytes);
        if (data.len > 0) {
            @memcpy(buffer[4..], data);
        }
        cb(runtime.event_ctx, name, buffer);
        return;
    }

    cb(runtime.event_ctx, name, &id_bytes);
}

pub fn updateSolidStateI32(_: *jsruntime.JSRuntime, _: []const u8, _: i32) !void {
    return;
}

pub fn updateSolidStateString(
    _: *jsruntime.JSRuntime,
    _: []const u8,
    _: []const u8,
) !void {
    return;
}

pub fn readSolidStateI32(_: *jsruntime.JSRuntime, _: []const u8) !i32 {
    return error.SignalMissing;
}

pub fn readSolidStateString(
    _: *jsruntime.JSRuntime,
    allocator: std.mem.Allocator,
    _: []const u8,
) ![]u8 {
    return allocator.dupe(u8, "");
}
