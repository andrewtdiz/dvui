const std = @import("std");

const solid = @import("solid");

const types = @import("types.zig");
const Renderer = types.Renderer;

// ============================================================
// SolidOp Types
// ============================================================

pub const SolidOp = struct {
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
    placeholder: ?[]const u8 = null,
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
    // Scroll fields
    scroll: ?bool = null,
    scrollX: ?f32 = null,
    scrollY: ?f32 = null,
    canvasWidth: ?f32 = null,
    canvasHeight: ?f32 = null,
    autoCanvas: ?bool = null,
    anchorId: ?u32 = null,
    anchorSide: ?[]const u8 = null,
    anchorAlign: ?[]const u8 = null,
    anchorOffset: ?f32 = null,
};

pub const SolidOpBatch = struct {
    ops: []const SolidOp = &.{},
    seq: ?u64 = null,
};

pub const OpError = error{
    OutOfMemory,
    UnknownOp,
    MissingId,
    MissingParent,
    MissingChild,
    MissingTag,
};

// ============================================================
// Transform/Visual Field Application
// ============================================================

pub fn applyTransformFields(store: *solid.NodeStore, id: u32, op: SolidOp) OpError!void {
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

pub fn applyVisualFields(store: *solid.NodeStore, id: u32, op: SolidOp) OpError!void {
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

pub fn applyScrollFields(store: *solid.NodeStore, id: u32, op: SolidOp) OpError!void {
    const target = store.node(id) orelse return error.MissingId;
    var changed = false;
    if (op.scroll) |flag| {
        target.scroll.enabled = flag;
        changed = true;
    }
    if (op.scrollX) |value| {
        target.scroll.offset_x = value;
        changed = true;
    }
    if (op.scrollY) |value| {
        target.scroll.offset_y = value;
        changed = true;
    }
    if (op.canvasWidth) |value| {
        target.scroll.canvas_width = value;
        changed = true;
    }
    if (op.canvasHeight) |value| {
        target.scroll.canvas_height = value;
        changed = true;
    }
    if (op.autoCanvas) |flag| {
        target.scroll.auto_canvas = flag;
        changed = true;
    }
    if (changed) {
        store.markNodeChanged(id);
    }
}

fn parseAnchorSide(value: []const u8) ?solid.AnchorSide {
    if (std.mem.eql(u8, value, "top")) return .top;
    if (std.mem.eql(u8, value, "bottom")) return .bottom;
    if (std.mem.eql(u8, value, "left")) return .left;
    if (std.mem.eql(u8, value, "right")) return .right;
    return null;
}

fn parseAnchorAlign(value: []const u8) ?solid.AnchorAlign {
    if (std.mem.eql(u8, value, "start")) return .start;
    if (std.mem.eql(u8, value, "center")) return .center;
    if (std.mem.eql(u8, value, "end")) return .end;
    return null;
}

pub fn applyAnchorFields(store: *solid.NodeStore, id: u32, op: SolidOp) OpError!void {
    const target = store.node(id) orelse return error.MissingId;
    var changed = false;
    if (op.anchorId) |value| {
        target.anchor_id = value;
        changed = true;
    }
    if (op.anchorSide) |value| {
        if (parseAnchorSide(value)) |side| {
            target.anchor_side = side;
            changed = true;
        }
    }
    if (op.anchorAlign) |value| {
        if (parseAnchorAlign(value)) |alignment| {
            target.anchor_align = alignment;
            changed = true;
        }
    }
    if (op.anchorOffset) |value| {
        target.anchor_offset = value;
        changed = true;
    }
    if (changed) {
        store.markNodeChanged(id);
    }
}

// ============================================================
// Store Initialization
// ============================================================

pub fn ensureSolidStore(renderer: *Renderer, logMessage: anytype) !*solid.NodeStore {
    if (renderer.solid_store_ready) {
        if (types.solidStore(renderer)) |store| {
            return store;
        }
        renderer.solid_store_ready = false;
    }

    const store = blk: {
        if (types.solidStore(renderer)) |existing| {
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

// ============================================================
// JSON Snapshot Rebuild
// ============================================================

pub fn rebuildSolidStoreFromJson(renderer: *Renderer, json_bytes: []const u8, logMessage: anytype) void {
    // Ensure the store exists, then rebuild it from scratch based on the JSON payload.
    const store = blk: {
        if (types.solidStore(renderer)) |existing| {
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
        placeholder: ?[]const u8 = null,
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
        // Scroll fields
        scroll: ?bool = null,
        scrollX: ?f32 = null,
        scrollY: ?f32 = null,
        canvasWidth: ?f32 = null,
        canvasHeight: ?f32 = null,
        autoCanvas: ?bool = null,
        anchorId: ?u32 = null,
        anchorSide: ?[]const u8 = null,
        anchorAlign: ?[]const u8 = null,
        anchorOffset: ?f32 = null,
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
        if (node.placeholder) |value| {
            store.setPlaceholder(node.id, value) catch |err| {
                logMessage(renderer, 3, "setPlaceholder failed for {d}: {s}", .{ node.id, @errorName(err) });
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
            if (node.scroll) |flag| {
                target.scroll.enabled = flag;
                touched = true;
            }
            if (node.scrollX) |value| {
                target.scroll.offset_x = value;
                touched = true;
            }
            if (node.scrollY) |value| {
                target.scroll.offset_y = value;
                touched = true;
            }
            if (node.canvasWidth) |value| {
                target.scroll.canvas_width = value;
                touched = true;
            }
            if (node.canvasHeight) |value| {
                target.scroll.canvas_height = value;
                touched = true;
            }
            if (node.autoCanvas) |flag| {
                target.scroll.auto_canvas = flag;
                touched = true;
            }
            if (node.anchorId) |value| {
                target.anchor_id = value;
                touched = true;
            }
            if (node.anchorSide) |value| {
                if (parseAnchorSide(value)) |side| {
                    target.anchor_side = side;
                    touched = true;
                }
            }
            if (node.anchorAlign) |value| {
                if (parseAnchorAlign(value)) |alignment| {
                    target.anchor_align = alignment;
                    touched = true;
                }
            }
            if (node.anchorOffset) |value| {
                target.anchor_offset = value;
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

// ============================================================
// Single Op Application
// ============================================================

pub fn applySolidOp(store: *solid.NodeStore, op: SolidOp) OpError!void {
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
        if (op.placeholder) |value| {
            try store.setPlaceholder(op.id, value);
        }
        // Apply inline transform/visual props carried with create, so nodes are born with correct style.
        try applyTransformFields(store, op.id, op);
        try applyVisualFields(store, op.id, op);
        try applyScrollFields(store, op.id, op);
        try applyAnchorFields(store, op.id, op);
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

    if (std.mem.eql(u8, op.op, "set_scroll")) {
        if (op.id == 0) return error.MissingId;
        try applyScrollFields(store, op.id, op);
        return;
    }

    if (std.mem.eql(u8, op.op, "set_anchor")) {
        if (op.id == 0) return error.MissingId;
        try applyAnchorFields(store, op.id, op);
        return;
    }

    // Listen op - register event listener on node
    if (std.mem.eql(u8, op.op, "listen")) {
        if (op.id == 0) return error.MissingId;
        const event_type = op.eventType orelse return error.MissingTag;
        try store.addListener(op.id, event_type);
        return;
    }

    // Generic set op - route by property name
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
        if (std.mem.eql(u8, prop_name, "placeholder")) {
            const val = op.value orelse op.placeholder orelse return error.MissingTag;
            try store.setPlaceholder(op.id, val);
            return;
        }
        // Unknown property - log but don't fail
        return;
    }

    return error.UnknownOp;
}

// ============================================================
// Batch Ops Application
// ============================================================

pub fn applySolidOps(renderer: *Renderer, json_bytes: []const u8, logMessage: anytype) bool {
    const store = ensureSolidStore(renderer, logMessage) catch return false;

    var parsed = std.json.parseFromSlice(SolidOpBatch, renderer.allocator, json_bytes, .{
        .ignore_unknown_fields = true,
    }) catch |err| {
        logMessage(renderer, 3, "solid ops parse failed: {s}", .{@errorName(err)});
        renderer.solid_store_ready = false;
        return false;
    };
    defer parsed.deinit();

    const batch = parsed.value;
    const seq = batch.seq orelse renderer.solid_seq_last + 1;
    if (seq <= renderer.solid_seq_last) {
        logMessage(renderer, 2, "solid ops dropped stale batch seq={d} last={d}", .{ seq, renderer.solid_seq_last });
        return false;
    }
    var listen_ops: usize = 0;
    for (batch.ops) |op| {
        if (std.mem.eql(u8, op.op, "listen")) {
            listen_ops += 1;
        }
    }
    logMessage(renderer, 1, "solid ops seq={d} count={d} listen={d}", .{ seq, batch.ops.len, listen_ops });
    for (batch.ops) |op| {
        applySolidOp(store, op) catch |err| {
            logMessage(renderer, 3, "solid op failed: {s} op={s} id={d} parent={?d} before={?d}", .{
                @errorName(err),
                op.op,
                op.id,
                op.parent,
                op.before,
            });
            renderer.solid_store_ready = false;
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
