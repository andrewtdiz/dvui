const std = @import("std");

const dvui = @import("dvui");
const FontId = dvui.Font.FontId;
var layout_flex_content_justify = dvui.FlexBoxWidget.ContentPosition.start;
var layout_flex_align_items = dvui.FlexBoxWidget.AlignItems.start;
const RaylibBackend = @import("raylib-backend");
const ray = RaylibBackend.c;

const jsruntime = @import("jsruntime/mod.zig");
const react = @import("jsruntime/react/mod.zig");

const js_console_log = std.log.scoped(.quickjs_console);

const js_entry_script = "examples/resources/js/main.js";
const theme_font_size_delta: f32 = 8.0;

var layout_flex_direction: dvui.enums.Direction = .horizontal;
var layout_flex_align_content: dvui.FlexBoxWidget.AlignContent = .start;

var last_frame_time: i128 = 0;
var frame_count: u64 = 0;
var fps: f64 = 0.0;

const SelectionDragPart = enum {
    move,
    resize_top_left,
    resize_top,
    resize_top_right,
    resize_right,
    resize_bottom_right,
    resize_bottom,
    resize_bottom_left,
    resize_left,

    fn cursor(self: SelectionDragPart) dvui.enums.Cursor {
        return switch (self) {
            .move => .arrow_all,
            .resize_top_left, .resize_bottom_right => .arrow_nw_se,
            .resize_top_right, .resize_bottom_left => .arrow_ne_sw,
            .resize_top, .resize_bottom => .arrow_n_s,
            .resize_left, .resize_right => .arrow_w_e,
        };
    }
};

var use_proportional_scaling = true;
var centered_scaling_enabled = false;
var fixed_increment_scaling_enabled = false;
const fixed_increment_step: f32 = 50;

var selection_rect = dvui.Rect{
    .x = 160,
    .y = 120,
    .w = 280,
    .h = 200,
};
var selection_rotation: f32 = 0.0;
const default_selection_border_color = dvui.Color{ .r = 0x20, .g = 0x9b, .b = 0xff, .a = 0xff };
var selection_border_color = default_selection_border_color;

var selection_drag_part: ?SelectionDragPart = null;
var selection_drag_origin_rect = dvui.Rect{
    .x = 160,
    .y = 120,
    .w = 280,
    .h = 200,
};
var selection_drag_origin_anchor = dvui.Point{ .x = 0, .y = 0 };
var selection_drag_offset = dvui.Point.Physical{ .x = 0, .y = 0 };
const selection_handle_visual: f32 = 10;
const selection_edge_handle_thickness: f32 = 16;
const selection_rotate_visual: f32 = 14;
const selection_rotate_gap: f32 = 24;
const selection_outer_hit_thickness: f32 = 12;
const selection_outer_hit_id_base: usize = 100;
const selection_outer_handle_visual_offset: f32 = 18;
var debug_show_hitboxes = false;
const scale_increment_step: f32 = 50.0;
const rotation_increment_step: f32 = std.math.pi / 8.0;

var selected = false;

fn toggleProportional() void {
    use_proportional_scaling = !use_proportional_scaling;
}

fn toggleCentered() void {
    centered_scaling_enabled = !centered_scaling_enabled;
}

fn toggleFixedIncrements() void {
    fixed_increment_scaling_enabled = !fixed_increment_scaling_enabled;
}

comptime {
    std.debug.assert(@hasDecl(RaylibBackend, "RaylibBackend"));
}

const window_icon_png = @embedFile("zig-favicon.png");

var js_runtime: jsruntime.JSRuntime = undefined;
var js_mouse_snapshot: jsruntime.MouseSnapshot = .{ .x = 0, .y = 0 };
var js_mouse_initialized = false;

pub fn main() !void {
    if (@import("builtin").os.tag == .windows) { // optional
        try dvui.Backend.Common.windowsAttachConsole();
    }
    RaylibBackend.enableRaylibLogging();
    var gpa_instance = std.heap.GeneralPurposeAllocator(.{}){};
    const gpa = gpa_instance.allocator();

    defer _ = gpa_instance.deinit();

    // create OS window directly with raylib
    ray.SetConfigFlags(ray.FLAG_WINDOW_RESIZABLE);
    ray.SetConfigFlags(ray.FLAG_VSYNC_HINT);
    ray.SetConfigFlags(ray.FLAG_MSAA_4X_HINT);
    ray.InitWindow(800, 600, "DVUI Raylib Ontop Example");
    defer ray.CloseWindow();

    var backend = RaylibBackend.init(gpa);
    defer backend.deinit();
    backend.log_events = true;

    var win = try dvui.Window.init(@src(), gpa, backend.backend(), .{});
    win.theme = dvui.Theme.builtin.shadcn;
    defer win.deinit();
    applySegoeFonts(&win);

    js_runtime = try jsruntime.JSRuntime.init(js_entry_script);
    jsruntime.setGlobalRuntime(&js_runtime);
    jsruntime.setConsoleSink(.{ .context = null, .send = jsConsoleSink });
    errdefer {
        jsruntime.clearConsoleSink();
        jsruntime.clearGlobalRuntime();
        js_runtime.deinit();
        jsruntime.shutdownHotReload();
    }
    defer {
        jsruntime.clearConsoleSink();
        jsruntime.clearGlobalRuntime();
        js_runtime.deinit();
        jsruntime.shutdownHotReload();
    }

    while (!ray.WindowShouldClose()) {
        ray.BeginDrawing();

        var pending_reload_runtime: ?jsruntime.JSRuntime = null;
        if (jsruntime.takeHotReloadRequest()) {
            const script_path = jsruntime.hotReloadScriptPath() orelse js_entry_script;
            pending_reload_runtime = jsruntime.JSRuntime.init(script_path) catch |err| {
                std.log.err("JavaScript reload failed: {s}", .{@errorName(err)});
                ray.EndDrawing();
                continue;
            };
        }
        if (pending_reload_runtime) |reloaded_runtime| {
            js_runtime.deinit();
            js_runtime = reloaded_runtime;
            jsruntime.setGlobalRuntime(&js_runtime);
            restoreJsRuntimeState();
            std.log.info("JavaScript runtime hot reloaded", .{});
        }

        var frame_dt: f32 = 0;
        const current_time = std.time.nanoTimestamp();
        if (last_frame_time != 0) {
            const elapsed_ns = current_time - last_frame_time;
            if (elapsed_ns > 0) {
                const dt_seconds = @as(f64, @floatFromInt(elapsed_ns)) / 1_000_000_000.0;
                if (dt_seconds > 0) {
                    fps = 1.0 / dt_seconds;
                    frame_dt = @floatCast(dt_seconds);
                }
            }
        }
        last_frame_time = current_time;
        frame_count += 1;

        const frame_data = jsruntime.FrameData{
            .position = selection_rotation,
            .dt = frame_dt,
        };

        if (js_runtime.runFrame(frame_data)) |result| {
            selection_rotation = result.new_position;
        } else |err| {
            std.log.err("JavaScript runFrame error: {s}", .{@errorName(err)});
        }

        try win.begin(std.time.nanoTimestamp());

        _ = try backend.addAllEvents(&win);
        forwardJsRuntimeEvents();

        if (backend.shouldBlockRaylibInput()) {
            ray.GuiLock();
        } else {
            ray.GuiUnlock();
        }
        ray.ClearBackground(RaylibBackend.dvuiColorToRaylib(dvui.Color.black));

        react.render(&js_runtime);

        _ = try win.end(.{});

        if (win.cursorRequestedFloating()) |cursor| {
            backend.setCursor(cursor);
        } else {
            backend.setCursor(win.cursorRequested());
        }

        ray.EndDrawing();
    }
}

fn forwardJsRuntimeEvents() void {
    for (dvui.events()) |*evt| {
        switch (evt.evt) {
            .mouse => |mouse_event| handleJsMouseEvent(mouse_event),
            .key => |key_event| emitJsKeyEvent(key_event),
            else => {},
        }
    }
}

fn handleJsMouseEvent(mouse: dvui.Event.Mouse) void {
    switch (mouse.action) {
        .press => emitJsMouseEvent(.down, mouse),
        .release => emitJsMouseEvent(.up, mouse),
        .position => syncJsMousePosition(mouse.p),
        else => {},
    }
}

fn emitJsMouseEvent(kind: jsruntime.MouseEventKind, mouse: dvui.Event.Mouse) void {
    const button = mapMouseButton(mouse.button) orelse return;
    const natural = mouse.p.toNatural();
    const event = jsruntime.MouseEvent{
        .kind = kind,
        .button = button,
        .x = roundToI32(natural.x),
        .y = roundToI32(natural.y),
    };
    js_runtime.emitMouseEvent(event) catch |err| {
        std.log.err("JavaScript mouse event failed: {s}", .{@errorName(err)});
    };
}

fn emitJsKeyEvent(key: dvui.Event.Key) void {
    const code = mapKeyCode(key.code) orelse return;
    const kind: jsruntime.KeyEventKind = switch (key.action) {
        .down, .repeat => .down,
        .up => .up,
    };
    const event = jsruntime.KeyEvent{
        .kind = kind,
        .code = code,
        .repeat = key.action == .repeat,
    };
    js_runtime.emitKeyEvent(event) catch |err| {
        std.log.err("JavaScript key event failed: {s}", .{@errorName(err)});
    };
}

fn syncJsMousePosition(point: dvui.Point.Physical) void {
    const natural = point.toNatural();
    const snapshot = jsruntime.MouseSnapshot{
        .x = roundToI32(natural.x),
        .y = roundToI32(natural.y),
    };
    js_mouse_snapshot = snapshot;
    js_mouse_initialized = true;
    js_runtime.updateMouse(snapshot) catch |err| {
        std.log.err("JavaScript mouse sync failed: {s}", .{@errorName(err)});
    };
}

fn restoreJsRuntimeState() void {
    if (!js_mouse_initialized) return;
    js_runtime.updateMouse(js_mouse_snapshot) catch |err| {
        std.log.err("JavaScript mouse restore failed: {s}", .{@errorName(err)});
    };
}

fn mapMouseButton(button: dvui.enums.Button) ?jsruntime.MouseButton {
    return switch (button) {
        .left => .left,
        .right => .right,
        else => null,
    };
}

fn mapKeyCode(code: dvui.enums.Key) ?jsruntime.KeyCode {
    return switch (code) {
        .g => .g,
        .r => .r,
        .s => .s,
        else => null,
    };
}

fn roundToI32(value: f32) i32 {
    return @intFromFloat(std.math.round(value));
}

fn jsConsoleSink(_: ?*anyopaque, level: []const u8, message: []const u8) void {
    js_console_log.info("{s}: {s}", .{ level, message });
}

fn applySegoeFonts(win: *dvui.Window) void {
    win.theme = win.theme.fontSizeAdd(theme_font_size_delta);
    win.theme.font_body = win.theme.font_body.switchFont(FontId.SegoeUI);
    win.theme.font_heading = win.theme.font_heading.switchFont(FontId.SegoeUIBd);
    win.theme.font_caption = win.theme.font_caption.switchFont(FontId.SegoeUILt);
    win.theme.font_caption_heading = win.theme.font_caption_heading.switchFont(FontId.SegoeUIIl);
    win.theme.font_title = win.theme.font_title.switchFont(FontId.SegoeUIBd);
    win.theme.font_title_1 = win.theme.font_title_1.switchFont(FontId.SegoeUIBd);
    win.theme.font_title_2 = win.theme.font_title_2.switchFont(FontId.SegoeUIBd);
    win.theme.font_title_3 = win.theme.font_title_3.switchFont(FontId.SegoeUIBd);
    win.theme.font_title_4 = win.theme.font_title_4.switchFont(FontId.SegoeUIBd);
}
