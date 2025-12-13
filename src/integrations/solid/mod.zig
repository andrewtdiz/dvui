const jsruntime = @import("jsruntime");

const types = @import("core/types.zig");
pub const NodeStore = types.NodeStore;
pub const SolidNode = types.SolidNode;
pub const Rect = types.Rect;
pub const GizmoRect = types.GizmoRect;
const events_mod = @import("events/mod.zig");
pub const events = events_mod;
pub const EventRing = events_mod.EventRing;
pub const EventKind = events_mod.EventKind;
const layout = @import("layout/mod.zig");
const render_mod = @import("render/mod.zig");

pub fn render(runtime: ?*jsruntime.JSRuntime, store: *types.NodeStore) bool {
    return render_mod.render(runtime, store);
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
