const std = @import("std");
const builtin = @import("builtin");

const dvui = @import("dvui");
const RaylibBackend = @import("raylib-backend");
const ray = RaylibBackend.raylib;
const raygui = RaylibBackend.raygui;
const solid_renderer = @import("solid_renderer.zig");
const solid_types = @import("jsruntime/solid/types.zig");

const LogFn = fn (level: u8, msg_ptr: [*]const u8, msg_len: usize) callconv(.c) void;
const EventFn = fn (name_ptr: [*]const u8, name_len: usize, data_ptr: [*]const u8, data_len: usize) callconv(.c) void;

const CommandHeader = extern struct {
    opcode: u8,
    flags: u8,
    reserved: u16,
    node_id: u32,
    parent_id: u32,
    x: f32,
    y: f32,
    width: f32,
    height: f32,
    payload_offset: u32,
    payload_size: u32,
    extra: u32,
};

const Renderer = struct {
    gpa_instance: std.heap.GeneralPurposeAllocator(.{}) = undefined,
    allocator: std.mem.Allocator,
    backend: ?RaylibBackend.RaylibBackend = null,
    window: ?dvui.Window = null,
    log_cb: ?*const LogFn = null,
    event_cb: ?*const EventFn = null,
    headers: std.ArrayListUnmanaged(CommandHeader) = .{},
    payload: std.ArrayListUnmanaged(u8) = .{},
    frame_arena: std.heap.ArenaAllocator,
    size: [2]u32 = .{ 0, 0 },
    window_ready: bool = false,
    busy: bool = false,
    callback_depth: usize = 0,
    pending_destroy: bool = false,
    destroy_started: bool = false,
    solid_store_ready: bool = false,
    solid_store: solid_types.NodeStore = undefined,
};

const flag_absolute: u8 = 1;

fn colorFromPacked(value: u32) dvui.Color {
    return .{
        .r = @intCast((value >> 24) & 0xff),
        .g = @intCast((value >> 16) & 0xff),
        .b = @intCast((value >> 8) & 0xff),
        .a = @intCast(value & 0xff),
    };
}

fn ensureSolidStore(renderer: *Renderer) !void {
    if (renderer.solid_store_ready) return;
    renderer.solid_store.init(renderer.allocator) catch |err| {
        logMessage(renderer, 3, "solid store init failed: {s}", .{@errorName(err)});
        return err;
    };
    renderer.solid_store_ready = true;
}

fn logMessage(renderer: *Renderer, level: u8, comptime fmt: []const u8, args: anytype) void {
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

fn sendFrameEvent(renderer: *Renderer) void {
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

fn sendWindowClosedEvent(renderer: *Renderer) void {
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

fn ensureWindow(renderer: *Renderer) !void {
    if (renderer.window_ready or renderer.size[0] == 0 or renderer.size[1] == 0) return;

    logMessage(renderer, 1, "ensureWindow size={d}x{d}", .{ renderer.size[0], renderer.size[1] });
    RaylibBackend.enableRaylibLogging();

    if (builtin.os.tag == .windows) {
        dvui.Backend.Common.windowsAttachConsole() catch {};
    }

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

    var win = blk: {
        if (renderer.backend) |*backend| {
            break :blk try dvui.Window.init(@src(), renderer.allocator, backend.backend(), .{});
        }
        unreachable;
    };
    errdefer win.deinit();
    win.theme = dvui.Theme.builtin.shadcn;
    renderer.window = win;
    renderer.window_ready = true;
    logMessage(renderer, 1, "window initialized", .{});
}

fn teardownWindow(renderer: *Renderer) void {
    if (renderer.window) |*win| {
        win.deinit();
        renderer.window = null;
    }
    if (renderer.backend) |*backend| {
        backend.deinit();
        renderer.backend = null;
    }
    renderer.window_ready = false;
    logMessage(renderer, 1, "window torn down", .{});
}

fn updateCommands(
    renderer: *Renderer,
    headers_ptr: [*]const u8,
    headers_len: usize,
    payload_ptr: [*]const u8,
    payload_len: usize,
    command_count: u32,
) void {
    if (command_count == 0) {
        renderer.headers.resize(renderer.allocator, 0) catch {};
        renderer.payload.resize(renderer.allocator, 0) catch {};
        return;
    }

    const header_size = @sizeOf(CommandHeader);
    const count: usize = @as(usize, @intCast(command_count));
    const expected_header_bytes: usize = header_size * count;
    if (headers_len < expected_header_bytes) {
        logMessage(renderer, 2, "commit ignored: header bytes short ({d} < {d})", .{ headers_len, expected_header_bytes });
        return;
    }

    renderer.headers.resize(renderer.allocator, count) catch {
        logMessage(renderer, 3, "commit ignored: unable to resize header buffer", .{});
        return;
    };
    const header_bytes = headers_ptr[0..expected_header_bytes];
    for (renderer.headers.items, 0..) |*dst, i| {
        const base = i * header_size;
        dst.* = std.mem.bytesToValue(CommandHeader, header_bytes[base .. base + header_size]);
    }

    renderer.payload.resize(renderer.allocator, payload_len) catch {
        logMessage(renderer, 3, "commit ignored: unable to resize payload buffer", .{});
        return;
    };
    if (payload_len > 0) {
        std.mem.copyForwards(u8, renderer.payload.items, payload_ptr[0..payload_len]);
    }
}

fn renderCommandsDvui(renderer: *Renderer, win: *dvui.Window) void {
    const allocator = renderer.frame_arena.allocator();
    const payload = renderer.payload.items;
    const scale = win.natural_scale;
    const offset = win.rect_pixels;

    const LayoutNode = struct {
        header: *const CommandHeader,
        children: std.ArrayListUnmanaged(u32) = .{},
        layout: dvui.Rect = .{},
    };

    var nodes = std.AutoHashMap(u32, *LayoutNode).init(allocator);
    defer nodes.deinit();

    var root_children: std.ArrayListUnmanaged(u32) = .{};
    defer root_children.deinit(allocator);

    for (renderer.headers.items) |*cmd| {
        const node = allocator.create(LayoutNode) catch continue;
        node.* = .{ .header = cmd, .children = .{}, .layout = .{} };
        nodes.put(cmd.node_id, node) catch {};
    }

    for (renderer.headers.items) |cmd| {
        const parent_id = cmd.parent_id;
        const child_id = cmd.node_id;
        if (parent_id == 0) {
            _ = root_children.append(allocator, child_id) catch {};
            continue;
        }
        if (nodes.getPtr(parent_id)) |parent_node_ptr| {
            _ = parent_node_ptr.*.children.append(allocator, child_id) catch {};
        } else {
            _ = root_children.append(allocator, child_id) catch {};
        }
    }

    const root_rect = dvui.Rect{
        .x = 0,
        .y = 0,
        .w = @floatFromInt(renderer.size[0]),
        .h = @floatFromInt(renderer.size[1]),
    };

    const measureNode = struct {
        fn run(header: *const CommandHeader, payload_bytes: []const u8) dvui.Size {
            if (header.opcode == 2) {
                const start: usize = @intCast(header.payload_offset);
                const len: usize = @intCast(header.payload_size);
                const end = start + len;
                if (start <= payload_bytes.len and end <= payload_bytes.len) {
                    const font = (dvui.Options{}).fontGet();
                    return font.textSize(payload_bytes[start..end]);
                }
            }
            return .{ .w = header.width, .h = header.height };
        }
    }.run;

    const layoutNode = struct {
        fn run(
            all_nodes: *std.AutoHashMap(u32, *LayoutNode),
            node_id: u32,
            parent_rect: dvui.Rect,
            payload_bytes: []const u8,
            flow_y: *f32,
        ) void {
            const node = all_nodes.getPtr(node_id) orelse return;
            const header = node.*.header;
            const measured = measureNode(header, payload_bytes);
            const is_abs = (header.flags & flag_absolute) != 0;

            var rect = dvui.Rect{
                .x = parent_rect.x,
                .y = parent_rect.y,
                .w = if (header.width != 0) header.width else parent_rect.w,
                .h = if (header.height != 0) header.height else measured.h,
            };

            if (is_abs) {
                rect.x = parent_rect.x + header.x;
                rect.y = parent_rect.y + header.y;
                if (rect.w == 0) rect.w = measured.w;
                if (rect.h == 0) rect.h = measured.h;
            } else {
                rect.x = parent_rect.x;
                rect.y = flow_y.*;
                flow_y.* = rect.y + rect.h;
            }

            node.*.layout = rect;

            var child_flow = rect.y;
            for (node.*.children.items) |child_id| {
                run(all_nodes, child_id, rect, payload_bytes, &child_flow);
            }
        }
    }.run;

    var root_flow: f32 = root_rect.y;
    for (root_children.items) |child_id| {
        layoutNode(&nodes, child_id, root_rect, payload, &root_flow);
    }

    for (renderer.headers.items) |cmd| {
        const logical = blk: {
            if (nodes.getPtr(cmd.node_id)) |node_ptr| {
                break :blk node_ptr.*.layout;
            }
            break :blk dvui.Rect{ .x = cmd.x, .y = cmd.y, .w = cmd.width, .h = cmd.height };
        };

        const phys = dvui.Rect.Physical{
            .x = offset.x + logical.x * scale,
            .y = offset.y + logical.y * scale,
            .w = logical.w * scale,
            .h = logical.h * scale,
        };

        switch (cmd.opcode) {
            1 => {
                var builder = dvui.Triangles.Builder.init(renderer.frame_arena.allocator(), 4, 6) catch continue;
                defer builder.deinit(renderer.frame_arena.allocator());

                const color = colorFromPacked(cmd.extra).opacity(win.alpha);
                const pma = dvui.Color.PMA.fromColor(color);
                builder.appendVertex(.{ .pos = .{ .x = phys.x, .y = phys.y }, .col = pma });
                builder.appendVertex(.{ .pos = .{ .x = phys.x + phys.w, .y = phys.y }, .col = pma });
                builder.appendVertex(.{ .pos = .{ .x = phys.x + phys.w, .y = phys.y + phys.h }, .col = pma });
                builder.appendVertex(.{ .pos = .{ .x = phys.x, .y = phys.y + phys.h }, .col = pma });
                builder.appendTriangles(&.{ 0, 1, 2, 0, 2, 3 });

                const tris = builder.build();
                dvui.renderTriangles(tris, null) catch |err| {
                    logMessage(renderer, 2, "renderTriangles failed: {s}", .{@errorName(err)});
                };
            },
            2 => {
                const start: usize = @intCast(cmd.payload_offset);
                const len: usize = @intCast(cmd.payload_size);
                if (start > payload.len) continue;
                const end = start + len;
                if (end > payload.len) continue;
                const text_slice = payload[start..end];

                const font = (dvui.Options{}).fontGet();
                const base_height = font.textHeight();
                const text_scale = if (base_height == 0) 1.0 else phys.h / base_height;

                const rs = dvui.RectScale{
                    .r = phys,
                    .s = text_scale,
                };
                const opts = dvui.render.TextOptions{
                    .font = font,
                    .text = text_slice,
                    .rs = rs,
                    .color = colorFromPacked(cmd.extra),
                };
                dvui.renderText(opts) catch |err| {
                    logMessage(renderer, 2, "renderText failed: {s}", .{@errorName(err)});
                };
            },
            else => {},
        }
    }
}

fn renderFrame(renderer: *Renderer) void {
    if (!renderer.window_ready) return;

    if (ray.windowShouldClose()) {
        teardownWindow(renderer);
        renderer.pending_destroy = true;
        sendWindowClosedEvent(renderer);
        return;
    }

    _ = renderer.frame_arena.reset(.retain_capacity);

    ray.beginDrawing();
    defer ray.endDrawing();

    ray.clearBackground(RaylibBackend.dvuiColorToRaylib(dvui.Color.black));

    if (renderer.window) |*win| {
        win.begin(std.time.nanoTimestamp()) catch |err| {
            logMessage(renderer, 3, "window begin failed: {s}", .{@errorName(err)});
            return;
        };
        defer {
            _ = win.end(.{}) catch |err| {
                logMessage(renderer, 3, "window end failed: {s}", .{@errorName(err)});
            };
        }

        if (renderer.backend) |*backend| {
            backend.addAllEvents(win) catch |err| {
                logMessage(renderer, 2, "event pump failed: {s}", .{@errorName(err)});
            };
            if (backend.shouldBlockRaylibInput()) {
                raygui.lock();
            } else {
                raygui.unlock();
            }
        }

        if (renderer.solid_store_ready) {
            solid_renderer.render(null, &renderer.solid_store);
        } else {
            renderCommandsDvui(renderer, win);
        }

        if (renderer.backend) |*backend| {
            if (win.cursorRequestedFloating()) |cursor| {
                backend.setCursor(cursor);
            } else {
                backend.setCursor(win.cursorRequested());
            }
        }
    }

    ray.drawFPS(10, 10);
    sendFrameEvent(renderer);
}

fn deinitRenderer(renderer: *Renderer) void {
    teardownWindow(renderer);
    renderer.headers.deinit(renderer.allocator);
    renderer.payload.deinit(renderer.allocator);
    renderer.frame_arena.deinit();
    if (renderer.solid_store_ready) {
        renderer.solid_store.deinit();
        renderer.solid_store_ready = false;
    }
}

fn finalizeDestroy(renderer: *Renderer) void {
    if (renderer.destroy_started) return;
    renderer.destroy_started = true;
    var gpa_instance = renderer.gpa_instance;
    deinitRenderer(renderer);
    _ = gpa_instance.deinit();
    std.heap.c_allocator.destroy(renderer);
}

fn tryFinalize(renderer: *Renderer) void {
    if (!renderer.pending_destroy) return;
    if (renderer.busy) return;
    if (renderer.callback_depth > 0) return;
    finalizeDestroy(renderer);
}

pub export fn createRenderer(log_cb: ?*const LogFn, event_cb: ?*const EventFn) callconv(.c) ?*Renderer {
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
        .solid_store = undefined,
    };

    renderer.allocator = renderer.gpa_instance.allocator();
    renderer.frame_arena = std.heap.ArenaAllocator.init(renderer.allocator);

    return renderer;
}

pub export fn destroyRenderer(renderer: ?*Renderer) callconv(.c) void {
    if (renderer) |ptr| {
        if (ptr.destroy_started) return;
        ptr.log_cb = null;
        ptr.event_cb = null;
        ptr.pending_destroy = true;
        tryFinalize(ptr);
    }
}

pub export fn resizeRenderer(renderer: ?*Renderer, width: u32, height: u32) callconv(.c) void {
    if (renderer) |ptr| {
        if (ptr.destroy_started or ptr.pending_destroy) return;
        if (ptr.busy) return;
        ptr.busy = true;
        defer {
            ptr.busy = false;
            tryFinalize(ptr);
        }
        ptr.size = .{ width, height };
        if (ptr.window_ready) {
            ray.setWindowSize(@intCast(width), @intCast(height));
        } else {
            ensureWindow(ptr) catch |err| {
                logMessage(ptr, 3, "resize failed to open window: {s}", .{@errorName(err)});
            };
        }
    }
}

pub export fn setRendererText(renderer: ?*Renderer, text_ptr: [*]const u8, text_len: usize) callconv(.c) void {
    if (renderer) |ptr| {
        if (ptr.destroy_started or ptr.pending_destroy) return;
        if (ptr.busy) return;
        ptr.busy = true;
        defer {
            ptr.busy = false;
            tryFinalize(ptr);
        }
        ensureSolidStore(ptr) catch return;

        const text_slice = text_ptr[0..text_len];
        ptr.solid_store.setTextNode(1, text_slice) catch |err| {
            logMessage(ptr, 3, "setText failed: {s}", .{@errorName(err)});
            return;
        };

        const root = ptr.solid_store.node(0) orelse return;
        var present = false;
        for (root.children.items) |cid| {
            if (cid == 1) {
                present = true;
                break;
            }
        }
        if (!present) {
            ptr.solid_store.insert(0, 1, null) catch |err| {
                logMessage(ptr, 3, "insert text failed: {s}", .{@errorName(err)});
            };
        }
    }
}

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
            tryFinalize(ptr);
        }
        updateCommands(ptr, header_ptr, header_len, payload_ptr, payload_len, command_count);
    }
}

pub export fn presentRenderer(renderer: ?*Renderer) callconv(.c) void {
    if (renderer) |ptr| {
        if (ptr.pending_destroy) return;
        if (ptr.destroy_started) return;
        if (!ptr.window_ready) {
            ensureWindow(ptr) catch |err| {
                logMessage(ptr, 3, "present failed to open window: {s}", .{@errorName(err)});
            };
        }
        ptr.busy = true;
        defer {
            ptr.busy = false;
            tryFinalize(ptr);
        }
        renderFrame(ptr);
    }
}
