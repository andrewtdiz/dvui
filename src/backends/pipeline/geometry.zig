const alloc = @import("../../../alloc.zig");
const wgpu = @import("wgpu");

pub const VertexAttributes = struct {
    position: [3]f32,
    uv: [2]f32,
};

pub const Resources = @This();

vertex_data: []VertexAttributes,
vertex_count: u32,
vertex_buffer: *wgpu.Buffer,

const quad_vertices = [_]VertexAttributes{
    .{ .position = .{ -0.5, -0.5, 0.0 }, .uv = .{ 0.0, 1.0 } },
    .{ .position = .{ 0.5, -0.5, 0.0 }, .uv = .{ 1.0, 1.0 } },
    .{ .position = .{ 0.5, 0.5, 0.0 }, .uv = .{ 1.0, 0.0 } },
    .{ .position = .{ -0.5, -0.5, 0.0 }, .uv = .{ 0.0, 1.0 } },
    .{ .position = .{ 0.5, 0.5, 0.0 }, .uv = .{ 1.0, 0.0 } },
    .{ .position = .{ -0.5, 0.5, 0.0 }, .uv = .{ 0.0, 0.0 } },
};

pub fn init(self: *Resources, device: *wgpu.Device, queue: *wgpu.Queue) !void {
    const allocator = alloc.allocator();
    const data = try allocator.alloc(VertexAttributes, quad_vertices.len);
    errdefer allocator.free(data);
    for (quad_vertices, 0..) |v, i| {
        data[i] = v;
    }

    const byte_len: usize = data.len * @sizeOf(VertexAttributes);
    const buffer_desc = &wgpu.BufferDescriptor{
        .label = wgpu.StringView.fromSlice("GPU quad vertex buffer"),
        .usage = wgpu.BufferUsages.vertex | wgpu.BufferUsages.copy_dst,
        .size = ((@as(u64, @intCast(byte_len)) + 3) & ~@as(u64, 3)),
        .mapped_at_creation = @as(u32, @intFromBool(false)),
    };
    const vb = device.createBuffer(buffer_desc).?;
    errdefer vb.release();

    queue.writeBuffer(vb, 0, data.ptr, byte_len);
    self.vertex_data = data;
    self.vertex_count = @intCast(data.len);
    self.vertex_buffer = vb;
}

pub fn deinit(self: *Resources) void {
    const allocator = alloc.allocator();
    self.vertex_buffer.release();
    allocator.free(self.vertex_data);
}
