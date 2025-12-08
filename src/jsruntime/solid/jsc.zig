const std = @import("std");

// Bun / JavaScriptCore bridge stub replacing the old QuickJS integration.
const jsruntime = @import("../mod.zig");
const types = @import("types.zig");

pub fn syncOps(_: *jsruntime.JSRuntime, _: *types.NodeStore) !bool {
    return false;
}

pub fn dispatchEvent(
    _: *jsruntime.JSRuntime,
    _: u32,
    _: []const u8,
    _: ?[]const u8,
) !void {
    return;
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
