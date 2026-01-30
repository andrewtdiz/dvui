const std = @import("std");

const transitions = @import("transitions.zig");
const types = @import("../core/types.zig");

test "lerpPackedColor endpoints" {
    const a: types.PackedColor = .{ .value = 0x00000000 };
    const b: types.PackedColor = .{ .value = 0xff0000ff };

    try std.testing.expectEqual(a.value, transitions.lerpPackedColor(a, b, 0).value);
    try std.testing.expectEqual(b.value, transitions.lerpPackedColor(a, b, 1).value);

    const mid = transitions.lerpPackedColor(a, b, 0.5);
    const r: u8 = @intCast((mid.value >> 24) & 0xff);
    const g: u8 = @intCast((mid.value >> 16) & 0xff);
    const bl: u8 = @intCast((mid.value >> 8) & 0xff);
    const al: u8 = @intCast(mid.value & 0xff);
    try std.testing.expect(r > 0 and r < 255);
    try std.testing.expectEqual(@as(u8, 0), g);
    try std.testing.expectEqual(@as(u8, 0), bl);
    try std.testing.expect(al > 0 and al < 255);
}

test "shortestAngleTarget chooses minimal wrap" {
    const from: f32 = std.math.pi * 0.9;
    const to: f32 = -std.math.pi * 0.9;
    const got = transitions.shortestAngleTarget(from, to);
    const expected = from + (2.0 * std.math.pi - 1.8 * std.math.pi);
    try std.testing.expectApproxEqAbs(expected, got, 0.0001);
}

