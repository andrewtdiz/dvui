const wgpu = @import("wgpu");

pub const format = wgpu.TextureFormat.depth24_plus_stencil8;

pub const Resources = @This();

texture: *wgpu.Texture,
view: *wgpu.TextureView,

pub fn init(device: *wgpu.Device, width: u32, height: u32) !Resources {
    const desc = wgpu.TextureDescriptor{
        .dimension = wgpu.TextureDimension.@"2d",
        .format = format,
        .mip_level_count = 1,
        .sample_count = 1,
        .size = wgpu.Extent3D{ .width = width, .height = height, .depth_or_array_layers = 1 },
        .usage = wgpu.TextureUsages.render_attachment,
        .view_format_count = 1,
        .view_formats = &[_]wgpu.TextureFormat{format},
    };
    const texture = device.createTexture(&desc).?;
    errdefer texture.release();

    const view = texture.createView(&wgpu.TextureViewDescriptor{
        .aspect = wgpu.TextureAspect.all,
        .base_array_layer = 0,
        .array_layer_count = 1,
        .base_mip_level = 0,
        .mip_level_count = 1,
        .dimension = wgpu.ViewDimension.@"2d",
        .format = format,
    }).?;
    errdefer view.release();

    return .{ .texture = texture, .view = view };
}

pub fn deinit(self: *Resources) void {
    self.view.release();
    self.texture.release();
}
