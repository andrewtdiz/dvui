const std = @import("std");
const dvui = @import("../dvui.zig");
const Options = dvui.Options;
const Debug = @This();

pub const DebugTarget = enum {
    none,
    focused,
    mouse_until_esc,
    mouse_until_click,
    mouse_quitting,

    pub fn mouse(self: DebugTarget) bool {
        return self == .mouse_until_click or self == .mouse_until_esc or self == .mouse_quitting;
    }
};

open: bool = false,
options_editor_open: bool = false,
options_override_list_open: bool = false,
show_frame_times: bool = false,

/// 0 means no widget is selected
widget_id: dvui.Id = .zero,
target: DebugTarget = .none,

/// All functions using the parent are invalid
target_wd: ?dvui.WidgetData = null,

/// Uses `gpa` allocator
///
/// The name slice is also duplicated by the `gpa` allocator
under_mouse_stack: std.ArrayListUnmanaged(struct { id: dvui.Id, name: []const u8 }) = .empty,

/// Uses `gpa` allocator
options_override: std.AutoHashMapUnmanaged(dvui.Id, struct { Options, std.builtin.SourceLocation }) = .empty,

toggle_mutex: std.Thread.Mutex = .{},
log_refresh: bool = false,
log_events: bool = false,

/// A panic will be called from within the targeted widget
widget_panic: bool = false,

/// when true, left mouse button works like a finger
touch_simulate_events: bool = false,
touch_simulate_down: bool = false,

pub fn reset(self: *Debug, gpa: std.mem.Allocator) void {
    if (self.target.mouse()) {
        for (self.under_mouse_stack.items) |item| {
            gpa.free(item.name);
        }
        self.under_mouse_stack.clearRetainingCapacity();
    }
    self.target_wd = null;
}

pub fn deinit(self: *Debug, gpa: std.mem.Allocator) void {
    for (self.under_mouse_stack.items) |item| {
        gpa.free(item.name);
    }
    self.under_mouse_stack.clearAndFree(gpa);
    self.options_override.deinit(gpa);
}

/// Returns the previous value
///
/// called from any thread
pub fn logEvents(self: *Debug, val: ?bool) bool {
    self.toggle_mutex.lock();
    defer self.toggle_mutex.unlock();

    const previous = self.log_events;
    if (val) |v| {
        self.log_events = v;
    }

    return previous;
}

/// Returns the previous value
///
/// called from any thread
pub fn logRefresh(self: *Debug, val: ?bool) bool {
    self.toggle_mutex.lock();
    defer self.toggle_mutex.unlock();

    const previous = self.log_refresh;
    if (val) |v| {
        self.log_refresh = v;
    }

    return previous;
}

/// Returns early if `Debug.open` is `false`
pub fn show(self: *Debug) void {
    if (self.target == .mouse_quitting) {
        self.target = .none;
    }

    if (self.show_frame_times) {
        self.showFrameTimes();
    }
}

pub fn showFrameTimes(self: *Debug) void {
    _ = self;
}
