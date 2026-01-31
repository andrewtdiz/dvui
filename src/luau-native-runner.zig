const std = @import("std");
const native = @import("native_renderer");

fn logCallback(level: u8, msg_ptr: [*]const u8, msg_len: usize) callconv(.c) void {
    const msg = msg_ptr[0..msg_len];
    std.debug.print("[native:{d}] {s}\n", .{ level, msg });
}

pub fn main() !void {
    const renderer = native.lifecycle.createRendererImpl(&logCallback, null) orelse {
        std.debug.print("Failed to create native renderer\n", .{});
        return;
    };
    defer native.lifecycle.destroyRendererImpl(renderer);

    renderer.screenshot_key_enabled = true;
    renderer.size = .{ 1280, 720 };
    renderer.pixel_size = .{ 1280, 720 };
    try native.window.ensureWindow(renderer);

    while (!renderer.pending_destroy and !renderer.destroy_started) {
        native.window.renderFrame(renderer);
    }
}
