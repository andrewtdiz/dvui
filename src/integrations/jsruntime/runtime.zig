const std = @import("std");

const alloc = @import("alloc");
const solid_events = @import("solid").events;

/// Minimal JS runtime state for FFI interop.
/// Event dispatch now uses the EventRing exclusively.
pub const JSRuntime = @This();

allocator: std.mem.Allocator,
/// Event ring buffer pointer for direct event dispatch
event_ring: ?*solid_events.EventRing = null,

pub const Error = error{
    RuntimeInitFailed,
};

pub fn init(_: []const u8) Error!JSRuntime {
    return JSRuntime{
        .allocator = alloc.allocator(),
    };
}

pub fn deinit(_: *JSRuntime) void {}
