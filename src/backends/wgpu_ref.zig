const std = @import("std");
const wgpu = @import("wgpu");

pub const RenderContext = struct {
    instance: *wgpu.Instance,
    adapter: *wgpu.Adapter,
    device: *wgpu.Device,
    queue: *wgpu.Queue,
    target_texture: *wgpu.Texture,
    target_texture_view: *wgpu.TextureView,
    shader_module: *wgpu.ShaderModule,

    staging_buffer: *wgpu.Buffer,
    point_buffer: *wgpu.Buffer,
    index_buffer: *wgpu.Buffer,
    uniform_buffer: *wgpu.Buffer,

    surface: *wgpu.Surface,
    pipeline: *wgpu.RenderPipeline,
    bind_group_layout: *wgpu.BindGroupLayout,
    layout: *wgpu.PipelineLayout,
    bind_group: *wgpu.BindGroup,
    width: u32,
    height: u32,
    pixel_buffer: []u8,
    allocator: std.mem.Allocator,
    needs_reconfigure: bool = true,
    start_time: u64,

    vertexData: []f32,
    indexData: []u16,
    indexCount: u32,
    vertexCount: u32,

    pub fn deinit(self: *const RenderContext) void {
        self.instance.release();
        self.adapter.release();
        self.device.release();
        self.queue.release();
        self.target_texture.release();
        self.target_texture_view.release();
        self.shader_module.release();

        // Buffers
        self.staging_buffer.release();
        self.point_buffer.release();
        self.index_buffer.release();
        self.uniform_buffer.release();

        self.surface.release();
        self.pipeline.release();
        self.bind_group_layout.release();
        self.layout.release();
        self.bind_group.release();

        self.allocator.free(self.pixel_buffer);
    }

    pub fn reconfigure(self: *RenderContext, new_width: u32, new_height: u32) void {
        if (self.width == new_width and self.height == new_height and !self.needs_reconfigure) {
            return;
        }

        const swap_chain_format = wgpu.TextureFormat.bgra8_unorm_srgb;
        self.surface.configure(&wgpu.SurfaceConfiguration{
            .device = self.device,
            .format = swap_chain_format,
            .usage = wgpu.TextureUsages.render_attachment,
            .width = new_width,
            .height = new_height,
            .alpha_mode = wgpu.CompositeAlphaMode.auto,
            .present_mode = wgpu.PresentMode.mailbox,
        });
        self.width = new_width;
        self.height = new_height;
        self.needs_reconfigure = false;
    }
};


fn handleBufferMap(status: wgpu.MapAsyncStatus, _: wgpu.StringView, userdata1: ?*anyopaque, _: ?*anyopaque) callconv(.c) void {
    std.debug.print("buffer map status: {any}\n", .{status});
    if (status != .success) {
        std.debug.print("failed to map buffer: {any}\n", .{status});
        return;
    }
    const complete: *bool = @ptrCast(@alignCast(userdata1));
    complete.* = true;
}

const numbers_size = 16;

fn getRequiredLimits(adapter: *wgpu.Adapter) !wgpu.Limits {
    var supportedLimits = std.mem.zeroes(wgpu.Limits);
    const supportedLimits_status = adapter.getLimits(&supportedLimits);
    if (supportedLimits_status != .success) {
        std.debug.print("failed to get supported limits: {any}\n", .{supportedLimits_status});
        return error.FailedToGetSupportedLimits;
    }
    std.debug.print("Adapter supported limits:\n", .{});
    std.debug.print(" - maxTextureDimension1D: {}\n", .{supportedLimits.max_texture_dimension_1d});
    std.debug.print(" - maxTextureDimension2D: {}\n", .{supportedLimits.max_texture_dimension_2d});
    std.debug.print(" - maxTextureDimension3D: {}\n", .{supportedLimits.max_texture_dimension_3d});
    std.debug.print(" - maxTextureArrayLayers: {}\n", .{supportedLimits.max_texture_array_layers});

    var requiredLimits = wgpu.Limits{};
    // Vertex attributes count
    requiredLimits.max_vertex_attributes = 2;
    // Maximum number of vertex buffers
    requiredLimits.max_vertex_buffers = 1;
    // Maximum size of a buffer is 6 vertices of 2 float each
    requiredLimits.max_buffer_size = 200 * 5 * @sizeOf(f32);
    // Maximum stride between 2 consecutive vertices in the vertex buffer
    requiredLimits.max_vertex_buffer_array_stride = 6 * @sizeOf(f32);
    // There is a maximum of 3 float forwarded from vertex to fragment shader
    requiredLimits.max_inter_stage_shader_variables = 3;

    // We use at most 1 bind group for now
    requiredLimits.max_bind_groups = 1;
    // We use at most 1 uniform buffer per stage
    requiredLimits.max_uniform_buffers_per_shader_stage = 1;
    // Uniform structs have a size of maximum 16 float (more than what we need)
    requiredLimits.max_uniform_buffer_binding_size = 16 * 4;

    // These two limits are different because they are "minimum" limits,
    // they are the only ones we may forward from the adapter's supported
    // limits.
    requiredLimits.min_uniform_buffer_offset_alignment = supportedLimits.min_uniform_buffer_offset_alignment;
    requiredLimits.min_storage_buffer_offset_alignment = supportedLimits.min_storage_buffer_offset_alignment;

    return requiredLimits;
}

// Based off of headless triangle example from https://github.com/eliemichel/LearnWebGPU-Code/tree/step030-headless

pub fn init(surface_descriptor: wgpu.SurfaceDescriptor, width: u32, height: u32, allocator: std.mem.Allocator) !renderer.RenderContext {
    const geometryData = try load3d.loadGeometry(allocator);

    const vertexData = geometryData.pointData;
    const indexData = geometryData.indexData;
    const indexCount = @as(u32, @intCast(indexData.len));
    const vertexCount = @as(u32, @intCast(vertexData.len / 5));

    const output_extent = wgpu.Extent3D{
        .width = width,
        .height = height,
        .depth_or_array_layers = 1,
    };
    const output_bytes_per_row = 4 * output_extent.width;
    const output_size = output_bytes_per_row * output_extent.height;

    const pixel_buffer = try allocator.alloc(u8, output_size);
    errdefer allocator.free(pixel_buffer);

    const instance = wgpu.Instance.create(null).?;
    errdefer instance.release();

    const surface = instance.createSurface(&surface_descriptor).?;
    errdefer surface.release();

    const adapter_request = instance.requestAdapterSync(&wgpu.RequestAdapterOptions{
        .compatible_surface = surface,
        .power_preference = wgpu.PowerPreference.undefined,
        .force_fallback_adapter = @intFromBool(false),
    }, 0);
    const adapter = switch (adapter_request.status) {
        .success => adapter_request.adapter.?,
        else => return error.NoAdapter,
    };
    errdefer adapter.release();

    var caps = std.mem.zeroes(wgpu.SurfaceCapabilities);
    const surface_caps = surface.getCapabilities(adapter, &caps);
    if (surface_caps != .success) {
        std.debug.print("failed to get surface capabilities: {any}\n", .{surface_caps});
        return error.FailedToGetSurfaceCapabilities;
    }
    defer caps.freeMembers();
    std.debug.print("surface capabilities: {any}\n", .{caps});

    var props = std.mem.zeroes(wgpu.AdapterInfo);
    const status = adapter.getInfo(&props);
    if (status != .success) {
        std.debug.print("failed to get adapter info: {any}\n", .{status});
        return error.FailedToGetAdapterInfo;
    }
    std.debug.print("found {s} backend on {s} adapter: {s}, {s}\n", .{
        @tagName(props.backend_type),
        @tagName(props.adapter_type),
        props.device.toSlice() orelse "unknown",
        props.description.toSlice() orelse "unknown",
    });
    defer props.freeMembers();

    const limits = try getRequiredLimits(adapter);

    const device_request = adapter.requestDeviceSync(instance, &wgpu.DeviceDescriptor{
        .label = myDeviceLabel,
        .required_limits = &limits,
    }, 0);
    const device = switch (device_request.status) {
        .success => device_request.device.?,
        else => return error.NoDevice,
    };
    errdefer device.release();

    const queue = device.getQueue().?;

    const swap_chain_format = wgpu.TextureFormat.bgra8_unorm_srgb;

    // Configure the surface for presentation
    surface.configure(&wgpu.SurfaceConfiguration{
        .device = device,
        .format = swap_chain_format,
        .usage = wgpu.TextureUsages.render_attachment,
        .width = width,
        .height = height,
        .alpha_mode = wgpu.CompositeAlphaMode.auto,
        .present_mode = wgpu.PresentMode.fifo,
    });

    const target_texture = device.createTexture(&wgpu.TextureDescriptor{
        .label = wgpu.StringView.fromSlice("Render texture"),
        .size = output_extent,
        .format = swap_chain_format,
        .usage = wgpu.TextureUsages.render_attachment | wgpu.TextureUsages.copy_src,
    }).?;
    errdefer target_texture.release();

    const target_texture_view = target_texture.createView(&wgpu.TextureViewDescriptor{
        .label = wgpu.StringView.fromSlice("Render texture view"),
        .mip_level_count = 1,
        .array_layer_count = 1,
    }).?;
    errdefer target_texture_view.release();

    const shader_module = device.createShaderModule(&wgpu.shaderModuleWGSLDescriptor(.{
        .code = @embedFile("./shaders/shader.wgsl"),
    })).?;
    errdefer shader_module.release();

    const point_buffer_desc = &wgpu.BufferDescriptor{
        .label = wgpu.StringView.fromSlice("Point buffer"),
        .usage = wgpu.BufferUsages.copy_dst | wgpu.BufferUsages.vertex,
        .size = ((vertexData.len * @sizeOf(f32)) + 3) & ~@as(u64, 3),
        .mapped_at_creation = @as(u32, @intFromBool(false)),
    };
    const point_buffer = device.createBuffer(point_buffer_desc).?;
    errdefer point_buffer.release();

    queue.writeBuffer(point_buffer, 0, vertexData.ptr, point_buffer_desc.size);

    const index_buffer_desc = &wgpu.BufferDescriptor{
        .label = wgpu.StringView.fromSlice("Index buffer"),
        .usage = wgpu.BufferUsages.copy_dst | wgpu.BufferUsages.index,
        .size = ((indexData.len * @sizeOf(u16)) + 3) & ~@as(u64, 3),
        .mapped_at_creation = @as(u32, @intFromBool(false)),
    };
    const index_buffer = device.createBuffer(index_buffer_desc).?;
    errdefer index_buffer.release();

    queue.writeBuffer(index_buffer, 0, indexData.ptr, index_buffer_desc.size);

    const buffer_desc = &wgpu.BufferDescriptor{
        .label = wgpu.StringView.fromSlice("GPU-side buffer"),
        .usage = wgpu.BufferUsages.copy_src | wgpu.BufferUsages.copy_dst,
        .size = numbers_size,
        .mapped_at_creation = @as(u32, @intFromBool(false)),
    };
    const buffer1 = device.createBuffer(buffer_desc).?;
    errdefer buffer1.release();

    const uniform_buffer_size = @sizeOf(f32) + 3 * @sizeOf(f32); // The required alignment is min 16 bytes

    const uniform_buffer_desc = &wgpu.BufferDescriptor{
        .label = wgpu.StringView.fromSlice("Uniform buffer"),
        .usage = wgpu.BufferUsages.copy_dst | wgpu.BufferUsages.uniform,
        .size = uniform_buffer_size,
        .mapped_at_creation = @as(u32, @intFromBool(false)),
    };
    const uniform_buffer = device.createBuffer(uniform_buffer_desc).?;
    errdefer uniform_buffer.release();

    var currentTime: f32 = @as(f32, @floatFromInt(std.time.timestamp()));

    queue.writeBuffer(uniform_buffer, 0, &currentTime, @sizeOf(f32));

    const color_targets = &[_]wgpu.ColorTargetState{
        wgpu.ColorTargetState{
            .format = swap_chain_format,
            .blend = &wgpu.BlendState{
                .color = wgpu.BlendComponent{
                    .operation = .add,
                    .src_factor = .src_alpha,
                    .dst_factor = .one_minus_src_alpha,
                },
                .alpha = wgpu.BlendComponent{
                    .operation = .add,
                    .src_factor = .zero,
                    .dst_factor = .one,
                },
            },
        },
    };

    const vertexBufferLayout = wgpu.VertexBufferLayout{
        .array_stride = 6 * @sizeOf(f32),
        .step_mode = wgpu.VertexStepMode.vertex,
        .attribute_count = 2,
        .attributes = &[_]wgpu.VertexAttribute{
            wgpu.VertexAttribute{
                .format = wgpu.VertexFormat.float32x3,
                .offset = 0,
                .shader_location = 0,
            },
            wgpu.VertexAttribute{
                .format = wgpu.VertexFormat.float32x3,
                .offset = 3 * @sizeOf(f32), // In bytes
                .shader_location = 1,
            },
        },
    };

    const buffers = &[_]wgpu.VertexBufferLayout{
        vertexBufferLayout,
    };

    const bind_group_layout = device.createBindGroupLayout(&wgpu.BindGroupLayoutDescriptor{
        .label = wgpu.StringView.fromSlice("Uniform bind group layout"),
        .entry_count = 1,
        .entries = &[_]wgpu.BindGroupLayoutEntry{
            wgpu.BindGroupLayoutEntry{
                .binding = 0,
                .visibility = wgpu.ShaderStages.vertex,
                .buffer = wgpu.BufferBindingLayout{
                    .type = wgpu.BufferBindingType.uniform,
                    .min_binding_size = uniform_buffer_size,
                },
            },
        },
    }).?;
    errdefer bind_group_layout.release();

    const binding = device.createBindGroup(&wgpu.BindGroupDescriptor{
        .label = wgpu.StringView.fromSlice("Uniform bind group"),
        .layout = bind_group_layout,
        .entry_count = 1,
        .entries = &[_]wgpu.BindGroupEntry{
            wgpu.BindGroupEntry{
                .binding = 0,
                .buffer = uniform_buffer,
                .offset = 0,
                .size = uniform_buffer_size,
            },
        },
    }).?;
    errdefer binding.release();

    const layout = device.createPipelineLayout(&wgpu.PipelineLayoutDescriptor{
        .label = wgpu.StringView.fromSlice("Pipeline layout"),
        .bind_group_layout_count = 1,
        .bind_group_layouts = &[_]*wgpu.BindGroupLayout{bind_group_layout},
    }).?;
    errdefer layout.release();

    const pipeline = device.createRenderPipeline(&wgpu.RenderPipelineDescriptor{
        .vertex = wgpu.VertexState{
            .module = shader_module,
            .entry_point = wgpu.StringView.fromSlice("vs_main"),
            .buffer_count = 1,
            .buffers = buffers,
        },
        .layout = layout,
        .primitive = wgpu.PrimitiveState{},
        .fragment = &wgpu.FragmentState{
            .module = shader_module,
            .entry_point = wgpu.StringView.fromSlice("fs_main"),
            .target_count = color_targets.len,
            .targets = color_targets.ptr,
        },
        .multisample = wgpu.MultisampleState{},
    }).?;
    errdefer pipeline.release();

    return renderer.RenderContext{
        .instance = instance,
        .adapter = adapter,
        .device = device,
        .queue = queue,

        .target_texture = target_texture,
        .target_texture_view = target_texture_view,
        .surface = surface,
        .shader_module = shader_module,

        .staging_buffer = buffer1,
        .point_buffer = point_buffer,
        .index_buffer = index_buffer,
        .uniform_buffer = uniform_buffer,

        .pipeline = pipeline,
        .bind_group_layout = bind_group_layout,
        .layout = layout,
        .bind_group = binding,
        .width = width,
        .height = height,
        .pixel_buffer = pixel_buffer,
        .allocator = allocator,
        .start_time = nanoTimestamp(),

        .vertexData = vertexData,
        .indexData = indexData,
        .indexCount = indexCount,
        .vertexCount = vertexCount,
        .geometryData = geometryData,
    };
}

pub fn getNextSurfaceViewData(ctx: *renderer.RenderContext) !renderer.SurfaceFrame {
    var surface_texture: wgpu.SurfaceTexture = undefined;
    ctx.surface.getCurrentTexture(&surface_texture);

    const maybe_texture = surface_texture.texture;
    const status = surface_texture.status;

    const texture = texture: {
        switch (status) {
            .success_optimal => {},
            .success_suboptimal => {
                ctx.needs_reconfigure = true;
            },
            .timeout => {
                if (maybe_texture) |tex| tex.release();
                return error.SurfaceTimeout;
            },
            .outdated => {
                ctx.needs_reconfigure = true;
                if (maybe_texture) |tex| tex.release();
                return error.SurfaceOutdated;
            },
            .lost => {
                ctx.needs_reconfigure = true;
                if (maybe_texture) |tex| tex.release();
                return error.SurfaceLost;
            },
            .out_of_memory => {
                if (maybe_texture) |tex| tex.release();
                return error.SurfaceOutOfMemory;
            },
            .device_lost => {
                if (maybe_texture) |tex| tex.release();
                return error.SurfaceDeviceLost;
            },
            .@"error" => {
                if (maybe_texture) |tex| tex.release();
                return error.SurfaceTextureError;
            },
        }

        if (maybe_texture) |tex| break :texture tex;
        return error.SurfaceTextureUnavailable;
    };

    const view = texture.createView(&wgpu.TextureViewDescriptor{
        .label = surfaceTextureLabel,
        .mip_level_count = 1,
        .array_layer_count = 1,
    }) orelse {
        texture.release();
        return error.SurfaceViewCreationFailed;
    };

    return renderer.SurfaceFrame{
        .texture = texture,
        .view = view,
        .status = status,
    };
}

pub fn render(ctx: *renderer.RenderContext, resized: bool) !void {
    if (resized) {
        ctx.needs_reconfigure = true;
    }
    if (ctx.needs_reconfigure) {
        ctx.reconfigure(ctx.width, ctx.height);
    }

    var currentTime: f32 = @as(f32, @floatFromInt(nanoTimestamp() - ctx.start_time)) / 1_000_000_000.0;
    ctx.queue.writeBuffer(ctx.uniform_buffer, 0, &currentTime, @sizeOf(f32));

    const frame = getNextSurfaceViewData(ctx) catch |err| {
        switch (err) {
            error.SurfaceOutdated, error.SurfaceLost, error.SurfaceTextureUnavailable => {
                ctx.needs_reconfigure = true;
                ctx.reconfigure(ctx.width, ctx.height);
            },
            error.SurfaceTimeout => {},
            else => {},
        }
        std.debug.print("failed to acquire surface frame: {any}\n", .{err});
        return;
    };
    defer frame.texture.release();
    defer frame.view.release();

    const encoder = ctx.device.createCommandEncoder(&wgpu.CommandEncoderDescriptor{
        .label = renderEncoderLabel,
    }).?;
    defer encoder.release();

    const color_attachments = &[_]wgpu.ColorAttachment{wgpu.ColorAttachment{
        .view = frame.view,
        // The loadOp setting indicates the load operation to perform on the view prior to executing the render pass.
        // It can be either read from the view or set to a default uniform color, namely the clear value.
        // When it does not matter, use WGPULoadOp_Clear as it is likely more efficient.
        .load_op = .clear,
        // The storeOp indicates the operation to perform on view after executing the render pass.
        // It can be either stored or discarded (the latter only makes sense if the render pass has side-effects).
        // The default is WGPUStoreOp_Store.
        .store_op = .store,
        .clear_value = wgpu.Color{ .r = 0.125, .g = 0.125, .b = 0.125, .a = 1.0 },
    }};
    const render_pass = encoder.beginRenderPass(&wgpu.RenderPassDescriptor{
        .color_attachment_count = color_attachments.len,
        .color_attachments = color_attachments.ptr,
        .depth_stencil_attachment = null,
    }).?;

    render_pass.setPipeline(ctx.pipeline);

    // Set both vertex and index buffers
    render_pass.setVertexBuffer(0, ctx.point_buffer, 0, ctx.point_buffer.getSize());
    // The second argument must correspond to the choice of uint16_t or uint32_t
    // we've done when creating the index buffer.
    render_pass.setIndexBuffer(ctx.index_buffer, wgpu.IndexFormat.uint16, 0, ctx.index_buffer.getSize());

    // Set binding group here!
    render_pass.setBindGroup(0, ctx.bind_group, 0, null);

    // Replace `draw()` with `drawIndexed()` and `vertexCount` with `indexCount`
    // The extra argument is an offset within the index buffer.
    render_pass.drawIndexed(ctx.indexCount, 1, 0, 0, 0);

    render_pass.end();

    // The render pass has to be released after .end() or otherwise we'll crash on queue.submit
    // https://github.com/gfx-rs/wgpu-native/issues/412#issuecomment-2311719154
    render_pass.release();

    const command_buffer_desc = wgpu.CommandBufferDescriptor{
        .label = commandBufferLabel,
    };
    const command_buffer = encoder.finish(&command_buffer_desc).?;
    defer command_buffer.release();

    const command_buffers = &[_]*const wgpu.CommandBuffer{command_buffer};
    ctx.queue.submit(command_buffers);

    const status = ctx.surface.present();
    if (status != .success) {
        std.debug.print("failed to present: {s}\n", .{@tagName(status)});
        return error.FailedToPresent;
    }
}
