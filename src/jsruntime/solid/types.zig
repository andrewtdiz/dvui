const std = @import("std");
const dvui = @import("dvui");
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

const StyleProps = struct {
    margin: ?dvui.Rect = null,
    padding: ?dvui.Rect = null,
    border: ?dvui.Rect = null,
    border_color: ?dvui.Color = null,
    background: ?dvui.Color = null,
    text: ?dvui.Color = null,
    width: ?f32 = null,
    height: ?f32 = null,
    corner_radius: ?f32 = null,

    pub fn apply(self: *const StyleProps, options: *dvui.Options) void {
        if (self.margin) |value| options.margin = value;
        if (self.padding) |value| options.padding = value;
        if (self.border) |value| options.border = value;
        if (self.border_color) |value| options.color_border = value;
        if (self.background) |value| {
            options.color_fill = value;
            options.background = true;
        }
        if (self.text) |value| options.color_text = value;
        if (self.corner_radius) |radius| options.corner_radius = dvui.Rect.all(radius);
        if (self.width) |w| applyFixedWidth(options, w);
        if (self.height) |h| applyFixedHeight(options, h);
    }

    pub fn setProperty(self: *StyleProps, name: []const u8, value: []const u8) bool {
        const trimmed_value = std.mem.trim(u8, value, " \n\r\t");
        if (matchesName(name, "margin")) {
            return self.setSpacing(&self.margin, trimmed_value);
        }
        if (matchesName(name, "padding")) {
            return self.setSpacing(&self.padding, trimmed_value);
        }
        if (matchesName(name, "border") or matchesName(name, "border-width")) {
            return self.setSpacing(&self.border, trimmed_value);
        }
        if (matchesName(name, "margin-top")) {
            return self.setSpacingSide(&self.margin, .top, trimmed_value);
        }
        if (matchesName(name, "margin-right")) {
            return self.setSpacingSide(&self.margin, .right, trimmed_value);
        }
        if (matchesName(name, "margin-bottom")) {
            return self.setSpacingSide(&self.margin, .bottom, trimmed_value);
        }
        if (matchesName(name, "margin-left")) {
            return self.setSpacingSide(&self.margin, .left, trimmed_value);
        }
        if (matchesName(name, "padding-top")) {
            return self.setSpacingSide(&self.padding, .top, trimmed_value);
        }
        if (matchesName(name, "padding-right")) {
            return self.setSpacingSide(&self.padding, .right, trimmed_value);
        }
        if (matchesName(name, "padding-bottom")) {
            return self.setSpacingSide(&self.padding, .bottom, trimmed_value);
        }
        if (matchesName(name, "padding-left")) {
            return self.setSpacingSide(&self.padding, .left, trimmed_value);
        }
        if (matchesName(name, "color")) {
            return self.setColor(&self.text, trimmed_value);
        }
        if (matchesName(name, "background") or matchesName(name, "background-color")) {
            return self.setColor(&self.background, trimmed_value);
        }
        if (matchesName(name, "border-color")) {
            return self.setColor(&self.border_color, trimmed_value);
        }
        if (matchesName(name, "width")) {
            return self.setLength(&self.width, trimmed_value);
        }
        if (matchesName(name, "height")) {
            return self.setLength(&self.height, trimmed_value);
        }
        if (matchesName(name, "border-radius")) {
            return self.setLength(&self.corner_radius, trimmed_value);
        }
        return false;
    }

    const Side = enum { left, right, top, bottom };

    fn setSpacing(self: *StyleProps, target: *?dvui.Rect, value: []const u8) bool {
        const parsed = parseSpacingRect(value) orelse return false;
        if (rectEqual(target.*, parsed)) return false;
        target.* = parsed;
        return true;
    }

    fn setSpacingSide(self: *StyleProps, target: *?dvui.Rect, side: Side, value: []const u8) bool {
        _ = self;
        const parsed = parseLength(value) orelse return false;
        var rect = target.* orelse dvui.Rect{};
        switch (side) {
            .left => rect.x = parsed,
            .top => rect.y = parsed,
            .right => rect.w = parsed,
            .bottom => rect.h = parsed,
        }
        if (rectEqual(target.*, rect)) return false;
        target.* = rect;
        return true;
    }

    fn setColor(self: *StyleProps, target: *?dvui.Color, value: []const u8) bool {
        _ = self;
        const parsed = parseColor(value) orelse return false;
        if (target.*) |existing| {
            if (colorsEqual(existing, parsed)) return false;
        }
        target.* = parsed;
        return true;
    }

    fn setLength(self: *StyleProps, target: *?f32, value: []const u8) bool {
        _ = self;
        const parsed = parseLength(value) orelse return false;
        if (target.*) |existing| {
            if (existing == parsed) return false;
        }
        target.* = parsed;
        return true;
    }

    fn matchesName(input: []const u8, expected: []const u8) bool {
        if (std.mem.eql(u8, input, expected)) return true;
        if (std.ascii.eqlIgnoreCase(input, expected)) return true;
        var camel_buf: [64]u8 = undefined;
        if (camelFor(expected, &camel_buf)) |camel| {
            if (std.ascii.eqlIgnoreCase(input, camel)) return true;
        }
        return false;
    }

    fn camelFor(expected: []const u8, buffer: *[64]u8) ?[]const u8 {
        var idx: usize = 0;
        while (idx < expected.len) : (idx += 1) {
            if (expected[idx] == '-') break;
        }
        if (idx == expected.len or idx + 1 >= expected.len) return null;
        if (expected.len - 1 > buffer.len) return null;
        const next = expected[idx + 1];
        const prefix = expected[0..idx];
        @memcpy(buffer[0..prefix.len], prefix);
        buffer[prefix.len] = std.ascii.toUpper(next);
        const tail = expected[(idx + 2)..];
        @memcpy(buffer[(prefix.len + 1)..(prefix.len + 1 + tail.len)], tail);
        return buffer[0 .. prefix.len + 1 + tail.len];
    }

    fn parseSpacingRect(value: []const u8) ?dvui.Rect {
        var parts: [4]f32 = undefined;
        var count: usize = 0;
        var iter = std.mem.tokenizeAny(u8, value, " \n\r\t");
        while (iter.next()) |token| {
            if (count >= parts.len) break;
            parts[count] = parseLength(token) orelse return null;
            count += 1;
        }
        if (count == 0) return null;

        var rect = dvui.Rect{};
        switch (count) {
            1 => {
                rect.x = parts[0];
                rect.y = parts[0];
                rect.w = parts[0];
                rect.h = parts[0];
            },
            2 => {
                rect.y = parts[0];
                rect.h = parts[0];
                rect.x = parts[1];
                rect.w = parts[1];
            },
            3 => {
                rect.y = parts[0];
                rect.x = parts[1];
                rect.w = parts[1];
                rect.h = parts[2];
            },
            else => {
                rect.y = parts[0];
                rect.w = parts[1];
                rect.h = parts[2];
                rect.x = parts[3];
            },
        }
        return rect;
    }

    fn parseLength(raw: []const u8) ?f32 {
        const trimmed = std.mem.trim(u8, raw, " \n\r\t");
        if (trimmed.len == 0) return null;
        if (std.mem.endsWith(u8, trimmed, "px")) {
            return std.fmt.parseFloat(f32, trimmed[0 .. trimmed.len - 2]) catch return null;
        }
        return std.fmt.parseFloat(f32, trimmed) catch null;
    }

    fn parseColor(raw: []const u8) ?dvui.Color {
        const trimmed = std.mem.trim(u8, raw, " \n\r\t");
        if (trimmed.len == 0) return null;
        if (trimmed.len >= 1 and trimmed[0] == '#') {
            return parseHexColor(trimmed[1..]);
        }
        return tailwind.lookupColor(trimmed);
    }

    fn parseHexColor(value: []const u8) ?dvui.Color {
        if (value.len == 3 or value.len == 4) {
            var channels: [4]u8 = .{0, 0, 0, 0xff};
            var idx: usize = 0;
            while (idx < value.len) : (idx += 1) {
                const nibble = parseHex(value[idx]) orelse return null;
                channels[idx] = (nibble << 4) | nibble;
            }
            return dvui.Color{ .r = channels[0], .g = channels[1], .b = channels[2], .a = channels[3] };
        }
        if (value.len == 6 or value.len == 8) {
            var channels: [4]u8 = .{0, 0, 0, 0xff};
            var idx: usize = 0;
            while (idx + 1 < value.len and idx / 2 < channels.len) : (idx += 2) {
                const hi = parseHex(value[idx]) orelse return null;
                const lo = parseHex(value[idx + 1]) orelse return null;
                channels[idx / 2] = (hi << 4) | lo;
            }
            return dvui.Color{ .r = channels[0], .g = channels[1], .b = channels[2], .a = channels[3] };
        }
        return null;
    }

    fn parseHex(char: u8) ?u8 {
        return switch (char) {
            '0'...'9' => char - '0',
            'a'...'f' => char - 'a' + 10,
            'A'...'F' => char - 'A' + 10,
            else => null,
        };
    }

    fn colorsEqual(a: dvui.Color, b: dvui.Color) bool {
        return a.r == b.r and a.g == b.g and a.b == b.b and a.a == b.a;
    }

    fn rectEqual(current: ?dvui.Rect, next: dvui.Rect) bool {
        if (current) |rect| {
            return rect.x == next.x and rect.y == next.y and rect.w == next.w and rect.h == next.h;
        }
        return false;
    }

    fn applyFixedWidth(options: *dvui.Options, width: f32) void {
        var min_size = options.min_size_content orelse dvui.Size{};
        min_size.w = width;
        options.min_size_content = min_size;

        var max_size = options.max_size_content orelse dvui.Options.MaxSize{ .w = dvui.max_float_safe, .h = dvui.max_float_safe };
        max_size.w = width;
        options.max_size_content = max_size;
    }

    fn applyFixedHeight(options: *dvui.Options, height: f32) void {
        var min_size = options.min_size_content orelse dvui.Size{};
        min_size.h = height;
        options.min_size_content = min_size;

        var max_size = options.max_size_content orelse dvui.Options.MaxSize{ .w = dvui.max_float_safe, .h = dvui.max_float_safe };
        max_size.h = height;
        options.max_size_content = max_size;
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
    style: StyleProps = .{},

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

    pub fn applyStyle(self: *const SolidNode, options: *dvui.Options) void {
        self.style.apply(options);
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

    pub fn setStyle(self: *SolidNode, name: []const u8, value: []const u8) bool {
        return self.style.setProperty(name, value);
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

    pub fn setStyle(self: *NodeStore, id: u32, name: []const u8, value: []const u8) void {
        const target = self.nodes.getPtr(id) orelse return;
        const changed = target.setStyle(name, value);
        if (changed) {
            self.markNodeChanged(id);
        }
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
