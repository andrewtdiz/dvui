const jsruntime = @import("../../jsruntime/mod.zig");
const types = @import("../core/types.zig");
const render_mod = @import("mod.zig");

pub fn render(runtime: *jsruntime.JSRuntime, store: *types.NodeStore) bool {
    return render_mod.render(runtime, store);
}
