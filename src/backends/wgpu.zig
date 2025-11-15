const std = @import("std");
const dvui = @import("dvui");
const wgpu = @import("wgpu");

pub const kind: dvui.enums.Backend = .wgpu;

pub const WgpuBackend = @This();
pub const Context = *WgpuBackend;
pub const SurfaceConfig = struct {
    window_size: dvui.Size.Natural = .{ .w = 1, .h = 1 },
    pixel_size: dvui.Size.Physical = .{ .w = 1, .h = 1 },
    surface_size: dvui.Size.Physical = .{ .w = 1, .h = 1 },
    viewport_origin: dvui.Point.Physical = .{ .x = 0, .y = 0 },
    content_scale: f32 = 1.0,
};

pub const InitOptions = struct {
    gpa: std.mem.Allocator,
    device: *wgpu.Device,
    queue: *wgpu.Queue,
    color_format: wgpu.TextureFormat,
    depth_format: ?wgpu.TextureFormat = null,
    sample_count: u32 = 1,
    max_frames_in_flight: u32 = 1,
    preferred_color_scheme: ?dvui.enums.ColorScheme = null,
};

const DrawCommand = struct {
    texture: *TextureResource,
    index_offset: u32,
    index_count: u32,
    vertex_offset: i32,
    clip_rect: ClipRect,
};

const ClipRect = struct {
    enabled: bool = false,
    x: i32 = 0,
    y: i32 = 0,
    width: i32 = 0,
    height: i32 = 0,
};

const Extent2D = struct {
    width: u32 = 0,
    height: u32 = 0,
};

const Vertex = extern struct {
    position: [2]f32,
    uv: [2]f32,
    color: [4]u8,
};

const Globals = extern struct {
    surface_size: [2]f32,
    viewport_origin: [2]f32,
};

const TextureResource = struct {
    texture: *wgpu.Texture,
    view: *wgpu.TextureView,
    sampler: *wgpu.Sampler,
    bind_group: *wgpu.BindGroup,
    interpolation: dvui.enums.TextureInterpolation,

    fn deinit(self: *TextureResource) void {
        self.bind_group.release();
        self.view.release();
        self.sampler.release();
        self.texture.release();
    }
};

gpa: std.mem.Allocator,
device: *wgpu.Device,
queue: *wgpu.Queue,
color_format: wgpu.TextureFormat,
depth_format: ?wgpu.TextureFormat,
sample_count: u32,
max_frames_in_flight: u32,
preferred_color_scheme: ?dvui.enums.ColorScheme,

surface: SurfaceConfig = .{},

vertex_data: std.ArrayListUnmanaged(Vertex) = .{},
index_data: std.ArrayListUnmanaged(u16) = .{},
draw_commands: std.ArrayListUnmanaged(DrawCommand) = .{},

shader_module: ?*wgpu.ShaderModule = null,
texture_bind_group_layout: ?*wgpu.BindGroupLayout = null,
globals_bind_group_layout: ?*wgpu.BindGroupLayout = null,
pipeline_layout: ?*wgpu.PipelineLayout = null,
render_pipeline: ?*wgpu.RenderPipeline = null,

globals_buffer: ?*wgpu.Buffer = null,
globals_bind_group: ?*wgpu.BindGroup = null,
vertex_buffer: ?*wgpu.Buffer = null,
index_buffer: ?*wgpu.Buffer = null,

default_texture: ?*TextureResource = null,

frame_arena: std.mem.Allocator = undefined,

msaa_texture: ?*wgpu.Texture = null,
msaa_view: ?*wgpu.TextureView = null,
msaa_extent: Extent2D = .{},

pub fn init(options: InitOptions) !WgpuBackend {
    var wgpu_backend: WgpuBackend = .{
        .gpa = options.gpa,
        .device = options.device,
        .queue = options.queue,
        .color_format = options.color_format,
        .depth_format = options.depth_format,
        .sample_count = options.sample_count,
        .max_frames_in_flight = options.max_frames_in_flight,
        .preferred_color_scheme = options.preferred_color_scheme,
    };

    try wgpu_backend.ensurePipeline();
    wgpu_backend.default_texture = try wgpu_backend.createSolidTexture(.linear, 0xffffffff);

    return wgpu_backend;
}

pub fn deinit(self: *WgpuBackend) void {
    if (self.default_texture) |texture| {
        texture.deinit();
        self.gpa.destroy(texture);
        self.default_texture = null;
    }

    if (self.vertex_buffer) |buf| {
        buf.release();
        self.vertex_buffer = null;
    }
    if (self.index_buffer) |buf| {
        buf.release();
        self.index_buffer = null;
    }
    if (self.globals_bind_group) |group| {
        group.release();
        self.globals_bind_group = null;
    }
    if (self.globals_buffer) |buffer| {
        buffer.release();
        self.globals_buffer = null;
    }
    if (self.render_pipeline) |pipeline| {
        pipeline.release();
        self.render_pipeline = null;
    }
    if (self.pipeline_layout) |layout| {
        layout.release();
        self.pipeline_layout = null;
    }
    if (self.shader_module) |module| {
        module.release();
        self.shader_module = null;
    }
    if (self.texture_bind_group_layout) |layout| {
        layout.release();
        self.texture_bind_group_layout = null;
    }
    if (self.globals_bind_group_layout) |layout| {
        layout.release();
        self.globals_bind_group_layout = null;
    }

    self.destroyMsaaResources();

    self.vertex_data.deinit(self.gpa);
    self.index_data.deinit(self.gpa);
    self.draw_commands.deinit(self.gpa);
}

pub fn backend(self: *WgpuBackend) dvui.Backend {
    return dvui.Backend.init(self);
}

pub fn updateSurface(self: *WgpuBackend, config: SurfaceConfig) void {
    self.surface = config;
    if (self.sample_count > 1) {
        self.destroyMsaaResources();
    }
}

pub fn hasCommands(self: *const WgpuBackend) bool {
    return self.draw_commands.items.len > 0;
}

pub fn encode(self: *WgpuBackend, encoder: *wgpu.CommandEncoder, color_view: *wgpu.TextureView) !void {
    if (self.draw_commands.items.len == 0) return;

    try self.ensurePipeline();
    try self.ensureGlobals();
    try self.uploadGeometry();

    var color_attachment = wgpu.ColorAttachment{
        .view = color_view,
        .resolve_target = null,
        .load_op = wgpu.LoadOp.load,
        .store_op = wgpu.StoreOp.store,
        .clear_value = .{ .r = 0, .g = 0, .b = 0, .a = 0 },
    };

    if (self.sample_count > 1) {
        try self.ensureMsaaResources();
        color_attachment.view = self.msaa_view.?;
        color_attachment.resolve_target = color_view;
        color_attachment.load_op = wgpu.LoadOp.clear;
        color_attachment.store_op = wgpu.StoreOp.discard;
    }

    const pass = encoder.beginRenderPass(&wgpu.RenderPassDescriptor{
        .label = wgpu.StringView.fromSlice("dvui pass"),
        .color_attachment_count = 1,
        .color_attachments = &[_]wgpu.ColorAttachment{color_attachment},
    }) orelse return dvui.Backend.GenericError.BackendError;
    defer pass.release();

    pass.setPipeline(self.render_pipeline.?);
    pass.setVertexBuffer(0, self.vertex_buffer.?, 0, wgpu.WGPU_WHOLE_SIZE);
    pass.setIndexBuffer(self.index_buffer.?, .uint16, 0, wgpu.WGPU_WHOLE_SIZE);
    pass.setBindGroup(0, self.globals_bind_group.?, 0, &[_]u32{});

    const viewport = self.viewportRect();
    const viewport_width = if (self.surface.surface_size.w <= 0) 1.0 else self.surface.surface_size.w;
    const viewport_height = if (self.surface.surface_size.h <= 0) 1.0 else self.surface.surface_size.h;
    pass.setViewport(0.0, 0.0, viewport_width, viewport_height, 0.0, 1.0);
    pass.setScissorRect(@intCast(viewport.x), @intCast(viewport.y), @intCast(viewport.width), @intCast(viewport.height));

    var current_scissor = ClipRect{ .enabled = false };
    for (self.draw_commands.items) |cmd| {
        if (cmd.clip_rect.enabled) {
            if (!self.applyClip(pass, cmd.clip_rect, &current_scissor)) continue;
        } else if (current_scissor.enabled) {
            current_scissor = .{ .enabled = false };
            pass.setScissorRect(@intCast(viewport.x), @intCast(viewport.y), @intCast(viewport.width), @intCast(viewport.height));
        }

        pass.setBindGroup(1, cmd.texture.bind_group, 0, &[_]u32{});
        pass.drawIndexed(cmd.index_count, 1, cmd.index_offset, cmd.vertex_offset, 0);
    }

    pass.end();
    self.clearFrameData();
}

pub fn begin(self: *WgpuBackend, arena: std.mem.Allocator) !void {
    self.frame_arena = arena;
    self.clearFrameData();
}

pub fn end(_: *WgpuBackend) !void {}

pub fn nanoTime(_: *WgpuBackend) i128 {
    return std.time.nanoTimestamp();
}

pub fn sleep(_: *WgpuBackend, ns: u64) void {
    std.Thread.sleep(ns);
}

pub fn pixelSize(self: *WgpuBackend) dvui.Size.Physical {
    return self.surface.pixel_size;
}

pub fn windowSize(self: *WgpuBackend) dvui.Size.Natural {
    return self.surface.window_size;
}

pub fn contentScale(self: *WgpuBackend) f32 {
    return self.surface.content_scale;
}

pub fn drawClippedTriangles(
    self: *WgpuBackend,
    texture: ?dvui.Texture,
    vtx: []const dvui.Vertex,
    idx: []const u16,
    clipr: ?dvui.Rect.Physical,
) dvui.Backend.GenericError!void {
    if (vtx.len == 0 or idx.len == 0) return;

    const base_vertex_i32: i32 = @intCast(self.vertex_data.items.len);
    try self.vertex_data.ensureTotalCapacity(self.gpa, self.vertex_data.items.len + vtx.len);
    try self.index_data.ensureTotalCapacity(self.gpa, self.index_data.items.len + idx.len);
    try self.draw_commands.ensureTotalCapacity(self.gpa, self.draw_commands.items.len + 1);

    for (vtx) |vertex| {
        const color = vertex.col;
        self.vertex_data.appendAssumeCapacity(.{
            .position = .{ vertex.pos.x, vertex.pos.y },
            .uv = vertex.uv,
            .color = .{ color.r, color.g, color.b, color.a },
        });
    }

    const index_offset: u32 = @intCast(self.index_data.items.len);
    for (idx) |value| {
        self.index_data.appendAssumeCapacity(value);
    }

    const resource = textureToResource(self, texture) orelse self.default_texture.?;

    var clip_rect = ClipRect{ .enabled = false };
    if (clipr) |rect| {
        clip_rect = self.computeClipRect(rect);
        if (clip_rect.width <= 0 or clip_rect.height <= 0) {
            return;
        }
    }

    self.draw_commands.appendAssumeCapacity(.{
        .texture = resource,
        .index_offset = index_offset,
        .index_count = @intCast(idx.len),
        .vertex_offset = base_vertex_i32,
        .clip_rect = clip_rect,
    });
}

pub fn textureCreate(
    self: *WgpuBackend,
    pixels: [*]const u8,
    width: u32,
    height: u32,
    interpolation: dvui.enums.TextureInterpolation,
) dvui.Backend.TextureError!dvui.Texture {
    const texture = try self.createTextureResource(width, height, interpolation, pixels);
    return dvui.Texture{ .ptr = texture, .width = width, .height = height };
}

pub fn textureDestroy(self: *WgpuBackend, texture: dvui.Texture) void {
    const resource: *TextureResource = @ptrCast(@alignCast(texture.ptr));
    resource.deinit();
    self.gpa.destroy(resource);
}

pub fn textureUpdate(
    self: *WgpuBackend,
    texture: dvui.Texture,
    pixels: [*]const u8,
) dvui.Backend.TextureError!void {
    if (texture.ptr == null) return dvui.Backend.TextureError.TextureUpdate;
    const resource: *TextureResource = @ptrCast(@alignCast(texture.ptr));
    const texture_bytes: usize = @intCast(@as(u64, texture.width) * @as(u64, texture.height) * 4);
    const copy_texture = wgpu.TexelCopyTextureInfo{
        .texture = resource.texture,
        .mip_level = 0,
        .origin = .{ .x = 0, .y = 0, .z = 0 },
        .aspect = .all,
    };
    const layout = wgpu.TexelCopyBufferLayout{
        .offset = 0,
        .bytes_per_row = texture.width * 4,
        .rows_per_image = texture.height,
    };
    const extent = wgpu.Extent3D{
        .width = texture.width,
        .height = texture.height,
        .depth_or_array_layers = 1,
    };
    self.queue.writeTexture(
        &copy_texture,
        pixels,
        texture_bytes,
        &layout,
        &extent,
    );
}

pub fn textureCreateTarget(
    _: *WgpuBackend,
    _: u32,
    _: u32,
    _: dvui.enums.TextureInterpolation,
) dvui.Backend.TextureError!dvui.TextureTarget {
    return dvui.Backend.TextureError.NotImplemented;
}

pub fn textureReadTarget(
    _: *WgpuBackend,
    _: dvui.TextureTarget,
    _: [*]u8,
) dvui.Backend.TextureError!void {
    return dvui.Backend.TextureError.NotImplemented;
}

pub fn textureFromTarget(_: *WgpuBackend, _: dvui.TextureTarget) dvui.Backend.TextureError!dvui.Texture {
    return dvui.Backend.TextureError.NotImplemented;
}

pub fn renderTarget(_: *WgpuBackend, _: ?dvui.TextureTarget) dvui.Backend.GenericError!void {
    return error.BackendError;
}

pub fn clipboardText(_: *WgpuBackend) dvui.Backend.GenericError![]const u8 {
    return dvui.Backend.GenericError.BackendError;
}

pub fn clipboardTextSet(_: *WgpuBackend, _: []const u8) dvui.Backend.GenericError!void {
    return dvui.Backend.GenericError.BackendError;
}

pub fn openURL(_: *WgpuBackend, _: []const u8, _: bool) dvui.Backend.GenericError!void {
    return dvui.Backend.GenericError.BackendError;
}

pub fn preferredColorScheme(self: *WgpuBackend) ?dvui.enums.ColorScheme {
    return self.preferred_color_scheme;
}

pub fn refresh(_: *WgpuBackend) void {}

pub fn accessKitShouldInitialize(_: *WgpuBackend) bool {
    return false;
}

pub fn accessKitInitInBegin(_: *WgpuBackend) dvui.Backend.GenericError!void {
    return;
}

fn textureToResource(self: *WgpuBackend, texture: ?dvui.Texture) ?*TextureResource {
    if (texture) |tex| {
        if (@intFromPtr(tex.ptr) == 0) return null;
        return @ptrCast(@alignCast(tex.ptr));
    }
    return self.default_texture;
}

fn ensurePipeline(self: *WgpuBackend) !void {
    if (self.render_pipeline != null) return;

    if (self.shader_module == null) {
        const shader = self.device.createShaderModule(&wgpu.shaderModuleWGSLDescriptor(.{ .code = shader_source })) orelse return dvui.Backend.GenericError.BackendError;
        self.shader_module = shader;
    }

    if (self.globals_bind_group_layout == null) {
        const layout = self.device.createBindGroupLayout(&wgpu.BindGroupLayoutDescriptor{
            .label = wgpu.StringView.fromSlice("dvui globals"),
            .entry_count = 1,
            .entries = &[_]wgpu.BindGroupLayoutEntry{
                .{
                    .binding = 0,
                    .visibility = wgpu.ShaderStages.vertex,
                    .buffer = wgpu.BufferBindingLayout{
                        .type = .uniform,
                        .has_dynamic_offset = 0,
                        .min_binding_size = @sizeOf(Globals),
                    },
                },
            },
        }) orelse return dvui.Backend.GenericError.BackendError;
        self.globals_bind_group_layout = layout;
    }

    if (self.texture_bind_group_layout == null) {
        const sampler_entry = wgpu.BindGroupLayoutEntry{
            .binding = 0,
            .visibility = wgpu.ShaderStages.fragment,
            .sampler = wgpu.SamplerBindingLayout{ .type = .filtering },
        };
        const texture_entry = wgpu.BindGroupLayoutEntry{
            .binding = 1,
            .visibility = wgpu.ShaderStages.fragment,
            .texture = wgpu.TextureBindingLayout{ .sample_type = .float, .view_dimension = .@"2d", .multisampled = 0 },
        };
        const layout = self.device.createBindGroupLayout(&wgpu.BindGroupLayoutDescriptor{
            .label = wgpu.StringView.fromSlice("dvui textures"),
            .entry_count = 2,
            .entries = &[_]wgpu.BindGroupLayoutEntry{ sampler_entry, texture_entry },
        }) orelse return dvui.Backend.GenericError.BackendError;
        self.texture_bind_group_layout = layout;
    }

    if (self.pipeline_layout == null) {
        const layout = self.device.createPipelineLayout(&wgpu.PipelineLayoutDescriptor{
            .label = wgpu.StringView.fromSlice("dvui pipeline layout"),
            .bind_group_layout_count = 2,
            .bind_group_layouts = &[_]*wgpu.BindGroupLayout{ self.globals_bind_group_layout.?, self.texture_bind_group_layout.? },
        }) orelse return dvui.Backend.GenericError.BackendError;
        self.pipeline_layout = layout;
    }

    const vertex_attributes = [_]wgpu.VertexAttribute{
        .{ .format = .float32x2, .offset = @offsetOf(Vertex, "position"), .shader_location = 0 },
        .{ .format = .float32x2, .offset = @offsetOf(Vertex, "uv"), .shader_location = 1 },
        .{ .format = .unorm8x4, .offset = @offsetOf(Vertex, "color"), .shader_location = 2 },
    };

    const vertex_buffers = [_]wgpu.VertexBufferLayout{
        .{
            .array_stride = @sizeOf(Vertex),
            .step_mode = wgpu.VertexStepMode.vertex,
            .attribute_count = vertex_attributes.len,
            .attributes = &vertex_attributes,
        },
    };

    const color_target = wgpu.ColorTargetState{
        .format = self.color_format,
        .blend = &wgpu.BlendState{
            .color = wgpu.BlendComponent{ .operation = .add, .src_factor = .one, .dst_factor = .one_minus_src_alpha },
            .alpha = wgpu.BlendComponent{ .operation = .add, .src_factor = .one, .dst_factor = .one_minus_src_alpha },
        },
        .write_mask = wgpu.ColorWriteMasks.all,
    };

    const multisample = wgpu.MultisampleState{
        .count = self.sample_count,
        .mask = std.math.maxInt(u32),
        .alpha_to_coverage_enabled = 0,
    };

    const pipeline = self.device.createRenderPipeline(&wgpu.RenderPipelineDescriptor{
        .label = wgpu.StringView.fromSlice("dvui pipeline"),
        .layout = self.pipeline_layout.?,
        .vertex = wgpu.VertexState{
            .module = self.shader_module.?,
            .entry_point = wgpu.StringView.fromSlice("vs_main"),
            .buffer_count = vertex_buffers.len,
            .buffers = &vertex_buffers,
        },
        .primitive = wgpu.PrimitiveState{ .topology = .triangle_list, .cull_mode = .none },
        .depth_stencil = null,
        .multisample = multisample,
        .fragment = &wgpu.FragmentState{
            .module = self.shader_module.?,
            .entry_point = wgpu.StringView.fromSlice("fs_main"),
            .target_count = 1,
            .targets = &[_]wgpu.ColorTargetState{ color_target },
        },
    }) orelse return dvui.Backend.GenericError.BackendError;

    self.render_pipeline = pipeline;
}

fn ensureGlobals(self: *WgpuBackend) !void {
    const surface_w = if (self.surface.surface_size.w <= 0) 1.0 else self.surface.surface_size.w;
    const surface_h = if (self.surface.surface_size.h <= 0) 1.0 else self.surface.surface_size.h;
    const origin_x = if (self.surface.viewport_origin.x < 0) 0 else self.surface.viewport_origin.x;
    const origin_y = if (self.surface.viewport_origin.y < 0) 0 else self.surface.viewport_origin.y;

    const globals_data = Globals{
        .surface_size = .{ surface_w, surface_h },
        .viewport_origin = .{ origin_x, origin_y },
    };

    if (self.globals_buffer == null) {
        const buffer = self.device.createBuffer(&wgpu.BufferDescriptor{
            .label = wgpu.StringView.fromSlice("dvui globals"),
            .usage = wgpu.BufferUsages.uniform | wgpu.BufferUsages.copy_dst,
            .size = @sizeOf(Globals),
            .mapped_at_creation = @intFromBool(false),
        }) orelse return dvui.Backend.GenericError.BackendError;
        self.globals_buffer = buffer;
    }

    self.queue.writeBuffer(self.globals_buffer.?, 0, &globals_data, @sizeOf(Globals));

    if (self.globals_bind_group == null) {
        const bind_group = self.device.createBindGroup(&wgpu.BindGroupDescriptor{
            .label = wgpu.StringView.fromSlice("dvui globals"),
            .layout = self.globals_bind_group_layout.?,
            .entry_count = 1,
            .entries = &[_]wgpu.BindGroupEntry{
                .{
                    .binding = 0,
                    .buffer = self.globals_buffer.?,
                    .offset = 0,
                    .size = @sizeOf(Globals),
                },
            },
        }) orelse return dvui.Backend.GenericError.BackendError;
        self.globals_bind_group = bind_group;
    }
}

fn uploadGeometry(self: *WgpuBackend) !void {
    if (self.vertex_data.items.len == 0 or self.index_data.items.len == 0) return;

    const vertex_bytes: usize = self.vertex_data.items.len * @sizeOf(Vertex);
    const index_bytes: usize = self.index_data.items.len * @sizeOf(u16);
    const vertex_buffer_size = std.mem.alignForward(usize, vertex_bytes, 4);
    const index_buffer_size = std.mem.alignForward(usize, index_bytes, 4);

    if (self.vertex_buffer) |buffer| {
        buffer.release();
    }
    if (self.index_buffer) |buffer| {
        buffer.release();
    }

    self.vertex_buffer = self.device.createBuffer(&wgpu.BufferDescriptor{
        .label = wgpu.StringView.fromSlice("dvui vertices"),
        .usage = wgpu.BufferUsages.vertex | wgpu.BufferUsages.copy_dst,
        .size = vertex_buffer_size,
        .mapped_at_creation = @intFromBool(false),
    }) orelse return dvui.Backend.GenericError.BackendError;

    self.index_buffer = self.device.createBuffer(&wgpu.BufferDescriptor{
        .label = wgpu.StringView.fromSlice("dvui indices"),
        .usage = wgpu.BufferUsages.index | wgpu.BufferUsages.copy_dst,
        .size = index_buffer_size,
        .mapped_at_creation = @intFromBool(false),
    }) orelse return dvui.Backend.GenericError.BackendError;

    const vertex_bytes_slice = std.mem.sliceAsBytes(self.vertex_data.items);
    try self.writeBufferAligned(self.vertex_buffer.?, vertex_bytes_slice);

    const index_bytes_slice = std.mem.sliceAsBytes(self.index_data.items);
    try self.writeBufferAligned(self.index_buffer.?, index_bytes_slice);
}

fn clearFrameData(self: *WgpuBackend) void {
    self.vertex_data.clearRetainingCapacity();
    self.index_data.clearRetainingCapacity();
    self.draw_commands.clearRetainingCapacity();
}

fn destroyMsaaResources(self: *WgpuBackend) void {
    if (self.msaa_view) |view| {
        view.release();
        self.msaa_view = null;
    }
    if (self.msaa_texture) |texture| {
        texture.release();
        self.msaa_texture = null;
    }
    self.msaa_extent = .{};
}

fn ensureMsaaResources(self: *WgpuBackend) !void {
    if (self.sample_count <= 1) return;

    const target_width: u32 = if (self.surface.surface_size.w <= 0) @as(u32, 0) else @intFromFloat(@ceil(self.surface.surface_size.w));
    const target_height: u32 = if (self.surface.surface_size.h <= 0) @as(u32, 0) else @intFromFloat(@ceil(self.surface.surface_size.h));

    if (target_width == 0 or target_height == 0) {
        return dvui.Backend.GenericError.BackendError;
    }

    if (self.msaa_texture != null and self.msaa_extent.width == target_width and self.msaa_extent.height == target_height) {
        return;
    }

    self.destroyMsaaResources();

    const descriptor = wgpu.TextureDescriptor{
        .label = wgpu.StringView.fromSlice("dvui msaa color"),
        .usage = wgpu.TextureUsages.render_attachment,
        .dimension = .@"2d",
        .size = .{ .width = target_width, .height = target_height, .depth_or_array_layers = 1 },
        .format = self.color_format,
        .mip_level_count = 1,
        .sample_count = self.sample_count,
    };

    const texture = self.device.createTexture(&descriptor) orelse return dvui.Backend.GenericError.BackendError;
    errdefer texture.release();

    const view = texture.createView(&wgpu.TextureViewDescriptor{}) orelse return dvui.Backend.GenericError.BackendError;
    errdefer view.release();

    self.msaa_texture = texture;
    self.msaa_view = view;
    self.msaa_extent = .{ .width = target_width, .height = target_height };
}

fn applyClip(
    self: *WgpuBackend,
    pass: *wgpu.RenderPassEncoder,
    clip: ClipRect,
    previous: *ClipRect,
) bool {
    const viewport = self.viewportRect();
    const x = std.math.clamp(clip.x, viewport.x, viewport.x + viewport.width);
    const y = std.math.clamp(clip.y, viewport.y, viewport.y + viewport.height);
    const max_x = std.math.clamp(clip.x + clip.width, viewport.x, viewport.x + viewport.width);
    const max_y = std.math.clamp(clip.y + clip.height, viewport.y, viewport.y + viewport.height);

    const width = max_x - x;
    const height = max_y - y;
    if (width <= 0 or height <= 0) return false;

    previous.* = .{ .enabled = true, .x = x, .y = y, .width = width, .height = height };
    pass.setScissorRect(@intCast(x), @intCast(y), @intCast(width), @intCast(height));
    return true;
}

fn viewportRect(self: *const WgpuBackend) struct { x: i32, y: i32, width: i32, height: i32 } {
    const width: i32 = if (self.surface.pixel_size.w <= 0) 0 else @intFromFloat(self.surface.pixel_size.w);
    const height: i32 = if (self.surface.pixel_size.h <= 0) 0 else @intFromFloat(self.surface.pixel_size.h);
    const x: i32 = if (self.surface.viewport_origin.x <= 0) 0 else @intFromFloat(self.surface.viewport_origin.x);
    const y: i32 = if (self.surface.viewport_origin.y <= 0) 0 else @intFromFloat(self.surface.viewport_origin.y);
    return .{ .x = x, .y = y, .width = width, .height = height };
}

fn computeClipRect(self: *const WgpuBackend, rect: dvui.Rect.Physical) ClipRect {
    const viewport_offset_x = self.surface.viewport_origin.x;
    const viewport_offset_y = self.surface.viewport_origin.y;
    const x0 = @floor(rect.x + viewport_offset_x);
    const y0 = @floor(rect.y + viewport_offset_y);
    const x1 = @ceil(rect.x + rect.w + viewport_offset_x);
    const y1 = @ceil(rect.y + rect.h + viewport_offset_y);
    return .{
        .enabled = true,
        .x = @intFromFloat(x0),
        .y = @intFromFloat(y0),
        .width = @intFromFloat(x1 - x0),
        .height = @intFromFloat(y1 - y0),
    };
}

fn writeBufferAligned(self: *WgpuBackend, buffer: *wgpu.Buffer, data: []const u8) !void {
    if (data.len == 0) return;

    const remainder = data.len % 4;
    const main_len = data.len - remainder;

    if (main_len > 0) {
        self.queue.writeBuffer(buffer, 0, data.ptr, main_len);
    }

    if (remainder == 0) {
        return;
    }

    var tail: [4]u8 = .{ 0, 0, 0, 0 };
    @memcpy(tail[0..remainder], data[main_len..]);
    self.queue.writeBuffer(buffer, main_len, &tail, 4);
}

fn createTextureResource(
    self: *WgpuBackend,
    width: u32,
    height: u32,
    interpolation: dvui.enums.TextureInterpolation,
    pixels: [*]const u8,
) !*TextureResource {
    try self.ensurePipeline();

    const descriptor = wgpu.TextureDescriptor{
        .label = wgpu.StringView.fromSlice("dvui texture"),
        .usage = wgpu.TextureUsages.texture_binding | wgpu.TextureUsages.copy_dst,
        .dimension = .@"2d",
        .size = .{ .width = width, .height = height, .depth_or_array_layers = 1 },
        .format = wgpu.TextureFormat.rgba8_unorm,
        .mip_level_count = 1,
        .sample_count = 1,
    };

    const texture = self.device.createTexture(&descriptor) orelse return dvui.Backend.TextureError.TextureCreate;
    errdefer texture.release();

    const texture_bytes: usize = @intCast(@as(u64, width) * @as(u64, height) * 4);
    const copy_texture = wgpu.TexelCopyTextureInfo{
        .texture = texture,
        .mip_level = 0,
        .origin = .{ .x = 0, .y = 0, .z = 0 },
        .aspect = .all,
    };
    const layout = wgpu.TexelCopyBufferLayout{
        .offset = 0,
        .bytes_per_row = width * 4,
        .rows_per_image = height,
    };
    self.queue.writeTexture(
        &copy_texture,
        pixels,
        texture_bytes,
        &layout,
        &descriptor.size,
    );

    const sampler = self.device.createSampler(&wgpu.SamplerDescriptor{
        .label = wgpu.StringView.fromSlice("dvui sampler"),
        .min_filter = if (interpolation == .linear) .linear else .nearest,
        .mag_filter = if (interpolation == .linear) .linear else .nearest,
        .mipmap_filter = .nearest,
        .address_mode_u = .clamp_to_edge,
        .address_mode_v = .clamp_to_edge,
        .address_mode_w = .clamp_to_edge,
    }) orelse return dvui.Backend.TextureError.TextureCreate;
    errdefer sampler.release();

    const view = texture.createView(&wgpu.TextureViewDescriptor{}) orelse return dvui.Backend.TextureError.TextureCreate;
    errdefer view.release();

    const bind_group = self.device.createBindGroup(&wgpu.BindGroupDescriptor{
        .label = wgpu.StringView.fromSlice("dvui texture"),
        .layout = self.texture_bind_group_layout.?,
        .entry_count = 2,
        .entries = &[_]wgpu.BindGroupEntry{
            .{ .binding = 0, .sampler = sampler },
            .{ .binding = 1, .texture_view = view },
        },
    }) orelse return dvui.Backend.TextureError.TextureCreate;
    errdefer bind_group.release();

    const resource = try self.gpa.create(TextureResource);
    resource.* = .{
        .texture = texture,
        .view = view,
        .sampler = sampler,
        .bind_group = bind_group,
        .interpolation = interpolation,
    };

    return resource;
}

fn createSolidTexture(
    self: *WgpuBackend,
    interpolation: dvui.enums.TextureInterpolation,
    color: u32,
) !*TextureResource {
    var pixel: [4]u8 = .{
        @intCast((color >> 24) & 0xFF),
        @intCast((color >> 16) & 0xFF),
        @intCast((color >> 8) & 0xFF),
        @intCast(color & 0xFF),
    };
    return try self.createTextureResource(1, 1, interpolation, &pixel);
}

const shader_source =
    \\struct Globals {
    \\    surface_size: vec2<f32>,
    \\    viewport_origin: vec2<f32>,
    \\};
    \\
    \\@group(0) @binding(0) var<uniform> globals: Globals;
    \\@group(1) @binding(0) var ui_sampler: sampler;
    \\@group(1) @binding(1) var ui_texture: texture_2d<f32>;
    \\
    \\struct VSIn {
    \\    @location(0) position: vec2<f32>,
    \\    @location(1) uv: vec2<f32>,
    \\    @location(2) color: vec4<f32>,
    \\};
    \\
    \\struct VSOut {
    \\    @builtin(position) clip_position: vec4<f32>,
    \\    @location(0) uv: vec2<f32>,
    \\    @location(1) color: vec4<f32>,
    \\};
    \\
    \\@vertex
    \\fn vs_main(input: VSIn) -> VSOut {
    \\    var out: VSOut;
    \\    let pixel = input.position + globals.viewport_origin;
    \\    let surface = globals.surface_size;
    \\    let ndc = vec2<f32>(
    \\        (pixel.x / surface.x) * 2.0 - 1.0,
    \\        1.0 - (pixel.y / surface.y) * 2.0,
    \\    );
    \\    out.clip_position = vec4<f32>(ndc, 0.0, 1.0);
    \\    out.uv = input.uv;
    \\    out.color = input.color;
    \\    return out;
    \\}
    \\
    \\@fragment
    \\fn fs_main(input: VSOut) -> @location(0) vec4<f32> {
    \\    let sampled = textureSample(ui_texture, ui_sampler, input.uv);
    \\    return sampled * input.color;
    \\}
;
