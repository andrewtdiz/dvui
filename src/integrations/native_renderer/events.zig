const retained = @import("retained");

const types = @import("types.zig");
const Renderer = types.Renderer;

// ============================================================
// Event Ring Push Helper
// ============================================================

/// Push an event to the ring buffer (called from Zig render code)
pub fn pushEvent(renderer: *Renderer, kind: retained.EventKind, node_id: u32, detail: ?[]const u8) bool {
    if (!renderer.retained_event_ring_ready) return false;
    if (types.retainedEventRing(renderer)) |ring| {
        return ring.push(kind, node_id, detail);
    }
    return false;
}
