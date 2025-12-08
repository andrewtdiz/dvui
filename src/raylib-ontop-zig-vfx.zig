const std = @import("std");
const builtin = @import("builtin");

const ray = @import("raylib");
const wgpu = @import("wgpu");

const alloc = @import("alloc.zig");
const swap_chain = @import("pipeline/swap_chain.zig");
const geometry = @import("pipeline/geometry.zig");
const uniforms = @import("pipeline/uniforms.zig");
const bind_group = @import("pipeline/bind_group.zig");
const depth = @import("pipeline/depth.zig");
const render_pipeline = @import("pipeline/render_pipeline.zig");

const log = std.log.scoped(.RaylibWgpu);

const WindowSize = struct {
    width: u32,
    height: u32,
};

const vertex_attributes = [_]wgpu.VertexAttribute{
    .{
        .format = wgpu.VertexFormat.float32x3,
        .offset = 0,
        .shader_location = 0,
    },
    .{
        .format = wgpu.VertexFormat.float32x3,
        .offset = @offsetOf(geometry.VertexAttributes, "normal"),
        .shader_location = 1,
    },
    .{
        .format = wgpu.VertexFormat.float32x3,
        .offset = @offsetOf(geometry.VertexAttributes, "color"),
        .shader_location = 2,
    },
};

const Renderer = struct {
    swap: swap_chain.Resources,
    depth_buffer: depth.Resources,
    geometry: geometry.Resources,
    uniforms: uniforms.Resources,
    bind_group: bind_group.Resources,
    pipeline: render_pipeline.Resources,
    size: WindowSize,

    pub fn init(surface_descriptor: wgpu.SurfaceDescriptor, size: WindowSize) !Renderer {
        var swap = try swap_chain.Resources.init(surface_descriptor, size.width, size.height, vertex_attributes);
        errdefer swap.deinit();

        var depth_buffer = try depth.Resources.init(swap.device, size.width, size.height);
        errdefer depth_buffer.deinit();

        var geometry_res: geometry.Resources = undefined;
        try geometry_res.init(swap.device, swap.queue);
        errdefer geometry_res.deinit();

        var uniform_res: uniforms.Resources = undefined;
        try uniform_res.init(swap.device, swap.queue, size.width, size.height);
        errdefer uniform_res.deinit();

        var bind_res: bind_group.Resources = undefined;
        try bind_res.init(swap.device, uniform_res.buffer, @as(u64, uniform_res.slot_stride));
        errdefer bind_res.deinit();

        var pipeline_res: render_pipeline.Resources = undefined;
        try pipeline_res.init(swap.device, swap.format, vertex_attributes, bind_res.layout);
        errdefer pipeline_res.deinit();

        return .{
            .swap = swap,
            .depth_buffer = depth_buffer,
            .geometry = geometry_res,
            .uniforms = uniform_res,
            .bind_group = bind_res,
            .pipeline = pipeline_res,
            .size = size,
        };
    }

    pub fn deinit(self: *Renderer) void {
        self.pipeline.deinit();
        self.bind_group.deinit();
        self.uniforms.deinit();
        self.geometry.deinit();
        self.depth_buffer.deinit();
        self.swap.deinit();
    }

    pub fn resize(self: *Renderer, new_size: WindowSize) !void {
        if (new_size.width == 0 or new_size.height == 0) return;

        configureSurface(&self.swap, new_size);

        self.depth_buffer.deinit();
        self.depth_buffer = try depth.Resources.init(self.swap.device, new_size.width, new_size.height);
        self.uniforms.refreshProjection(self.swap.queue, new_size.width, new_size.height);
        self.size = new_size;
    }

    pub fn animate(self: *Renderer, angle: f32) void {
        self.uniforms.updateModel(self.swap.queue, angle);
    }

    pub fn render(self: *Renderer) !void {
        var surface_texture = std.mem.zeroes(wgpu.SurfaceTexture);
        self.swap.surface.getCurrentTexture(&surface_texture);
        defer {
            if (surface_texture.texture) |tex| tex.release();
        }

        const status = surface_texture.status;
        if (status != wgpu.GetCurrentTextureStatus.success_optimal and status != wgpu.GetCurrentTextureStatus.success_suboptimal) {
            log.err("surface status {s}, reconfiguring", .{@tagName(status)});
            configureSurface(&self.swap, self.size);
            return;
        }

        const texture = surface_texture.texture orelse return error.SurfaceTextureMissing;
        const view = texture.createView(null) orelse return error.CreateViewFailed;
        defer view.release();

        const encoder = self.swap.device.createCommandEncoder(&wgpu.CommandEncoderDescriptor{
            .label = wgpu.StringView.fromSlice("Main encoder"),
        }).?;
        defer encoder.release();

        const color_attachment = wgpu.ColorAttachment{
            .view = view,
            .depth_slice = wgpu.WGPU_DEPTH_SLICE_UNDEFINED,
            .load_op = wgpu.LoadOp.clear,
            .store_op = wgpu.StoreOp.store,
            .clear_value = wgpu.Color{ .r = 0.06, .g = 0.07, .b = 0.12, .a = 1.0 },
        };
        var depth_attachment = wgpu.DepthStencilAttachment{
            .view = self.depth_buffer.view,
            .depth_load_op = wgpu.LoadOp.clear,
            .depth_store_op = wgpu.StoreOp.store,
            .depth_clear_value = 1.0,
            .depth_read_only = @intFromBool(false),
            .stencil_load_op = wgpu.LoadOp.clear,
            .stencil_store_op = wgpu.StoreOp.discard,
            .stencil_clear_value = 0,
            .stencil_read_only = @intFromBool(false),
        };

        const color_attachments = [_]wgpu.ColorAttachment{color_attachment};
        var render_pass = encoder.beginRenderPass(&wgpu.RenderPassDescriptor{
            .label = wgpu.StringView.fromSlice("Render pass"),
            .color_attachment_count = color_attachments.len,
            .color_attachments = &[_]wgpu.ColorAttachment{color_attachment},
            .depth_stencil_attachment = &depth_attachment,
        }).?;

        const offsets = [_]u32{self.uniforms.dynamicOffsetForIndex(0)};
        const vertex_buffer_size: u64 = @as(u64, @intCast(self.geometry.vertexCount)) * @as(u64, @sizeOf(geometry.VertexAttributes));

        render_pass.setPipeline(self.pipeline.pipeline);
        render_pass.setBindGroup(0, self.bind_group.group, offsets.len, &offsets);
        render_pass.setVertexBuffer(0, self.geometry.point_buffer, 0, vertex_buffer_size);
        render_pass.draw(self.geometry.vertexCount, 1, 0, 0);
        render_pass.end();
        render_pass.release();

        const command_buffer = encoder.finish(&wgpu.CommandBufferDescriptor{
            .label = wgpu.StringView.fromSlice("Render commands"),
        }).?;
        defer command_buffer.release();

        self.swap.queue.submit(&[_]*const wgpu.CommandBuffer{command_buffer});
        _ = self.swap.surface.present();
    }
};

pub fn main() !void {
    alloc.init();
    defer alloc.deinit();

    ray.setConfigFlags(.{ .window_resizable = true, .vsync_hint = true });
    ray.initWindow(1280, 720, "Raylib + WGPU pipeline");
    defer ray.closeWindow();

    const surface_desc = try surfaceDescriptor();
    var size = currentSize();
    var renderer = try Renderer.init(surface_desc, size);
    defer renderer.deinit();

    const two_pi: f32 = 6.283185307179586;
    var angle: f32 = 0.0;

    while (!ray.windowShouldClose()) {
        ray.pollInputEvents();

        const next_size = currentSize();
        if (next_size.width != size.width or next_size.height != size.height) {
            size = next_size;
            renderer.resize(size) catch |err| log.err("resize failed: {s}", .{@errorName(err)});
        }

        const dt = ray.getFrameTime();
        angle += dt * 0.7;
        if (angle > two_pi) angle -= two_pi;
        renderer.animate(angle);

        renderer.render() catch |err| {
            log.err("render failed: {s}", .{@errorName(err)});
        };
    }
}

fn currentSize() WindowSize {
    return .{
        .width = @intCast(ray.getScreenWidth()),
        .height = @intCast(ray.getScreenHeight()),
    };
}

fn configureSurface(swap: *swap_chain.Resources, size: WindowSize) void {
    swap.surface.configure(&wgpu.SurfaceConfiguration{
        .device = swap.device,
        .format = swap.format,
        .usage = wgpu.TextureUsages.render_attachment,
        .width = size.width,
        .height = size.height,
        .alpha_mode = wgpu.CompositeAlphaMode.auto,
        .present_mode = wgpu.PresentMode.fifo,
    });
}

fn surfaceDescriptor() !wgpu.SurfaceDescriptor {
    return switch (builtin.os.tag) {
        .windows => {
            const hwnd = ray.getWindowHandle();
            const hinstance = std.os.windows.kernel32.GetModuleHandleW(null) orelse return error.MissingInstanceHandle;
            return wgpu.surfaceDescriptorFromWindowsHWND(.{
                .label = "raylib window surface",
                .hinstance = @ptrCast(hinstance),
                .hwnd = hwnd,
            });
        },
        else => error.UnsupportedPlatform,
    };
}
