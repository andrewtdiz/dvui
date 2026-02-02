const std = @import("std");

const luaz = @import("luaz");
const luau_ui = @import("luau_ui");

const retained = @import("retained");
const solidluau_embedded = @import("solidluau_embedded");
const types = @import("types.zig");
const utils = @import("utils.zig");
const Renderer = types.Renderer;

const lua_script_paths = [_][]const u8{
    "luau/index.luau",
    "luau/ui_features_decl.luau",
    "luau/ui_features.luau",
    "luau/ui_features_all.luau",
    "luau/native_ui.luau",
};
const max_lua_script_bytes: usize = 1024 * 1024;
const max_lua_error_len: usize = 120;
var require_cache_key: u8 = 0;

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

fn dvuiDofile(state_opt: ?luaz.State.LuaState) callconv(.c) c_int {
    const lua = luaz.Lua.fromState(state_opt.?);
    const base_top = lua.state.getTop();

    const renderer_ptr = lua.state.toLightUserdata(luaz.State.upvalueIndex(1)) orelse {
        lua.state.setTop(base_top);
        lua.state.pushNil();
        lua.state.pushString("dvui_dofile missing renderer");
        return 2;
    };
    const renderer: *Renderer = @ptrCast(@alignCast(renderer_ptr));

    const path_z = lua.state.checkString(1);
    const path: []const u8 = path_z;

    var file = std.fs.cwd().openFile(path, .{ .mode = .read_only }) catch |err| {
        lua.state.setTop(base_top);
        lua.state.pushNil();
        lua.state.pushString("dofile(");
        lua.state.pushLString(path);
        lua.state.pushString(") open failed: ");
        lua.state.pushLString(@errorName(err));
        lua.state.concat(4);
        return 2;
    };
    defer file.close();

    const script_bytes = file.readToEndAlloc(renderer.allocator, max_lua_script_bytes) catch |err| {
        lua.state.setTop(base_top);
        lua.state.pushNil();
        lua.state.pushString("dofile(");
        lua.state.pushLString(path);
        lua.state.pushString(") read failed: ");
        lua.state.pushLString(@errorName(err));
        lua.state.concat(4);
        return 2;
    };
    defer renderer.allocator.free(script_bytes);

    const compile_result = luaz.Compiler.compile(script_bytes, .{}) catch |err| {
        lua.state.setTop(base_top);
        lua.state.pushNil();
        lua.state.pushString("dofile(");
        lua.state.pushLString(path);
        lua.state.pushString(") compile failed: ");
        lua.state.pushLString(@errorName(err));
        lua.state.concat(4);
        return 2;
    };
    defer compile_result.deinit();

    if (compile_result == .err) {
        const message = compile_result.err;
        const trimmed = if (message.len > max_lua_error_len) message[0..max_lua_error_len] else message;

        lua.state.setTop(base_top);
        lua.state.pushNil();
        lua.state.pushString("dofile(");
        lua.state.pushLString(path);
        lua.state.pushString(") compile error: ");
        lua.state.pushLString(trimmed);
        lua.state.concat(4);
        return 2;
    }

    const load_status = lua.state.load(path_z, compile_result.ok, 0);
    switch (load_status) {
        .ok => {},
        .errmem => {
            lua.state.setTop(base_top);
            lua.state.pushNil();
            lua.state.pushString("dofile(");
            lua.state.pushLString(path);
            lua.state.pushString(") load out of memory");
            lua.state.concat(3);
            return 2;
        },
        else => {
            lua.state.setTop(base_top);
            lua.state.pushNil();
            lua.state.pushString("dofile(");
            lua.state.pushLString(path);
            lua.state.pushString(") load failed");
            lua.state.concat(3);
            return 2;
        },
    }

    const call_status = lua.state.pcall(0, 1, 0);
    switch (call_status) {
        .ok => {
            const new_top = lua.state.getTop();
            return @intCast(new_top - base_top);
        },
        else => {
            var err_message_buf: [max_lua_error_len]u8 = undefined;
            var err_message: []const u8 = @tagName(call_status);

            if (lua.state.getTop() > base_top) {
                if (lua.state.toString(-1)) |err_z| {
                    const err_raw: []const u8 = err_z;
                    const n: usize = @min(err_raw.len, max_lua_error_len);
                    std.mem.copyForwards(u8, err_message_buf[0..n], err_raw[0..n]);
                    err_message = err_message_buf[0..n];
                }
            }

            lua.state.setTop(base_top);
            lua.state.pushNil();
            lua.state.pushString("dofile(");
            lua.state.pushLString(path);
            lua.state.pushString(") runtime error: ");
            lua.state.pushLString(err_message);
            lua.state.concat(4);
            return 2;
        },
    }
}

fn dvuiRequire(state_opt: ?luaz.State.LuaState) callconv(.c) c_int {
    const lua = luaz.Lua.fromState(state_opt.?);
    const base_top = lua.state.getTop();

    const renderer_ptr = lua.state.toLightUserdata(luaz.State.upvalueIndex(1)) orelse {
        lua.state.setTop(base_top);
        lua.state.pushLString("require missing renderer");
        lua.state.raiseError();
    };
    const renderer: *Renderer = @ptrCast(@alignCast(renderer_ptr));

    const module_z = lua.state.checkString(1);
    const module_full: []const u8 = module_z;
    const module_id = if (std.mem.endsWith(u8, module_full, ".luau")) module_full[0 .. module_full.len - 5] else module_full;

    lua.state.pushLightUserdata(@ptrCast(&require_cache_key));
    _ = lua.state.getTable(luaz.State.REGISTRYINDEX);
    if (lua.state.isNil(-1)) {
        lua.state.pop(1);
        lua.state.createTable(0, 64);
        lua.state.pushLightUserdata(@ptrCast(&require_cache_key));
        lua.state.pushValue(-2);
        lua.state.setTable(luaz.State.REGISTRYINDEX);
    }

    lua.state.pushLString(module_id);
    _ = lua.state.rawGet(-2);
    if (!lua.state.isNil(-1)) {
        lua.state.remove(-2);
        return 1;
    }
    lua.state.pop(1);

    const embedded_source = solidluau_embedded.get(module_id);
    var owned_source: ?[]u8 = null;
    defer if (owned_source) |bytes| renderer.allocator.free(bytes);

    const source_bytes: []const u8 = blk: {
        if (embedded_source) |src| break :blk src;

        var path_buf: [512]u8 = undefined;
        const path = if (std.mem.endsWith(u8, module_full, ".luau"))
            module_full
        else
            std.fmt.bufPrint(&path_buf, "{s}.luau", .{module_full}) catch {
                lua.state.setTop(base_top);
                lua.state.pushLString("require invalid module id");
                lua.state.raiseError();
            };

        var file = std.fs.cwd().openFile(path, .{ .mode = .read_only }) catch |err| {
            lua.state.setTop(base_top);
            lua.state.pushLString("require(");
            lua.state.pushLString(module_id);
            lua.state.pushLString(") open failed: ");
            lua.state.pushLString(@errorName(err));
            lua.state.concat(4);
            lua.state.raiseError();
        };
        defer file.close();

        const bytes = file.readToEndAlloc(renderer.allocator, max_lua_script_bytes) catch |err| {
            lua.state.setTop(base_top);
            lua.state.pushLString("require(");
            lua.state.pushLString(module_id);
            lua.state.pushLString(") read failed: ");
            lua.state.pushLString(@errorName(err));
            lua.state.concat(4);
            lua.state.raiseError();
        };
        owned_source = bytes;
        break :blk bytes;
    };

    const compile_result = luaz.Compiler.compile(source_bytes, .{}) catch |err| {
        lua.state.setTop(base_top);
        lua.state.pushLString("require(");
        lua.state.pushLString(module_id);
        lua.state.pushLString(") compile failed: ");
        lua.state.pushLString(@errorName(err));
        lua.state.concat(4);
        lua.state.raiseError();
    };
    defer compile_result.deinit();

    if (compile_result == .err) {
        const message = compile_result.err;
        const trimmed = if (message.len > max_lua_error_len) message[0..max_lua_error_len] else message;
        lua.state.setTop(base_top);
        lua.state.pushLString("require(");
        lua.state.pushLString(module_id);
        lua.state.pushLString(") compile error: ");
        lua.state.pushLString(trimmed);
        lua.state.concat(4);
        lua.state.raiseError();
    }

    const load_status = lua.state.load(module_z, compile_result.ok, 0);
    switch (load_status) {
        .ok => {},
        else => {
            lua.state.setTop(base_top);
            lua.state.pushLString("require(");
            lua.state.pushLString(module_id);
            lua.state.pushLString(") load error: ");
            lua.state.pushLString(@tagName(load_status));
            lua.state.concat(4);
            lua.state.raiseError();
        },
    }

    const call_status = lua.state.pcall(0, 1, 0);
    switch (call_status) {
        .ok => {},
        else => {
            var err_message_buf: [max_lua_error_len]u8 = undefined;
            var err_message: []const u8 = @tagName(call_status);
            if (lua.state.getTop() > base_top) {
                if (lua.state.toString(-1)) |err_z| {
                    const err_raw: []const u8 = err_z;
                    const n: usize = @min(err_raw.len, max_lua_error_len);
                    std.mem.copyForwards(u8, err_message_buf[0..n], err_raw[0..n]);
                    err_message = err_message_buf[0..n];
                }
            }
            lua.state.setTop(base_top);
            lua.state.pushLString("require(");
            lua.state.pushLString(module_id);
            lua.state.pushLString(") runtime error: ");
            lua.state.pushLString(err_message);
            lua.state.concat(4);
            lua.state.raiseError();
        },
    }

    if (lua.state.isNil(-1)) {
        lua.state.pop(1);
        lua.state.pushBoolean(true);
    }

    lua.state.pushLString(module_id);
    lua.state.pushValue(-2);
    lua.state.setTable(-4);
    lua.state.remove(-2);
    return 1;
}

fn registerLuaFileLoader(renderer: *Renderer, lua: *luaz.Lua) void {
    lua.state.pushLightUserdata(@ptrCast(renderer));
    lua.state.pushCClosureK(dvuiDofile, "dvui_dofile", 1, null);
    lua.state.setGlobal("dvui_dofile");
    lua.state.pushLightUserdata(@ptrCast(renderer));
    lua.state.pushCClosureK(dvuiRequire, "require", 1, null);
    lua.state.setGlobal("require");
}

fn loadLuaScript(renderer: *Renderer) bool {
    var file_opt: ?std.fs.File = null;
    var chosen_path: []const u8 = "";
    for (lua_script_paths) |candidate| {
        file_opt = std.fs.cwd().openFile(candidate, .{ .mode = .read_only }) catch null;
        if (file_opt != null) {
            chosen_path = candidate;
            break;
        }
    }

    if (file_opt == null) {
        logMessage(renderer, 3, "lua script open failed (no candidate found)", .{});
        return false;
    }

    var file = file_opt.?;
    defer file.close();

    const script_bytes = file.readToEndAlloc(renderer.allocator, max_lua_script_bytes) catch |err| {
        logLuaError(renderer, "script read", err);
        return false;
    };
    defer renderer.allocator.free(script_bytes);

    if (renderer.lua_state) |lua_state| {
        logMessage(renderer, 1, "lua script: {s}", .{chosen_path});
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

pub fn ensureRetainedStore(renderer: *Renderer) !*retained.NodeStore {
    if (renderer.retained_store_ready) {
        if (utils.retainedStore(renderer)) |store| {
            return store;
        }
        renderer.retained_store_ready = false;
    }

    const store = blk: {
        if (utils.retainedStore(renderer)) |existing| {
            break :blk existing;
        }
        const allocated = renderer.allocator.create(retained.NodeStore) catch {
            logMessage(renderer, 3, "retained store alloc failed", .{});
            return error.OutOfMemory;
        };
        renderer.retained_store_ptr = allocated;
        break :blk allocated;
    };

    store.init(renderer.allocator) catch |err| {
        logMessage(renderer, 3, "retained store init failed: {s}", .{@errorName(err)});
        return err;
    };
    renderer.retained_store_ready = true;
    return store;
}


fn initLua(renderer: *Renderer) void {
    if (renderer.lua_ready) return;

    const store = ensureRetainedStore(renderer) catch |err| {
        logLuaError(renderer, "retained store", err);
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
    registerLuaFileLoader(renderer, lua_ptr);

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
    if (renderer.retained_store_ready) {
        if (utils.retainedStore(renderer)) |store| {
            store.deinit();
        }
        renderer.retained_store_ready = false;
    }
    if (utils.retainedStore(renderer)) |store| {
        renderer.allocator.destroy(store);
        renderer.retained_store_ptr = null;
    }
    if (renderer.retained_event_ring_ready) {
        if (utils.retainedEventRing(renderer)) |ring| {
            ring.deinit();
        }
        renderer.retained_event_ring_ready = false;
    }
    if (utils.retainedEventRing(renderer)) |ring| {
        renderer.allocator.destroy(ring);
        renderer.retained_event_ring_ptr = null;
    }
    retained.deinit();
}

pub fn finalizeDestroy(renderer: *Renderer) void {
    if (renderer.destroy_started) return;
    renderer.destroy_started = true;
    deinitRenderer(renderer);
    _ = renderer.gpa_instance.deinit();
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
        .webgpu = null,
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
        .frame_count = 0,
        .retained_store_ready = false,
        .retained_store_ptr = null,
        .retained_event_ring_ptr = null,
        .retained_event_ring_ready = false,
        .lua_state = null,
        .lua_ui = null,
        .lua_ready = false,
        .screenshot_key_enabled = false,
        .screenshot_index = 0,
    };

    renderer.allocator = renderer.gpa_instance.allocator();
    renderer.frame_arena = std.heap.ArenaAllocator.init(renderer.allocator);

    // Initialize event ring buffer for retained Lua UI.
    const retained_ring_instance = renderer.allocator.create(retained.EventRing) catch {
        renderer.frame_arena.deinit();
        _ = renderer.gpa_instance.deinit();
        std.heap.c_allocator.destroy(renderer);
        return null;
    };
    renderer.retained_event_ring_ptr = retained_ring_instance;
    retained_ring_instance.* = retained.EventRing.init(renderer.allocator) catch {
        renderer.allocator.destroy(retained_ring_instance);
        renderer.retained_event_ring_ptr = null;
        renderer.retained_event_ring_ready = false;
        renderer.frame_arena.deinit();
        _ = renderer.gpa_instance.deinit();
        std.heap.c_allocator.destroy(renderer);
        return null;
    };
    renderer.retained_event_ring_ready = true;

    retained.init();

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
