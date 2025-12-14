const types = @import("../core/types.zig");
const events = @import("../events/mod.zig");
const render_mod = @import("mod.zig");

pub fn render(event_ring: ?*events.EventRing, store: *types.NodeStore) bool {
    return render_mod.render(event_ring, store);
}
