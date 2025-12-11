const solid = @import("solid");

const types = @import("types.zig");
const Renderer = types.Renderer;

// ============================================================
// Event Ring Push Helper
// ============================================================

/// Push an event to the ring buffer (called from Zig render code)
pub fn pushEvent(renderer: *Renderer, kind: solid.EventKind, node_id: u32, detail: ?[]const u8) bool {
    if (!renderer.event_ring_ready) return false;
    if (types.eventRing(renderer)) |ring| {
        return ring.push(kind, node_id, detail);
    }
    return false;
}
