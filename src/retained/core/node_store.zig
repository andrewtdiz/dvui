const std = @import("std");

const dvui = @import("dvui");
const tailwind = @import("../style/tailwind.zig");
const geometry = @import("geometry.zig");
const visual = @import("visual.zig");
const layout = @import("layout.zig");
const media = @import("media.zig");
const events = @import("../events/mod.zig");

const Rect = geometry.Rect;
const SideOffsets = geometry.SideOffsets;
const Transform = geometry.Transform;

const PackedColor = visual.PackedColor;
const VisualProps = visual.VisualProps;

const LayoutCache = layout.LayoutCache;
const PaintCache = layout.PaintCache;

const IconKind = media.IconKind;
const CachedImage = media.CachedImage;
const CachedIcon = media.CachedIcon;

const AnchorSide = dvui.AnchorSide;
const AnchorAlign = dvui.AnchorAlign;

comptime {
    var max_value: u32 = 0;
    for (@typeInfo(events.EventKind).@"enum".fields) |field| {
        if (field.value > max_value) max_value = field.value;
    }
    if (max_value >= 64) @compileError("EventKind exceeds listener_mask capacity");
}

pub const AccessToggled = enum {
    ak_false,
    ak_true,
    mixed,
};

pub const AccessHasPopup = enum {
    menu,
    listbox,
    tree,
    grid,
    dialog,
};

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
    caret: usize = 0,
    limit: usize = default_input_limit,
    value_owned: []u8 = &.{},
    value_serial: u64 = 0,
    applied_serial: u64 = 0,
    focused: bool = false,

    fn init(allocator: std.mem.Allocator) InputState {
        return .{ .allocator = allocator };
    }

    fn deinit(self: *InputState) void {
        if (self.buffer.len > 0) self.allocator.free(self.buffer);
        if (self.value_owned.len > 0) self.allocator.free(self.value_owned);
    }

    pub fn ensureCapacity(self: *InputState, needed: usize) !void {
        const max_needed = if (self.limit == std.math.maxInt(usize)) self.limit else self.limit + 1;
        if (needed > max_needed) return error.InputLimitExceeded;
        if (self.buffer.len >= needed and self.buffer.len != 0) return;
        var target = needed;
        if (target < 32) target = 32;
        if (self.buffer.len > 0) {
            target = @max(target, self.buffer.len * 2);
        }
        if (target > max_needed) target = max_needed;
        if (self.buffer.len > 0) {
            self.buffer = try self.allocator.realloc(self.buffer, target);
        } else {
            self.buffer = try self.allocator.alloc(u8, target);
        }
    }

    fn setValue(self: *InputState, value: []const u8) !void {
        if (value.len > self.limit) return error.InputLimitExceeded;
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
        self.caret = self.text_len;
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
        self.caret = @min(self.caret, self.text_len);
    }

    pub fn currentText(self: *const InputState) []const u8 {
        return self.buffer[0..self.text_len];
    }
};

pub const ScrollState = struct {
    enabled: bool = false,
    class_enabled: bool = false,
    class_x: bool = false,
    class_y: bool = false,
    offset_x: f32 = 0,
    offset_y: f32 = 0,
    canvas_width: f32 = 0,
    canvas_height: f32 = 0,
    auto_canvas: bool = false,
    content_width: f32 = 0,
    content_height: f32 = 0,
    scrollbar_thickness: f32 = 10,

    pub fn isEnabled(self: *const ScrollState) bool {
        return self.enabled or self.class_enabled;
    }

    pub fn allowX(self: *const ScrollState) bool {
        if (self.class_enabled) return self.class_x;
        return true;
    }

    pub fn allowY(self: *const ScrollState) bool {
        if (self.class_enabled) return self.class_y;
        return true;
    }

    pub fn isAutoCanvas(self: *const ScrollState) bool {
        return self.auto_canvas or self.class_enabled;
    }
};

pub const TransitionState = struct {
    enabled: bool = false,
    active_props: tailwind.TransitionProps = .{},
    prev_initialized: bool = false,

    prev_layout_rect: ?Rect = null,
    prev_margin: SideOffsets = .{},
    prev_padding: SideOffsets = .{},
    prev_translation: [2]f32 = .{ 0, 0 },
    prev_scale: [2]f32 = .{ 1, 1 },
    prev_rotation: f32 = 0,
    prev_opacity: f32 = 1,
    prev_image_opacity: f32 = 1,
    prev_bg: ?PackedColor = null,
    prev_text: ?PackedColor = null,
    prev_tint: ?PackedColor = null,
    prev_border: PackedColor = .{ .value = 0 },

    bg_from: ?PackedColor = null,
    bg_to: ?PackedColor = null,
    text_from: ?PackedColor = null,
    text_to: ?PackedColor = null,
    tint_from: ?PackedColor = null,
    tint_to: ?PackedColor = null,
    border_from: ?PackedColor = null,
    border_to: ?PackedColor = null,

    flip_translation: [2]f32 = .{ 0, 0 },
    flip_scale: [2]f32 = .{ 1, 1 },

    anim_translation: ?[2]f32 = null,
    anim_scale: ?[2]f32 = null,
    anim_rotation: ?f32 = null,
    anim_opacity: ?f32 = null,
    anim_image_opacity: ?f32 = null,
    anim_bg: ?PackedColor = null,
    anim_text: ?PackedColor = null,
    anim_tint: ?PackedColor = null,
    anim_border: ?PackedColor = null,
};

pub const SolidNode = struct {
    id: u32,
    kind: NodeKind,
    tag: []u8 = &.{},
    text: []u8 = &.{},
    class_name: []u8 = &.{},
    image_src: []u8 = &.{},
    image_tint: ?PackedColor = null,
    image_opacity: f32 = 1.0,
    image_src_set_by_image_prop: bool = false,
    icon_kind: IconKind = .auto,
    icon_glyph: []u8 = &.{},
    resolved_image_path: []u8 = &.{},
    resolved_icon_path: []u8 = &.{},
    cached_image: CachedImage = .none,
    cached_icon: CachedIcon = .none,
    parent: ?u32 = null,
    children: std.ArrayList(u32),
    listener_mask: u64 = 0,
    version: u64 = 0,
    subtree_version: u64 = 0,
    layout_subtree_version: u64 = 0,
    last_render_version: u64 = 0,
    layout: LayoutCache = .{},
    paint: PaintCache = .{},
    transform: Transform = .{},
    visual: VisualProps = .{},
    visual_props: VisualProps = .{},
    transition_state: TransitionState = .{},
    scroll: ScrollState = .{},
    hovered: bool = false,
    interactive_self: bool = false,
    total_interactive: u32 = 0,
    tab_index: ?i32 = null,
    focus_trap: bool = false,
    roving: bool = false,
    modal: bool = false,
    anchor_id: ?u32 = null,
    anchor_side: AnchorSide = .bottom,
    anchor_align: AnchorAlign = .start,
    anchor_offset: f32 = 0,
    access_role: ?dvui.AccessKit.Role = null,
    access_label: []u8 = &.{},
    access_description: []u8 = &.{},
    access_expanded: ?bool = null,
    access_selected: ?bool = null,
    access_toggled: ?AccessToggled = null,
    access_hidden: ?bool = null,
    access_disabled: ?bool = null,
    access_has_popup: ?AccessHasPopup = null,
    access_modal: ?bool = null,
    class_spec: tailwind.Spec = .{},
    class_spec_dirty: bool = true,
    font_render_mode_override: ?tailwind.FontRenderMode = null,
    input_state: ?InputState = null,

    fn initCommon(allocator: std.mem.Allocator, id: u32, kind: NodeKind) SolidNode {
        _ = allocator;
        return SolidNode{
            .id = id,
            .kind = kind,
            .children = .empty,
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
        node.scroll.enabled = tagImpliesScroll(tag);
        if (node.scroll.enabled) {
            node.scroll.auto_canvas = true;
        }
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
        if (self.access_label.len > 0) allocator.free(self.access_label);
        if (self.access_description.len > 0) allocator.free(self.access_description);
        if (self.image_src.len > 0) allocator.free(self.image_src);
        if (self.icon_glyph.len > 0) allocator.free(self.icon_glyph);
        if (self.resolved_image_path.len > 0) allocator.free(self.resolved_image_path);
        if (self.resolved_icon_path.len > 0) allocator.free(self.resolved_icon_path);
        if (self.input_state) |*state| {
            state.deinit();
        }
        self.layout.text_layout.deinit(allocator);
        self.paint.deinit(allocator);
        self.children.deinit(allocator);
    }

    pub fn setText(self: *SolidNode, allocator: std.mem.Allocator, content: []const u8) !void {
        const copy = try allocator.dupe(u8, content);
        if (self.text.len > 0) allocator.free(self.text);
        self.text = copy;
        self.invalidatePaint();
    }

    pub fn setTag(self: *SolidNode, allocator: std.mem.Allocator, value: []const u8) !void {
        const copy = try allocator.dupe(u8, value);
        if (self.tag.len > 0) allocator.free(self.tag);
        self.tag = copy;
    }

    pub fn addListenerKind(self: *SolidNode, kind: events.EventKind) bool {
        const bit = listenerBit(kind);
        if ((self.listener_mask & bit) != 0) return false;
        self.listener_mask |= bit;
        return true;
    }

    pub fn hasListenerKind(self: *const SolidNode, kind: events.EventKind) bool {
        return (self.listener_mask & listenerBit(kind)) != 0;
    }

    fn listenerBit(kind: events.EventKind) u64 {
        const shift: u6 = @intCast(@intFromEnum(kind));
        return (@as(u64, 1) << shift);
    }

    pub fn setClassName(self: *SolidNode, allocator: std.mem.Allocator, value: []const u8) !void {
        if (std.mem.eql(u8, self.class_name, value)) return;
        const copy = try allocator.dupe(u8, value);
        if (self.class_name.len > 0) allocator.free(self.class_name);
        self.class_name = copy;
        self.class_spec_dirty = true;
        self.invalidatePaint();
    }

    pub fn setFontRenderMode(self: *SolidNode, mode: ?tailwind.FontRenderMode) void {
        if (self.font_render_mode_override == mode) return;
        self.font_render_mode_override = mode;
        self.class_spec_dirty = true;
        self.invalidatePaint();
    }

    pub fn className(self: *const SolidNode) []const u8 {
        return self.class_name;
    }

    pub fn setAccessLabel(self: *SolidNode, allocator: std.mem.Allocator, value: []const u8) !void {
        if (self.access_label.len > 0) allocator.free(self.access_label);
        if (value.len == 0) {
            self.access_label = &.{};
            return;
        }
        self.access_label = try allocator.dupe(u8, value);
    }

    pub fn setAccessDescription(self: *SolidNode, allocator: std.mem.Allocator, value: []const u8) !void {
        if (self.access_description.len > 0) allocator.free(self.access_description);
        if (value.len == 0) {
            self.access_description = &.{};
            return;
        }
        self.access_description = try allocator.dupe(u8, value);
    }

    pub fn setImageSource(self: *SolidNode, allocator: std.mem.Allocator, value: []const u8) !void {
        if (std.mem.eql(u8, self.image_src, value)) return;
        const copy = try allocator.dupe(u8, value);
        if (self.image_src.len > 0) allocator.free(self.image_src);
        self.image_src = copy;
        self.clearImageCache(allocator);
        self.clearIconCache(allocator);
    }

    pub fn setImageTint(self: *SolidNode, value: u32) void {
        if (self.image_tint) |current| {
            if (current.value == value) return;
        }
        self.image_tint = .{ .value = value };
        self.invalidatePaint();
    }

    pub fn setImageOpacity(self: *SolidNode, value: f32) void {
        const clamped: f32 = if (value < 0.0) 0.0 else if (value > 1.0) 1.0 else value;
        if (self.image_opacity == clamped) return;
        self.image_opacity = clamped;
        self.invalidatePaint();
    }

    fn clearImageCache(self: *SolidNode, allocator: std.mem.Allocator) void {
        if (self.resolved_image_path.len > 0) allocator.free(self.resolved_image_path);
        self.resolved_image_path = &.{};
        self.cached_image = .none;
    }

    fn clearIconCache(self: *SolidNode, allocator: std.mem.Allocator) void {
        if (self.resolved_icon_path.len > 0) allocator.free(self.resolved_icon_path);
        self.resolved_icon_path = &.{};
        self.cached_icon = .none;
    }

    pub fn setIconGlyph(self: *SolidNode, allocator: std.mem.Allocator, value: []const u8) !void {
        if (std.mem.eql(u8, self.icon_glyph, value)) return;
        const copy = try allocator.dupe(u8, value);
        if (self.icon_glyph.len > 0) allocator.free(self.icon_glyph);
        self.icon_glyph = copy;
        self.clearIconCache(allocator);
        self.invalidatePaint();
    }

    pub fn iconGlyph(self: *const SolidNode) []const u8 {
        return self.icon_glyph;
    }

    pub fn iconKind(self: *const SolidNode) IconKind {
        return self.icon_kind;
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
        try state.syncBufferFromValue();
        self.invalidatePaint();
    }

    pub fn currentInputValue(self: *const SolidNode) []const u8 {
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

    pub fn needsPaintUpdate(self: *const SolidNode) bool {
        if (self.paint.paint_dirty) return true;
        if (self.paint.version < self.version) return true;
        if (self.layout.version > self.paint.version) return true;
        return false;
    }

    pub fn invalidatePaint(self: *SolidNode) void {
        self.paint.paint_dirty = true;
    }

    pub fn interactiveChildCount(self: *const SolidNode) u32 {
        const self_weight: u32 = if (self.interactive_self) 1 else 0;
        if (self.total_interactive <= self_weight) return 0;
        return self.total_interactive - self_weight;
    }

    fn tagImpliesInteractive(tag: []const u8) bool {
        return std.mem.eql(u8, tag, "button") or std.mem.eql(u8, tag, "input") or std.mem.eql(u8, tag, "slider");
    }

    fn tagImpliesScroll(tag: []const u8) bool {
        return std.mem.eql(u8, tag, "scrollframe") or std.mem.eql(u8, tag, "scroll");
    }

    pub fn prepareClassSpec(self: *SolidNode) tailwind.Spec {
        if (self.class_spec_dirty) {
            self.class_spec = tailwind.parse(self.className());
            self.class_spec_dirty = false;
        }
        if (self.font_render_mode_override) |mode| {
            self.class_spec.font_render_mode = mode;
        }
        return self.class_spec;
    }

    pub fn isInteractive(self: *const SolidNode) bool {
        return self.interactive_self or self.listener_mask != 0;
    }

    pub fn needsLayoutUpdate(self: *const SolidNode) bool {
        if (self.layout.rect == null) return true;
        return self.layout.version < self.layout_subtree_version;
    }

    pub fn invalidateLayout(self: *SolidNode) void {
        self.layout.rect = null;
    }

    pub fn textContentHash(self: *const SolidNode) u64 {
        if (self.text.len == 0) return 0;
        var hasher = std.hash.Wyhash.init(0);
        hasher.update(self.text);
        return hasher.final();
    }
};

const InsertError = error{
    MissingParent,
    MissingChild,
};

pub const VersionTracker = struct {
    value: u64 = 0,

    pub fn next(self: *VersionTracker) u64 {
        self.value +%= 1;
        return self.value;
    }

    pub fn current(self: *const VersionTracker) u64 {
        return self.value;
    }
};

pub const NodeStore = struct {
    allocator: std.mem.Allocator,
    nodes: std.AutoHashMap(u32, SolidNode),
    active_spacing_anim_ids: std.AutoHashMap(u32, u8),
    versions: VersionTracker = .{},

    pub fn init(self: *NodeStore, allocator: std.mem.Allocator) !void {
        self.* = .{
            .allocator = allocator,
            .nodes = std.AutoHashMap(u32, SolidNode).init(allocator),
            .active_spacing_anim_ids = std.AutoHashMap(u32, u8).init(allocator),
            .versions = .{},
        };
        try self.ensureRoot(0);
    }

    pub fn deinit(self: *NodeStore) void {
        var iter = self.nodes.iterator();
        while (iter.next()) |entry| {
            entry.value_ptr.deinit(self.allocator);
        }
        self.nodes.deinit();
        self.active_spacing_anim_ids.deinit();
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
            const tag = found_node.tag;
            if (!std.mem.eql(u8, tag, "input") and !std.mem.eql(u8, tag, "slider")) return;
            if (std.mem.eql(u8, found_node.currentInputValue(), value)) return;
            try found_node.setInputValue(self.allocator, value);
            self.markNodeChanged(id);
        }
    }

    pub fn setTextNode(self: *NodeStore, id: u32, content: []const u8) !void {
        if (self.nodes.getPtr(id)) |_node| {
            if (_node.kind == .text) {
                if (std.mem.eql(u8, _node.text, content)) return;
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
        const parent = self.nodes.getPtr(parent_id) orelse return error.MissingParent;
        const child = self.nodes.getPtr(child_id) orelse return error.MissingChild;

        self.detachFromParent(child);
        child.parent = parent_id;
        child.invalidateLayout();
        child.invalidatePaint();
        self.markNodeChanged(child_id);
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

    pub fn addListenerKind(self: *NodeStore, id: u32, kind: events.EventKind) !void {
        const _node = self.nodes.getPtr(id) orelse return;
        const added = _node.addListenerKind(kind);
        if (added) {
            self.activateInteractive(id);
        }
    }

    pub fn node(self: *NodeStore, id: u32) ?*SolidNode {
        return self.nodes.getPtr(id);
    }

    pub fn noteActiveSpacingAnimation(self: *NodeStore, id: u32) void {
        self.active_spacing_anim_ids.put(id, 1) catch {};
    }

    pub fn setClassName(self: *NodeStore, id: u32, value: []const u8) !void {
        const target = self.nodes.getPtr(id) orelse return;
        if (std.mem.eql(u8, target.class_name, value)) return;
        try target.setClassName(self.allocator, value);
        self.markNodeChanged(id);
    }

    pub fn setFontRenderMode(self: *NodeStore, id: u32, mode: ?tailwind.FontRenderMode) void {
        const target = self.nodes.getPtr(id) orelse return;
        if (target.font_render_mode_override == mode) return;
        target.setFontRenderMode(mode);
        self.markNodeChanged(id);
    }

    pub fn setImageSource(self: *NodeStore, id: u32, value: []const u8) !void {
        const target = self.nodes.getPtr(id) orelse return;
        if (std.mem.eql(u8, target.image_src, value)) return;
        try target.setImageSource(self.allocator, value);
        self.markNodeChanged(id);
    }

    pub fn setImageTint(self: *NodeStore, id: u32, value: u32) !void {
        const target = self.nodes.getPtr(id) orelse return;
        if (target.image_tint) |current| {
            if (current.value == value) return;
        }
        target.setImageTint(value);
        self.markNodePaintChanged(id);
    }

    pub fn setImageOpacity(self: *NodeStore, id: u32, value: f32) !void {
        const target = self.nodes.getPtr(id) orelse return;
        const clamped: f32 = if (value < 0.0) 0.0 else if (value > 1.0) 1.0 else value;
        if (target.image_opacity == clamped) return;
        target.setImageOpacity(clamped);
        self.markNodePaintChanged(id);
    }

    pub fn setIconGlyph(self: *NodeStore, id: u32, value: []const u8) !void {
        const target = self.nodes.getPtr(id) orelse return;
        if (std.mem.eql(u8, target.icon_glyph, value)) return;
        try target.setIconGlyph(self.allocator, value);
        self.markNodeChanged(id);
    }

    pub fn setIconKind(self: *NodeStore, id: u32, value: IconKind) void {
        const target = self.nodes.getPtr(id) orelse return;
        if (target.icon_kind == value) return;
        target.icon_kind = value;
        target.clearIconCache(self.allocator);
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

    pub fn markNodeChanged(self: *NodeStore, id: u32) void {
        const version = self.nextVersion();
        var current: ?u32 = id;
        var is_self = true;
        while (current) |node_id| {
            const _node = self.nodes.getPtr(node_id) orelse break;
            if (is_self) {
                _node.version = version;
                _node.invalidatePaint();
                is_self = false;
            }
            if (_node.subtree_version < version) {
                _node.subtree_version = version;
            }
            if (_node.layout_subtree_version < version) {
                _node.layout_subtree_version = version;
            }
            current = _node.parent;
        }
    }

    pub fn markNodePaintChanged(self: *NodeStore, id: u32) void {
        const version = self.nextVersion();
        const _node = self.nodes.getPtr(id) orelse return;
        _node.version = version;
        _node.invalidatePaint();
    }

    pub fn currentVersion(self: *const NodeStore) u64 {
        return self.versions.current();
    }

    fn nextVersion(self: *NodeStore) u64 {
        return self.versions.next();
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
