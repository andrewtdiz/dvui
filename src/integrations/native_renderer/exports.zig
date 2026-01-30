const ray = @import("raylib-backend").raylib;

const commands = @import("commands.zig");
const lifecycle = @import("lifecycle.zig");
const logMessage = lifecycle.logMessage;
const types = @import("types.zig");
const Renderer = types.Renderer;
const window = @import("window.zig");

// ============================================================
// Renderer Lifecycle Exports
// ============================================================

pub export fn createRenderer(log_cb: ?*const types.LogFn, event_cb: ?*const types.EventFn) callconv(.c) ?*Renderer {
    return lifecycle.createRendererImpl(log_cb, event_cb);
}

pub export fn destroyRenderer(renderer: ?*Renderer) callconv(.c) void {
    lifecycle.destroyRendererImpl(renderer);
}

// ============================================================
// Window/Resize Exports
// ============================================================

pub export fn resizeRenderer(renderer: ?*Renderer, width: u32, height: u32) callconv(.c) void {
    if (renderer) |ptr| {
        if (ptr.destroy_started or ptr.pending_destroy) return;
        if (ptr.busy) return;
        ptr.busy = true;
        defer {
            ptr.busy = false;
            lifecycle.tryFinalize(ptr);
        }
        if (width == 0 or height == 0) return;
        ptr.size = .{ width, height };
        if (ptr.window_ready) {
            const current_w: u32 = @intCast(ray.getScreenWidth());
            const current_h: u32 = @intCast(ray.getScreenHeight());
            if (current_w != width or current_h != height) {
                ray.setWindowSize(@intCast(width), @intCast(height));
            }
        } else {
            window.ensureWindow(ptr) catch |err| {
                logMessage(ptr, 3, "resize failed to open window: {s}", .{@errorName(err)});
            };
        }
    }
}

pub export fn presentRenderer(renderer: ?*Renderer) callconv(.c) void {
    if (renderer) |ptr| {
        if (ptr.pending_destroy) return;
        if (ptr.destroy_started) return;
        if (!ptr.window_ready) {
            window.ensureWindow(ptr) catch |err| {
                logMessage(ptr, 3, "present failed to open window: {s}", .{@errorName(err)});
            };
        }
        ptr.busy = true;
        defer {
            ptr.busy = false;
            lifecycle.tryFinalize(ptr);
        }
        window.renderFrame(ptr);
    }
}

// ============================================================
// Command Buffer Exports
// ============================================================

pub export fn commitCommands(
    renderer: ?*Renderer,
    header_ptr: [*]const u8,
    header_len: usize,
    payload_ptr: [*]const u8,
    payload_len: usize,
    command_count: u32,
) callconv(.c) void {
    if (renderer) |ptr| {
        if (ptr.destroy_started or ptr.pending_destroy) return;
        if (ptr.busy) return;
        ptr.busy = true;
        defer {
            ptr.busy = false;
            lifecycle.tryFinalize(ptr);
        }
        commands.updateCommands(ptr, header_ptr, header_len, payload_ptr, payload_len, command_count);
    }
}
