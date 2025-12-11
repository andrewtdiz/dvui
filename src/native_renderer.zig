const std = @import("std");
const builtin = @import("builtin");

const dvui = @import("dvui");
const RaylibBackend = @import("raylib-backend");
const ray = RaylibBackend.raylib;
const raygui = RaylibBackend.raygui;

const jsruntime = @import("jsruntime/mod.zig");
const solid = @import("solid/mod.zig");

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
    solid_store_ptr: ?*anyopaque = null,
    solid_seq_last: u64 = 0,
    frame_count: u64 = 0,
    runtime_ptr: ?*anyopaque = null,
    // Event ring buffer for Zig→JS event dispatch (Phase 2)
    event_ring_ptr: ?*anyopaque = null,
    event_ring_ready: bool = false,
};

fn asOpaquePtr(comptime T: type, raw: ?*anyopaque) ?*T {
    if (raw) |ptr| {
        return @ptrCast(@alignCast(ptr));
    }
    return null;
}

fn runtime(renderer: *Renderer) ?*jsruntime.JSRuntime {
    return asOpaquePtr(jsruntime.JSRuntime, renderer.runtime_ptr);
}

fn solidStore(renderer: *Renderer) ?*solid.NodeStore {
    return asOpaquePtr(solid.NodeStore, renderer.solid_store_ptr);
}

fn eventRing(renderer: *Renderer) ?*solid.EventRing {
    return asOpaquePtr(solid.EventRing, renderer.event_ring_ptr);
}

const flag_absolute: u8 = 1;
const frame_event_interval: u64 = 6; // ~10fps when running at 60fps

const SolidOp = struct {
    op: []const u8,
    id: u32 = 0,
    parent: ?u32 = null,
    before: ?u32 = null,
    tag: ?[]const u8 = null,
    text: ?[]const u8 = null,
    className: ?[]const u8 = null,
    // Listen op fields
    eventType: ?[]const u8 = null,
    // Generic set op fields
    name: ?[]const u8 = null,
    value: ?[]const u8 = null,
    src: ?[]const u8 = null,
    // Transform fields (optional; last-write-wins)
    rotation: ?f32 = null,
    scaleX: ?f32 = null,
    scaleY: ?f32 = null,
    anchorX: ?f32 = null,
    anchorY: ?f32 = null,
    translateX: ?f32 = null,
    translateY: ?f32 = null,
    // Visual fields (optional; last-write-wins)
    opacity: ?f32 = null,
    cornerRadius: ?f32 = null,
    background: ?u32 = null,
    textColor: ?u32 = null,
    clipChildren: ?bool = null,
};

const SolidOpBatch = struct {
    ops: []const SolidOp = &.{},
    seq: ?u64 = null,
};

fn applyTransformFields(store: *solid.NodeStore, id: u32, op: SolidOp) OpError!void {
    const target = store.node(id) orelse return error.MissingId;
    var changed = false;
    if (op.rotation) |v| {
        target.transform.rotation = v;
        changed = true;
    }
    if (op.scaleX) |v| {
        target.transform.scale[0] = v;
        changed = true;
    }
    if (op.scaleY) |v| {
        target.transform.scale[1] = v;
        changed = true;
    }
    if (op.anchorX) |v| {
        target.transform.anchor[0] = v;
        changed = true;
    }
    if (op.anchorY) |v| {
        target.transform.anchor[1] = v;
        changed = true;
    }
    if (op.translateX) |v| {
        target.transform.translation[0] = v;
        changed = true;
    }
    if (op.translateY) |v| {
        target.transform.translation[1] = v;
        changed = true;
    }
    if (changed) {
        store.markNodeChanged(id);
    }
}

fn applyVisualFields(store: *solid.NodeStore, id: u32, op: SolidOp) OpError!void {
    const target = store.node(id) orelse return error.MissingId;
    var changed = false;
    if (op.opacity) |v| {
        target.visual.opacity = v;
        changed = true;
    }
    if (op.cornerRadius) |v| {
        target.visual.corner_radius = v;
        changed = true;
    }
    if (op.background) |c| {
        target.visual.background = .{ .value = c };
        changed = true;
    }
    if (op.textColor) |c| {
        target.visual.text_color = .{ .value = c };
        changed = true;
    }
    if (op.clipChildren) |flag| {
        target.visual.clip_children = flag;
        changed = true;
    }
    if (changed) {
        store.markNodeChanged(id);
    }
}

const OpError = error{
    OutOfMemory,
    UnknownOp,
    MissingId,
    MissingParent,
    MissingChild,
    MissingTag,
};

fn colorFromPacked(value: u32) dvui.Color {
    return .{
        .r = @intCast((value >> 24) & 0xff),
        .g = @intCast((value >> 16) & 0xff),
        .b = @intCast((value >> 8) & 0xff),
        .a = @intCast(value & 0xff),
    };
}

fn ensureSolidStore(renderer: *Renderer) !*solid.NodeStore {
    if (renderer.solid_store_ready) {
        if (solidStore(renderer)) |store| {
            return store;
        }
        renderer.solid_store_ready = false;
    }

    const store = blk: {
        if (solidStore(renderer)) |existing| {
            break :blk existing;
        }
        const allocated = renderer.allocator.create(solid.NodeStore) catch {
            logMessage(renderer, 3, "solid store alloc failed", .{});
            return error.OutOfMemory;
        };
        renderer.solid_store_ptr = allocated;
        break :blk allocated;
    };

    store.init(renderer.allocator) catch |err| {
        logMessage(renderer, 3, "solid store init failed: {s}", .{@errorName(err)});
        return err;
    };
    renderer.solid_store_ready = true;
    return store;
}

fn rebuildSolidStoreFromJson(renderer: *Renderer, json_bytes: []const u8) void {
    // Ensure the store exists, then rebuild it from scratch based on the JSON payload.
    const store = blk: {
        if (solidStore(renderer)) |existing| {
            break :blk existing;
        }
        const allocated = renderer.allocator.create(solid.NodeStore) catch {
            logMessage(renderer, 3, "solid store alloc failed", .{});
            return;
        };
        renderer.solid_store_ptr = allocated;
        break :blk allocated;
    };

    if (renderer.solid_store_ready) {
        store.deinit();
        renderer.solid_store_ready = false;
    }

    store.init(renderer.allocator) catch |err| {
        logMessage(renderer, 3, "solid store reset failed: {s}", .{@errorName(err)});
        return;
    };
    renderer.solid_store_ready = true;

    const NodeEntry = struct {
        id: u32,
        tag: []const u8,
        parent: ?u32 = null,
        text: ?[]const u8 = null,
        className: ?[]const u8 = null,
        // Transform fields
        rotation: ?f32 = null,
        scaleX: ?f32 = null,
        scaleY: ?f32 = null,
        anchorX: ?f32 = null,
        anchorY: ?f32 = null,
        translateX: ?f32 = null,
        translateY: ?f32 = null,
        // Visual fields
        opacity: ?f32 = null,
        cornerRadius: ?f32 = null,
        background: ?u32 = null,
        textColor: ?u32 = null,
        clipChildren: ?bool = null,
    };

    const Payload = struct {
        nodes: []const NodeEntry = &.{},
    };

    var parsed = std.json.parseFromSlice(Payload, renderer.allocator, json_bytes, .{
        .ignore_unknown_fields = true,
    }) catch |err| {
        logMessage(renderer, 3, "solid tree parse failed: {s}", .{@errorName(err)});
        return;
    };
    defer parsed.deinit();

    const payload = parsed.value;
    logMessage(renderer, 2, "solid snapshot nodes={d}", .{payload.nodes.len});

    // First pass: create/upsert nodes.
    for (payload.nodes) |node| {
        if (node.id == 0) continue; // 0 is reserved for root
        if (std.mem.eql(u8, node.tag, "text")) {
            store.setTextNode(node.id, node.text orelse "") catch |err| {
                logMessage(renderer, 3, "setTextNode failed for {d}: {s}", .{ node.id, @errorName(err) });
            };
            continue;
        }
        if (std.mem.eql(u8, node.tag, "slot")) {
            store.upsertSlot(node.id) catch |err| {
                logMessage(renderer, 3, "upsertSlot failed for {d}: {s}", .{ node.id, @errorName(err) });
            };
        } else {
            store.upsertElement(node.id, node.tag) catch |err| {
                logMessage(renderer, 3, "upsertElement failed for {d}: {s}", .{ node.id, @errorName(err) });
                return;
            };
        }
        if (node.className) |cls| {
            store.setClassName(node.id, cls) catch |err| {
                logMessage(renderer, 3, "setClassName failed for {d}: {s}", .{ node.id, @errorName(err) });
            };
        }
        if (store.node(node.id)) |target| {
            var touched = false;
            if (node.rotation) |v| {
                target.transform.rotation = v;
                touched = true;
            }
            if (node.scaleX) |v| {
                target.transform.scale[0] = v;
                touched = true;
            }
            if (node.scaleY) |v| {
                target.transform.scale[1] = v;
                touched = true;
            }
            if (node.anchorX) |v| {
                target.transform.anchor[0] = v;
                touched = true;
            }
            if (node.anchorY) |v| {
                target.transform.anchor[1] = v;
                touched = true;
            }
            if (node.translateX) |v| {
                target.transform.translation[0] = v;
                touched = true;
            }
            if (node.translateY) |v| {
                target.transform.translation[1] = v;
                touched = true;
            }
            if (node.opacity) |v| {
                target.visual.opacity = v;
                touched = true;
            }
            if (node.cornerRadius) |v| {
                target.visual.corner_radius = v;
                touched = true;
            }
            if (node.background) |c| {
                target.visual.background = .{ .value = c };
                touched = true;
            }
            if (node.textColor) |c| {
                target.visual.text_color = .{ .value = c };
                touched = true;
            }
            if (node.clipChildren) |flag| {
                target.visual.clip_children = flag;
                touched = true;
            }
            if (touched) {
                store.markNodeChanged(node.id);
            }
        }
    }

    // Second pass: wire parent/child relationships in order.
    for (payload.nodes) |node| {
        if (node.id == 0) continue;
        const parent_id: u32 = node.parent orelse 0;
        store.insert(parent_id, node.id, null) catch |err| {
            logMessage(renderer, 3, "insert failed for {d} -> {d}: {s}", .{ parent_id, node.id, @errorName(err) });
        };
    }

    if (store.node(0)) |root| {
        logMessage(renderer, 2, "solid snapshot root children={d}", .{root.children.items.len});
        if (root.children.items.len == 0) {
            renderer.solid_store_ready = false;
        }
    }
}

fn applySolidOp(store: *solid.NodeStore, op: SolidOp) OpError!void {
    if (op.op.len == 0) return error.UnknownOp;

    if (std.mem.eql(u8, op.op, "create")) {
        const tag = op.tag orelse return error.MissingTag;
        if (std.mem.eql(u8, tag, "text")) {
            try store.setTextNode(op.id, op.text orelse "");
        } else if (std.mem.eql(u8, tag, "slot")) {
            try store.upsertSlot(op.id);
        } else {
            try store.upsertElement(op.id, tag);
        }
        if (op.className) |cls| {
            try store.setClassName(op.id, cls);
        }
        const parent_id: u32 = op.parent orelse 0;
        try store.insert(parent_id, op.id, op.before);
        return;
    }

    if (std.mem.eql(u8, op.op, "remove")) {
        if (op.id == 0) return error.MissingId;
        store.remove(op.id);
        return;
    }

    if (std.mem.eql(u8, op.op, "move") or std.mem.eql(u8, op.op, "insert")) {
        if (op.id == 0) return error.MissingId;
        const parent_id = op.parent orelse return error.MissingParent;
        if (store.node(op.id) == null) return error.MissingChild;
        if (store.node(parent_id) == null) return error.MissingParent;
        try store.insert(parent_id, op.id, op.before);
        return;
    }

    if (std.mem.eql(u8, op.op, "set_text")) {
        if (op.id == 0) return error.MissingId;
        try store.setTextNode(op.id, op.text orelse "");
        return;
    }

    if (std.mem.eql(u8, op.op, "set_class")) {
        if (op.id == 0) return error.MissingId;
        const cls = op.className orelse return error.MissingTag;
        try store.setClassName(op.id, cls);
        return;
    }

    if (std.mem.eql(u8, op.op, "set_transform")) {
        if (op.id == 0) return error.MissingId;
        try applyTransformFields(store, op.id, op);
        return;
    }

    if (std.mem.eql(u8, op.op, "set_visual")) {
        if (op.id == 0) return error.MissingId;
        try applyVisualFields(store, op.id, op);
        return;
    }

    // Listen op - register event listener on node (extracted from reference)
    if (std.mem.eql(u8, op.op, "listen")) {
        if (op.id == 0) return error.MissingId;
        const event_type = op.eventType orelse return error.MissingTag;
        try store.addListener(op.id, event_type);
        return;
    }

    // Generic set op - route by property name (extracted from reference)
    if (std.mem.eql(u8, op.op, "set")) {
        if (op.id == 0) return error.MissingId;
        const prop_name = op.name orelse return error.MissingTag;

        // Route to appropriate setter based on property name
        if (std.mem.eql(u8, prop_name, "class") or std.mem.eql(u8, prop_name, "className")) {
            const val = op.value orelse op.className orelse return error.MissingTag;
            try store.setClassName(op.id, val);
            return;
        }
        if (std.mem.eql(u8, prop_name, "src")) {
            const val = op.value orelse op.src orelse return error.MissingTag;
            try store.setImageSource(op.id, val);
            return;
        }
        if (std.mem.eql(u8, prop_name, "value")) {
            const val = op.value orelse return error.MissingTag;
            try store.setInputValue(op.id, val);
            return;
        }
        // Unknown property - log but don't fail
        return;
    }

    return error.UnknownOp;
}

fn applySolidOps(renderer: *Renderer, json_bytes: []const u8) bool {
    const store = ensureSolidStore(renderer) catch return false;

    var parsed = std.json.parseFromSlice(SolidOpBatch, renderer.allocator, json_bytes, .{
        .ignore_unknown_fields = true,
    }) catch |err| {
        logMessage(renderer, 3, "solid ops parse failed: {s}", .{@errorName(err)});
        return false;
    };
    defer parsed.deinit();

    const batch = parsed.value;
    const seq = batch.seq orelse renderer.solid_seq_last + 1;
    if (seq <= renderer.solid_seq_last) {
        logMessage(renderer, 2, "solid ops dropped stale batch seq={d} last={d}", .{ seq, renderer.solid_seq_last });
        return false;
    }
    logMessage(renderer, 1, "solid ops seq={d} count={d}", .{ seq, batch.ops.len });
    for (batch.ops) |op| {
        applySolidOp(store, op) catch |err| {
            logMessage(renderer, 3, "solid op failed: {s} op={s} id={d} parent={?d} before={?d}", .{
                @errorName(err),
                op.op,
                op.id,
                op.parent,
                op.before,
            });
            return false;
        };
    }
    renderer.solid_seq_last = seq;

    const root = store.node(0) orelse {
        logMessage(renderer, 3, "solid store missing root after ops", .{});
        renderer.solid_store_ready = false;
        return false;
    };
    logMessage(renderer, 1, "solid store nodes={d}", .{store.nodes.count()});
    logMessage(renderer, 1, "solid ops root children={d}", .{root.children.items.len});

    if (root.children.items.len == 0) {
        logMessage(renderer, 2, "solid ops produced empty root; requesting resync", .{});
        renderer.solid_store_ready = false;
        return false;
    }

    renderer.solid_store_ready = true;
    return true;
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

        const frame_start = std.time.nanoTimestamp();

        const runtime_ptr = runtime(renderer);
        const store = solidStore(renderer);
        const drew_solid = renderer.solid_store_ready and store != null and solid.render(runtime_ptr, store.?);
        if (!drew_solid) {
            renderCommandsDvui(renderer, win);
        }

        if (renderer.backend) |*backend| {
            if (win.cursorRequestedFloating()) |cursor| {
                backend.setCursor(cursor);
            } else {
                backend.setCursor(win.cursorRequested());
            }
        }

        // Temporarily disable per-frame logging to diagnose FFI crash
        _ = frame_start;
    }

    ray.drawFPS(10, 10);
    renderer.frame_count +%= 1;
    if (frame_event_interval == 0 or renderer.frame_count % frame_event_interval == 0) {
        sendFrameEvent(renderer);
    }
}

fn deinitRenderer(renderer: *Renderer) void {
    teardownWindow(renderer);
    renderer.headers.deinit(renderer.allocator);
    renderer.payload.deinit(renderer.allocator);
    renderer.frame_arena.deinit();
    if (runtime(renderer)) |rt| {
        rt.deinit();
        renderer.allocator.destroy(rt);
        renderer.runtime_ptr = null;
    }
    if (renderer.solid_store_ready) {
        if (solidStore(renderer)) |store| {
            store.deinit();
        }
        renderer.solid_store_ready = false;
    }
    if (solidStore(renderer)) |store| {
        renderer.allocator.destroy(store);
        renderer.solid_store_ptr = null;
    }
    if (renderer.event_ring_ready) {
        if (eventRing(renderer)) |ring| {
            ring.deinit();
        }
        renderer.event_ring_ready = false;
    }
    if (eventRing(renderer)) |ring| {
        renderer.allocator.destroy(ring);
        renderer.event_ring_ptr = null;
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

fn forwardEvent(ctx: ?*anyopaque, name: []const u8, payload: []const u8) void {
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
        .solid_store_ptr = null,
        .frame_count = 0,
        .event_ring_ptr = null,
        .event_ring_ready = false,
        .runtime_ptr = null,
    };

    renderer.allocator = renderer.gpa_instance.allocator();
    renderer.frame_arena = std.heap.ArenaAllocator.init(renderer.allocator);

    const runtime_instance = renderer.allocator.create(jsruntime.JSRuntime) catch {
        renderer.frame_arena.deinit();
        _ = renderer.gpa_instance.deinit();
        std.heap.c_allocator.destroy(renderer);
        return null;
    };
    renderer.runtime_ptr = runtime_instance;
    runtime_instance.* = jsruntime.JSRuntime.init("") catch {
        renderer.allocator.destroy(runtime_instance);
        renderer.runtime_ptr = null;
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
        renderer.runtime_ptr = null;
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
        renderer.runtime_ptr = null;
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
        const store = ensureSolidStore(ptr) catch return;

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
            tryFinalize(ptr);
        }
        const data = json_ptr[0..json_len];
        rebuildSolidStoreFromJson(ptr, data);
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
            tryFinalize(ptr);
        }
        const data = json_ptr[0..json_len];
        return applySolidOps(ptr, data);
    }
    return false;
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

// === Event Ring Buffer FFI Exports ===

/// Get event ring header (read_head, write_head, capacity, detail_capacity)
pub export fn getEventRingHeader(renderer: ?*Renderer) callconv(.c) solid.EventRing.Header {
    if (renderer) |ptr| {
        if (ptr.event_ring_ready) {
            if (eventRing(ptr)) |ring| {
                return ring.getHeader();
            }
        }
    }
    return .{ .read_head = 0, .write_head = 0, .capacity = 0, .detail_capacity = 0 };
}

/// Get pointer to event buffer for JS TypedArray view
pub export fn getEventRingBuffer(renderer: ?*Renderer) callconv(.c) ?[*]solid.events.EventEntry {
    if (renderer) |ptr| {
        if (ptr.event_ring_ready) {
            if (eventRing(ptr)) |ring| {
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
            if (eventRing(ptr)) |ring| {
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
            if (eventRing(ptr)) |ring| {
                ring.setReadHead(new_read_head);
            }
        }
    }
}

/// Push an event to the ring buffer (called from Zig render code)
pub fn pushEvent(renderer: *Renderer, kind: solid.EventKind, node_id: u32, detail: ?[]const u8) bool {
    if (!renderer.event_ring_ready) return false;
    if (eventRing(renderer)) |ring| {
        return ring.push(kind, node_id, detail);
    }
    return false;
}

// Simple test export to verify DLL exports work
pub export fn testExportWorks() callconv(.c) i32 {
    return 12345;
}
