const std = @import("std");

const luaz = @import("luaz");
const luau_ui = @import("luau_ui");
const solid = @import("solid");

const solid_sync = @import("solid_sync.zig");
const types = @import("types.zig");
const Renderer = types.Renderer;

const lua_script_path = "scripts/native_ui.luau";
const max_lua_script_bytes: usize = 1024 * 1024;
const max_lua_error_len: usize = 120;

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

// ============================================================
// Luau Lifecycle
// ============================================================

pub fn isLuaFuncPresent(lua: *luaz.Lua, name: []const u8) bool {
    const globals = lua.globals();
    const lua_func = globals.get(name, luaz.Lua.Function) catch return false;
    lua_func.deinit();
    return true;
}

pub fn logLuaError(renderer: *Renderer, label: []const u8, err: anyerror) void {
    const err_name = @errorName(err);
    const err_msg = if (err_name.len > max_lua_error_len) err_name[0..max_lua_error_len] else err_name;
    logMessage(renderer, 3, "lua {s} failed: {s}", .{ label, err_msg });
}

fn loadLuaScript(renderer: *Renderer) bool {
    var file = std.fs.cwd().openFile(lua_script_path, .{ .mode = .read_only }) catch |err| {
        logLuaError(renderer, "script open", err);
        return false;
    };
    defer file.close();

    const script_bytes = file.readToEndAlloc(renderer.allocator, max_lua_script_bytes) catch |err| {
        logLuaError(renderer, "script read", err);
        return false;
    };
    defer renderer.allocator.free(script_bytes);

    if (renderer.lua_state) |lua_state| {
        const compile_result = luaz.Compiler.compile(script_bytes, .{}) catch |err| {
            logLuaError(renderer, "script compile", err);
            return false;
        };
        defer compile_result.deinit();
        if (compile_result == .err) {
            const message = compile_result.err;
            const trimmed = if (message.len > max_lua_error_len) message[0..max_lua_error_len] else message;
            logMessage(renderer, 3, "lua script compile error: {s}", .{trimmed});
            return false;
        }
        const exec_result = lua_state.exec(compile_result.ok, void) catch |err| {
            logLuaError(renderer, "script exec", err);
            return false;
        };
        switch (exec_result) {
            .ok => return true,
            else => {
                logMessage(renderer, 3, "lua script exec did not complete", .{});
                return false;
            },
        }
    }

    logMessage(renderer, 3, "lua state missing", .{});
    return false;
}

fn callLuaInit(renderer: *Renderer) bool {
    if (renderer.lua_state) |lua_state| {
        if (!isLuaFuncPresent(lua_state, "init")) {
            return true;
        }
        const globals = lua_state.globals();
        const call_result = globals.call("init", .{}, void) catch |err| {
            logLuaError(renderer, "init", err);
            return false;
        };
        switch (call_result) {
            .ok => return true,
            else => {
                logMessage(renderer, 3, "lua init did not complete", .{});
                return false;
            },
        }
    }
    return false;
}

pub fn teardownLua(renderer: *Renderer) void {
    if (renderer.lua_ready) {
        if (renderer.lua_ui) |lua_ui| {
            lua_ui.deinit();
        }
        renderer.lua_ready = false;
    }
    if (renderer.lua_ui) |lua_ui| {
        renderer.allocator.destroy(lua_ui);
        renderer.lua_ui = null;
    }
    if (renderer.lua_state) |lua_state| {
        lua_state.deinit();
        renderer.allocator.destroy(lua_state);
        renderer.lua_state = null;
    }
}

fn initLua(renderer: *Renderer) void {
    if (renderer.lua_ready) return;

    const store = solid_sync.ensureSolidStore(renderer, logMessage) catch |err| {
        logLuaError(renderer, "solid store", err);
        return;
    };

    const lua_ptr = renderer.allocator.create(luaz.Lua) catch |err| {
        logLuaError(renderer, "state alloc", err);
        return;
    };
    lua_ptr.* = luaz.Lua.init(&renderer.allocator) catch |err| {
        renderer.allocator.destroy(lua_ptr);
        logLuaError(renderer, "state init", err);
        return;
    };
    lua_ptr.openLibs();

    const lua_ui_ptr = renderer.allocator.create(luau_ui.LuaUi) catch |err| {
        lua_ptr.deinit();
        renderer.allocator.destroy(lua_ptr);
        logLuaError(renderer, "ui alloc", err);
        return;
    };
    lua_ui_ptr.init(store, lua_ptr, renderer.log_cb) catch |err| {
        renderer.allocator.destroy(lua_ui_ptr);
        lua_ptr.deinit();
        renderer.allocator.destroy(lua_ptr);
        logLuaError(renderer, "ui init", err);
        return;
    };

    renderer.lua_state = lua_ptr;
    renderer.lua_ui = lua_ui_ptr;

    if (!loadLuaScript(renderer)) {
        teardownLua(renderer);
        return;
    }
    if (!callLuaInit(renderer)) {
        teardownLua(renderer);
        return;
    }

    renderer.lua_ready = true;
    logMessage(renderer, 1, "lua ready", .{});
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

pub fn sendWindowResizeEvent(renderer: *Renderer, width: u32, height: u32, pixel_width: u32, pixel_height: u32) void {
    if (renderer.event_cb) |event_fn| {
        var payload: [16]u8 = undefined;
        std.mem.writeInt(u32, payload[0..4], width, .little);
        std.mem.writeInt(u32, payload[4..8], height, .little);
        std.mem.writeInt(u32, payload[8..12], pixel_width, .little);
        std.mem.writeInt(u32, payload[12..16], pixel_height, .little);
        const name = "window_resize";
        renderer.callback_depth += 1;
        defer {
            renderer.callback_depth -= 1;
            tryFinalize(renderer);
        }
        event_fn(name, name.len, &payload, payload.len);
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
    teardownLua(renderer);
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
        .pixel_size = .{ 0, 0 },
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
        .lua_state = null,
        .lua_ui = null,
        .lua_ready = false,
    };

    renderer.allocator = renderer.gpa_instance.allocator();
    renderer.frame_arena = std.heap.ArenaAllocator.init(renderer.allocator);

    // Initialize event ring buffer for Zig→JS event dispatch
    const ring_instance = renderer.allocator.create(solid.EventRing) catch {
        renderer.frame_arena.deinit();
        _ = renderer.gpa_instance.deinit();
        std.heap.c_allocator.destroy(renderer);
        return null;
    };
    renderer.event_ring_ptr = ring_instance;
    ring_instance.* = solid.EventRing.init(renderer.allocator) catch {
        renderer.allocator.destroy(ring_instance);
        renderer.event_ring_ptr = null;
        renderer.frame_arena.deinit();
        _ = renderer.gpa_instance.deinit();
        std.heap.c_allocator.destroy(renderer);
        return null;
    };
    renderer.event_ring_ready = true;

    initLua(renderer);

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
