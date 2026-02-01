const wgpu = @import("wgpu");

const buffers = @import("buffers.zig");
const types = @import("types.zig");

pub const Resources = @This();

shader_module: *wgpu.ShaderModule,
layout: *wgpu.PipelineLayout,
bind_group_layout: *wgpu.BindGroupLayout,
bind_group: *wgpu.BindGroup,
clear_pipeline: *wgpu.ComputePipeline,
simulate_pipeline: *wgpu.ComputePipeline,
spawn_pipeline: *wgpu.ComputePipeline,
prepare_draw_pipeline: *wgpu.ComputePipeline,

pub fn init(self: *Resources, device: *wgpu.Device, res: *const buffers.Resources) !void {
    const shader_module = device.createShaderModule(&wgpu.shaderModuleWGSLDescriptor(.{
        .label = "Particles GPU compute shader",
        .code = @embedFile("../resources/shaders/particles_gpu_compute.wgsl"),
    })).?;
    errdefer shader_module.release();

    const bind_group_layout = device.createBindGroupLayout(&wgpu.BindGroupLayoutDescriptor{
        .label = wgpu.StringView.fromSlice("Particles GPU compute BGL"),
        .entry_count = 7,
        .entries = &[_]wgpu.BindGroupLayoutEntry{
            .{
                .binding = 0,
                .visibility = wgpu.ShaderStages.compute,
                .buffer = wgpu.BufferBindingLayout{
                    .type = wgpu.BufferBindingType.uniform,
                    .has_dynamic_offset = @intFromBool(true),
                    .min_binding_size = res.sim_params_stride,
                },
            },
            .{
                .binding = 1,
                .visibility = wgpu.ShaderStages.compute,
                .buffer = wgpu.BufferBindingLayout{
                    .type = wgpu.BufferBindingType.storage,
                    .has_dynamic_offset = @intFromBool(false),
                    .min_binding_size = res.particle_stride * @as(u64, @intCast(res.total_capacity)),
                },
            },
            .{
                .binding = 2,
                .visibility = wgpu.ShaderStages.compute,
                .buffer = wgpu.BufferBindingLayout{
                    .type = wgpu.BufferBindingType.storage,
                    .has_dynamic_offset = @intFromBool(false),
                    .min_binding_size = @as(u64, @intCast(res.total_capacity)) * @sizeOf(u32),
                },
            },
            .{
                .binding = 3,
                .visibility = wgpu.ShaderStages.compute,
                .buffer = wgpu.BufferBindingLayout{
                    .type = wgpu.BufferBindingType.storage,
                    .has_dynamic_offset = @intFromBool(false),
                    .min_binding_size = @as(u64, @intCast(res.total_capacity)) * @sizeOf(u32),
                },
            },
            .{
                .binding = 4,
                .visibility = wgpu.ShaderStages.compute,
                .buffer = wgpu.BufferBindingLayout{
                    .type = wgpu.BufferBindingType.storage,
                    .has_dynamic_offset = @intFromBool(false),
                    .min_binding_size = @sizeOf(types.Counters) * @as(u64, @intCast(res.emitter_count)),
                },
            },
            .{
                .binding = 5,
                .visibility = wgpu.ShaderStages.compute,
                .buffer = wgpu.BufferBindingLayout{
                    .type = wgpu.BufferBindingType.storage,
                    .has_dynamic_offset = @intFromBool(false),
                    .min_binding_size = @sizeOf(types.DrawArgs) * @as(u64, @intCast(res.emitter_count)),
                },
            },
            .{
                .binding = 6,
                .visibility = wgpu.ShaderStages.compute,
                .buffer = wgpu.BufferBindingLayout{
                    .type = wgpu.BufferBindingType.storage,
                    .has_dynamic_offset = @intFromBool(false),
                    .min_binding_size = @sizeOf(types.DebugData) * @as(u64, @intCast(res.emitter_count)),
                },
            },
        },
    }).?;
    errdefer bind_group_layout.release();

    const layout = device.createPipelineLayout(&wgpu.PipelineLayoutDescriptor{
        .label = wgpu.StringView.fromSlice("Particles GPU compute layout"),
        .bind_group_layout_count = 1,
        .bind_group_layouts = &[_]*wgpu.BindGroupLayout{bind_group_layout},
    }).?;
    errdefer layout.release();

    const clear_pipeline = device.createComputePipeline(&wgpu.ComputePipelineDescriptor{
        .label = wgpu.StringView.fromSlice("Particles clear alive pipeline"),
        .layout = layout,
        .compute = wgpu.ProgrammableStageDescriptor{
            .module = shader_module,
            .entry_point = wgpu.StringView.fromSlice("cs_clear_alive"),
        },
    }).?;
    errdefer clear_pipeline.release();

    const simulate_pipeline = device.createComputePipeline(&wgpu.ComputePipelineDescriptor{
        .label = wgpu.StringView.fromSlice("Particles simulate pipeline"),
        .layout = layout,
        .compute = wgpu.ProgrammableStageDescriptor{
            .module = shader_module,
            .entry_point = wgpu.StringView.fromSlice("cs_simulate"),
        },
    }).?;
    errdefer simulate_pipeline.release();

    const spawn_pipeline = device.createComputePipeline(&wgpu.ComputePipelineDescriptor{
        .label = wgpu.StringView.fromSlice("Particles spawn pipeline"),
        .layout = layout,
        .compute = wgpu.ProgrammableStageDescriptor{
            .module = shader_module,
            .entry_point = wgpu.StringView.fromSlice("cs_spawn"),
        },
    }).?;
    errdefer spawn_pipeline.release();

    const prepare_draw_pipeline = device.createComputePipeline(&wgpu.ComputePipelineDescriptor{
        .label = wgpu.StringView.fromSlice("Particles draw args pipeline"),
        .layout = layout,
        .compute = wgpu.ProgrammableStageDescriptor{
            .module = shader_module,
            .entry_point = wgpu.StringView.fromSlice("cs_prepare_draw"),
        },
    }).?;
    errdefer prepare_draw_pipeline.release();

    const bind_group = device.createBindGroup(&wgpu.BindGroupDescriptor{
        .label = wgpu.StringView.fromSlice("Particles GPU compute bind group"),
        .layout = bind_group_layout,
        .entry_count = 7,
        .entries = &[_]wgpu.BindGroupEntry{
            .{ .binding = 0, .buffer = res.sim_params, .offset = 0, .size = res.sim_params_stride },
            .{ .binding = 1, .buffer = res.particles, .offset = 0, .size = res.particle_stride * @as(u64, @intCast(res.total_capacity)) },
            .{ .binding = 2, .buffer = res.alive_list, .offset = 0, .size = @as(u64, @intCast(res.total_capacity)) * @sizeOf(u32) },
            .{ .binding = 3, .buffer = res.free_list, .offset = 0, .size = @as(u64, @intCast(res.total_capacity)) * @sizeOf(u32) },
            .{ .binding = 4, .buffer = res.counters, .offset = 0, .size = @sizeOf(types.Counters) * @as(u64, @intCast(res.emitter_count)) },
            .{ .binding = 5, .buffer = res.indirect, .offset = 0, .size = @sizeOf(types.DrawArgs) * @as(u64, @intCast(res.emitter_count)) },
            .{ .binding = 6, .buffer = res.debug_out, .offset = 0, .size = @sizeOf(types.DebugData) * @as(u64, @intCast(res.emitter_count)) },
        },
    }).?;
    errdefer bind_group.release();

    self.shader_module = shader_module;
    self.layout = layout;
    self.bind_group_layout = bind_group_layout;
    self.bind_group = bind_group;
    self.clear_pipeline = clear_pipeline;
    self.simulate_pipeline = simulate_pipeline;
    self.spawn_pipeline = spawn_pipeline;
    self.prepare_draw_pipeline = prepare_draw_pipeline;
}

pub fn deinit(self: *Resources) void {
    self.prepare_draw_pipeline.release();
    self.spawn_pipeline.release();
    self.simulate_pipeline.release();
    self.clear_pipeline.release();
    self.bind_group.release();
    self.bind_group_layout.release();
    self.layout.release();
    self.shader_module.release();
}
