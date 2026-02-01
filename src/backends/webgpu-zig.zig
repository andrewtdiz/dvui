const std = @import("std");
const dvui = @import("dvui");
const wgpu = @import("wgpu");
const RaylibBackend = @import("raylib-backend");
const ray = RaylibBackend.raylib;

const WgpuBackend = @import("wgpu-backend").WgpuBackend;
const swap_chain = @import("pipeline/swap_chain.zig");

const log = std.log.scoped(.Webgpu);

pub const WindowSize = struct {
    width: u32,
    height: u32,
};

pub const Renderer = struct {
    swap: swap_chain.Resources,
    dvui_backend: WgpuBackend,
    size: WindowSize,
    pixel_size: WindowSize,
    content_scale: f32,

    pub fn init(allocator: std.mem.Allocator, size: WindowSize, pixel_size: WindowSize) !Renderer {
        const hwnd = ray.getWindowHandle();
        if (@intFromPtr(hwnd) == 0) return error.MissingWindowHandle;
        const hinstance = std.os.windows.kernel32.GetModuleHandleW(null) orelse return error.MissingInstanceHandle;
        var swap = try swap_chain.Resources.initWindows(hwnd, @ptrCast(hinstance), pixel_size.width, pixel_size.height);
        errdefer swap.deinit();

        var dvui_backend = try WgpuBackend.init(.{
            .gpa = allocator,
            .device = swap.device,
            .queue = swap.queue,
            .color_format = swap.format,
            .depth_format = null,
            .sample_count = 1,
            .max_frames_in_flight = 1,
            .preferred_color_scheme = null,
        });
        errdefer dvui_backend.deinit();

        var renderer = Renderer{
            .swap = swap,
            .dvui_backend = dvui_backend,
            .size = size,
            .pixel_size = pixel_size,
            .content_scale = computeContentScale(size, pixel_size),
        };
        renderer.updateSurface();
        return renderer;
    }

    pub fn deinit(self: *Renderer) void {
        self.dvui_backend.deinit();
        self.swap.deinit();
    }

    pub fn dvuiBackend(self: *Renderer) dvui.Backend {
        return self.dvui_backend.backend();
    }

    pub fn resize(self: *Renderer, size: WindowSize, pixel_size: WindowSize) void {
        if (pixel_size.width == 0 or pixel_size.height == 0) return;
        self.size = size;
        self.pixel_size = pixel_size;
        self.content_scale = computeContentScale(size, pixel_size);
        configureSurface(&self.swap, pixel_size);
        self.updateSurface();
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
            configureSurface(&self.swap, self.pixel_size);
            return;
        }

        const texture = surface_texture.texture orelse return error.SurfaceTextureMissing;
        const view = texture.createView(null) orelse return error.CreateViewFailed;
        defer view.release();

        const encoder = self.swap.device.createCommandEncoder(&wgpu.CommandEncoderDescriptor{
            .label = wgpu.StringView.fromSlice("dvui encoder"),
        }).?;
        defer encoder.release();

        const clear_attachment = wgpu.ColorAttachment{
            .view = view,
            .depth_slice = wgpu.WGPU_DEPTH_SLICE_UNDEFINED,
            .load_op = wgpu.LoadOp.clear,
            .store_op = wgpu.StoreOp.store,
            .clear_value = wgpu.Color{ .r = 0.06, .g = 0.07, .b = 0.12, .a = 1.0 },
        };

        var clear_pass = encoder.beginRenderPass(&wgpu.RenderPassDescriptor{
            .label = wgpu.StringView.fromSlice("dvui clear"),
            .color_attachment_count = 1,
            .color_attachments = &[_]wgpu.ColorAttachment{clear_attachment},
            .depth_stencil_attachment = null,
        }).?;
        clear_pass.end();
        clear_pass.release();

        try self.dvui_backend.encode(encoder, view);

        const command_buffer = encoder.finish(&wgpu.CommandBufferDescriptor{
            .label = wgpu.StringView.fromSlice("dvui commands"),
        }).?;
        defer command_buffer.release();

        self.swap.queue.submit(&[_]*const wgpu.CommandBuffer{command_buffer});
        _ = self.swap.surface.present();
    }

    fn updateSurface(self: *Renderer) void {
        const window_w = if (self.size.width == 0) 1 else self.size.width;
        const window_h = if (self.size.height == 0) 1 else self.size.height;
        const pixel_w = if (self.pixel_size.width == 0) 1 else self.pixel_size.width;
        const pixel_h = if (self.pixel_size.height == 0) 1 else self.pixel_size.height;
        self.dvui_backend.updateSurface(.{
            .window_size = .{ .w = @floatFromInt(window_w), .h = @floatFromInt(window_h) },
            .pixel_size = .{ .w = @floatFromInt(pixel_w), .h = @floatFromInt(pixel_h) },
            .surface_size = .{ .w = @floatFromInt(pixel_w), .h = @floatFromInt(pixel_h) },
            .viewport_origin = .{ .x = 0, .y = 0 },
            .content_scale = self.content_scale,
        });
    }
};

fn computeContentScale(size: WindowSize, pixel_size: WindowSize) f32 {
    if (size.width == 0 or pixel_size.width == 0) return 1.0;
    return @as(f32, @floatFromInt(pixel_size.width)) / @as(f32, @floatFromInt(size.width));
}

fn configureSurface(swap: *swap_chain.Resources, pixel_size: WindowSize) void {
    swap.surface.configure(&wgpu.SurfaceConfiguration{
        .device = swap.device,
        .format = swap.format,
        .usage = wgpu.TextureUsages.render_attachment | wgpu.TextureUsages.copy_src,
        .width = pixel_size.width,
        .height = pixel_size.height,
        .alpha_mode = swap.alpha_mode,
        .present_mode = swap.present_mode,
    });
}
