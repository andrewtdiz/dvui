const std = @import("std");
const dvui = @import("dvui");

const types = @import("../../core/types.zig");
const state = @import("state.zig");

pub const OffscreenCacheEntry = struct {
    target: dvui.TextureTarget,
    subtree_version: u64 = 0,
    max_desc_version: u64 = 0,
};

pub const RenderRuntime = struct {
    gizmo_override_rect: ?types.GizmoRect = null,
    gizmo_rect_pending: ?types.GizmoRect = null,
    button_text_error_log_count: usize = 0,
    input_enabled_state: bool = true,

    render_layer: state.RenderLayer = .base,
    hover_layer: state.RenderLayer = .base,
    pointer_top_base_id: u32 = 0,
    pointer_top_overlay_id: u32 = 0,
    modal_overlay_active: bool = false,

    last_mouse_pt: ?dvui.Point.Physical = null,
    last_input_enabled: ?bool = null,
    last_hover_layer: state.RenderLayer = .base,

    portal_cache_allocator: ?std.mem.Allocator = null,
    portal_cache_version: u64 = 0,
    cached_portal_ids: std.ArrayList(u32) = .empty,

    hover_layout_invalidated: bool = false,
    hovered_cache_allocator: ?std.mem.Allocator = null,
    hovered_ids: std.ArrayList(u32) = .empty,

    last_paint_cache_version: u64 = 0,

    cached_overlay_state: state.OverlayState = .{},
    overlay_cache_version: u64 = 0,

    offscreen_cache_allocator: ?std.mem.Allocator = null,
    offscreen_cache: std.AutoHashMapUnmanaged(u32, OffscreenCacheEntry) = .empty,
    offscreen_capture_active: bool = false,

    pressed_node_id: u32 = 0,

    pub fn init(self: *RenderRuntime) void {
        self.* = .{};
    }

    pub fn reset(self: *RenderRuntime) void {
        self.deinit();
        self.* = .{};
    }

    pub fn deinit(self: *RenderRuntime) void {
        if (self.portal_cache_allocator) |alloc| {
            self.cached_portal_ids.deinit(alloc);
        }
        self.cached_portal_ids = .empty;
        self.portal_cache_allocator = null;
        self.portal_cache_version = 0;
        self.cached_overlay_state = .{};
        self.overlay_cache_version = 0;

        if (self.hovered_cache_allocator) |alloc| {
            self.hovered_ids.deinit(alloc);
        }
        self.hovered_ids = .empty;
        self.hovered_cache_allocator = null;

        self.last_paint_cache_version = 0;

        if (self.offscreen_cache_allocator) |alloc| {
            self.offscreen_cache.deinit(alloc);
        }
        self.offscreen_cache = .empty;
        self.offscreen_cache_allocator = null;
        self.offscreen_capture_active = false;
        self.pressed_node_id = 0;
    }

    pub fn allowPointerInput(self: *const RenderRuntime) bool {
        return self.input_enabled_state and self.render_layer == self.hover_layer;
    }

    pub fn pointerTargetId(self: *const RenderRuntime) u32 {
        return if (self.render_layer == .overlay) self.pointer_top_overlay_id else self.pointer_top_base_id;
    }

    pub fn allowFocusRegistration(self: *const RenderRuntime) bool {
        if (!self.input_enabled_state) return false;
        if (!self.modal_overlay_active) return true;
        return self.render_layer == .overlay;
    }
};
