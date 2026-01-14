const ray = @import("raylib-backend").raylib;
const solid = @import("solid");

const commands = @import("commands.zig");
const lifecycle = @import("lifecycle.zig");
const logMessage = lifecycle.logMessage;
const solid_sync = @import("solid_sync.zig");
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

// ============================================================
// Solid Tree Exports
// ============================================================

pub export fn setRendererText(renderer: ?*Renderer, text_ptr: [*]const u8, text_len: usize) callconv(.c) void {
    if (renderer) |ptr| {
        if (ptr.destroy_started or ptr.pending_destroy) return;
        if (ptr.busy) return;
        ptr.busy = true;
        defer {
            ptr.busy = false;
            lifecycle.tryFinalize(ptr);
        }
        const store = solid_sync.ensureSolidStore(ptr, logMessage) catch return;

        const text_slice = text_ptr[0..text_len];
        store.setTextNode(1, text_slice) catch |err| {
            logMessage(ptr, 3, "setText failed: {s}", .{@errorName(err)});
            return;
        };

        const root = store.node(0) orelse return;
        var present = false;
        for (root.children.items) |cid| {
            if (cid == 1) {
                present = true;
                break;
            }
        }
        if (!present) {
            store.insert(0, 1, null) catch |err| {
                logMessage(ptr, 3, "insert text failed: {s}", .{@errorName(err)});
            };
        }
    }
}

pub export fn setRendererSolidTree(
    renderer: ?*Renderer,
    json_ptr: [*]const u8,
    json_len: usize,
) callconv(.c) void {
    if (renderer) |ptr| {
        if (ptr.destroy_started or ptr.pending_destroy) return;
        if (ptr.busy) return;
        ptr.busy = true;
        defer {
            ptr.busy = false;
            lifecycle.tryFinalize(ptr);
        }
        const data = json_ptr[0..json_len];
        solid_sync.rebuildSolidStoreFromJson(ptr, data, logMessage);
    }
}

pub export fn applyRendererSolidOps(
    renderer: ?*Renderer,
    json_ptr: [*]const u8,
    json_len: usize,
) callconv(.c) bool {
    if (renderer) |ptr| {
        if (ptr.destroy_started or ptr.pending_destroy) return false;
        if (ptr.busy) return false;
        ptr.busy = true;
        defer {
            ptr.busy = false;
            lifecycle.tryFinalize(ptr);
        }
        const data = json_ptr[0..json_len];
        return solid_sync.applySolidOps(ptr, data, logMessage);
    }
    return false;
}

// ============================================================
// Event Ring Buffer FFI Exports
// ============================================================

/// Copy event ring header (read_head, write_head, capacity, detail_capacity, dropped counts) into out buffer.
pub export fn getEventRingHeader(renderer: ?*Renderer, out_ptr: [*]u8, out_len: usize) callconv(.c) usize {
    const std = @import("std");
    if (renderer == null or out_len < @sizeOf(solid.EventRing.Header)) return 0;
    if (renderer.?.event_ring_ready) {
        if (types.eventRing(renderer.?)) |ring| {
            const header = ring.snapshotHeader();
            const bytes = std.mem.asBytes(&header);
            const dest = out_ptr[0..@sizeOf(solid.EventRing.Header)];
            @memcpy(dest, bytes);
            return @sizeOf(solid.EventRing.Header);
        }
    }
    return 0;
}

/// Get pointer to event buffer for JS TypedArray view
pub export fn getEventRingBuffer(renderer: ?*Renderer) callconv(.c) ?[*]solid.events.EventEntry {
    if (renderer) |ptr| {
        if (ptr.event_ring_ready) {
            if (types.eventRing(ptr)) |ring| {
                return ring.getBufferPtr();
            }
        }
    }
    return null;
}

/// Get pointer to detail string buffer for JS TypedArray view
pub export fn getEventRingDetail(renderer: ?*Renderer) callconv(.c) ?[*]u8 {
    if (renderer) |ptr| {
        if (ptr.event_ring_ready) {
            if (types.eventRing(ptr)) |ring| {
                return ring.getDetailPtr();
            }
        }
    }
    return null;
}

/// Acknowledge that JS has consumed events up to new_read_head
pub export fn acknowledgeEvents(renderer: ?*Renderer, new_read_head: u32) callconv(.c) void {
    if (renderer) |ptr| {
        if (ptr.event_ring_ready) {
            if (types.eventRing(ptr)) |ring| {
                ring.setReadHead(new_read_head);
            }
        }
    }
}
