const types = @import("types.zig");

const FrameData = types.FrameData;
const FrameResult = types.FrameResult;

pub fn runFrame(_: anytype, frame_data: FrameData) !FrameResult {
    return .{ .new_position = frame_data.position };
}
