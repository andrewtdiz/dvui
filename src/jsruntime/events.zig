const types = @import("types.zig");

const MouseSnapshot = types.MouseSnapshot;
const MouseEvent = types.MouseEvent;
const KeyEvent = types.KeyEvent;

pub fn updateMouse(_: anytype, _: MouseSnapshot) !void {
    return;
}

pub fn emitMouseEvent(_: anytype, _: MouseEvent) !void {
    return;
}

pub fn emitKeyEvent(_: anytype, _: KeyEvent) !void {
    return;
}
