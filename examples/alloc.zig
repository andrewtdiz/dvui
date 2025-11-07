const std = @import("std");
const builtin = @import("builtin");

const is_debug_mode = builtin.mode == .Debug;

pub var gpa = std.heap.GeneralPurposeAllocator(.{
    .safety = is_debug_mode,
}){};

var alloc: ?std.mem.Allocator = null;

pub fn init() void {
    alloc = if (is_debug_mode) gpa.allocator() else std.heap.c_allocator;
}

pub fn deinit() void {
    const leaked = gpa.deinit();
    if (is_debug_mode and leaked == .leak) {
        std.debug.print("Memory leak detected!\n", .{});
    }
}

pub fn allocator() std.mem.Allocator {
    if (alloc == null) init();
    return alloc.?;
}
