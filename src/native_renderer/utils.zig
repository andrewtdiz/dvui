const dvui = @import("dvui");
const retained = @import("retained");
const types = @import("types.zig");

pub fn asOpaquePtr(comptime T: type, raw: ?*anyopaque) ?*T {
    if (raw) |ptr| {
        return @ptrCast(@alignCast(ptr));
    }
    return null;
}

pub fn retainedStore(renderer: *types.Renderer) ?*retained.NodeStore {
    return asOpaquePtr(retained.NodeStore, renderer.retained_store_ptr);
}

pub fn retainedEventRing(renderer: *types.Renderer) ?*retained.EventRing {
    return asOpaquePtr(retained.EventRing, renderer.retained_event_ring_ptr);
}

pub fn colorFromPacked(value: u32) dvui.Color {
    return .{
        .r = @intCast((value >> 24) & 0xff),
        .g = @intCast((value >> 16) & 0xff),
        .b = @intCast((value >> 8) & 0xff),
        .a = @intCast(value & 0xff),
    };
}
