const swap_chain = @import("../pipeline/swap_chain.zig");

extern fn dvuiCreateMetalLayer(nswindow: *anyopaque) ?*anyopaque;
extern fn dvuiSetMetalLayerSize(layer: *anyopaque, width: f64, height: f64, scale: f64) void;

pub const State = struct {
    layer: *anyopaque,
};

pub const Init = struct {
    swap: swap_chain.Resources,
    state: State,
};

pub fn init(handle: *anyopaque, width: u32, height: u32, content_scale: f32) !Init {
    const layer = dvuiCreateMetalLayer(handle) orelse return error.MissingMetalLayer;
    dvuiSetMetalLayerSize(layer, @floatFromInt(width), @floatFromInt(height), @floatCast(content_scale));
    const swap = try swap_chain.Resources.initMacos(layer, width, height);
    return .{ .swap = swap, .state = .{ .layer = layer } };
}

pub fn resize(state: *State, width: u32, height: u32, content_scale: f32) void {
    dvuiSetMetalLayerSize(state.layer, @floatFromInt(width), @floatFromInt(height), @floatCast(content_scale));
}
