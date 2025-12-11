const std = @import("std");

const dvui = @import("dvui");

const lifecycle = @import("lifecycle.zig");
const logMessage = lifecycle.logMessage;
const types = @import("types.zig");
const Renderer = types.Renderer;

// ============================================================
// Command Buffer Update
// ============================================================

pub fn updateCommands(
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

    const header_size = @sizeOf(types.CommandHeader);
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
        dst.* = std.mem.bytesToValue(types.CommandHeader, header_bytes[base .. base + header_size]);
    }

    renderer.payload.resize(renderer.allocator, payload_len) catch {
        logMessage(renderer, 3, "commit ignored: unable to resize payload buffer", .{});
        return;
    };
    if (payload_len > 0) {
        std.mem.copyForwards(u8, renderer.payload.items, payload_ptr[0..payload_len]);
    }
}

// ============================================================
// DVUI Command Rendering
// ============================================================

pub fn renderCommandsDvui(renderer: *Renderer, win: *dvui.Window) void {
    const allocator = renderer.frame_arena.allocator();
    const payload = renderer.payload.items;
    const scale = win.natural_scale;
    const offset = win.rect_pixels;

    const LayoutNode = struct {
        header: *const types.CommandHeader,
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
        fn run(header: *const types.CommandHeader, payload_bytes: []const u8) dvui.Size {
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
            const is_abs = (header.flags & types.flag_absolute) != 0;

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

                const color = types.colorFromPacked(cmd.extra).opacity(win.alpha);
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
                    .color = types.colorFromPacked(cmd.extra),
                };
                dvui.renderText(opts) catch |err| {
                    logMessage(renderer, 2, "renderText failed: {s}", .{@errorName(err)});
                };
            },
            else => {},
        }
    }
}
