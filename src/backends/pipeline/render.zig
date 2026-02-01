const wgpu = @import("wgpu");

const buffers = @import("buffers.zig");
const depth = @import("depth.zig");
const geometry = @import("geometry.zig");
const types = @import("types.zig");

pub const Resources = @This();

shader_module: *wgpu.ShaderModule,
pipeline_layout: *wgpu.PipelineLayout,
pipeline: *wgpu.RenderPipeline,
view_bind_group_layout: *wgpu.BindGroupLayout,
render_bind_group_layout: *wgpu.BindGroupLayout,
view_bind_group: *wgpu.BindGroup,
render_bind_group: *wgpu.BindGroup,

pub fn init(
    self: *Resources,
    device: *wgpu.Device,
    format: wgpu.TextureFormat,
    vertex_attributes: [2]wgpu.VertexAttribute,
    res: *const buffers.Resources,
    texture_view: *wgpu.TextureView,
    sampler: *wgpu.Sampler,
) !void {
    const shader_module = device.createShaderModule(&wgpu.shaderModuleWGSLDescriptor(.{
        .label = "Particles GPU render shader",
        .code = @embedFile("../resources/shaders/particles_gpu_render.wgsl"),
    })).?;
    errdefer shader_module.release();

    const view_bgl = device.createBindGroupLayout(&wgpu.BindGroupLayoutDescriptor{
        .label = wgpu.StringView.fromSlice("Particles view BGL"),
        .entry_count = 1,
        .entries = &[_]wgpu.BindGroupLayoutEntry{
            .{
                .binding = 0,
                .visibility = wgpu.ShaderStages.vertex,
                .buffer = wgpu.BufferBindingLayout{
                    .type = wgpu.BufferBindingType.uniform,
                    .has_dynamic_offset = @intFromBool(false),
                    .min_binding_size = @sizeOf(types.ViewUniforms),
                },
            },
        },
    }).?;
    errdefer view_bgl.release();

    const render_bgl = device.createBindGroupLayout(&wgpu.BindGroupLayoutDescriptor{
        .label = wgpu.StringView.fromSlice("Particles render BGL"),
        .entry_count = 4,
        .entries = &[_]wgpu.BindGroupLayoutEntry{
            .{
                .binding = 0,
                .visibility = wgpu.ShaderStages.vertex,
                .buffer = wgpu.BufferBindingLayout{
                    .type = wgpu.BufferBindingType.read_only_storage,
                    .has_dynamic_offset = @intFromBool(false),
                    .min_binding_size = res.particle_stride * @as(u64, @intCast(res.total_capacity)),
                },
            },
            .{
                .binding = 1,
                .visibility = wgpu.ShaderStages.vertex,
                .buffer = wgpu.BufferBindingLayout{
                    .type = wgpu.BufferBindingType.read_only_storage,
                    .has_dynamic_offset = @intFromBool(false),
                    .min_binding_size = @as(u64, @intCast(res.total_capacity)) * @sizeOf(u32),
                },
            },
            .{
                .binding = 2,
                .visibility = wgpu.ShaderStages.fragment,
                .texture = wgpu.TextureBindingLayout{
                    .sample_type = .float,
                    .view_dimension = .@"2d",
                },
            },
            .{
                .binding = 3,
                .visibility = wgpu.ShaderStages.fragment,
                .sampler = wgpu.SamplerBindingLayout{ .type = .filtering },
            },
        },
    }).?;
    errdefer render_bgl.release();

    const pipeline_layout = device.createPipelineLayout(&wgpu.PipelineLayoutDescriptor{
        .label = wgpu.StringView.fromSlice("Particles render layout"),
        .bind_group_layout_count = 2,
        .bind_group_layouts = &[_]*wgpu.BindGroupLayout{ view_bgl, render_bgl },
    }).?;
    errdefer pipeline_layout.release();

    const vertex_buffer_layout = wgpu.VertexBufferLayout{
        .array_stride = @sizeOf(geometry.VertexAttributes),
        .step_mode = wgpu.VertexStepMode.vertex,
        .attribute_count = vertex_attributes.len,
        .attributes = &vertex_attributes,
    };
    const buffers_desc = &[_]wgpu.VertexBufferLayout{vertex_buffer_layout};

    const color_targets = &[_]wgpu.ColorTargetState{
        wgpu.ColorTargetState{
            .format = format,
            .blend = &wgpu.BlendState{
                .color = wgpu.BlendComponent{ .operation = .add, .src_factor = .src_alpha, .dst_factor = .one },
                .alpha = wgpu.BlendComponent{ .operation = .add, .src_factor = .src_alpha, .dst_factor = .one },
            },
        },
    };

    const pipeline = device.createRenderPipeline(&wgpu.RenderPipelineDescriptor{
        .vertex = wgpu.VertexState{
            .module = shader_module,
            .entry_point = wgpu.StringView.fromSlice("vs_main"),
            .buffer_count = buffers_desc.len,
            .buffers = buffers_desc.ptr,
        },
        .layout = pipeline_layout,
        .primitive = wgpu.PrimitiveState{},
        .fragment = &wgpu.FragmentState{
            .module = shader_module,
            .entry_point = wgpu.StringView.fromSlice("fs_main"),
            .target_count = color_targets.len,
            .targets = color_targets.ptr,
        },
        .depth_stencil = &wgpu.DepthStencilState{
            .format = depth.format,
            .depth_write_enabled = .false,
            .depth_compare = .less_equal,
            .stencil_front = wgpu.StencilFaceState{
                .compare = .always,
                .fail_op = .keep,
                .depth_fail_op = .keep,
                .pass_op = .keep,
            },
            .stencil_back = wgpu.StencilFaceState{
                .compare = .always,
                .fail_op = .keep,
                .depth_fail_op = .keep,
                .pass_op = .keep,
            },
            .stencil_read_mask = 0,
            .stencil_write_mask = 0,
            .depth_bias = 0,
            .depth_bias_slope_scale = 0.0,
            .depth_bias_clamp = 0.0,
        },
        .multisample = wgpu.MultisampleState{},
    }).?;
    errdefer pipeline.release();

    const view_bind_group = device.createBindGroup(&wgpu.BindGroupDescriptor{
        .label = wgpu.StringView.fromSlice("Particles view BG"),
        .layout = view_bgl,
        .entry_count = 1,
        .entries = &[_]wgpu.BindGroupEntry{
            .{ .binding = 0, .buffer = res.view, .offset = 0, .size = @sizeOf(types.ViewUniforms) },
        },
    }).?;
    errdefer view_bind_group.release();

    const render_bind_group = device.createBindGroup(&wgpu.BindGroupDescriptor{
        .label = wgpu.StringView.fromSlice("Particles render BG"),
        .layout = render_bgl,
        .entry_count = 4,
        .entries = &[_]wgpu.BindGroupEntry{
            .{ .binding = 0, .buffer = res.particles, .offset = 0, .size = res.particle_stride * @as(u64, @intCast(res.total_capacity)) },
            .{ .binding = 1, .buffer = res.alive_list, .offset = 0, .size = @as(u64, @intCast(res.total_capacity)) * @sizeOf(u32) },
            .{ .binding = 2, .texture_view = texture_view },
            .{ .binding = 3, .sampler = sampler },
        },
    }).?;
    errdefer render_bind_group.release();

    self.shader_module = shader_module;
    self.pipeline_layout = pipeline_layout;
    self.pipeline = pipeline;
    self.view_bind_group_layout = view_bgl;
    self.render_bind_group_layout = render_bgl;
    self.view_bind_group = view_bind_group;
    self.render_bind_group = render_bind_group;
}

/// Initialize the render pipeline layout and resources without creating any bind groups.
/// Use this when textures will be loaded dynamically later.
pub fn initLayoutOnly(
    self: *Resources,
    device: *wgpu.Device,
    format: wgpu.TextureFormat,
    vertex_attributes: [2]wgpu.VertexAttribute,
    res: *const buffers.Resources,
) !void {
    const shader_module = device.createShaderModule(&wgpu.shaderModuleWGSLDescriptor(.{
        .label = "Particles GPU render shader",
        .code = @embedFile("../resources/shaders/particles_gpu_render.wgsl"),
    })).?;
    errdefer shader_module.release();

    const view_bgl = device.createBindGroupLayout(&wgpu.BindGroupLayoutDescriptor{
        .label = wgpu.StringView.fromSlice("Particles view BGL"),
        .entry_count = 1,
        .entries = &[_]wgpu.BindGroupLayoutEntry{
            .{
                .binding = 0,
                .visibility = wgpu.ShaderStages.vertex,
                .buffer = wgpu.BufferBindingLayout{
                    .type = wgpu.BufferBindingType.uniform,
                    .has_dynamic_offset = @intFromBool(false),
                    .min_binding_size = @sizeOf(types.ViewUniforms),
                },
            },
        },
    }).?;
    errdefer view_bgl.release();

    const render_bgl = device.createBindGroupLayout(&wgpu.BindGroupLayoutDescriptor{
        .label = wgpu.StringView.fromSlice("Particles render BGL"),
        .entry_count = 4,
        .entries = &[_]wgpu.BindGroupLayoutEntry{
            .{
                .binding = 0,
                .visibility = wgpu.ShaderStages.vertex,
                .buffer = wgpu.BufferBindingLayout{
                    .type = wgpu.BufferBindingType.read_only_storage,
                    .has_dynamic_offset = @intFromBool(false),
                    .min_binding_size = res.particle_stride * @as(u64, @intCast(res.total_capacity)),
                },
            },
            .{
                .binding = 1,
                .visibility = wgpu.ShaderStages.vertex,
                .buffer = wgpu.BufferBindingLayout{
                    .type = wgpu.BufferBindingType.read_only_storage,
                    .has_dynamic_offset = @intFromBool(false),
                    .min_binding_size = @as(u64, @intCast(res.total_capacity)) * @sizeOf(u32),
                },
            },
            .{
                .binding = 2,
                .visibility = wgpu.ShaderStages.fragment,
                .texture = wgpu.TextureBindingLayout{
                    .sample_type = .float,
                    .view_dimension = .@"2d",
                },
            },
            .{
                .binding = 3,
                .visibility = wgpu.ShaderStages.fragment,
                .sampler = wgpu.SamplerBindingLayout{ .type = .filtering },
            },
        },
    }).?;
    errdefer render_bgl.release();

    const pipeline_layout = device.createPipelineLayout(&wgpu.PipelineLayoutDescriptor{
        .label = wgpu.StringView.fromSlice("Particles render layout"),
        .bind_group_layout_count = 2,
        .bind_group_layouts = &[_]*wgpu.BindGroupLayout{ view_bgl, render_bgl },
    }).?;
    errdefer pipeline_layout.release();

    const vertex_buffer_layout = wgpu.VertexBufferLayout{
        .array_stride = @sizeOf(geometry.VertexAttributes),
        .step_mode = wgpu.VertexStepMode.vertex,
        .attribute_count = vertex_attributes.len,
        .attributes = &vertex_attributes,
    };
    const buffers_desc = &[_]wgpu.VertexBufferLayout{vertex_buffer_layout};

    const color_targets = &[_]wgpu.ColorTargetState{
        wgpu.ColorTargetState{
            .format = format,
            .blend = &wgpu.BlendState{
                .color = wgpu.BlendComponent{ .operation = .add, .src_factor = .src_alpha, .dst_factor = .one },
                .alpha = wgpu.BlendComponent{ .operation = .add, .src_factor = .src_alpha, .dst_factor = .one },
            },
        },
    };

    const pipeline = device.createRenderPipeline(&wgpu.RenderPipelineDescriptor{
        .vertex = wgpu.VertexState{
            .module = shader_module,
            .entry_point = wgpu.StringView.fromSlice("vs_main"),
            .buffer_count = buffers_desc.len,
            .buffers = buffers_desc.ptr,
        },
        .layout = pipeline_layout,
        .primitive = wgpu.PrimitiveState{},
        .fragment = &wgpu.FragmentState{
            .module = shader_module,
            .entry_point = wgpu.StringView.fromSlice("fs_main"),
            .target_count = color_targets.len,
            .targets = color_targets.ptr,
        },
        .depth_stencil = &wgpu.DepthStencilState{
            .format = depth.format,
            .depth_write_enabled = .false,
            .depth_compare = .less_equal,
            .stencil_front = wgpu.StencilFaceState{
                .compare = .always,
                .fail_op = .keep,
                .depth_fail_op = .keep,
                .pass_op = .keep,
            },
            .stencil_back = wgpu.StencilFaceState{
                .compare = .always,
                .fail_op = .keep,
                .depth_fail_op = .keep,
                .pass_op = .keep,
            },
            .stencil_read_mask = 0,
            .stencil_write_mask = 0,
            .depth_bias = 0,
            .depth_bias_slope_scale = 0.0,
            .depth_bias_clamp = 0.0,
        },
        .multisample = wgpu.MultisampleState{},
    }).?;
    errdefer pipeline.release();

    const view_bind_group = device.createBindGroup(&wgpu.BindGroupDescriptor{
        .label = wgpu.StringView.fromSlice("Particles view BG"),
        .layout = view_bgl,
        .entry_count = 1,
        .entries = &[_]wgpu.BindGroupEntry{
            .{ .binding = 0, .buffer = res.view, .offset = 0, .size = @sizeOf(types.ViewUniforms) },
        },
    }).?;
    errdefer view_bind_group.release();

    self.shader_module = shader_module;
    self.pipeline_layout = pipeline_layout;
    self.pipeline = pipeline;
    self.view_bind_group_layout = view_bgl;
    self.render_bind_group_layout = render_bgl;
    self.view_bind_group = view_bind_group;
    // Note: render_bind_group is not created here - it will be created per-texture
    self.render_bind_group = undefined;
}

pub fn deinitLayoutOnly(self: *Resources) void {
    // Same as deinit but skips render_bind_group since it wasn't created
    self.view_bind_group.release();
    self.pipeline.release();
    self.pipeline_layout.release();
    self.render_bind_group_layout.release();
    self.view_bind_group_layout.release();
    self.shader_module.release();
}

pub fn deinit(self: *Resources) void {
    self.render_bind_group.release();
    self.view_bind_group.release();
    self.pipeline.release();
    self.pipeline_layout.release();
    self.render_bind_group_layout.release();
    self.view_bind_group_layout.release();
    self.shader_module.release();
}
