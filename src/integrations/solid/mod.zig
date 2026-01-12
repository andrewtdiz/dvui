const types = @import("core/types.zig");
pub const NodeStore = types.NodeStore;
pub const SolidNode = types.SolidNode;
pub const Rect = types.Rect;
pub const GizmoRect = types.GizmoRect;
pub const AnchorSide = types.AnchorSide;
pub const AnchorAlign = types.AnchorAlign;
const events_mod = @import("events/mod.zig");
pub const events = events_mod;
pub const EventRing = events_mod.EventRing;
pub const EventKind = events_mod.EventKind;
const layout = @import("layout/mod.zig");
const render_mod = @import("render/mod.zig");

pub fn render(event_ring: ?*EventRing, store: *types.NodeStore) bool {
    return render_mod.render(event_ring, store);
}

pub fn updateLayouts(store: *types.NodeStore) void {
    layout.updateLayouts(store);
}

pub fn setGizmoRectOverride(rect: ?types.GizmoRect) void {
    render_mod.setGizmoRectOverride(rect);
}

pub fn takeGizmoRectUpdate() ?types.GizmoRect {
    return render_mod.takeGizmoRectUpdate();
}
