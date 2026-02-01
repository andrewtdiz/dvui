const std = @import("std");

const wgpu = @import("wgpu");

const clayEngineDeviceLabel = wgpu.StringView.fromSlice("Clay Engine GPU Device");

fn logUncapturedError(
    _: ?*wgpu.Device,
    error_type: wgpu.ErrorType,
    message: wgpu.StringView,
    _: ?*anyopaque,
    _: ?*anyopaque,
) callconv(.c) void {
    std.debug.print("[wgpu] {s}: {s}\n", .{ @tagName(error_type), message.toSlice() orelse "" });
}

pub const Resources = @This();

instance: *wgpu.Instance,
adapter: *wgpu.Adapter,
device: *wgpu.Device,
queue: *wgpu.Queue,
surface: *wgpu.Surface,
format: wgpu.TextureFormat,
present_mode: wgpu.PresentMode,
alpha_mode: wgpu.CompositeAlphaMode,

pub fn initWindows(hwnd: *anyopaque, hinstance: *anyopaque, width: u32, height: u32) !Resources {
    const instance = wgpu.Instance.create(null).?;
    errdefer instance.release();

    var surface_source = wgpu.SurfaceSourceWindowsHWND{
        .hinstance = hinstance,
        .hwnd = hwnd,
    };
    const surface_descriptor = wgpu.SurfaceDescriptor{
        .next_in_chain = @ptrCast(&surface_source),
        .label = wgpu.StringView.fromSlice("raylib window surface"),
    };
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

    var props = std.mem.zeroes(wgpu.AdapterInfo);
    const status = adapter.getInfo(&props);
    if (status != .success) {
        std.debug.print("failed to get adapter info: {any}\n", .{status});
        return error.FailedToGetAdapterInfo;
    }
    std.debug.print("GPU adapter {s} ({s}) backend={s}\n", .{
        props.device.toSlice() orelse "unknown",
        props.description.toSlice() orelse "unknown",
        @tagName(props.backend_type),
    });
    defer props.freeMembers();

    const device_request = adapter.requestDeviceSync(instance, &wgpu.DeviceDescriptor{
        .label = clayEngineDeviceLabel,
        .required_limits = null,
        .uncaptured_error_callback_info = wgpu.UncapturedErrorCallbackInfo{
            .callback = logUncapturedError,
        },
    }, 0);
    const device = switch (device_request.status) {
        .success => device_request.device.?,
        else => return error.NoDevice,
    };
    errdefer device.release();

    const queue = device.getQueue().?;

    const format = pickSurfaceFormat(&caps);
    const present_mode = if (caps.present_mode_count > 0) caps.present_modes[0] else wgpu.PresentMode.mailbox;
    const alpha_mode = if (caps.alpha_mode_count > 0) caps.alpha_modes[0] else wgpu.CompositeAlphaMode.auto;
    surface.configure(&wgpu.SurfaceConfiguration{
        .device = device,
        .format = format,
        .usage = wgpu.TextureUsages.render_attachment | wgpu.TextureUsages.copy_src,
        .width = width,
        .height = height,
        .present_mode = present_mode,
        .alpha_mode = alpha_mode,
    });

    return .{
        .instance = instance,
        .adapter = adapter,
        .device = device,
        .queue = queue,
        .surface = surface,
        .format = format,
        .present_mode = present_mode,
        .alpha_mode = alpha_mode,
    };
}

fn pickSurfaceFormat(caps: *const wgpu.SurfaceCapabilities) wgpu.TextureFormat {
    const preferred = [_]wgpu.TextureFormat{
        .bgra8_unorm_srgb,
        .rgba8_unorm_srgb,
        .bgra8_unorm,
        .rgba8_unorm,
    };
    for (preferred) |candidate| {
        var i: usize = 0;
        while (i < caps.format_count) : (i += 1) {
            if (caps.formats[i] == candidate) return candidate;
        }
    }
    if (caps.format_count > 0) return caps.formats[0];
    return wgpu.TextureFormat.bgra8_unorm_srgb;
}

pub fn deinit(self: *Resources) void {
    self.surface.release();
    self.queue.release();
    self.device.release();
    self.adapter.release();
    self.instance.release();
}
