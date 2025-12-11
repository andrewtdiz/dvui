const std = @import("std");

const jsruntime = @import("jsruntime");
const solid = @import("solid");

const types = @import("types.zig");
const Renderer = types.Renderer;

// ============================================================
// Logging
// ============================================================

pub fn logMessage(renderer: *Renderer, level: u8, comptime fmt: []const u8, args: anytype) void {
    if (renderer.pending_destroy or renderer.destroy_started) return;
    if (renderer.log_cb) |log_fn| {
        var buffer: [160]u8 = undefined;
        const msg = std.fmt.bufPrint(&buffer, fmt, args) catch return;
        const msg_ptr: [*]const u8 = @ptrCast(msg.ptr);
        renderer.callback_depth += 1;
        defer {
            renderer.callback_depth -= 1;
            tryFinalize(renderer);
        }
        log_fn(level, msg_ptr, msg.len);
    }
}

// ============================================================
// Event Dispatch
// ============================================================

pub fn sendFrameEvent(renderer: *Renderer) void {
    if (renderer.event_cb) |event_fn| {
        var payload: [8]u8 = undefined;
        std.mem.writeInt(u32, payload[0..4], 0, .little);
        std.mem.writeInt(u32, payload[4..], @intCast(renderer.headers.items.len), .little);
        const name = "frame";
        renderer.callback_depth += 1;
        defer {
            renderer.callback_depth -= 1;
            tryFinalize(renderer);
        }
        event_fn(name, name.len, &payload, payload.len);
    }
}

pub fn sendWindowClosedEvent(renderer: *Renderer) void {
    if (renderer.event_cb) |event_fn| {
        var payload: [4]u8 = .{ 0, 0, 0, 0 };
        const name = "window_closed";
        renderer.callback_depth += 1;
        defer {
            renderer.callback_depth -= 1;
            tryFinalize(renderer);
        }
        event_fn(name, name.len, &payload, payload.len);
    }
}

pub fn forwardEvent(ctx: ?*anyopaque, name: []const u8, payload: []const u8) void {
    const renderer = ctx orelse return;
    const typed: *Renderer = @ptrCast(@alignCast(renderer));
    if (typed.event_cb) |event_fn| {
        const name_ptr: [*]const u8 = @ptrCast(name.ptr);
        const payload_ptr: [*]const u8 = @ptrCast(payload.ptr);
        typed.callback_depth += 1;
        defer {
            typed.callback_depth -= 1;
            tryFinalize(typed);
        }
        event_fn(name_ptr, name.len, payload_ptr, payload.len);
    }
}

// ============================================================
// Finalization & Destruction
// ============================================================

pub fn tryFinalize(renderer: *Renderer) void {
    if (!renderer.pending_destroy) return;
    if (renderer.busy) return;
    if (renderer.callback_depth > 0) return;
    finalizeDestroy(renderer);
}

pub fn deinitRenderer(renderer: *Renderer) void {
    @import("window.zig").teardownWindow(renderer);
    renderer.headers.deinit(renderer.allocator);
    renderer.payload.deinit(renderer.allocator);
    renderer.frame_arena.deinit();
    renderer.runtime.deinit(renderer.allocator);
    if (renderer.solid_store_ready) {
        if (types.solidStore(renderer)) |store| {
            store.deinit();
        }
        renderer.solid_store_ready = false;
    }
    if (types.solidStore(renderer)) |store| {
        renderer.allocator.destroy(store);
        renderer.solid_store_ptr = null;
    }
    if (renderer.event_ring_ready) {
        if (types.eventRing(renderer)) |ring| {
            ring.deinit();
        }
        renderer.event_ring_ready = false;
    }
    if (types.eventRing(renderer)) |ring| {
        renderer.allocator.destroy(ring);
        renderer.event_ring_ptr = null;
    }
}

pub fn finalizeDestroy(renderer: *Renderer) void {
    if (renderer.destroy_started) return;
    renderer.destroy_started = true;
    var gpa_instance = renderer.gpa_instance;
    deinitRenderer(renderer);
    _ = gpa_instance.deinit();
    std.heap.c_allocator.destroy(renderer);
}

// ============================================================
// Renderer Creation
// ============================================================

pub fn createRendererImpl(log_cb: ?*const types.LogFn, event_cb: ?*const types.EventFn) ?*Renderer {
    const renderer = std.heap.c_allocator.create(Renderer) catch return null;

    renderer.* = .{
        .gpa_instance = std.heap.GeneralPurposeAllocator(.{}){},
        .allocator = undefined,
        .backend = null,
        .window = null,
        .log_cb = log_cb,
        .event_cb = event_cb,
        .headers = .{},
        .payload = .{},
        .frame_arena = undefined,
        .size = .{ 0, 0 },
        .window_ready = false,
        .busy = false,
        .callback_depth = 0,
        .pending_destroy = false,
        .destroy_started = false,
        .solid_store_ready = false,
        .solid_store_ptr = null,
        .frame_count = 0,
        .event_ring_ptr = null,
        .event_ring_ready = false,
        .runtime = .{},
    };

    renderer.allocator = renderer.gpa_instance.allocator();
    renderer.frame_arena = std.heap.ArenaAllocator.init(renderer.allocator);

    const runtime_instance = renderer.allocator.create(jsruntime.JSRuntime) catch {
        renderer.frame_arena.deinit();
        _ = renderer.gpa_instance.deinit();
        std.heap.c_allocator.destroy(renderer);
        return null;
    };
    renderer.runtime.set(runtime_instance);
    runtime_instance.* = jsruntime.JSRuntime.init("") catch {
        renderer.runtime.clear();
        renderer.allocator.destroy(runtime_instance);
        renderer.frame_arena.deinit();
        _ = renderer.gpa_instance.deinit();
        std.heap.c_allocator.destroy(renderer);
        return null;
    };
    runtime_instance.event_cb = &forwardEvent;
    runtime_instance.event_ctx = renderer;

    // Initialize event ring buffer for Zig→JS event dispatch
    const ring_instance = renderer.allocator.create(solid.EventRing) catch {
        runtime_instance.deinit();
        renderer.allocator.destroy(runtime_instance);
        renderer.runtime.clear();
        renderer.frame_arena.deinit();
        _ = renderer.gpa_instance.deinit();
        std.heap.c_allocator.destroy(renderer);
        return null;
    };
    renderer.event_ring_ptr = ring_instance;
    ring_instance.* = solid.EventRing.init(renderer.allocator) catch {
        renderer.allocator.destroy(ring_instance);
        renderer.event_ring_ptr = null;
        runtime_instance.deinit();
        renderer.allocator.destroy(runtime_instance);
        renderer.runtime.clear();
        renderer.frame_arena.deinit();
        _ = renderer.gpa_instance.deinit();
        std.heap.c_allocator.destroy(renderer);
        return null;
    };
    renderer.event_ring_ready = true;

    // Link event ring to runtime so render code can push events directly
    runtime_instance.event_ring = ring_instance;

    return renderer;
}

pub fn destroyRendererImpl(renderer: ?*Renderer) void {
    if (renderer) |ptr| {
        if (ptr.destroy_started) return;
        ptr.log_cb = null;
        ptr.event_cb = null;
        ptr.pending_destroy = true;
        tryFinalize(ptr);
    }
}
