const std = @import("std");
const dvui = @import("dvui");
const retained = @import("dvui_retained");
const RaylibBackend = @import("raylib-backend");
const ray = RaylibBackend.raylib;
const raygui = RaylibBackend.raygui;

const max_snapshot_bytes: usize = 16 * 1024 * 1024;

pub fn main() !void {
    if (@import("builtin").os.tag == .windows) {
        dvui.Backend.Common.windowsAttachConsole() catch {};
    }

    var gpa_instance = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa_instance.allocator();
    defer _ = gpa_instance.deinit();

    var args_arena = std.heap.ArenaAllocator.init(allocator);
    defer args_arena.deinit();
    const args = try std.process.argsAlloc(args_arena.allocator());
    if (args.len < 2) {
        std.debug.print("Usage: retained-harness <snapshot.json>\n", .{});
        return;
    }

    const snapshot_path = args[1];
    const snapshot_bytes = try std.fs.cwd().readFileAlloc(allocator, snapshot_path, max_snapshot_bytes);
    defer allocator.free(snapshot_bytes);

    retained.init();
    defer retained.deinit();

    var store: retained.NodeStore = undefined;
    try store.init(allocator);
    defer store.deinit();

    var event_ring = try retained.EventRing.init(allocator);
    defer event_ring.deinit();

    const snapshot_ok = retained.setSnapshot(&store, &event_ring, snapshot_bytes);
    if (!snapshot_ok) {
        std.debug.print("Failed to parse snapshot {s}\n", .{snapshot_path});
        return;
    }

    var title_buffer: [64]u8 = undefined;
    const title = std.fmt.bufPrintZ(&title_buffer, "DVUI Retained Harness", .{}) catch "DVUI Retained Harness";

    ray.setTraceLogLevel(ray.TraceLogLevel.warning);

    var backend = try RaylibBackend.initWindow(.{
        .gpa = allocator,
        .size = .{ .w = 1280, .h = 720 },
        .min_size = null,
        .max_size = null,
        .vsync = true,
        .title = title,
        .icon = null,
    });
    defer backend.deinit();

    var win = try dvui.Window.init(@src(), allocator, backend.backend(), .{});
    win.theme = dvui.Theme.builtin.shadcn;
    defer win.deinit();

    while (!ray.windowShouldClose()) {
        ray.beginDrawing();
        defer ray.endDrawing();

        ray.clearBackground(RaylibBackend.dvuiColorToRaylib(dvui.Color.black));

        win.begin(std.time.nanoTimestamp()) catch |err| {
            std.debug.print("Window begin failed: {s}\n", .{@errorName(err)});
            return;
        };
        defer {
            _ = win.end(.{}) catch {};
        }

        backend.addAllEvents(&win) catch {};
        if (backend.shouldBlockRaylibInput()) {
            raygui.lock();
        } else {
            raygui.unlock();
        }

        _ = retained.render(&event_ring, &store, true);
        drainEventRing(&event_ring);

        if (win.cursorRequestedFloating()) |cursor| {
            backend.setCursor(cursor);
        } else {
            backend.setCursor(win.cursorRequested());
        }
    }
}

fn drainEventRing(ring: *retained.EventRing) void {
    const header = ring.getHeader();
    if (header.read_head == header.write_head) return;
    if (header.capacity == 0) {
        ring.setReadHead(header.write_head);
        return;
    }

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
        std.debug.print("event {s} node={d} detail={s}\n", .{ @tagName(entry.kind), entry.node_id, detail });
    }

    ring.setReadHead(header.write_head);
}
