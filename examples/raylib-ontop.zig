const std = @import("std");

const dvui = @import("dvui");
var layout_flex_content_justify = dvui.FlexBoxWidget.ContentPosition.start;
var layout_flex_align_items = dvui.FlexBoxWidget.AlignItems.start;
const RaylibBackend = @import("raylib-backend");
const jsruntime = @import("jsruntime/mod.zig");
const js_console_log = std.log.scoped(.quickjs_console);

const js_entry_script = "examples/resources/js/main.js";

const ray = RaylibBackend.c;

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

fn toggleProportional() void {
    use_proportional_scaling = !use_proportional_scaling;
    logScalingState("Proportional", use_proportional_scaling);
}

fn toggleCentered() void {
    centered_scaling_enabled = !centered_scaling_enabled;
    logScalingState("Centered", centered_scaling_enabled);
}

fn toggleFixedIncrements() void {
    fixed_increment_scaling_enabled = !fixed_increment_scaling_enabled;
    logScalingState("Fixed Increments", fixed_increment_scaling_enabled);
}

fn logScalingState(name: []const u8, enabled: bool) void {
    std.debug.print("{s} scaling {s}\n", .{ name, if (enabled) "enabled" else "disabled" });
}

comptime {
    std.debug.assert(@hasDecl(RaylibBackend, "RaylibBackend"));
}

const window_icon_png = @embedFile("zig-favicon.png");

//TODO:
//Figure out the best way to integrate raylib and dvui Event Handling

var js_runtime: jsruntime.JSRuntime = undefined;
var js_mouse_snapshot: jsruntime.MouseSnapshot = .{ .x = 0, .y = 0 };
var js_mouse_initialized = false;

pub fn main() !void {
    if (@import("builtin").os.tag == .windows) { // optional
        // on windows graphical apps have no console, so output goes to nowhere - attach it manually. related: https://github.com/ziglang/zig/issues/4196
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

    // init Raylib backend
    // init() means the app owns the window (and must call CloseWindow itself)
    var backend = RaylibBackend.init(gpa);
    defer backend.deinit();
    backend.log_events = true;

    // init dvui Window (maps onto a single OS window)
    // OS window is managed by raylib, not dvui
    var win = try dvui.Window.init(@src(), gpa, backend.backend(), .{});
    defer win.deinit();

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
            updateSelectionBorderColorFromJs();
        } else |err| {
            std.log.err("JavaScript runFrame error: {s}", .{@errorName(err)});
        }

        // marks the beginning of a frame for dvui, can call dvui functions after this
        try win.begin(std.time.nanoTimestamp());

        // send all Raylib events to dvui for processing
        _ = try backend.addAllEvents(&win);
        forwardJsRuntimeEvents();
        updateSelectionBorderColorFromJs();

        if (backend.shouldBlockRaylibInput()) {
            // NOTE: I am using raygui here because it has a simple lock-unlock system
            // Non-raygui raylib apps could also easily implement such a system
            ray.GuiLock();
        } else {
            ray.GuiUnlock();
        }
        // if dvui widgets might not cover the whole window, then need to clear
        // the previous frame's render
        ray.ClearBackground(RaylibBackend.dvuiColorToRaylib(dvui.Color.black));

        dvuiStuff();

        // marks end of dvui frame, don't call dvui functions after this
        // - sends all dvui stuff to backend for rendering, must be called before EndDrawing()
        _ = try win.end(.{});

        // cursor management
        if (win.cursorRequestedFloating()) |cursor| {
            // cursor is over floating window, dvui sets it
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

fn updateSelectionBorderColorFromJs() void {
    if (js_runtime.takeSelectionColor()) |color| {
        selection_border_color = colorFromPacked(color);
    }
}

fn colorFromPacked(value: u32) dvui.Color {
    const r: u8 = @intCast((value >> 24) & 0xff);
    const g: u8 = @intCast((value >> 16) & 0xff);
    const b: u8 = @intCast((value >> 8) & 0xff);
    const a: u8 = @intCast(value & 0xff);
    return dvui.Color{ .r = r, .g = g, .b = b, .a = a };
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

fn updateDebugHitboxView() void {
    for (dvui.events()) |*e| {
        switch (e.evt) {
            .key => |ke| {
                if (ke.action == .down) {
                    switch (ke.code) {
                        .f6 => {
                            debug_show_hitboxes = !debug_show_hitboxes;
                        },
                        .left_shift => toggleProportional(),
                        .left_control => toggleCentered(),
                        .left_alt => toggleFixedIncrements(),
                        else => {},
                    }
                    continue;
                }
                if (ke.action == .up) {
                    switch (ke.code) {
                        .left_shift => toggleProportional(),
                        .left_control => toggleCentered(),
                        .left_alt => toggleFixedIncrements(),
                        else => {},
                    }
                    continue;
                }
            },
            .mouse => |me| {
                if (me.action == .press and me.button.pointer()) {
                    const click_nat = dvui.Point.cast(me.p.toNatural());
                    const in_selection = selection_state.rect.contains(click_nat);
                    if (in_selection) {
                        selected = true;
                    } else if (selected) {
                        selected = false;
                    }
                }
            },
            else => {},
        }
    }
}

var hovered = false;
var selected = false;

var selection_state = dvui.SelectionWidget.State{
    .rect = .{
        .x = 160,
        .y = 120,
        .w = 280,
        .h = 200,
    },
};
const selection_min_size = dvui.Size{ .w = 10, .h = 10 };

fn dvuiStuff() void {
    updateDebugHitboxView();

    var overlay = dvui.overlay(@src(), .{
        .expand = .both,
        .name = "SelectionOverlay",
    });
    defer overlay.deinit();

    const modifiers = dvui.SelectionWidget.TransformModifiers{
        .proportional = use_proportional_scaling,
        .centered = centered_scaling_enabled,
        .fixed_increment = fixed_increment_scaling_enabled,
        .scale_increment = scale_increment_step,
        .rotation_increment = rotation_increment_step,
    };

    var selection = dvui.selectionBox(@src(), .{
        .state = &selection_state,
        .min_size = selection_min_size,
        .transform_modifiers = modifiers,
        .color_fill = dvui.Color{ .r = 0x20, .g = 0x9b, .b = 0xff, .a = 0x40 },
        .color_border = dvui.Color{ .r = 0x20, .g = 0x9b, .b = 0xff, .a = 0xff },
    }, .{
        .rect = selection_state.rect,
        .name = "SelectionWidget",
    });
    defer selection.deinit();
    selection.draw();
}
