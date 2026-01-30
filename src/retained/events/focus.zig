const std = @import("std");
const dvui = @import("dvui");
const types = @import("../core/types.zig");
const events = @import("mod.zig");

pub const TabIndexInfo = struct {
    focusable: bool,
    tab_index: ?u16 = null,
};

const FocusEntry = struct {
    node_id: u32,
    widget_id: dvui.Id,
    widget_data: *const dvui.WidgetData,
    border_rect: dvui.Rect.Physical,
    tab_index: i32,
    roving_group: ?u32,
    trap_id: ?u32,
};

const FocusState = struct {
    allocator: std.mem.Allocator = undefined,
    entries: std.ArrayList(FocusEntry) = .empty,
    roving_active: std.AutoHashMap(u32, u32) = undefined,
    focused_node: ?u32 = null,

    fn init(self: *FocusState, allocator: std.mem.Allocator) void {
        self.* = .{
            .allocator = allocator,
            .entries = .empty,
            .roving_active = std.AutoHashMap(u32, u32).init(allocator),
            .focused_node = null,
        };
    }

    fn deinit(self: *FocusState) void {
        self.entries.deinit(self.allocator);
        self.roving_active.deinit();
        self.* = .{};
    }
};

const Move = enum {
    next,
    prev,
    first,
    last,
};

var focus_state: FocusState = .{};
var focus_state_initialized: bool = false;

pub fn init() void {
    if (focus_state_initialized) {
        focus_state.deinit();
        focus_state_initialized = false;
    }
}

pub fn deinit() void {
    if (focus_state_initialized) {
        focus_state.deinit();
        focus_state_initialized = false;
    }
}

fn ensureState(allocator: std.mem.Allocator) *FocusState {
    if (!focus_state_initialized) {
        focus_state.init(allocator);
        focus_state_initialized = true;
    }
    return &focus_state;
}

pub fn beginFrame(store: *types.NodeStore) void {
    const state = ensureState(store.allocator);
    state.entries.clearRetainingCapacity();
}

pub fn tabIndexForNode(store: *types.NodeStore, node: *types.SolidNode) TabIndexInfo {
    const raw_tab_index = effectiveTabIndex(node) orelse return .{ .focusable = false, .tab_index = null };
    const state = ensureState(store.allocator);

    const roving_group = findRovingGroup(store, node.id);
    if (roving_group) |group_id| {
        const active_id = ensureRovingActive(state, store, group_id, node.id);
        if (active_id != node.id) {
            return .{ .focusable = true, .tab_index = 0 };
        }
    }

    if (raw_tab_index < 0) {
        return .{ .focusable = true, .tab_index = 0 };
    }
    if (raw_tab_index == 0) {
        return .{ .focusable = true, .tab_index = null };
    }
    const max_tab: i32 = @intCast(std.math.maxInt(u16));
    const clamped: i32 = @min(raw_tab_index, max_tab);
    return .{ .focusable = true, .tab_index = @intCast(clamped) };
}

pub fn registerFocusable(store: *types.NodeStore, node: *types.SolidNode, wd: *dvui.WidgetData) void {
    const tab_index = effectiveTabIndex(node) orelse return;
    const state = ensureState(store.allocator);

    const roving_group = findRovingGroup(store, node.id);
    if (roving_group) |group_id| {
        _ = ensureRovingActive(state, store, group_id, node.id);
    }

    const stored_wd = dvui.widgetAlloc(dvui.WidgetData);
    stored_wd.* = wd.*;
    const entry = FocusEntry{
        .node_id = node.id,
        .widget_id = wd.id,
        .widget_data = stored_wd,
        .border_rect = wd.borderRectScale().r,
        .tab_index = tab_index,
        .roving_group = roving_group,
        .trap_id = findFocusTrap(store, node.id),
    };
    state.entries.append(state.allocator, entry) catch {};
}

pub fn endFrame(event_ring: ?*events.EventRing, store: *types.NodeStore, input_enabled: bool) void {
    const state = ensureState(store.allocator);
    if (input_enabled) {
        handleKeyEvents(event_ring, store, state);
    }
    updateFocusState(event_ring, store, state);
}

fn effectiveTabIndex(node: *const types.SolidNode) ?i32 {
    if (node.tab_index) |value| {
        return value;
    }
    if (node.isInteractive()) {
        return 0;
    }
    return null;
}

fn findRovingGroup(store: *types.NodeStore, start_id: u32) ?u32 {
    var current_id: ?u32 = start_id;
    while (current_id) |node_id| {
        const node = store.node(node_id) orelse return null;
        if (node.roving) return node_id;
        current_id = node.parent;
    }
    return null;
}

fn findFocusTrap(store: *types.NodeStore, start_id: u32) ?u32 {
    var current_id: ?u32 = start_id;
    while (current_id) |node_id| {
        const node = store.node(node_id) orelse return null;
        if (node.focus_trap) return node_id;
        current_id = node.parent;
    }
    return null;
}

fn activeInGroup(store: *types.NodeStore, group_id: u32, active_id: u32) bool {
    var current_id: ?u32 = active_id;
    while (current_id) |node_id| {
        const node = store.node(node_id) orelse return false;
        if (node.roving) return node_id == group_id;
        current_id = node.parent;
    }
    return false;
}

fn ensureRovingActive(state: *FocusState, store: *types.NodeStore, group_id: u32, fallback_id: u32) u32 {
    if (state.roving_active.get(group_id)) |active_id| {
        if (activeInGroup(store, group_id, active_id)) return active_id;
    }
    state.roving_active.put(group_id, fallback_id) catch {};
    return fallback_id;
}

fn updateFocusState(event_ring: ?*events.EventRing, store: *types.NodeStore, state: *FocusState) void {
    const focused_widget = dvui.focusedWidgetId();
    const focused_entry = if (focused_widget) |widget_id|
        entryForWidget(state, widget_id)
    else
        null;
    const new_focused_node = if (focused_entry) |entry| entry.node_id else null;

    if (state.focused_node != new_focused_node) {
        if (state.focused_node) |prev_id| {
            if (store.node(prev_id)) |prev_node| {
                dispatchFocusEvent(event_ring, prev_node, false);
            }
        }
        if (new_focused_node) |next_id| {
            if (store.node(next_id)) |next_node| {
                dispatchFocusEvent(event_ring, next_node, true);
            }
        }
        state.focused_node = new_focused_node;
    }

    if (focused_entry) |entry| {
        if (entry.roving_group) |group_id| {
            state.roving_active.put(group_id, entry.node_id) catch {};
        }
    }
}

fn dispatchFocusEvent(event_ring: ?*events.EventRing, node: *types.SolidNode, focused: bool) void {
    if (event_ring == null) return;
    if (std.mem.eql(u8, node.tag, "input")) return;
    if (focused) {
        if (node.hasListener("focus")) {
            _ = event_ring.?.pushFocus(node.id);
        }
    } else {
        if (node.hasListener("blur")) {
            _ = event_ring.?.pushBlur(node.id);
        }
    }
}

fn handleKeyEvents(event_ring: ?*events.EventRing, store: *types.NodeStore, state: *FocusState) void {
    if (state.entries.items.len == 0) return;

    for (dvui.events()) |*event| {
        if (event.evt != .key) continue;
        if (event.handled) continue;

        const focused_widget = dvui.focusedWidgetId() orelse continue;
        const entry = entryForWidget(state, focused_widget) orelse continue;

        if (!dvui.eventMatch(event, .{ .id = entry.widget_id, .r = entry.border_rect })) {
            continue;
        }

        const key_event = event.evt.key;
        const is_down = key_event.action == .down or key_event.action == .repeat;

        if (key_event.code == .tab) {
            if (entry.trap_id) |trap_id| {
                if (is_down) {
                    const forward = !key_event.mod.shift();
                    if (moveFocusInTrap(state, trap_id, entry.node_id, forward)) |target| {
                        event.handle(@src(), entry.widget_data);
                        dvui.focusWidget(target.widget_id, null, event.num);
                    } else {
                        event.handle(@src(), entry.widget_data);
                    }
                } else if (key_event.action == .up) {
                    event.handle(@src(), entry.widget_data);
                }
                continue;
            }
            continue;
        }

        if (entry.roving_group) |group_id| {
            if (is_down) {
                if (rovingMoveForKey(key_event.code)) |move| {
                    if (moveFocusInRovingGroup(state, group_id, entry.node_id, move)) |target| {
                        event.handle(@src(), entry.widget_data);
                        dvui.focusWidget(target.widget_id, null, event.num);
                    } else {
                        event.handle(@src(), entry.widget_data);
                    }
                    continue;
                }
            } else if (key_event.action == .up and rovingMoveForKey(key_event.code) != null) {
                event.handle(@src(), entry.widget_data);
                continue;
            }
        }

        if (event_ring == null) continue;
        if (key_event.action == .down or key_event.action == .repeat) {
            if (store.node(entry.node_id)) |node| {
                if (node.hasListener("keydown")) {
                    const payload = @tagName(key_event.code);
                    _ = event_ring.?.push(.keydown, entry.node_id, payload);
                    event.handle(@src(), entry.widget_data);
                }
            }
        } else if (key_event.action == .up) {
            if (store.node(entry.node_id)) |node| {
                if (node.hasListener("keyup")) {
                    const payload = @tagName(key_event.code);
                    _ = event_ring.?.push(.keyup, entry.node_id, payload);
                    event.handle(@src(), entry.widget_data);
                }
            }
        }
    }
}

fn rovingMoveForKey(code: dvui.enums.Key) ?Move {
    return switch (code) {
        .left, .up => .prev,
        .right, .down => .next,
        .home => .first,
        .end => .last,
        else => null,
    };
}

fn moveFocusInRovingGroup(state: *FocusState, group_id: u32, current_id: u32, move: Move) ?*FocusEntry {
    var first: ?*FocusEntry = null;
    var last: ?*FocusEntry = null;
    var prev: ?*FocusEntry = null;
    var next: ?*FocusEntry = null;
    var seen_current = false;

    for (state.entries.items) |*entry| {
        if (entry.roving_group == null or entry.roving_group.? != group_id) continue;
        if (first == null) first = entry;
        last = entry;
        if (entry.node_id == current_id) {
            seen_current = true;
            continue;
        }
        if (!seen_current) {
            prev = entry;
        } else if (next == null) {
            next = entry;
        }
    }

    return switch (move) {
        .first => first,
        .last => last,
        .next => next orelse first,
        .prev => prev orelse last,
    };
}

fn moveFocusInTrap(state: *FocusState, trap_id: u32, current_id: u32, forward: bool) ?*FocusEntry {
    const move: Move = if (forward) .next else .prev;
    var first: ?*FocusEntry = null;
    var last: ?*FocusEntry = null;
    var prev: ?*FocusEntry = null;
    var next: ?*FocusEntry = null;
    var seen_current = false;

    for (state.entries.items) |*entry| {
        if (entry.trap_id == null or entry.trap_id.? != trap_id) continue;
        if (!isTabbable(state, entry)) continue;
        if (first == null) first = entry;
        last = entry;
        if (entry.node_id == current_id) {
            seen_current = true;
            continue;
        }
        if (!seen_current) {
            prev = entry;
        } else if (next == null) {
            next = entry;
        }
    }

    return switch (move) {
        .first => first,
        .last => last,
        .next => next orelse first,
        .prev => prev orelse last,
    };
}

fn isTabbable(state: *FocusState, entry: *const FocusEntry) bool {
    if (entry.tab_index < 0) return false;
    if (entry.roving_group) |group_id| {
        if (state.roving_active.get(group_id)) |active_id| {
            return active_id == entry.node_id;
        }
        return false;
    }
    return true;
}

fn entryForWidget(state: *FocusState, widget_id: dvui.Id) ?*FocusEntry {
    for (state.entries.items) |*entry| {
        if (entry.widget_id == widget_id) return entry;
    }
    return null;
}
