const std = @import("std");

const alloc = @import("../alloc.zig");
const console = @import("console.zig");
const hot_reload = @import("hotreload.zig");
const types = @import("types.zig");

pub const FrameData = types.FrameData;
pub const FrameResult = types.FrameResult;
pub const FrameCommand = types.FrameCommand;
pub const SelectionColor = types.SelectionColor;
pub const MouseSnapshot = types.MouseSnapshot;
pub const MouseEvent = types.MouseEvent;
pub const MouseEventKind = types.MouseEventKind;
pub const MouseButton = types.MouseButton;
pub const KeyEvent = types.KeyEvent;
pub const KeyEventKind = types.KeyEventKind;
pub const KeyCode = types.KeyCode;

pub const EvalResult = struct {
    success: bool,
    result: []u8,
};

pub const JSRuntime = @This();

allocator: std.mem.Allocator,
stored_message: []u8 = &.{},

pub const Error = error{
    RuntimeInitFailed,
    ScriptLoadFailed,
    CallFailed,
    InvalidResponse,
};

pub fn init(_: []const u8) Error!JSRuntime {
    return JSRuntime{
        .allocator = alloc.allocator(),
    };
}

pub fn deinit(self: *JSRuntime) void {
    if (self.stored_message.len > 0) {
        self.allocator.free(self.stored_message);
    }
}

pub fn runFrame(_: *JSRuntime, frame_data: FrameData) Error!FrameResult {
    return .{ .new_position = frame_data.position };
}

pub fn updateMouse(_: *JSRuntime, _: MouseSnapshot) Error!void {
    return;
}

pub fn emitMouseEvent(_: *JSRuntime, _: MouseEvent) Error!void {
    return;
}

pub fn emitKeyEvent(_: *JSRuntime, _: KeyEvent) Error!void {
    return;
}

pub fn recordStackUsage(_: *JSRuntime) void {}

pub fn setFloatProperty(_: *JSRuntime, _: anytype, _: anytype, comptime _: []const u8, _: f64) Error!void {
    return;
}

pub fn setIntProperty(_: *JSRuntime, _: anytype, _: anytype, comptime _: []const u8, _: i32) Error!void {
    return;
}

pub fn setBoolProperty(_: *JSRuntime, _: anytype, _: anytype, comptime _: []const u8, _: bool) Error!void {
    return;
}

pub fn setStringProperty(_: *JSRuntime, _: anytype, _: anytype, comptime _: []const u8, _: []const u8) Error!void {
    return;
}

pub fn populateWindowEventCommon(_: *JSRuntime, _: anytype, _: anytype, _: []const u8) Error!void {
    return;
}

pub fn invokeListener(_: *JSRuntime, _: []const u8) Error!void {
    return;
}

pub fn takeFrameCommand(_: *JSRuntime) ?FrameCommand {
    return null;
}

pub fn setFrameCommand(_: *JSRuntime, _: FrameCommand) void {}

pub fn clearFrameCommand(_: *JSRuntime) void {}

pub fn setSelectionColor(_: *JSRuntime, _: SelectionColor) void {}

pub fn takeSelectionColor(_: *JSRuntime) ?SelectionColor {
    return null;
}

pub fn acquireContext(_: *JSRuntime) !void {
    return;
}

pub fn evalScript(
    self: *JSRuntime,
    allocator: std.mem.Allocator,
    _: []const u8,
    _: []const u8,
    _: anytype,
) Error!EvalResult {
    _ = allocator;
    return .{ .success = true, .result = try self.allocator.dupe(u8, "") };
}

pub fn warnLastException(_: *JSRuntime, _: []const u8) void {}

pub fn setMessage(self: *JSRuntime, value: []const u8) !void {
    if (self.stored_message.len > 0) {
        self.allocator.free(self.stored_message);
    }
    self.stored_message = try self.allocator.dupe(u8, value);
}

pub fn message(self: *JSRuntime) []const u8 {
    return self.stored_message;
}

pub fn enableHotReload(script_path: []const u8) !void {
    try hot_reload.enable(script_path);
}

pub fn setConsoleSink(_: console.ConsoleSink) void {}

pub fn clearConsoleSink() void {}
