//! Minimal C-friendly entrypoints for the dvui core. This is a seed file for
//! the Bun FFI surface; we will grow it with real window/event/render calls.
const std = @import("std");
const dvui = @import("dvui");
const RaylibBackendMod = @import("raylib-backend");
const WgpuBackendMod = struct {
    pub const WgpuBackend = void;
};
const render = dvui.render;
const enums = dvui.enums;

const version_cstr: [*:0]const u8 = "dvui-core-ffi-0.1.0";

/// Returns a static, null-terminated version string.
pub export fn dvui_core_version() [*:0]const u8 {
    return version_cstr;
}

/// Backend selector understood by the FFI surface.
pub const BackendKind = enum(u8) {
    raylib = 0,
    wgpu = 1,
};

/// Basic init options; extend as the FFI surface expands.
pub const InitOptions = extern struct {
    backend: BackendKind,
    width: f32,
    height: f32,
    vsync: bool,
    title: [*:0]const u8,
};

/// Opaque handle returned to callers.
pub const FfiHandle = extern struct {
    backend: BackendKind,
    window: *dvui.Window,
    raylib: ?*RaylibBackendMod.RaylibBackend,
    wgpu: ?*WgpuBackendMod.WgpuBackend,
};

var gpa_instance = std.heap.GeneralPurposeAllocator(.{}){};

fn alloc(comptime T: type) !*T {
    return try gpa_instance.allocator().create(T);
}

fn destroy(ptr: anytype) void {
    gpa_instance.allocator().destroy(ptr);
}

fn initRaylib(opts: *const InitOptions) ?*FfiHandle {
    const gpa = gpa_instance.allocator();

    const title_slice: []const u8 = if (opts.title == null) "dvui" else std.mem.span(opts.title);
    const size = dvui.Size{ .w = if (opts.width > 0) opts.width else 800, .h = if (opts.height > 0) opts.height else 600 };

    var rb = alloc(RaylibBackendMod.RaylibBackend) catch return null;
    rb.* = RaylibBackendMod.RaylibBackend.initWindow(.{
        .gpa = gpa,
        .size = size,
        .min_size = null,
        .max_size = null,
        .vsync = opts.vsync,
        .title = title_slice,
        .icon = null,
    }) catch |err| {
        destroy(rb);
        std.log.err("dvui_core_init raylib failed: {s}", .{@errorName(err)});
        return null;
    };

    var win = alloc(dvui.Window) catch {
        rb.deinit();
        destroy(rb);
        return null;
    };
    win.* = dvui.Window.init(@src(), gpa, rb.backend(), .{}) catch |err| {
        rb.deinit();
        destroy(rb);
        destroy(win);
        std.log.err("dvui_core_init window failed: {s}", .{@errorName(err)});
        return null;
    };

    const handle = alloc(FfiHandle) catch {
        win.deinit();
        destroy(win);
        rb.deinit();
        destroy(rb);
        return null;
    };
    handle.* = .{
        .backend = .raylib,
        .window = win,
        .raylib = rb,
        .wgpu = null,
    };
    return handle;
}

fn initWgpu(_: *const InitOptions) ?*FfiHandle {
    // WGPU path requires caller-provided device/queue/surface; leave stubbed for now.
    return null;
}

/// Initialize dvui and return an opaque handle or null on failure.
pub export fn dvui_core_init(opts: *const InitOptions) ?*FfiHandle {
    return switch (opts.backend) {
        .raylib => initRaylib(opts),
        .wgpu => initWgpu(opts),
    };
}

/// Shut down and free all resources for the given handle.
pub export fn dvui_core_deinit(handle: *FfiHandle) void {
    // Tear down window first so it can free textures/caches before backend.
    const w = handle.window;
    w.deinit();
    destroy(w);

    if (handle.raylib) |rb| {
        rb.deinit();
        destroy(rb);
    }

    if (handle.wgpu) |wb| {
        wb.deinit();
        destroy(wb);
    }

    destroy(handle);
}

// --- Frame orchestration ----------------------------------------------------

/// Begin a frame. Returns false on failure.
pub export fn dvui_core_begin_frame(handle: *FfiHandle) bool {
    const time_ns: i128 = switch (handle.backend) {
        .raylib => blk: {
            if (handle.raylib) |rb| {
                RaylibBackendMod.raylib.beginDrawing();
                RaylibBackendMod.raylib.clearBackground(RaylibBackendMod.raylib.Color.blank);
                break :blk rb.nanoTime();
            } else return false;
        },
        .wgpu => return false,
    };

    handle.window.begin(time_ns) catch return false;
    return true;
}

/// End a frame and present. Returns false on failure.
pub export fn dvui_core_end_frame(handle: *FfiHandle) bool {
    const wait_micros = handle.window.end(.{}) catch return false;

    switch (handle.backend) {
        .raylib => {
            const rb = handle.raylib orelse return false;
            rb.setCursor(handle.window.cursorRequested());
            const timeout = wait_micros orelse std.math.maxInt(u32);
            rb.EndDrawingWaitEventTimeout(timeout);
        },
        .wgpu => {},
    }

    return true;
}

// --- Event injection --------------------------------------------------------

pub const PointerEvent = extern struct {
    x: f32,
    y: f32,
    button: u8, // dvui.enums.Button
    action: u8, // 0=motion,1=press,2=release
};

pub export fn dvui_core_pointer(handle: *FfiHandle, evt: PointerEvent) bool {
    const win = handle.window;
    const button: enums.Button = @enumFromInt(evt.button);
    const p: dvui.Point.Physical = .{ .x = evt.x, .y = evt.y };

    switch (evt.action) {
        0 => win.addEventMouseMotion(.{ .pt = p }) catch return false,
        1 => win.addEventMouseButton(button, .press) catch return false,
        2 => win.addEventMouseButton(button, .release) catch return false,
        else => return false,
    }
    return true;
}

pub const WheelEvent = extern struct {
    dx: f32,
    dy: f32,
};

pub export fn dvui_core_wheel(handle: *FfiHandle, evt: WheelEvent) bool {
    const win = handle.window;
    if (evt.dx != 0) win.addEventMouseWheel(evt.dx, .horizontal) catch return false;
    if (evt.dy != 0) win.addEventMouseWheel(evt.dy, .vertical) catch return false;
    return true;
}

pub const KeyEvent = extern struct {
    code: u16, // dvui.enums.Key
    action: u8, // 0=down,1=repeat,2=up
    mods: u16, // dvui.enums.Mod bitset
};

pub export fn dvui_core_key(handle: *FfiHandle, evt: KeyEvent) bool {
    const win = handle.window;
    const code: enums.Key = @enumFromInt(evt.code);
    const modbits: enums.Mod = @enumFromInt(evt.mods);
    const action: dvui.Event.Key.Action = switch (evt.action) {
        0 => .down,
        1 => .repeat,
        2 => .up,
        else => return false,
    };
    win.addEventKey(.{ .code = code, .action = action, .mod = modbits }) catch return false;
    return true;
}

pub const TextEvent = extern struct {
    ptr: ?[*]const u8,
    len: usize,
};

pub export fn dvui_core_text(handle: *FfiHandle, evt: TextEvent) bool {
    if (evt.ptr == null or evt.len == 0) return true;
    const slice = evt.ptr.?[0..evt.len];
    handle.window.addEventText(.{ .text = slice, .replace = false, .selected = false }) catch return false;
    return true;
}

// --- Command ingest (Quad / Text) ------------------------------------------

const CommandHeader = struct {
    opcode: u8,
    flags: u8,
    node_id: u32,
    parent_id: u32,
    x: f32,
    y: f32,
    w: f32,
    h: f32,
    payload_off: u32,
    payload_len: u32,
    extra: u32,
};

fn readHeader(slice: []const u8) CommandHeader {
    return .{
        .opcode = slice[0],
        .flags = slice[1],
        .node_id = std.mem.readInt(u32, slice[4..8], .little),
        .parent_id = std.mem.readInt(u32, slice[8..12], .little),
        .x = @bitCast(std.mem.readInt(u32, slice[12..16], .little)),
        .y = @bitCast(std.mem.readInt(u32, slice[16..20], .little)),
        .w = @bitCast(std.mem.readInt(u32, slice[20..24], .little)),
        .h = @bitCast(std.mem.readInt(u32, slice[24..28], .little)),
        .payload_off = std.mem.readInt(u32, slice[28..32], .little),
        .payload_len = std.mem.readInt(u32, slice[32..36], .little),
        .extra = std.mem.readInt(u32, slice[36..40], .little),
    };
}

fn colorFromU32(v: u32) dvui.Color {
    return .{
        .r = @intCast((v >> 24) & 0xff),
        .g = @intCast((v >> 16) & 0xff),
        .b = @intCast((v >> 8) & 0xff),
        .a = @intCast(v & 0xff),
    };
}

fn renderQuad(win: *dvui.Window, hdr: CommandHeader) !void {
    _ = hdr.parent_id;
    _ = hdr.flags;
    const rect: dvui.Rect.Physical = .{ .x = hdr.x, .y = hdr.y, .w = hdr.w, .h = hdr.h };
    const color = colorFromU32(hdr.extra);
    _ = win;
    // No radius, no fade
    rect.fill(.{}, .{ .color = color });
}

fn renderText(win: *dvui.Window, hdr: CommandHeader, payload: []const u8) !void {
    _ = hdr.parent_id;
    _ = hdr.flags;
    const rect: dvui.Rect.Physical = .{ .x = hdr.x, .y = hdr.y, .w = hdr.w, .h = hdr.h };
    const rs: dvui.RectScale = .{ .r = rect, .s = 1.0 };
    const color = colorFromU32(hdr.extra);
    const font = win.theme.font(.body);
    try render.renderText(.{
        .font = font,
        .text = payload,
        .rs = rs,
        .color = color,
        .background_color = null,
        .sel_start = null,
        .sel_end = null,
        .sel_color = null,
        .kerning = null,
        .kern_in = null,
    });
}

/// Ingest command buffers (headers + payload) produced by the JS encoder.
/// headers_len must be count * 40 bytes (see command schema), payload can be zero-length.
pub export fn dvui_core_commit(
    handle: *FfiHandle,
    headers_ptr: [*]const u8,
    headers_len: usize,
    payload_ptr: [*]const u8,
    payload_len: usize,
    count: u32,
) bool {
    const header_size: usize = 40;
    if (headers_len < header_size * @as(usize, @intCast(count))) return false;

    const headers = headers_ptr[0..headers_len];
    const payload = payload_ptr[0..payload_len];
    var i: usize = 0;
    while (i < count) : (i += 1) {
        const base = i * header_size;
        const hdr = readHeader(headers[base .. base + header_size]);

        switch (hdr.opcode) {
            1 => renderQuad(handle.window, hdr) catch return false,
            2 => {
                const off = @as(usize, hdr.payload_off);
                const len = @as(usize, hdr.payload_len);
                if (off + len > payload.len) return false;
                const slice = payload[off .. off + len];
                renderText(handle.window, hdr, slice) catch return false;
            },
            else => {},
        }
    }
    return true;
}

