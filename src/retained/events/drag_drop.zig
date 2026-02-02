const std = @import("std");
const dvui = @import("dvui");

const events = @import("mod.zig");
const types = @import("../core/types.zig");
const hit_test = @import("../hit_test.zig");
const tailwind = @import("../style/tailwind.zig");

const DragState = struct {
    active: bool = false,
    source_id: u32 = 0,
    button: u8 = 0,
    start: dvui.Point.Physical = .{},
    last: dvui.Point.Physical = .{},
    hover_target: ?u32 = null,
};

var drag_state: DragState = .{};

const HitTestContext = struct {
    portal_ids: []const u32 = &.{},
    overlay_modal: bool = false,
    overlay_hit_rect: ?types.Rect = null,
};

var hit_ctx: HitTestContext = .{};

pub fn init() void {
    drag_state = .{};
    hit_ctx = .{};
}

pub fn deinit() void {
    drag_state = .{};
    hit_ctx = .{};
}

pub fn setHitTestContext(portal_ids: []const u32, overlay_modal: bool, overlay_hit_rect: ?types.Rect) void {
    hit_ctx.portal_ids = portal_ids;
    hit_ctx.overlay_modal = overlay_modal;
    hit_ctx.overlay_hit_rect = overlay_hit_rect;
}

pub fn cancelIfMissing(event_ring: ?*events.EventRing, store: *types.NodeStore) void {
    if (!drag_state.active) return;
    if (store.node(drag_state.source_id) != null) return;
    if (drag_state.hover_target) |target_id| {
        dispatchDragLeave(event_ring, store, target_id, drag_state.last);
    }
    drag_state = .{};
    dvui.captureMouse(null, 0);
}

pub fn handleDiv(
    event_ring: ?*events.EventRing,
    store: *types.NodeStore,
    node: *types.SolidNode,
    wd: *dvui.WidgetData,
) void {
    if (event_ring == null) return;
    const wants_pointer = node.hasListenerKind(.pointerdown) or node.hasListenerKind(.pointermove) or node.hasListenerKind(.pointerup) or node.hasListenerKind(.pointercancel);
    const wants_drag = node.hasListenerKind(.dragstart) or node.hasListenerKind(.drag) or node.hasListenerKind(.dragend);
    if (!wants_pointer and !wants_drag) return;

    const rect = wd.borderRectScale().r;
    for (dvui.events()) |*event| {
        if (!dvui.eventMatch(event, .{ .id = wd.id, .r = rect })) continue;
        switch (event.evt) {
            .mouse => |mouse| handleMouse(event_ring, store, node, wd, event, mouse, wants_pointer, wants_drag),
            else => {},
        }
    }
}

fn handleMouse(
    event_ring: ?*events.EventRing,
    store: *types.NodeStore,
    node: *types.SolidNode,
    wd: *dvui.WidgetData,
    event: *dvui.Event,
    mouse: dvui.Event.Mouse,
    wants_pointer: bool,
    wants_drag: bool,
) void {
    const is_source = drag_state.active and drag_state.source_id == node.id;
    switch (mouse.action) {
        .press => {
            if (!mouse.button.pointer()) return;
            var handled = false;
            if (wants_pointer and node.hasListenerKind(.pointerdown)) {
                pushPointerEvent(event_ring, .pointerdown, node.id, mouse);
                handled = true;
            }
            if (!drag_state.active and wants_drag) {
                startDrag(node.id, mouse, wd, event.num);
                if (node.hasListenerKind(.dragstart)) {
                    pushPointerEvent(event_ring, .dragstart, node.id, mouse);
                }
                updateHoverTarget(event_ring, store, mouse.p);
                handled = true;
            }
            if (handled) {
                event.handle(@src(), wd);
            }
        },
        .release => {
            if (!mouse.button.pointer()) return;
            var handled = false;
            if (wants_pointer and node.hasListenerKind(.pointerup)) {
                pushPointerEvent(event_ring, .pointerup, node.id, mouse);
                handled = true;
            }
            if (is_source) {
                updateHoverTarget(event_ring, store, mouse.p);
                if (drag_state.hover_target) |target_id| {
                    dispatchDrop(event_ring, store, target_id, mouse);
                }
                if (node.hasListenerKind(.dragend)) {
                    pushPointerEvent(event_ring, .dragend, node.id, mouse);
                }
                clearHover(event_ring, store, mouse.p);
                drag_state = .{};
                dvui.captureMouse(null, event.num);
                handled = true;
            }
            if (handled) {
                event.handle(@src(), wd);
            }
        },
        .motion => {
            var handled = false;
            if (is_source) {
                drag_state.last = mouse.p;
                if (node.hasListenerKind(.pointermove)) {
                    pushPointerEvent(event_ring, .pointermove, node.id, mouse);
                }
                if (node.hasListenerKind(.drag)) {
                    pushPointerEvent(event_ring, .drag, node.id, mouse);
                }
                updateHoverTarget(event_ring, store, mouse.p);
                handled = true;
            } else if (wants_pointer and node.hasListenerKind(.pointermove)) {
                pushPointerEvent(event_ring, .pointermove, node.id, mouse);
                handled = true;
            }
            if (handled) {
                event.handle(@src(), wd);
            }
        },
        else => {},
    }
}

fn startDrag(node_id: u32, mouse: dvui.Event.Mouse, wd: *dvui.WidgetData, event_num: u16) void {
    drag_state.active = true;
    drag_state.source_id = node_id;
    drag_state.start = mouse.p;
    drag_state.last = mouse.p;
    drag_state.button = mapButton(mouse.button);
    drag_state.hover_target = null;
    dvui.captureMouse(wd, event_num);
}

fn pushPointerEvent(
    event_ring: ?*events.EventRing,
    kind: events.EventKind,
    node_id: u32,
    mouse: dvui.Event.Mouse,
) void {
    if (event_ring) |ring| {
        const payload = pointerPayload(mouse);
        _ = ring.push(kind, node_id, std.mem.asBytes(&payload));
    }
}

fn pointerPayload(mouse: dvui.Event.Mouse) events.PointerPayload {
    return .{
        .x = mouse.p.x,
        .y = mouse.p.y,
        .button = mapButton(mouse.button),
        .modifiers = modMask(mouse.mod),
    };
}

fn mapButton(button: dvui.enums.Button) u8 {
    return switch (button) {
        .left => 0,
        .middle => 1,
        .right => 2,
        .four => 3,
        .five => 4,
        else => 255,
    };
}

fn modMask(mods: dvui.enums.Mod) u8 {
    var mask: u8 = 0;
    if (mods.shift()) mask |= 1;
    if (mods.control()) mask |= 2;
    if (mods.alt()) mask |= 4;
    if (mods.command()) mask |= 8;
    return mask;
}

fn updateHoverTarget(event_ring: ?*events.EventRing, store: *types.NodeStore, point: dvui.Point.Physical) void {
    const target = findDropTarget(store, point, drag_state.source_id);
    if (target == drag_state.hover_target) return;
    if (drag_state.hover_target) |prev_id| {
        dispatchDragLeave(event_ring, store, prev_id, point);
    }
    if (target) |next_id| {
        dispatchDragEnter(event_ring, store, next_id, point);
    }
    drag_state.hover_target = target;
}

fn clearHover(event_ring: ?*events.EventRing, store: *types.NodeStore, point: dvui.Point.Physical) void {
    if (drag_state.hover_target) |target_id| {
        dispatchDragLeave(event_ring, store, target_id, point);
        drag_state.hover_target = null;
    }
}

fn dispatchDragEnter(event_ring: ?*events.EventRing, store: *types.NodeStore, target_id: u32, point: dvui.Point.Physical) void {
    if (event_ring == null) return;
    const target = store.node(target_id) orelse return;
    if (!target.hasListenerKind(.dragenter)) return;
    const mouse = dvui.Event.Mouse{
        .action = .position,
        .button = .none,
        .mod = .none,
        .p = point,
        .floating_win = dvui.subwindowCurrentId(),
    };
    pushPointerEvent(event_ring, .dragenter, target_id, mouse);
}

fn dispatchDragLeave(event_ring: ?*events.EventRing, store: *types.NodeStore, target_id: u32, point: dvui.Point.Physical) void {
    if (event_ring == null) return;
    const target = store.node(target_id) orelse return;
    if (!target.hasListenerKind(.dragleave)) return;
    const mouse = dvui.Event.Mouse{
        .action = .position,
        .button = .none,
        .mod = .none,
        .p = point,
        .floating_win = dvui.subwindowCurrentId(),
    };
    pushPointerEvent(event_ring, .dragleave, target_id, mouse);
}

fn dispatchDrop(event_ring: ?*events.EventRing, store: *types.NodeStore, target_id: u32, mouse: dvui.Event.Mouse) void {
    if (event_ring == null) return;
    const target = store.node(target_id) orelse return;
    if (!target.hasListenerKind(.drop)) return;
    pushPointerEvent(event_ring, .drop, target_id, mouse);
}

fn findDropTarget(store: *types.NodeStore, point: dvui.Point.Physical, source_id: u32) ?u32 {
    const root = store.node(0) orelse return null;
    var best_id: ?u32 = null;
    var best_z: i16 = std.math.minInt(i16);
    var best_order: u32 = 0;
    var order: u32 = 0;
    const ctx = hit_test.RenderContext{ .origin = .{ .x = 0, .y = 0 }, .clip = null, .scale = .{ 1, 1 }, .offset = .{ 0, 0 } };

    var visitor = struct {
        source_id: u32,
        best_id: *?u32,
        best_z: *i16,
        best_order: *u32,

        fn wantsDrop(self: *@This(), n: *types.SolidNode) bool {
            if (n.id == self.source_id) return false;
            if (n.kind != .element) return false;
            if (!std.mem.eql(u8, n.tag, "div")) return false;
            return n.hasListenerKind(.dragenter) or n.hasListenerKind(.dragleave) or n.hasListenerKind(.drop);
        }

        pub fn count(self: *@This(), n: *types.SolidNode, spec: tailwind.Spec) bool {
            _ = spec;
            return self.wantsDrop(n);
        }

        pub fn hit(self: *@This(), n: *types.SolidNode, spec: tailwind.Spec, rect: types.Rect, ord: u32) void {
            _ = rect;
            if (!self.wantsDrop(n)) return;
            const z = spec.z_index;
            if (z > self.best_z.* or (z == self.best_z.* and ord >= self.best_order.*)) {
                self.best_z.* = z;
                self.best_order.* = ord;
                self.best_id.* = n.id;
            }
        }
    }{ .source_id = source_id, .best_id = &best_id, .best_z = &best_z, .best_order = &best_order };

    var use_overlay = false;
    if (hit_ctx.portal_ids.len > 0) {
        if (hit_ctx.overlay_modal) {
            use_overlay = true;
        } else if (hit_ctx.overlay_hit_rect) |hit_rect| {
            use_overlay = hit_test.rectContains(hit_rect, point);
        }
    }

    if (use_overlay) {
        for (hit_ctx.portal_ids) |portal_id| {
            const portal = store.node(portal_id) orelse continue;
            hit_test.scan(store, portal, point, ctx, &visitor, &order, .{ .skip_portals = false });
        }
    } else {
        hit_test.scan(store, root, point, ctx, &visitor, &order, .{ .skip_portals = true });
    }

    return best_id;
}
