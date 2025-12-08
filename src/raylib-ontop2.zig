const std = @import("std");

const dvui = @import("dvui");
const FontId = dvui.Font.FontId;
var layout_flex_content_justify = dvui.FlexBoxWidget.ContentPosition.start;
var layout_flex_align_items = dvui.FlexBoxWidget.AlignItems.start;
const RaylibBackend = @import("raylib-backend");
const ray = RaylibBackend.c;

const jsruntime = @import("jsruntime/mod.zig");
const solid = @import("jsruntime/solid/mod.zig");

const js_console_log = std.log.scoped(.quickjs_console);

const js_entry_script = "src/js/main.js";
const theme_font_size_delta: f32 = 8.0;

var layout_flex_direction: dvui.enums.Direction = .horizontal;
var layout_flex_align_content: dvui.FlexBoxWidget.AlignContent = .start;

const raylib_msaa_enabled = true;

var last_frame_time: i128 = 0;
var last_state_push_time: i128 = 0;
var frame_count: u64 = 0;
var fps: f64 = 0.0;
var solid_state_counter: i32 = 0;

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

const msaa_demo_margin = dvui.Rect{
    .x = 24,
    .y = 24,
    .w = 24,
    .h = 24,
};

var gizmo_state = dvui.GizmoWidget.State{
    .rect = dvui.Rect{
        .x = 0,
        .y = 0,
        .w = 100,
        .h = 100,
    },
};

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
    if (raylib_msaa_enabled) {
        ray.SetConfigFlags(ray.FLAG_MSAA_4X_HINT);
    }
    ray.InitWindow(1400, 900, "DVUI Raylib Ontop Example");
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

        const now = current_time;
        const should_push = last_state_push_time == 0 or (now - last_state_push_time) >= std.time.ns_per_s;
        if (should_push) {
            last_state_push_time = now;
            if (solid_state_counter < std.math.maxInt(i32)) {
                solid_state_counter += 1;
            }
            const new_count = solid_state_counter;
            solid.quickjs.updateSolidStateI32(&js_runtime, "zig:count", new_count) catch |err| {
                std.log.err("Solid count update failed: {s}", .{@errorName(err)});
            };

            var message_buffer: [64]u8 = undefined;
            const fallback_message: []const u8 = "Updated from Zig!";
            const message = std.fmt.bufPrint(&message_buffer, "Updated from Zig #{d}", .{new_count}) catch fallback_message;
            solid.quickjs.updateSolidStateString(&js_runtime, "zig:message", message) catch |err| {
                std.log.err("Solid message update failed: {s}", .{@errorName(err)});
            };

            const observed_count = solid.quickjs.readSolidStateI32(&js_runtime, "zig:count") catch |err| blk: {
                std.log.warn("Solid count read failed: {s}", .{@errorName(err)});
                break :blk new_count;
            };
            const observed_message: ?[]u8 = solid.quickjs.readSolidStateString(&js_runtime, gpa, "zig:message") catch |err| blk: {
                std.log.warn("Solid message read failed: {s}", .{@errorName(err)});
                break :blk null;
            };
            defer if (observed_message) |owned| gpa.free(owned);

            if (observed_message) |owned| {
                std.log.info("Solid state observed count={d} message={s}", .{ observed_count, owned });
            } else {
                std.log.info("Solid state observed count={d}", .{observed_count});
            }
        }

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

        dvui.gizmo2d(@src(), .{
            .state = &gizmo_state,
            .min_extent = dvui.Size{
                .w = 100,
                .h = 100,
            },
            .axis_length = 150,
            .axis_thickness = 3,
            .handle_size = 10,
            .colors = dvui.GizmoWidget.Colors{
                .horizontal = dvui.Color.red,
                .vertical = dvui.Color{ .r = 0x00, .g = 0xff, .b = 0x00, .a = 0xff },
                .center = dvui.Color{ .r = 0x00, .g = 0x00, .b = 0x8b, .a = 0xff },
                .highlight_mix = 0.35,
            },
        }, .{});

        // const window_rect = dvui.windowRect();
        // const panel_min_size = dvui.Size{
        //     .w = @max(360, window_rect.w * 0.7),
        //     .h = @max(320, window_rect.h * 0.6),
        // };
        // const canvas_min_size = dvui.Size{
        //     .w = @max(320, panel_min_size.w - 80),
        //     .h = @max(220, panel_min_size.h - 120),
        // };

        // {
        //     var panel = dvui.box(@src(), .{}, .{
        //         .name = "MSAA reference panel",
        //         .margin = msaa_demo_margin,
        //         .padding = dvui.Rect.all(16),
        //         .min_size_content = panel_min_size,
        //         .expand = dvui.Options.Expand.both,
        //         .gravity_x = 0.5,
        //         .gravity_y = 0.5,
        //         .corner_radius = dvui.Rect.all(8),
        //         .background = true,
        //         .border = dvui.Rect.all(1),
        //     });
        //     defer panel.deinit();
        //     dvui.label(@src(), "MSAA reference", .{}, .{ .gravity_x = 0.5 });

        //     var canvas = dvui.box(@src(), .{}, .{
        //         .min_size_content = canvas_min_size,
        //         .expand = dvui.Options.Expand.both,
        //         .gravity_x = 0.5,
        //         .gravity_y = 0.5,
        //     });
        //     defer canvas.deinit();

        //     const rs = canvas.data().contentRectScale();
        //     drawMsaaReferenceShape(rs.r, rs.s);
        // }

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

fn drawMsaaReferenceShape(rect: dvui.Rect.Physical, scale: f32) void {
    if (rect.w <= 0 or rect.h <= 0) return;

    const inset = 12 * scale;
    const draw_rect = dvui.Rect.Physical{
        .x = rect.x + inset,
        .y = rect.y + inset,
        .w = @max(@as(f32, 0), rect.w - inset * 2),
        .h = @max(@as(f32, 0), rect.h - inset * 2),
    };
    if (draw_rect.w <= 0 or draw_rect.h <= 0) return;

    const center = draw_rect.center();
    const spike_count: usize = 8;
    const outer_radius = @min(draw_rect.w, draw_rect.h) * 0.5;
    const inner_radius = outer_radius * 0.45;
    const two_pi = std.math.pi * 2.0;

    var star = dvui.Path.Builder.init(dvui.currentWindow().lifo());
    defer star.deinit();

    var i: usize = 0;
    while (i < spike_count * 2) : (i += 1) {
        const _i_float: f32 = @floatFromInt(i);
        const angle = (two_pi / @as(f32, spike_count * 2)) * _i_float;
        const radius = if ((i & 1) == 0) outer_radius else inner_radius;
        star.addPoint(.{
            .x = center.x + radius * @cos(angle),
            .y = center.y + radius * @sin(angle),
        });
    }

    star.build().stroke(.{
        .thickness = 6.0 * scale,
        .color = dvui.Color{ .r = 0xff, .g = 0xff, .b = 0xff, .a = 0xff },
        .closed = true,
        .endcap_style = .square,
    });

    var circle = dvui.Path.Builder.init(dvui.currentWindow().lifo());
    defer circle.deinit();
    circle.addArc(center, inner_radius * 0.7, std.math.pi * 2.0, 0, false);
    circle.build().stroke(.{
        .thickness = 2.0 * scale,
        .color = dvui.Color{ .r = 0x2b, .g = 0x96, .b = 0xff, .a = 0xff },
        .closed = true,
    });

    var diagonal = dvui.Path.Builder.init(dvui.currentWindow().lifo());
    defer diagonal.deinit();
    diagonal.addPoint(draw_rect.topLeft());
    diagonal.addPoint(draw_rect.bottomRight());
    diagonal.build().stroke(.{
        .thickness = 3.0 * scale,
        .color = dvui.Color{ .r = 0xff, .g = 0x45, .b = 0x64, .a = 0xff },
        .endcap_style = .square,
    });

    var cross = dvui.Path.Builder.init(dvui.currentWindow().lifo());
    defer cross.deinit();
    cross.addPoint(.{ .x = draw_rect.x, .y = draw_rect.y + draw_rect.h });
    cross.addPoint(.{ .x = draw_rect.x + draw_rect.w, .y = draw_rect.y });
    cross.build().stroke(.{
        .thickness = 1.5 * scale,
        .color = dvui.Color{ .r = 0xff, .g = 0xcf, .b = 0x33, .a = 0xff },
        .endcap_style = .square,
    });
}
