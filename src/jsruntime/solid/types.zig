const std = @import("std");
const tailwind = @import("tailwind.zig");

pub const NodeKind = enum {
    root,
    element,
    text,
    slot,
};

const default_input_limit: usize = 128 * 1024;

pub const InputState = struct {
    allocator: std.mem.Allocator,
    buffer: []u8 = &.{},
    text_len: usize = 0,
    limit: usize = default_input_limit,
    value_owned: []u8 = &.{},
    value_serial: u64 = 0,
    applied_serial: u64 = 0,

    fn init(allocator: std.mem.Allocator) InputState {
        return .{ .allocator = allocator };
    }

    fn deinit(self: *InputState) void {
        if (self.buffer.len > 0) self.allocator.free(self.buffer);
        if (self.value_owned.len > 0) self.allocator.free(self.value_owned);
    }

    fn ensureCapacity(self: *InputState, needed: usize) !void {
        var target = if (needed > self.limit) needed else needed;
        if (self.buffer.len >= target and self.buffer.len != 0) return;
        if (target < 32) target = 32;
        if (self.buffer.len > 0) {
            target = @max(target, self.buffer.len * 2);
            self.buffer = try self.allocator.realloc(self.buffer, target);
        } else {
            self.buffer = try self.allocator.alloc(u8, target);
        }
    }

    fn setValue(self: *InputState, value: []const u8) !void {
        const copy = try self.allocator.dupe(u8, value);
        if (self.value_owned.len > 0) self.allocator.free(self.value_owned);
        self.value_owned = copy;
        self.value_serial +%= 1;
    }

    pub fn syncBufferFromValue(self: *InputState) !void {
        if (self.value_serial == self.applied_serial) return;
        try self.ensureCapacity(self.value_owned.len + 1);
        if (self.value_owned.len > 0) {
            @memcpy(self.buffer[0..self.value_owned.len], self.value_owned);
        }
        if (self.buffer.len > self.value_owned.len) {
            self.buffer[self.value_owned.len] = 0;
        }
        self.text_len = self.value_owned.len;
        self.applied_serial = self.value_serial;
    }

    pub fn updateFromText(self: *InputState, text: []const u8) !void {
        try self.ensureCapacity(text.len + 1);
        if (self.buffer.len > text.len) {
            self.buffer[text.len] = 0;
        }
        const copy = try self.allocator.dupe(u8, text);
        if (self.value_owned.len > 0) self.allocator.free(self.value_owned);
        self.value_owned = copy;
        self.value_serial +%= 1;
        self.applied_serial = self.value_serial;
        self.text_len = text.len;
    }

    fn currentText(self: *const InputState) []const u8 {
        return self.buffer[0..self.text_len];
    }
};

const ListenerSet = struct {
    allocator: std.mem.Allocator,
    names: std.ArrayList([]u8),

    fn init(allocator: std.mem.Allocator) ListenerSet {
        return .{ .allocator = allocator, .names = .empty };
    }

    fn deinit(self: *ListenerSet) void {
        for (self.names.items) |name| {
            self.allocator.free(name);
        }
        self.names.deinit(self.allocator);
    }

    fn add(self: *ListenerSet, name: []const u8) !bool {
        for (self.names.items) |existing| {
            if (std.mem.eql(u8, existing, name)) return false;
        }
        const copy = try self.allocator.dupe(u8, name);
        errdefer self.allocator.free(copy);
        try self.names.append(self.allocator, copy);
        return true;
    }

    fn has(self: *const ListenerSet, name: []const u8) bool {
        for (self.names.items) |existing| {
            if (std.mem.eql(u8, existing, name)) return true;
        }
        return false;
    }
};

pub const SolidNode = struct {
    id: u32,
    kind: NodeKind,
    tag: []u8 = &.{},
    text: []u8 = &.{},
    class_name: []u8 = &.{},
    image_src: []u8 = &.{},
    parent: ?u32 = null,
    children: std.ArrayList(u32),
    listeners: ListenerSet,
    version: u64 = 0,
    subtree_version: u64 = 0,
    last_render_version: u64 = 0,
    interactive_self: bool = false,
    total_interactive: u32 = 0,
    class_spec: tailwind.Spec = .{},
    class_spec_dirty: bool = true,
    input_state: ?InputState = null,

    fn initCommon(allocator: std.mem.Allocator, id: u32, kind: NodeKind) SolidNode {
        return SolidNode{
            .id = id,
            .kind = kind,
            .children = .empty,
            .listeners = ListenerSet.init(allocator),
        };
    }

    pub fn initRoot(allocator: std.mem.Allocator, id: u32) SolidNode {
        return initCommon(allocator, id, .root);
    }

    pub fn initElement(allocator: std.mem.Allocator, id: u32, tag: []const u8) !SolidNode {
        var node = initCommon(allocator, id, .element);
        node.tag = try allocator.dupe(u8, tag);
        node.interactive_self = tagImpliesInteractive(tag);
        node.total_interactive = if (node.interactive_self) 1 else 0;
        return node;
    }

    pub fn initSlot(allocator: std.mem.Allocator, id: u32) SolidNode {
        return initCommon(allocator, id, .slot);
    }

    pub fn initText(allocator: std.mem.Allocator, id: u32, content: []const u8) !SolidNode {
        var node = initCommon(allocator, id, .text);
        node.text = try allocator.dupe(u8, content);
        return node;
    }

    pub fn deinit(self: *SolidNode, allocator: std.mem.Allocator) void {
        if (self.tag.len > 0) allocator.free(self.tag);
        if (self.text.len > 0) allocator.free(self.text);
        if (self.class_name.len > 0) allocator.free(self.class_name);
        if (self.image_src.len > 0) allocator.free(self.image_src);
        if (self.input_state) |*state| {
            state.deinit();
        }
        self.children.deinit(allocator);
        self.listeners.deinit();
    }

    pub fn setText(self: *SolidNode, allocator: std.mem.Allocator, content: []const u8) !void {
        const copy = try allocator.dupe(u8, content);
        if (self.text.len > 0) allocator.free(self.text);
        self.text = copy;
    }

    pub fn setTag(self: *SolidNode, allocator: std.mem.Allocator, value: []const u8) !void {
        const copy = try allocator.dupe(u8, value);
        if (self.tag.len > 0) allocator.free(self.tag);
        self.tag = copy;
    }

    pub fn addListener(self: *SolidNode, name: []const u8) !bool {
        return try self.listeners.add(name);
    }

    pub fn hasListener(self: *const SolidNode, name: []const u8) bool {
        return self.listeners.has(name);
    }

    pub fn setClassName(self: *SolidNode, allocator: std.mem.Allocator, value: []const u8) !void {
        const copy = try allocator.dupe(u8, value);
        if (self.class_name.len > 0) allocator.free(self.class_name);
        self.class_name = copy;
        self.class_spec_dirty = true;
    }

    pub fn className(self: *const SolidNode) []const u8 {
        return self.class_name;
    }

    pub fn setImageSource(self: *SolidNode, allocator: std.mem.Allocator, value: []const u8) !void {
        const copy = try allocator.dupe(u8, value);
        if (self.image_src.len > 0) allocator.free(self.image_src);
        self.image_src = copy;
    }

    pub fn ensureInputState(self: *SolidNode, allocator: std.mem.Allocator) !*InputState {
        if (self.input_state == null) {
            self.input_state = InputState.init(allocator);
            const state = &self.input_state.?;
            try state.ensureCapacity(32);
            if (state.buffer.len > 0) state.buffer[0] = 0;
        }
        return &self.input_state.?;
    }

    pub fn setInputValue(self: *SolidNode, allocator: std.mem.Allocator, value: []const u8) !void {
        var state = try self.ensureInputState(allocator);
        try state.setValue(value);
    }

    pub fn currentInputValue(self: *SolidNode) []const u8 {
        if (self.input_state) |state| {
            return state.currentText();
        }
        return &.{};
    }

    pub fn imageSource(self: *const SolidNode) []const u8 {
        return self.image_src;
    }

    pub fn hasDirtySubtree(self: *const SolidNode) bool {
        return self.last_render_version < self.subtree_version;
    }

    pub fn markRendered(self: *SolidNode) void {
        self.last_render_version = self.subtree_version;
    }

    pub fn interactiveChildCount(self: *const SolidNode) u32 {
        const self_weight: u32 = if (self.interactive_self) 1 else 0;
        if (self.total_interactive <= self_weight) return 0;
        return self.total_interactive - self_weight;
    }

    fn tagImpliesInteractive(tag: []const u8) bool {
        return std.mem.eql(u8, tag, "button") or std.mem.eql(u8, tag, "input");
    }

    pub fn prepareClassSpec(self: *SolidNode) tailwind.Spec {
        if (self.class_spec_dirty) {
            self.class_spec = tailwind.parse(self.className());
            self.class_spec_dirty = false;
        }
        return self.class_spec;
    }
};

pub const NodeStore = struct {
    allocator: std.mem.Allocator,
    nodes: std.AutoHashMap(u32, SolidNode),
    change_counter: u64 = 0,

    pub fn init(self: *NodeStore, allocator: std.mem.Allocator) !void {
        self.* = .{
            .allocator = allocator,
            .nodes = std.AutoHashMap(u32, SolidNode).init(allocator),
        };
        try self.ensureRoot(0);
    }

    pub fn deinit(self: *NodeStore) void {
        var iter = self.nodes.iterator();
        while (iter.next()) |entry| {
            entry.value_ptr.deinit(self.allocator);
        }
        self.nodes.deinit();
    }

    fn ensureRoot(self: *NodeStore, id: u32) !void {
        if (self.nodes.contains(id)) return;
        try self.nodes.put(id, SolidNode.initRoot(self.allocator, id));
        self.markNodeChanged(id);
    }

    pub fn upsertElement(self: *NodeStore, id: u32, tag: []const u8) !void {
        self.removeRecursive(id);
        const element = try SolidNode.initElement(self.allocator, id, tag);
        try self.nodes.put(id, element);
        self.markNodeChanged(id);
    }

    pub fn upsertSlot(self: *NodeStore, id: u32) !void {
        self.removeRecursive(id);
        const element = SolidNode.initSlot(self.allocator, id);
        try self.nodes.put(id, element);
        self.markNodeChanged(id);
    }

    pub fn setInputValue(self: *NodeStore, id: u32, value: []const u8) !void {
        if (self.nodes.getPtr(id)) |found_node| {
            if (!std.mem.eql(u8, found_node.tag, "input")) return;
            try found_node.setInputValue(self.allocator, value);
            self.markNodeChanged(id);
        }
    }

    pub fn setTextNode(self: *NodeStore, id: u32, content: []const u8) !void {
        if (self.nodes.getPtr(id)) |_node| {
            if (_node.kind == .text) {
                try _node.setText(self.allocator, content);
                self.markNodeChanged(id);
                return;
            }
            self.removeRecursive(id);
        }
        const new_node = try SolidNode.initText(self.allocator, id, content);
        try self.nodes.put(id, new_node);
        self.markNodeChanged(id);
    }

    pub fn insert(self: *NodeStore, parent_id: u32, child_id: u32, before_id: ?u32) !void {
        const parent = self.nodes.getPtr(parent_id) orelse return;
        const child = self.nodes.getPtr(child_id) orelse return;

        self.detachFromParent(child);
        child.parent = parent_id;
        if (child.total_interactive > 0) {
            self.propagateInteractiveDelta(parent_id, @intCast(child.total_interactive));
        }

        if (before_id) |anchor| {
            if (indexOf(parent.children.items, anchor)) |pos| {
                try parent.children.insert(self.allocator, pos, child_id);
                self.markNodeChanged(parent_id);
                return;
            }
        }
        try parent.children.append(self.allocator, child_id);
        self.markNodeChanged(parent_id);
    }

    pub fn remove(self: *NodeStore, id: u32) void {
        self.removeRecursive(id);
    }

    pub fn addListener(self: *NodeStore, id: u32, name: []const u8) !void {
        const _node = self.nodes.getPtr(id) orelse return;
        const added = try _node.addListener(name);
        if (added) {
            self.activateInteractive(id);
        }
    }

    pub fn node(self: *NodeStore, id: u32) ?*SolidNode {
        return self.nodes.getPtr(id);
    }

    pub fn setClassName(self: *NodeStore, id: u32, value: []const u8) !void {
        const target = self.nodes.getPtr(id) orelse return;
        try target.setClassName(self.allocator, value);
        self.markNodeChanged(id);
    }

    pub fn setImageSource(self: *NodeStore, id: u32, value: []const u8) !void {
        const target = self.nodes.getPtr(id) orelse return;
        try target.setImageSource(self.allocator, value);
        self.markNodeChanged(id);
    }

    fn removeRecursive(self: *NodeStore, id: u32) void {
        const entry = self.nodes.fetchRemove(id) orelse return;
        var removed_node = entry.value;

        if (removed_node.parent) |parent_id| {
            if (self.nodes.getPtr(parent_id)) |parent| {
                removeChild(parent, id);
                if (removed_node.total_interactive > 0) {
                    self.propagateInteractiveDelta(parent_id, -@as(i64, removed_node.total_interactive));
                }
                self.markNodeChanged(parent_id);
            }
        }

        while (removed_node.children.items.len > 0) {
            const child_id = removed_node.children.items[removed_node.children.items.len - 1];
            removed_node.children.items.len -= 1;
            self.removeRecursive(child_id);
        }

        removed_node.deinit(self.allocator);
    }

    fn detachFromParent(self: *NodeStore, child: *SolidNode) void {
        if (child.parent) |parent_id| {
            if (self.nodes.getPtr(parent_id)) |parent| {
                removeChild(parent, child.id);
                if (child.total_interactive > 0) {
                    self.propagateInteractiveDelta(parent_id, -@as(i64, child.total_interactive));
                }
                self.markNodeChanged(parent_id);
            }
            child.parent = null;
        }
    }

    fn markNodeChanged(self: *NodeStore, id: u32) void {
        const version = self.nextVersion();
        var current: ?u32 = id;
        var is_self = true;
        while (current) |node_id| {
            const _node = self.nodes.getPtr(node_id) orelse break;
            if (is_self) {
                _node.version = version;
                is_self = false;
            }
            if (_node.subtree_version < version) {
                _node.subtree_version = version;
            }
            current = _node.parent;
        }
    }

    fn nextVersion(self: *NodeStore) u64 {
        self.change_counter += 1;
        return self.change_counter;
    }

    fn activateInteractive(self: *NodeStore, id: u32) void {
        const _node = self.nodes.getPtr(id) orelse return;
        if (_node.interactive_self) return;
        _node.interactive_self = true;
        _node.total_interactive += 1;
        self.propagateInteractiveDelta(_node.parent, 1);
    }

    fn propagateInteractiveDelta(self: *NodeStore, start_parent: ?u32, delta_signed: i64) void {
        var current = start_parent;
        while (current) |node_id| {
            const _node = self.nodes.getPtr(node_id) orelse break;
            const base: i64 = @intCast(_node.total_interactive);
            var updated = base + delta_signed;
            if (updated < 0) {
                updated = 0;
            }
            _node.total_interactive = @intCast(updated);
            current = _node.parent;
        }
    }
};

fn removeChild(node: *SolidNode, child_id: u32) void {
    var idx: usize = 0;
    while (idx < node.children.items.len) : (idx += 1) {
        if (node.children.items[idx] == child_id) {
            _ = node.children.orderedRemove(idx);
            return;
        }
    }
}

fn indexOf(slice: []const u32, target: u32) ?usize {
    for (slice, 0..) |value, idx| {
        if (value == target) return idx;
    }
    return null;
}
