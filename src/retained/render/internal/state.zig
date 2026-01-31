const std = @import("std");
const dvui = @import("dvui");

const types = @import("../../core/types.zig");

pub var gizmo_override_rect: ?types.GizmoRect = null;
pub var gizmo_rect_pending: ?types.GizmoRect = null;
pub var logged_tree_dump: bool = false;
pub var logged_render_state: bool = false;
pub var logged_button_render: bool = false;
pub var button_debug_count: usize = 0;
pub var button_text_error_log_count: usize = 0;
pub var paragraph_log_count: usize = 0;
pub var input_enabled_state: bool = true;

pub const RenderLayer = enum {
    base,
    overlay,
};

pub const overlay_subwindow_seed: u32 = 0x4f564c59;

pub var render_layer: RenderLayer = .base;
pub var hover_layer: RenderLayer = .base;
pub var pointer_top_base_id: u32 = 0;
pub var pointer_top_overlay_id: u32 = 0;
pub var modal_overlay_active: bool = false;
pub var last_mouse_pt: ?dvui.Point.Physical = null;
pub var last_input_enabled: ?bool = null;
pub var last_hover_layer: RenderLayer = .base;
pub var portal_cache_allocator: ?std.mem.Allocator = null;
pub var portal_cache_version: u64 = 0;
pub var cached_portal_ids: std.ArrayList(u32) = .empty;
pub var hover_layout_invalidated: bool = false;

pub const OverlayState = struct {
    modal: bool = false,
    hit_rect: ?types.Rect = null,
};

pub var cached_overlay_state: OverlayState = .{};
pub var overlay_cache_version: u64 = 0;

pub const ClipState = struct {
    active: bool = false,
    rect: types.Rect = .{},
};

pub const PointerPick = struct {
    id: u32 = 0,
    z_index: i16 = std.math.minInt(i16),
    order: u32 = 0,
};

pub const OrderedNode = struct {
    id: u32,
    z_index: i16,
    order: usize,
};

fn orderedNodeLessThan(_: void, lhs: OrderedNode, rhs: OrderedNode) bool {
    if (lhs.z_index == rhs.z_index) {
        return lhs.order < rhs.order;
    }
    return lhs.z_index < rhs.z_index;
}

pub fn sortOrderedNodes(nodes: []OrderedNode) void {
    if (nodes.len < 2) return;
    std.sort.pdq(OrderedNode, nodes, {}, orderedNodeLessThan);
}

pub fn physicalToDvuiRect(rect: types.Rect) dvui.Rect {
    const scale = dvui.windowNaturalScale();
    const inv_scale: f32 = if (scale != 0) 1.0 / scale else 1.0;
    return dvui.Rect{
        .x = rect.x * inv_scale,
        .y = rect.y * inv_scale,
        .w = rect.w * inv_scale,
        .h = rect.h * inv_scale,
    };
}

pub fn intersectRect(a: types.Rect, b: types.Rect) types.Rect {
    const x0 = @max(a.x, b.x);
    const y0 = @max(a.y, b.y);
    const x1 = @min(a.x + a.w, b.x + b.w);
    const y1 = @min(a.y + a.h, b.y + b.h);
    return types.Rect{
        .x = x0,
        .y = y0,
        .w = @max(0.0, x1 - x0),
        .h = @max(0.0, y1 - y0),
    };
}

pub fn unionRect(a: types.Rect, b: types.Rect) types.Rect {
    const x0 = @min(a.x, b.x);
    const y0 = @min(a.y, b.y);
    const x1 = @max(a.x + a.w, b.x + b.w);
    const y1 = @max(a.y + a.h, b.y + b.h);
    return types.Rect{
        .x = x0,
        .y = y0,
        .w = @max(0.0, x1 - x0),
        .h = @max(0.0, y1 - y0),
    };
}

pub fn appendRect(target: *?types.Rect, rect: types.Rect) void {
    if (rect.w <= 0 or rect.h <= 0) return;
    if (target.*) |existing| {
        target.* = unionRect(existing, rect);
    } else {
        target.* = rect;
    }
}

pub fn rectContains(rect: types.Rect, point: dvui.Point.Physical) bool {
    if (rect.w <= 0 or rect.h <= 0) return false;
    if (point.x < rect.x or point.y < rect.y) return false;
    if (point.x > rect.x + rect.w or point.y > rect.y + rect.h) return false;
    return true;
}

pub fn isPortalNode(node: *const types.SolidNode) bool {
    return node.kind == .element and std.mem.eql(u8, node.tag, "portal");
}

pub fn allowPointerInput() bool {
    return input_enabled_state and render_layer == hover_layer;
}

pub fn pointerTargetId() u32 {
    return if (render_layer == .overlay) pointer_top_overlay_id else pointer_top_base_id;
}

pub fn allowFocusRegistration() bool {
    if (!input_enabled_state) return false;
    if (!modal_overlay_active) return true;
    return render_layer == .overlay;
}

pub fn overlaySubwindowId() dvui.Id {
    return dvui.Id.extendId(null, @src(), nodeIdExtra(overlay_subwindow_seed));
}

pub fn scrollContentId(node_id: u32) dvui.Id {
    return dvui.Id.extendId(null, @src(), nodeIdExtra(node_id));
}

pub fn nodeIdExtra(id: u32) usize {
    var hasher = std.hash.Wyhash.init(0);
    hasher.update(std.mem.asBytes(&id));
    return @intCast(hasher.final());
}
