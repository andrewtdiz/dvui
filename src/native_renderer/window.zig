const std = @import("std");
const builtin = @import("builtin");

const dvui = @import("dvui");
const RaylibBackend = @import("raylib-backend");
const ray = RaylibBackend.raylib;
const raygui = RaylibBackend.raygui;
const webgpu = @import("webgpu");
const retained = @import("retained");
const luaz = @import("luaz");

const commands = @import("commands.zig");
const lifecycle = @import("lifecycle.zig");
const logMessage = lifecycle.logMessage;
const types = @import("types.zig");
const utils = @import("utils.zig");
const Renderer = types.Renderer;
const profiling = @import("profiling.zig");

// ============================================================
// Window Initialization
// ============================================================

pub fn ensureWindow(renderer: *Renderer) !void {
    if (renderer.window_ready or renderer.size[0] == 0 or renderer.size[1] == 0) return;

    logMessage(renderer, 1, "ensureWindow size={d}x{d}", .{ renderer.size[0], renderer.size[1] });

    if (builtin.os.tag == .windows) {
        dvui.Backend.Common.windowsAttachConsole() catch {};
    }

    // Reduce Raylib info spam (texture/FBO load logs) — keep warnings/errors.
    ray.setTraceLogLevel(ray.TraceLogLevel.warning);

    var title_buffer: [64]u8 = undefined;
    const title = std.fmt.bufPrintZ(&title_buffer, "DVUI Native Renderer", .{}) catch "DVUI";

    renderer.backend = try RaylibBackend.initWindow(.{
        .gpa = renderer.allocator,
        .size = .{
            .w = @floatFromInt(renderer.size[0]),
            .h = @floatFromInt(renderer.size[1]),
        },
        .min_size = null,
        .max_size = null,
        .vsync = true,
        .title = title,
        .icon = null,
    });
    errdefer {
        if (renderer.backend) |*backend| {
            backend.deinit();
        }
        renderer.backend = null;
    }

    renderer.size = .{ @intCast(ray.getScreenWidth()), @intCast(ray.getScreenHeight()) };
    renderer.pixel_size = .{ @intCast(ray.getRenderWidth()), @intCast(ray.getRenderHeight()) };

    renderer.webgpu = try webgpu.Renderer.init(renderer.allocator, .{
        .width = renderer.size[0],
        .height = renderer.size[1],
    }, .{
        .width = renderer.pixel_size[0],
        .height = renderer.pixel_size[1],
    });
    errdefer {
        if (renderer.webgpu) |*wgpu_renderer| {
            wgpu_renderer.deinit();
        }
        renderer.webgpu = null;
    }

    var win = try dvui.Window.init(@src(), renderer.allocator, renderer.webgpu.?.dvuiBackend(), .{});
    errdefer win.deinit();
    win.theme = dvui.Theme.builtin.shadcn;
    renderer.window = win;
    renderer.window_ready = true;
    logMessage(renderer, 1, "window initialized", .{});
}

// ============================================================
// Window Teardown
// ============================================================

pub fn teardownWindow(renderer: *Renderer) void {
    if (renderer.window) |*win| {
        retained.deinit();
        win.deinit();
        renderer.window = null;
    }
    if (renderer.webgpu) |*wgpu_renderer| {
        wgpu_renderer.deinit();
        renderer.webgpu = null;
    }
    if (renderer.backend) |*backend| {
        backend.deinit();
        renderer.backend = null;
    }
    renderer.window_ready = false;
    logMessage(renderer, 1, "window torn down", .{});
}

// ============================================================
// Frame Rendering
// ============================================================

fn sendResizeEventIfNeeded(renderer: *Renderer) void {
    const screen_w: u32 = @intCast(ray.getScreenWidth());
    const screen_h: u32 = @intCast(ray.getScreenHeight());
    const pixel_w: u32 = @intCast(ray.getRenderWidth());
    const pixel_h: u32 = @intCast(ray.getRenderHeight());
    if (screen_w == 0 or screen_h == 0) return;
    const logical_changed = screen_w != renderer.size[0] or screen_h != renderer.size[1];
    const pixel_changed = pixel_w != renderer.pixel_size[0] or pixel_h != renderer.pixel_size[1];
    if (!logical_changed and !pixel_changed) return;
    renderer.size = .{ screen_w, screen_h };
    renderer.pixel_size = .{ pixel_w, pixel_h };
    lifecycle.sendWindowResizeEvent(renderer, screen_w, screen_h, pixel_w, pixel_h);
    if (renderer.webgpu) |*wgpu_renderer| {
        wgpu_renderer.resize(.{ .width = screen_w, .height = screen_h }, .{ .width = pixel_w, .height = pixel_h });
    }
}

fn saveScreenshotPng(renderer: *Renderer, picture: *dvui.Picture) void {
    var name_buf: [96]u8 = undefined;
    const index = renderer.screenshot_index;
    renderer.screenshot_index +%= 1;
    const name = std.fmt.bufPrint(&name_buf, "screenshot-{d}.png", .{index}) catch {
        logMessage(renderer, 3, "screenshot name failed", .{});
        return;
    };
    const file = std.fs.cwd().createFile(name, .{}) catch |err| {
        logMessage(renderer, 3, "screenshot create failed: {s}", .{@errorName(err)});
        return;
    };
    defer file.close();
    var buf: [8192]u8 = undefined;
    var writer = file.writer(&buf);
    picture.png(&writer.interface) catch |err| {
        logMessage(renderer, 3, "screenshot write failed: {s}", .{@errorName(err)});
        return;
    };
    writer.end() catch |err| {
        logMessage(renderer, 3, "screenshot finalize failed: {s}", .{@errorName(err)});
        return;
    };
    logMessage(renderer, 1, "screenshot saved: {s}", .{name});
}

fn drainLuaEvents(renderer: *Renderer, lua_state: *luaz.Lua, ring: *retained.EventRing) void {
    const header = ring.getHeader();
    if (header.read_head == header.write_head or header.capacity == 0) {
        ring.setReadHead(header.write_head);
        return;
    }

    if (!lifecycle.isLuaFuncPresent(lua_state, "on_event")) {
        ring.setReadHead(header.write_head);
        return;
    }

    const globals = lua_state.globals();

    var cursor = header.read_head;
    while (cursor < header.write_head) : (cursor += 1) {
        const buffer_index: usize = @intCast(cursor % header.capacity);
        const entry = ring.buffer[buffer_index];
        var detail: []const u8 = "";
        if (entry.detail_len > 0) {
            const detail_offset: usize = @intCast(entry.detail_offset);
            const detail_length: usize = @intCast(entry.detail_len);
            const detail_end = detail_offset + detail_length;
            if (detail_end <= ring.detail_buffer.len) {
                detail = ring.detail_buffer[detail_offset..detail_end];
            }
        }

        const kind_int: u32 = @intFromEnum(entry.kind);

        const call_result = globals.call("on_event", .{ kind_int, entry.node_id, detail }, void) catch |err| {
            lifecycle.logLuaError(renderer, "on_event", err);
            lifecycle.teardownLua(renderer);
            return;
        };
        switch (call_result) {
            .ok => {},
            else => {
                logMessage(renderer, 3, "lua on_event did not complete", .{});
                lifecycle.teardownLua(renderer);
                return;
            },
        }
    }

    ring.setReadHead(header.write_head);
}

pub fn renderFrame(renderer: *Renderer) void {
    if (!renderer.window_ready) return;

    const frame_start_ns = profiling.mark();
    ray.pollInputEvents();

    if (ray.windowShouldClose()) {
        teardownWindow(renderer);
        renderer.pending_destroy = true;
        lifecycle.sendWindowClosedEvent(renderer);
        return;
    }

    sendResizeEventIfNeeded(renderer);

    _ = renderer.frame_arena.reset(.retain_capacity);

    if (renderer.window) |*win| {
        win.begin(std.time.nanoTimestamp()) catch |err| {
            logMessage(renderer, 3, "window begin failed: {s}", .{@errorName(err)});
            return;
        };
        defer {
            if (renderer.webgpu) |*wgpu_renderer| {
                const present_start_ns = profiling.mark();
                wgpu_renderer.render() catch |err| {
                    logMessage(renderer, 3, "webgpu render failed: {s}", .{@errorName(err)});
                };
                profiling.addPresent(&renderer.profiler, present_start_ns);
            }
        }
        defer {
            _ = win.end(.{}) catch |err| {
                logMessage(renderer, 3, "window end failed: {s}", .{@errorName(err)});
            };
        }

        if (renderer.backend) |*backend| {
            const input_start_ns = profiling.mark();
            backend.addAllEvents(win) catch |err| {
                logMessage(renderer, 2, "event pump failed: {s}", .{@errorName(err)});
            };
            if (backend.shouldBlockRaylibInput()) {
                raygui.lock();
            } else {
                raygui.unlock();
            }
            profiling.addInput(&renderer.profiler, input_start_ns);
        }

        var picture_opt: ?dvui.Picture = null;
        if (renderer.screenshot_key_enabled) {
            const pressed = ray.isKeyPressed(ray.KeyboardKey.print_screen) or ray.isKeyPressed(ray.KeyboardKey.f12);
            if (pressed) {
                picture_opt = dvui.Picture.start(dvui.windowRectPixels());
                if (picture_opt == null) {
                    logMessage(renderer, 2, "screenshot not supported", .{});
                }
            }
        }

        const retained_event_ring_ptr = utils.retainedEventRing(renderer);
        if (renderer.lua_ready) {
            if (renderer.lua_state) |lua_state| {
                if (retained_event_ring_ptr) |ring| {
                    const lua_events_start_ns = profiling.mark();
                    drainLuaEvents(renderer, lua_state, ring);
                    profiling.addLuaEvents(&renderer.profiler, lua_events_start_ns);
                }
            }
        }

        if (renderer.lua_ready) {
            if (renderer.lua_state) |lua_state| {
                if (lifecycle.isLuaFuncPresent(lua_state, "update")) {
                    const lua_update_start_ns = profiling.mark();
                    const globals = lua_state.globals();
                    const dt = dvui.secondsSinceLastFrame();
                    const window_rect = dvui.windowRect();
                    const mouse_nat = win.mouse_pt.toNatural();
                    const input_table = lua_state.createTable(.{ .rec = 12 });
                    defer input_table.deinit();
                    input_table.set("width", window_rect.w) catch |err| {
                        lifecycle.logLuaError(renderer, "update input", err);
                        lifecycle.teardownLua(renderer);
                        return;
                    };
                    input_table.set("height", window_rect.h) catch |err| {
                        lifecycle.logLuaError(renderer, "update input", err);
                        lifecycle.teardownLua(renderer);
                        return;
                    };
                    input_table.set("mouseX", mouse_nat.x) catch |err| {
                        lifecycle.logLuaError(renderer, "update input", err);
                        lifecycle.teardownLua(renderer);
                        return;
                    };
                    input_table.set("mouseY", mouse_nat.y) catch |err| {
                        lifecycle.logLuaError(renderer, "update input", err);
                        lifecycle.teardownLua(renderer);
                        return;
                    };
                    const left_down = ray.isMouseButtonDown(ray.MouseButton.left);
                    input_table.set("mouseDown", left_down) catch |err| {
                        lifecycle.logLuaError(renderer, "update input", err);
                        lifecycle.teardownLua(renderer);
                        return;
                    };
                    const mods = win.modifiers;
                    input_table.set("shift", mods.shift()) catch |err| {
                        lifecycle.logLuaError(renderer, "update input", err);
                        lifecycle.teardownLua(renderer);
                        return;
                    };
                    input_table.set("ctrl", mods.control()) catch |err| {
                        lifecycle.logLuaError(renderer, "update input", err);
                        lifecycle.teardownLua(renderer);
                        return;
                    };
                    input_table.set("alt", mods.alt()) catch |err| {
                        lifecycle.logLuaError(renderer, "update input", err);
                        lifecycle.teardownLua(renderer);
                        return;
                    };
                    input_table.set("cmd", mods.command()) catch |err| {
                        lifecycle.logLuaError(renderer, "update input", err);
                        lifecycle.teardownLua(renderer);
                        return;
                    };

                    const call_result = globals.call("update", .{ dt, input_table }, void) catch |err| {
                        lifecycle.logLuaError(renderer, "update", err);
                        lifecycle.teardownLua(renderer);
                        return;
                    };
                    switch (call_result) {
                        .ok => {},
                        else => {
                            logMessage(renderer, 3, "lua update did not complete", .{});
                            lifecycle.teardownLua(renderer);
                            return;
                        },
                    }
                    profiling.addLuaUpdate(&renderer.profiler, lua_update_start_ns);
                }
            }
        }

        const retained_store = utils.retainedStore(renderer);
        var retained_timings: retained.FrameTimings = .{};
        const retained_start_ns = profiling.mark();
        const drew_retained = renderer.retained_store_ready and retained_store != null and retained.render(retained_event_ring_ptr, retained_store.?, true, &retained_timings);
        profiling.addRetained(&renderer.profiler, retained_start_ns, retained_timings);
        if (!drew_retained) {
            const commands_start_ns = profiling.mark();
            commands.renderCommandsDvui(renderer, win);
            profiling.addCommands(&renderer.profiler, commands_start_ns);
        }

        if (picture_opt) |*picture| {
            win.endRendering(.{});
            picture.stop();
            saveScreenshotPng(renderer, picture);
            picture.deinit();
        }

        if (renderer.backend) |*backend| {
            if (win.cursorRequestedFloating()) |cursor| {
                backend.setCursor(cursor);
            } else {
                backend.setCursor(win.cursorRequested());
            }
        }
    }

    renderer.frame_count +%= 1;
    profiling.endFrame(&renderer.profiler, logMessage, renderer, frame_start_ns);
    if (types.frame_event_interval == 0 or renderer.frame_count % types.frame_event_interval == 0) {
        lifecycle.sendFrameEvent(renderer);
    }
}
