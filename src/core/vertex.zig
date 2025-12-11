const dvui = @import("../dvui.zig");

pub const Vertex = struct {
    pos: dvui.Point.Physical,
    col: dvui.Color.PMA,
    uv: @Vector(2, f32) = @splat(0),
};

test {
    @import("std").testing.refAllDecls(Vertex);
}
