const retained = @import("retained");

const types = @import("types.zig");
const Renderer = types.Renderer;

pub fn ensureRetainedStore(renderer: *Renderer, logMessage: anytype) !*retained.NodeStore {
    if (renderer.retained_store_ready) {
        if (types.retainedStore(renderer)) |store| {
            return store;
        }
        renderer.retained_store_ready = false;
    }

    const store = blk: {
        if (types.retainedStore(renderer)) |existing| {
            break :blk existing;
        }
        const allocated = renderer.allocator.create(retained.NodeStore) catch {
            logMessage(renderer, 3, "retained store alloc failed", .{});
            return error.OutOfMemory;
        };
        renderer.retained_store_ptr = allocated;
        break :blk allocated;
    };

    store.init(renderer.allocator) catch |err| {
        logMessage(renderer, 3, "retained store init failed: {s}", .{@errorName(err)});
        return err;
    };
    renderer.retained_store_ready = true;
    return store;
}
