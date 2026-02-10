const std = @import("std");
const builtin = @import("builtin");

const dvui = @import("dvui");
const wgpu = @import("wgpu");
const RaylibBackend = @import("raylib-backend");
const ray = RaylibBackend.raylib;

const WgpuBackend = @import("wgpu-backend").WgpuBackend;
const swap_chain = @import("../pipeline/swap_chain.zig");

const log = std.log.scoped(.Webgpu);

const platform = switch (builtin.os.tag) {
    .windows => @import("platform_windows.zig"),
    .macos => @import("platform_macos.zig"),
    else => struct {
        pub const State = struct {};
        pub const Init = struct { swap: swap_chain.Resources, state: State };
        pub fn init(_: *anyopaque, _: u32, _: u32, _: f32) !Init {
            return error.UnsupportedPlatform;
        }
        pub fn resize(_: *State, _: u32, _: u32, _: f32) void {}
    },
};

pub const WindowSize = struct {
    width: u32,
    height: u32,
};

pub const Renderer = struct {
    swap: swap_chain.Resources,
    dvui_backend: WgpuBackend,
    platform_state: platform.State,
    size: WindowSize,
    pixel_size: WindowSize,
    content_scale: f32,
    screenshot_path_buf: [260]u8 = undefined,
    screenshot_path_len: usize = 0,

    pub fn init(allocator: std.mem.Allocator, size: WindowSize, pixel_size: WindowSize) !Renderer {
        const handle = ray.getWindowHandle();
        if (@intFromPtr(handle) == 0) return error.MissingWindowHandle;

        const content_scale = computeContentScale(size, pixel_size);
        const init_result = try platform.init(handle, pixel_size.width, pixel_size.height, content_scale);
        var swap = init_result.swap;
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
            .platform_state = init_result.state,
            .size = size,
            .pixel_size = pixel_size,
            .content_scale = content_scale,
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

    pub fn requestScreenshot(self: *Renderer, path: []const u8) bool {
        if (self.screenshot_path_len != 0) return false;
        if (path.len == 0 or path.len > self.screenshot_path_buf.len) return false;
        @memcpy(self.screenshot_path_buf[0..path.len], path);
        self.screenshot_path_len = path.len;
        return true;
    }

    pub fn resize(self: *Renderer, size: WindowSize, pixel_size: WindowSize) void {
        if (pixel_size.width == 0 or pixel_size.height == 0) return;
        self.size = size;
        self.pixel_size = pixel_size;
        self.content_scale = computeContentScale(size, pixel_size);
        platform.resize(&self.platform_state, pixel_size.width, pixel_size.height, self.content_scale);
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

        const screenshot_path = if (self.screenshot_path_len == 0) null else self.screenshot_path_buf[0..self.screenshot_path_len];
        if (screenshot_path != null) self.screenshot_path_len = 0;
        var screenshot_buffer: ?*wgpu.Buffer = null;
        var screenshot_width: u32 = 0;
        var screenshot_height: u32 = 0;
        var screenshot_stride: usize = 0;
        var screenshot_size: usize = 0;

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

        if (screenshot_path != null) {
            screenshot_width = self.pixel_size.width;
            screenshot_height = self.pixel_size.height;
            if (screenshot_width == 0 or screenshot_height == 0) return error.ScreenshotInvalidSize;

            switch (self.swap.format) {
                .bgra8_unorm_srgb, .bgra8_unorm, .rgba8_unorm_srgb, .rgba8_unorm => {},
                else => return error.ScreenshotUnsupportedFormat,
            }

            const unpadded_bytes_per_row: usize = @as(usize, screenshot_width) * 4;
            screenshot_stride = std.mem.alignForward(usize, unpadded_bytes_per_row, 256);
            screenshot_size = screenshot_stride * @as(usize, screenshot_height);

            const buffer = self.swap.device.createBuffer(&wgpu.BufferDescriptor{
                .label = wgpu.StringView.fromSlice("dvui screenshot"),
                .usage = wgpu.BufferUsages.copy_dst | wgpu.BufferUsages.map_read,
                .size = @intCast(screenshot_size),
                .mapped_at_creation = @intFromBool(false),
            }) orelse return error.ScreenshotBufferCreateFailed;
            screenshot_buffer = buffer;

            const source = wgpu.TexelCopyTextureInfo{
                .texture = texture,
                .mip_level = 0,
                .origin = .{},
                .aspect = .all,
            };
            const dest = wgpu.TexelCopyBufferInfo{
                .buffer = buffer,
                .layout = .{
                    .offset = 0,
                    .bytes_per_row = @intCast(screenshot_stride),
                    .rows_per_image = screenshot_height,
                },
            };
            const extent = wgpu.Extent3D{
                .width = screenshot_width,
                .height = screenshot_height,
                .depth_or_array_layers = 1,
            };
            encoder.copyTextureToBuffer(&source, &dest, &extent);
        }

        const command_buffer = encoder.finish(&wgpu.CommandBufferDescriptor{
            .label = wgpu.StringView.fromSlice("dvui commands"),
        }).?;
        defer command_buffer.release();

        self.swap.queue.submit(&[_]*const wgpu.CommandBuffer{command_buffer});
        _ = self.swap.surface.present();

        if (screenshot_buffer) |buffer| {
            defer buffer.release();

            var map_done = false;
            var map_status: wgpu.MapAsyncStatus = .unknown;
            _ = buffer.mapAsync(wgpu.MapModes.read, 0, screenshot_size, wgpu.BufferMapCallbackInfo{
                .callback = screenshotMapCallback,
                .userdata1 = @ptrCast(&map_done),
                .userdata2 = @ptrCast(&map_status),
            });

            self.swap.instance.processEvents();
            while (!map_done) {
                _ = self.swap.device.poll(true, null);
                self.swap.instance.processEvents();
            }
            if (map_status != .success) return error.ScreenshotMapFailed;
            defer buffer.unmap();

            const mapped_ptr = buffer.getConstMappedRange(0, screenshot_size) orelse return error.ScreenshotMapFailed;
            const mapped: [*]const u8 = @ptrCast(mapped_ptr);

            const format_is_bgra = switch (self.swap.format) {
                .bgra8_unorm_srgb, .bgra8_unorm => true,
                .rgba8_unorm_srgb, .rgba8_unorm => false,
                else => return error.ScreenshotUnsupportedFormat,
            };

            const pixel_count: usize = @as(usize, screenshot_width) * @as(usize, screenshot_height);
            var rgba_pixels = try self.dvui_backend.gpa.alloc(u8, pixel_count * 4);
            defer self.dvui_backend.gpa.free(rgba_pixels);

            const row_bytes: usize = @as(usize, screenshot_width) * 4;
            var y: usize = 0;
            while (y < screenshot_height) : (y += 1) {
                const row_src = mapped[y * screenshot_stride .. y * screenshot_stride + row_bytes];
                const row_dst = rgba_pixels[y * row_bytes .. y * row_bytes + row_bytes];
                var x: usize = 0;
                while (x < screenshot_width) : (x += 1) {
                    const si: usize = x * 4;
                    const di: usize = x * 4;
                    if (format_is_bgra) {
                        row_dst[di + 0] = row_src[si + 2];
                        row_dst[di + 1] = row_src[si + 1];
                        row_dst[di + 2] = row_src[si + 0];
                        row_dst[di + 3] = row_src[si + 3];
                    } else {
                        row_dst[di + 0] = row_src[si + 0];
                        row_dst[di + 1] = row_src[si + 1];
                        row_dst[di + 2] = row_src[si + 2];
                        row_dst[di + 3] = row_src[si + 3];
                    }
                }
            }

            const file = try std.fs.cwd().createFile(screenshot_path.?, .{});
            defer file.close();
            var out_buf: [8192]u8 = undefined;
            var writer = file.writer(&out_buf);
            try dvui.PNGEncoder.writeWithResolution(&writer.interface, rgba_pixels, screenshot_width, screenshot_height, 0);
            try writer.end();
        }
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

    fn screenshotMapCallback(status: wgpu.MapAsyncStatus, _: wgpu.StringView, userdata1: ?*anyopaque, userdata2: ?*anyopaque) callconv(.c) void {
        const map_done: *bool = @ptrCast(@alignCast(userdata1.?));
        const map_status: *wgpu.MapAsyncStatus = @ptrCast(@alignCast(userdata2.?));
        map_status.* = status;
        map_done.* = true;
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
