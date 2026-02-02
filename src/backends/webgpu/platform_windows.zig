const std = @import("std");

const swap_chain = @import("../pipeline/swap_chain.zig");

pub const State = struct {};

pub const Init = struct {
    swap: swap_chain.Resources,
    state: State,
};

pub fn init(handle: *anyopaque, width: u32, height: u32, _: f32) !Init {
    const hinstance = std.os.windows.kernel32.GetModuleHandleW(null) orelse return error.MissingInstanceHandle;
    const swap = try swap_chain.Resources.initWindows(handle, @ptrCast(hinstance), width, height);
    return .{ .swap = swap, .state = .{} };
}

pub fn resize(_: *State, _: u32, _: u32, _: f32) void {}
